targetScope = 'resourceGroup'

@description('Base name for all resources (lowercase letters and digits only)')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('VNet address space for the lab')
param vnetAddressPrefix string = '10.60.0.0/16'

@description('Container Apps workload-profile subnet prefix (must be at least /23)')
param acaSubnetPrefix string = '10.60.0.0/23'

@description('Private Endpoint subnet prefix')
param peSubnetPrefix string = '10.60.4.0/24'

@description('DNS forwarder VM subnet prefix (/27 is enough for one VM)')
param dnsSubnetPrefix string = '10.60.5.0/27'

@description('Static private IP for the dnsmasq VM (must be inside dnsSubnetPrefix and outside the first four addresses Azure reserves)')
param dnsVmPrivateIp string = '10.60.5.4'

@description('Admin username for the dnsmasq VM (only used for VM provisioning; lab uses az vm run-command for all operations)')
param vmAdminUsername string = 'azureuser'

@description('Admin password for the dnsmasq VM. Required by Azure VM provisioning but unused by the lab scripts (which use az vm run-command). Pass a freshly-generated strong password and discard it.')
@secure()
@minLength(12)
param vmAdminPassword string

@description('VM size for the DNS forwarder. B1s is sufficient.')
param vmSize string = 'Standard_B1s'

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
var dnsSubnetName = 'snet-dns'
var dnsVmName = 'vm-dns-${suffix}'
var dnsNicName = 'nic-dns-${suffix}'
var dnsNsgName = 'nsg-dns-${suffix}'
var privateDnsZoneName = 'privatelink.azurecr.io'
var privateEndpointName = 'pe-${registryName}'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// cloud-init for the dnsmasq VM. Initial (HEALTHY) state: dnsmasq's
// default upstream is Azure DNS (168.63.129.16), so the CAE → VM path
// resolves ACR's public FQDN through Azure DNS. Azure DNS sees this
// VM's VNet is linked to the Private DNS Zone privatelink.azurecr.io
// and substitutes the PE NIC IP for the CNAME chain. falsify.sh
// rewrites this line to 8.8.8.8 via `az vm run-command invoke` to
// drive the lab into Scenario E (resolver topology no longer covers
// the Azure namespace, so ACR FQDN resolves to the public registry IP).
//
// Multi-line string literals in Bicep don't support interpolation, so the
// VM IP is templated with __DNS_IP__ and rewritten via replace() below.
// Chicken-and-egg: VNet DNS = this VM's IP (10.60.5.4), but at first boot
// dnsmasq isn't installed yet, so the VM cannot resolve archive.ubuntu.com.
// bootcmd runs BEFORE the package phase: pin /etc/resolv.conf to Azure
// DNS (168.63.129.16) and chattr +i so DHCP/systemd-resolved cannot
// overwrite it. The VM keeps using Azure DNS forever; dnsmasq binds to
// 10.60.5.4:53 (bind-interfaces) and serves only CAE workload clients.
//
// Why a default forward instead of a `server=/privatelink.azurecr.io/...`
// conditional forward: a conditional forward only fires when the QUERY
// name is under that zone. CAE / glibc / curl all query the PUBLIC
// FQDN (e.g. `myreg.azurecr.io`) first; if dnsmasq's default upstream is
// 8.8.8.8 it returns the full public CNAME chain in one response and
// the client uses the public A record without ever re-querying the
// privatelink CNAME target. Forwarding the parent zone (the entire
// query namespace) to Azure DNS lets Azure DNS perform the Private DNS
// Zone substitution while resolving the chain.
var dnsmasqCloudInitTemplate = '''#cloud-config
bootcmd:
  - [ rm, -f, /etc/resolv.conf ]
  - [ sh, -c, 'printf "nameserver 168.63.129.16\nnameserver 8.8.8.8\n" > /etc/resolv.conf' ]
  - [ chattr, +i, /etc/resolv.conf ]
package_update: true
packages:
  - dnsmasq
write_files:
  - path: /etc/dnsmasq.d/acr-lab.conf
    permissions: '0644'
    content: |
      # Lab: ACR Network Path E - DNS Forwarder Bypass (HEALTHY state)
      # Listen on the VM's private IP so the CAE workload subnet can reach us.
      listen-address=__DNS_IP__
      bind-interfaces
      no-resolv
      no-poll
      # Default upstream: Azure DNS (168.63.129.16). Azure DNS knows this
      # VNet is linked to the Private DNS Zone privatelink.azurecr.io and
      # substitutes the PE NIC IP for the ACR CNAME chain.
      #
      # SCENARIO E FAILURE INJECTION (falsify.sh): rewrite this line to
      # `server=8.8.8.8`. dnsmasq then resolves ACR FQDNs through the
      # public DNS chain and returns the public registry IP, which the
      # registry rejects because publicNetworkAccess=Disabled.
      server=168.63.129.16
      # Logging for evidence collection.
      log-queries
      log-facility=/var/log/dnsmasq.log
runcmd:
  - systemctl enable dnsmasq
  - systemctl restart dnsmasq
'''
var dnsmasqCloudInit = replace(dnsmasqCloudInitTemplate, '__DNS_IP__', dnsVmPrivateIp)

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

