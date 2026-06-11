targetScope = 'resourceGroup'

// =====================================================================
// replica-node-spread lab — Consumption vs Dedicated D8 spread test
//
// Provisions one Container Apps Environment with TWO workload profiles
// (Consumption + Dedicated D8 capped at minimumCount=1, maximumCount=1)
// and TWO identical Container Apps that differ only in the workload
// profile they target. The apps run a tiny bash diag image that exposes
// boot_id / uptime / microcode via `az containerapp exec`, so the lab
// can compare how N replicas distribute across underlying shared-kernel
// contexts on each profile.
//
// Sources (all Microsoft Learn):
// - https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
// - https://learn.microsoft.com/en-us/azure/container-apps/plans
// - https://learn.microsoft.com/en-us/azure/container-apps/environment
// =====================================================================

@description('Base name used to derive resource names (lowercase, 3-15 chars).')
@minLength(3)
@maxLength(15)
param baseName string = 'rnslab'

@description('Azure region. Must support Container Apps workload profiles AND the D8 SKU.')
param location string = resourceGroup().location

@description('Hours until resources should be cleaned up. Stamped as expires-at tag.')
@minValue(1)
@maxValue(168)
param expiryHours int = 24

@description('Container image used by both subject apps. Override after building from labs/replica-node-spread/app/.')
param diagImage string = 'mcr.microsoft.com/azure-cli:2.83.0'

@description('Optional Azure Container Registry name (without ".azurecr.io" suffix) in the same RG. When set, both apps wire a registries block so they can pull the custom diag image. Leave empty before the image is built.')
param diagAcrName string = ''

@description('Initial minReplicas/maxReplicas for the Consumption app. Scale tests later override these via az containerapp update.')
param consumptionInitialReplicas int = 1

@description('Initial minReplicas/maxReplicas for the Dedicated D8 app.')
param dedicatedInitialReplicas int = 1

@description('Per-replica CPU (cores). 0.25 is the smallest Consumption-valid allocation.')
param replicaCpu string = '0.25'

@description('Per-replica memory.')
param replicaMemory string = '0.5Gi'

@description('Dedicated workload profile SKU. D8 chosen because D4 cannot fit the planned 24-replica top scale (24 * 0.25 vCPU = 6 vCPU > D4 4 vCPU).')
@allowed([
  'D4'
  'D8'
  'D16'
  'D32'
])
param dedicatedProfileType string = 'D8'

@description('Minimum dedicated node count. Hard-pinned to 1 for this experiment so concentration vs spread is directly observable.')
@minValue(1)
@maxValue(1)
param dedicatedMinimumCount int = 1

@description('Maximum dedicated node count. Hard-pinned to 1 to prevent auto-scale from confounding the result. Replicas that do not fit will fail to start, which is itself an experimental signal.')
@minValue(1)
@maxValue(1)
param dedicatedMaximumCount int = 1

@description('UTC timestamp captured at deployment start. Required as a parameter because utcNow() is only valid as a parameter default.')
param deploymentTime string = utcNow()

// ---------------------------------------------------------------------
// Derived names + common tags
// ---------------------------------------------------------------------

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var expiresAt = dateTimeAdd(deploymentTime, 'PT${expiryHours}H')

var names = {
  law: 'log-${baseName}-${suffix}'
  env: 'cae-${baseName}-${suffix}'
  uami: 'id-${baseName}-${suffix}'
  consumptionApp: 'ca-diag-consumption'
  dedicatedApp: 'ca-diag-dedicated'
  dedicatedProfile: 'dedicated-${toLower(dedicatedProfileType)}'
}

var commonTags = {
  lab: 'replica-node-spread'
  'expires-at': expiresAt
  managedBy: 'bicep'
  warning: 'lab-resources-delete-after-expiry'
}

// ---------------------------------------------------------------------
// Observability — kept minimal (stdout flows to LAW for debug only;
// the experiment captures evidence via az containerapp exec, not KQL).
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
// Identity + ACR wiring (optional, only when diagAcrName is supplied)
// ---------------------------------------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.uami
  location: location
  tags: commonTags
}

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
// Container Apps Environment — workload profiles, NO VNet integration
// (kept simple; the experiment tests scheduling within a single env)
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
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: names.dedicatedProfile
        workloadProfileType: dedicatedProfileType
        minimumCount: dedicatedMinimumCount
        maximumCount: dedicatedMaximumCount
      }
    ]
  }
}

// ---------------------------------------------------------------------
// Reusable container template — identical between the two apps.
// Defines ENTRYPOINT-style `tail -f /dev/null` (the image's own
// ENTRYPOINT keeps the process alive; we exec the diag.sh on demand).
// ---------------------------------------------------------------------

var containerTemplate = {
  name: 'diag'
  image: diagImage
  resources: {
    cpu: json(replicaCpu)
    memory: replicaMemory
  }
  // No probes: we want fast scale-up so replica count stabilizes
  // quickly during the scale-sequence experiment. Health is verified
  // out-of-band by sample.sh.
}

// ---------------------------------------------------------------------
// Consumption-profile app
// ---------------------------------------------------------------------

resource consumptionApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: names.consumptionApp
  location: location
  tags: union(commonTags, {
    profile: 'Consumption'
    role: 'subject'
  })
  dependsOn: [
    uamiAcrPull
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      registries: empty(diagAcrName) ? [] : [
        {
          server: '${diagAcrName}.azurecr.io'
          identity: uami.id
        }
      ]
      // No ingress: this is a diag worker, not a public service.
      // `az containerapp exec` works without ingress.
    }
    template: {
      containers: [
        containerTemplate
      ]
      scale: {
        minReplicas: consumptionInitialReplicas
        maxReplicas: consumptionInitialReplicas
      }
    }
  }
}

// ---------------------------------------------------------------------
// Dedicated-profile app (D8 by default, single node pinned)
// ---------------------------------------------------------------------

resource dedicatedApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: names.dedicatedApp
  location: location
  tags: union(commonTags, {
    profile: dedicatedProfileType
    role: 'subject'
  })
  dependsOn: [
    uamiAcrPull
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: env.id
    workloadProfileName: names.dedicatedProfile
    configuration: {
      activeRevisionsMode: 'Single'
      registries: empty(diagAcrName) ? [] : [
        {
          server: '${diagAcrName}.azurecr.io'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        containerTemplate
      ]
      scale: {
        minReplicas: dedicatedInitialReplicas
        maxReplicas: dedicatedInitialReplicas
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
output uamiResourceId string = uami.id
output uamiClientId string = uami.properties.clientId
output consumptionAppName string = consumptionApp.name
output dedicatedAppName string = dedicatedApp.name
output dedicatedProfileName string = names.dedicatedProfile
output dedicatedProfileType string = dedicatedProfileType
output expiresAt string = expiresAt
