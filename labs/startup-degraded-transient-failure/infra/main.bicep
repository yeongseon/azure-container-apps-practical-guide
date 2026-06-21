targetScope = 'resourceGroup'

// =====================================================================
// Startup-degraded transient-failure lab (issue #205)
//
// Provisions a single subject Container App with a deterministic 25-second
// startup delay (custom Python image) and three identical replicas, plus
// three Container Apps Jobs:
//
//   audit-sampler            5-minute cron, ReplicaInventorySample +
//                            RevisionStateSample.
//   perturbation-sampler     Manual trigger, 5-second cadence around each
//                            perturbation event (10-minute window).
//   loadgen-k6               Manual trigger, k6 sustains 200 RPS against
//                            the subject app for a parameterized duration.
//
// Lab design binding:
// - Subject probes target /healthz (not /).
// - Primary perturbation is an ACA-managed new revision rollout, NOT
//   `az containerapp revision restart`.
// - High-frequency perturbation sampling is mandatory; 5-minute audit
//   alone is too coarse for a 10-second-bucket transition lab.
//
// Sources:
// - https://learn.microsoft.com/en-us/azure/container-apps/health-probes
// - https://learn.microsoft.com/en-us/azure/container-apps/revisions
// - https://learn.microsoft.com/en-us/azure/container-apps/jobs
// - https://learn.microsoft.com/en-us/azure/container-apps/planned-maintenance
// =====================================================================

@description('Base name used to derive resource names (lowercase, 3-15 chars).')
@minLength(3)
@maxLength(15)
param baseName string = 'sdlab'

@description('Azure region. Must support Container Apps workload profiles.')
param location string = resourceGroup().location

@description('Hours until resources should be cleaned up. Stamped as expires-at tag.')
@minValue(1)
@maxValue(168)
param expiryHours int = 48

@description('VNet address space for the lab.')
param vnetAddressPrefix string = '10.60.0.0/16'

@description('Workload-profile subnet prefix. Must be at least /27 for workload profile environments.')
param infrastructureSubnetPrefix string = '10.60.0.0/23'

@description('Container image for the subject app. Default is the public azurelinux Python base, which will only print the entrypoint help until the custom subject image is built. Override with the custom image tag after building from labs/startup-degraded-transient-failure/subject/.')
param subjectImage string = 'mcr.microsoft.com/azurelinux/base/python:3.12'

@description('Optional Azure Container Registry name (without ".azurecr.io" suffix). When set, the deployment grants the UAMI AcrPull and wires the registry into all three Jobs so they can pull custom images.')
param acrName string = ''

@description('Container image for the audit Job. Defaults to a placeholder; override with the custom image after building from labs/startup-degraded-transient-failure/audit/.')
param auditImage string = 'mcr.microsoft.com/azure-cli:2.83.0'

@description('Container image for the perturbation-sampler Job. Defaults to a placeholder; override with the custom image after building from labs/startup-degraded-transient-failure/perturbation-sampler/.')
param perturbationSamplerImage string = 'mcr.microsoft.com/azure-cli:2.83.0'

@description('Container image for the k6 loadgen Job. Defaults to the public grafana/k6 image without the bundled k6-script.js; override with the custom image after building from labs/startup-degraded-transient-failure/loadgen/.')
param loadgenImage string = 'grafana/k6:0.50.0'

@description('Deterministic startup delay (seconds) for the subject app PID 1.')
@minValue(0)
@maxValue(120)
param subjectStartupDelaySeconds int = 25

@description('Artificial per-request work delay (milliseconds) for the subject app `/` path. Set non-zero to consume per-replica headroom during preflight calibration.')
@minValue(0)
@maxValue(5000)
param subjectRequestDelayMs int = 0

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
  subjectApp: 'subject-app'
  auditJob: 'audit-sampler'
  perturbationSamplerJob: 'perturbation-sampler'
  loadgenJob: 'loadgen-k6'
}

var subjectAppName = names.subjectApp

var commonTags = {
  lab: 'startup-degraded-transient-failure'
  'expires-at': expiresAt
  managedBy: 'bicep'
  warning: 'lab-resources-delete-after-expiry'
  issue: '205'
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
// Identity + role assignments
// ---------------------------------------------------------------------

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.uami
  location: location
  tags: commonTags
}

