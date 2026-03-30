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

// Generate unique suffix
var uniqueSuffix = uniqueString(resourceGroup().id)
var containerRegistryName = replace('cr${baseName}${uniqueSuffix}', '-', '')
var containerAppEnvName = 'cae-${baseName}-${uniqueSuffix}'
var containerAppName = 'ca-${baseName}-${uniqueSuffix}'
var logAnalyticsName = 'log-${baseName}-${uniqueSuffix}'
var appInsightsName = 'appi-${baseName}-${uniqueSuffix}'

// Log Analytics Workspace
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

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Container Registry
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

// Container Apps Environment
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
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

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
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

// Outputs
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerAppEnvName string = containerAppEnv.name
output containerAppName string = containerApp.name
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceName string = logAnalytics.name
