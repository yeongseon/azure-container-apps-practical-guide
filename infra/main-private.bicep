// Main Bicep template for Container Apps with VNet Integration and Private Endpoints
targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Container image tag')
param imageTag string = 'latest'

@description('Log Analytics retention in days')
param logAnalyticsRetentionDays int = 30

@description('Minimum replicas')
param minReplicas int = 0

@description('Maximum replicas')
param maxReplicas int = 3

@description('CPU cores')
param cpu string = '0.5'

@description('Memory size')
param memory string = '1Gi'

@description('Enable internal-only ingress (no public access)')
param internalOnly bool = false

// Generate unique suffix
var uniqueSuffix = uniqueString(resourceGroup().id)
var containerRegistryName = replace('cr${baseName}${uniqueSuffix}', '-', '')
var containerAppEnvName = 'cae-${baseName}-${uniqueSuffix}'
var containerAppName = 'ca-${baseName}-${uniqueSuffix}'
var logAnalyticsName = 'log-${baseName}-${uniqueSuffix}'
var appInsightsName = 'appi-${baseName}-${uniqueSuffix}'
var managedIdentityName = 'id-${baseName}-${uniqueSuffix}'

// ============================================================================
// Network Infrastructure
// ============================================================================

module network 'modules/network.bicep' = {
  name: 'network-deployment'
  params: {
    baseName: baseName
    location: location
  }
}

// ============================================================================
// Managed Identity
// ============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

// ============================================================================
// Key Vault with Private Endpoint
// ============================================================================

module keyVault 'modules/keyvault-private.bicep' = {
  name: 'keyvault-deployment'
  params: {
    baseName: baseName
    location: location
    privateEndpointSubnetId: network.outputs.privateEndpointsSubnetId
    vnetId: network.outputs.vnetId
    managedIdentityPrincipalId: managedIdentity.properties.principalId
  }
}

// ============================================================================
// Storage Account with Private Endpoint
// ============================================================================

module storage 'modules/storage-private.bicep' = {
  name: 'storage-deployment'
  params: {
    baseName: baseName
    location: location
    privateEndpointSubnetId: network.outputs.privateEndpointsSubnetId
    vnetId: network.outputs.vnetId
    managedIdentityPrincipalId: managedIdentity.properties.principalId
  }
}

// ============================================================================
// Logging & Monitoring
// ============================================================================

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ============================================================================
// Container Registry
// ============================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

// ============================================================================
// Container Apps Environment (VNet-Integrated)
// ============================================================================

resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: network.outputs.containerAppsSubnetId
      internal: internalOnly
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    daprAIConnectionString: appInsights.properties.ConnectionString
  }
}

// ============================================================================
// Container App
// ============================================================================

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'appinsights-connection-string'
          value: appInsights.properties.ConnectionString
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'app'
          image: '${containerRegistry.properties.loginServer}/${baseName}:${imageTag}'
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
            {
              name: 'TELEMETRY_MODE'
              value: 'advanced'
            }
            {
              name: 'LOG_LEVEL'
              value: 'INFO'
            }
            {
              name: 'CONTAINER_APP_NAME'
              value: containerAppName
            }
            {
              name: 'CONTAINER_APP_REVISION'
              value: 'initial'
            }
            // Private Endpoint test environment variables
            {
              name: 'KEY_VAULT_URL'
              value: keyVault.outputs.keyVaultUri
            }
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storage.outputs.storageAccountName
            }
            {
              name: 'STORAGE_BLOB_ENDPOINT'
              value: storage.outputs.blobEndpoint
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: managedIdentity.properties.clientId
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

// Network
output vnetId string = network.outputs.vnetId
output vnetName string = network.outputs.vnetName
output containerAppsSubnetId string = network.outputs.containerAppsSubnetId
output privateEndpointsSubnetId string = network.outputs.privateEndpointsSubnetId

// Container Registry
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

// Container Apps
output containerAppEnvName string = containerAppEnv.name
output containerAppName string = containerApp.name
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'

// Monitoring
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceName string = logAnalytics.name

// Private Endpoint Resources
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output storageAccountName string = storage.outputs.storageAccountName
output storageBlobEndpoint string = storage.outputs.blobEndpoint

// Identity
output managedIdentityClientId string = managedIdentity.properties.clientId
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
