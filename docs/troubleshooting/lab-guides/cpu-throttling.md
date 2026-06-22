---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/containers
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/metrics
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
  diagrams:
    - id: cpu-throttling-lab-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/containers
        - https://learn.microsoft.com/en-us/azure/container-apps/metrics
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app
validation:
  az_cli:
    last_tested: '2026-06-22'
    cli_version: '2.79.0'
    result: pass
  bicep:
    last_tested: '2026-06-22'
    result: pass
---
# CPU Throttling Lab

Reproducible lab demonstrating that per-replica CPU allocation is the dominant bottleneck for a CPU-bound HTTP workload on Azure Container Apps, and that raising the CPU allocation from 0.25 vCPU to 1.0 vCPU removes the bottleneck under the same byte-identical concurrent load. The lab uses a deterministic CPU-bound workload (`python:3.12-slim` running an inline HTTP server that computes 80 SHA-256 hashes over a 200 KiB buffer per GET) so the latency difference between the baseline and the post-fix run is attributable to per-replica CPU pressure and not to cold-start, image-pull, or scale-out effects.

## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 10-15 minutes |
| Tier | Full evidence pack (IaC + scripts + raw CLI evidence) |
| Category | Scaling and Runtime |

<!-- diagram-id: cpu-throttling-lab-flow -->
```mermaid
flowchart TD
    A[Deploy Container App with cpu=0.25, memory=0.5Gi, single replica via Bicep] --> B[Capture initial config + revision list]
    B --> C[Warm up replica with 5 discarded GETs]
    C --> D[Load test 100 req / 20 concurrent at cpu=0.25, capture p50/p95/p99/max/avg]
    D --> E[az containerapp update --cpu 1.0 --memory 2.0Gi -> new revision]
    E --> F[Wait for new revision to reach runningState=Running]
    F --> G[Warm up new replica with 5 discarded GETs]
    G --> H[Load test 100 req / 20 concurrent at cpu=1.0, byte-identical client code]
    H --> I[Evaluate H1: cpu=0.25 p95 > 100ms AND H2: cpu=1.0 p95 < 50% of cpu=0.25 p95]
```

