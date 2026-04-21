targetScope = 'resourceGroup'

@description('Object ID of the principal to grant AcrPush on the registry')
param principalObjectId string

@description('Name of the existing Azure Container Registry')
param registryName string

@description('Optional override for the role assignment GUID. Leave empty to deterministically derive it from principalObjectId+registry+role.')
param roleAssignmentName string = ''

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

var acrPushRoleId = '8311e382-0749-4cb8-b61a-304f252e45ec'
var derivedName = guid(registry.id, principalObjectId, acrPushRoleId)
var assignmentName = empty(roleAssignmentName) ? derivedName : roleAssignmentName

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: assignmentName
  properties: {
    principalId: principalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPushRoleId)
  }
}

output roleAssignmentName string = roleAssignment.name
