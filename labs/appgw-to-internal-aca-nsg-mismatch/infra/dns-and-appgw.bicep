targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// dns-and-appgw.bicep — Phase 2 module deployed AFTER the Container Apps
// environment is created, so `defaultDomain` and `staticIp` are known.
//
// Splitting these resources into a module is required because ARM/Bicep
// evaluates resource names at the START of a deployment. The Private DNS
// Zone name must equal env.properties.defaultDomain, which is only known
// after env.deploy completes. Module parameters are evaluated when the
// module's inner deployment starts, so passing the values in as params
// makes them resolvable in time.
// -----------------------------------------------------------------------------

@description('Location for all resources')
param location string

@description('Container Apps environment defaultDomain (used as Private DNS Zone name)')
param defaultDomain string

@description('Container Apps environment staticIp (ILB frontend IP; A record target)')
param staticIp string

@description('Container app FQDN (used as Application Gateway backend pool member)')
param appFqdn string

@description('VNet resource ID (linked to the Private DNS Zone so AppGW can resolve appFqdn)')
param vnetId string

@description('Application Gateway subnet resource ID')
param appgwSubnetId string

@description('Application Gateway name')
param appgwName string

@description('Application Gateway public IP name')
param appgwPublicIpName string

@description('VNet name (used to derive the DNS Zone-to-VNet link name)')
param vnetName string

@description('Log Analytics workspace resource ID (for diagnostic settings)')
param logAnalyticsId string

// -----------------------------------------------------------------------------
// Private DNS Zone matching the CAE defaultDomain
// -----------------------------------------------------------------------------

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: defaultDomain
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-${vnetName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource wildcardRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: '*'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: staticIp
      }
    ]
  }
}

resource apexRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: '@'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: staticIp
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Application Gateway Standard_v2 + Public IP
// -----------------------------------------------------------------------------

resource appgwPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: appgwPublicIpName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

var appgwId = resourceId('Microsoft.Network/applicationGateways', appgwName)

resource appgw 'Microsoft.Network/applicationGateways@2024-01-01' = {
  name: appgwName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appgwIpConfig'
        properties: {
          subnet: {
            id: appgwSubnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appgwFrontendPublic'
        properties: {
          publicIPAddress: {
            id: appgwPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'aca-backend-pool'
        properties: {
          backendAddresses: [
            {
              fqdn: appFqdn
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'aca-https-probe'
        properties: {
          protocol: 'Https'
          port: 443
          path: '/'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'aca-https-setting'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
          probe: {
            id: '${appgwId}/probes/aca-https-probe'
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'appgw-listener-http'
        properties: {
          frontendIPConfiguration: {
            id: '${appgwId}/frontendIPConfigurations/appgwFrontendPublic'
          }
          frontendPort: {
            id: '${appgwId}/frontendPorts/port80'
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'appgw-route-http'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: '${appgwId}/httpListeners/appgw-listener-http'
          }
          backendAddressPool: {
            id: '${appgwId}/backendAddressPools/aca-backend-pool'
          }
          backendHttpSettings: {
            id: '${appgwId}/backendHttpSettingsCollection/aca-https-setting'
          }
        }
      }
    ]
  }
  dependsOn: [
    privateDnsZoneLink
    wildcardRecord
    apexRecord
  ]
}

resource appgwDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: appgw
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output appgwPublicIpAddress string = appgwPublicIp.properties.ipAddress
output privateDnsZoneName string = privateDnsZone.name
