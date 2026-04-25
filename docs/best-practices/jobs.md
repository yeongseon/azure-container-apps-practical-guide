---
content_sources:
  diagrams:
    - id: image-acr-name-azurecr-io-jobs-orders-reconcile-v1-0-0
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/jobs
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app#jobs
        - https://learn.microsoft.com/en-us/azure/container-apps/overview
    - id: final-status-published-to-dashboard-alert-channel
      type: state
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/jobs
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app#jobs
        - https://learn.microsoft.com/en-us/azure/container-apps/overview
content_validation:
  status: verified
  last_reviewed: "2026-04-12"
  reviewer: ai-agent
  core_claims:
    - claim: "Azure Container Apps jobs run containerized tasks for a finite duration and then stop."
      source: "https://learn.microsoft.com/azure/container-apps/jobs"
      verified: true
    - claim: "Job executions can start manually, on a schedule, or in response to events."
      source: "https://learn.microsoft.com/azure/container-apps/jobs"
      verified: true
    - claim: "Container apps and jobs run in the same environment and can share capabilities such as networking and logging."
      source: "https://learn.microsoft.com/azure/container-apps/jobs"
      verified: true
    - claim: "The execution history for scheduled and event-based jobs is limited to the most recent 100 successful and failed job executions."
      source: "https://learn.microsoft.com/azure/container-apps/jobs"
      verified: true
    - claim: "Ingress and related features such as custom domains and SSL certificates aren't supported for jobs."
      source: "https://learn.microsoft.com/azure/container-apps/jobs"
      verified: true
---

# Jobs Best Practices

Azure Container Apps Jobs are built for bounded background execution, not permanently running processes. This guide covers design patterns that keep job workloads reliable, observable, and cost-efficient in production.

## Prerequisites

- Azure Container Apps environment available
- Azure CLI with Container Apps extension
- A container image for job execution
- Access to data dependencies used by the job

```bash
export RG="rg-aca-prod"
export ENVIRONMENT_NAME="cae-prod-shared"
export APP_NAME="ca-orders-api"
export ACR_NAME="acrsharedprod"
export LOCATION="koreacentral"
export JOB_NAME="job-orders-reconcile"

az extension add --name "containerapp" --upgrade
az account show --output table
```

## Main Content

### Decide correctly: Job vs App

Use Container Apps Jobs when work has a clear start and finish boundary.

Use Container Apps (apps) when work is continuously available and request-driven.

| Decision area | Use Job | Use App |
|---|---|---|
| Workload lifetime | Finite execution | Long-running process |
| Trigger mode | Manual, scheduled, event-driven | HTTP and scaler-driven service runtime |
| Ingress requirement | Usually none | Common for APIs |
| Retry ownership | Platform execution retry + app idempotency | App and queue semantics |
| Cost shape | Execution window based | Baseline plus scale |

Signals you should switch from app to job:

- The process wakes up only on timer/queue and idles otherwise.
- Success is defined by "completed with exit code 0".
- You need execution history as an operational artifact.

Signals you should switch from job to app:

- You require low-latency request serving.
- Work cannot tolerate cold startup at each run.
- Stateful session behavior is expected across requests.

### Trigger type design: Manual, Scheduled, Event-driven

Container Apps Jobs support three trigger models. Match trigger to operational intent.

#### Manual trigger (operator-controlled runs)

Manual jobs are useful for one-off tasks:

- Backfill operations
- Data repair and replay
- Controlled maintenance windows

Create a manual job:

```bash
az containerapp job create \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --environment "$ENVIRONMENT_NAME" \
  --trigger-type "Manual" \
  --replica-timeout 1800 \
  --replica-retry-limit 1 \
  --image "$ACR_NAME.azurecr.io/jobs/orders-reconcile:v1.0.0"
```

Start execution on demand:

```bash
az containerapp job start \
  --name "$JOB_NAME" \
  --resource-group "$RG"
```

#### Scheduled trigger (predictable recurring runs)

Scheduled jobs are best when time is the primary trigger.

Common examples:

- Daily settlement calculations
- Nightly cleanup
- Hourly materialized view refresh

Create a scheduled job:

```bash
az containerapp job create \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --environment "$ENVIRONMENT_NAME" \
  --trigger-type "Schedule" \
  --cron-expression "0 */2 * * *" \
  --replica-timeout 1200 \
  --replica-retry-limit 2 \
  --image "$ACR_NAME.azurecr.io/jobs/orders-reconcile:v1.0.0"
```

!!! note "Cron timezone"
    Store and document cron expectations in UTC to avoid daylight saving ambiguity. Add business-local translation in your runbook.

#### Event-driven trigger (throughput-linked runs)

