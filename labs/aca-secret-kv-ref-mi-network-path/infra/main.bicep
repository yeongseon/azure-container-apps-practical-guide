targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// aca-secret-kv-ref-mi-network-path — infrastructure
// -----------------------------------------------------------------------------
//
// Reproduces the customer failure:
//   az containerapp secret set --identity system --key-vault-url https://<kv>.vault.azure.net/secrets/<name>
//     -> Failed to update secrets
//     -> Unable to get value using Managed identity
//     -> Get https://login.microsoftonline.com/<tenant>/.well-known/openid-configuration EOF
//
// Hypothesis: When ACA control plane validates a Key Vault secret reference
// with `--identity system`, the OIDC discovery call to Microsoft Entra ID
// authority (login.microsoftonline.com) traverses the CUSTOMER SUBNET egress
// path. If a UDR forces that egress through Azure Firewall and the firewall
// does not have an Application Rule allowing the Entra authority FQDNs, the
// discovery call is denied and the secret set fails at OIDC-discovery time —
// BEFORE any token is issued.
//
// Controlled variable: one named Application Rule allowing BOTH
//     login.microsoftonline.com
//     login.microsoft.com
// Baseline (H0) and recovery (H2): rule present -> `secret set` succeeds.
// H1: rule removed (via falsify.sh)     -> `secret set` fails with EOF.
// H2: rule re-added                     -> `secret set` succeeds.
//
// Anti-patterns deliberately avoided (per Oracle architecture review):
//   - No ACR in this lab — image pull uses a public MCR image so ACR is not
//     a confounding variable.
//   - No AzureActiveDirectory service-tag network rule — that broad allow
//     would let Entra traffic pass EVEN WHEN the Application Rule is removed,
//     silently defeating H1.
//   - No wildcard rules on *.microsoft.com or *.microsoftonline.com — same
//     silent-bypass risk.
//   - No revision-based gating — secret updates do not create new revisions,
//     so the silence gate proves latestReadyRevisionName is unchanged and
//     ingress health stays green rather than counting revision events.

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

@description('AzureFirewallSubnet prefix (Azure Firewall Basic requires /26 or larger; name MUST be exactly AzureFirewallSubnet)')
param firewallSubnetPrefix string = '10.90.2.0/26'

@description('AzureFirewallManagementSubnet prefix (Azure Firewall Basic requires this dedicated subnet in addition to AzureFirewallSubnet)')
param firewallManagementSubnetPrefix string = '10.90.2.64/26'

@description('Public MCR image used as the lab workload — no ACR is needed for this lab because the network path being tested is KV secret-reference validation, not image pull.')
param placeholderImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Object ID (principalId) of the identity running the deployment. Required so the deployment can grant itself Key Vault Secrets Officer at the KV scope, which is needed by trigger.sh to write the KV secret value that the app then references.')
param deploymentPrincipalId string

@description('Principal type of deploymentPrincipalId. Use "User" for an interactive az login, "ServicePrincipal" for CI/CD.')
@allowed([
  'User'
  'ServicePrincipal'
])
param deploymentPrincipalType string = 'User'

// -----------------------------------------------------------------------------
// Naming
// -----------------------------------------------------------------------------

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var appName = 'ca-${baseName}-${suffix}'
var vnetName = 'vnet-${baseName}-${suffix}'
var acaSubnetName = 'snet-aca'
var firewallSubnetName = 'AzureFirewallSubnet'
var firewallManagementSubnetName = 'AzureFirewallManagementSubnet'
var firewallName = 'afw-${baseName}-${suffix}'
var firewallPublicIpName = 'pip-${firewallName}'
var firewallManagementPublicIpName = '${firewallPublicIpName}-mgmt'
var firewallPolicyName = 'afwp-${baseName}-${suffix}'
var routeTableName = 'rt-${baseName}-${suffix}'
var defaultRouteName = 'default-via-afw'
// KV name must be 3-24 chars, alphanumeric + dashes. We omit dashes to
// preserve character budget for the suffix.
var keyVaultName = take('kv${baseName}${suffix}', 24)
var keyVaultDataPlaneFqdn = '${keyVaultName}.vault.azure.net'

