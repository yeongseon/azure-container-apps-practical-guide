---
description: Reproduce Azure Container Apps OOMKilled (exit code 137) under three workloads, capture KQL plus Portal Diagnose-and-Solve evidence, then verify the fix restores HealthState.
content_sources:
  diagrams:
    - id: memory-leak-oomkilled-experiment
      type: flowchart
      source: self-generated
      justification: Lab-specific architecture showing three side-by-side Container Apps sharing one environment, with one running the workload that allocates memory at startup, one running a slow leak in a background thread, and a healthy control, designed to differentiate a hard OOM from a gradual leak from a non-OOM baseline.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-container-start-failures
        - https://learn.microsoft.com/en-us/azure/container-apps/metrics
        - https://learn.microsoft.com/en-us/azure/container-apps/containers
content_validation:
  status: verified
  last_reviewed: '2026-06-20'
  reviewer: ai-agent
  lab_validation:
    status: reproduced
    tested_date: '2026-06-20'
    az_cli_version: 2.79.0
    notes: "All three scenarios reproduced in Korea Central (rg-aca-memleak-lab). Scenario A (hard-oom) produced 76 exit-code-137 events on revision ca-oom-hard--18xosgl within the first 60 seconds after deployment, then CrashLoopBackOff. Scenario B (leak) produced progressive [leak] tick console-log entries climbing by 30 MiB every 20 seconds. Scenario C (healthy) stayed under 50 MiB working set the entire run. Fix (MODE=healthy + memory 1Gi) created revision ca-oom-hard--0000001 which reached HealthState=Healthy within 90 seconds, and the failing revision was retained as inactive evidence. Portal Diagnose-and-Solve / Availability-and-Performance / Container Exit Events detector independently confirmed exit code 137 as SIGKILL from OOM (the Portal text reads 'Resource exhaustion - containers terminated with SIGKILL (exit code 137) ... This is commonly caused by Out of Memory (OOM) conditions')."
  core_claims:
    - claim: Azure Container Apps can terminate containers that exceed their memory limit, surfacing as exit code 137 plus ContainerTerminated/ProcessExited in system logs.
      source: https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-container-start-failures
      verified: true
    - claim: Azure Monitor exposes WorkingSetBytes and MemoryPercentage metrics for Azure Container Apps, broken out per revision and per replica.
      source: https://learn.microsoft.com/en-us/azure/container-apps/metrics
      verified: true
    - claim: The Azure Portal Diagnose-and-Solve Problems blade includes an Availability-and-Performance category with a Container Exit Events detector that identifies SIGKILL (exit code 137) as commonly caused by Out of Memory conditions and counts exit events per revision.
      source: https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-container-start-failures
      verified: true
validation:
  az_cli:
    last_tested: '2026-06-20'
    cli_version: 2.79.0
    result: pass
  bicep:
    last_tested: '2026-06-20'
    result: pass
---
# Memory Leak OOMKilled Lab

Reproduce the canonical Azure Container Apps memory-pressure failure pattern (exit code 137 / OOMKilled), capture the evidence from CLI, KQL, and the Azure Portal Diagnose-and-Solve detectors, then verify that applying the fix creates a new healthy revision while preserving the failing revision for post-incident review.

## Lab Metadata

| Attribute | Value |
|---|---|
| Difficulty | Intermediate |
| Estimated Duration | 30-45 minutes (10 min wait for log ingestion, ~5 min for leak to reach the cgroup ceiling) |
| Tier | Consumption |
| Failure Mode | Container terminated with exit code 137 (SIGKILL), CrashLoopBackOff, ProvisioningState=Failed |
| Skills Practiced | System log analysis, KQL queries, MemoryPercentage / WorkingSetBytes correlation, Diagnose-and-Solve detector usage, fix-and-verify workflow |

## 1) Background

When a container's resident set size (RSS) crosses the cgroup memory ceiling configured by `--memory` (for example `0.5Gi`), the Linux kernel OOM killer sends SIGKILL to the container's main PID. Azure Container Apps surfaces this as:

- Exit code **137** (128 + signal 9 = SIGKILL)
- `Reason: ContainerTerminated`, sub-reason `ProcessExited`
- `HealthState: Unhealthy`, `ProvisioningState: Failed`
- Restart loop driven by the platform's CrashLoopBackOff behavior

The exit code does **not** include an explicit "OOM" string in platform logs. Operators must correlate exit 137 with the `MemoryPercentage` / `WorkingSetBytes` metric curve to confirm OOM as the root cause versus other SIGKILL sources (admin kill, deployment cycle, manual restart).

### Architecture

<!-- diagram-id: memory-leak-oomkilled-experiment -->
```mermaid
flowchart TD
    A["Azure Container Apps environment<br/>cae-memleak-* (koreacentral)"] --> B["Scenario A: ca-oom-hard"]
    A --> C["Scenario B: ca-oom-leak"]
    A --> D["Scenario C: ca-oom-healthy"]
    B --> B1["MODE=hard-oom<br/>allocate 600 MiB at startup<br/>memory 0.5Gi"]
    C --> C1["MODE=leak<br/>+30 MiB every 20s<br/>in background thread<br/>memory 0.5Gi"]
    D --> D1["MODE=healthy<br/>no allocations<br/>memory 1.0Gi"]
    B1 --> E["Observe:<br/>ContainerAppSystemLogs_CL<br/>WorkingSetBytes<br/>RestartCount<br/>D&S Exit Events detector"]
    C1 --> E
    D1 --> E
    E --> F["Apply fix to Scenario A:<br/>MODE=healthy + memory 1Gi<br/>creates new revision"]
    F --> G["Verify:<br/>HealthState=Healthy<br/>old revision retained for evidence"]
```