Event-driven jobs are best when signal volume changes over time (for example queue depth).

Create an event-driven job with Service Bus scaler metadata:

```bash
az containerapp job create \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --environment "$ENVIRONMENT_NAME" \
  --trigger-type "Event" \
  --scale-rule-name "orders-queue" \
  --scale-rule-type "azure-servicebus" \
  --scale-rule-metadata "queueName=orders" "messageCount=50" "namespace=<servicebus-namespace>.servicebus.windows.net" \
  --replica-timeout 900 \
  --replica-retry-limit 3 \
  --image "$ACR_NAME.azurecr.io/jobs/orders-reconcile:v1.0.0"
```

### Tune timeout and retry limits as SLO controls

`--replica-timeout` and `--replica-retry-limit` define both recovery behavior and spend profile.

Design method:

1. Measure p95 execution duration under normal load.
2. Set timeout at p95 + safety margin.
3. Classify failures as transient vs deterministic.
4. Allow retries only for transient categories.

Update timeout/retry:

```bash
az containerapp job update \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --replica-timeout 1500 \
  --replica-retry-limit 2
```

Failure-classification pattern:

- Authentication denied: no retry until configuration is fixed.
- Dependency timeout: limited retries with backoff.
- Data validation error: fail fast and send to dead-letter flow.

!!! warning "Retry amplification"
    High retry limits on non-idempotent operations can duplicate side effects. Always design write paths with idempotency keys or conflict-safe upserts before increasing retries.

### Parallelism and completion count patterns

Jobs support execution-level concurrency controls:

- `--parallelism`: how many replicas run in parallel
- `--replica-completion-count`: how many successful replicas mark the execution complete

Pattern guidance:

- Set `parallelism=1` for order-sensitive workloads.
- Increase parallelism for partitioned workloads with independent shards.
- Use completion count equal to partition count when all shards are mandatory.

Create a parallelized job execution model:

```bash
az containerapp job create \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --environment "$ENVIRONMENT_NAME" \
  --trigger-type "Manual" \
  --parallelism 4 \
  --replica-completion-count 4 \
  --replica-timeout 1800 \
  --image "$ACR_NAME.azurecr.io/jobs/orders-reconcile:v1.0.0"
```

<!-- diagram-id: image-acr-name-azurecr-io-jobs-orders-reconcile-v1-0-0 -->
```mermaid
flowchart TD
    A[Execution Triggered] --> B[Replica 1]
    A --> C[Replica 2]
    A --> D[Replica 3]
    A --> E[Replica 4]
    B --> F{All required completions reached?}
    C --> F
    D --> F
    E --> F
    F -->|Yes| G[Execution Succeeded]
    F -->|No and retries remain| H[Retry Failed Partitions]
    H --> F
```

### Exit code conventions and error handling contracts

Define a clear contract between your job container and operations team.

Recommended exit code model:

| Exit code | Meaning | Operational action |
|---|---|---|
| 0 | Success | No action |
| 10 | Retryable external dependency issue | Allow configured retries |
| 20 | Validation/business-rule failure | No retry, inspect payload |
| 30 | Configuration or identity failure | Stop and fix deployment config |
| 40 | Unknown unhandled failure | Investigate logs and crash context |

Implementation principles:

- Emit structured log event before exit.
- Include correlation identifiers for replay.
- Keep final failure summary in one machine-readable line.

### Job image design for fast startup and lower spend

Job runtime cost is sensitive to startup overhead. Keep images minimal and deterministic.

Best practices:

- Use slim base images and minimal runtime dependencies.
- Separate build dependencies from runtime layer.
- Avoid shell-heavy entrypoints for simple workloads.
- Pin image tags by immutable version (for example `v1.4.2`), not `latest`.

List job image currently configured:

```bash
az containerapp job show \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --query "properties.template.containers[0].image" \
  --output tsv
```

!!! tip "Startup budget"
    If job average runtime is short, image pull and startup can dominate total execution time. A 30-second startup penalty on a 60-second job can increase cost and delay by 50 percent or more.

### Use managed identity for job workloads

Jobs frequently access Storage, Service Bus, Key Vault, or databases. Avoid embedded credentials.

Enable system-assigned identity:

```bash
az containerapp job identity assign \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --system-assigned
```

Inspect principal ID for role assignment workflows:

```bash
az containerapp job show \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --query "identity.principalId" \
  --output tsv
```

Identity patterns:

- Give jobs dedicated identities when blast radius must be isolated.
- Apply least-privilege role assignments per dependency.
- Rotate away from shared credentials and admin keys.

### Storage and I/O design patterns for jobs

Choose storage by execution pattern:

| Pattern | Preferred storage | Why |
|---|---|---|
| Large immutable input/output files | Blob Storage | Durable and cost-efficient object store |
| Shared mutable work queue | Queue or Service Bus | Explicit delivery semantics |
| Low-latency metadata and checkpoints | Table/Cosmos DB/SQL | Queryable state with partitioning |
| Temporary per-execution files | Ephemeral local filesystem | Fast local scratch space |

Design guidance:

- Keep local filesystem usage ephemeral and bounded.
- Persist checkpoint state externally for retry continuation.
- Never assume execution affinity to previous replicas.

### Monitor job execution health with CLI and KQL

List recent executions:

```bash
az containerapp job execution list \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --output table
```

Show execution logs:

```bash
az containerapp job logs show \
  --name "$JOB_NAME" \
  --resource-group "$RG"
```

KQL: success/failure trend by job over 24 hours:

```kusto
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(24h)
| where Reason_s has "Job" or Log_s has "execution"
| summarize Events=count() by JobName=tostring(ContainerAppName_s), Result=tostring(Reason_s), bin(TimeGenerated, 1h)
| order by TimeGenerated asc
```

KQL: identify long-running executions:

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(24h)
| where ContainerAppName_s == "$JOB_NAME"
| extend Parsed=parse_json(Log_s)
| where tostring(Parsed.event) in ("job-start", "job-end")
| project TimeGenerated, ExecutionId=tostring(Parsed.executionId), Event=tostring(Parsed.event), DurationMs=todouble(Parsed.durationMs)
| summarize MaxDurationMs=max(DurationMs), AvgDurationMs=avg(DurationMs) by ExecutionId
| order by MaxDurationMs desc
```

Operational SLO indicators:

- Success rate by trigger type
- p95 execution duration
- Retry amplification ratio
- Queue lag to execution start delay

### Cost implications of schedule frequency

Scheduling frequency directly controls run count and therefore total cost.

Guideline:

- If data freshness objective is 15 minutes, do not schedule every minute.
- Batch lightweight tasks into fewer runs when latency allows.
- Avoid overlap where one execution starts before previous completion.

Example adjustment from aggressive schedule to aligned schedule:

```bash
az containerapp job update \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --cron-expression "*/15 * * * *"
```

Schedule design checklist:

| Question | Action |
|---|---|
| What freshness SLA is required? | Set cron at SLA boundary, not below |
| Can executions overlap? | Add guard logic or widen interval |
| Is runtime variable? | Use timeout headroom and concurrency limits |
| Is workload bursty? | Prefer event-driven trigger over fixed cron |

### Execution lifecycle runbook pattern

Use a consistent lifecycle runbook for every production job:

1. Trigger observed (manual/schedule/event)
2. Execution started and correlated
3. Dependency reachability verified
4. Completion event emitted with exit code
5. Retry decision logged
6. Final status published to dashboard/alert channel

<!-- diagram-id: final-status-published-to-dashboard-alert-channel -->
```mermaid
stateDiagram-v2
    [*] --> Triggered
    Triggered --> Running
    Running --> Succeeded: exit 0
    Running --> Failed: non-zero exit
    Failed --> Retrying: retryable + limit not reached
    Retrying --> Running
    Failed --> TerminalFailed: no retries
    Succeeded --> [*]
    TerminalFailed --> [*]
```

### Production hardening checklist for jobs

| Domain | Required control |
|---|---|
| Trigger design | Manual/schedule/event selected by workload semantics |
| Timeouts | `--replica-timeout` set from measured p95 |
| Retries | `--replica-retry-limit` matches idempotency capability |
| Parallelism | Throughput tuned without overloading dependencies |
| Identity | Managed identity enabled with least privilege |
| Observability | Structured logs + execution dashboards + alerts |
| Cost | Schedule frequency and run duration reviewed monthly |

## Advanced Topics

- Build partition-aware jobs that dynamically assign shards using queue metadata and bounded parallelism.
- Add execution idempotency tokens persisted in durable storage to guarantee exactly-once side effects at business level.
- Use separate job definitions for fast and slow paths to avoid one timeout/retry policy for incompatible workloads.
- Integrate job execution status with deployment gates so critical release steps are blocked on failed prerequisite jobs.

## See Also

- [Platform - Jobs](../platform/jobs/index.md)
- [Best Practices - Job Design](job-design.md)
- [Platform - Jobs vs Apps](../platform/jobs/jobs-vs-apps.md)
- [Best Practices - Scaling](scaling.md)
- [Best Practices - Reliability](reliability.md)
- [Best Practices - Identity and Secrets](identity-and-secrets.md)
- [Operations - Monitoring](../operations/monitoring/index.md)