// Built-in role definition IDs
// Reference: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
var kvSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer

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
// Layout:
//   VNet                                10.90.0.0/16
//     snet-aca                          10.90.0.0/23   (delegated to Microsoft.App/environments)
//     AzureFirewallSubnet               10.90.2.0/26   (Firewall Basic data plane)
//     AzureFirewallManagementSubnet     10.90.2.64/26  (Firewall Basic mgmt plane)
//
// The VNet uses default Azure DNS (no dhcpOptions.dnsServers). DNS is NOT
// the controlled variable in this lab — Firewall Application Rule presence
// for the Entra authority FQDNs is.

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
        // The route table is attached inline here so the UDR is present the
        // moment the subnet exists — the ACA env creation later will use
        // this subnet, and its egress will already be routed through the
        // firewall private IP.
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
        // Azure Firewall subnet — name MUST be exactly 'AzureFirewallSubnet'.
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

// Firewall Basic requires both a management public IP and a separate
// management subnet (name MUST be exactly 'AzureFirewallManagementSubnet').
// Standard/Premium tiers do not require the management subnet.
// Reference: https://learn.microsoft.com/en-us/azure/firewall/deploy-firewall-basic-portal-policy
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
    // The next-hop IP MUST be Azure Firewall's actual
    // ipConfigurations[0].properties.privateIPAddress. Computing this from
    // the subnet CIDR (e.g. cidrHost('10.90.2.0/26', 0)) returns the
    // Azure-reserved gateway address (.1), not the firewall instance
    // address (.4 in this layout because Azure reserves .0/.1/.2/.3).
    // Hard-coding ".4" happens to work for /26 today but breaks if the
    // subnet is moved or resized; reading the resource property is correct
    // in all cases.
    nextHopIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
  }
}

// -----------------------------------------------------------------------------
// Azure Firewall (Basic SKU) + Firewall Policy
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

resource firewallManagementPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: firewallManagementPublicIpName
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

