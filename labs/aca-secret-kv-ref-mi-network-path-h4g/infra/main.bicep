targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// aca-secret-kv-ref-mi-network-path-h4g — infrastructure
// -----------------------------------------------------------------------------
//
// Reproduces the H4g variant for the customer failure:
//   az containerapp secret set --secrets <name>=keyvaultref:https://<kv>.vault.azure.net/secrets/<name>,identityref:system
//     -> Failed to update secrets
//     -> Unable to get value using Managed identity
//     -> OpenID Connect / openid-configuration failure with a TLS / certificate clue
//
// H4g deliberately keeps the same app / KV / identity / RBAC / ingress / revision
// cohort as H4c, but swaps the network mechanism:
//   - Azure Firewall Premium is PRESENT
//   - Firewall Policy Premium is PRESENT
//   - TLS inspection is CONFIGURED with an intermediate CA secret from Key Vault
//   - A route table sends 0.0.0.0/0 from the ACA subnet to the firewall private IP
//   - There is NO NSG deny trigger, NO custom DNS override, and NO Virtual WAN routing intent
//
// The ONLY controlled variable is the Entra-authority application rule's
// terminateTLS flag:
//   H0 baseline: terminateTLS = false -> secret set succeeds
//   H1 trigger:  terminateTLS = true  -> secret set fails
//   H2 fix:      terminateTLS = false -> secret set succeeds again

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

@description('AzureFirewallSubnet prefix (Premium SKU requires AzureFirewallSubnet; /26 or larger recommended)')
param firewallSubnetPrefix string = '10.90.2.0/26'

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

@secure()
@description('Key Vault secret ID for the password-less PFX intermediate CA used by Azure Firewall Premium TLS inspection. Example: https://<vault>.vault.azure.net/secrets/<secret-name>/<version>.')
param tlsInspectionCaKeyVaultSecretId string

@description('Display name for the Firewall Policy TLS-inspection CA reference.')
param tlsInspectionCaCertificateName string = 'lab-h4g-intermediate-ca'

@description('Resource ID of a PRE-CREATED user-assigned managed identity that already has Get/List access to the CA certificate Key Vault. Example: /subscriptions/<subscription-id>/resourceGroups/<identity-rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<identity-name>.')
param tlsInspectionIdentityResourceId string

@description('Whether the Entra-authority application rule should terminate TLS. H0/H2 = false, H1 = true.')
param entraAuthorityTerminateTls bool = false

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var appName = 'ca-${baseName}-${suffix}'
var vnetName = 'vnet-${baseName}-${suffix}'
var acaSubnetName = 'snet-aca'
var firewallSubnetName = 'AzureFirewallSubnet'
var nsgName = 'nsg-${baseName}-${suffix}'
var firewallName = 'afw-${baseName}-${suffix}'
var firewallPublicIpName = 'pip-${firewallName}'
var firewallPolicyName = 'afwp-${baseName}-${suffix}'
var firewallRuleCollectionGroupName = 'aca-secret-kv-ref-mi-network-path-h4g'
var entraAuthorityRuleCollectionName = 'allow-entra-authority-h4g'
var entraAuthorityRuleName = 'allow-entra-login-h4g'
var routeTableName = 'rt-${baseName}-${suffix}'
var defaultRouteName = 'default-via-afw-h4g'
var keyVaultName = take('kv${baseName}${suffix}', 24)
var keyVaultDataPlaneFqdn = '${keyVaultName}.vault.azure.net'
var tenantId = subscription().tenantId

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

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  properties: {}
}

resource routeTable 'Microsoft.Network/routeTables@2024-01-01' = {
  name: routeTableName
  location: location
  properties: {
    disableBgpRoutePropagation: true
  }
}

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
          networkSecurityGroup: {
            id: nsg.id
          }
          routeTable: {
            id: routeTable.id
          }
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
      {
        name: firewallSubnetName
        properties: {
          addressPrefix: firewallSubnetPrefix
        }
      }
    ]
  }
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: acaSubnetName
  parent: vnet
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: firewallSubnetName
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
    tenantId: tenantId
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

