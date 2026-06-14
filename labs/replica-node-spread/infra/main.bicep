targetScope = 'resourceGroup'

// =====================================================================
// Replica node-spread lab — Consumption vs Dedicated D8 distribution
//
// Provisions a single Container Apps environment with TWO workload
// profiles (Consumption + Dedicated D8) and TWO identical diag apps
// (one bound to each profile). The diag app exposes /diag which
// returns kernel signals (boot_id, uptime, machine_id, kernel_release,
// microcode) that act as a proxy for underlying node identity. Replicas
// that share the same kernel context (same boot_id + monotonic uptime)
// are running on the same physical node; replicas with distinct
// boot_id + > 5s boot_time_estimate delta are inferred to be running
// on different physical nodes.
//
// Issue: https://github.com/yeongseon/azure-container-apps-practical-guide/issues/202
// Oracle design review session: ses_14b7919caffe2lB37qNy19bGl5 (APPROVE-WITH-MODIFICATIONS)
//
// Sources:
// - https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
// - https://learn.microsoft.com/en-us/azure/container-apps/plans
// - https://learn.microsoft.com/en-us/azure/container-apps/environment
// =====================================================================

@description('Base name used to derive resource names (lowercase, 3-12 chars).')
@minLength(3)
@maxLength(12)
param baseName string = 'rnslab'

@description('Azure region. Must support Container Apps workload profiles. Issue #202 specifies koreacentral for consistency with companion zone-redundancy lab.')
param location string = resourceGroup().location

@description('Hours until resources should be cleaned up. Stamped as expires-at tag.')
@minValue(1)
@maxValue(168)
param expiryHours int = 24

@description('VNet address space for the lab.')
param vnetAddressPrefix string = '10.60.0.0/16'

@description('Workload-profile subnet prefix. Must be at least /27 for workload profile environments.')
param infrastructureSubnetPrefix string = '10.60.0.0/23'

@description('Container image for both diag apps. Override after building from labs/replica-node-spread/diag/.')
param diagImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Optional ACR name (without ".azurecr.io" suffix) in the same resource group. When set, the deployment grants both apps UAMI AcrPull and wires a registries block so the apps can pull the custom diag image. Leave empty when using the default placeholder diagImage.')
param diagAcrName string = ''

@description('UTC timestamp captured at deployment start.')
param deploymentTime string = utcNow()

// ---------------------------------------------------------------------
// Derived names + common tags
// ---------------------------------------------------------------------

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var expiresAt = dateTimeAdd(deploymentTime, 'PT${expiryHours}H')

var names = {
  vnet: 'vnet-${baseName}-${suffix}'
  subnet: 'snet-aca-${baseName}'
  law: 'log-${baseName}-${suffix}'
  env: 'cae-${baseName}-${suffix}'
  uami: 'id-${baseName}-${suffix}'
  appConsumption: 'app-consumption'
  appDedicated: 'app-dedicated-d8'
}

var commonTags = {
  lab: 'replica-node-spread'
  'expires-at': expiresAt
  managedBy: 'bicep'
  warning: 'lab-resources-delete-after-expiry'
}

// ---------------------------------------------------------------------
// Networking
// ---------------------------------------------------------------------

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: names.vnet
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: names.subnet
        properties: {
          addressPrefix: infrastructureSubnetPrefix
          delegations: [
            {
              name: 'aca-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: names.subnet
  parent: vnet
}

// ---------------------------------------------------------------------
// Observability
// ---------------------------------------------------------------------

resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: names.law
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ---------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.uami
  location: location
  tags: commonTags
}

// Optional: AcrPull on a customer-supplied ACR so the apps can pull
// their custom diag image. Only created when diagAcrName is non-empty.
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource diagAcr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (!empty(diagAcrName)) {
  name: diagAcrName
}

resource uamiAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(diagAcrName)) {
  name: guid(resourceGroup().id, uami.id, acrPullRoleId, diagAcrName)
  scope: diagAcr
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
  }
}