// Application Rules — the ONLY controlled surface for this lab.
//
// We deliberately do NOT declare any Network Rule collection with the
// AzureActiveDirectory service tag or the AzureKeyVault service tag on 443.
// Doing so would allow Entra / KV traffic to pass EVEN AFTER the Application
// Rule for the Entra authority is removed by falsify.sh, silently defeating
// H1. All Azure identity + KV data-plane egress from snet-aca is required
// to match one of the Application Rules below, or the firewall denies it.
resource firewallAppRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-01-01' = {
  name: 'aca-kv-entra-application'
  parent: firewallPolicy
  properties: {
    priority: 200
    ruleCollections: [
      {
        // Platform-required FQDNs for image pull and Container Apps runtime.
        // Kept as a SEPARATE collection from the Entra rule so falsify.sh
        // can toggle Entra without touching platform rules.
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-platform-dependencies'
        priority: 210
        action: {
          type: 'Allow'
        }
        rules: [
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
          {
            // Key Vault data-plane FQDN for THIS lab's KV instance.
            // Kept OPEN throughout the lab so the failure mode is
            // exclusively at the OIDC-discovery step, not at KV reach.
            ruleType: 'ApplicationRule'
            name: 'allow-kv-data-plane'
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
              keyVaultDataPlaneFqdn
            ]
          }
        ]
      }
      {
        // THE CONTROLLED VARIABLE.
        //
        // One collection, one rule, two FQDNs. falsify.sh removes this
        // ENTIRE rule collection to reproduce H1, and re-applies it to
        // reproduce H2. Keeping the two FQDNs together in a single rule
        // guarantees H1 is one atomic remove — no partial removal that
        // could accidentally leave one of the two hosts reachable.
        //
        // login.microsoftonline.com  — the FQDN that surfaces in the
        //                              customer error string.
        // login.microsoft.com        — the FQDN that Microsoft Learn
        //                              documents as the primary login
        //                              endpoint for KV secret refs
        //                              (see manage-secrets doc).
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-entra-authority'
        priority: 220
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-entra-login'
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
              'login.microsoftonline.com'
              'login.microsoft.com'
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
// appears in LAW, making the smoking-gun evidence (Deny row naming
// login.microsoftonline.com) impossible to capture.
//
// logAnalyticsDestinationType MUST be 'Dedicated' (NOT the legacy default
// 'AzureDiagnostics') so logs land in resource-specific tables —
// AZFWApplicationRule, AZFWNetworkRule, AZFWDnsQuery — instead of the
// generic 'AzureDiagnostics' table. falsify.sh queries
// `AZFWApplicationRule | where Fqdn has "login.microsoftonline.com"` for the
// smoking-gun Deny row; that table only exists in the Dedicated schema.
// In the legacy schema, the same data lives in
// `AzureDiagnostics | where Category == "AzureFirewallApplicationRule"` with
// column names like `msg_s` instead of `Fqdn`. falsify.sh falls back to that
// shape as a compatibility hedge, but the Dedicated schema is the primary
// path and the one we design for.
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
// Key Vault (Standard, RBAC-authorized)
// -----------------------------------------------------------------------------
//
// Public network access is Enabled at the KV firewall level because the ACA
// subnet reaches KV over the public data-plane FQDN through Azure Firewall.
// Using a Private Endpoint here would eliminate the firewall path entirely
// and change what the lab is testing. That variant is a separate design.

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
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

// -----------------------------------------------------------------------------
// Container Apps Environment + App (system-assigned MI, MCR placeholder image)
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

// -----------------------------------------------------------------------------
// RBAC — grant KV data-plane access
// -----------------------------------------------------------------------------
//
// Two role assignments at the KV scope:
//   1. Key Vault Secrets User -> app system-assigned MI
//        Needed so ACA control plane's KV secret reference resolution can
//        read the secret value on behalf of the app.
//   2. Key Vault Secrets Officer -> deployment identity (operator)
//        Needed so trigger.sh can write kvref-h0 / kvref-h1 / kvref-h2
//        secret values using the operator's identity.
//
// Note: RBAC propagation on Key Vault typically takes 30-120 seconds. Both
// trigger.sh and falsify.sh include a wait-with-retry step before their
// first KV operation to absorb that lag.

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

// -----------------------------------------------------------------------------
// Outputs — consumed by trigger.sh / verify.sh / falsify.sh
// -----------------------------------------------------------------------------

output resourceGroupName string = resourceGroup().name
output location string = location
output appName string = appName
output environmentName string = environmentName
output firewallName string = firewallName
output firewallPolicyName string = firewallPolicyName
output firewallPublicIpName string = firewallPublicIpName
output firewallPublicIpAddress string = firewallPublicIp.properties.ipAddress
output vnetName string = vnetName
output acaSubnetName string = acaSubnetName
output acaSubnetPrefix string = acaSubnetPrefix
output logAnalyticsName string = logAnalyticsName
// Workspace customer ID (GUID) for `az monitor log-analytics query --workspace`.
// falsify.sh uses this to query AZFWApplicationRule for the smoking-gun
// Deny row naming login.microsoftonline.com.
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
output keyVaultName string = keyVaultName
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultDataPlaneFqdn string = keyVaultDataPlaneFqdn
output appPrincipalId string = app.identity.principalId
// Firewall Application Rule collection name that H1 removes and H2 re-adds.
// falsify.sh addresses this by name.
output entraAuthorityRuleCollectionName string = 'allow-entra-authority'
output entraAuthorityRuleName string = 'allow-entra-login'
