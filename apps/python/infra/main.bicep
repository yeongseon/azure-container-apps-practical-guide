targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Container image tag')
param imageTag string = 'latest'

@description('Enable Application Insights')
param enableObservability bool = false

@description('Minimum replicas')
param minReplicas int = 0

@description('Maximum replicas')
param maxReplicas int = 3

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    baseName: baseName
    location: location
    enableObservability: enableObservability
  }
}

module acr 'modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    baseName: baseName
    location: location
  }
}

module env 'modules/container-apps-environment.bicep' = {
  name: 'container-apps-environment'
  params: {
    baseName: baseName
    location: location
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsSharedKey: logAnalytics.outputs.sharedKey
  }
}

module app 'modules/container-app.bicep' = {
  name: 'container-app'
  params: {
    baseName: baseName
    location: location
    environmentId: env.outputs.environmentId
    acrLoginServer: acr.outputs.loginServer
    acrName: acr.outputs.name
    imageTag: imageTag
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    appInsightsConnectionString: logAnalytics.outputs.appInsightsConnectionString
  }
}

output containerAppUrl string = app.outputs.appUrl
output containerAppName string = app.outputs.appName
output acrLoginServer string = acr.outputs.loginServer
output environmentName string = env.outputs.environmentName
output logAnalyticsName string = logAnalytics.outputs.name
