# Metrics load test evidence baseline

This directory contains the committed **Option C special-case evidence baseline** for `labs/metrics-load-test/`. It is **not** a Phase B falsification pack and it intentionally ships **no gate JSONs** and **no `verify.sh`** because the lab itself is not a falsifiable troubleshooting lab.

Per [`../README.md`](../README.md) line 8, this lab is the data source for the metrics reference, not a trigger/fix/falsification loop. The evidence here establishes a reproducible baseline for the 45 Portal screenshot states already referenced under `docs/reference/metrics/`.

## Baseline status

- **Framework**: Option C special-case evidence baseline
- **Phase B framing**: **27/28 falsification labs + 1 metrics evidence baseline = 28 total**
- **Capture timestamp (UTC)**: `2026-06-29T00:25:19Z`
- **Metric window (UTC)**: `2026-06-28T22:25:19Z` → `2026-06-29T00:25:19Z`
- **Granularity**: `PT1M` (1-minute buckets)
- **Region**: `koreacentral`
- **Resource group**: `rg-aca-basics-d38538`
- **Topology**: 8 Container Apps across 2 Container Apps environments, 1 ACR Basic registry, 1 Log Analytics workspace
- **Portal screenshots in this pack**: none added in this refresh

## Files in this directory

- `capture-manifest.json` — sanitized capture metadata, resource IDs, and the exact query mapping for all 45 exports.
- `raw/metric-01-...json` through `raw/metric-45-...json` — sanitized raw `az monitor metrics list` JSON outputs, one file per metrics-reference screenshot state.

## Capture inventory

