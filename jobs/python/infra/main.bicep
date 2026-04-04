targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Container image tag')
param imageTag string = 'latest'

@description('Storage container name for job input')
param storageContainerName string = 'samples'

@description('Storage blob name for job input')
param storageBlobName string = 'input/demo.txt'

var uniqueSuffix = uniqueString(resourceGroup().id)
var storageAccountName = toLower(replace('st${baseName}${uniqueSuffix}', '-', ''))

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    baseName: baseName
    location: location
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

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
}

resource testContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: storageContainerName
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

// Note: Blobs cannot be created via Bicep/ARM. Use trigger.sh or az cli to upload test data.

module job 'modules/container-app-job.bicep' = {
  name: 'container-app-job'
  params: {
    baseName: baseName
    location: location
    environmentId: env.outputs.environmentId
    acrName: acr.outputs.name
    acrLoginServer: acr.outputs.loginServer
    imageTag: imageTag
    storageAccountName: storageAccount.name
    storageContainerName: testContainer.name
    storageBlobName: storageBlobName
  }
}

output jobName string = job.outputs.jobName
output environmentName string = env.outputs.environmentName
output acrLoginServer string = acr.outputs.loginServer
output storageAccountName string = storageAccount.name
output storageContainerName string = testContainer.name
output storageBlobName string = storageBlobName
