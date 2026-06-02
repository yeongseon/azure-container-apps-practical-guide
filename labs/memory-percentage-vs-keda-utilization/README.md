# Lab: Memory Percentage vs KEDA Utilization

Reproduce the failure mode where a Container Apps revision sustains a high
`MemoryPercentage` value on the Azure Portal but the KEDA memory scale rule
(`Utilization=50`) does **not** trigger scale-out.

The lab tests two independent contributors to this symptom, in three
side-by-side scenarios:

1. **HPA ceiling math** — KEDA uses the standard HPA formula
   `desiredReplicas = ceil(currentReplicas × currentMetricValue / desiredMetricValue)`.
   With `currentReplicas = 2` and `desiredMetricValue = 50`, any
   `currentMetricValue` strictly less than `25` keeps the result at `2`. Any
   value at or above ~`26` rounds up to `3`. The customer-visible symptom
   "Portal shows 70%, replicas stay at 2" can be a pure rounding artifact.
2. **Metric source mismatch** — The Portal `MemoryPercentage (Preview)`
   metric is sourced from Azure Monitor (working-set / limit, includes page
   cache). KEDA's memory scaler is sourced from the Kubernetes metrics API
   (effectively `container_memory_working_set_bytes` minus inactive cache,
   divided by the resource request). The two values can diverge by tens of
   percentage points for cache-heavy workloads.

| Scenario | App name | Workload | TARGET_MB | Expected per-replica util | HPA calc | Expected replicas |
|---|---|---|---|---|---|---|
| **A. Just-below** | `ca-mempct-a-below` | `MODE=rss` | 400 (~40% of 1024) | ~40% | `ceil(2 × 40/50) = 2` | **2 (no scale-out)** |
| **B. Just-above** | `ca-mempct-b-above` | `MODE=rss` | 560 (~55% of 1024) | ~55% | `ceil(2 × 55/50) = 3` | **3 (scale-out)** |
| **C. Cache inflation** | `ca-mempct-cache` | `MODE=cache` | 700 (~68% of 1024) | low (cache, see notes) | `ceil(2 × ~10/50) = 2` | **2 (no scale-out)** |

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

export ACR_NAME="$(az deployment group show -g "$RG" -n main \
  --query properties.outputs.containerRegistryName.value -o tsv)"
export ENV_NAME="$(az deployment group show -g "$RG" -n main \
  --query properties.outputs.environmentName.value -o tsv)"

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
   `Replicas (Max)` stays at `2`. cgroup `memory.current / memory.max` is
   roughly 35-45%.
2. **Scenario B**: `MemoryPercentage (Avg)` is in the 50-70% range AND
   `Replicas (Max)` rises to `3` (or higher).
3. **Scenario C**: `MemoryPercentage (Avg)` is in the 60-80% range BUT
   `Replicas (Max)` stays at `2`, AND `memory.stat` from the replica shows
   `file >> anon` (page cache dominates).

(1) and (2) together prove the HPA ceiling effect (same metric source,
different headroom). (3) demonstrates the metric-source divergence (Portal
high, KEDA low).

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
