targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// aca-secret-kv-ref-mi-network-path-h4f — infrastructure
// -----------------------------------------------------------------------------
//
// Reproduces the H4f variant for the customer failure:
//   az containerapp secret set --secrets <name>=keyvaultref:https://<kv>.vault.azure.net/secrets/<name>,identityref:system
//     -> Failed to update secrets
//     -> Unable to get value using Managed identity
//     -> OpenID Connect / openid-configuration failure with a connectivity clue
//
// H4f deliberately keeps the same app / KV / identity / RBAC / ingress / revision
// cohort as H4c, but swaps the network mechanism:
//   - A route table sends 0.0.0.0/0 from the ACA workload subnet to a Linux VM
//     private IP used as an NVA surrogate.
//   - The VM has Azure NIC IP forwarding enabled, OS IP forwarding enabled,
//     rp_filter disabled, and nftables NAT/masquerade configured by cloud-init.
//   - There is NO Azure Firewall, NO Firewall Policy, NO TLS inspection,
//     NO NSG deny trigger, and NO custom DNS override.
//
// The ONLY controlled variable is a forwarding-plane nftables DROP rule on the
// VM for outbound tcp/443 to AzureActiveDirectory service-tag prefixes:
//   H0 baseline: route table + VM forwarding/NAT present, no DROP rule.
//   H1 trigger:  DROP rule present -> secret set fails.
//   H2 fix:      DROP rule removed -> secret set succeeds again.

@description('Base name for all resources (lowercase letters and digits only, 3-11 chars). KV name = "kv<baseName><6-char-suffix>", max 24 chars total.')
@minLength(3)
@maxLength(11)
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('VNet address space for the lab')
param vnetAddressPrefix string = '10.90.0.0/16'

@description('Container Apps workload-profile subnet prefix (must be at least /23)')
param acaSubnetPrefix string = '10.90.0.0/23'

@description('Subnet prefix for the Linux forwarding VM used as the H4f NVA surrogate')
param nvaSubnetPrefix string = '10.90.2.0/27'

@description('Public MCR image used as the lab workload — no ACR is needed for this lab because the network path being tested is KV secret-reference validation, not image pull.')
param placeholderImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Object ID (principalId) of the identity running the deployment. Required so the deployment can grant itself Key Vault Secrets Officer at the KV scope, which is needed by trigger.sh / falsify.sh to write the KV secret values that the app then references.')
param deploymentPrincipalId string

@description('Principal type of deploymentPrincipalId. Use "User" for an interactive az login, "ServicePrincipal" for CI/CD.')
@allowed([
  'User'
  'ServicePrincipal'
])
param deploymentPrincipalType string = 'User'

@description('Admin username for the Linux forwarding VM. No SSH step is documented; the lab uses az vm run-command invoke for VM-side state changes.')
param nvaVmAdminUsername string = 'azureuser'

@secure()
@description('Admin password for the Linux forwarding VM. Azure requires a credential at provision time even though the lab uses az vm run-command invoke instead of SSH.')
param nvaVmAdminPassword string

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var appName = 'ca-${baseName}-${suffix}'
var vnetName = 'vnet-${baseName}-${suffix}'
var acaSubnetName = 'snet-aca'
var nvaSubnetName = 'snet-nva'
var nsgName = 'nsg-${baseName}-${suffix}'
var nvaNsgName = 'nsg-nva-${baseName}-${suffix}'
var routeTableName = 'rt-${baseName}-${suffix}'
var defaultRouteName = 'default-via-nva-h4f'
var keyVaultName = take('kv${baseName}${suffix}', 24)
var keyVaultDataPlaneFqdn = '${keyVaultName}.vault.azure.net'
var nvaVmName = 'vmnva-${baseName}-${suffix}'
var nvaNicName = 'nic-${nvaVmName}'
var nvaPublicIpName = 'pip-${nvaVmName}'
var tenantId = subscription().tenantId
var kvSecretsUserRoleId = '4633458b-17de-4321-be99-e39f9d67d7dd'
var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
var nvaBootstrap = '''#cloud-config
package_update: true
packages:
  - nftables
  - jq
write_files:
  - path: /usr/local/sbin/h4f-nva-bootstrap.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -euo pipefail
      cat >/etc/sysctl.d/99-h4f-nva.conf <<'EOF'
      net.ipv4.ip_forward=1
      net.ipv4.conf.all.rp_filter=0
      net.ipv4.conf.default.rp_filter=0
      net.ipv4.conf.eth0.rp_filter=0
      EOF
      sysctl --system >/dev/null
      cat >/etc/nftables.conf <<'EOF'
      flush ruleset
      table inet h4f {
        chain forward {
          type filter hook forward priority filter; policy accept;
          ct state established,related accept
        }
      }
      table ip nat {
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ip saddr ${acaSubnetPrefix} oifname "eth0" masquerade
        }
      }
      EOF
      systemctl enable nftables
      nft -f /etc/nftables.conf
runcmd:
  - [ /usr/local/sbin/h4f-nva-bootstrap.sh ]
'''

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

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  properties: {}
}

