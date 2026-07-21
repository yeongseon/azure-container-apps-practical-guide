targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// aca-secret-kv-ref-mi-network-path-h4e — infrastructure
// -----------------------------------------------------------------------------
//
// Reproduces the H4e variant for the customer failure:
//   az containerapp secret set --identity system --key-vault-url https://<kv>.vault.azure.net/secrets/<name>
//     -> Failed to update secrets
//     -> Unable to get value using Managed identity
//     -> Get https://login.microsoftonline.com/<tenant>/.well-known/openid-configuration EOF
//
// H4e deliberately removes Azure Firewall, UDR, and custom VNet DNS servers.
// The ONLY controlled variable is a custom Private DNS override for the Entra
// authority hosts:
//   - login.microsoftonline.com
//   - login.microsoft.com
//
// Phase behavior:
//   H0 baseline: No override -> secret set succeeds.
//   H1 trigger:  Custom Private DNS zones linked to the ACA VNet, apex A record
//                for each authority -> 192.0.2.1 -> secret set fails.
//   H2 fix:      Override removed, wait past TTL -> secret set succeeds again.
//
// The topology therefore proves "NOT H4a": there is no Azure Firewall and no
// UDR at all, while H0 and H2 both succeed with the same Key Vault, identity,
// and RBAC state.

@description('Base name for all resources (lowercase letters and digits only, 3-11 chars). KV name = "kv<baseName><6-char-suffix>", max 24 chars total.')
@minLength(3)
@maxLength(11)
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('VNet address space for the lab')
param vnetAddressPrefix string = '10.90.0.0/16'

@description('Container Apps workload-profile subnet prefix (must be at least /23)')
param acaSubnetPrefix string = '10.90.0.0/23'

@description('Public MCR image used as the lab workload — no ACR is needed for this lab because the network path being tested is KV secret-reference validation, not image pull.')
param placeholderImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Object ID (principalId) of the identity running the deployment. Required so the deployment can grant itself Key Vault Secrets Officer at the KV scope, which is needed by trigger.sh / falsify.sh to write the KV secret values that the app then references.')
param deploymentPrincipalId string

@description('Principal type of deploymentPrincipalId. Use "User" for an interactive az login, "ServicePrincipal" for CI/CD.')
@allowed([
  'User'
  'ServicePrincipal'
])
param deploymentPrincipalType string = 'User'

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var appName = 'ca-${baseName}-${suffix}'
var vnetName = 'vnet-${baseName}-${suffix}'
var acaSubnetName = 'snet-aca'
var keyVaultName = take('kv${baseName}${suffix}', 24)
var keyVaultDataPlaneFqdn = '${keyVaultName}.vault.azure.net'

var kvSecretsUserRoleId = '4633458b-17de-4321-be99-e39f9d67d7dd'
var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// No custom VNet DNS servers. Azure-provided DNS stays in place so linked
// Private DNS zones become the only H1/H2 variable.
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: acaSubnetName
        properties: {
          addressPrefix: acaSubnetPrefix
          delegations: [
            {
              name: 'aca-env-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: acaSubnetName
  parent: vnet
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: null
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      internal: false
      infrastructureSubnetId: acaSubnet.id
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'app'
          image: placeholderImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

resource kvSecretsUserForApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, app.id, kvSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleId)
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource kvSecretsOfficerForDeployer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, deploymentPrincipalId, kvSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsOfficerRoleId)
    principalId: deploymentPrincipalId
    principalType: deploymentPrincipalType
  }
}

output resourceGroupName string = resourceGroup().name
output location string = location
output appName string = appName
output environmentName string = environmentName
output vnetName string = vnetName
output acaSubnetName string = acaSubnetName
output acaSubnetPrefix string = acaSubnetPrefix
output logAnalyticsName string = logAnalyticsName
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
output keyVaultName string = keyVaultName
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultDataPlaneFqdn string = keyVaultDataPlaneFqdn
output appPrincipalId string = app.identity.principalId
output usesAzureProvidedDns bool = true
output routeTableAttached bool = false
output azureFirewallPresent bool = false