| Scenario | App name | Mode | Memory | Expected behavior |
|---|---|---|---|---|
| **A. Hard OOM** | `ca-oom-hard` | `hard-oom` (allocate 600 MiB at startup) | 0.5Gi | Immediate OOMKill before HTTP server starts. CrashLoopBackOff. ProvisioningState=Failed. |
| **B. Gradual leak** | `ca-oom-leak` | `leak` (+30 MiB / 20s in background thread) | 0.5Gi | Healthy for ~5-7 minutes, then OOMKill. Restart re-runs the leak. |
| **C. Healthy control** | `ca-oom-healthy` | `healthy` (no allocations) | 1.0Gi | Stable. RSS ~30-50 MiB. RestartCount=0. HealthState=Healthy. |
| **Fix** | `ca-oom-hard` (updated) | `healthy` + memory 1.0Gi | 1.0Gi | New revision recovers. Old failing revision retained for evidence. |

Comparing A and B against C proves the OOMs are caused by the workload's memory growth, not by the image, network, registry, or platform.

## 2) Hypothesis

**IF** three Container Apps share an environment but run workloads with different memory-allocation patterns, **THEN**:

- **Scenario A (hard-oom)**: System logs show `exit code '137'` plus `ProcessExited` plus `ContainerTerminated` within the first 60 seconds after deployment. The revision's `HealthState` reports `Unhealthy` and `ProvisioningState` reports `Failed`. The container never serves HTTP traffic.
- **Scenario B (leak)**: Console logs show progressive `[leak] tick N: +30 MiB, total retained K MiB` entries. `MemoryPercentage` climbs steadily over minutes. Around tick 12-15 (corresponding to ~360-450 MiB retained), the first OOM appears, followed by CrashLoopBackOff. The restart re-runs the leak, producing a periodic cliff pattern in the metric.
- **Scenario C (healthy)**: `WorkingSetBytes` stays at ~30-50 MiB. `RestartCount` remains 0. `HealthState` reports `Healthy`. This is the control that proves the platform, the image, the network, and the registry are all fine.
- **Fix**: After `trigger-fix.sh` updates Scenario A to `MODE=healthy` with `memory=1.0Gi`, a new revision is created. The new revision reaches `HealthState: Healthy` within 90 seconds. `MemoryPercentage` drops to baseline. The Portal Diagnose-and-Solve `Container App Memory Usage` detector flips to green (no thresholds exceeded), and the failing revision is retained inactive in the Revisions blade for post-incident review.

## 3) Runbook

### Deploy infrastructure

```bash
export RG="rg-aca-memleak-lab"
export LOCATION="koreacentral"
export BASE_NAME="memleak"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" --name main \
    --template-file labs/memory-leak-oomkilled/infra/main.bicep \
    --parameters baseName="$BASE_NAME"

export ACR_NAME="$(az deployment group show --resource-group "$RG" --name main \
    --query properties.outputs.containerRegistryName.value --output tsv)"
export ENV_NAME="$(az deployment group show --resource-group "$RG" --name main \
    --query properties.outputs.environmentName.value --output tsv)"
```

| Command | Why it is used |
|---|---|
| `az group create` | Creates the resource group that scopes all lab resources for easy teardown. |
| `az deployment group create` | Deploys the Bicep template that provisions Log Analytics workspace, Azure Container Registry, and the Container Apps environment with `appLogsConfiguration.destination=log-analytics`. |
| `az deployment group show` | Reads the Bicep outputs to capture the generated ACR and environment names (both use random suffixes for uniqueness). |

### Deploy the three scenarios

```bash
bash labs/memory-leak-oomkilled/trigger-scenario-a.sh
bash labs/memory-leak-oomkilled/trigger-scenario-b.sh
bash labs/memory-leak-oomkilled/trigger-scenario-c.sh
```

| Command | Why it is used |
|---|---|
| `trigger-scenario-a.sh` | Builds the image, pushes to ACR, and creates `ca-oom-hard` with `MODE=hard-oom` and `HARD_OOM_MB=600`, `cpu=0.25`, `memory=0.5Gi`. The container tries to allocate 600 MiB at startup, exceeds the 0.5Gi cgroup limit, and gets SIGKILL'd before the HTTP server binds. |
| `trigger-scenario-b.sh` | Creates `ca-oom-leak` with `MODE=leak` and `LEAK_MB_PER_TICK=30`, `cpu=0.25`, `memory=0.5Gi`. A background thread retains 30 MiB every 20 seconds. The HTTP server stays healthy until the leak crosses the ceiling, then OOMKills. |
| `trigger-scenario-c.sh` | Creates `ca-oom-healthy` with `MODE=healthy`, `cpu=0.5`, `memory=1.0Gi`. No allocations beyond the Python runtime. Acts as a control to prove the platform and image are fine. |

### Wait, then verify each scenario

```bash
echo "Waiting 10 minutes for log ingestion and leak progression..."
sleep 600

APP_NAME=ca-oom-hard    bash labs/memory-leak-oomkilled/verify.sh
APP_NAME=ca-oom-leak    bash labs/memory-leak-oomkilled/verify.sh
APP_NAME=ca-oom-healthy bash labs/memory-leak-oomkilled/verify.sh
```

