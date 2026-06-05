targetScope = 'resourceGroup'

@description('Base name for all resources (lowercase letters and digits only)')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('VNet address space for the lab')
param vnetAddressPrefix string = '10.70.0.0/16'

@description('Container Apps workload-profile subnet prefix (must be at least /23)')
param acaSubnetPrefix string = '10.70.0.0/23'

@description('Private Endpoint subnet prefix')
param peSubnetPrefix string = '10.70.4.0/24'

@description('Public placeholder image used until the lab switches to the private ACR image')
param placeholderImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var registryName = toLower(replace('acr${baseName}${suffix}', '-', ''))
var appName = 'ca-${baseName}-${suffix}'
var vnetName = 'vnet-${baseName}-${suffix}'
var acaSubnetName = 'snet-aca'
var peSubnetName = 'snet-pe'
var privateDnsZoneName = 'privatelink.azurecr.io'
var privateEndpointName = 'pe-${registryName}'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// -----------------------------------------------------------------------------
// Observability
// -----------------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
// Networking
// -----------------------------------------------------------------------------
//
// Scenario D (record-level split-brain) is a resolver-PATH-correct, RECORD-LEVEL
// failure: the VNet sends DNS queries to Azure DNS (the default 168.63.129.16),
// Azure DNS sees that this VNet is linked to the privatelink.azurecr.io zone,
// and Azure DNS would substitute the PE NIC IP for ANY record present in that
// zone. The failure injected by falsify.sh is at the zone CONTENT layer:
// delete the `<registry>.<region>.data` A record, so Azure DNS has nothing to
// substitute for that name and the answer falls through to the public CNAME
// chain. We do NOT need a custom DNS forwarder VM for Scenario D, which is
// what distinguishes it from Scenario E (DNS-topology failure, covered by the
// sibling acr-network-path-dns-forwarder-bypass lab).
//
// The VNet therefore deliberately omits dhcpOptions.dnsServers; every NIC in
// the VNet uses Azure DNS by default.

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        // Container Apps workload-profile infrastructure subnet.
        // Must be delegated to Microsoft.App/environments.
        name: acaSubnetName
        properties: {
          addressPrefix: acaSubnetPrefix
          delegations: [
            {
              name: 'aca-env-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        // Dedicated Private Endpoint subnet. Must be non-delegated.
        name: peSubnetName
        properties: {
          addressPrefix: peSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: acaSubnetName
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: peSubnetName
}

// -----------------------------------------------------------------------------
// Container Registry (Premium, public access disabled)
// -----------------------------------------------------------------------------
//
// publicNetworkAccess=Disabled is what gives Scenario D its operational teeth:
// when the data record is deleted from the private DNS zone and the data FQDN
// resolves publicly, the public registry IP rejects the inbound connection
// because the source is the internet and the firewall is closed. If
// publicNetworkAccess were Enabled, the layer download would silently traverse
// public Internet and "succeed" (defeating the lab's purpose), even though it
// would still violate the customer's expected network posture.

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: registryName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
  }
}

// -----------------------------------------------------------------------------
// Private DNS zone for ACR, linked to the lab VNet
// -----------------------------------------------------------------------------
//
// The zone group on the PE auto-populates BOTH A records on baseline deploy:
//   - <registry>.azurecr.io → registry PE NIC IP (registry login endpoint)
//   - <registry>.<region>.data.azurecr.io → data PE NIC IP (regional data endpoint)
// falsify.sh deletes only the second one to inject Scenario D.

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// -----------------------------------------------------------------------------
// Private Endpoint for ACR (single 'registry' sub-resource)
// -----------------------------------------------------------------------------
//
// The 'registry' sub-resource is the only PE group ACR exposes, but the PE NIC
// itself holds TWO private IPs: one for the registry login endpoint and one
// for the regional data endpoint. The privateDnsZoneGroup below auto-creates
// the A records for BOTH FQDNs at deploy time.

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: peSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'acr-conn'
        properties: {
          privateLinkServiceId: containerRegistry.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

resource acrPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: acrPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Container Apps environment (workload profiles, VNet-integrated)
// -----------------------------------------------------------------------------

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
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnet.id
      internal: false
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Container App with system-assigned managed identity
// -----------------------------------------------------------------------------
//
// The workload's /probe endpoint takes two URL parameters target=registry|data
// and runs a 4-layer probe against the corresponding ACR FQDN inside the
// replica:
//   1) socket.getaddrinfo() → first resolved IP + classification (private/public)
//   2) socket.create_connection() → TCP handshake success / refused / timeout
//   3) ssl.wrap_socket() → TLS handshake success / failure
//   4) HTTP GET /v2/        → expected status code (401 = success; ACR's
//                              firewall rejection looks different)
// ACR_FQDN is the registry login FQDN (from containerRegistry.loginServer).
// ACR_DATA_FQDN is the regional data FQDN, computed in Bicep and injected as
// an env var so the probe can address it directly without recomputing the
// region name.

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
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
          // Public placeholder until trigger.sh switches to the private ACR image.
          image: placeholderImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'ACR_FQDN'
              value: containerRegistry.properties.loginServer
            }
            {
              name: 'ACR_DATA_FQDN'
              value: '${registryName}.${location}.data.azurecr.io'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// -----------------------------------------------------------------------------
// AcrPull role assignment for the Container App's managed identity
// -----------------------------------------------------------------------------

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, app.id, acrPullRoleId)
  scope: containerRegistry
  properties: {
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
  }
}

// -----------------------------------------------------------------------------
// Outputs (consumed by trigger.sh / verify.sh / falsify.sh)
// -----------------------------------------------------------------------------

output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output environmentName string = environment.name
output environmentId string = environment.id
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerRegistryDataFqdn string = '${registryName}.${location}.data.azurecr.io'
output containerAppName string = app.name
output containerAppFqdn string = app.properties.configuration.ingress.fqdn
output containerAppPrincipalId string = app.identity.principalId
output vnetName string = vnet.name
output acaSubnetName string = acaSubnet.name
output peSubnetName string = peSubnet.name
output privateDnsZoneName string = privateDnsZone.name
output privateEndpointName string = acrPrivateEndpoint.name
