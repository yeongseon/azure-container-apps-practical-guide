targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Public placeholder image. helloworld is sufficient because this lab does not measure app behavior; it measures whether the Container Apps environment routes platform/console logs to Log Analytics at all. The image is identical across the baseline and post-fix runs; the only variable is whether the environment has appLogsConfiguration populated.')
param placeholderImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var appName = 'ca-${baseName}-${suffix}'

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

// Environment is intentionally provisioned WITHOUT appLogsConfiguration. This is the
// experimental "before" state: no destination is set, so neither ContainerAppConsoleLogs_CL
// nor ContainerAppSystemLogs_CL receive data from this environment. verify.sh later applies
// the fix via `az containerapp env update --logs-destination log-analytics ...`.
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: environmentName
  location: location
  properties: {}
}

resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
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

output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
output environmentName string = environment.name
output environmentResourceId string = environment.id
output containerAppName string = app.name
output containerAppFqdn string = app.properties.configuration.ingress.fqdn