| # | Screenshot state | Metric | Resource | Aggregation | Filter | Raw file |
|---|---|---|---|---|---|---|
| 1 | `metrics-usage-nano-cores-baseline` | `UsageNanoCores` | `ca-loadtest-d38538` | `Average` | none | `raw/metric-01-metrics-usage-nano-cores-baseline.json` |
| 2 | `metrics-usage-nano-cores-split-replica` | `UsageNanoCores` | `ca-loadtest-d38538` | `Average` | `podName eq '*'` | `raw/metric-02-metrics-usage-nano-cores-split-replica.json` |
| 3 | `metrics-working-set-bytes-baseline` | `WorkingSetBytes` | `ca-loadtest-d38538` | `Average` | none | `raw/metric-03-metrics-working-set-bytes-baseline.json` |
| 4 | `metrics-working-set-bytes-split-replica` | `WorkingSetBytes` | `ca-loadtest-d38538` | `Average` | `podName eq '*'` | `raw/metric-04-metrics-working-set-bytes-split-replica.json` |
| 5 | `metrics-rx-bytes-baseline` | `RxBytes` | `ca-loadtest-d38538` | `Total` | none | `raw/metric-05-metrics-rx-bytes-baseline.json` |
| 6 | `metrics-rx-bytes-split-replica` | `RxBytes` | `ca-loadtest-d38538` | `Total` | `podName eq '*'` | `raw/metric-06-metrics-rx-bytes-split-replica.json` |
| 7 | `metrics-tx-bytes-baseline` | `TxBytes` | `ca-loadtest-d38538` | `Total` | none | `raw/metric-07-metrics-tx-bytes-baseline.json` |
| 8 | `metrics-tx-bytes-split-replica` | `TxBytes` | `ca-loadtest-d38538` | `Total` | `podName eq '*'` | `raw/metric-08-metrics-tx-bytes-split-replica.json` |
| 9 | `metrics-replicas-baseline` | `Replicas` | `ca-loadtest-d38538` | `Maximum` | none | `raw/metric-09-metrics-replicas-baseline.json` |
| 10 | `metrics-replicas-split-revision` | `Replicas` | `ca-loadtest-d38538` | `Maximum` | `revisionName eq '*'` | `raw/metric-10-metrics-replicas-split-revision.json` |
| 11 | `metrics-restart-count-baseline` | `RestartCount` | `ca-crashloop-d38538` | `Maximum` | none | `raw/metric-11-metrics-restart-count-baseline.json` |
| 12 | `metrics-restart-count-split-replica` | `RestartCount` | `ca-crashloop-d38538` | `Maximum` | `podName eq '*'` | `raw/metric-12-metrics-restart-count-split-replica.json` |
| 13 | `metrics-restart-count-split-revision` | `RestartCount` | `ca-crashloop-d38538` | `Maximum` | `revisionName eq '*'` | `raw/metric-13-metrics-restart-count-split-revision.json` |
| 14 | `metrics-requests-baseline` | `Requests` | `ca-loadtest-d38538` | `Total` | none | `raw/metric-14-metrics-requests-baseline.json` |
| 15 | `metrics-requests-split-replica` | `Requests` | `ca-loadtest-d38538` | `Total` | `podName eq '*'` | `raw/metric-15-metrics-requests-split-replica.json` |
| 16 | `metrics-requests-split-status-category` | `Requests` | `ca-loadtest-d38538` | `Total` | `statusCodeCategory eq '*'` | `raw/metric-16-metrics-requests-split-status-category.json` |
| 17 | `metrics-requests-split-status-code` | `Requests` | `ca-loadtest-d38538` | `Total` | `statusCode eq '*'` | `raw/metric-17-metrics-requests-split-status-code.json` |
| 18 | `metrics-response-time-baseline` | `ResponseTime` | `ca-loadtest-d38538` | `Average` | none | `raw/metric-18-metrics-response-time-baseline.json` |
| 19 | `metrics-response-time-split-status-category` | `ResponseTime` | `ca-loadtest-d38538` | `Average` | `statusCodeCategory eq '*'` | `raw/metric-19-metrics-response-time-split-status-category.json` |
| 20 | `metrics-cpu-percentage-baseline` | `CpuPercentage` | `ca-loadtest-d38538` | `Average` | none | `raw/metric-20-metrics-cpu-percentage-baseline.json` |
| 21 | `metrics-cpu-percentage-split-replica` | `CpuPercentage` | `ca-loadtest-d38538` | `Average` | `podName eq '*'` | `raw/metric-21-metrics-cpu-percentage-split-replica.json` |
| 22 | `metrics-memory-percentage-baseline` | `MemoryPercentage` | `ca-loadtest-d38538` | `Average` | none | `raw/metric-22-metrics-memory-percentage-baseline.json` |
| 23 | `metrics-memory-percentage-split-replica` | `MemoryPercentage` | `ca-loadtest-d38538` | `Average` | `podName eq '*'` | `raw/metric-23-metrics-memory-percentage-split-replica.json` |
| 24 | `metrics-cores-quota-used-baseline` | `CoresQuotaUsed` | `ca-loadtest-d38538` | `Maximum` | none | `raw/metric-24-metrics-cores-quota-used-baseline.json` |
| 25 | `metrics-cores-quota-used-split-revision` | `CoresQuotaUsed` | `ca-loadtest-d38538` | `Maximum` | `revisionName eq '*'` | `raw/metric-25-metrics-cores-quota-used-split-revision.json` |
| 26 | `metrics-resiliency-connect-timeouts-baseline` | `ResiliencyConnectTimeouts` | `ca-res-blackhole` | `Total` | none | `raw/metric-26-metrics-resiliency-connect-timeouts-baseline.json` |
| 27 | `metrics-resiliency-ejected-hosts-baseline` | `ResiliencyEjectedHosts` | `ca-res-503` | `Total` | none | `raw/metric-27-metrics-resiliency-ejected-hosts-baseline.json` |
| 28 | `metrics-resiliency-ejected-hosts-split-revision` | `ResiliencyEjectedHosts` | `ca-res-503` | `Total` | `revisionName eq '*'` | `raw/metric-28-metrics-resiliency-ejected-hosts-split-revision.json` |
| 29 | `metrics-resiliency-ejections-aborted-baseline` | `ResiliencyEjectionsAborted` | `ca-res-503` | `Total` | none | `raw/metric-29-metrics-resiliency-ejections-aborted-baseline.json` |
| 30 | `metrics-resiliency-ejections-aborted-split-revision` | `ResiliencyEjectionsAborted` | `ca-res-503` | `Total` | `revisionName eq '*'` | `raw/metric-30-metrics-resiliency-ejections-aborted-split-revision.json` |
| 31 | `metrics-resiliency-ejections-aborted-blackhole-baseline` | `ResiliencyEjectionsAborted` | `ca-res-blackhole` | `Total` | none | `raw/metric-31-metrics-resiliency-ejections-aborted-blackhole-baseline.json` |
| 32 | `metrics-resiliency-request-retries-baseline` | `ResiliencyRequestRetries` | `ca-res-503` | `Total` | none | `raw/metric-32-metrics-resiliency-request-retries-baseline.json` |
| 33 | `metrics-resiliency-request-retries-split-revision` | `ResiliencyRequestRetries` | `ca-res-503` | `Total` | `revisionName eq '*'` | `raw/metric-33-metrics-resiliency-request-retries-split-revision.json` |
| 34 | `metrics-resiliency-request-timeouts-baseline` | `ResiliencyRequestTimeouts` | `ca-res-slow` | `Total` | none | `raw/metric-34-metrics-resiliency-request-timeouts-baseline.json` |
| 35 | `metrics-resiliency-request-timeouts-split-revision` | `ResiliencyRequestTimeouts` | `ca-res-slow` | `Total` | `revisionName eq '*'` | `raw/metric-35-metrics-resiliency-request-timeouts-split-revision.json` |
| 36 | `metrics-resiliency-pending-pool-baseline` | `ResiliencyRequestsPendingConnectionPool` | `ca-res-pool` | `Total` | none | `raw/metric-36-metrics-resiliency-pending-pool-baseline.json` |
| 37 | `metrics-resiliency-pending-pool-split-revision` | `ResiliencyRequestsPendingConnectionPool` | `ca-res-pool` | `Total` | `revisionName eq '*'` | `raw/metric-37-metrics-resiliency-pending-pool-split-revision.json` |
| 38 | `metrics-nodecount-baseline` | `NodeCount` | `cae-wp-d38538` | `Maximum` | none | `raw/metric-38-metrics-nodecount-baseline.json` |
| 39 | `metrics-nodecount-split-profile` | `NodeCount` | `cae-wp-d38538` | `Maximum` | `workloadProfileName eq '*'` | `raw/metric-39-metrics-nodecount-split-profile.json` |
| 40 | `metrics-ingress-cpu-usage-baseline` | `IngressUsageNanoCores` | `cae-wp-d38538` | `Average` | none | `raw/metric-40-metrics-ingress-cpu-usage-baseline.json` |
| 41 | `metrics-ingress-memory-bytes-baseline` | `IngressUsageBytes` | `cae-wp-d38538` | `Average` | none | `raw/metric-41-metrics-ingress-memory-bytes-baseline.json` |
| 42 | `metrics-ingress-cpu-percentage-baseline` | `IngressCpuPercentage` | `cae-wp-d38538` | `Average` | none | `raw/metric-42-metrics-ingress-cpu-percentage-baseline.json` |
| 43 | `metrics-ingress-memory-percentage-baseline` | `IngressMemoryPercentage` | `cae-wp-d38538` | `Average` | none | `raw/metric-43-metrics-ingress-memory-percentage-baseline.json` |
| 44 | `metrics-cores-quota-limit-deprecated` | `EnvCoresQuotaLimit` | `cae-wp-d38538` | `Average` | none | `raw/metric-44-metrics-cores-quota-limit-deprecated.json` |
| 45 | `metrics-percentage-cores-used-deprecated` | `EnvCoresQuotaUtilization` | `cae-wp-d38538` | `Average` | none | `raw/metric-45-metrics-percentage-cores-used-deprecated.json` |

