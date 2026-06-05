# Lab: KEDA "No Metrics Returned from Resource Metrics API"

Reproduce the KEDA/HPA log messages commonly seen in Azure Container Apps
when the Kubernetes Metrics Server cannot collect CPU or memory data from
a container:

```
failed to get memory usage: unable to get metrics for resource memory: no metrics returned from resource metrics API
invalid metrics (1 invalid out of 5), first error is: failed to get <app> container metric value: failed to get cpu usage: unable to get metrics for resource cpu: no metrics returned from resource metrics API
scaler memory info: The 'type' setting is DEPRECATED and will be removed in v2.18 - Use 'metricType' instead.
```

## Root Cause

These logs originate from the KEDA operator (which manages the underlying
Kubernetes HPA) when it queries the Kubernetes Resource Metrics API and
receives no data for one or more containers. This happens when:

1. **Pod is Not Ready** — during startup, before the readiness probe
   succeeds, the Metrics Server has no data to return.
2. **Container restart** — after a crash or OOMKill, the restarting
   container briefly has no metrics.
3. **Revision deployment** — new replicas created during a revision
   change go through the same Not Ready window.
4. **Platform maintenance** — node updates may reschedule pods, creating
   brief metrics gaps.

The `invalid metrics` message appears when **some** (but not all) metrics
in a multi-scaler setup fail to collect. The `DEPRECATED` warning is
unrelated — it occurs because the scale rule uses the legacy
`metadata.type` field instead of the trigger-level `metricType` field
(removed in KEDA v2.18).

## Scenarios

| Scenario | App name | Mode | Expected behavior |
|---|---|---|---|
| **A. Slow startup** | `ca-nometrics-slow` | `slow-start` (120s delay) | "no metrics returned" during first ~2 min, then resolves |
| **B. CrashLoopBackOff** | `ca-nometrics-crash` | `crash-loop` (exits every 30s) | Recurring "no metrics returned" + "invalid metrics" on every crash cycle |
| **C. Healthy baseline** | `ca-nometrics-healthy` | `healthy` | No metric error logs (control) |

Comparing A/B against C isolates that the metric errors are caused by
container lifecycle events (Not Ready / restart), not by a platform or
scaler defect.

## Workload

```text
labs/keda-no-metrics-returned/
├── infra/main.bicep            # RG-scoped: ACR + Log Analytics + ACA env
├── workload/
│   ├── app.py                  # MODE=healthy | slow-start | crash-loop | oom
│   └── Dockerfile
├── trigger-scenario-a.sh       # Slow startup (readiness probe fails)
├── trigger-scenario-b.sh       # CrashLoopBackOff (repeated exits)
├── trigger-scenario-c.sh       # Healthy baseline (control)
├── verify.sh                   # Query system logs for metric errors
└── cleanup.sh
```

## Quick Start

```bash
export RG="rg-aca-no-metrics-lab"
export LOCATION="koreacentral"
export BASE_NAME="nometrics"

# 1. Create resource group and infrastructure
az group create --name "$RG" --location "$LOCATION"

az deployment group create \
  --resource-group "$RG" --name main \
  --template-file labs/keda-no-metrics-returned/infra/main.bicep \
  --parameters baseName="$BASE_NAME"

export ACR_NAME="$(az deployment group show --resource-group "$RG" --name main \
  --query properties.outputs.containerRegistryName.value --output tsv)"
export ENV_NAME="$(az deployment group show --resource-group "$RG" --name main \
  --query properties.outputs.environmentName.value --output tsv)"

# 2. Deploy all three scenarios
bash labs/keda-no-metrics-returned/trigger-scenario-a.sh
bash labs/keda-no-metrics-returned/trigger-scenario-b.sh
bash labs/keda-no-metrics-returned/trigger-scenario-c.sh

# 3. Wait for logs to be ingested (5-10 min for Log Analytics)
echo "Waiting 10 minutes for log ingestion..."
sleep 600

# 4. Verify each scenario
APP_NAME=ca-nometrics-slow    bash labs/keda-no-metrics-returned/verify.sh
APP_NAME=ca-nometrics-crash   bash labs/keda-no-metrics-returned/verify.sh
APP_NAME=ca-nometrics-healthy bash labs/keda-no-metrics-returned/verify.sh

# 5. Cleanup
bash labs/keda-no-metrics-returned/cleanup.sh
```

## What "Success" Looks Like

The lab is considered reproduced when:

1. **Scenario A (slow-start)**: `ContainerAppSystemLogs_CL` contains
   "no metrics returned" entries during the first ~2 minutes after
   deployment, then the errors stop once the container becomes Ready.

2. **Scenario B (crash-loop)**: `ContainerAppSystemLogs_CL` contains
   recurring "no metrics returned" and "invalid metrics" entries that
   correlate with container restart timestamps. The pattern repeats
   with increasing intervals (CrashLoopBackOff).

3. **Scenario C (healthy)**: `ContainerAppSystemLogs_CL` contains **no**
   "no metrics returned" or "invalid metrics" entries for this app.
   The `DEPRECATED` warning may still appear (it is independent of
   container health).

4. **All scenarios**: The `DEPRECATED` / `metricType` warning appears
   in system logs for all three apps, confirming it is a configuration
   warning, not a runtime error.

## Operator Takeaway

When a customer reports these log messages:

1. **Check if the logs are transient or persistent.** Transient
   occurrences during deployments, restarts, or scale events are
   expected and do not affect service health.

2. **If persistent**, investigate container health:
   - Is the container crash-looping? (`RestartCount` metric)
   - Are readiness/startup probes too aggressive?
   - Is the container OOMKilled repeatedly?

3. **The "DEPRECATED" warning** can be addressed by migrating the scale
   rule from `metadata.type=Utilization` to the trigger-level
   `metricType` field, if the Azure Container Apps API version supports
   it. This is cosmetic and does not affect scaling behavior.

4. **To reduce frequency** of these logs:
   - Set `minReplicas >= 1` to avoid cold-start metrics gaps
   - Tune startup/readiness probes to match actual container startup time
   - Fix application crashes that cause CrashLoopBackOff
   - These logs cannot be suppressed — they are internal KEDA/HPA logs

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/memory-percentage-vs-keda-utilization.md`
- Playbook: `docs/troubleshooting/playbooks/scaling-and-runtime/memory-percentage-vs-keda-utilization.md`
- Platform docs: `docs/platform/scaling/cpu-memory-scaler.md`
