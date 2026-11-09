---
description: Azure Container Apps configuration scope matrix for deciding whether a setting affects an environment, every revision, or a new revision.
content_sources:
  diagrams:
    - id: config-scope-decision
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/azure-resource-manager-api-spec
---
# Configuration Scope Matrix

Azure Container Apps settings live at several scopes — the managed **environment**, the **container app** (application scope), the **revision** (revision scope), and the individual **container**. The scope of a setting determines *what happens when you change it*: whether the change creates a new revision, applies globally to every revision, requires a restart to take effect, or is immutable after the environment is created.

Use this matrix to answer a common production question: **"If I change this setting, does it create a revision, affect the whole environment, or need a redeploy?"**

!!! tip "The rule of thumb"
    Anything under `properties.template` is **revision-scope** (creates a new, immutable revision). Anything under `properties.configuration` is **application-scope** (applies to all revisions, no new revision). Environment-level settings live on a separate resource entirely.

## Scope decision at a glance

<!-- diagram-id: config-scope-decision -->
```mermaid
flowchart TD
    accTitle: Decide the scope and effect of a Container Apps setting change
    accDescr: First identify whether the setting belongs to the managed environment or container app. For app settings, template changes create a revision while configuration changes apply to all revisions; changed secret values also require affected revisions to restart.

    CHANGE[Change a setting]
    RESOURCE{Which Azure resource<br/>owns the setting?}
    ENVIRONMENT[Managed environment scope]
    APP_SECTION{Which container app<br/>section owns it?}
    TEMPLATE[properties.template]
    CONFIGURATION[properties.configuration]
    NEW_REVISION[Create a new immutable revision<br/>for the changed template]
    ALL_REVISIONS[Apply the configuration change<br/>to all revisions]
    SECRET{Did a secret value change?}
    RESTART[Restart affected revisions<br/>to load the new value]
    COMPLETE[No revision restart required<br/>by the secret-value rule]
    ENV_REVIEW[Check the property contract<br/>before changing the environment]

    CHANGE --> RESOURCE
    RESOURCE -->|Managed environment| ENVIRONMENT
    RESOURCE -->|Container app| APP_SECTION
    ENVIRONMENT --> ENV_REVIEW
    APP_SECTION -->|properties.template| TEMPLATE
    APP_SECTION -->|properties.configuration| CONFIGURATION
    TEMPLATE --> NEW_REVISION
    CONFIGURATION --> ALL_REVISIONS
    ALL_REVISIONS --> SECRET
    SECRET -->|Yes| RESTART
    SECRET -->|No| COMPLETE
```

The branches classify change impact; they do not imply that every managed-environment property is mutable after creation. Check the property-specific guidance before changing the environment resource.

## Change-type model

Microsoft documents two categories of change to a container app:

- **Revision-scope changes** — any change to a parameter in the [`properties.template`](https://learn.microsoft.com/en-us/azure/container-apps/azure-resource-manager-api-spec#propertiestemplate) section. These trigger a new revision when you deploy, and are limited to the revision in which they are deployed.
- **Application-scope changes** — any change to a parameter in the [`properties.configuration`](https://learn.microsoft.com/en-us/azure/container-apps/azure-resource-manager-api-spec#propertiesconfiguration) section. These are applied globally to all revisions and do **not** create a new revision.

## Environment-scope settings

These settings are defined on the **managed environment** resource (the `Microsoft.App/managedEnvironments` resource), not on individual apps — this is a separate resource scope, not a `properties.configuration` section of an app. They affect every app in the environment. Several are immutable after the environment is created.

| Setting | ARM property | Change effect | Notes |
|---|---|---|---|
| VNet integration | `vnetConfiguration.infrastructureSubnetId` | Immutable after creation | Set at creation; changing the network requires recreating the environment ([networking](https://learn.microsoft.com/en-us/azure/container-apps/networking)) |
| Zone redundancy | `zoneRedundant` | Immutable after creation | Must be enabled at environment creation and can't be changed or disabled afterward ([reliability](https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps)) |
| Log destination | `appLogsConfiguration` | Environment-wide | Log Analytics workspace / logging configuration |
| Workload profiles | `workloadProfiles` | Environment-wide | Add/scale profiles; apps select a profile by name |
| mTLS (peer authentication) | `peerAuthentication` | Environment-wide | Enables environment-level mTLS encryption |
| Dapr AI instrumentation key | `daprAIInstrumentationKey` | Environment-wide | Application Insights key used by Dapr |
| Environment custom domain | `customDomainConfiguration` | Environment-wide | DNS suffix and certificate for the environment |

## Application-scope settings (no new revision)

These are `properties.configuration` parameters. Changing them applies to all revisions and does **not** create a new revision.

| Setting | ARM property | Change effect | Notes |
|---|---|---|---|
| Revision mode | `activeRevisionsMode` | Applies globally | `single` or `multiple`; `multiple` is required for traffic splitting |
| Secret values | `secrets` | Applies globally; **restart required** | Revisions must be restarted before the container recognizes new secret values |
| Ingress on/off | `ingress.external` / ingress enabled | Applies globally | Turning ingress on or off is application-scope |
| Traffic splitting | `ingress.traffic` | Applies globally | Weights and `latestRevision` routing |
| Revision labels | `ingress.traffic[].label` | Applies globally | Labels can be moved between revisions without a deploy |
| IP restrictions | `ingress.ipSecurityRestrictions` | Applies globally | Allow/deny ranges |
| Sticky sessions | `ingress.stickySessions` | Applies globally | Session affinity |
| Client certificate mode | `ingress.clientCertificateMode` | Applies globally | mTLS ingress client certificate handling |
| CORS policy | `ingress.corsPolicy` | Applies globally | Allowed origins/methods/headers |
| Registry credentials | `registries` | Applies globally | Credentials for private container registries |
| Dapr settings | `dapr` | Applies globally | Enable/configure the app's managed Dapr sidecar |
| Inactive revision limit | `maxInactiveRevisions` | Applies globally | Controls retained inactive revision count |

!!! warning "Secret values are application-scope but not live"
    Changing a secret's value is an application-scope change (it does not create a new revision), **but a container only reads secret values at startup**. You must restart the affected revisions before the new value is used. See [Secret Rotation](../operations/secret-rotation/index.md).

## Revision-scope settings (new revision created)

These are `properties.template` parameters. Any change here creates a new, immutable revision on deploy.

| Setting | ARM property | Change effect | Notes |
|---|---|---|---|
| Revision suffix | `template.revisionSuffix` | New revision | Friendly name suffix; must be unique |
| Container image | `template.containers[].image` | New revision | Prefer immutable tags over `:latest` |
| Scale rules | `template.scale` | New revision | `minReplicas`, `maxReplicas`, and KEDA rules |
| Volumes | `template.volumes` | New revision | `EmptyDir`, `AzureFile`, or `Secret` volumes |
| Init containers | `template.initContainers` | New revision | Run-to-completion before app containers |
| Service binds | `template.serviceBinds` | New revision | Dev-time service connections |

## Container-scope settings (part of the revision)

Container settings live inside `template.containers[]` (and `template.initContainers[]`). They are part of the revision snapshot, so changing any of them is a **revision-scope** change.

| Setting | ARM property | Change effect | Notes |
|---|---|---|---|
| CPU / memory | `containers[].resources` | New revision | Must use a supported CPU/memory combination |
| Health probes | `containers[].probes` | New revision | Liveness, readiness, startup |
| Environment variables | `containers[].env` | New revision | Plain values or `secretRef` references |
| Volume mounts | `containers[].volumeMounts` | New revision | Bind a defined volume to a mount path |
| Command / args | `containers[].command` / `args` | New revision | Container entrypoint overrides |

!!! note "Env vars that reference secrets"
    An env var value change is revision-scope (new revision). But when the env var uses `secretRef`, rotating the *underlying secret value* is application-scope and requires a restart — see the secret note above.

## Jobs: a different lifecycle

Container Apps **jobs** do not use the revision model. For jobs, `properties.configuration` holds `triggerType`, `replicaTimeout`, and `replicaRetryLimit`, while `properties.template` holds `containers` (and optionally `initContainers` and `volumes`) and `scale`. Updating a job changes the job definition used by subsequent executions rather than creating a revision.

## Usage Notes

- When you need a change to be picked up **without** creating a new revision, confirm it is a `properties.configuration` parameter.
- When you need an **auditable, rollback-able** snapshot, make the change revision-scope so it produces a new revision.
- Environment-level immutable settings (VNet, zone redundancy) must be decided at environment creation; plan them during architecture review, not day-2.
- Use `az containerapp revision list` to confirm whether your change produced a new revision.

## See Also

- [Revision Lifecycle](../platform/revisions/lifecycle.md)
- [Revision Modes](../platform/revisions/revision-modes.md)
- [Traffic Split](../platform/revisions/traffic-split.md)
- [Secret Rotation](../operations/secret-rotation/index.md)
- [Platform Limits](platform-limits.md)

## Sources

- [Microsoft Learn: Update and deploy changes in Azure Container Apps (revisions)](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Microsoft Learn: Azure Container Apps ARM and YAML template specifications](https://learn.microsoft.com/en-us/azure/container-apps/azure-resource-manager-api-spec)
- [Microsoft Learn: Manage secrets in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [Microsoft Learn: Reliability in Azure Container Apps (zone redundancy)](https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps)
- [Microsoft Learn: Networking in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/networking)
