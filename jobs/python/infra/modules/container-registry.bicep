targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

var uniqueSuffix = uniqueString(resourceGroup().id)
var rawName = 'cr${baseName}${uniqueSuffix}'
var registryName = toLower(replace(rawName, '-', ''))

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

output id string = acr.id
output name string = acr.name
output loginServer string = acr.properties.loginServer
