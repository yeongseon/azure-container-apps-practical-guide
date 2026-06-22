targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Public placeholder image. The lab never switches off this image — every revision created by trigger.sh keeps the same image and only changes the REV env var, so the only experimental variable is the inactive-revision retention limit.')
param placeholderImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Inactive-revision retention limit. Intentionally low (2) so trigger.sh can demonstrate the configured target after just a few env-var updates. Note: the Bicep schema names this `maxInactiveRevisions` at API version 2023-05-01; the Azure CLI exposes the same value via the preview flag `--max-inactive-revisions` (alias: `--revision-history-limit`). This lab sets the value in Bicep only and never mutates it from the CLI.')
@minValue(0)
@maxValue(100)
param initialMaxInactiveRevisions int = 2

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
      activeRevisionsMode: 'Single'
      maxInactiveRevisions: initialMaxInactiveRevisions
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
        minReplicas: 0
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