// NSG for the NVA-surrogate subnet. The VM has a Standard public IP so it has an
// outbound path to the Internet for NAT/masquerade of forwarded ACA egress. This
// NSG closes the inbound attack surface: because Azure NSGs are stateful, return
// traffic for connections the VM initiates (the masqueraded NAT flows) is allowed,
// while NEW inbound connections from the Internet — notably SSH/22, which the VM
// still runs with password auth — are denied. The lab drives the VM exclusively
// through `az vm run-command invoke` (VM agent), so no inbound SSH is required.
//
// This NSG is a management-plane boundary on the NVA subnet only. It is NOT the
// H4f "NSG deny trigger" confounder: the ACA workload subnet's NSG (nsg) stays
// empty and nsgDenyPresent remains false, so the H1<->H2 controlled variable is
// still solely the nftables forwarding-plane DROP rule.
resource nvaNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nvaNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllInboundFromInternet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny new inbound connections from the Internet (including SSH/22). Stateful NSG still allows NAT return traffic for VM-initiated forwarded flows.'
        }
      }
    ]
  }
}

resource routeTable 'Microsoft.Network/routeTables@2024-01-01' = {
  name: routeTableName
  location: location
  properties: {
    disableBgpRoutePropagation: true
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
    subnets: [
      {
        name: acaSubnetName
        properties: {
          addressPrefix: acaSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          routeTable: {
            id: routeTable.id
          }
          delegations: [
            {
              name: 'aca-env-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: nvaSubnetName
        properties: {
          addressPrefix: nvaSubnetPrefix
          networkSecurityGroup: {
            id: nvaNsg.id
          }
        }
      }
    ]
  }
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: acaSubnetName
  parent: vnet
}

resource nvaSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: nvaSubnetName
  parent: vnet
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: null
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource nvaPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: nvaPublicIpName
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

resource nvaNic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: nvaNicName
  location: location
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: nvaSubnet.id
          }
          publicIPAddress: {
            id: nvaPublicIp.id
          }
        }
      }
    ]
  }
}

resource nvaVm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: nvaVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: nvaVmName
      adminUsername: nvaVmAdminUsername
      adminPassword: nvaVmAdminPassword
      customData: base64(nvaBootstrap)
      linuxConfiguration: {
        disablePasswordAuthentication: false
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
      }
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
        diskSizeGB: 30
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nvaNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource defaultRoute 'Microsoft.Network/routeTables/routes@2024-01-01' = {
  name: defaultRouteName
  parent: routeTable
  properties: {
    addressPrefix: '0.0.0.0/0'
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: nvaNic.properties.ipConfigurations[0].properties.privateIPAddress
  }
}

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
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
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

resource kvSecretsUserForApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, app.id, kvSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleId)
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource kvSecretsOfficerForDeployer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, deploymentPrincipalId, kvSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsOfficerRoleId)
    principalId: deploymentPrincipalId
    principalType: deploymentPrincipalType
  }
}

output resourceGroupName string = resourceGroup().name
output tenantId string = tenantId
output location string = location
output appName string = appName
output environmentName string = environmentName
output vnetName string = vnetName
output acaSubnetName string = acaSubnetName
output acaSubnetPrefix string = acaSubnetPrefix
output nvaSubnetName string = nvaSubnetName
output nvaSubnetPrefix string = nvaSubnetPrefix
output logAnalyticsName string = logAnalyticsName
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
output keyVaultName string = keyVaultName
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultDataPlaneFqdn string = keyVaultDataPlaneFqdn
output appPrincipalId string = app.identity.principalId
output nsgAttached bool = true
output nsgName string = nsgName
output nvaSubnetNsgAttached bool = true
output nvaSubnetNsgName string = nvaNsgName
output routeTableAttached bool = true
output routeTableName string = routeTableName
output routeTableDefaultRouteName string = defaultRouteName
output routeTableDefaultNextHopType string = 'VirtualAppliance'
output nvaSurrogatePresent bool = true
output nvaSurrogateType string = 'linux_forwarding_vm'
output nvaVmName string = nvaVmName
output nvaNicName string = nvaNicName
output nvaPublicIpName string = nvaPublicIpName
output nvaPrivateIp string = nvaNic.properties.ipConfigurations[0].properties.privateIPAddress
output nvaNicIpForwardingEnabled bool = true
output nvaOsIpForwardingEnabled bool = true
output nvaNatEnabled bool = true
output azureFirewallPresent bool = false
output firewallPolicyPresent bool = false
output tlsInspectionConfigured bool = false
output usesAzureProvidedDns bool = true
output nsgDenyPresent bool = false
output dnsOverridePresent bool = false
output vwanRoutingIntentPresent bool = false
