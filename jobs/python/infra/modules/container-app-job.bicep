targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Container Apps environment resource ID')
param environmentId string

@description('ACR resource name')
param acrName string

@description('ACR login server')
param acrLoginServer string

@description('Container image tag')
param imageTag string = 'latest'

@description('Storage account name for blob endpoint URL')
param storageAccountName string

@description('Storage container name')
param storageContainerName string

@description('Storage blob name')
param storageBlobName string

var uniqueSuffix = uniqueString(resourceGroup().id)
var jobName = 'job-${baseName}-${uniqueSuffix}'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource job 'Microsoft.App/jobs@2023-05-01' = {
  name: jobName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: environmentId
    configuration: {
      triggerType: 'Manual'
      replicaRetryLimit: 2
      replicaTimeout: 1800
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: acrLoginServer
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'job'
          image: '${acrLoginServer}/${baseName}-job:${imageTag}'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'STORAGE_ACCOUNT_URL'
              value: 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
            }
            {
              name: 'STORAGE_CONTAINER_NAME'
              value: storageContainerName
            }
            {
              name: 'STORAGE_BLOB_NAME'
              value: storageBlobName
            }
            {
              name: 'LOG_LEVEL'
              value: 'INFO'
            }
          ]
        }
      ]
    }
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, job.id, 'acrpull')
  scope: acr
  properties: {
    principalId: job.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource blobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, job.id, 'blobreader')
  scope: storageAccount
  properties: {
    principalId: job.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

output jobId string = job.id
output jobName string = job.name
