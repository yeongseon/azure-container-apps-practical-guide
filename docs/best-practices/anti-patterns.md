---
content_sources:
  diagrams:
    - id: anti-pattern-relationship-map
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-container-apps
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
content_validation:
  status: verified
  last_reviewed: 2026-11-08
  reviewer: agent
  core_claims:
    - claim: A revision is an immutable snapshot of your container app.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: Single revision mode automatically diverts traffic from the old revision to the new one after the new revision is ready.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: If you want to ensure that an instance of your revision is always running, set the minimum number of replicas to 1 or higher.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
    - claim: Workload-profile custom virtual network subnets require a /27 or larger range and delegation to Microsoft.App/environments, while consumption-only custom virtual network subnets require a /23 or larger range and must not be delegated.
      source: https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks
      verified: true
    - claim: You can use managed identity to authenticate with a private Azure Container Registry without a username and password.
      source: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
      verified: true
---
# Common Anti-Patterns

This quick-reference guide lists frequent Azure Container Apps anti-patterns seen in production, why they fail, and what to do instead. Use it as a pre-deployment review checklist and incident prevention reference.

## Why This Matters

Production Container Apps behavior depends on explicit platform choices for ingress, scale, identity, observability, and release safety. This page turns the cited Microsoft Learn guidance into reviewable practices that can be checked before promotion.

## Prerequisites

- Azure Container Apps environment and at least one deployed app
- Azure CLI with Container Apps extension
- Access to ACR, Log Analytics, and app configuration

```bash
export RG="rg-aca-prod"
export APP_NAME="ca-orders-api"
export ACA_ENV_NAME="cae-prod-shared"
export ACR_NAME="acrsharedprod"
export LOCATION="koreacentral"

az extension add --name "containerapp" --upgrade
az account show --output table
```

| Command / Parameter | Purpose |
|---|---|
| `az extension add` | Installs or upgrades the Container Apps extension required by the examples. |
| `--name` | Selects the resource named by the command for this check. |
| `--upgrade` | Replaces an older Container Apps extension with the current installed version. |
| `az account show` | Shows the active Azure subscription and tenant before the review commands run. |
| `--output` | Returns the result in the format needed by this review step. |

## Recommended Practices

### Anti-pattern quick reference table

| Problem | Why It Fails | Better Approach |
|---|---|---|
| Using `:latest` image tag in production | Revisions are not reproducible; rollbacks can pull unexpected image content | Use immutable version tags (`v1.2.3`) or digest pinning |
| Unnecessarily large container images | Measured pull and startup times can increase deployment risk and registry storage cost | Use minimal runtime images, multi-stage builds, and dependency trimming |
| No health probes configured | Platform cannot distinguish slow start from broken runtime; unhealthy replicas linger | Configure readiness and liveness probes matching startup/runtime behavior |
| Storing secrets directly in environment variables | Secret sprawl, accidental leakage in logs, manual rotation pain | Use Container Apps secrets and Key Vault references |
| Using ACR admin credentials instead of managed identity | Shared static credentials create blast radius and rotation risk | Use managed identity for image pulls and disable admin auth where possible |
| Setting `minReplicas=0` for latency-sensitive APIs | Cold starts increase p95 and p99 latency | Keep `minReplicas` at 1 or higher for strict latency services |
| Expecting canary or A/B control from single revision mode | Single revision mode performs a readiness-gated cutover but doesn't expose percentage traffic splitting between active revisions | Choose multiple revision mode when staged traffic, canary, or A/B control is required |
| Hardcoded connection strings | Secrets baked into image/config drift across environments | Resolve from secret store at runtime with identity-based access |
| Ignoring SIGTERM and ungraceful shutdown | In-flight requests/jobs are interrupted; data corruption and retry storms | Handle SIGTERM, drain requests, and flush telemetry before exit |
| Not configuring ingress when external access is required | App is healthy but unreachable from clients | Explicitly configure external ingress, target port, and transport |
| Using Container Apps for persistent stateful workloads | Ephemeral replicas are poor fit for durable local-state dependencies | Use managed state services or AKS for strict persistent workload patterns |
| Over-provisioning CPU and memory "just in case" | Continuous waste and lower bin-packing efficiency | Right-size from observed p95 usage and revise periodically |
| Not separating dev, staging, prod environments | Shared blast radius and accidental cross-environment impact | Separate environments and enforce scoped RBAC and network boundaries |
| Running database migrations in app startup | Startup path becomes risky and slow; scale-out can trigger concurrent migrations | Run migrations as controlled job or pipeline step before traffic shift |
| Ignoring scale rule interaction and precedence | Competing scalers create unstable replica behavior and cost spikes | Document scaler intent, test interaction, and set clear thresholds |

