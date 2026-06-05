---
content_validation:
  status: verified
  last_reviewed: '2026-06-05'
  reviewer: agent
  core_claims: []
---
# Metrics Reference — Reorganized

!!! info "This page has been split into focused sub-pages"
    The metrics reference has been reorganized for easier navigation. Use the links below to find the content you need. Existing deep links are preserved via anchors on this page.

| Topic | Page |
|---|---|
| Overview, collection flow, quick lookup | [Metrics Overview](metrics/index.md) |
| Container App metrics (20 metrics) | [Container App Metrics](metrics/container-app-metrics.md) |
| Environment metrics (7 metrics) | [Environment Metrics](metrics/managed-environment-metrics.md) |
| CpuPercentage / MemoryPercentage denominators | [Percentage Metrics](metrics/percentage-metrics.md) |
| Portal display name vs API filter key | [Dimensions](metrics/dimensions.md) |
| KEDA scaler observability | [KEDA Observability](metrics/keda-observability.md) |
| Screenshots, lab environment, CLI queries | [Evidence and Captures](metrics/evidence-and-captures.md) |

## Preserved Anchors

The following anchors redirect to the new locations for backward compatibility.

<a id="container-app-metrics-microsoftappcontainerapps"></a>
**Container App metrics** → [Container App Metrics](metrics/container-app-metrics.md)

<a id="percentage-metric-denominators"></a>
**Percentage metric denominators** → [Percentage Metrics](metrics/percentage-metrics.md)

<a id="usagenanocores-cpu-usage"></a>
<a id="workingsetbytes-memory-working-set-bytes"></a>
<a id="rxbytes-network-in-bytes"></a>
<a id="txbytes-network-out-bytes"></a>
<a id="replicas-replica-count"></a>
<a id="restartcount-total-replica-restart-count"></a>
<a id="requests-requests"></a>
<a id="coresquotaused-reserved-cores-per-revision"></a>
<a id="totalcoresquotaused-total-reserved-cores-per-container-app"></a>
<a id="resiliencyconnecttimeouts-resiliency-connection-timeouts"></a>
<a id="resiliencyejectedhosts-resiliency-ejected-hosts"></a>
<a id="resiliencyejectionsaborted-resiliency-ejections-aborted"></a>
<a id="resiliencyrequestretries-resiliency-request-retries"></a>
<a id="resiliencyrequesttimeouts-resiliency-request-timeouts"></a>
<a id="resiliencyrequestspendingconnectionpool-resiliency-requests-pending-connection-pool"></a>
<a id="responsetime-average-response-time-preview"></a>
<a id="cpupercentage-cpu-usage-percentage-preview"></a>
<a id="memorypercentage-memory-percentage-preview"></a>
<a id="gpuutilizationpercentage-gpu-utilization-percentage-preview"></a>
**All container app metrics** → [Container App Metrics](metrics/container-app-metrics.md)

<a id="nodecount-workload-profile-node-count-preview"></a>
<a id="ingressusagenanocores-ingress-cpu-usage-preview"></a>
<a id="ingressusagebytes-ingress-memory-usage-bytes-preview"></a>
<a id="ingresscpupercentage-ingress-cpu-usage-percentage-preview"></a>
<a id="ingressmemorypercentage-ingress-memory-usage-percentage-preview"></a>
<a id="envcoresquotalimit-and-envcoresquotautilization-deprecated-cores-quota-metrics"></a>
**All environment metrics** → [Environment Metrics](metrics/managed-environment-metrics.md)

<a id="keda-scaler-observability"></a>
**KEDA scaler observability** → [KEDA Observability](metrics/keda-observability.md)

<a id="how-these-numbers-were-produced"></a>
<a id="query-metrics-with-az-cli"></a>
**Evidence and CLI queries** → [Evidence and Captures](metrics/evidence-and-captures.md)

## See Also

- [Metrics Overview](metrics/index.md)
- [CLI Reference](cli-reference.md)
- [Platform Limits](platform-limits.md)

## Sources

- [Supported metrics for Microsoft.App/containerapps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/metrics)
- [Azure Monitor metrics overview (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/essentials/data-platform-metrics)
