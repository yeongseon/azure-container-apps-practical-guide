targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var registryName = toLower(replace('acr${baseName}${suffix}', '-', ''))

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

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    // Lab-only setting for simpler image pulls without managed identity.
    adminUserEnabled: true
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
        #disable-next-line use-secure-value-for-secure-inputs
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output environmentName string = environment.name
output environmentId string = environment.id
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
