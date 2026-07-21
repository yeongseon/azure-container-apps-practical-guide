targetScope = 'resourceGroup'

// aca-secret-kv-ref-mi-network-path-h4d — infrastructure
// Workload plane is always deployed. Virtual WAN secured-hub resources deploy
// only when deployVirtualWan=true so a naive run does not incur vWAN cost.

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

@description('Deploy the expensive Virtual WAN secured-hub plane in this resource group. Default false so a naive deployment does not incur vWAN cost.')
param deployVirtualWan bool = false

@description('Existing Virtual Hub resource ID for cost-conscious mode. Leave empty when deployVirtualWan=true.')
param existingVirtualHubResourceId string = ''

@description('Existing secured-hub Azure Firewall resource ID for cost-conscious mode. Leave empty when deployVirtualWan=true.')
param existingAzureFirewallResourceId string = ''

@description('Existing Firewall Policy resource ID for cost-conscious mode. Leave empty when deployVirtualWan=true.')
param existingFirewallPolicyResourceId string = ''

@description('Optional existing Firewall diagnostic Log Analytics customer ID (workspace GUID) for best-effort clue capture in existing secured-hub mode.')
param existingFirewallLogAnalyticsCustomerId string = ''

@description('Virtual WAN address prefix used only when deployVirtualWan=true.')
param virtualHubAddressPrefix string = '10.91.0.0/23'

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var appName = 'ca-${baseName}-${suffix}'
var vnetName = 'vnet-${baseName}-${suffix}'
var acaSubnetName = 'snet-aca'
var keyVaultName = take('kv${baseName}${suffix}', 24)
var keyVaultDataPlaneFqdn = '${keyVaultName}.vault.azure.net'

var virtualWanName = 'vwan-${baseName}-${suffix}'
var virtualHubName = 'vhub-${baseName}-${suffix}'
var firewallName = 'afw-${baseName}-${suffix}'
var firewallPolicyName = 'afwp-${baseName}-${suffix}'
var routingIntentName = 'defaultRoutingIntent'
var routeConnectionPrefix = 'conn-${appName}'

var kvSecretsUserRoleId = '4633458b-17de-4321-be99-e39f9d67d7dd'
var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

var existingModeConfigured = length(existingVirtualHubResourceId) > 0 && length(existingAzureFirewallResourceId) > 0 && length(existingFirewallPolicyResourceId) > 0
var virtualWanMode = deployVirtualWan ? 'synthetic-secured-hub' : (existingModeConfigured ? 'existing-secured-hub' : 'workload-only')

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

resource virtualWan 'Microsoft.Network/virtualWans@2024-01-01' = if (deployVirtualWan) {
  name: virtualWanName
  location: location
  properties: {
    type: 'Standard'
    disableVpnEncryption: false
    allowBranchToBranchTraffic: true
    allowVnetToVnetTraffic: true
  }
}

resource virtualHub 'Microsoft.Network/virtualHubs@2024-01-01' = if (deployVirtualWan) {
  name: virtualHubName
  location: location
  properties: {
    addressPrefix: virtualHubAddressPrefix
    virtualWan: {
      id: virtualWan.id
    }
    sku: 'Standard'
  }
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-01-01' = if (deployVirtualWan) {
  name: firewallPolicyName
  location: location
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
  }
}

resource firewallRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = if (deployVirtualWan) {
  name: 'aca-kv-routing-intent'
  parent: firewallPolicy
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-kv-public-only'
        priority: 210
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-key-vault-public'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [
              vnetAddressPrefix
            ]
            targetFqdns: [
              '*.vault.azure.net'
            ]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-01-01' = if (deployVirtualWan) {
  name: firewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_Hub'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    virtualHub: {
      id: virtualHub.id
    }
    hubIPAddresses: {
      publicIPs: {
        count: 1
      }
    }
  }
  dependsOn: [
    firewallRuleCollectionGroup
  ]
}

resource firewallDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployVirtualWan) {
  name: 'diag-to-law'
  scope: firewall
  properties: {
    workspaceId: logAnalytics.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'AzureFirewallApplicationRule'
        enabled: true
      }
      {
        category: 'AzureFirewallNetworkRule'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
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
output vnetResourceId string = vnet.id
output acaSubnetName string = acaSubnetName
output acaSubnetPrefix string = acaSubnetPrefix
output logAnalyticsName string = logAnalyticsName
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
output keyVaultName string = keyVaultName
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultDataPlaneFqdn string = keyVaultDataPlaneFqdn
output appPrincipalId string = app.identity.principalId
output deployVirtualWan bool = deployVirtualWan
output virtualWanMode string = virtualWanMode
output virtualHubResourceId string = deployVirtualWan ? virtualHub.id : existingVirtualHubResourceId
output virtualHubName string = deployVirtualWan ? virtualHub.name : (length(existingVirtualHubResourceId) > 0 ? last(split(existingVirtualHubResourceId, '/')) : '')
output azureFirewallResourceId string = deployVirtualWan ? firewall.id : existingAzureFirewallResourceId
output azureFirewallName string = deployVirtualWan ? firewall.name : (length(existingAzureFirewallResourceId) > 0 ? last(split(existingAzureFirewallResourceId, '/')) : '')
output firewallPolicyResourceId string = deployVirtualWan ? firewallPolicy.id : existingFirewallPolicyResourceId
output firewallPolicyName string = deployVirtualWan ? firewallPolicy.name : (length(existingFirewallPolicyResourceId) > 0 ? last(split(existingFirewallPolicyResourceId, '/')) : '')
output firewallLogAnalyticsCustomerId string = deployVirtualWan ? logAnalytics.properties.customerId : existingFirewallLogAnalyticsCustomerId
output routingIntentName string = routingIntentName
output vhubConnectionNamePrefix string = routeConnectionPrefix
output usesAzureProvidedDns bool = true
output routeTableAttached bool = false
