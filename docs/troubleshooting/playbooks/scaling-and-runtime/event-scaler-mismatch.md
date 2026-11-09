---
content_sources:
  diagrams:
    - id: troubleshooting-decision-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app#scale-rules
        - https://learn.microsoft.com/en-us/azure/container-apps/jobs
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: ai-agent
  core_claims:
    - claim: Azure Container Apps can scale based on HTTP traffic, CPU, memory, and custom scale rules.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
    - claim: Scale rules define the conditions under which a container app scales.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
---
# Event Scaler Mismatch

## 1. Summary

### Symptom

Queue or event-driven workloads do not scale as expected because trigger metadata does not match the event source. Common symptoms include growing backlog while replicas remain low, scale events with wrong trigger metadata or authentication errors, and event-driven jobs that run sporadically despite available messages.

### Why this scenario is confusing

A scaler mismatch can look like low traffic, platform delay, or an insufficient `maxReplicas` setting. In practice, backlog can exist while the scaler cannot read the metric source at all, and increasing max replicas does nothing if the trigger metadata is wrong.

### Troubleshooting decision flow

<!-- diagram-id: troubleshooting-decision-flow -->
```mermaid
flowchart TD
    accTitle: Diagnose a custom event scaler mismatch
    accDescr: Validate event-source metadata and scaler authentication before tuning thresholds, then use a controlled backlog to verify that replicas respond within configured limits.

    START[Backlog grows without scale-out] --> SOURCE{Rule type and metadata match<br/>the actual event source?}
    SOURCE -->|No| METADATA[Correct queue, topic,<br/>subscription, or consumer metadata]
    SOURCE -->|Yes| AUTH{Scaler can authenticate<br/>to the event source?}
    AUTH -->|No| CREDENTIALS[Correct secret mapping<br/>or managed identity]
    AUTH -->|Yes| METRIC{Scaler can read a<br/>nonzero event metric?}
    METRIC -->|No| CONNECTIVITY[Check network path,<br/>permissions, and source state]
    METRIC -->|Yes| LIMITS{Threshold and replica limits<br/>match the backlog?}
    LIMITS -->|No| TUNE[Tune threshold, polling,<br/>minimum, and maximum]
    LIMITS -->|Yes| TEST[Create a controlled backlog]
    METADATA --> TEST
    CREDENTIALS --> TEST
    CONNECTIVITY --> TEST
    TUNE --> TEST
    TEST --> SCALE{Replicas increase?}
    SCALE -->|Yes| DONE[Rule path verified]
    SCALE -->|No| EVIDENCE[Collect scaler system logs]
```

*Figure: Metadata, scaler authentication, metric access, and scale limits are separate prerequisites for custom scaling.*

## 2. Common Misreadings

- "No messages are arriving." Backlog can exist while scaler cannot read metric source.
- "Increase max replicas only." Wrong trigger metadata prevents any meaningful scale-out.

## 3. Competing Hypotheses

| Hypothesis | Typical Evidence For | Typical Evidence Against |
|---|---|---|
| Trigger metadata mismatch | Errors mention queue name, consumer group, or subscription | Metadata matches source and works elsewhere |
| Scaler auth failure | Secret/identity errors in scaler logs | Auth successful and metric endpoint reachable |
| Poll interval too slow for burst traffic | Delayed scale-out despite healthy trigger auth | Immediate scaling after each event burst |

## 4. What to Check First

### Metrics

- Backlog depth and consumer lag versus replica count.

### Logs

```kusto
let AppName = "ca-myapp";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("keda", "trigger", "queue", "eventhub", "servicebus", "scale")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

### Platform Signals

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.scale.rules" --output json
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --output table
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the scale rule definition to verify trigger type (KEDA scaler name), metadata fields, and authentication references. |
| `az containerapp replica list` | Lists current replicas and their states to confirm whether they are responding to scale events or staying idle despite backlog. |
| `--name` | Targets the app by name to retrieve its specific scale rule and replica state. |
| `--output` | Formats `show` as `json` (detailed rule structure) and `replica list` as `table` (human-readable replica counts). |
| `--query` | Extracts `scale.rules` from the app definition to isolate trigger configuration from unrelated fields. |
| `--resource-group` | Keeps scale-rule and replica evidence within the deployment being diagnosed. |

## 5. Evidence to Collect

### Required Evidence

| Evidence | Command/Query | Purpose |
|---|---|---|
| Scale rule definition | `az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.scale.rules" --output json` | Validate trigger metadata |
| Replica state | `az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --output table` | Confirm whether scaling is happening |
| System scaler logs | `az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system` | Find KEDA trigger or auth errors |
| Secret inventory | `az containerapp secret list --name "$APP_NAME" --resource-group "$RG"` | Validate secret-backed auth inputs |
| Identity configuration | `az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "identity" --output json` | Verify managed identity for scaler auth |
| KEDA-related platform logs | KQL on `ContainerAppSystemLogs_CL` | Correlate backlog and scaler behavior |

### Useful Context

- Event source type and exact metadata values in use.
- Expected backlog threshold and acceptable reaction time.
- Whether the issue affects a Container App or an event-driven job.

Observed scaler lifecycle signal when rule initialization succeeds:

```text
Reason_s             Type_s    Typical count
-------------------  --------  -------------
KEDAScalersStarted   Normal    6
```

## 6. Validation and Disproof by Hypothesis

### H1: Trigger metadata mismatch

**Signals that support:**

- Errors mention queue name, consumer group, or subscription.
- Backlog grows while scale rules show metadata that does not match the actual source.
- Scale rule initialization never reaches the expected healthy pattern.

**Signals that weaken:**

- Metadata matches source and works elsewhere.
- `KEDAScalersStarted` appears as expected and scaling still does not happen for another reason.

**What to verify:**

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.scale.rules" --output json
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the scale rule metadata (queue name, subscription, topic, consumer group) to compare against the actual event source configuration. |
| `az containerapp logs show` | Displays system logs showing KEDA initialization or metadata parsing errors (e.g., "queue not found", "invalid subscription name"). |
| `--name` | Names the app whose scaler rules and replica state are being compared. |
| `--output` | Formats as `json` so rule metadata can be extracted and validated line-by-line. |
| `--query` | Extracts `scale.rules` to show only the trigger definition without extra fields. |
| `--resource-group` | Scopes metadata and system-log checks to the app resource group. |
| `--type` | Requests `system` logs specifically (where KEDA logs appear). |

```kusto
let AppName = "ca-myapp";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("keda", "trigger", "queue", "eventhub", "servicebus", "scale")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

**Disproof logic:**

If the scale rule metadata exactly matches the event source and system logs show successful scaler initialization, metadata mismatch is less likely.

### H2: Scaler auth failure

**Signals that support:**

- Secret or identity errors appear in scaler logs.
- Secret-backed auth values are missing or wrong.
- Managed identity is absent or not the one expected for the scaler.

**Signals that weaken:**

- Auth successful and metric endpoint reachable.
- Secret inventory and identity configuration match the expected scaler configuration.

**What to verify:**

```bash
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
az containerapp secret list --name "$APP_NAME" --resource-group "$RG"
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "identity" --output json
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp logs show` | Retrieves system logs to find scaler auth failures (e.g., "Unauthorized", "Secret not found", "Identity not available"). |
| `az containerapp secret list` | Lists all defined secrets to confirm that the secret referenced in scale-rule auth actually exists and is not a typo. |
| `az containerapp show` | Reads the identity configuration (managed identity or service principal) to verify it is assigned to the app and has permission to the event source. |
| `--name` | Selects the app with the suspected metadata mismatch. |
| `--output` | Formats as `json` to display the full identity object. |
| `--query` | Extracts the `identity` field to show assigned identity details. |
| `--resource-group` | Looks up secrets and identity in the group that owns the scaler configuration. |
| `--type` | Requests `system` logs (where auth errors appear). |

**Disproof logic:**

If system logs do not show auth failures and both secrets and identity are correct, auth is unlikely to be the main blocker.

### H3: Poll interval too slow for burst traffic

**Signals that support:**

- Delayed scale-out despite healthy trigger auth.
- Replica count eventually increases, but too late for the burst profile.
- System logs show healthy scaler behavior without metadata or auth errors.

**Signals that weaken:**

- Immediate scaling after each event burst.
- No scaling at all even when backlog is sustained, which points back to metadata or auth issues.

**What to verify:**

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.scale.rules" --output json
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --output table
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the scale rule to extract polling interval and threshold settings (e.g., `pollingInterval`, `desiredReplicas`). |
| `az containerapp replica list` | Lists replicas with their creation times to measure the lag between backlog arrival and scale-out response. |
| `--name` | Points secret, identity, and system-log checks at the scaler-auth failure. |
| `--output` | Formats as `json` for rule details and `table` for replica timeline. |
| `--query` | Extracts `scale.rules` to focus on timing configuration. |
| `--resource-group` | Reads polling rules and replica state from the affected workload group. |

**Disproof logic:**

If scaling reacts immediately during synthetic backlog tests, polling and threshold tuning are not the primary cause.

## 7. Likely Root Cause Patterns

| Pattern | Frequency | First Signal | Typical Resolution |
|---|---|---|---|
| Wrong queue, topic, subscription, or consumer group | Common | Scaler logs mention trigger metadata | Correct scale rule metadata |
| Missing secret or identity for scaler auth | Common | Auth errors in system logs | Fix secret reference or managed identity |
| Threshold and polling tuned for steady traffic, not bursts | Occasional | Delayed scale-out without auth errors | Tune polling and threshold settings |

## 8. Immediate Mitigations

1. Verify scaler metadata (queue/subscription/topic names) exactly.
2. Fix scaler authentication via managed identity or secret reference.
3. Tune trigger thresholds and polling intervals for workload profile.
4. Generate test events and confirm replica reaction time.

## 9. Prevention

- Keep scaler metadata in version-controlled IaC.
- Add synthetic event checks after deploy.
- Maintain runbook per event source with expected lag and thresholds.

## See Also

- [HTTP Scaling Not Triggering](http-scaling-not-triggering.md)
- [Container App Job Execution Failure](../platform-features/container-app-job-execution-failure.md)
- [Scaling Events KQL](../../kql/scaling-and-replicas/scaling-events.md)

## Sources

- [Scale applications in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Set scaling rules in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app#scale-rules)
- [Jobs in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/jobs)