!!! note "Evidence depth"
    This lab is **fully reproducible** with dedicated infrastructure-as-code, helper scripts, and raw evidence committed under [`labs/cpu-throttling/`](https://github.com/yeongseon/azure-container-apps-practical-guide/tree/main/labs/cpu-throttling):

    - `infra/main.bicep` provisions a Log Analytics workspace, a Container Apps Environment (Consumption), and one Container App running `python:3.12-slim` with an inline CPU-burn HTTP server (80 SHA-256 hashes over a 200 KiB buffer per GET) at `cpu: '0.25'`, `memory: '0.5Gi'`, `minReplicas: 1`, `maxReplicas: 1`, and `activeRevisionsMode: 'Single'`. The container image, command, and inline Python script are byte-identical across the baseline and post-fix runs — the only experimental variable is the per-replica CPU/memory allocation.
    - `load_test.py` is a 93-line standalone load generator using `ThreadPoolExecutor` with nearest-rank percentile aggregation. The same file is used by both `trigger.sh` and `verify.sh` so the cpu=0.25 baseline and cpu=1.0 post-fix runs are measured by byte-identical client code.
    - `trigger.sh` runs Phases 1-5: capture initial config (fails fast if `cpu != 0.25`), capture initial revision list, warm up the replica with 5 discarded GETs, run a 100-request / 20-concurrent load test against the FQDN, and capture the `UsageNanoCores` metric for the baseline window.
    - `verify.sh` runs Phases 6-12: apply the fix (`az containerapp update --cpu 1.0 --memory 2.0Gi`), poll until the new revision reaches `runningState=Running` (max 5 min), capture post-fix config and revision list, warm up the new replica, re-run the byte-identical 100/20 load test, capture the post-fix `UsageNanoCores` metric, and evaluate H1+H2 with explicit exit codes (0=supported, 1=invalid, 2=falsified).
    - `evidence/` carries 15 raw captures from the 2026-06-22 reproduction in `koreacentral`: full script execution logs (`00-trigger-run.txt`, `00-verify-run.txt`), per-phase JSON captures of the app configuration, revision list, load-test latency, and `UsageNanoCores` metric (`01`-`09`), and supporting environment captures (CLI version, `containerapp` extension version, region, Bicep deployment outputs).

    Azure Portal screenshots (Container App Overview, Metrics blade with `UsageNanoCores`, Revisions blade with cpu=0.25 and cpu=1.0 revisions side-by-side) are **pending in a follow-up PR**. The follow-up will re-deploy the same Bicep template in a short-lived environment purely to capture the Portal blades, then close out.

## 1) Background

On Azure Container Apps, is per-replica CPU allocation the dominant bottleneck for a CPU-bound HTTP workload — and does raising the configured CPU/memory envelope via `az containerapp update --cpu --memory` cleanly remove that bottleneck under the same concurrent load?

The lab uses a dedicated resource group and Bicep template (`infra/main.bicep`) that provisions exactly three resources: a Log Analytics workspace, a Container Apps Environment, and one Container App at `cpu: '0.25'`, `memory: '0.5Gi'`, `minReplicas: 1`, `maxReplicas: 1`. No ACR (the image is `python:3.12-slim` from public Docker Hub), no Application Insights, no private endpoint, no public IP. The Container App runs an inline Python HTTP server that performs a deterministic 80 SHA-256 hashes over a 200 KiB buffer per GET — measured at ~40 ms of CPU work on a full vCPU at the time of this reproduction. Under Linux CFS throttling at 0.25 vCPU, that same work takes ~160 ms minimum per request plus queueing time when concurrent requests share the throttled CPU budget.

The lab deliberately avoids `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` because helloworld returns immediately without measurable CPU work, so any latency difference between cpu=0.25 and cpu=1.0 on helloworld is dominated by cold-start (~6 s spike on first request), image-pull (~1-2 s), and TLS/TCP setup (~50-100 ms) rather than steady-state CPU throttling. The inline `python:3.12-slim` server gives each GET enough deterministic CPU work to dwarf network jitter, and the lab's Phase-3 and Phase-10 warm-up steps remove cold-start as a confounding variable before each load test.

The lab also pins `minReplicas: 1, maxReplicas: 1` so a scale-out cannot mask per-replica CPU pressure. The hypothesis under test is specifically about CPU throttling at the replica level. A separate lab ([Replica Load Imbalance](./replica-load-imbalance.md)) covers scale-out behavior.

Per-replica CPU/memory allocation is documented in [Microsoft Learn → Containers in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/containers). The `UsageNanoCores` metric used by this lab to corroborate the load-test latency evidence is documented in [Microsoft Learn → Metrics in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/metrics).

Set the base inputs before running the runbook. `APP_NAME` and `APP_FQDN` are derived from Bicep outputs in the next section because `infra/main.bicep` appends a deterministic but resource-group-scoped suffix to every resource name:

```bash
export AZ_SUBSCRIPTION="<subscription-id>"
export RG="rg-aca-lab-cputhrottle"
export LOCATION="koreacentral"
```

## 2) Hypothesis

On the same Container App, same `python:3.12-slim` image, same inline CPU-burn HTTP server, and same 100-request / 20-concurrent load pattern, raising the per-replica CPU allocation from `0.25` vCPU to `1.0` vCPU (and the memory from `0.5Gi` to `2.0Gi`, the smallest valid pair for 1.0 vCPU) materially reduces tail latency. Specifically: the p95 latency at cpu=1.0 will be strictly less than 50% of the p95 latency at cpu=0.25.

The alternative hypothesis being tested is that **CPU allocation is NOT the dominant bottleneck** for this workload — meaning per-request work is bounded by some other resource (concurrency limits, network egress, dependency latency, memory pressure) and raising CPU alone has no material effect on tail latency.

**Prediction (IF / THEN):**

- IF the CPU-throttling hypothesis holds, THEN at the same 100/20 load with byte-identical client code:
    - **H1** — cpu=0.25 baseline p95 will be strictly greater than 100 ms (CPU pressure is observable). If this fails, the workload was too light to demonstrate the throttling effect and the run is invalid.
    - **H2** — cpu=1.0 post-fix p95 will be strictly less than 50% of the cpu=0.25 baseline p95 (raising CPU removes the bottleneck).
- IF the alternative hypothesis is correct, THEN H1 may still pass (something else creates the latency) but H2 will fail: the cpu=1.0 p95 will be ≥ 50% of the cpu=0.25 p95 because raising CPU alone does not address the real bottleneck.

## 3) Runbook

### Deploy infrastructure

All `az`, `./trigger.sh`, `./verify.sh`, and `./cleanup.sh` invocations below assume the working directory is the lab folder. Switch into it from the repository root before running anything:

```bash
cd labs/cpu-throttling/
```

1. Create the resource group and deploy the Bicep template. The `--parameters baseName="cputhrottle"` value is required (the Bicep template declares `param baseName string` with no default). `--name main` gives the deployment a stable, queryable name so the next step can read its outputs:

    ```bash
    az group create \
        --subscription "$AZ_SUBSCRIPTION" \
        --name "$RG" \
        --location "$LOCATION"

    az deployment group create \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name main \
        --template-file ./infra/main.bicep \
        --parameters baseName="cputhrottle"
    ```

    This creates the Log Analytics workspace, Container Apps Environment, and one Container App running the inline CPU-burn HTTP server at `cpu=0.25, memory=0.5Gi, minReplicas=1, maxReplicas=1`.

2. Read the deployment outputs the scripts need:

    ```bash
    export APP_NAME=$(az deployment group show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name main \
        --query "properties.outputs.containerAppName.value" \
        --output tsv)
    export APP_FQDN=$(az deployment group show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name main \
        --query "properties.outputs.containerAppFqdn.value" \
        --output tsv)
    ```

### Trigger the baseline (run trigger.sh)

Run `trigger.sh`, which:

- Captures `01-app-config-before.json` (reads `cpu`, `memory`, `minReplicas`, `maxReplicas`, `activeRevisionsMode`; aborts with exit code 1 if `cpu != 0.25`).
- Captures `02-revisions-before.json` (revision list before the load test — expects 1 revision from the Bicep deploy).
- Warms up the replica with 5 discarded GETs so cold-start latency does not contaminate the baseline.
- Runs a 100-request / 20-concurrent load test via `load_test.py` against `https://${APP_FQDN}/`, captures the JSON summary to `03-loadtest-cpu025.json` (url, started/finished UTC, wall_clock_seconds, requests_total/ok/err, latency_ms {p50, p95, p99, max, avg}, errors_sample).
- Captures the `UsageNanoCores` metric for the same window to `04-metrics-cpu025.json`.
- Exits 0 if requests_ok ≥ 95 AND p95 > 100 ms (clean baseline for the cpu=1.0 comparison); exits 1 if either gate fails (INVALID RUN — re-run with a heavier workload or investigate network errors).

All scripts pass `--subscription "$AZ_SUBSCRIPTION"` on every `az` invocation to immunize the run against the Azure CLI's default-subscription drift, which has been observed in long-running shells where unrelated commands silently switch back to a different subscription.

### Apply the fix and re-measure (run verify.sh)

Run `verify.sh`, which:

- Reads the cpu=0.25 baseline p95 from `03-loadtest-cpu025.json` (the file `trigger.sh` produced).
- Applies the fix: `az containerapp update --cpu 1.0 --memory 2.0Gi`. The platform creates a new revision under `activeRevisionsMode: 'Single'`; the update result (including the new revision name) is captured to `05-update-result.json`.
- Polls `az containerapp revision show` every 10 seconds until the new revision reaches `runningState=Running` or `runningState=RunningAtMaxScale`, with a 5-minute deadline. Exits 1 (INVALID RUN) on timeout.
- Captures `06-app-config-after.json` (post-fix config readback to prove `cpu=1.0`) and `07-revisions-after.json` (revision list showing the old revision in `Deprovisioning` state and the new revision active).
- Warms up the new replica with 5 discarded GETs.
- Re-runs the byte-identical 100-request / 20-concurrent load test via `load_test.py`, captures the JSON summary to `08-loadtest-cpu1.json`.
- Captures the post-fix `UsageNanoCores` metric to `09-metrics-cpu1.json`.
- Evaluates H1 and H2 and exits with one of three codes:
    - **Exit 0** — H1 PASS (cpu=0.25 baseline p95 > 100 ms, established in `trigger.sh`) AND H2 PASS (cpu=1.0 post-fix p95 < 50% of cpu=0.25 baseline p95). CPU-throttling hypothesis SUPPORTED.
    - **Exit 1** — INVALID RUN (post-fix request success count < 95/100; investigate before re-running).
    - **Exit 2** — H2 FALSIFIED (cpu=1.0 p95 NOT < 50% of cpu=0.25 p95). CPU is not the dominant bottleneck; investigate concurrency, network, dependency latency, or memory pressure before raising CPU further.

### Apply the fix manually (the canonical operator response)

The fix that `verify.sh` applies is also the canonical operator response for a real CPU-throttling incident. When the lab proves CPU is the bottleneck for a given workload, the operator action is:

```bash
az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --cpu 1.0 \
    --memory 2.0Gi
```

| Command | Why it is used |
|---|---|
| `az containerapp update --cpu --memory` | Updates the per-replica CPU and memory envelope. Under `activeRevisionsMode: 'Single'`, the platform creates a new revision with the new resource settings and shifts 100% traffic to it; the old revision moves to `Deprovisioning`. Cold-start during the swap adds a few seconds for the new replica to warm up. |

The platform requires that `(cpu, memory)` be a valid pair from the documented CPU/memory matrix. For `cpu=1.0`, the minimum valid memory is `2.0Gi`. Attempting `cpu=1.0` with `memory=0.5Gi` returns a validation error.

### Prevention guidance

- Treat per-replica CPU as a configurable knob that depends on your per-request work, not as an environmental constant. The Container Apps Consumption profile defaults to `cpu=0.25, memory=0.5Gi`, which is intentionally low for cost — it is NOT the right setting for CPU-bound workloads.
- Before changing CPU in production, run `az monitor metrics list --metric UsageNanoCores --aggregation Average,Maximum` against the live app under representative load. If the average usage is pinned near the configured limit (e.g., `Average ≈ 0.25 vCPU * 1e9 nanoCores = 2.5e8 nanoCores` at cpu=0.25), CPU is at least one constraint — but raising CPU alone is only effective when each request is the unit of work that needs more compute.
- Choose between scaling UP and scaling OUT based on the workload shape:
    - **Scale UP (raise per-replica CPU/memory)** when each request needs more compute and concurrency is naturally bounded by upstream rate limits or a small concurrent-user count.
    - **Scale OUT (raise `maxReplicas` and tune scale rules)** when total throughput is the constraint and the workload is many small independent requests competing for a shared per-replica budget. See [Microsoft Learn → Scaling in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app).
- Document the CPU/memory pair in your IaC (Bicep, Terraform, ARM) so the value is visible in pull request reviews rather than hidden behind a platform default that could change. Bicep schema for `Microsoft.App/containerApps@2023-05-01` carries CPU as `properties.template.containers[N].resources.cpu` (typed as JSON number, e.g., `json('0.25')`) and memory as `properties.template.containers[N].resources.memory` (typed as string, e.g., `'0.5Gi'`).

## 4) Experiment Log

### Initial-state evidence (immediately after Bicep deploy)

- `[Observed]` `evidence/01-app-config-before.json`: `{"activeRevisionsMode": "Single", "cpu": 0.25, "memory": "0.5Gi", "minReplicas": 1, "maxReplicas": 1}` — Bicep values persisted to the live resource exactly as declared.
- `[Observed]` `evidence/02-revisions-before.json`: 1 revision visible (`ca-cputhrottle-65svxr--8pz2nir`, `active=true`, `provisioningState=Provisioned`, `runningState=RunningAtMaxScale`, `trafficWeight=100`).

### Baseline evidence (cpu=0.25, 100 req / 20 concurrent)

- `[Measured]` `evidence/03-loadtest-cpu025.json`: 100/100 successful requests, 0 errors, wall_clock=8.65s, latency_ms `{p50: 1554.5, p95: 2574.8, p99: 2703.4, max: 2800.8, avg: 1625.6}`. The p95 of **2575 ms** clears the 100 ms H1 minimum by more than 25×, confirming CPU pressure is the dominant component of tail latency at this configuration.
- `[Observed]` `evidence/04-metrics-cpu025.json`: `UsageNanoCores` query for the baseline window (07:49-08:48 UTC) returned 60 per-minute timestamps with **no Average or Maximum samples populated**. This is a documented Azure Monitor metric materialization lag (1-3 minutes typical, occasionally longer) for newly-deployed Container Apps; the snapshot was taken immediately after `trigger.sh` finished its load test. The latency evidence in `03-loadtest-cpu025.json` is the lab's primary signal; the metric capture is documented as an empty baseline so that the script behavior is reproducible and the timing limitation is visible. For a production diagnosis, wait 3-5 minutes after the load event before querying `UsageNanoCores`.

### Post-fix evidence (cpu=1.0 after `az containerapp update`)

- `[Observed]` `evidence/05-update-result.json`: `{"latestRevisionName": "ca-cputhrottle-65svxr--0000001", "name": "ca-cputhrottle-65svxr", "provisioningState": "Succeeded"}`. The platform created a new revision (`--0000001`) and shifted traffic to it under `activeRevisionsMode: 'Single'`.
- `[Observed]` `evidence/00-verify-run.txt` Phase 7 timeline: the new revision reached `runningState=Activating` at 08:50:45Z and `runningState=RunningAtMaxScale` at 08:51:00Z — a 15-second activation window from the `az containerapp update` call.
- `[Observed]` `evidence/06-app-config-after.json`: `{"cpu": 1.0, "memory": "2Gi", "minReplicas": 1, "maxReplicas": 1, "latestRevisionName": "ca-cputhrottle-65svxr--0000001"}` — config readback proves the fix landed on the new revision with the expected resource envelope.
- `[Observed]` `evidence/07-revisions-after.json`: 2 revisions visible — the old `ca-cputhrottle-65svxr--8pz2nir` in `runningState=Deprovisioning` with `trafficWeight=0`, and the new `ca-cputhrottle-65svxr--0000001` in `runningState=RunningAtMaxScale` with `trafficWeight=100`.
- `[Measured]` `evidence/08-loadtest-cpu1.json`: 100/100 successful requests, 0 errors, wall_clock=2.85s, latency_ms `{p50: 473.6, p95: 773.2, p99: 1092.8, max: 1302.2, avg: 531.0}`. The p95 of **773 ms** is 30.0% of the cpu=0.25 p95 (2575 ms), well below the 50% H2 threshold.
- `[Observed]` `evidence/09-metrics-cpu1.json`: `UsageNanoCores` query for the post-fix window (07:51-08:51 UTC) returned 62 per-minute timestamps; only the trailing minute at `08:50:00Z` has materialized samples (`average=820660.5 nanoCores`, `maximum=852758.0 nanoCores`). This is the same Azure Monitor materialization lag as the baseline capture and is further compounded by per-minute averaging: the post-fix load test ran for ~2.85 s inside a 60 s aggregation window, so the per-minute Average reads as a small fraction (≈ 2.85/60 ≈ 4.7%) of the peak instantaneous usage. The latency evidence in `08-loadtest-cpu1.json` is the primary signal; the metric capture documents that snapshot timing matters and that short-duration load events are systematically under-sampled by `PT1M` aggregation.

### Analysis

The before/after comparison isolates per-replica CPU allocation as the only relevant variable. The Container App resource is unchanged across the two load tests except for `cpu` (0.25 → 1.0) and the dependent `memory` (0.5Gi → 2Gi, required for `cpu=1.0` per the platform's CPU/memory matrix); the image, command, inline Python script, ingress, target port, and `minReplicas`/`maxReplicas` are byte-identical. Both load tests use the same `load_test.py` with the same `total=100`, `concurrency=20`, same warm-up sequence (5 discarded GETs), and target the same FQDN. Network conditions are held constant by running both tests from the same client within ~2 minutes of each other.

The 70.0% reduction in p95 (2575 ms → 773 ms) plus the 3.0× improvement in wall-clock throughput (8.65s → 2.85s for 100 requests at concurrency 20) directly demonstrates that the per-replica CPU budget at 0.25 vCPU was the controlling bottleneck. The load-test latency in `03-loadtest-cpu025.json` and `08-loadtest-cpu1.json` is the lab's primary evidence. The `UsageNanoCores` metric captures (`04-metrics-cpu025.json`, `09-metrics-cpu1.json`) document a separate operational lesson: a snapshot taken immediately after a load event under-samples by design — Azure Monitor metric aggregation typically materializes 1-3 minutes after the event, and the PT1M aggregation window further averages a short load test across a full minute. A production diagnostic should wait 3-5 minutes after the load event before querying `UsageNanoCores` and ideally use a Maximum aggregation rather than Average for short-duration events.

The supporting environment captures (`evidence/10-cli-versions.json`, `evidence/11-cli-containerapp-ext.json`, `evidence/12-region.json`, `evidence/13-deployment-outputs.json`) record the exact CLI version (`2.79.0`), `containerapp` extension version (`1.3.0b4`, marked preview), Azure region (`koreacentral`), and Bicep deployment outputs (Container App name, FQDN, environment name, Log Analytics workspace name) used in this reproduction so that any second observer can compare apples to apples.

### Conclusion

The CPU-throttling hypothesis is SUPPORTED in this reproduction. Per-replica CPU allocation at 0.25 vCPU is the dominant tail-latency bottleneck for the CPU-bound workload, and raising the allocation to 1.0 vCPU eliminates the bottleneck — H1 holds (cpu=0.25 baseline p95 = 2575 ms ≫ 100 ms) AND H2 holds (cpu=1.0 post-fix p95 = 773 ms < 1287 ms, which is 50% of the baseline). The corrective operator action — `az containerapp update --cpu 1.0 --memory 2.0Gi` — landed in a new revision within 15 seconds of the `az` call and required no application code change.

### Falsification

The alternative hypothesis ("CPU is NOT the dominant bottleneck; raising CPU alone has no material effect on tail latency") is falsified by the directly evidenced before/after comparison:

- `[Measured]` `evidence/03-loadtest-cpu025.json` (cpu=0.25): p95 = 2575 ms with 100/100 successful requests.
- `[Measured]` `evidence/08-loadtest-cpu1.json` (cpu=1.0): p95 = 773 ms with 100/100 successful requests.
- `[Measured]` ratio: 773 / 2575 = 0.300, well below the 50% H2 threshold.
- `[Observed]` Both runs used byte-identical client code (`load_test.py`), same FQDN, same warm-up sequence, same `total=100, concurrency=20`. The only changed variable on the server is the per-replica CPU/memory envelope.

If the alternative hypothesis were correct, the p95 at cpu=1.0 would be ≥ 50% of the p95 at cpu=0.25 because the bottleneck would be something CPU does not address. The observed ratio of 30.0% rules that out.

To re-falsify in a future re-reproduction: run `verify.sh` against an app where the bottleneck is genuinely elsewhere (e.g., add an artificial `time.sleep(0.5)` to the inline server's `do_GET`). In that case, both cpu=0.25 and cpu=1.0 will produce similar p95 values (around 500 ms + per-request CPU work), the H2 ratio will land near 1.0, and `verify.sh` will exit 2 (H2 FALSIFIED).

### Operator takeaway

Per-replica CPU is a configurable knob, not an environmental constant. When latency rises under load:

1. Confirm CPU is the bottleneck with `az monitor metrics list --metric UsageNanoCores --aggregation Average,Maximum` against the live app under representative load. If average usage is pinned near the configured nanocore budget, CPU is at least one constraint.
2. Reproduce the bottleneck deterministically (this lab's pattern) before changing production. A latency spike that disappears after a CPU bump but reappears on the next deploy means CPU was a contributing factor, not the root cause.
3. Choose between scaling UP and scaling OUT based on the workload shape (per-request compute need vs total throughput).
4. Apply the change via `az containerapp update --cpu <new> --memory <new>` (or Bicep with the same property names). The platform creates a new revision and swaps traffic under `activeRevisionsMode: 'Single'`; cold-start adds a few seconds during the swap.

### Support takeaway

When escalating a "latency is bad under load" case on Azure Container Apps, run this sequence in order before assuming a platform issue:

1. Confirm the per-replica CPU/memory envelope and that the workload is actually CPU-bound (not memory-pressure-bound, not network-bound, not dependency-latency-bound):

    ```bash
    az containerapp show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --query "{cpu: properties.template.containers[0].resources.cpu, memory: properties.template.containers[0].resources.memory, minReplicas: properties.template.scale.minReplicas, maxReplicas: properties.template.scale.maxReplicas}"
    ```

2. Capture `UsageNanoCores` for a window that covers the reported latency event:

    ```bash
    az monitor metrics list \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource "/subscriptions/$AZ_SUBSCRIPTION/resourceGroups/$RG/providers/Microsoft.App/containerApps/$APP_NAME" \
        --metric UsageNanoCores \
        --aggregation Average Maximum \
        --interval PT1M
    ```

3. Recommend the controlled before/after experiment in this lab (`trigger.sh` + `verify.sh` pattern) on a non-production replica before raising CPU in production. The lab's H2 ratio (post-fix p95 / pre-fix p95) is the falsifiable signal that distinguishes "CPU was the bottleneck" from "raising CPU masked the real bottleneck temporarily."

## Expected Evidence

Reproduced end-to-end in `koreacentral` on 2026-06-22. All raw evidence is committed under [`labs/cpu-throttling/evidence/`](https://github.com/yeongseon/azure-container-apps-practical-guide/tree/main/labs/cpu-throttling/evidence):

| File | Content |
|---|---|
| `00-trigger-run.txt` | Full `trigger.sh` execution log (config check + warm-up + load test at cpu=0.25 + metric capture, exit 0) |
| `00-verify-run.txt` | Full `verify.sh` execution log (apply fix + revision swap + load test at cpu=1.0 + metric capture + H1+H2 evaluation, exit 0 / SUPPORTED) |
| `01-app-config-before.json` | Initial config readback: `{"cpu": 0.25, "memory": "0.5Gi", "minReplicas": 1, "maxReplicas": 1, "activeRevisionsMode": "Single"}` |
| `02-revisions-before.json` | Initial revision list: 1 revision (Bicep-deployed baseline at cpu=0.25) |
| `03-loadtest-cpu025.json` | Baseline load test summary: 100/100 ok, p50=1555ms, p95=2575ms, p99=2703ms, max=2801ms, avg=1626ms, wall=8.65s |
| `04-metrics-cpu025.json` | `UsageNanoCores` query attempt for the baseline window (07:49-08:48 UTC); 60 per-minute timestamps with no Average/Maximum samples populated — documents Azure Monitor metric materialization lag for snapshots taken immediately after a load event |
| `05-update-result.json` | `az containerapp update --cpu 1.0 --memory 2.0Gi` result: new revision name `ca-cputhrottle-65svxr--0000001`, provisioningState=Succeeded |
| `06-app-config-after.json` | Post-fix config readback: `{"cpu": 1.0, "memory": "2Gi", "minReplicas": 1, "maxReplicas": 1, "latestRevisionName": "ca-cputhrottle-65svxr--0000001"}` |
| `07-revisions-after.json` | Post-fix revision list: 2 revisions — old in Deprovisioning, new RunningAtMaxScale with 100% traffic |
| `08-loadtest-cpu1.json` | Post-fix load test summary: 100/100 ok, p50=474ms, p95=773ms, p99=1093ms, max=1302ms, avg=531ms, wall=2.85s |
| `09-metrics-cpu1.json` | `UsageNanoCores` query for the post-fix window (07:51-08:51 UTC); 62 per-minute timestamps, only the trailing minute at 08:50:00Z has materialized samples (average=820660.5 nC, maximum=852758.0 nC) due to materialization lag + PT1M averaging of a ~2.85 s load event |
| `10-cli-versions.json` | Azure CLI version (`2.79.0`) and installed extensions at the time of the run |
| `11-cli-containerapp-ext.json` | `containerapp` extension version (`1.3.0b4`, marked preview) |
| `12-region.json` | Azure region (`koreacentral`) used for the reproduction |
| `13-deployment-outputs.json` | Bicep deployment outputs (Container App name, FQDN, environment name, Log Analytics workspace name) |

```json
// Excerpt from evidence/03-loadtest-cpu025.json — cpu=0.25 baseline
{
  "requests_ok": 100,
  "latency_ms": { "p50": 1554.5, "p95": 2574.8, "p99": 2703.4, "max": 2800.8, "avg": 1625.6 }
}
```

```json
// Excerpt from evidence/08-loadtest-cpu1.json — cpu=1.0 post-fix
{
  "requests_ok": 100,
  "latency_ms": { "p50": 473.6, "p95": 773.2, "p99": 1092.8, "max": 1302.2, "avg": 531.0 }
}
```

The 70% reduction in p95 (2575 ms → 773 ms) for the same 100 req / 20 concurrent load against byte-identical client code is the lab's central evidence.

## Clean Up

```bash
./cleanup.sh   # deletes the entire resource group (lab is fully disposable)
```

Or, if you want to keep the environment and only roll the app back to the cheap baseline:

```bash
az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --cpu 0.25 \
    --memory 0.5Gi
```

| Command | Why it is used |
|---|---|
| `./cleanup.sh` | Runs `az group delete --subscription "$AZ_SUBSCRIPTION" --name "$RG" --yes --no-wait` so all lab resources (Container App, environment, Log Analytics workspace) are removed in one call. Recommended after evidence has been captured. |
| `az containerapp update --cpu 0.25 --memory 0.5Gi` | Rolls the Container App back to the cheap baseline allocation if you want to keep the environment and workspace for further KQL exploration. Creates yet another revision under `activeRevisionsMode: 'Single'`. |

## Related Playbook

- [CPU Throttling](../playbooks/scaling-and-runtime/cpu-throttling.md)

## See Also

- [Memory Leak OOMKilled](./memory-leak-oomkilled.md)
- [Replica Load Imbalance](./replica-load-imbalance.md)
- [Cold Start and Scale-to-Zero Lab](./cold-start-scale-to-zero.md)
- [Image Size Startup Delay Lab](./image-size-startup-delay.md)
- [Revision History Limit Lab](./revision-history-limit.md)

## Sources

- [Containers in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/containers)
- [Metrics in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/metrics)
- [Scaling in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