### 1) Using `:latest` image tag in production

`latest` breaks revision traceability because the same tag can point to different image contents over time.

Bad pattern:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/orders-api:latest"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp update` | Updates the selected Container App configuration. |
| `--image` | Selects the exact container image tag deployed by this example. |
| `--name` | Selects the resource named by the command for this check. |
| `--resource-group` | Selects the resource group containing the resource under review. |

Better pattern:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/orders-api:v1.9.4"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp update` | Updates the selected Container App configuration. |
| `--image` | Selects the exact container image tag deployed by this example. |
| `--name` | Selects the resource named by the command for this check. |
| `--resource-group` | Selects the resource group containing the resource under review. |

### 2) Unnecessarily large container images

Image size, layer reuse, registry throughput, and network conditions all affect pull and startup time. Measure those outcomes for the workload instead of applying an uncited universal size cutoff.

Operational impact:

- Longer revision provisioning windows
- Higher failure probability during pull/network pressure
- Increased registry storage and transfer overhead

Better approach:

- Use slim base image
- Remove build-time tooling from runtime image
- Keep only required runtime assets

### 3) No health probes configured

Without probes, platform-level health decisions are less precise.

Bad outcome examples:

- Broken dependency initialization treated as healthy
- Stuck replicas remain in rotation too long

Better approach with an app template file that defines explicit probe settings:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --yaml "./infra/containerapp-probes.yaml"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp update` | Updates the selected Container App configuration. |
| `--name` | Selects the resource named by the command for this check. |
| `--resource-group` | Selects the resource group containing the resource under review. |
| `--yaml` | Applies the YAML template that contains the documented app configuration. |

!!! note "Probe design"
    Readiness should represent dependency readiness for serving traffic. Liveness should represent process health, not external dependency state.

### 4) Secrets in environment variables instead of Container Apps secrets

Directly embedding secrets in plain environment values increases exposure risk.

Bad pattern:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars "DATABASE_URL=Server=tcp:db.example;User Id=admin;Password=<plaintext>"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp update` | Updates the selected Container App configuration. |
| `--name` | Selects the resource named by the command for this check. |
| `--resource-group` | Selects the resource group containing the resource under review. |
| `--set-env-vars` | Adds or updates the documented environment variable; `secretref:` resolves a Container Apps secret. |

Better pattern using platform secret abstraction:

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "db-connection=<redacted-secret-value>"

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars "DATABASE_URL=secretref:db-connection"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp secret set` | Creates or updates the named Container Apps secret values. |
| `--name` | Selects the resource named by the command for this check. |
| `--resource-group` | Selects the resource group containing the resource under review. |
| `--secrets` | Creates or updates the named secret value referenced by the app. |
| `az containerapp update` | Updates the selected Container App configuration. |
| `--set-env-vars` | Adds or updates the documented environment variable; `secretref:` resolves a Container Apps secret. |

### 5) Using ACR admin credentials instead of managed identity

ACR admin credentials are long-lived shared secrets and weaken least privilege.

Better approach:

1. Assign managed identity to app.
2. Grant AcrPull role to that identity.
3. Configure registry identity-based auth.

Assign identity:

```bash
az containerapp identity assign \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --system-assigned
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp identity assign` | Assigns a managed identity to the selected Container App. |
| `--name` | Selects the resource named by the command for this check. |
| `--resource-group` | Selects the resource group containing the resource under review. |
| `--system-assigned` | Enables the app-owned system-assigned managed identity. |

### 6) `minReplicas=0` on latency-sensitive APIs

For strict SLO APIs, scale-to-zero introduces predictable cold-start delay.

Bad pattern:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --min-replicas 0
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp update` | Updates the selected Container App configuration. |
| `--min-replicas` | Sets the app replica floor used for the latency or cost decision. |
| `--name` | Selects the resource named by the command for this check. |
| `--resource-group` | Selects the resource group containing the resource under review. |

