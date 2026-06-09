targetScope = 'resourceGroup'

@description('Base name for all resources (lowercase letters and digits only)')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('VNet address space for the lab')
param vnetAddressPrefix string = '10.80.0.0/16'

@description('Container Apps workload-profile subnet prefix (must be at least /23)')
param acaSubnetPrefix string = '10.80.0.0/23'

@description('AzureFirewallSubnet prefix (Azure Firewall Basic requires /26 or larger; name MUST be exactly AzureFirewallSubnet)')
param firewallSubnetPrefix string = '10.80.2.0/26'

@description('Public placeholder image used until the lab switches to the private ACR image')
param placeholderImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var registryName = toLower(replace('acr${baseName}${suffix}', '-', ''))
var appName = 'ca-${baseName}-${suffix}'
var vnetName = 'vnet-${baseName}-${suffix}'
var acaSubnetName = 'snet-aca'
var firewallSubnetName = 'AzureFirewallSubnet'
var firewallName = 'afw-${baseName}-${suffix}'
var firewallPublicIpName = 'pip-${firewallName}'
var firewallPolicyName = 'afwp-${baseName}-${suffix}'
var routeTableName = 'rt-${baseName}-${suffix}'
var defaultRouteName = 'default-via-afw'

// Regional ACR data endpoint FQDN — exact FQDN required for firewall app rule.
// Format: <registry>.<region>.data.azurecr.io (lowercase region).
var registryLoginFqdn = '${registryName}.azurecr.io'
var registryDataFqdn = '${registryName}.${toLower(location)}.data.azurecr.io'

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
// Scenario A (Public ACR via Firewall) requires:
//   - snet-aca (Container Apps workload-profile subnet, delegated, /23 or larger)
//   - AzureFirewallSubnet (exact name, /26 or larger for Azure Firewall Basic)
//   - A UDR forcing 0.0.0.0/0 from snet-aca through the firewall private IP, so
//     replica egress to ACR's PUBLIC FQDN traverses the firewall and is
//     SNAT'd to the firewall's public IP.
//   - ACR's network rule set will be tightened (out-of-band by trigger.sh) to:
//         defaultAction          = Deny
//         networkRuleBypassOptions = None
//         ipRules                = [<firewall public IP>]
//     so ACR proves it sees the firewall's SNAT public IP, not the replica IP.
//
// The VNet uses default Azure DNS (no dhcpOptions.dnsServers). DNS is NOT the
// controlled variable in this lab — egress IP via the firewall SNAT is.

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
        // UDR attachment happens via the dedicated route-table association
        // resource below, so the subnet's UDR is updated atomically without
        // re-declaring the full subnet here.
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
          // The route table is attached via routeTable property below in a
          // separate subnet resource declaration to keep the dependency order
          // explicit (route table -> default route -> subnet association).
          routeTable: {
            id: routeTable.id
          }
        }
      }
      {
        // Azure Firewall subnet. Name MUST be exactly 'AzureFirewallSubnet'.
        // Azure Firewall Basic requires /26 or larger.
        name: firewallSubnetName
        properties: {
          addressPrefix: firewallSubnetPrefix
        }
      }
    ]
  }
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: acaSubnetName
  parent: vnet
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: firewallSubnetName
  parent: vnet
}

// -----------------------------------------------------------------------------
// Route Table — forces snet-aca egress through the firewall private IP
// -----------------------------------------------------------------------------

resource routeTable 'Microsoft.Network/routeTables@2024-01-01' = {
  name: routeTableName
  location: location
  properties: {
    disableBgpRoutePropagation: true
  }
}

resource defaultRoute 'Microsoft.Network/routeTables/routes@2024-01-01' = {
  name: defaultRouteName
  parent: routeTable
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'VirtualAppliance'
    // The next-hop IP MUST be Azure Firewall's actual ipConfigurations[0]
    // privateIPAddress. Computing this from the subnet CIDR (e.g.
    // cidrHost('10.80.2.0/26', 0)) returns the Azure-reserved gateway
    // address (.1), not the firewall instance address (.4 in this layout
    // because Azure reserves .0/.1/.2/.3). Hard-coding ".4" works for /26
    // but breaks if the subnet is moved or resized; reading the resource
    // property is correct in all cases.
    nextHopIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
  }
}

// -----------------------------------------------------------------------------
// Azure Firewall (Basic SKU)
// -----------------------------------------------------------------------------

resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: firewallPublicIpName
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

