---
content_validation:
  status: verified
  last_reviewed: '2026-06-05'
  reviewer: agent
  core_claims:
    - claim: KEDA scaler-level metrics are not surfaced as Azure Monitor platform metrics and are only reachable through system logs, source-side scaler metrics, or the KEDA OTel export preview.
      source: https://learn.microsoft.com/en-us/azure/container-apps/metrics
      verified: true
---
# KEDA Scaler Observability

KEDA is the autoscaler embedded inside the Container Apps data plane: every scale-out and scale-in on `Replicas` is a KEDA reconciliation. The `Replicas` metric tells you *that* a change happened; it does not tell you *which* scaler fired (HTTP concurrency? CPU? queue depth?), *what value* the scaler observed, or *why* a scale event was suppressed. KEDA's own scaler-level metrics are not surfaced as Azure Monitor platform metrics — they are only reachable through the surfaces below.

**[Observed]** In this environment, system logs exposed scaler lifecycle, failure, and rescale events, while Activity Log did not show per-rescale runtime events. **[Not Proven]** The KEDA OTel export path was not enabled in this environment, so that part of this section is based on Microsoft Learn rather than live observation. This section catalogues the three places you *can* observe KEDA behavior, the gap each surface has, and the KQL pattern that closes the most common gap.

## The three observable surfaces

| Surface | How to enable | What you get | Caveats |
|---|---|---|---|
| **`ContainerAppSystemLogs_CL` in Log Analytics** | Always on if Log Analytics is attached to the environment (`--logs-destination log-analytics`) | Scaler lifecycle (`KEDAScalersStarted`), validation failures (`ScaledObjectCheckFailed`), and the actual rescale decisions (`SuccessfulRescale`). The fired scaler name is embedded in the log message body. | The `EventSource_s` column does not consistently match the scaler family (see warning below). Filter primarily on `Reason_s`, not `EventSource_s`. |
| **Source-side scaler metric (where applicable)** | Query the scaler's source system directly — Service Bus message count, Storage Queue depth, custom HTTP scaler target, etc. | The exact value KEDA polled at decision time, with the source system's own granularity. | Each scaler has a different source; there is no unified Azure Monitor metric for "scaler current value". This is often the easier observability win because the source metric already exists in your monitoring stack. |
| **KEDA OTel export (Preview)** | `properties.openTelemetryConfiguration.metricsConfiguration.includeKeda: true` on the **environment**, plus a metrics-capable destination configured under the same block | KEDA internal metrics such as `keda.scaler.metrics.value`, `keda.scaler.active`, `keda.scaled.object.paused`, and scaler/scaled-object error metrics (some backends normalize these to Prometheus-style names such as `keda_scaler_metrics_value`) | Preview feature. Microsoft Learn documents metrics export to Datadog or a named OTLP endpoint; Application Insights doesn't accept metrics, and Learn does not document direct export to Azure Monitor platform metrics, Managed Prometheus, or Log Analytics as first-class `includeKeda` destinations |

## What system logs publish

Run this in Log Analytics to catalog the scaling-related `Reason_s` codes appearing in the last 6 hours:

```kusto
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(6h)
| where Reason_s in (
    "SuccessfulRescale",
    "KEDAScalersStarted",
    "ScaledObjectCheckFailed",
    "ScaledObjectReady"
)
| summarize Count = count() by EventSource_s, Reason_s, Type_s
| order by Count desc
```

The values below were observed in the shared Log Analytics workspace attached to both test environments over a 6-hour window. The `SuccessfulRescale` example below comes from `ca-loadtest-d38538` in `cae-basics-d38538`. The first row is the goal of this section: it is the only event source that ties a `Replicas` step to a scaler name.

| `EventSource_s` | `Reason_s` | `Type_s` | Count (this env, 6h) | What it means |
|---|---|---|---|---|
| `Scaling` | `SuccessfulRescale` | `Normal` | 2 | The HPA-equivalent inside KEDA decided to change the replica count. The log message body contains the new replica count and the scaler that triggered the change. |
| `KEDA` | `KEDAScalersStarted` | `Normal` | 18 | KEDA initialized the scalers attached to a ScaledObject. Logged once per ScaledObject lifecycle, typically at app create or revision activation. |
| `KEDA` | `ScaledObjectCheckFailed` | `Warning` | 70 | KEDA tried to validate the ScaledObject's trigger spec and found no usable trigger definition. **[Observed]** In this environment, the warning repeated roughly every 5 minutes on apps effectively pinned at a fixed replica count with no usable scale rule; other environments can also emit this for invalid trigger specs, including HTTP rules created before ingress is enabled. |

