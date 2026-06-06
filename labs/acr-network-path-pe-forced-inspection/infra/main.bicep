targetScope = 'resourceGroup'

@description('Base name for all resources (lowercase letters and digits only)')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('VNet address space for the lab')
param vnetAddressPrefix string = '10.90.0.0/16'

@description('Container Apps workload-profile subnet prefix (must be at least /23)')
param acaSubnetPrefix string = '10.90.0.0/23'

@description('Private Endpoint subnet prefix')
param peSubnetPrefix string = '10.90.2.0/26'

@description('AzureFirewallSubnet prefix (Azure Firewall Basic requires /26 or larger; name MUST be exactly AzureFirewallSubnet)')
param firewallSubnetPrefix string = '10.90.3.0/26'

@description('AzureFirewallManagementSubnet prefix (required for Azure Firewall Basic)')
param firewallManagementSubnetPrefix string = '10.90.3.64/26'

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
var firewallSubnetName = 'AzureFirewallSubnet'
var firewallManagementSubnetName = 'AzureFirewallManagementSubnet'
var firewallName = 'afw-${baseName}-${suffix}'
var firewallPublicIpName = 'pip-${firewallName}'
var firewallPolicyName = 'afwp-${baseName}-${suffix}'
var routeTableName = 'rt-${baseName}-${suffix}'
var defaultRouteName = 'default-via-afw'
var privateDnsZoneName = 'privatelink.azurecr.io'
var privateEndpointName = 'pe-${registryName}'

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
// Scenario C (ACR PE with Forced Inspection) requires:
//   - snet-aca (Container Apps workload-profile subnet, delegated, /23 or larger)
//   - snet-pe with privateEndpointNetworkPolicies=Enabled — THIS IS THE KEY
//     SETTING for Scenario C. Without this, UDRs on the consuming subnet do
//     NOT apply to PE traffic; the system /32 route for the PE wins
//     unconditionally and traffic bypasses any inspection NVA. With this set
//     to Enabled, UDRs CAN redirect PE traffic, but only if the UDR has a
//     specific /32 route for the PE NIC IP (a 0.0.0.0/0 default route is
//     NOT sufficient because the system route for the PE is more specific).
//   - AzureFirewallSubnet (exact name, /26 or larger for Basic)
//   - AzureFirewallManagementSubnet (Basic only)
//   - ACR Premium with publicNetworkAccess (toggled by trigger.sh)
//   - PE for ACR with private DNS zone linked to the VNet
//   - UDR initially deploys with ONLY a 0.0.0.0/0 → firewall route. After
//     PE provisioning completes and PE NIC IPs are discoverable, trigger.sh
//     adds the explicit /32 routes for the PE registry IP and the PE data
//     IP. This staged approach matches the real-world deployment story:
//     compliance team requires inspection, operator adds the /32 UDR
//     entries explicitly, firewall app rules then see the ACR traffic.
//
// The single controlled variable in falsify.sh is the PRESENCE of those /32
// UDR entries. Removing them = traffic bypasses firewall (smoking gun:
// AZFWApplicationRule stops logging ACR FQDN). Re-adding them = traffic
// flows through firewall again (smoking gun: AZFWApplicationRule resumes).

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
          routeTable: {
            id: routeTable.id
          }
        }
      }
      {
        // Dedicated Private Endpoint subnet.
        // privateEndpointNetworkPolicies MUST be 'Enabled' for Scenario C —
        // this is the setting that allows UDRs on the consuming subnet to
        // redirect PE traffic. With it set to 'Disabled' (the default in
        // older deployments), PE traffic always takes the system /32 route
        // and bypasses any UDR-driven NVA inspection.
        name: peSubnetName
        properties: {
          addressPrefix: peSubnetPrefix
          privateEndpointNetworkPolicies: 'Enabled'
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

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: peSubnetName
  parent: vnet
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: firewallSubnetName
  parent: vnet
}

// -----------------------------------------------------------------------------
// Route Table — forces snet-aca egress through the firewall private IP
// -----------------------------------------------------------------------------
//
// The route table is associated with snet-aca only. It starts with ONLY the
// default route (0.0.0.0/0 → firewall private IP). After PE provisioning,
// trigger.sh discovers the PE NIC private IPs (one for registry, one for
// the regional data endpoint) and adds explicit /32 routes for each → same
// firewall private IP. Those /32 routes are the controlled variable.

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
    // privateIPAddress. Reading the resource property is correct in all
    // cases vs computing from subnet CIDR (which returns the Azure-reserved
    // gateway address, not the firewall instance address).
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
  name: firewallManagementSubnetName
  parent: vnet
  properties: {
    addressPrefix: firewallManagementSubnetPrefix
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
            // The firewall must explicitly allow the ACR FQDNs even though
            // those FQDNs resolve to private IPs (the PE NIC IPs). The
            // application rule matches on the host header sent by the
            // client (docker pull), not on the destination IP.
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
// Without this, the firewall silently allows/denies traffic but no record
// appears in LAW. The Scenario C smoking-gun KQL queries AZFWApplicationRule
// for ACR FQDN entries to prove (a) inspection is happening when /32 PE
// routes are present, and (b) inspection has stopped when /32 routes are
// removed. Without diagnostic settings flowing to LAW, the smoking gun
// cannot be observed.
//
// logAnalyticsDestinationType MUST be 'Dedicated' (NOT the legacy default
// 'AzureDiagnostics') so logs land in resource-specific tables —
// AZFWApplicationRule, AZFWNetworkRule, AZFWDnsQuery — instead of the
// generic 'AzureDiagnostics' table. The lab's falsify.sh queries
// `AZFWApplicationRule | where Fqdn endswith ".azurecr.io"` directly; that
// table only exists in the Dedicated schema. With the legacy schema the
// same data lives in `AzureDiagnostics | where Category == "AzureFirewallApplicationRule"`
// with column names like `msg_s` instead of `Fqdn`, and the lab's KQL
// would never match.
resource firewallDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: firewall
  properties: {
    workspaceId: logAnalytics.id
    logAnalyticsDestinationType: 'Dedicated'
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
// ACR (Premium) — public access initially Enabled, switched to Disabled
// by trigger.sh after the lab images are built
// -----------------------------------------------------------------------------
//
// Initially deployed with publicNetworkAccess=Enabled so trigger.sh can use
// `az acr build` to push v1/v-bypass/v-recover. After the build step,
// trigger.sh sets publicNetworkAccess=Disabled, which forces all subsequent
// pulls to go through the Private Endpoint.
//
// adminUserEnabled is TRUE because this lab uses ACR admin credentials, NOT
// managed identity. This matches Lab 1 (Scenario A — firewall-allowlist),
// which documented the rationale in its README/trigger.sh:
//
//     Managed identity introduces a control-plane token-exchange call
//     (CAE control plane -> ACR for an ACR refresh token) whose network
//     path is DIFFERENT from the replica's image-pull path. With MI, the
//     workload's MI must also reach login.microsoftonline.com from inside
//     snet-aca to acquire an AAD token. With a forced-inspection topology
//     (default route -> firewall), the MI's AAD call has to traverse the
//     firewall and the firewall must have an explicit application rule for
//     login.microsoftonline.com. That second auth path is a confound: a
//     failure could be attributable to the data-plane PE path under test
//     OR to the MI auth path that has nothing to do with the lab thesis.
//
//     With admin credentials, the ONLY authentication is a docker login
//     happening over the replica's egress path to the ACR FQDN. The
//     FQDN resolves via the private DNS zone to a PE NIC IP, so the entire
//     auth+pull conversation rides on the same /32-controlled path. The
//     /32 UDR entries for PE NIC IPs become the single controlled variable.
//
// Both the registry FQDN and the regional data endpoint FQDN resolve via
// the private DNS zone to PE NIC IPs.

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
// Private DNS zone for ACR, linked to the lab VNet
// -----------------------------------------------------------------------------

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
// The PE NIC will hold separate private IPs for the global/login endpoint
// and for the regional data endpoint. trigger.sh discovers both IPs after
// PE provisioning and adds /32 UDR routes for each. The PE network policies
// on snet-pe being 'Enabled' is what allows those UDR routes to actually
// apply to PE traffic from snet-aca.

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
          privateLinkServiceId: registry.id
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
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      // Workload-profile environment with the ACA subnet as its
      // infrastructure subnet. internal=false keeps ingress public; the
      // egress path is what this lab is about, not ingress.
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
  dependsOn: [
    firewall
  ]
}

// -----------------------------------------------------------------------------
// Container App (placeholder image; trigger.sh wires admin creds + ACR image)
// -----------------------------------------------------------------------------
//
// The placeholder image (mcr.microsoft.com/k8se/quickstart:latest) lets the
// Container App resource provision without requiring access to the private
// ACR. trigger.sh then runs `az containerapp registry set --username/--password`
// to attach the ACR with admin credentials, and `az containerapp update
// --image <acr-fqdn>/...:<tag>` to switch the workload image to the lab tags.
//
// No system-assigned managed identity and no registries[] block here — see
// the rationale on the ACR resource above. Admin credentials make the entire
// auth+pull conversation ride on the same PE-NIC-IP path the /32 UDRs
// control, isolating the single variable the lab is designed to test.

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: environment.id
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
          // Public placeholder until trigger.sh switches to the private ACR image.
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
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output routeTableName string = routeTableName
output vnetName string = vnetName
output acaSubnetName string = acaSubnetName
output peSubnetName string = peSubnetName
output privateEndpointName string = privateEndpointName
output logAnalyticsName string = logAnalyticsName
// Workspace customer ID (GUID) for `az monitor log-analytics query --workspace`.
// falsify.sh uses this to query both ContainerAppSystemLogs_CL and
// AZFWApplicationRule. The latter is the Scenario C smoking gun: presence of
// rows for ACR FQDNs proves inspection is happening; absence after /32 routes
// are removed proves bypass (system PE route winning).
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
