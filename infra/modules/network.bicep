// Network module - VNet with subnets for Container Apps and Private Endpoints
targetScope = 'resourceGroup'

@description('Base name for resources')
param baseName string

@description('Location for resources')
param location string

@description('VNet address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Container Apps subnet address prefix (minimum /23)')
param containerAppsSubnetPrefix string = '10.0.0.0/23'

@description('Private Endpoints subnet address prefix')
param privateEndpointsSubnetPrefix string = '10.0.2.0/24'

// Generate unique suffix
var uniqueSuffix = uniqueString(resourceGroup().id)
var vnetName = 'vnet-${baseName}-${uniqueSuffix}'
var nsgContainerAppsName = 'nsg-containerapp-${baseName}'
var nsgPrivateEndpointsName = 'nsg-privateendpoints-${baseName}'

// Network Security Group for Container Apps subnet
resource nsgContainerApps 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgContainerAppsName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPSInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowHTTPInbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

// Network Security Group for Private Endpoints subnet
resource nsgPrivateEndpoints 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgPrivateEndpointsName
  location: location
  properties: {
    securityRules: []  // Private endpoints don't require special NSG rules
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-container-apps'
        properties: {
          addressPrefix: containerAppsSubnetPrefix
          networkSecurityGroup: {
            id: nsgContainerApps.id
          }
          delegations: [
            {
              name: 'Microsoft-App-environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          networkSecurityGroup: {
            id: nsgPrivateEndpoints.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output containerAppsSubnetId string = vnet.properties.subnets[0].id
output containerAppsSubnetName string = vnet.properties.subnets[0].name
output privateEndpointsSubnetId string = vnet.properties.subnets[1].id
output privateEndpointsSubnetName string = vnet.properties.subnets[1].name
