targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Initial image that intentionally pulls slowly because of its size. The verify step later updates the app to a smaller image.')
param largeImage string = 'python:3.11'

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
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
      }
    }
    template: {
      containers: [
        {
          name: 'app'
          // Large public image - python:3.11 is ~407 MB on disk, demonstrating a slow pull.
          image: largeImage
          // Run python's built-in HTTP server on port 8080 so the readiness probe passes once the image is pulled.
          command: [
            'python'
            '-m'
            'http.server'
            '8080'
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        // minReplicas: 1 keeps one replica warm so the initial cold-pull is observable in Log Analytics.
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output environmentName string = environment.name
output containerAppName string = app.name
output containerAppFqdn string = app.properties.configuration.ingress.fqdn
output largeImage string = largeImage