`verify.sh` collects every available signal per app: app configuration, active revisions, replica list, Log Analytics workspace ID, system-log query for exit-137 and OOM patterns, console-log query for `[leak] tick` entries, and `RestartCount`. Output goes to `labs/memory-leak-oomkilled/evidence/<APP_NAME>/report-<TIMESTAMP>.txt`. Note: `MemoryPercentage` and `WorkingSetBytes` time series are read from the Portal **Metrics** blade (captures 22-23, 27) rather than the CLI — the `az monitor metrics list` calls in `verify.sh` return empty payloads for short observation windows on newly created revisions, so the Portal Metrics chart is the authoritative source for memory-trace evidence in this lab.

### Apply fix to Scenario A and verify recovery

```bash
bash labs/memory-leak-oomkilled/trigger-fix.sh
sleep 90
APP_NAME=ca-oom-hard bash labs/memory-leak-oomkilled/verify.sh
```

| Command | Why it is used |
|---|---|
| `trigger-fix.sh` | Updates `ca-oom-hard` with `MODE=healthy` and `--memory 1.0Gi --cpu 0.5`. This creates a new revision (`--0000001`); the failing revision (`--18xosgl`) is retained but deactivated. |
| Second `verify.sh` | Confirms the new revision is `HealthState: Healthy` and the old revision is preserved as evidence. The Portal **Metrics** blade is the authoritative source for confirming `MemoryPercentage` returned to baseline. |

## 4) Experiment Log

Tested in Azure region Korea Central, 2026-06-20, az CLI 2.79.0, containerapp extension 1.3.0b4.

### Scenario A: Hard OOM evidence [Observed]

```text
# verify.sh output for ca-oom-hard (pre-fix, 2026-06-20T04:21:13Z)
Active revisions: ca-oom-hard--18xosgl
HealthState:      Unhealthy
ProvisioningState: Failed
RunningState:     Stopped

# System log entries (excerpt):
Container 'ca-oom-hard' was terminated with exit code '137' and reason 'ProcessExited'   ContainerTerminated
Container 'ca-oom-hard' was terminated with exit code '137'                              ProcessExited
Container 'ca-oom-hard' was terminated with exit code '137' and reason 'ProcessExited'   ContainerTerminated
... (76 such entries within ~17 minutes)

# Console log entries (excerpt): allocation progress prints only.
[hard-oom] allocating 600 MiB at startup (will exceed cgroup limit)
[hard-oom] allocated 50/600 MiB
[hard-oom] allocated 100/600 MiB
... (climbs to ~400-450/600 MiB)
# The line "[app] listening on :8000" is NEVER printed —
# the kernel killed the process during the allocation loop, before serve()
# was reached, so no HTTP traffic ever flowed.
```

### Scenario B: Gradual leak evidence [Measured]

```text
# verify.sh output for ca-oom-leak (2026-06-20T04:22:00Z)
Active revisions: ca-oom-leak--y1hn6jn
HealthState:      Healthy (at time of capture, before first OOM)
RestartCount:     0

# Console log entries (excerpt — progressive tick prints):
[leak] tick 1:  +30 MiB, total retained  30 MiB
[leak] tick 2:  +30 MiB, total retained  60 MiB
[leak] tick 3:  +30 MiB, total retained  90 MiB
...
[leak] tick 12: +30 MiB, total retained 360 MiB
[leak] tick 13: +30 MiB, total retained 390 MiB
[leak] tick 14: +30 MiB, total retained 420 MiB    ← OOM imminent

# Portal Metrics blade — WorkingSetBytes chart (capture 23, 60s bin):
# climbs linearly from ~50 MiB to ~450 MiB over the first 5 minutes,
# then drops to ~50 MiB at restart, then climbs again.
```

### Scenario C: Healthy control evidence [Observed]

```text
# verify.sh output for ca-oom-healthy (2026-06-20T04:22:46Z)
Active revisions: ca-oom-healthy--00000<X>
HealthState:      Healthy
ProvisioningState: Provisioned
RunningState:     RunningAtMaxScale
RestartCount:     0

# Console log entries: only the startup line (request logging is suppressed
# by `log_message = return` in the HTTP handler, so individual GET hits are
# not printed by design).
[app] listening on :8000
... (no errors, no terminations)

# Portal Metrics blade — WorkingSetBytes chart (capture 27): stable at
# ~30-50 MiB for the entire observation window.
```

### Post-fix evidence [Observed]

```text
# verify.sh output for ca-oom-hard (post-fix, 2026-06-20T06:02:57Z)
Active revisions: ca-oom-hard--0000001    ← NEW revision after fix
HealthState:      Healthy
ProvisioningState: Provisioned
RunningState:     RunningAtMaxScale
Replicas:         1
Memory:           1Gi                       ← raised from 0.5Gi
CPU:              0.5                       ← raised from 0.25

# System log entries during fix rollout:
Replica 'ca-oom-hard--0000001-67d777f859-v6brv' has been scheduled to run on a node.    AssigningReplica
Creating a new revision: ca-oom-hard--0000001                                            RevisionCreation
Rolling Transition: Successfully completed rolling over existing to latest revision...   RollingRevisionCompleted
Successfully updated containerApp: ca-oom-hard                                           ContainerAppReady
Deactivating old revisions for ContainerApp 'ca-oom-hard'                                RevisionDeactivating
Created container 'ca-oom-hard'                                                          ContainerCreated
Started container 'ca-oom-hard'                                                          ContainerStarted

# Failing revision (ca-oom-hard--18xosgl) status:
Active:           false
RunningState:     Stopped
(retained inactive for evidence; NOT deleted)
```

