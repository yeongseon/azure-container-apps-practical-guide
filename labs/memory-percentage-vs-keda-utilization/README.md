# Lab: Memory Percentage vs KEDA Utilization

Reproduce the failure mode where a Container Apps revision sustains a high
`MemoryPercentage` value on the Azure Portal but the KEDA memory scale rule
(`Utilization=50`) does **not** trigger scale-out.

The lab tests two independent contributors to this symptom, in three
side-by-side scenarios:

1. **HPA ceiling math** — KEDA uses the standard HPA formula
   `desiredReplicas = ceil(currentReplicas × currentMetricValue / desiredMetricValue)`.
   With `currentReplicas = 2` and `desiredMetricValue = 50`, any
   `currentMetricValue` at or below `50` keeps the result at `2`. The
   formula only rounds up to `3` once the per-replica value strictly
   exceeds `50`. The customer-visible symptom "Portal shows 70%, replicas
   stay at 2" can be a pure rounding artifact when per-replica memory
   stays at or below the target.
2. **Metric source mismatch** — The Portal `MemoryPercentage (Preview)`
   metric is sourced from Azure Monitor and, based on the cgroup data this
   lab observed, reflects the container working set including reclaimable
   page cache. KEDA's memory scaler is sourced from the Kubernetes metrics
   API (kubelet/metrics-server), which does **not** always report the same
   numerator as the Azure Monitor metric. The two values can diverge by
   tens of percentage points for cache-heavy workloads — this lab
   demonstrates the divergence behaviorally rather than measuring the
   exact metrics-server numerator.

| Scenario | App name | Workload | TARGET_MB | Per-replica Portal util | HPA on Portal value | Observed replicas |
|---|---|---|---|---|---|---|
| **A. Just-below** | `ca-mempct-a-below` | `MODE=rss` | 400 (~40% of 1024) | ~40% | `ceil(2 × 40/50) = 2` | **2 (held)** |
| **B. Just-above** | `ca-mempct-b-above` | `MODE=rss` | 560 (~56% of 1024) | ~56% | `ceil(2 × 56/50) = 3`, then walks up | **2 → 20 (maxReplicas)** |
| **C. Cache inflation** | `ca-mempct-cache` | `MODE=cache` | 700 (~68% of 1024) | ~72% (cache-heavy) | `ceil(2 × 72/50) = 3` predicts further scale-out | **3 (held; far below Portal-predicted)** |

The behavioral diff between A and B isolates the **HPA ceiling effect** with
the metric source held constant (both rss). The diff between C and B
isolates the **metric-source effect** with the working-set value held
roughly constant.

## Workload

```text
labs/memory-percentage-vs-keda-utilization/
├── infra/main.bicep            # RG-scoped: ACR + Log Analytics + ACA env
├── workload/
│   ├── app.py                  # MODE=cache | rss exerciser
│   └── Dockerfile
├── trigger-scenario-a.sh       # Just-below threshold (rss, TARGET_MB=400)
├── trigger-scenario-b.sh       # Just-above threshold (rss, TARGET_MB=560)
├── trigger-scenario-c.sh       # Cache inflation        (cache, TARGET_MB=700)
├── verify.sh                   # Per-app metrics + cgroup memory.stat
└── cleanup.sh
```

## Quick start

```bash
export RG="rg-aca-mem-pct-lab"
export LOCATION="koreacentral"
export BASE_NAME="mempct"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
  --resource-group "$RG" --name main \
  --template-file labs/memory-percentage-vs-keda-utilization/infra/main.bicep \
  --parameters baseName="$BASE_NAME"

export ACR_NAME="$(az deployment group show --resource-group "$RG" --name main \
  --query properties.outputs.containerRegistryName.value --output tsv)"
export ENV_NAME="$(az deployment group show --resource-group "$RG" --name main \
  --query properties.outputs.environmentName.value --output tsv)"

# Create all three scenarios in parallel; they observe the same 15-min window.
bash labs/memory-percentage-vs-keda-utilization/trigger-scenario-a.sh
bash labs/memory-percentage-vs-keda-utilization/trigger-scenario-b.sh
bash labs/memory-percentage-vs-keda-utilization/trigger-scenario-c.sh

# Wait ~15-20 minutes for cgroup to stabilize and KEDA to evaluate.
sleep 1200

# Verify each scenario.
APP_NAME=ca-mempct-a-below bash labs/memory-percentage-vs-keda-utilization/verify.sh
APP_NAME=ca-mempct-b-above bash labs/memory-percentage-vs-keda-utilization/verify.sh
APP_NAME=ca-mempct-cache   bash labs/memory-percentage-vs-keda-utilization/verify.sh

# Done
bash labs/memory-percentage-vs-keda-utilization/cleanup.sh
```

## What "success" looks like

The lab is considered reproduced when **all** of the following hold over a
window of at least 10 consecutive minutes:

1. **Scenario A**: `MemoryPercentage (Avg)` is in the 35-50% range AND
   `Replicas (Max)` stays at `2` for the observation window.
2. **Scenario B**: `MemoryPercentage (Avg)` is in the 50-60% range AND
   `Replicas (Max)` walks up toward `maxReplicas` because every new
   replica also reports ~56% per-replica utilization, so the HPA formula
   keeps recomputing `ceil(N × 56/50) = N+1`.
3. **Scenario C**: `MemoryPercentage (Avg)` is in the 70-80% range BUT
   `Replicas (Max)` plateaus far below what `ceil(N × 0.72 / 0.5)` would
   predict (we observed 3, not 5+), AND `memory.stat` from the replica
   shows `cache >> rss` (or `file >> anon` on cgroup v2). This proves the
   Portal value is **not** the same input KEDA evaluated; it does **not**
   directly measure the metrics-server value KEDA actually used.

(1) and (2) together prove the HPA ceiling effect (same metric source,
different headroom). (3) demonstrates behavioral divergence between the
Portal metric and the scaler input for cache-heavy workloads.

## Why this matters (operator takeaway)

When a customer asks "why didn't my memory rule trigger?" with a chart
showing 60-70%, the correct diagnostic sequence is:

1. Open the Azure Portal metric chart and **apply splitting by replica**.
   This shows whether all replicas are near the same utilization or one is
   pulling the average up.
2. Compute the HPA ceiling: `ceil(currentReplicas × currentMetric / target)`.
   If the result equals `currentReplicas`, KEDA is working as designed.
3. If per-replica memory diverges sharply from the Portal value, suspect
   page cache / working-set semantics, not a broken scaler.

## See also

- Lab guide: `docs/troubleshooting/lab-guides/memory-percentage-vs-keda-utilization.md`
- Playbook: `docs/troubleshooting/playbooks/scaling-and-runtime/memory-percentage-vs-keda-utilization.md`
