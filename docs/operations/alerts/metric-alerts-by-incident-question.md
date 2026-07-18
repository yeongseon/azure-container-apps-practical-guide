---
content_validation:
  status: verified
  last_reviewed: '2026-06-05'
  reviewer: agent
  core_claims:
    - claim: Azure Monitor metric alert rules evaluate platform metrics on a fixed `evaluation-frequency` and `window-size` and do not natively compute ratios between metrics.
      source: https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-types
      verified: true
    - claim: Container Apps publishes `ResponseTime` as an Average metric in Preview; percentile (p95/p99) latency requires Application Insights or log-based alerting.
      source: https://learn.microsoft.com/en-us/azure/container-apps/metrics
      verified: true
    - claim: The `Replicas` metric splits by `revisionName` and does not attribute scale events to specific KEDA scalers; scaler attribution requires system logs.
      source: https://learn.microsoft.com/en-us/azure/container-apps/observability
      verified: true
---
# Metric alerts by incident question

When an on-call SRE asks "what's the right alert for incident X?", this page maps the question to the exact metric, aggregation, split dimension, and a starting threshold. The page is a **selection aid**, not an alert-rule tutorial — for CLI syntax, action groups, and Portal capture of alert blades, see [Alerting for Container Apps](index.md). For metric definitions, denominators, and dimensions, see the [Container Apps metrics reference](../../reference/metrics/index.md).

## Prerequisites

