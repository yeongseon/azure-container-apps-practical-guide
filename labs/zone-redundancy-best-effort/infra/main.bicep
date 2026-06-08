targetScope = 'resourceGroup'

// =====================================================================
// Zone-redundancy best-effort lab — parallel multi-min deployment
//
// Provisions three identical Container Apps with min={2,3,6} inside a
// single zone-redundant Container Apps Environment, plus an audit Job
// that samples replica placement every 5 minutes. The audit data is
// written to Log Analytics so the lab can compute coverage and skew
// statistics against the deployed apps.
//
// Sources:
// - https://learn.microsoft.com/azure/reliability/reliability-container-apps
// - https://learn.microsoft.com/azure/container-apps/how-to-zone-redundancy
// - https://learn.microsoft.com/azure/container-apps/workload-profiles-overview
// =====================================================================

@description('Base name used to derive resource names (lowercase, 3-15 chars).')
@minLength(3)
@maxLength(15)
param baseName string = 'zrlab'

@description('Azure region. Must support Container Apps workload profiles AND availability zones.')
param location string = resourceGroup().location

@description('Hours until resources should be cleaned up. Stamped as expires-at tag.')
@minValue(1)
@maxValue(168)
param expiryHours int = 48

@description('VNet address space for the lab.')
param vnetAddressPrefix string = '10.50.0.0/16'

@description('Workload-profile subnet prefix. Must be at least /27 for workload profile environments.')
param infrastructureSubnetPrefix string = '10.50.0.0/23'

@description('Container image for all three subject apps. Default uses the helloworld sample.')
param appImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container image for the audit job. Override after building from labs/zone-redundancy-best-effort/audit/.')
param auditImage string = 'mcr.microsoft.com/azure-cli:2.83.0'

@description('Optional Azure Container Registry name (without ".azurecr.io" suffix) in the same resource group. When set, the deployment grants the audit Job UAMI AcrPull on this registry and wires a registries block so the Job can pull the custom audit image. Leave empty when using the default placeholder auditImage.')
param auditAcrName string = ''

@description('UTC timestamp captured at deployment start. Required as a parameter because utcNow() is only valid as a parameter default.')
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
  jobName: 'audit-sampler'
}

// Three identical subject apps with deliberately different minReplicas.
var subjectApps = [
  {
    name: 'app-min2'
    minReplicas: 2
  }
  {
    name: 'app-min3'
    minReplicas: 3
  }
  {
    name: 'app-min6'
    minReplicas: 6
  }
]

var commonTags = {
  lab: 'zone-redundancy-best-effort'
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
    retentionInDays: 90
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

// Reader role on the resource group so the audit Job can enumerate
// replicas via the ARM REST API.
var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

resource uamiReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, uami.id, readerRoleId)
  scope: resourceGroup()
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
  }
}

// Optional: AcrPull on a customer-supplied ACR so the audit Job can pull
// its custom image. Only created when auditAcrName is non-empty.
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource auditAcr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (!empty(auditAcrName)) {
  name: auditAcrName
}

resource uamiAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(auditAcrName)) {
  name: guid(resourceGroup().id, uami.id, acrPullRoleId, auditAcrName)
  scope: auditAcr
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
  }
}

// ---------------------------------------------------------------------
// Container Apps Environment — zone-redundant + workload profile
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
    zoneRedundant: true
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// ---------------------------------------------------------------------
// Subject apps — identical except for minReplicas
// ---------------------------------------------------------------------

resource apps 'Microsoft.App/containerApps@2024-03-01' = [for app in subjectApps: {
  name: app.name
  location: location
  tags: union(commonTags, {
    role: 'subject'
    minReplicas: string(app.minReplicas)
  })
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
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'app'
          image: appImage
          // Explicit requests + limits (per MS Learn guidance) so the
          // scheduler is not handed an underspecified placement decision.
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/'
                port: 80
              }
              initialDelaySeconds: 2
              periodSeconds: 5
              failureThreshold: 6
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/'
                port: 80
              }
              periodSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/'
                port: 80
              }
              periodSeconds: 30
              failureThreshold: 3
            }
          ]
        }
      ]
      // Autoscale is intentionally disabled (min == max) so placement
      // statistics are not confounded by scale events during the audit
      // window.
      scale: {
        minReplicas: app.minReplicas
        maxReplicas: app.minReplicas
      }
    }
  }
}]

// ---------------------------------------------------------------------
// Audit Job — samples replica placement every 5 minutes
// ---------------------------------------------------------------------

resource auditJob 'Microsoft.App/jobs@2024-03-01' = {
  name: names.jobName
  location: location
  tags: union(commonTags, {
    role: 'audit'
  })
  dependsOn: [
    uamiReader
    uamiAcrPull
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: 180
      replicaRetryLimit: 1
      scheduleTriggerConfig: {
        cronExpression: '*/5 * * * *'
        parallelism: 1
        replicaCompletionCount: 1
      }
      // Registries block is only needed when pulling from a private ACR.
      // We always emit the array shape but leave it empty when no ACR
      // was supplied, so the Job validates against the public default
      // auditImage.
      registries: empty(auditAcrName) ? [] : [
        {
          server: '${auditAcrName}.azurecr.io'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'audit'
          image: auditImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: uami.properties.clientId
            }
            {
              name: 'SUBSCRIPTION_ID'
              value: subscription().subscriptionId
            }
            {
              name: 'RESOURCE_GROUP'
              value: resourceGroup().name
            }
            {
              name: 'ENVIRONMENT_NAME'
              value: env.name
            }
            {
              name: 'SUBJECT_APPS'
              value: 'app-min2,app-min3,app-min6'
            }
            {
              name: 'API_VERSION'
              value: '2024-03-01'
            }
          ]
          // The default `auditImage` is `mcr.microsoft.com/azure-cli` so
          // the deployment succeeds even before the user builds the
          // custom audit image. When no custom ACR is wired (`auditAcrName`
          // empty), override command/args with a placeholder echo so the
          // Job emits an explicit `AuditPlaceholder` notice instead of
          // running the azure-cli default ENTRYPOINT. When a custom ACR
          // is provided, assume the image's own ENTRYPOINT (sample.sh)
          // should run, so leave command/args unset.
          command: empty(auditAcrName) ? [
            '/bin/sh'
            '-c'
          ] : []
          args: empty(auditAcrName) ? [
            'echo {\\"event\\":\\"AuditPlaceholder\\",\\"note\\":\\"Override auditImage parameter with the built sample.sh image to begin sampling\\"}'
          ] : []
        }
      ]
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
output subjectAppNames array = [for (app, i) in subjectApps: apps[i].name]
output subjectAppFqdns array = [for (app, i) in subjectApps: apps[i].properties.configuration.ingress.fqdn]
output auditJobName string = auditJob.name
output expiresAt string = expiresAt
