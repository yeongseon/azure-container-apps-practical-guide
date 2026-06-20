# Lab: Memory Leak OOMKilled

Reproduce the canonical Container Apps memory failure pattern: a container exceeds its cgroup memory ceiling, gets SIGKILL'd by the kernel OOM killer, surfaces as exit code 137 + ContainerTerminated/ProcessExited in `ContainerAppSystemLogs_CL`, and falls into CrashLoopBackOff.

## Root Cause

When a container's resident set (RSS) crosses the cgroup memory ceiling configured by `--memory` (for example `0.5Gi`), the Linux kernel OOM killer sends SIGKILL to the container's main PID. Azure Container Apps surfaces this as:

- Exit code **137** (128 + signal 9 = SIGKILL)
- `Reason: ContainerTerminated`, sub-reason `ProcessExited`
- `HealthState: Unhealthy`, `ProvisioningState: Failed`
- Restart loop driven by the platform's CrashLoopBackOff behavior

The exit code does NOT include an explicit "OOM" string in platform logs. Operators must correlate exit 137 with the `MemoryPercentage` / `WorkingSetBytes` metric curve to confirm OOM as the root cause vs other SIGKILL sources (admin kill, deployment, manual restart).

## Scenarios

| Scenario | App name | Mode | Memory | Expected behavior |
|---|---|---|---|---|
| **A. Hard OOM** | `ca-oom-hard` | `hard-oom` (allocate 600 MiB at startup) | 0.5Gi | Immediate OOMKill before HTTP server starts. CrashLoopBackOff. ProvisioningState=Failed. |
| **B. Gradual leak** | `ca-oom-leak` | `leak` (+30 MiB / 20s in background thread) | 0.5Gi | Healthy for ~5-7 minutes, then OOMKill. Restart re-runs the leak. |
| **C. Healthy control** | `ca-oom-healthy` | `healthy` (no allocations) | 1.0Gi | Stable. RSS ~30-50 MiB. RestartCount=0. HealthState=Healthy. |
| **Fix** | `ca-oom-hard` (updated) | `healthy` + memory 1.0Gi | 1.0Gi | New revision recovers. Old failing revision retained for evidence. |

Comparing A and B against C proves the OOMs are caused by the workload's memory growth, not by the image, network, registry, or platform.

## Workload

```text
labs/memory-leak-oomkilled/
├── infra/main.bicep            # RG-scoped: ACR + Log Analytics + ACA env
├── workload/
│   ├── app.py                  # MODE=healthy | hard-oom | leak
│   └── Dockerfile
├── trigger-scenario-a.sh       # Hard OOM at startup
├── trigger-scenario-b.sh       # Gradual leak (background thread)
├── trigger-scenario-c.sh       # Healthy control
├── trigger-fix.sh              # Apply fix to Scenario A
├── verify.sh                   # Collect evidence (logs, metrics, cgroup)
└── cleanup.sh
```

## Quick Start

```bash
export RG="rg-aca-memleak-lab"
export LOCATION="koreacentral"
export BASE_NAME="memleak"

# 1. Create resource group and infrastructure
az group create --name "$RG" --location "$LOCATION"

az deployment group create \
  --resource-group "$RG" --name main \
  --template-file labs/memory-leak-oomkilled/infra/main.bicep \
  --parameters baseName="$BASE_NAME"

export ACR_NAME="$(az deployment group show --resource-group "$RG" --name main \
  --query properties.outputs.containerRegistryName.value --output tsv)"
export ENV_NAME="$(az deployment group show --resource-group "$RG" --name main \
  --query properties.outputs.environmentName.value --output tsv)"

# 2. Deploy all three scenarios
bash labs/memory-leak-oomkilled/trigger-scenario-a.sh
bash labs/memory-leak-oomkilled/trigger-scenario-b.sh
bash labs/memory-leak-oomkilled/trigger-scenario-c.sh

# 3. Wait for logs to be ingested (5-10 min for Log Analytics) and for
#    scenario B's leak to reach the cgroup ceiling (~5-7 min).
echo "Waiting 10 minutes for log ingestion and leak progression..."
sleep 600

# 4. Verify each scenario
APP_NAME=ca-oom-hard    bash labs/memory-leak-oomkilled/verify.sh
APP_NAME=ca-oom-leak    bash labs/memory-leak-oomkilled/verify.sh
APP_NAME=ca-oom-healthy bash labs/memory-leak-oomkilled/verify.sh

# 5. Apply fix to Scenario A and verify recovery
bash labs/memory-leak-oomkilled/trigger-fix.sh
sleep 90
APP_NAME=ca-oom-hard bash labs/memory-leak-oomkilled/verify.sh

# 6. Cleanup
bash labs/memory-leak-oomkilled/cleanup.sh
```

