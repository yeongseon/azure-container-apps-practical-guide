// ACR module with Private Endpoint (Premium SKU, data endpoint enabled)
// Supports managed identity pull via ARM audience tokens
targetScope = 'resourceGroup'

@description('Base name for resources')
param baseName string

@description('Location for resources')
param location string

@description('Subnet ID for private endpoints')
param privateEndpointSubnetId string

@description('VNet ID for DNS zone link')
param vnetId string

@description('Principal ID of the managed identity that will pull images (AcrPull)')
param pullIdentityPrincipalId string

// Generate unique suffix
var uniqueSuffix = uniqueString(resourceGroup().id)
var acrName = take(replace('cr${baseName}${uniqueSuffix}', '-', ''), 50)
var peRegistryName = 'pe-acr-${baseName}'
var privateDnsZoneName = 'privatelink.azurecr.io'

// ============================================================================
// Container Registry (Premium — required for Private Endpoints)
// ============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium'  // Basic/Standard do not support Private Endpoints
  }
  properties: {
    adminUserEnabled: false           // Disable admin — use managed identity
    publicNetworkAccess: 'Disabled'   // All access via private endpoint
    // Note: dataEndpointEnabled requires a separate PE for registry_data_<location>
    // Enable this after ACR is fully provisioned, then add a second PE manually.
    // See docs/recipes/container-registry.md for details.
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
  }
}

// ============================================================================
// Private DNS Zone (shared for both registry and data endpoints)
// ============================================================================

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-acr-${baseName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

// ============================================================================
// Private Endpoint — Registry (login server: myregistry.azurecr.io)
// ============================================================================

resource peRegistry 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: peRegistryName
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'conn-acr-registry'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: ['registry']
        }
      }
    ]
  }
}

resource peRegistryDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: peRegistry
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'registry'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ============================================================================
// AcrPull role assignment for the pull identity (user-assigned MI)
// ============================================================================

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, pullIdentityPrincipalId, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'  // AcrPull
    )
    principalId: pullIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

output acrId string = acr.id
output acrName string = acr.name
output loginServer string = acr.properties.loginServer
output privateEndpointRegistryId string = peRegistry.id
output privateDnsZoneId string = privateDnsZone.id
