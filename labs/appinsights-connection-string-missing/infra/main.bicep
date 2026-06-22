targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Initial placeholder image (public MCR helloworld). The lab scripts later switch this to the freshly-built ACR image that uses the Application Insights SDK.')
param placeholderImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var appInsightsName = 'appi-${baseName}-${suffix}'
var acrName = 'acr${baseName}${suffix}'
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

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  // Workspace-based App Insights so telemetry lands in the same Log Analytics workspace used by ContainerAppSystemLogs.
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  // Admin user disabled — the Container App pulls via system-assigned managed identity with AcrPull role assignment.
  properties: {
    adminUserEnabled: false
  }
}

resource environment 'Microsoft.App/managedEnvironments@2023-05-01' = {
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
  }
}

resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  // System-assigned identity is required for the AcrPull role assignment below so the Container App can pull from the lab's ACR without admin credentials.
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
      }
      registries: [
        {
          server: '${acr.name}.azurecr.io'
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'app'
          // Initial image is the public MCR helloworld so the Bicep deployment finishes without depending on the ACR image existing yet.
          // trigger.sh later switches this to the freshly-built ACR image (ca-appiconn-<suffix> running app.py with the azure-monitor-opentelemetry SDK).
          image: placeholderImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        // minReplicas: 1 keeps one replica warm so telemetry from `/` requests is consistently emitted while the lab generates curl traffic.
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// AcrPull (built-in role 7f951dda-4ed3-4680-a7ca-43fe172d538d) so the Container App's system identity can pull ACR images once trigger.sh switches to the custom image.
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, app.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output environmentName string = environment.name
output containerAppName string = app.name
output containerAppFqdn string = app.properties.configuration.ingress.fqdn