resource dnsNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: dnsNsgName
  location: location
  properties: {
    securityRules: [
      {
        // DNS from the CAE workload subnet (UDP). UDP is what dnsmasq
        // primarily serves; TCP is allowed below for fallback.
        name: 'allow-dns-udp-from-aca'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Udp'
          sourceAddressPrefix: acaSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: dnsVmPrivateIp
          destinationPortRange: '53'
        }
      }
      {
        name: 'allow-dns-tcp-from-aca'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: acaSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: dnsVmPrivateIp
          destinationPortRange: '53'
        }
      }
      {
        // Deny all other inbound. SSH is deliberately not exposed; the lab
        // uses `az vm run-command invoke` (control-plane RBAC) for all VM
        // operations, so no SSH key or public IP is required.
        name: 'deny-all-inbound'
        properties: {
          priority: 4000
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    // Custom DNS: every NIC in this VNet (including the CAE infrastructure
    // subnet) resolves through the dnsmasq VM. This is what places Scenario
    // E on the lab's critical path.
    dhcpOptions: {
      dnsServers: [
        dnsVmPrivateIp
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
      {
        // DNS forwarder VM subnet.
        name: dnsSubnetName
        properties: {
          addressPrefix: dnsSubnetPrefix
          networkSecurityGroup: {
            id: dnsNsg.id
          }
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

resource dnsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: dnsSubnetName
}

// -----------------------------------------------------------------------------
// DNS forwarder VM (Ubuntu 22.04 + dnsmasq via cloud-init)
// -----------------------------------------------------------------------------

resource dnsNic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: dnsNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: dnsSubnet.id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: dnsVmPrivateIp
        }
      }
    ]
  }
}

resource dnsVm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: dnsVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: dnsVmName
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
      customData: base64(dnsmasqCloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: dnsNic.id
        }
      ]
    }
  }
}

// -----------------------------------------------------------------------------
// Container Registry (Premium, public access disabled)
// -----------------------------------------------------------------------------

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: registryName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    // Force pulls through the Private Endpoint path; reject any public
    // traffic. In Scenario E, DNS returns the public IP and ACR refuses
    // the connection at the TLS layer because the source is internet.
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
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
  // The CAE must be created AFTER the VM is provisioning DNS, otherwise the
  // environment may fail to validate VNet DNS resolution. dependsOn keeps the
  // ordering explicit.
  dependsOn: [
    dnsVm
  ]
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
          // ACR_FQDN is the workload-path probe target. The /probe endpoint in the
          // private image calls socket.getaddrinfo(ACR_FQDN) from inside the replica
          // and reports whether the result is RFC1918 (private = PE NIC, dnsmasq
          // upstream is Azure DNS) or public (dnsmasq upstream bypasses Azure DNS,
          // i.e. Scenario E DNS forwarder bypass). Set from Bicep so the value is
          // wired even before the private image lands.
          env: [
            {
              name: 'ACR_FQDN'
              value: containerRegistry.properties.loginServer
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
output containerAppName string = app.name
output containerAppFqdn string = app.properties.configuration.ingress.fqdn
output containerAppPrincipalId string = app.identity.principalId
output vnetName string = vnet.name
output acaSubnetName string = acaSubnet.name
output peSubnetName string = peSubnet.name
output dnsSubnetName string = dnsSubnet.name
output dnsVmName string = dnsVm.name
output dnsVmPrivateIp string = dnsVmPrivateIp
output privateDnsZoneName string = privateDnsZone.name
output privateEndpointName string = acrPrivateEndpoint.name
