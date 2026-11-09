---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/jobs
  diagrams:
    - id: event-job-storm-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/jobs
        - https://learn.microsoft.com/en-us/azure/container-apps/jobs-get-started-cli
content_validation:
  status: verified
  last_reviewed: 2026-07-18
  reviewer: ai-agent
  core_claims:
    - claim: Azure Container Apps jobs support event-driven execution patterns.
      source: https://learn.microsoft.com/en-us/azure/container-apps/jobs
      verified: true
    - claim: Job execution history can be reviewed with Azure CLI commands for Container Apps jobs.
      source: https://learn.microsoft.com/en-us/cli/azure/containerapp/job
      verified: true
---
# Event Job Storm

Use this playbook when an event-driven job creates too many executions, drains a queue unexpectedly fast, or amplifies downstream failures.

## Symptom

- A queue spike results in far more job executions than expected.
- Downstream dependencies throttle because too many job executions start concurrently.
- Retries or poison messages keep re-triggering work.
- Operators see a sudden burst in `az containerapp job execution list` even though the backlog was small.

<!-- diagram-id: event-job-storm-flow -->
```mermaid
flowchart TD
    accTitle: Diagnose an event-driven job execution storm
    accDescr: Compare scaler configuration, authenticated event-source backlog, and execution history before deciding whether to cap executions or repair duplicate and poison-message handling.

    START[Execution count surges] --> RULE[Inspect event trigger,<br/>metadata, and authentication]
    RULE --> SOURCE{Scaler reads the intended<br/>event source?}
    SOURCE -->|No| CONFIG[Correct source metadata<br/>or scaler authentication]
    SOURCE -->|Yes| BACKLOG{Backlog justifies<br/>the execution count?}
    BACKLOG -->|Yes| CAP[Set safe maximum executions<br/>for downstream capacity]
    BACKLOG -->|No| REAPPEAR{Messages reappear or<br/>repeat business keys?}
    REAPPEAR -->|Yes| DELIVERY[Fix completion, retry,<br/>and dead-letter handling]
    REAPPEAR -->|No| THRESHOLD[Reduce trigger sensitivity<br/>and polling fan-out]
    CONFIG --> TEST[Replay a controlled backlog]
    CAP --> TEST
    DELIVERY --> TEST
    THRESHOLD --> TEST
    TEST --> BOUNDED{Execution fan-out bounded?}
    BOUNDED -->|Yes| DONE[Record safe capacity envelope]
    BOUNDED -->|No| ESCALATE[Collect scaler and queue evidence]
```

*Figure: Event-driven jobs create executions from scaler results; source authentication and duplicate delivery must be verified before tuning concurrency.*

## Possible Causes

- The event trigger metadata is too aggressive for the queue or downstream dependency.
- Maximum parallel executions are higher than the workload can safely absorb.
- Messages are retried repeatedly because the consumer fails before acknowledging completion.
- A Dapr or queue component points to the wrong source, causing duplicate delivery patterns.
- Operators are measuring execution count instead of unique business work items.

## Diagnosis Steps

1. Confirm the job really is event-driven.
2. Compare execution history with the actual backlog and dead-letter counts.
3. Check whether the same messages are being retried or re-enqueued.
4. Bound the concurrency hypothesis by reviewing the configured max execution behavior.

```bash
az containerapp job show \
    --name "$JOB_NAME" \
    --resource-group "$RG" \
    --output json

az containerapp job execution list \
    --name "$JOB_NAME" \
    --resource-group "$RG" \
    --output table

az containerapp job list \
    --resource-group "$RG" \
    --query "[?properties.environmentId != null && ends_with(properties.environmentId, '/$ACA_ENV_NAME')].{name:name, triggerType:properties.configuration.triggerType}" \
    --output table
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp job show` | Reads the job definition to identify trigger type and event-source metadata. |
| `az containerapp job execution list` | Lists job execution history to correlate execution count with queue backlog timing. |
| `az containerapp job list` | Enumerates all jobs in the environment and filters by event-driven trigger type. |
| `--name` | Targets the specific job whose execution storm is being investigated. |
| `--output` | Formats as JSON (full config) or table (quick review). |
| `--query` | Filters the job list to show only trigger type and name for fast scanning. |
| `--resource-group` | Ensures queries target the correct resource group. |

KQL to correlate burst timing:

```kusto
let JobName = "job-myapp";
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(6h)
| where JobName_s == JobName or ContainerAppName_s == JobName
| where Log_s has_any ("Execution", "Started", "Completed", "Failed")
| summarize Executions=count() by bin(TimeGenerated, 5m), Reason_s
| order by TimeGenerated asc
```

## Resolution

1. Reduce event-trigger aggressiveness and cap safe concurrency in the job definition.
2. Fix duplicate-delivery patterns before increasing throughput.
3. If poison messages are present, route them away from the hot path and retry them separately.
4. Validate the tuned configuration against a controlled backlog instead of production surge traffic.

```bash
az containerapp job show \
    --name "$JOB_NAME" \
    --resource-group "$RG" \
    --output yaml
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp job show` | Reads the post-change job definition to verify trigger settings and scaling limits are applied. |
| `--name` | Targets the event-driven job whose configuration was tuned. |
| `--output` | Emits YAML to preserve nested trigger and scale configuration structure. |
| `--resource-group` | Ensures the query targets the correct resource group. |

## Prevention

- Define explicit upper bounds for job concurrency.
- Dead-letter poison messages instead of allowing infinite business retries.
- Load-test event jobs with realistic backlog shapes.
- Document the mapping between queue depth, execution fan-out, and downstream capacity.

## See Also

- [Scheduled Job Missed](./scheduled-job-missed.md)
- [Event Job Storm Lab](../../lab-guides/event-job-storm.md)
- [Container App Job Execution Failure](./container-app-job-execution-failure.md)

## Sources

- [Azure Container Apps jobs](https://learn.microsoft.com/en-us/azure/container-apps/jobs)
- [Create a job with the Azure CLI](https://learn.microsoft.com/en-us/azure/container-apps/jobs-get-started-cli)
- [Azure CLI `az containerapp job` reference](https://learn.microsoft.com/en-us/cli/azure/containerapp/job)
