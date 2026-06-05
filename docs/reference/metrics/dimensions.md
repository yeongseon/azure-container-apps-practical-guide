---
content_validation:
  status: verified
  last_reviewed: '2026-06-05'
  reviewer: agent
  core_claims:
  - claim: Container Apps metrics support Replica and Revision dimensions for splitting and filtering.
    source: https://learn.microsoft.com/azure/container-apps/metrics
    verified: true
  - claim: The Portal Metrics blade displays friendly dimension names (e.g., "Replica") but the az CLI --filter flag requires the API key (e.g., "podName"), and using the wrong key returns BadRequest.
    source: https://learn.microsoft.com/azure/container-apps/metrics
    verified: true
---
# Metric Dimensions

Azure Container Apps metrics support dimensions for splitting and filtering in the Portal Metrics blade and via `az monitor metrics list --filter`. However, the dimension names shown in the Portal are **display names** (friendly labels like "Replica"), while the `az monitor metrics list --filter` flag requires the underlying **API filter key** (e.g., `podName`). Using the wrong key -- for example, passing `replicaName eq '*'` instead of `podName eq '*'` -- returns a `BadRequest` error from the metrics service. This page maps every display name to its corresponding API key so you can write correct CLI queries on the first attempt.

!!! warning "Portal display name vs API filter key"
    The "Replica" chip in the Portal Metrics blade maps to the API filter key `podName`, **not** `replicaName`. Calling the API with `replicaName eq '*'` returns `BadRequest`. Always use the API filter keys listed in the table below when constructing `--filter` arguments for `az monitor metrics list`. The Portal handles this translation automatically when you click a chip, but CLI and SDK callers must use the API key directly.

## Dimension mapping table

The table below lists every metric published under the `Microsoft.App/containerapps` namespace along with the exact `--filter` dimension keys accepted by the Azure Monitor metrics API. These were verified by observing the `BadRequest` error messages returned when unsupported dimension keys are requested.

| Metric | Portal display dimensions | Supported `--filter` API keys | Notes |
|---|---|---|---|
| `UsageNanoCores` | Replica, Revision | `revisionName`, `podName` | "Replica" in Portal = `podName` in API |
| `WorkingSetBytes` | Replica, Revision | `revisionName`, `podName` | |
| `RxBytes` | Replica, Revision | `revisionName`, `podName` | |
| `TxBytes` | Replica, Revision | `revisionName`, `podName` | |
| `RestartCount` | Replica, Revision | `revisionName`, `podName` | |
| `Requests` | Replica, Revision, Status Code, Status Code Category | `revisionName`, `podName`, `statusCodeCategory`, `statusCode` | Four dimension keys available |
| `Replicas` | Revision | `revisionName` | No replica-level split (this metric counts replicas) |
| `CoresQuotaUsed` | Revision | `revisionName` | |
| `TotalCoresQuotaUsed` | None | (no dimensions) | Already an aggregate for the resource |
| `CpuPercentage` | Replica | `podName` | No `revisionName` split |
| `MemoryPercentage` | Replica | `podName` | No `revisionName` split |
| `GpuUtilizationPercentage` | Replica, Revision | `revisionName`, `podName` | |
| `Resiliency*` (all six) | Revision | `revisionName` | No replica-level split on resiliency metrics |
| `ResponseTime` | Status Code, Status Code Category | `statusCodeCategory`, `statusCode` | No replica or revision split |

For the `Microsoft.App/managedEnvironments` namespace:

| Metric | Portal display dimensions | Supported `--filter` API keys | Notes |
|---|---|---|---|
| `NodeCount` | Workload Profile Name | `workloadProfileName` | |
| `IngressUsageNanoCores` | Pod Name, Node Name | `podName`, `nodeName` | These refer to ingress-controller pods, not app replicas |
| `IngressUsageBytes` | Pod Name, Node Name | `podName`, `nodeName` | |
| `IngressCpuPercentage` | Pod Name, Node Name | `podName`, `nodeName` | |
| `IngressMemoryPercentage` | Pod Name, Node Name | `podName`, `nodeName` | |
| `EnvCoresQuotaLimit` | None | (no dimensions) | Deprecated |
| `EnvCoresQuotaUtilization` | None | (no dimensions) | Deprecated |

## CLI usage examples

Split CPU usage by replica (the Portal "Replica" chip):

```bash
az monitor metrics list \
    --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.App/containerApps/$APP_NAME" \
    --metric CpuPercentage \
    --aggregation Average \
    --interval PT5M \
    --filter "podName eq '*'" \
    --output table
```

| Command | Why it is used |
|---|---|
| `az monitor metrics list --filter "podName eq '*'"` | Splits per-replica CPU usage using the API dimension key `podName` (Portal displays "Replica"). |

Split requests by status code category:

```bash
az monitor metrics list \
    --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.App/containerApps/$APP_NAME" \
    --metric Requests \
    --aggregation Total \
    --interval PT5M \
    --filter "statusCodeCategory eq '*'" \
    --output table
```

| Command | Why it is used |
|---|---|
| `az monitor metrics list --filter "statusCodeCategory eq '*'"` | Splits HTTP requests into 2xx/3xx/4xx/5xx categories. |

Split node count by workload profile (environment-level metric):

```bash
az monitor metrics list \
    --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.App/managedEnvironments/$CONTAINER_ENV" \
    --metric NodeCount \
    --aggregation Maximum \
    --interval PT5M \
    --filter "workloadProfileName eq '*'" \
    --output table
```

| Command | Why it is used |
|---|---|
| `az monitor metrics list --filter "workloadProfileName eq '*'"` | Splits node count by workload profile for capacity planning. |

Wherever a metric section in this guide refers to `podName`, that is the literal value to pass to `--filter "podName eq '*'"`. The Portal chip will still display "Replica" because that is the friendly display name.

## See Also

- [Metrics Overview](index.md)
- [Container App Metrics](container-app-metrics.md)
- [Environment Metrics](managed-environment-metrics.md)
- [Percentage Metrics](percentage-metrics.md)
- [Dimensions](dimensions.md)
- [KEDA Observability](keda-observability.md)
- [Evidence and Captures](evidence-and-captures.md)

## Sources

- [Supported metrics for Microsoft.App/containerapps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/metrics)
- [Supported metrics for Microsoft.App/managedEnvironments (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/metrics)
- [Azure Monitor metrics overview (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/essentials/data-platform-metrics)