You already know how to create an Azure Monitor metric alert (`az monitor metrics alert create`) — that lives in [Alerting for Container Apps](index.md#azure-monitor-alert-rules). This page assumes you are looking for the *correct metric and threshold*, not the CLI shape.

```bash
export RG="rg-myapp"
export APP_NAME="ca-myapp"
```

## When to Use

Use this page in three situations:

- **Designing a new metric alert** — you have an incident question ("what should page me when CPU saturates?") and need to pick the metric, aggregation, and split before writing the `az monitor metrics alert create` command.
- **Evaluating an existing alert's signal-to-noise** — your current alert fires too often or never fires, and you want to confirm you chose the right metric and aggregation, or check whether a metric alert is even the right vehicle.
- **Incident triage** — an alert just fired and you want to confirm what the metric actually measures, what its denominator is, and whether a companion signal (e.g., `RestartCount` confirming `MemoryPercentage`) should also have fired.

Skip this page if you need: CLI syntax (see [Alerting for Container Apps](index.md)), threshold-tuning methodology (see [Recommended Threshold Baseline](index.md#recommended-threshold-baseline)), or metric definitions (see the [metrics reference](../../reference/metrics/index.md)).

## Procedure

1. Scan the **Incident question** column for the symptom you want to alert on.
2. Check the **Use when / Preconditions** column — many rows are only valid under specific workload conditions (always-on apps, profile-pinned envs, attached resiliency policies, etc.). Skip rows whose preconditions do not match your app.
3. Click the metric link to confirm the exact dimension names, denominators, and observed-data sample in the [Metrics reference](../../reference/metrics/index.md).
4. Use the starting threshold as a **first draft**, then tune from 2-4 weeks of baseline data per the methodology in [Alerting for Container Apps → Recommended Threshold Baseline](index.md#recommended-threshold-baseline).
5. Write the alert using the CLI shape documented in [Azure Monitor alert rules](index.md#azure-monitor-alert-rules).

### Incident question to metric mapping

!!! note "Dimension display name vs API filter key"
    The Portal Metrics blade chip says "Replica", but the API filter key (and the value you pass to `az monitor metrics list --filter`) is **`podName`**. Calling the API with `replicaName eq '*'` returns `BadRequest`. The `Split by` column below uses the API key. See [Dimension display name vs API filter name](../../reference/metrics/dimensions.md) for the full per-metric matrix.

| Incident question | Use when / Preconditions | Metric or signal | Aggregation | Split by | Starting threshold | Severity | Notes |
|---|---|---|---|---|---|---|---|
| CPU saturated on a replica? | App is provisioned with `--cpu` and is CPU-bound (web, encoders, ML inference, etc.) | [`CpuPercentage`](../../reference/metrics/container-app-metrics.md#cpupercentage-cpu-usage-percentage-preview) | Avg, Max | `podName` | > 85% Avg for 10m | sev2 | Preview metric. Denominator is the configured `--cpu` value, not host capacity. `CpuPercentage` supports `podName` only — `revisionName` returns `BadRequest`. |
| Memory pressure / OOM risk? | App is provisioned with `--memory` | [`MemoryPercentage`](../../reference/metrics/container-app-metrics.md#memorypercentage-memory-percentage-preview) + [`WorkingSetBytes`](../../reference/metrics/container-app-metrics.md#workingsetbytes-memory-working-set-bytes) | Avg | `podName` | > 85% Avg for 10m | sev2 | Preview metric. Pair with the next row as a confirming companion alert. `MemoryPercentage` supports `podName` only. |
| OOM kills are recurring? | A memory alert has fired, or you want an independent confirming signal | [`RestartCount`](../../reference/metrics/container-app-metrics.md#restartcount-total-replica-restart-count) | Total | `podName` | > 0 over 5m, repeating | sev1 | Confirms the memory pressure converted into kills. Use `podName` to find the failing replica; add a second alert split by `revisionName` if you also want rollout attribution. |
| 5xx errors are climbing? | App has external ingress; you want platform-metric alerting (no ratio math) | [`Requests`](../../reference/metrics/container-app-metrics.md#requests-requests) | Total | `statusCodeCategory` | > N requests / 5m where `statusCodeCategory=5xx` (tune per app) | sev2 | Azure Monitor metric alerts do not natively compute "5xx as percent of total". For true error-rate / SLO alerting see [Use logs or App Insights instead](#use-logs-or-app-insights-instead) below. |
| Average latency degraded? | You accept an Average latency signal (not percentile) | [`ResponseTime`](../../reference/metrics/container-app-metrics.md#responsetime-average-response-time-preview) | Avg | `statusCodeCategory=2xx` (so 5xx fast-fail does not mask 2xx slowdown) | > 1500ms for 10m | sev2 | Preview metric. **Average only** — for p95/p99 use App Insights percentile alerts (see below). |
| Replicas dropped to zero (always-on app)? | `min-replicas > 0` is the intentional design AND the app must stay warm (low-latency external ingress, etc.) | [`Replicas`](../../reference/metrics/container-app-metrics.md#replicas-replica-count) | Min | `revisionName` | == 0 for 2m | sev1 | **Skip this row entirely** if `min-replicas=0` is intentional (event-driven, idle-tolerant, batch). |
| Replicas pinned at max (capacity saturation)? | Paired with rising `Requests`, `ResponseTime`, or CPU/memory saturation — alone it can be legitimate load | [`Replicas`](../../reference/metrics/container-app-metrics.md#replicas-replica-count) AND a saturation signal | Max | `revisionName` | `Replicas` == `max-replicas` for 15m | sev3 alone, sev2 if paired | A single-metric alert on `Replicas` at max produces false positives during legitimate load spikes; the pairing matters. |
| Retry storm (intra-env)? | You have a [retry resiliency policy](https://learn.microsoft.com/en-us/azure/container-apps/service-discovery-resiliency) attached | [`ResiliencyRequestRetries`](../../reference/metrics/container-app-metrics.md#resiliencyrequestretries-resiliency-request-retries) | Total | `revisionName` (or none) | Large delta over 7-day rolling baseline | sev2 | Pairs with [`ResiliencyEjectionsAborted`](../../reference/metrics/container-app-metrics.md#resiliencyejectionsaborted-resiliency-ejections-aborted) (circuit breaker engaged). Tune from observed baseline, not absolute count. |
| Connection pool exhausted (downstream slow)? | You have a pool policy (`http1MaxPendingRequests`) attached | [`ResiliencyRequestsPendingConnectionPool`](../../reference/metrics/container-app-metrics.md#resiliencyrequestspendingconnectionpool-resiliency-requests-pending-connection-pool) | Maximum | `revisionName` | > N pending (tune from baseline) for 5m | sev2 | This is a queue-depth gauge; use `Maximum` to catch saturation spikes. `Avg` can hide short bursts. |
| Per-app vCPU reservation approaching its scaling ceiling? | App uses HTTP scaler or KEDA with `max-replicas` set, AND reserved cores matter for cost/quota planning | [`TotalCoresQuotaUsed`](../../reference/metrics/container-app-metrics.md#totalcoresquotaused-total-reserved-cores-per-container-app) | Max | (none — this metric has no dimensions) | > 80% of `max-replicas × --cpu` for 5m | sev3 | Per-container-app metric, not per-environment. For environment-level quota saturation see [Rollback / Troubleshooting](#rollback-troubleshooting). |
| Workload-profile node fleet undersized? | Env uses workload profiles (not Consumption-only) AND the profile has `min-nodes` < `max-nodes` AND apps are sensitive to scheduling delays | [`NodeCount`](../../reference/metrics/managed-environment-metrics.md#nodecount-workload-profile-node-count-preview) | Min | `workloadProfileName` | < expected baseline for 5m | sev2 | Preview metric. Does not apply to Consumption-only environments. Pair with replica-scheduling-failure log queries. |
| Which KEDA scaler caused the last replica change? | You need diagnostic attribution *after* a scale event, NOT proactive alerting | **Not a metric alert** — use system logs + KQL | N/A | N/A | N/A | N/A | See [KEDA scaler observability](../../reference/metrics/keda-observability.md) and the [KEDA scaler metrics KQL pack](../../troubleshooting/kql/scaling-and-replicas/keda-scaler-metrics.md). The Metrics blade alone cannot attribute scale events to specific scalers — `Replicas` only splits by `revisionName`. |

### Use logs or App Insights instead

Azure Monitor metric alerts on Container Apps platform metrics are the fastest signal (1-2 minute evaluation), but they have hard limits. Use these alternatives when the metric-alert column above cannot express what you need.

| Need | Why metric alerts fall short | Use instead |
|---|---|---|
| 5xx as percent of total requests (SLO-style) | `Requests` metric alerts threshold absolute counts; no native ratio math between two metric splits | Azure Monitor log alert against the Application Insights `requests` table (`requests \| summarize errorRate=...`) |
| p95 / p99 latency | `ResponseTime` is Average only | Azure Monitor log alert against the Application Insights `requests` table (`requests \| summarize percentile(duration, 95) ...`) |
| Semantic error patterns from app stdout (e.g., specific exception class, retry-after-503) | Platform metrics have no log content | [Log search alert on `ContainerAppConsoleLogs`](index.md#log-based-alerts-with-kql) |
| Environment-wide quota saturation | `TotalCoresQuotaUsed` is per-container-app; no env-wide quota metric exists | `az containerapp env list-usages` poll + threshold logic in a Logic App or scheduled job |
| KEDA scaler attribution for a specific replica change | `Replicas` metric does not carry scaler/trigger identity | [KEDA scaler observability](../../reference/metrics/keda-observability.md) + [KQL pack](../../troubleshooting/kql/scaling-and-replicas/keda-scaler-metrics.md) |

## Verification

Before you commit a new metric-alert rule to production, confirm the metric is actually being emitted for your specific app and that your aggregation produces non-empty values over your window.

1. Confirm the metric is published for your resource (catches metric-typo and preview-metric-not-yet-available errors):

    ```bash
    az monitor metrics list-definitions \
      --resource "/subscriptions/<subscription-id>/resourceGroups/$RG/providers/Microsoft.App/containerApps/$APP_NAME" \
      --query "[?name.value=='CpuPercentage']"
    ```

    | Flag | Purpose |
    |---|---|
    | `--resource` | Full Azure resource ID of the target container app; `metrics list-definitions` is resource-scoped, so the shorter `--name` form is not accepted here. |
    | `--query` | JMESPath filter on the response to verify the specific metric ID (`CpuPercentage`) is actually published for this resource and not just listed in Azure-wide reference docs. |

2. Dry-run the aggregation over a recent window to confirm non-empty data and a realistic baseline. The `--offset` flag accepts portable `##d##h` notation (default `1h`) and avoids OS-specific `date` substitutions:

    ```bash
    az monitor metrics list \
      --resource "/subscriptions/<subscription-id>/resourceGroups/$RG/providers/Microsoft.App/containerApps/$APP_NAME" \
      --metric "CpuPercentage" \
      --aggregation Average \
      --interval PT5M \
      --offset 2h
    ```

    | Flag | Purpose |
    |---|---|
    | `--resource` | Targets the exact Container App resource whose metric stream you plan to alert on, so the dry run reflects the same scope the future alert rule will evaluate. |
    | `--metric "CpuPercentage"` | Chooses the specific metric signal under review, which lets the operator confirm that this incident question maps to a real Container Apps metric instead of a guessed name. |
    | `--aggregation Average` | Tests the same rollup style an alert would use, which matters because averages can look healthy even when single spikes would have triggered a `Maximum`-based rule. |
    | `--interval PT5M` | Buckets the series into 5-minute windows so you can judge whether the alerting granularity is too coarse or too noisy for incident response. |
    | `--offset 2h` | Pulls a recent two-hour sample window, which is long enough to confirm the metric is emitting and to estimate a realistic threshold before you create the alert. |

3. After creating the rule, confirm it is firing as expected against historical data by reviewing the rule's **Fired alerts** tab in the Portal, per [Alerting for Container Apps → Portal view](index.md#portal-view-container-app-alerts-blade).

## Rollback / Troubleshooting

If your alert misfires (too noisy or silent), the rollback is usually **not** to disable the rule but to retune the threshold or change the metric. Use this decision order:

- **Alert fires too often (false positives)** → Re-check the **Use when / Preconditions** column for your row. Common cause: alerting `Replicas == max-replicas` without a saturation-signal pairing produces false positives during legitimate load spikes. Adjust by adding the paired signal or by widening the window.
- **Alert never fires when you expect it to** → Confirm the metric is published for your app via the `list-definitions` command in the **Verification** section above. Preview metrics (`CpuPercentage`, `MemoryPercentage`, `ResponseTime`, `NodeCount`, etc.) may not be available in all regions/SKUs.
- **You picked a metric alert but actually need ratio math or log content** → Switch to the [Use logs or App Insights instead](#use-logs-or-app-insights-instead) table above and migrate the rule to a log-based or Application Insights alert.
- **Environment-wide quota saturation** → `TotalCoresQuotaUsed` is per-app, not per-environment. For env-wide quota use `az containerapp env list-usages` in a scheduled job; there is no metric alert for this dimension.
- **Threshold tuning methodology** (collecting 2-4 weeks of baseline before locking thresholds) → [Alerting for Container Apps → Recommended Threshold Baseline](index.md#recommended-threshold-baseline).

To disable a rule temporarily without deleting it:

```bash
az monitor metrics alert update \
  --name "<alert-name>" \
  --resource-group "$RG" \
  --enabled false
```

| Flag | Purpose |
|---|---|
| `--name` | The exact name of the metric alert rule to update (case-sensitive). |
| `--resource-group` | The resource group that owns the alert rule (not the resource group of the monitored container app). |
| `--enabled false` | Disables evaluation without deleting the rule. Re-enable with `--enabled true` to resume; severity, conditions, and action groups are preserved. |

## What this page does not cover

This page is scoped to **metric-alert selection**. The following are owned by other pages — do not duplicate the configuration here:

- **Metric alert CLI syntax** (`az monitor metrics alert create`), action groups, notification channels, severity-to-channel routing → [Alerting for Container Apps](index.md).
- **Log-based and Activity-log alerts** (the full KQL alert lifecycle) → [Alerting for Container Apps → Log-Based Alerts with KQL](index.md#log-based-alerts-with-kql) and [Activity Log Alert Example](index.md#activity-log-alert-example).
- **Portal screenshots** of the Alerts blade, Alert rules blade, and Alert rule detail → [Alerting for Container Apps → Portal view sections](index.md#portal-view-container-app-alerts-blade).
- **Metric definitions** (what each metric measures, denominators, dimensions, observed sample data, capture screenshots) → [Container Apps metrics reference](../../reference/metrics/index.md).

## See Also

- [Alerting for Container Apps](index.md) — alert-rule CLI, action groups, baseline thresholds, Portal screenshots
- [Container Apps metrics reference](../../reference/metrics/index.md) — metric IDs, aggregations, dimensions, denominators, observed sample data
- [KEDA scaler observability](../../reference/metrics/keda-observability.md) — system-logs-only attribution for scale events
- [KEDA scaler metrics (KQL pack)](../../troubleshooting/kql/scaling-and-replicas/keda-scaler-metrics.md)
- [Scaling events (KQL pack)](../../troubleshooting/kql/scaling-and-replicas/scaling-events.md)
- [Observability Operations (monitoring index)](../monitoring/index.md)
- [Recovery and Incident Readiness](../recovery/index.md)

## Sources

- [Set alerts in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/alerts)
- [Monitor metrics in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/metrics)
- [Service discovery and resiliency in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/service-discovery-resiliency)
- [Types of Azure Monitor alerts](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-types)
- [Application Insights query alerts (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-log-alert-rule)