// Reader on the resource group so the audit and perturbation-sampler
// Jobs can enumerate revisions and replicas via the ARM REST API.
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

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (!empty(acrName)) {
  name: acrName
}

resource uamiAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(acrName)) {
  name: guid(resourceGroup().id, uami.id, acrPullRoleId, acrName)
  scope: acr
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
  }
}

// ---------------------------------------------------------------------
// Container Apps Environment
//
// Zone-redundancy is enabled to mirror realistic production placement,
// but the lab claim is independent of zone topology: the lab tests
// rolling-rollout transition behavior under load, not zone availability.
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
// Subject app — deterministic 25s startup delay, /healthz endpoint
//
// Per lab design D2 + D3:
// - Custom Python image (not containerapps-helloworld + args).
// - All three probes target /healthz (not /).
// - Single fixed correctly-configured probe profile before first run.
//   Probe timings serve as the primary baseline.
// ---------------------------------------------------------------------

resource subjectApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: subjectAppName
  location: location
  tags: union(commonTags, {
    role: 'subject'
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
      registries: empty(acrName) ? [] : [
        {
          server: '${acrName}.azurecr.io'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'subject'
          image: subjectImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'STARTUP_DELAY_SECONDS'
              value: string(subjectStartupDelaySeconds)
            }
            {
              name: 'REQUEST_DELAY_MS'
              value: string(subjectRequestDelayMs)
            }
            {
              name: 'PORT'
              value: '8080'
            }
            {
              name: 'PYTHONUNBUFFERED'
              value: '1'
            }
          ]
          probes: [
            // Startup probe gives the deterministic 25-second sleep
            // enough budget to finish, then fail-closes if /healthz is
            // not reachable. Budget = initialDelaySeconds (2) +
            // periodSeconds (3) * failureThreshold (15) = 47s, which
            // comfortably covers the 25s sleep + ~5s import + buffer.
            {
              type: 'Startup'
              httpGet: {
                path: '/healthz'
                port: 8080
              }
              initialDelaySeconds: 2
              periodSeconds: 3
              failureThreshold: 15
            }
            // Readiness probe controls when the replica is added to
            // the ingress backend pool. periodSeconds 3 + failureThreshold
            // 3 means a stuck replica leaves the pool within ~10s of
            // failing.
            {
              type: 'Readiness'
              httpGet: {
                path: '/healthz'
                port: 8080
              }
              periodSeconds: 3
              failureThreshold: 3
            }
            // Liveness probe restarts the replica if /healthz fails
            // for 90 consecutive seconds (periodSeconds 30 *
            // failureThreshold 3).
            {
              type: 'Liveness'
              httpGet: {
                path: '/healthz'
                port: 8080
              }
              periodSeconds: 30
              failureThreshold: 3
            }
          ]
        }
      ]
      // Pinned at 3 replicas. Autoscale is disabled so the experiment
      // isolates rolling-rollout transition behavior, not scale events.
      scale: {
        minReplicas: 3
        maxReplicas: 3
      }
    }
  }
}

// ---------------------------------------------------------------------
// Audit Job — 5-minute cron, ReplicaInventorySample + RevisionStateSample
// ---------------------------------------------------------------------