## What "Success" Looks Like

The lab is considered reproduced when **all** of the following hold:

1. **Scenario A (hard-oom)**: `ContainerAppSystemLogs_CL` contains `exit code '137'` + `ProcessExited` entries within the first 60 seconds after deployment. `RestartCount` climbs. The Revisions blade shows `HealthState: Unhealthy` for the failing revision.

2. **Scenario B (leak)**: Console logs show progressive `[leak] tick N: +30 MiB, total retained K MiB` prints. `MemoryPercentage` curve climbs steadily. Around the 12-15th tick, the first OOM appears, followed by CrashLoopBackOff. The pattern is visibly different from Scenario A: there is a healthy runway before the kill.

3. **Scenario C (healthy)**: `WorkingSetBytes` stays at ~30-50 MiB. `RestartCount` remains 0. HealthState reports Healthy. Acts as control proving the platform and image are fine.

4. **Fix**: After `trigger-fix.sh`, a new revision is created. The new revision reaches `HealthState: Healthy`. `MemoryPercentage` drops back to baseline. The old failing revision is preserved (inactive but visible in the Revisions blade) for post-incident review.

## Operator Takeaway

When investigating exit code 137 / OOMKilled symptoms:

1. **Exit 137 alone does not prove OOM.** SIGKILL also comes from admin actions, platform deployment cycles, and manual restarts. Confirm OOM with the `MemoryPercentage` curve — it should reach ~100% just before the exit timestamp.

2. **System logs do not explicitly say "OOMKilled".** Look for `exit code '137'` + `ProcessExited` + `ContainerTerminated`. The kernel does not write an OOM message into the platform log surface — only the kill is visible.

3. **Hard OOM vs gradual leak look different in metrics.**
    - Hard OOM: `MemoryPercentage` spikes to ~100% within seconds, container dies before HTTP traffic.
    - Gradual leak: `MemoryPercentage` climbs over minutes, container serves traffic until the ceiling is hit. Restart history shows a periodic cliff pattern.

4. **Always validate the fix.** Raising memory alone DOES NOT fix a true leak — it only delays the OOM. The Scenario B pattern (re-leak after restart) makes this visible. The fix must change the workload (Scenario A's `MODE=healthy` switch) or include both axes (memory raise + workload fix).

5. **Preserve the failing revision.** `az containerapp update` creates a new revision but does not delete the old one. The Revisions blade retains the failing revision's HealthState and RestartCount for post-incident review. Do not delete it until evidence collection is complete.

## See Also

- Lab guide: [`docs/troubleshooting/lab-guides/memory-leak-oomkilled.md`](../../docs/troubleshooting/lab-guides/memory-leak-oomkilled.md)
- Playbook: [`docs/troubleshooting/playbooks/scaling-and-runtime/memory-leak-oomkilled.md`](../../docs/troubleshooting/playbooks/scaling-and-runtime/memory-leak-oomkilled.md)
- Related playbook: [`docs/troubleshooting/playbooks/scaling-and-runtime/crashloop-oom-and-resource-pressure.md`](../../docs/troubleshooting/playbooks/scaling-and-runtime/crashloop-oom-and-resource-pressure.md)
- MSLearn: [Troubleshoot container start failures](https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-container-start-failures)
- MSLearn: [Metrics in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/metrics)