Better pattern:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --min-replicas 1 \
  --max-replicas 20
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp update` | Updates the selected Container App configuration. |
| `--max-replicas` | Caps app scale-out at the documented replica count. |
| `--min-replicas` | Sets the app replica floor used for the latency or cost decision. |
| `--name` | Selects the resource named by the command for this check. |
| `--resource-group` | Selects the resource group containing the resource under review. |

### 7) Expecting progressive-delivery controls from single revision mode

Single revision mode is the default and provides a readiness-gated cutover: with ingress enabled, the existing revision continues to receive 100% of traffic until the new revision is ready, and traffic remains on the old revision if the update fails. It is not itself a production anti-pattern.

Use multiple revision mode when the release process requires controls that single revision mode does not provide:

- Percentage-based traffic splitting between active revisions
- Canary or A/B comparison before full promotion
- Operator-controlled activation and deactivation of revisions

When those controls are required:

- Enable multiple revisions
- Send small traffic percentage to candidate revision
- Promote after SLO and error checks

### 8) Hardcoded connection strings

Hardcoded values in code or container args become operational debt.

Failure modes:

- Secrets leak through repository, logs, or diagnostics
- Environment promotion requires image rebuilds
- Rotation causes downtime or drift

Better approach:

- Use secret references and managed identity
- Use one code artifact across environments
- Resolve environment-specific values at deploy/runtime

### 9) Ignoring SIGTERM and ungraceful shutdown

Container Apps sends termination signal during scale-in and revision changes.

If ignored:

- In-flight requests can fail
- Background work may be interrupted mid-transaction
- Telemetry may never flush

Better approach:

- Handle SIGTERM in runtime
- Stop accepting new work immediately
- Drain active work and close cleanly within timeout

### 10) Missing ingress configuration for externally consumed apps

A common issue is healthy app replicas with no reachable endpoint.

Set ingress explicitly during create:

```bash
az containerapp create \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --environment "$ACA_ENV_NAME" \
  --image "$ACR_NAME.azurecr.io/orders-api:v1.9.4" \
  --ingress external \
  --target-port 8000
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp create` | Creates the Container App with the documented image, environment, and ingress settings. |
| `--environment` | Selects the Container Apps environment that hosts the app or job. |
| `--image` | Selects the exact container image tag deployed by this example. |
| `--ingress` | Makes the example app externally reachable through managed ingress. |
| `--name` | Selects the resource named by the command for this check. |
| `--resource-group` | Selects the resource group containing the resource under review. |
| `--target-port` | Routes managed ingress to the application listener on port 8000. |

Validate ingress state:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress" \
  --output json
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the selected Container App settings for the documented verification. |
| `--name` | Selects the resource named by the command for this check. |
| `--output` | Returns the result in the format needed by this review step. |
| `--query` | Extracts only the fields needed for this documented verification. |
| `--resource-group` | Selects the resource group containing the resource under review. |

### 11) Using Container Apps for persistent local-state workloads

Container Apps is optimized for stateless or externally stateful services.

Anti-pattern examples:

- Local filesystem as primary database
- Stateful leader election dependent on replica identity
- Long-running node-local storage assumptions

Better approach:

- Use managed database/storage services for durable state
- For strict container-orchestrated persistent patterns, evaluate AKS

### 12) Over-provisioning CPU and memory

Provisioning "just in case" directly inflates cost and can mask performance problems.

Review configured resources:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.template.containers[0].resources" \
  --output json
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the selected Container App settings for the documented verification. |
| `--name` | Selects the resource named by the command for this check. |
| `--output` | Returns the result in the format needed by this review step. |
| `--query` | Extracts only the fields needed for this documented verification. |
| `--resource-group` | Selects the resource group containing the resource under review. |

Better approach:

- Start with measured baseline
- Increase only when metrics show sustained contention
- Reassess after each major release

### 13) Mixing dev/staging/prod in one environment

Single shared environment for all stages causes blast-radius coupling.

Typical failures:

- Non-production experiments impact production networking or quotas
- Shared secrets and RBAC reduce control boundaries
- Troubleshooting signal is noisy and ambiguous

Better approach:

- Separate managed environments per stage
- Separate resource groups and budgets
- Enforce stage-specific RBAC policies

### 14) Running database migrations in app startup

Startup migrations turn deployment into an implicit schema operation.

Risk pattern:

- Horizontal scale events run migration logic concurrently
- App startup blocks on long migration tasks
- Failed migration leaves mixed schema/runtime state

Better approach:

- Run migrations as explicit pre-deployment job
- Verify migration success before traffic shift
- Keep startup path limited to health-ready initialization

Example migration as job:

```bash
az containerapp job create \
  --name "job-db-migrate" \
  --resource-group "$RG" \
  --environment "$ACA_ENV_NAME" \
  --trigger-type "Manual" \
  --replica-timeout 1800 \
  --replica-retry-limit 0 \
  --image "$ACR_NAME.azurecr.io/orders-migration:v1.9.4"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp job create` | Creates the database-migration job with its execution limits and image. |
| `--environment` | Selects the Container Apps environment that hosts the app or job. |
| `--image` | Selects the exact container image tag deployed by this example. |
| `--name` | Selects the resource named by the command for this check. |
| `--replica-retry-limit` | Prevents an unsafe automatic rerun of the migration job. |
| `--replica-timeout` | Limits each migration-job replica to the documented execution window. |
| `--resource-group` | Selects the resource group containing the resource under review. |
| `--trigger-type` | Selects manual execution for the controlled migration job. |

### 15) Ignoring scale rule interaction and precedence

Multiple scalers can interact in unexpected ways when thresholds are inconsistent.

Symptoms:

- Replica oscillation (rapid up/down)
- Excessive scale-out under one hot metric
- Cost spikes without throughput gains

Better approach:

- Document each scale rule intent and owner
- Test rule combinations under synthetic load
- Align cooldown and threshold settings with downstream capacity

Inspect current scale settings:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.template.scale" \
  --output json
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the selected Container App settings for the documented verification. |
| `--name` | Selects the resource named by the command for this check. |
| `--output` | Returns the result in the format needed by this review step. |
| `--query` | Extracts only the fields needed for this documented verification. |
| `--resource-group` | Selects the resource group containing the resource under review. |

### Anti-pattern severity and impact matrix

| Anti-Pattern | Severity | Impact Area | Detection Difficulty | Fix Effort |
|---|---|---|---|---|
| `:latest` image tag | 🔴 High | Release safety | Easy — check image field | Low |
| No health probes | 🔴 High | Runtime reliability | Easy — check probe config | Low |
| Secrets in plain env vars | 🔴 High | Security | Medium — audit env config | Medium |
| ACR admin credentials | 🟠 Medium | Security | Easy — check registry auth | Medium |
| Ignoring SIGTERM | 🔴 High | Runtime reliability | Hard — requires load testing | Medium |
| Unnecessarily large images | 🟠 Medium | Cost, startup | Medium — measure pull and startup time | Medium |
| `minReplicas=0` on SLO APIs | 🟠 Medium | Latency | Medium — correlate cold starts | Low |
| Revision mode does not match rollout controls | 🟠 Medium | Release safety | Easy — compare release requirements with revision mode | Low |
| Hardcoded connection strings | 🔴 High | Security, operations | Medium — code/config audit | High |
| Missing ingress config | 🟡 Low | Connectivity | Easy — check ingress field | Low |
| Persistent local state | 🔴 High | Architecture fit | Hard — requires design review | High |
| Over-provisioned resources | 🟠 Medium | Cost | Medium — compare usage vs config | Low |
| Mixed dev/staging/prod env | 🟠 Medium | Blast radius | Easy — list environment apps | High |
| DB migrations in startup | 🔴 High | Release safety | Medium — review entrypoint | Medium |
| Scale rule conflicts | 🟠 Medium | Cost, reliability | Hard — requires load testing | Medium |

### Anti-pattern relationship map

<!-- diagram-id: anti-pattern-relationship-map -->
```mermaid
flowchart TD
    accTitle: Container Apps anti-pattern review areas
    accDescr: Groups common release, runtime, security, cost, and architecture anti-patterns so a reviewer can trace each configuration smell to its primary impact area.

    ROOT["Container Apps<br/>anti-pattern review"]
    RELEASE["Release safety"]
    RUNTIME["Runtime reliability"]
    SECURITY["Security and identity"]
    COST["Cost control"]
    FIT["Architecture fit"]
    MUTABLE["Mutable image tag"]
    CUTOVER["No staged rollout"]
    MIGRATION["Migration in app startup"]
    PROBES["Missing or incorrect probes"]
    SHUTDOWN["No graceful shutdown"]
    SCALERS["Unvalidated scale rules"]
    SECRETS["Plaintext credentials"]
    REGISTRY["Shared registry credentials"]
    ACCESS["Over-broad dependency access"]
    SIZE["Unmeasured resource sizing"]
    BASELINE["Unjustified minimum replicas"]
    LOGS["Unbounded log ingestion"]
    STATE["Durable state on replicas"]
    BOUNDARY["Mismatched environment boundary"]
    INGRESS["Ingress does not match exposure need"]

    ROOT --> RELEASE
    ROOT --> RUNTIME
    ROOT --> SECURITY
    ROOT --> COST
    ROOT --> FIT
    RELEASE --> MUTABLE
    RELEASE --> CUTOVER
    RELEASE --> MIGRATION
    RUNTIME --> PROBES
    RUNTIME --> SHUTDOWN
    RUNTIME --> SCALERS
    SECURITY --> SECRETS
    SECURITY --> REGISTRY
    SECURITY --> ACCESS
    COST --> SIZE
    COST --> BASELINE
    COST --> LOGS
    FIT --> STATE
    FIT --> BOUNDARY
    FIT --> INGRESS