resource auditJob 'Microsoft.App/jobs@2024-03-01' = {
  name: names.auditJob
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
      replicaTimeout: 240
      replicaRetryLimit: 1
      scheduleTriggerConfig: {
        cronExpression: '*/5 * * * *'
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: empty(acrName) ? [] : [
        {
          server: '${acrName}.azurecr.io'
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
              name: 'MANAGED_IDENTITY_CLIENT_ID'
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
              name: 'CONTAINER_APP_NAMES'
              value: subjectAppName
            }
            {
              name: 'SAMPLE_INTERVAL_SECONDS'
              value: '30'
            }
            {
              name: 'RUN_LABEL'
              value: 'audit-cron'
            }
          ]
          // When using the placeholder image (no custom ACR wired),
          // emit a single notice JSON so the Job exits cleanly and the
          // 5-minute schedule keeps firing. When the custom audit image
          // is wired, run its own ENTRYPOINT (sample.sh).
          command: empty(acrName) ? [
            '/bin/sh'
            '-c'
          ] : []
          args: empty(acrName) ? [
            'echo {\\"event\\":\\"AuditPlaceholder\\",\\"note\\":\\"Override auditImage with the built sample.sh image to begin emitting ReplicaInventorySample and RevisionStateSample\\"}'
          ] : []
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------
// Perturbation sampler Job — manual trigger, 5-second cadence
//
// Per lab design D7: 5-minute audit alone is insufficient
// for a 10-second-bucket transition lab. This Job is triggered from
// trigger.sh immediately before each perturbation event and runs for
// SAMPLE_DURATION_SECONDS (default 600 = 10 minutes) at SAMPLE_INTERVAL_SECONDS
// (default 5 seconds) to provide sub-minute resolution.
// ---------------------------------------------------------------------

resource perturbationSamplerJob 'Microsoft.App/jobs@2024-03-01' = {
  name: names.perturbationSamplerJob
  location: location
  tags: union(commonTags, {
    role: 'perturbation-sampler'
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
      triggerType: 'Manual'
      replicaTimeout: 900
      replicaRetryLimit: 0
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: empty(acrName) ? [] : [
        {
          server: '${acrName}.azurecr.io'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'sampler'
          image: perturbationSamplerImage
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
              name: 'MANAGED_IDENTITY_CLIENT_ID'
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
              name: 'CONTAINER_APP_NAMES'
              value: subjectAppName
            }
            {
              name: 'SAMPLE_INTERVAL_SECONDS'
              value: '5'
            }
            {
              name: 'SAMPLE_DURATION_SECONDS'
              value: '600'
            }
            {
              name: 'PERTURBATION_ID'
              value: 'unspecified'
            }
          ]
          command: empty(acrName) ? [
            '/bin/sh'
            '-c'
          ] : []
          args: empty(acrName) ? [
            'echo {\\"event\\":\\"PerturbationSamplerPlaceholder\\",\\"note\\":\\"Override perturbationSamplerImage with the built sample.sh image\\"}'
          ] : []
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------
// k6 loadgen Job — manual trigger, sustains TARGET_RPS for DURATION_SECONDS
// ---------------------------------------------------------------------

resource loadgenJob 'Microsoft.App/jobs@2024-03-01' = {
  name: names.loadgenJob
  location: location
  tags: union(commonTags, {
    role: 'loadgen'
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
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 14400
      replicaRetryLimit: 0
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: empty(acrName) ? [] : [
        {
          server: '${acrName}.azurecr.io'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'k6'
          image: loadgenImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'SUBJECT_URL'
              value: 'https://${subjectApp.properties.configuration.ingress.fqdn}/'
            }
            {
              name: 'TARGET_RPS'
              value: '200'
            }
            {
              name: 'DURATION_SECONDS'
              value: '1800'
            }
            {
              name: 'PERTURBATION_ID'
              value: 'unspecified'
            }
            {
              name: 'RUN_ID'
              value: 'unspecified'
            }
            {
              name: 'K6_NO_USAGE_REPORT'
              value: 'true'
            }
          ]
          // When the placeholder grafana/k6 image is in use (no custom
          // ACR wired), there is no /scripts/k6-script.js inside the
          // image. Override the entrypoint with a notice so the Job
          // exits cleanly. When the custom loadgen image is wired, run
          // its own ENTRYPOINT.
          command: empty(acrName) ? [
            '/bin/sh'
            '-c'
          ] : []
          args: empty(acrName) ? [
            'echo {\\"event\\":\\"LoadgenPlaceholder\\",\\"note\\":\\"Override loadgenImage with the built k6-script.js image to begin emitting client-side 10s buckets\\"}'
          ] : []
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------

output environmentName string = env.name
output environmentId string = env.id
output logAnalyticsWorkspaceName string = law.name
output logAnalyticsWorkspaceId string = law.id
output uamiResourceId string = uami.id
output uamiClientId string = uami.properties.clientId
output uamiPrincipalId string = uami.properties.principalId
output subjectAppName string = subjectApp.name
output subjectAppFqdn string = subjectApp.properties.configuration.ingress.fqdn
output subjectAppUrl string = 'https://${subjectApp.properties.configuration.ingress.fqdn}/'
output subjectAppHealthzUrl string = 'https://${subjectApp.properties.configuration.ingress.fqdn}/healthz'
output auditJobName string = auditJob.name
output perturbationSamplerJobName string = perturbationSamplerJob.name
output loadgenJobName string = loadgenJob.name
output expiresAt string = expiresAt
