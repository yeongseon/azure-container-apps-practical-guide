---
description: Day-2 production operations for Azure Container Apps — monitoring, scaling, deployment, alerts, secret rotation, recovery, and revision management.
content_sources:
  diagrams:
    - id: use-a-repeatable-control-loop-so
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/
content_validation:
  status: verified
  last_reviewed: 2026-11-08
  reviewer: agent
  core_claims:
    - claim: Azure Container Apps supports monitoring logs, autoscaling, and multiple revisions for application lifecycle management.
      source: https://learn.microsoft.com/en-us/azure/container-apps/overview
      verified: true
    - claim: Container Apps revisions are immutable snapshots, and multiple revision mode supports traffic allocation between active revisions.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: Container Apps integrates with Azure Monitor Log Analytics for querying system and application log data.
      source: https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring
      verified: true
---
# Operations

This section covers production operations for Azure Container Apps. It is language-agnostic and focuses on platform behavior, reliability, and cost control in running systems.

!!! note "Variable naming in this section"
    Operations guides use production-style variable names (e.g., `RG="rg-aca-prod"`) to reflect real operational contexts. Tutorial guides use demo-style names (e.g., `RG="rg-aca-python-demo"`). Substitute your own resource names as appropriate.

## Prerequisites

- An existing Container Apps environment and app
- Azure CLI with Container Apps extension installed
- Permissions to view and update Container App resources

```bash
export RG="rg-aca-prod"
export APP_NAME="app-python-api-prod"
export ACA_ENV_NAME="aca-env-prod"

az extension add --name containerapp --upgrade
az account show --output table
```

| Command | Purpose |
|---|---|
| `az extension add` | Installs the Container Apps extension required by the operations commands in this guide. |
| `--name` | Identifies `containerapp` as the extension to install before operating the app. |
| `--upgrade` | Updates an existing Container Apps extension so the documented subcommands are available. |
| `az account show` | Confirms the active subscription and tenant before production operations. |
| `--output` | Formats the active account context as a table for a quick pre-operation check. |

## Main Content

### Operations Documents

| Document | Description |
|---|---|
| [Deployment](deployment/index.md) | CI/CD patterns, image build, registry authentication, production rollouts |
| [Custom Domains](custom-domains/index.md) | Hostname binding, managed certificates, and BYO TLS operations |
| [Disaster Recovery](disaster-recovery/index.md) | Zone redundancy, multi-region routing, and regional failover patterns |
| [Networking](deployment/networking.md) | VNet deployment, private endpoints, egress controls |
| [Health Probes](health-probes/index.md) | Startup, readiness, and liveness probe runbooks |
| [Jobs](jobs/index.md) | Execution inspection, replay, stop actions, and job health monitoring |
| [Logging](logging/index.md) | Console and system log streams, streaming, KQL, and export |
| [Revision Management](revision-management/index.md) | Revision lifecycle, traffic splitting, rollback procedures |
| [Monitoring](monitoring/index.md) | Log Analytics, metrics, distributed tracing, alerting |
| [Scaling](scaling/index.md) | KEDA scale rules, manual scaling, concurrency limits |
| [Alerts](alerts/index.md) | SLO-driven alerts for availability, latency, and resource usage |
| [Image Pull and Registry](image-pull-and-registry/index.md) | Private registry authentication, managed identity pull |
| [Secret Rotation](secret-rotation/index.md) | Credential rotation without downtime |
| [Recovery](recovery/index.md) | Failed revision handling, replica restarts, regional failover |

### Quick Operational Commands

```bash
az containerapp show --resource-group $RG --name $APP_NAME --output json
az containerapp revision restart --name "$APP_NAME" --resource-group "$RG" --revision "<revision-name>"
az containerapp revision list --resource-group $RG --name $APP_NAME --output table
az containerapp logs show --resource-group $RG --name $APP_NAME --type system --follow
```

| Command | Why it is used |
|---|---|
| `az containerapp show` | Reads the app configuration for the initial operational inspection. |
| `az containerapp revision restart` | Restarts the specified revision when an operator needs to recycle its replicas. |
| `az containerapp revision list` | Lists revision health and state after the restart. |
| `az containerapp logs show` | Streams platform events that explain revision and replica behavior. |
| `--resource-group` | Scopes each app operation to the resource group stored in `$RG`. |
| `--name` | Targets the Container App stored in `$APP_NAME`. |
| `--output` | Returns full JSON for app inspection and a table for the revision check. |
| `--type` | Chooses system logs because the check concerns platform and revision events. |
| `--follow` | Keeps the system-log session open while the operator watches new events. |
| `--revision` | Identifies the exact revision to restart rather than recycling an unspecified deployment. |

### Verification Steps