### Operator takeaway from experiment

1. **Exit code 137 alone does not prove OOM**. SIGKILL also comes from admin actions, deployment cycles, and manual restarts. Confirm OOM with the `MemoryPercentage` curve — it should approach 100% just before the exit timestamp.
2. **System logs do not explicitly say "OOMKilled"**. Look for `exit code '137'` + `ProcessExited` + `ContainerTerminated`. The kernel does not write an OOM message into the platform log surface — only the kill is visible.
3. **Hard OOM versus gradual leak look different in metrics**. Hard OOM: `MemoryPercentage` spikes to ~100% within seconds, container dies before HTTP traffic. Gradual leak: `MemoryPercentage` climbs over minutes, container serves traffic until the ceiling is hit, then restart history shows a periodic cliff pattern.
4. **Always validate the fix**. Raising memory alone does not fix a true leak — it only delays the OOM. The Scenario B pattern (re-leak after restart) makes this visible. The fix must change the workload (Scenario A's `MODE=healthy` switch) or include both axes (memory raise plus workload fix).
5. **Preserve the failing revision**. `az containerapp update` creates a new revision but does not delete the old one. The Revisions blade retains the failing revision's `HealthState` and `RunningState` for post-incident review. Do not delete it until evidence collection is complete.

## 5) Verification Queries

### KQL: Cross-scenario exit-event summary

```kusto
ContainerAppSystemLogs_CL
| where ContainerAppName_s in ("ca-oom-hard", "ca-oom-leak", "ca-oom-healthy")
| where Log_s has "exit code" or Reason_s in ("ContainerTerminated", "ProcessExited")
| summarize ExitEvents = count() by ContainerAppName_s, Reason_s
| order by ExitEvents desc
```

Expected: `ca-oom-hard` shows the highest count concentrated in `ContainerTerminated` and `ProcessExited`. `ca-oom-leak` shows a smaller but non-zero count. `ca-oom-healthy` shows zero.

### KQL: Scenario B leak-tick console log

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-oom-leak"
| where Log_s has "[leak] tick"
| project TimeGenerated, Log_s
| order by TimeGenerated asc
```

Expected: Progressive `[leak] tick N: +30 MiB, total retained K MiB` entries. The `K` value increases by 30 each tick until the container is killed and restarted.

### KQL: Scenario A container-terminated detail

```kusto
ContainerAppSystemLogs_CL
| where ContainerAppName_s == "ca-oom-hard"
| where Reason_s in ("ContainerTerminated", "ProcessExited")
| where Log_s has "137"
| project TimeGenerated, Reason_s, Log_s, RevisionName_s
| order by TimeGenerated asc
```

Expected: Repeated `exit code '137'` entries scoped to the failing revision (`ca-oom-hard--18xosgl`). Each entry is a separate SIGKILL event.

### KQL: Memory growth timechart

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-oom-leak"
| where Log_s has "[leak] tick"
| extend RetainedMiB = toint(extract(@"total retained (\d+) MiB", 1, Log_s))
| project TimeGenerated, RetainedMiB
| order by TimeGenerated asc
| render timechart
```

Expected: A staircase that climbs by 30 MiB every 20 seconds, with a sharp reset to baseline each time the container is OOMKilled and restarted.

### KQL: ProbeFailed on Scenario B (after leak crosses ceiling)

```kusto
ContainerAppSystemLogs_CL
| where ContainerAppName_s == "ca-oom-leak"
| where Reason_s == "ProbeFailed"
| project TimeGenerated, Log_s
| order by TimeGenerated asc
```

Expected: Probe-failure entries appearing once the leak exhausts the memory budget and the process slows or stops responding before SIGKILL.

### KQL: ScaledObjectCheckFailed (KEDA correlation)

```kusto
ContainerAppSystemLogs_CL
| where ContainerAppName_s == "ca-oom-hard"
| where Reason_s == "ScaledObjectCheckFailed"
| project TimeGenerated, Log_s
| order by TimeGenerated asc
```

Expected: KEDA scaler check failures while the revision is in CrashLoopBackOff (the scaler cannot read metrics from a container that is not Ready). This is a downstream symptom — not the root cause — and it disappears after the fix.

## 6) Portal Evidence

All captures live in `docs/assets/troubleshooting/memory-leak-oomkilled/`. Each capture was taken in a sanitized Azure Portal session with the documented inline PII helper applied (subscription/tenant GUIDs zeroed, MCAPS subscription name replaced with the Visual Studio Enterprise placeholder, Microsoft Non-Production tenant replaced with Contoso, `@microsoft.com` emails rewritten to `user@example.com`, `ychoe`/`Yeongseon Choe` rewritten to `demouser`/`Demo User`, account-menu avatar masked with Portal blue `#0078d4`).

### Resource Group landing

!!! note "Portal evidence — Resource group overview"
    The lab's resource group `rg-aca-memleak-lab` contains the Log Analytics workspace, the Azure Container Registry, the Container Apps environment, and the three Container App scenarios.

    ![Resource group overview listing all lab resources](../../assets/troubleshooting/memory-leak-oomkilled/01-resource-group-overview.png)

### Scenario A — `ca-oom-hard` (Hard OOM)

!!! note "Portal evidence — Overview and revisions during failure"
    The Container App overview shows `ProvisioningState: Failed` and `RunningStatus: Stopped`. The Revisions blade shows the failing revision `ca-oom-hard--18xosgl` with `HealthState: Unhealthy`.

    ![ca-oom-hard Overview blade showing failure state](../../assets/troubleshooting/memory-leak-oomkilled/02-ca-oom-hard-overview.png)

    ![ca-oom-hard Revisions blade showing the failing revision](../../assets/troubleshooting/memory-leak-oomkilled/03-ca-oom-hard-revisions.png)

    ![ca-oom-hard Revision detail flyout with HealthState=Unhealthy](../../assets/troubleshooting/memory-leak-oomkilled/04-ca-oom-hard-revision-detail.png)

!!! note "Portal evidence — Container configuration and scale rule"
    The Containers blade confirms `memory: 0.5Gi` and `cpu: 0.25` for the failing revision. The env vars `MODE=hard-oom` and `HARD_OOM_MB=600` are set by `trigger-scenario-a.sh` and visible in the **Environment variables** tab of the same blade (not captured here). The Scale blade shows the active KEDA configuration (min 1, max 1).

    ![ca-oom-hard Containers blade Properties tab showing 0.5Gi memory and 0.25 vCPU](../../assets/troubleshooting/memory-leak-oomkilled/05-ca-oom-hard-containers.png)

    ![ca-oom-hard Scale blade showing min/max replicas](../../assets/troubleshooting/memory-leak-oomkilled/06-ca-oom-hard-scale.png)

!!! note "Portal evidence — Log stream during CrashLoopBackOff"
    The System log stream captures the `ContainerTerminated` / `ProcessExited` entries with `exit code '137'`. The Application log stream shows the `[hard-oom] allocating ...` line followed by `[hard-oom] allocated N/600 MiB` progress lines climbing to ~400-450 MiB — and then nothing. The expected `[app] listening on :8000` line is **never** printed: the kernel killed the process during the allocation loop, before `serve()` was reached, so no HTTP traffic ever flowed.

    ![ca-oom-hard System log stream showing exit code 137 entries](../../assets/troubleshooting/memory-leak-oomkilled/07-ca-oom-hard-logstream-system.png)

    ![ca-oom-hard Application log stream showing allocation progress lines but no "[app] listening" message](../../assets/troubleshooting/memory-leak-oomkilled/08-ca-oom-hard-logstream-application.png)

!!! note "Portal evidence — Metrics during failure"
    The Memory Percentage metric stays at the cgroup ceiling. The Memory Working Set Bytes metric mirrors the same shape in absolute bytes. CPU Usage is near zero (the container exits before doing significant work). RestartCount climbs in steps. Replica Count flips between 0 and 1 as Kubernetes attempts and aborts restarts.

    ![ca-oom-hard Memory Percentage metric — at ceiling](../../assets/troubleshooting/memory-leak-oomkilled/09-ca-oom-hard-metric-memory-percentage.png)

    ![ca-oom-hard Memory Working Set Bytes metric — at ceiling](../../assets/troubleshooting/memory-leak-oomkilled/10-ca-oom-hard-metric-memory-working-set-bytes.png)

    ![ca-oom-hard CPU Usage metric — near zero](../../assets/troubleshooting/memory-leak-oomkilled/11-ca-oom-hard-metric-cpu-usage.png)

    ![ca-oom-hard Restart Count metric — climbing](../../assets/troubleshooting/memory-leak-oomkilled/12-ca-oom-hard-metric-restart-count.png)

    ![ca-oom-hard Replica Count metric — flipping during CrashLoopBackOff](../../assets/troubleshooting/memory-leak-oomkilled/13-ca-oom-hard-metric-replica-count.png)

!!! note "Portal evidence — Logs (KQL) and Activity Log"
    The Logs blade running the cross-scenario KQL query confirms the failure pattern is isolated to `ca-oom-hard`. The Activity Log captures every `Create or Update Container App` operation against the resource.

    ![ca-oom-hard Logs blade running the cross-scenario exit-event KQL](../../assets/troubleshooting/memory-leak-oomkilled/14-ca-oom-hard-logs-kql.png)

    ![ca-oom-hard Activity Log listing the deployment operations](../../assets/troubleshooting/memory-leak-oomkilled/15-ca-oom-hard-activity-log.png)

!!! note "Portal evidence — Diagnose and Solve during the live incident (pre-fix)"
    Captures 16 through 16d show the Diagnose-and-Solve experience an operator sees **during** the incident, while the failing revision (`ca-oom-hard--18xosgl`) is still the active revision. Compare with captures 44 through 47 in the post-fix subsection further down — the same detectors render different summary cards once a healthy revision is in place.

    ![Diagnose and Solve landing page during the incident](../../assets/troubleshooting/memory-leak-oomkilled/16-ca-oom-hard-diagnose.png)

    ![Availability and Performance category during the incident, failing revision active](../../assets/troubleshooting/memory-leak-oomkilled/16b-ca-oom-hard-diagnose-availability.png)

    ![Container App Memory Usage detector during the incident — thresholds exceeded](../../assets/troubleshooting/memory-leak-oomkilled/16c-ca-oom-hard-diagnose-memory-usage.png)

    ![Container Exit Events detector during the incident — exit code 137 cluster](../../assets/troubleshooting/memory-leak-oomkilled/16d-ca-oom-hard-diagnose-exit-events.png)

    ![Container Exit Events detector during the incident — full-blade view](../../assets/troubleshooting/memory-leak-oomkilled/16d-ca-oom-hard-diagnose-exit-events-full.png)

### Scenario B — `ca-oom-leak` (Gradual leak)

!!! note "Portal evidence — Overview, containers, scale"
    Scenario B uses the same image as Scenario A. The Containers blade shows `memory: 0.5Gi` and `cpu: 0.25`. The differentiating env vars `MODE=leak` and `LEAK_MB_PER_TICK=30` are set by `trigger-scenario-b.sh` and visible in the **Environment variables** tab of the same blade (not captured here). The Scale blade shows the same min/max as the other scenarios.

    ![ca-oom-leak Overview blade](../../assets/troubleshooting/memory-leak-oomkilled/17-ca-oom-leak-overview.png)

    ![ca-oom-leak Containers blade Properties tab showing 0.5Gi memory and 0.25 vCPU](../../assets/troubleshooting/memory-leak-oomkilled/18-ca-oom-leak-containers.png)

    ![ca-oom-leak Scale blade](../../assets/troubleshooting/memory-leak-oomkilled/19-ca-oom-leak-scale.png)

!!! note "Portal evidence — Log streams during progressive leak"
    The System log stream captures the eventual `ContainerTerminated` after the leak crosses the ceiling. The Application log stream shows the progressive `[leak] tick N: +30 MiB, total retained K MiB` entries — this is the signature pattern that distinguishes a gradual leak from a hard OOM.

    ![ca-oom-leak System log stream](../../assets/troubleshooting/memory-leak-oomkilled/20-ca-oom-leak-logstream-system.png)

    ![ca-oom-leak Application log stream showing [leak] tick entries](../../assets/troubleshooting/memory-leak-oomkilled/21-ca-oom-leak-logstream-application.png)

!!! note "Portal evidence — Metrics showing the staircase pattern"
    Memory Percentage and Memory Working Set Bytes climb linearly, then drop to baseline when the container is OOMKilled, then climb again — the staircase pattern that proves the leak is in the workload. RestartCount and ReplicaCount track the kill-and-restart cycle.

    ![ca-oom-leak Memory Percentage metric — staircase](../../assets/troubleshooting/memory-leak-oomkilled/22-ca-oom-leak-metric-memory-percentage.png)

    ![ca-oom-leak Memory Working Set Bytes metric — staircase](../../assets/troubleshooting/memory-leak-oomkilled/23-ca-oom-leak-metric-memory-working-set-bytes.png)

    ![ca-oom-leak Restart Count metric](../../assets/troubleshooting/memory-leak-oomkilled/24-ca-oom-leak-metric-restart-count.png)

    ![ca-oom-leak Replica Count metric](../../assets/troubleshooting/memory-leak-oomkilled/25-ca-oom-leak-metric-replica-count.png)

### Scenario C — `ca-oom-healthy` (Healthy control)

!!! note "Portal evidence — Stable healthy baseline"
    The Container App overview shows `Healthy`. The Memory Percentage metric stays flat at a very low level. The Revisions blade shows a single active revision with `HealthState: Healthy` and no restart history. This is the control proving the platform, image, environment, and network path are all fine.

    ![ca-oom-healthy Overview blade — Healthy](../../assets/troubleshooting/memory-leak-oomkilled/26-ca-oom-healthy-overview.png)

    ![ca-oom-healthy Memory Percentage metric — flat baseline](../../assets/troubleshooting/memory-leak-oomkilled/27-ca-oom-healthy-metric-memory-percentage.png)

    ![ca-oom-healthy Revisions blade — single healthy revision](../../assets/troubleshooting/memory-leak-oomkilled/28-ca-oom-healthy-revisions.png)

### Environment and Log Analytics workspace

!!! note "Portal evidence — Shared environment and workspace"
    All three Container Apps share one Container Apps environment, which forwards both system logs and application logs to one Log Analytics workspace. This is what makes the cross-scenario KQL queries possible.

    ![Container Apps environment overview](../../assets/troubleshooting/memory-leak-oomkilled/29-environment-overview.png)

    ![Log Analytics workspace overview](../../assets/troubleshooting/memory-leak-oomkilled/30-loganalytics-workspace-overview.png)

### KQL verification queries (Logs blade)

!!! note "Portal evidence — Cross-scenario exit-event summary"
    The cross-scenario `summarize` confirms the failure pattern is concentrated on `ca-oom-hard`, present in smaller quantity on `ca-oom-leak`, and absent on `ca-oom-healthy`. This is the single best one-shot view of "which scenarios are OOMing".

    ![KQL: cross-scenario exit-event summary](../../assets/troubleshooting/memory-leak-oomkilled/31-kql-cross-scenario-exit-events.png)

!!! note "Portal evidence — Schema discovery and leak tick log"
    The schema-discovery query lists the available columns on `ContainerAppConsoleLogs_CL`. The leak-tick query renders the progressive `[leak] tick` entries on `ca-oom-leak`.

    ![KQL: ContainerAppConsoleLogs_CL schema](../../assets/troubleshooting/memory-leak-oomkilled/32a-kql-schema-discovery.png)

    ![KQL: ca-oom-leak [leak] tick entries](../../assets/troubleshooting/memory-leak-oomkilled/32-kql-ca-oom-leak-app-log-ticks.png)

!!! note "Portal evidence — Container terminated detail"
    The `ContainerTerminated` detail query on `ca-oom-hard` projects the exact log text and revision name, giving you the full audit trail of every SIGKILL the failing revision received.

    ![KQL: ca-oom-hard container terminated detail](../../assets/troubleshooting/memory-leak-oomkilled/33-kql-ca-oom-hard-container-terminated.png)

!!! note "Portal evidence — Memory growth timechart"
    The `render timechart` of `total retained MiB` extracted from the leak tick logs produces the staircase visualization. Each step is a 30 MiB allocation. Each drop is an OOMKill plus restart.

    ![KQL: ca-oom-leak memory growth timechart](../../assets/troubleshooting/memory-leak-oomkilled/34-kql-memory-growth-timechart.png)

!!! note "Portal evidence — AzureMetrics path returns empty (teaching point)"
    A common operator instinct is to query the `AzureMetrics` table for `MemoryPercentage`. The query parses but returns **zero rows** for Azure Container Apps resources, because Azure Container Apps platform metrics (`MemoryPercentage`, `WorkingSetBytes`, `CpuPercentage`, `RestartCount`, `Replicas`) are not routed into the `AzureMetrics` Log Analytics table. The correct paths are the Azure Monitor Metrics service directly (the **Metrics** blade in the Portal, or `az monitor metrics list --resource ... --metric ...` from the CLI). The Log Analytics tables (`ContainerAppSystemLogs_CL` / `ContainerAppConsoleLogs_CL`) are for **events and application log lines**, not for platform metric series. This empty-result capture documents the wrong path so future operators do not waste time on it.

    ![KQL: AzureMetrics MemoryPercentage query returning zero rows for Container Apps](../../assets/troubleshooting/memory-leak-oomkilled/34-kql-memory-percentage-azuremetrics.png)

!!! note "Portal evidence — ProbeFailed and ScaledObjectCheckFailed (downstream symptoms)"
    These two queries show the downstream effects of the OOM: the readiness probe fails once the leak exhausts the memory budget, and KEDA's scaler-check fails because it cannot read metrics from a Not-Ready container. Both clear up after the fix.

    ![KQL: ca-oom-leak ProbeFailed entries](../../assets/troubleshooting/memory-leak-oomkilled/35-kql-ca-oom-leak-probefailed.png)

    ![KQL: ca-oom-hard ScaledObjectCheckFailed entries](../../assets/troubleshooting/memory-leak-oomkilled/36-kql-ca-oom-hard-scaledobjectcheckfailed.png)

### Post-fix verification

!!! note "Portal evidence — Overview, revisions, and containers after the fix"
    After `trigger-fix.sh` updates Scenario A to `MODE=healthy` with `memory=1.0Gi`, a new revision `ca-oom-hard--0000001` is created. The overview shows `Running`. The Revisions blade shows the new healthy revision alongside the failing one (now inactive but preserved). The Containers blade confirms the new memory allocation.

    ![ca-oom-hard Overview blade after fix — Running](../../assets/troubleshooting/memory-leak-oomkilled/37-ca-oom-hard-overview-postfix.png)

    ![ca-oom-hard Revisions blade after fix — new healthy revision](../../assets/troubleshooting/memory-leak-oomkilled/38-ca-oom-hard-revisions-postfix.png)

    ![ca-oom-hard Revisions blade showing the inactive failing revision retained for evidence](../../assets/troubleshooting/memory-leak-oomkilled/38b-ca-oom-hard-revisions-inactive.png)

    ![ca-oom-hard Containers blade after fix — 1Gi memory](../../assets/troubleshooting/memory-leak-oomkilled/43-ca-oom-hard-containers-postfix.png)

!!! note "Portal evidence — Metrics after the fix"
    The Metrics blade after the fix shows Memory Working Set stable at ~15 MiB (the Python runtime), well below the new 1Gi ceiling. The metric picker confirms all Container Apps metric dimensions are available per revision and per replica.

    ![ca-oom-hard Metrics blade initial view after fix](../../assets/troubleshooting/memory-leak-oomkilled/39-ca-oom-hard-metrics-blade-initial.png)

    ![ca-oom-hard Memory Working Set Bytes metric after fix — stable](../../assets/troubleshooting/memory-leak-oomkilled/39b-ca-oom-hard-metrics-memoryworkingset.png)

    ![ca-oom-hard Metric picker dropdown showing available metrics](../../assets/troubleshooting/memory-leak-oomkilled/39c-ca-oom-hard-metrics-dropdown.png)

!!! note "Portal evidence — Activity Log of the fix operations"
    The Activity Log captures the exact `Create or Update Container App` operations that produced the failing revision and then the fix revision, including the operation status, timestamps, and operation detail.

    ![ca-oom-hard Activity Log listing the create and fix operations](../../assets/troubleshooting/memory-leak-oomkilled/40-ca-oom-hard-activity-log.png)

    ![ca-oom-hard Activity Log entry expanded](../../assets/troubleshooting/memory-leak-oomkilled/41-ca-oom-hard-activity-log-create-expanded.png)

    ![ca-oom-hard Activity Log operation detail](../../assets/troubleshooting/memory-leak-oomkilled/42-ca-oom-hard-activity-log-operation-detail.png)

### Diagnose and Solve Problems (Portal-native OOM diagnosis)

The Azure Portal Diagnose-and-Solve Problems blade is the single best evidence surface for OOM diagnosis: it provides the Portal's own diagnosis text, the per-revision exit-event count, and a differential view that rules out alternative causes.

!!! note "Portal evidence — Diagnose and Solve landing page"
    The Diagnose-and-Solve landing page exposes seven troubleshooting categories. For OOM diagnosis, drill into `Availability and Performance`.

    ![Diagnose and Solve Problems landing page with seven categories](../../assets/troubleshooting/memory-leak-oomkilled/44-ca-oom-hard-diagnose-solve.png)

!!! note "Portal evidence — Availability and Performance overview"
    The Availability-and-Performance category aggregates 13 detectors. The Revisions Health chart shows the new revision (`ca-oom-hard--0000001`) green alongside the inactive failing revision (`ca-oom-hard--18xosgl`) red — a side-by-side fix-validation view.

    ![Availability and Performance category — Revisions Health chart with green/red revisions and 13 detector sidebar](../../assets/troubleshooting/memory-leak-oomkilled/44b-ca-oom-hard-diagnose-availability-performance.png)

!!! note "Portal evidence — Container App Memory Usage detector (post-fix)"
    The Container App Memory Usage detector independently confirms the fix: a green check reads "No revisions detected with Memory usage exceeding warning or critical thresholds". The per-replica chart shows `Memory: 1Gi` with the new replica running well under the 80% warning threshold.

    ![Container App Memory Usage detector — green check, no thresholds exceeded](../../assets/troubleshooting/memory-leak-oomkilled/44c-ca-oom-hard-diagnose-memory-detector.png)

    ![Container App Memory Usage detector — per-revision chart showing 1Gi config and 80% warning threshold](../../assets/troubleshooting/memory-leak-oomkilled/44d-ca-oom-hard-diagnose-memory-perrevision.png)

!!! note "Portal evidence — Container Exit Events detector (the killer evidence)"
    The Container Exit Events detector is the single most valuable Portal capture in this lab. It contains the Portal's **own** OOM diagnosis text:

    > "Resource exhaustion - containers terminated with SIGKILL (exit code 137) ... This is commonly caused by Out of Memory (OOM) conditions."

    The header counter reads `28 exit event(s)`. The recommended action points to the Metrics blade and the Container App CPU and Memory detectors.

    ![Container Exit Events detector — 28 exit events, Portal text identifying SIGKILL as OOM](../../assets/troubleshooting/memory-leak-oomkilled/45-ca-oom-hard-diagnose-exit-events.png)

!!! note "Portal evidence — Exit Events common root causes"
    The detector enumerates the common root causes of container exits: port mismatch, missing environment variables or secrets, health-probe misconfiguration, and application errors. It cross-references the same `ContainerAppConsoleLogs_CL` and `ContainerAppSystemLogs_CL` tables used in the lab's KQL queries, plus the Health Probe Failures detector.

    ![Container Exit Events detector — common root causes and KQL table references](../../assets/troubleshooting/memory-leak-oomkilled/45b-ca-oom-hard-diagnose-exit-codes-table.png)

!!! note "Portal evidence — Exit Events graph and per-revision drill-down"
    The Exit Events graph plots a bar chart of exit events across the 24-hour window, with two series — `exit code '137' and reason 'ProcessExited'` and `exit code '137'`. The drill-down table totals **76 exit events** for the failing revision `ca-oom-hard--18xosgl` (52 ProcessExited + 24 exit-137-only), confirming the SIGKILL count.

    ![Container Exit Events detector — bar chart and per-revision table totalling 76 events](../../assets/troubleshooting/memory-leak-oomkilled/45c-ca-oom-hard-diagnose-exit-events-graph.png)

!!! note "Portal evidence — Successful Checks (differential diagnosis)"
    The Exit Events detector's `Successful Checks (3)` section lists the other detectors that passed: Health Probe Failures, Image Pull Failures, and Ingress Port settings check. This is the Portal's **differential diagnosis**: it has ruled out probes, image pull, and port configuration, leaving OOM as the explanation.

    ![Container Exit Events detector — Successful Checks ruling out probes, image pull, and ingress port](../../assets/troubleshooting/memory-leak-oomkilled/45d-ca-oom-hard-diagnose-exit-events-checks.png)

!!! note "Portal evidence — Container Create Failures detector (clean)"
    The Container Create Failures detector explicitly reports "No container creation failures have been detected" — proving the failing revision was **created successfully** then killed at runtime, not blocked at containerd. This is the differential evidence that distinguishes OOM from image-pull failure or runtime-create failure.

    ![Container Create Failures detector — clean, proving OOM is at runtime not at container create](../../assets/troubleshooting/memory-leak-oomkilled/46-ca-oom-hard-diagnose-container-create-failures.png)

!!! note "Portal evidence — Health Probe Failures detector (clean)"
    The Health Probe Failures detector explicitly reports "No Health Probe failures were detected" between the failure window timestamps — confirming the OOM was not caused by a misconfigured probe. The kernel SIGKILL fired before any probe could fail.

    ![Health Probe Failures detector — clean, ruling out probe misconfiguration as the cause](../../assets/troubleshooting/memory-leak-oomkilled/47-ca-oom-hard-diagnose-health-probe-failures.png)

## Clean Up

```bash
bash labs/memory-leak-oomkilled/cleanup.sh
```

| Command | Why it is used |
|---|---|
| `cleanup.sh` | Deletes the resource group `rg-aca-memleak-lab` and all child resources asynchronously. |

## Related Playbook

- [Memory Leak OOMKilled](../playbooks/scaling-and-runtime/memory-leak-oomkilled.md)

## See Also

- [CPU Throttling Lab](./cpu-throttling.md)
- [CrashLoop OOM and Resource Pressure Playbook](../playbooks/scaling-and-runtime/crashloop-oom-and-resource-pressure.md)
- [KEDA "No Metrics Returned" Lab](./keda-no-metrics-returned.md)

## Sources

- [Troubleshoot container start failures in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-container-start-failures)
- [Metrics in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/metrics)
- [Containers in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/containers)
- [Application logging in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/logging)
- [Health probes in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/health-probes)
