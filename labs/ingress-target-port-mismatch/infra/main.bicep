targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Public placeholder image. helloworld is sufficient because this lab does not measure app behavior; it measures whether an ingress targetPort vs. container listening port mismatch produces the documented failure signature (HTTP 503 at the edge + TargetPort row in ContainerAppSystemLogs_CL). The image is identical across the baseline, trigger, and post-fix windows; the only experimental variable is the ingress targetPort field.')
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

// The Container App is provisioned in the documented healthy baseline:
// ingress.external=true, ingress.targetPort=80, transport=auto, and the helloworld
// image listens on :80. trigger.sh later flips targetPort to 8081 to reproduce the
// mismatch; verify.sh flips it back to 80 to confirm recovery on the same revision.
// activeRevisionsMode: 'Single' so the only revision is the one being modified.
// minReplicas=1, maxReplicas=1 so the platform reliably emits RevisionReady and
// probe-failure events without a scale-to-zero confounder.
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
        transport: 'auto'
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