Validate that the operations baseline is healthy before changing configuration.

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "{name:name,environmentId:properties.managedEnvironmentId,provisioningState:properties.provisioningState,runningStatus:properties.runningStatus}" \
  --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp show` | Reads the Container App configuration so the documented setting can be verified. |
| `--name` | Targets the Container App whose baseline is being captured. |
| `--resource-group` | Scopes the baseline lookup to the app's resource group. |
| `--query` | Projects the environment, provisioning, and running-state fields needed for the baseline. |
| `--output` | Preserves the projected baseline as structured JSON evidence. |

Example output (PII masked):

```json
{
  "name": "app-python-api-prod",
  "environmentId": "/subscriptions/<subscription-id>/resourceGroups/rg-aca-prod/providers/Microsoft.App/managedEnvironments/aca-env-prod",
  "provisioningState": "Succeeded",
  "runningStatus": "Running"
}
```

### Operations Control Loop

Use a repeatable control loop so every operational change is observable, reversible, and documented.

<!-- diagram-id: use-a-repeatable-control-loop-so -->
```mermaid
flowchart TD
    BASELINE[Capture health and configuration baseline]
    CHANGE[Apply one controlled change]
    RUNTIME[Validate revision and replicas]
    SIGNALS[Observe metrics, logs, and transactions]
    HEALTHY{Release criteria met?}
    RECORD[Record evidence and close]
    ROLLBACK[Roll back the failed change]
    ESCALATE[Escalate with preserved evidence]

    BASELINE --> CHANGE
    CHANGE --> RUNTIME
    RUNTIME --> SIGNALS
    SIGNALS -. evaluation evidence .-> HEALTHY
    HEALTHY -->|Yes| RECORD
    HEALTHY -->|No| ROLLBACK
    ROLLBACK --> ESCALATE
    ESCALATE --> BASELINE
```

The control loop returns a failed change to a fresh baseline rather than applying additional mitigations without verification.

### Operational Cadence Matrix

| Cadence | Primary Goal | Required Commands | Exit Criteria |
|---|---|---|---|
| Per deployment | Prevent bad revision promotion | `az containerapp revision list`, `az containerapp ingress traffic show` | New revision healthy with expected traffic |
| Daily | Catch platform drift early | `az containerapp show`, `az containerapp env show` | Running status is healthy and config matches baseline |
| Weekly | Validate scale and alert posture | `az monitor metrics list`, `az monitor scheduled-query list` | Alerts are enabled and thresholds are current |
| Monthly | Recovery readiness | rollback simulation + runbook review | Recovery target time met in drill |

!!! tip "Use pre-change and post-change snapshots"
    Capture key fields before and after updates (ingress, scale rules, identity, revision mode). A small JSON diff dramatically reduces incident triage time.

!!! warning "Treat operations changes as production releases"
    Any update to scale rules, traffic weights, ingress, secrets, or identity can change customer impact immediately. Always run health verification and rollback checks after each change.

### Baseline Snapshot Commands

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "{name:name,latestRevision:properties.latestRevisionName,provisioningState:properties.provisioningState,runningStatus:properties.runningStatus}" \
  --output json

az containerapp ingress traffic show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output json
```

| Command | Purpose |
|---|---|
| `az containerapp show` | Captures the app's current revision and runtime state before an operational change. |
| `az containerapp ingress traffic show` | Records the pre-change revision traffic weights needed for rollback. |
| `--name` | Targets the Container App whose pre-change state is being recorded. |
| `--resource-group` | Scopes both snapshots to the app's resource group. |
| `--query` | Projects the latest revision, provisioning state, and running state for baseline comparison. |
| `--output` | Preserves both snapshots as structured JSON for comparison and rollback evidence. |

### Operational Ownership Checklist

| Capability | Primary Owner | Backup Owner | Evidence |
|---|---|---|---|
| Deployment and rollback | Application team | Platform team | Successful revision promotion logs |
| Alert tuning | SRE/operations | Application team | Alert history and threshold review notes |
| Secret rotation | Security/app owner | Operations | Rotation runbook and audit log entries |
| Recovery drills | Operations lead | Incident commander | Quarterly drill report |

!!! info "Keep runbooks co-located with services"
    Store the operational runbook path in each service repository so on-call engineers can find the latest rollback and recovery guidance without context switching.

Operational readiness minimum:

- Every production app has a tested rollback command set.
- Every sev1 alert maps to a named incident owner.
- Every production app has an explicit logging, health probe, and custom-domain runbook where applicable.

## Advanced Topics

- Build an SLO-based operating model mapping each control to measurable service outcomes.
- Keep runbooks and IaC synchronized so recovery steps are deterministic during incidents.
- Validate production controls regularly through game days and restore exercises.

## Language-Specific Details

For language-specific operational guidance, see:
- [Python Guide](../language-guides/python/index.md)

## See Also

- [Platform](../platform/index.md)
- [Best Practices](../best-practices/index.md)
- [Reference](../reference/index.md)
- [Logging](logging/index.md)
- [Custom Domains and TLS](custom-domains/index.md)
- [Disaster Recovery](disaster-recovery/index.md)
- [Health Probes](health-probes/index.md)

## Sources

- [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Revisions in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Monitor logs in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring)