```

*Figure: Review categories associate each configuration smell with its primary risk; an item can affect more than one category in a real workload.*

### Pre-production anti-pattern review checklist

| Review category | Key check | Pass criteria |
|---|---|---|
| Image management | No mutable production tags | Version or digest pinned |
| Runtime health | Readiness/liveness probes present | Probe paths tested |
| Secret handling | No plaintext credentials in env vars | Secret references used |
| Identity | Managed identity configured for dependencies | Least privilege applied |
| Scaling | Min/max replicas and scale rules justified | No contradictory scaler behavior |
| Release safety | Revision mode matches the required cutover or progressive-delivery controls | Rollback path documented |
| Environment boundaries | Stage isolation enforced | Separate environments for prod and non-prod |

!!! warning "Bookmark this page"
    Most high-severity Container Apps incidents map to one or more anti-patterns in this list. Running this checklist before every major release prevents avoidable outages.

### Verify anti-pattern surfaces in Azure Portal

![ca-sample-d38538 | Revisions and replicas | Container App | Create new revision | Save | Refresh | Deployment mode | Active revisions | Inactive revisions | Replicas | Name | ca-sample-d38538--0uzoi59 | Date created | 6/3/2026, 10:34:26 PM | Running status | Running | Label | Traffic | 100 % | Replicas | 1 (Show replicas)](../assets/best-practices/anti-patterns-revisions-and-replicas.png)

**[Observed]** `ca-sample-d38538 | Revisions and replicas` `Container App` `Create new revision` `Save` `Refresh` `Deployment mode` `Active revisions` `Inactive revisions` `Replicas` `Name` `Date created` `Running status` `View Logs` `Label` `Traffic` `Replicas` `ca-sample-d38538--0uzoi59` `6/3/2026, 10:34:26 PM` `Running` `View details` `Show Logs` `100 %` `1 (Show replicas)`.

**[Inferred]** The immutable revision suffix on `ca-sample-d38538--0uzoi59` is consistent with the digest-or-versioned-tag guidance in [1) Using `:latest` image tag in production](#1-using-latest-image-tag-in-production), which treats mutable tags as the anti-pattern under review. The `Deployment mode` setting is the surface where an operator chooses the rollout controls discussed in [7) Expecting progressive-delivery controls from single revision mode](#7-expecting-progressive-delivery-controls-from-single-revision-mode). The `Active revisions` and `Inactive revisions` grouping appears to map to the rollout-history guidance referenced in the [Anti-pattern quick reference table](#anti-pattern-quick-reference-table). The displayed `Traffic` value of `100 %` does not prove that the configured mode is unsafe; it only shows the current allocation, while multiple revision mode is needed when percentage-based canary or A/B control is a release requirement.

**[Not Proven]** Additional revision configuration detail and runtime parameters are not visible on this view.

## Advanced Topics

- Automate anti-pattern detection in CI using policy checks for image tags, resource limits, and revision mode.
- Build organization-level deployment templates that enforce managed identity and secret reference defaults.
- Combine platform diagnostics and KQL dashboards to detect anti-pattern drift (for example sudden increase in image pull failures or cold-start latency).
- Establish a quarterly architecture review to identify workloads that should move to jobs, managed services, or AKS based on state and performance requirements.

## Common Mistakes / Anti-Patterns

- Treating sample defaults as production-ready without checking ingress, scale, identity, and monitoring requirements.
- Applying a configuration change without verifying the resulting revision, logs, and metrics.
- Leaving ownership for certificates, private DNS, secrets, or rollout decisions undocumented.

## Validation Checklist

- [ ] Required Container Apps settings are represented in infrastructure as code.
- [ ] The active revision, ingress, scale, identity, and monitoring state match the intended design.
- [ ] Rollback or cleanup commands have been tested in a non-production environment.

## See Also

- [Best Practices - Revision Strategy](revision-strategy.md)
- [Best Practices - Scaling](scaling.md)
- [Best Practices - Identity and Secrets](identity-and-secrets.md)
- [Best Practices - Reliability](reliability.md)
- [Platform - Reliability](../platform/reliability/health-recovery.md)

## Sources

- [Microsoft Learn source 1](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-container-apps)
- [Microsoft Learn source 2](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Microsoft Learn source 3](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Microsoft Learn source 4](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Microsoft Learn source 5](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Microsoft Learn source 6](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Microsoft Learn source 7](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Microsoft Learn source 8](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