// ---------------------------------------------------------------------
// Container Apps Environment — workload profiles enabled
//   Profile A: Consumption (multi-tenant, shared)
//   Profile B: D8 (Dedicated, 8 vCPU / 32 GiB single-tenant)
// ---------------------------------------------------------------------

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: names.env
  location: location
  tags: commonTags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: subnet.id
      internal: false
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: 'd8-dedicated'
        workloadProfileType: 'D8'
        minimumCount: 1
        maximumCount: 1
      }
    ]
  }
}

// ---------------------------------------------------------------------
// Diag apps — identical image, different workloadProfileName.
//   - app-consumption uses the Consumption (multi-tenant) profile
//   - app-dedicated-d8 uses the d8-dedicated (Dedicated D8) profile
//
// Per Issue #202 design (Oracle-modified, top targets revised after
// empirical D8 capacity-ceiling finding 2026-06-14):
//   - Per-replica resources: 0.25 vCPU / 0.5 Gi (smallest Consumption alloc)
//   - Top scale targets used by trigger.sh: Consumption=30, Dedicated D8=10
//     (D8 ceiling note: a single 8 vCPU / 32 GiB D8 node could not
//     provision N=24 of 0.25 vCPU replicas within the 600s scale window
//     because of system overhead; lab now tops at 10 to fit the 3-repeat
//     protocol)
//   - Bicep maxReplicas headroom remains intentionally wider than the
//     scripted targets so operators can experiment past 30 / 10 manually
//     without redeploying — actual scaling is driven by `scale.sh`
//   - Deployed at min=max=1; scale.sh perturbs both up to top during the
//     experiment so we can reuse the same deployment across all scale steps
// ---------------------------------------------------------------------

resource appConsumption 'Microsoft.App/containerApps@2024-03-01' = {
  name: names.appConsumption
  location: location
  tags: union(commonTags, {
    role: 'subject'
    profile: 'Consumption'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  // Explicit dependsOn ensures AcrPull propagates before the first
  // image pull. Without it, Bicep parallelizes app + roleAssignment
  // creation and the first revision can fail with "401 Unauthorized"
  // from ACR until RBAC propagates (typically 1-5 minutes).
  dependsOn: empty(diagAcrName) ? [] : [
    uamiAcrPull
  ]
  properties: {
    managedEnvironmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: empty(diagAcrName) ? [] : [
        {
          server: '${diagAcrName}.azurecr.io'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'diag'
          image: diagImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          // Probes hit / so the helloworld placeholder image works before
          // the custom diag image is built and re-deployed.
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/'
                port: 8080
              }
              initialDelaySeconds: 2
              periodSeconds: 5
              failureThreshold: 6
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/'
                port: 8080
              }
              periodSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 30
      }
    }
  }
}

resource appDedicated 'Microsoft.App/containerApps@2024-03-01' = {
  name: names.appDedicated
  location: location
  tags: union(commonTags, {
    role: 'subject'
    profile: 'd8-dedicated'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  // See appConsumption for AcrPull race rationale.
  dependsOn: empty(diagAcrName) ? [] : [
    uamiAcrPull
  ]
  properties: {
    managedEnvironmentId: env.id
    workloadProfileName: 'd8-dedicated'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: empty(diagAcrName) ? [] : [
        {
          server: '${diagAcrName}.azurecr.io'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'diag'
          image: diagImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/'
                port: 8080
              }
              initialDelaySeconds: 2
              periodSeconds: 5
              failureThreshold: 6
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/'
                port: 8080
              }
              periodSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 24
      }
    }
  }
}

// ---------------------------------------------------------------------
// Outputs — consumed by scripts and the lab guide
// ---------------------------------------------------------------------

output environmentName string = env.name
output environmentId string = env.id
output logAnalyticsWorkspaceName string = law.name
output logAnalyticsWorkspaceId string = law.id
output uamiResourceId string = uami.id
output uamiClientId string = uami.properties.clientId
output uamiPrincipalId string = uami.properties.principalId
output appConsumptionName string = appConsumption.name
output appConsumptionFqdn string = appConsumption.properties.configuration.ingress.fqdn
output appDedicatedName string = appDedicated.name
output appDedicatedFqdn string = appDedicated.properties.configuration.ingress.fqdn
output expiresAt string = expiresAt