resource firewallTlsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  scope: resourceGroup(split(tlsInspectionIdentityResourceId, '/')[2], split(tlsInspectionIdentityResourceId, '/')[4])
  name: split(tlsInspectionIdentityResourceId, '/')[8]
}

// NOTE: Azure Firewall Premium TLS inspection requires a password-less PFX
// intermediate CA certificate stored as a Key Vault secret (or certificate-backed
// secret) and a managed identity that can read that secret. This lab does NOT
// embed any real certificate. The reader must PRE-CREATE the user-assigned
// identity, grant it Get/List permissions on the CA vault, and then pass both
// tlsInspectionIdentityResourceId and tlsInspectionCaKeyVaultSecretId.
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: firewallPublicIpName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-01-01' = {
  name: firewallPolicyName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${firewallTlsIdentity.id}': {}
    }
  }
  properties: {
    sku: {
      tier: 'Premium'
    }
    threatIntelMode: 'Alert'
    transportSecurity: {
      certificateAuthority: {
        keyVaultSecretId: tlsInspectionCaKeyVaultSecretId
        name: tlsInspectionCaCertificateName
      }
    }
  }
}

resource firewallRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = {
  name: firewallRuleCollectionGroupName
  parent: firewallPolicy
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-platform-dependencies-h4g'
        priority: 210
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-mcr-h4g'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [
              acaSubnetPrefix
            ]
            targetFqdns: [
              'mcr.microsoft.com'
              '*.data.mcr.microsoft.com'
            ]
            terminateTLS: false
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-acs-mirror-h4g'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [
              acaSubnetPrefix
            ]
            targetFqdns: [
              'acs-mirror.azureedge.net'
              'packages.aks.azure.com'
            ]
            terminateTLS: false
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-kv-data-plane-h4g'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [
              acaSubnetPrefix
            ]
            targetFqdns: [
              keyVaultDataPlaneFqdn
            ]
            terminateTLS: false
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: entraAuthorityRuleCollectionName
        priority: 220
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: entraAuthorityRuleName
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [
              acaSubnetPrefix
            ]
            targetFqdns: [
              'login.microsoftonline.com'
              'login.microsoft.com'
            ]
            terminateTLS: entraAuthorityTerminateTls
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-01-01' = {
  name: firewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Premium'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'fwIpConfig'
        properties: {
          subnet: {
            id: firewallSubnet.id
          }
          publicIPAddress: {
            id: firewallPublicIp.id
          }
        }
      }
    ]
  }
  dependsOn: [
    firewallRuleCollectionGroup
  ]
}

resource defaultRoute 'Microsoft.Network/routeTables/routes@2024-01-01' = {
  name: defaultRouteName
  parent: routeTable
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
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
output tenantId string = tenantId
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
output tlsInspectionIdentityResourceId string = tlsInspectionIdentityResourceId
output nsgAttached bool = true
output nsgName string = nsgName
output routeTableAttached bool = true
output routeTableName string = routeTableName
output routeTableDefaultRouteName string = defaultRouteName
output routeTableDefaultNextHopType string = 'VirtualAppliance'
output azureFirewallPresent bool = true
output azureFirewallName string = firewallName
output azureFirewallSku string = 'Premium'
output azureFirewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallPolicyPresent bool = true
output firewallPolicyName string = firewallPolicyName
output firewallPolicySku string = 'Premium'
output firewallRuleCollectionGroupName string = firewallRuleCollectionGroupName
output entraAuthorityRuleCollectionName string = entraAuthorityRuleCollectionName
output entraAuthorityRuleName string = entraAuthorityRuleName
output entraAuthorityTerminateTls bool = entraAuthorityTerminateTls
output tlsInspectionConfigured bool = true
output tlsInspectionCaCertificateName string = tlsInspectionCaCertificateName
output usesAzureProvidedDns bool = true
output nsgDenyPresent bool = false
output dnsOverridePresent bool = false
output vwanRoutingIntentPresent bool = false