!!! warning "`SuccessfulRescale` was observed under `Scaling` in this environment"
    **[Observed]** In this environment, `SuccessfulRescale` arrived with `EventSource_s == "Scaling"`, not `EventSource_s == "KEDA"`. Treat that as current observed behavior rather than a guaranteed schema contract; to avoid missing real scale events, filter by `Reason_s == "SuccessfulRescale"` first and use `EventSource_s` only as a secondary classifier.

## Smoking-gun KQL — which scaler fired the rescale?

This query extracts the target replica count and scaler name from `SuccessfulRescale` events. Read it next to the `Replicas` metric timeline to answer both *what* scaled and *who* fired it.

```kusto
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(6h)
| where Reason_s == "SuccessfulRescale"
| extend ScalerName = coalesce(
    extract(@"(?i)by the scaler:\s*([^\s\.]+)", 1, Log_s),
    extract(@"(?i)scaler:\s*([^\s\.]+)", 1, Log_s)
)
| extend TargetReplicas = toint(extract(@"scaled to (\d+)", 1, Log_s))
| project TimeGenerated, ContainerAppName_s, TargetReplicas, ScalerName, Log_s
| order by TimeGenerated desc
```

Example output from the test environment (`ca-loadtest-d38538` has an HTTP scaler with `concurrentRequests=20`):

| TimeGenerated | ContainerAppName_s | TargetReplicas | ScalerName | `Log_s` excerpt |
|---|---|---|---|---|
| 2026-06-05T01:42:37Z | `ca-loadtest-d38538` | 10 | `http-scaler` | `"ca-loadtest-d38538 has been scaled to 10 by the scaler: http-scaler."` |
| 2026-06-05T01:33:12Z | `ca-loadtest-d38538` | 5 | `http-scaler` | `"ca-loadtest-d38538 has been scaled to 5 by the scaler: http-scaler."` |

For apps with multiple scale rules (e.g., HTTP + CPU + custom queue), the `ScalerName` column tells you which one won the reconciliation — KEDA selects the maximum desired replica count across all active scalers, then the log message names the winner.

## What is *not* available

These gaps are intentional to call out so support engineers don't waste time searching for them:

| Missing surface | Reality |
|---|---|
| A Portal Metrics blade dropdown entry called "KEDA Scaler Value" or similar | Not present. `Replicas` is the only KEDA-adjacent metric in the platform dropdown. |
| `Replicas` split by `triggerName` or `scaler` | Not supported. `Replicas` only splits by `revisionName`. To attribute a scale step to a scaler you must correlate the `Replicas` timeline alongside `ContainerAppSystemLogs_CL` `SuccessfulRescale` events using the KQL above — there is no in-Metrics-blade join. |
| KEDA metrics in Managed Prometheus by default | Not collected. Managed Prometheus on AKS scrapes KEDA's `/metrics` endpoint; Container Apps does not expose that endpoint to the user. Use the `includeKeda` OTel preview to a metrics-capable destination instead. |
| Activity Log entries for each scale-out | **[Observed]** Not present in this environment. Activity Log captured control-plane operations (revision create, app update, resiliency policy update) but no per-rescale runtime events, so treat it as a control-plane audit surface rather than a primary runtime scaling surface. |

!!! tip "The source-side metric is often the easier win"
    For Service Bus, Storage Queue, Event Hubs, and other Azure-native scalers, the *source* already publishes a platform metric (queue depth, lag, message count) in Azure Monitor. Alert on the *source* metric — your KEDA scaler is polling it anyway, and the source metric arrives without the OTel preview, without log parsing, and at lower latency than the system log surface.

For the matching KQL query pack, see [KEDA scaler metrics](../../troubleshooting/kql/scaling-and-replicas/keda-scaler-metrics.md) and [Scaling events](../../troubleshooting/kql/scaling-and-replicas/scaling-events.md).

## See Also

- [Metrics Overview](index.md)
- [Container App Metrics](container-app-metrics.md)
- [Environment Metrics](managed-environment-metrics.md)
- [Percentage Metrics](percentage-metrics.md)
- [Dimensions](dimensions.md)
- [KEDA Observability](keda-observability.md)
- [Evidence and Captures](evidence-and-captures.md)

## Sources

- [Supported metrics for Microsoft.App/containerapps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/metrics)
- [Supported metrics for Microsoft.App/managedEnvironments (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/metrics)
- [Azure Monitor metrics overview (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-platform-metrics)