// Azure Firewall Basic requires both a management public IP and a separate
// management subnet (AzureFirewallManagementSubnet). The Standard/Premium
// tiers do not require this. The management NIC handles control-plane
// traffic from the firewall to the Azure backend (status, signatures,
// metrics) on a path independent of the data plane.
// Reference: https://learn.microsoft.com/en-us/azure/firewall/deploy-firewall-basic-portal-policy

resource firewallManagementPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: '${firewallPublicIpName}-mgmt'
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

resource firewallManagementSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  name: 'AzureFirewallManagementSubnet'
  parent: vnet
  properties: {
    addressPrefix: '10.80.2.64/26'
  }
  dependsOn: [
    firewallSubnet
  ]
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-01-01' = {
  name: firewallPolicyName
  location: location
  properties: {
    sku: {
      tier: 'Basic'
    }
    threatIntelMode: 'Alert'
  }
}

resource firewallAppRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = {
  name: 'acr-and-platform-allow'
  parent: firewallPolicy
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-acr-and-platform'
        priority: 210
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-acr-login'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [
              acaSubnetPrefix
            ]
            targetFqdns: [
              registryLoginFqdn
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-acr-data'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [
              acaSubnetPrefix
            ]
            targetFqdns: [
              registryDataFqdn
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-mcr'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [
              acaSubnetPrefix
            ]
            targetFqdns: [
              'mcr.microsoft.com'
              '*.data.mcr.microsoft.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-acs-mirror'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [
              acaSubnetPrefix
            ]
            targetFqdns: [
              'acs-mirror.azureedge.net'
              'packages.aks.azure.com'
            ]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-01-01' = {
  name: firewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Basic'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'fwIpConfig'
        properties: {
          subnet: {
            id: firewallSubnet.id
          }
          publicIPAddress: {
            id: firewallPublicIp.id
          }
        }
      }
    ]
    managementIpConfiguration: {
      name: 'fwMgmtIpConfig'
      properties: {
        subnet: {
          id: firewallManagementSubnet.id
        }
        publicIPAddress: {
          id: firewallManagementPublicIp.id
        }
      }
    }
  }
  dependsOn: [
    firewallAppRules
  ]
}

// Diagnostic settings on the firewall — required to populate
// AZFWApplicationRule / AZFWNetworkRule / AZFWDnsQuery in Log Analytics.
// Without this, the firewall silently drops/allows traffic but no record
// appears in LAW, making lab evidence collection impossible.
resource firewallDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: firewall
  properties: {
    workspaceId: logAnalytics.id
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

// -----------------------------------------------------------------------------
// ACR (Premium) — public access, dedicated data endpoint, admin user enabled
// -----------------------------------------------------------------------------
//
// Initially deployed with defaultAction=Allow so trigger.sh can use
// `az acr build` to push v1/v-broken/v-recover. After the build step,
// trigger.sh tightens the network rule set to:
//     defaultAction          = Deny
//     networkRuleBypassOptions = None
//     ipRules                = [<firewall public IP>]
//
// This is the central thesis of Scenario A: ACR's allowlist is keyed on
// the egress firewall's SNAT public IP, not the replica's internal IP.

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: registryName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
    dataEndpointEnabled: true
    networkRuleSet: {
      defaultAction: 'Allow'
      ipRules: []
    }
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      retentionPolicy: {
        days: 7
        status: 'enabled'
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Container Apps Environment + App (placeholder image)
// -----------------------------------------------------------------------------

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      internal: false
      infrastructureSubnetId: acaSubnet.id
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
  dependsOn: [
    firewall
  ]
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'app'
          image: placeholderImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
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
// Outputs (consumed by trigger.sh / verify.sh / falsify.sh)
// -----------------------------------------------------------------------------

output resourceGroupName string = resourceGroup().name
output registryName string = registryName
output registryLoginServer string = registryLoginFqdn
output registryDataEndpoint string = registryDataFqdn
output appName string = appName
output environmentName string = environmentName
output firewallName string = firewallName
output firewallPolicyName string = firewallPolicyName
output firewallPublicIpName string = firewallPublicIpName
output firewallPublicIpAddress string = firewallPublicIp.properties.ipAddress
output vnetName string = vnetName
output acaSubnetName string = acaSubnetName
output logAnalyticsName string = logAnalyticsName
// Workspace customer ID (GUID) for `az monitor log-analytics query --workspace`.
// falsify.sh uses this to query ContainerAppSystemLogs_CL for the smoking-gun
// DENIED log entry naming the firewall PIP as the rejected source IP — this is
// the empirical proof that ACR's `ipRules` is keyed on the firewall SNAT IP.
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