## Interpretation notes

- The two deprecated env-quota metrics are captured as **expected empty-state evidence** (`timeseries: []`), matching the current product behavior documented in the metrics reference.
- `ResiliencyConnectTimeouts` is expected baseline-zero in this topology because the blackhole target completes the TCP handshake before the HTTP hang.
- `ResiliencyEjectionsAborted` is captured for both the 503-policy target and the blackhole target because the metrics reference carries both screenshot states.
- No GPU signal is captured here because the metrics reference does not ship a live GPU screenshot for this lab topology.

## How to refresh

```bash
cd labs/metrics-load-test
bash rebuild.sh
# Run the load profile without modifying the committed script in-place:
# use the printed FQDN from rebuild.sh and either patch a temporary copy of run-load.sh
# or run the equivalent hey commands against that FQDN.
bash run-load.sh
# Wait 30-60 minutes for Azure Monitor backfill, then capture PT1M metric exports.
az group delete --resource-group rg-aca-basics-d38538 --yes --no-wait
```

Refresh rules:

1. Re-run `rebuild.sh` without modifying the committed lab assets.
2. Drive the full 30-minute load profile.
3. Wait at least 30 minutes after load completion so 1-minute buckets are queryable.
4. Re-export all 45 screenshot states with `az monitor metrics list`.
5. Sanitize all exported files with the canonical regex set used in `labs/dapr-integration/fix-and-capture.sh`.
6. Delete the resource group immediately after the capture completes.

## Scope boundary

This baseline is intentionally narrow:

- It proves that the lab can reproduce the 45 metrics-reference screenshot states with sanitized raw Azure Monitor exports.
- It does **not** claim H1/H2/H3 semantics, falsification gates, recovery causality, or a replayable offline `verify.sh` contract.
- It does **not** replace the metrics reference itself; it supports it.

## See also

- [Metrics load test lab overview](../README.md)
- [Metrics reference evidence page](../../../docs/reference/metrics/evidence-and-captures.md)
- [Metrics reference index](../../../docs/reference/metrics/index.md)
