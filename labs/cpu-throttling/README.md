# Lab: CPU Throttling

Reproducible lab demonstrating that per-replica CPU allocation is the dominant bottleneck for a CPU-bound HTTP workload on Azure Container Apps, and that raising the CPU allocation from 0.25 vCPU to 1.0 vCPU removes the bottleneck under the same concurrent load.

The lab provisions one Container App with a deterministic CPU-bound HTTP endpoint (`python:3.12-slim` running an inline HTTP server that computes 80 SHA-256 hashes over a 200 KiB buffer per GET), runs a 100-request / 20-concurrent load test against it at `cpu=0.25, memory=0.5Gi`, then raises the resource envelope to `cpu=1.0, memory=2.0Gi` via `az containerapp update` and re-runs the byte-identical load test. The two hypotheses under test:

1. **H1 — CPU pressure is observable at cpu=0.25.** The cpu=0.25 baseline run produces p95 latency strictly above 100 ms. If this fails, the workload was too light to reproduce the throttling effect and the run is invalid.
2. **H2 — Raising CPU to 1.0 removes the bottleneck.** The cpu=1.0 post-fix run produces p95 latency strictly below 50% of the cpu=0.25 baseline p95. If H1 holds but H2 fails, CPU is not the dominant bottleneck and the operator should investigate concurrency, network, or memory.

If both hold, the lab proves per-replica CPU allocation was the controlling variable. Operators should size CPU to the per-request work and scale OUT replicas (not just UP CPU) when total throughput is the constraint.

> **Workload design.** The lab deliberately avoids `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` because helloworld returns instantly without measurable CPU work, so any latency difference between cpu=0.25 and cpu=1.0 on helloworld is dominated by cold-start, image-pull, and scale-from-zero effects rather than steady-state CPU throttling. The inline `python:3.12-slim` server gives each GET a deterministic ~40 ms of CPU work on a full vCPU, which scales to ~160 ms under 0.25-vCPU CFS throttling — a measurable and reproducible signal isolated from cold-start.
>
> **Single-replica scope.** The lab pins `minReplicas: 1, maxReplicas: 1` so a scale-out cannot mask per-replica CPU pressure. The hypothesis under test is specifically about CPU throttling at the replica level. A separate lab (`replica-load-imbalance`) covers scale-out behavior.

## Structure

```text
labs/cpu-throttling/
├── infra/main.bicep         # LAW + Container Apps env + 1 app (python:3.12-slim inline CPU-burn HTTP server, cpu=0.25, single replica)
├── load_test.py             # Concurrent HTTP load generator with JSON output (p50/p95/p99/max/avg)
├── trigger.sh               # Phase A — Phases 1-5: config check, revisions, warm-up, load test at cpu=0.25, capture metrics
├── fix-and-capture.sh       # Phase A — Phases 6-12: apply fix (cpu=1.0, memory=2.0Gi), wait for new revision, warm-up, load test at cpu=1.0, capture metrics, evaluate H1+H2 (formerly verify.sh)
├── verify.sh                # Phase B — Evidence-pack verifier (4 gates / 15 sub-gates, no Azure calls). Pure file processor that reads only the 15 canonical Phase A files and emits 4 derived gate JSONs.
├── cleanup.sh               # Delete the resource group (async)
└── evidence/                # Captured CLI evidence
    ├── 00-trigger-run.txt                            # Full trigger.sh stdout/stderr (67 lines, Phases 1-5)
    ├── 00-verify-run.txt                             # Full fix-and-capture.sh stdout/stderr (111 lines, Phases 6-12; filename preserved across the Phase B verify.sh → fix-and-capture.sh rename for schema stability)
    ├── 01-app-config-before.json                     # Phase 1: cpu/memory/replicas before fix (expect cpu=0.25, memory=0.5Gi, minReplicas=1, maxReplicas=1, activeRevisionsMode=Single)
    ├── 02-revisions-before.json                      # Phase 2: revision list before fix (single revision --8pz2nir, runningState=RunningAtMaxScale, trafficWeight=100)
    ├── 03-loadtest-cpu025.json                       # Phase 4: load test at cpu=0.25 (baseline — p95=2574.8 ms, 100/100 ok, wall=8.65 s, started_utc=2026-06-22T08:49:38Z, finished_utc=2026-06-22T08:49:46Z)
    ├── 04-metrics-cpu025.json                        # Phase 5: UsageNanoCores metric snapshot during baseline load (60 PT1M timestamps, no populated samples due to Azure Monitor materialization lag)
    ├── 05-update-result.json                         # Phase 6: az containerapp update output (latestRevisionName=ca-cputhrottle-65svxr--0000001, provisioningState=Succeeded)
    ├── 06-app-config-after.json                      # Phase 8: cpu/memory/replicas after fix (expect cpu=1.0, memory=2Gi, minReplicas=1, maxReplicas=1)
    ├── 07-revisions-after.json                       # Phase 9: revision list after fix (2 revisions: old --8pz2nir Deprovisioning trafficWeight=0; new --0000001 RunningAtMaxScale trafficWeight=100)
    ├── 08-loadtest-cpu1.json                         # Phase 11: load test at cpu=1.0 (post-fix — p95=773.2 ms, 100/100 ok, wall=2.85 s, started_utc=2026-06-22T08:51:10Z, finished_utc=2026-06-22T08:51:13Z)
    ├── 09-metrics-cpu1.json                          # Phase 12: UsageNanoCores metric snapshot during post-fix load (60 PT1M timestamps, only trailing 08:50:00Z minute has samples)
    ├── 10-cli-versions.json                          # Azure CLI version (2.79.0) + 6 installed extensions including containerapp 1.3.0b4
    ├── 11-cli-containerapp-ext.json                  # containerapp extension metadata (preview: true, experimental: false, extensionType: whl)
    ├── 12-region.json                                # Azure region used (koreacentral)
    ├── 13-deployment-outputs.json                    # Bicep deployment outputs (containerAppFqdn, containerAppName, environmentName, logAnalyticsWorkspaceName, timestamp, duration)
    ├── 14-cohort-integrity-gate.json                 # Phase B Gate 14: 4 sub-gates (a) 15 canonical files present, (b) temporal coherence — 03 started_utc and 08 finished_utc both strict ISO-8601 UTC + monotonic + 95.0 s span within the 30-min Strong window, (c) no unexpected non-junk extras, (d) this README cross-references all 4 Phase B gate JSON filenames literally
    ├── 15-baseline-cpu-pressure-gate.json            # Phase B Gate 15 (H1): 4 sub-gates (a) baseline envelope cpu=0.25 + memory=0.5Gi + replicas=1, (b) baseline p95 > 100 ms floor (observed 2574.8 ms), (c) requests_ok ≥ 95 + requests_err == 0 (observed 100/0), (d) wall_clock > 5 s floor (observed 8.65 s)
    ├── 16-recovery-materialization-gate.json         # Phase B Gate 16 (H2): 4 sub-gates (a) recovery envelope cpu=1.0 + memory ∈ {2Gi, 2.0Gi} + replicas=1 + latestRevisionName cross-check with 05, (b) post-fix p95 < 0.5 × baseline p95 strict (observed ratio 0.3003), (c) post-fix requests_ok ≥ 95 + requests_err == 0 (observed 100/0), (d) revision state — 2 records, exactly 1 trafficWeight==100 holder, name matches 06.latestRevisionName, runningState ∈ {Running, RunningAtMaxScale} (excludes Deprovisioning)
    ├── 17-single-variable-falsification-gate.json    # Phase B Gate 17 (H3): 3 sub-gates (a) shared-keys diff between 01 and 06 = exactly {cpu, memory} (activeRevisionsMode-only-in-01 / latestRevisionName-only-in-06 documented as schema asymmetry), (b) revision lineage — old --8pz2nir in 07, new --0000001 in 07 with trafficWeight==100, new not in 02, (c) Container App identity — every revision name starts with containerAppName + "--". Carries cohort_binding_note documenting image-byte-identity is inferred (not directly evidenced).
    └── README.md                                     # Phase B evidence tour: provenance + capture timeline + claim ceiling + per-file integrity table + honest disclosure
```

## Quick Start

These commands assume the working directory is `labs/cpu-throttling/`. All `az` invocations pin `--subscription` explicitly to immunize the run against Azure CLI default-subscription drift, and the deployment is given the explicit name `main` so its outputs can be read back deterministically. Total wall-clock runtime is approximately 8-10 minutes (3 min deploy + 2 min trigger + 3 min verify including revision swap + 1 min cleanup).

```bash
cd labs/cpu-throttling/

# 1) Base inputs.
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-cputhrottle"
export LOCATION="koreacentral"

# 2) Provision the resource group and lab infra.
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

# 3) Read the deployment outputs the scripts need.
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

# 4) Run the experiment (Phase A — Live-Azure reproduction).
./trigger.sh           2>&1 | tee evidence/00-trigger-run.txt   # load test at cpu=0.25 (baseline)
./fix-and-capture.sh   2>&1 | tee evidence/00-verify-run.txt    # apply fix to cpu=1.0, wait for new revision, load test, evaluate H1+H2
./cleanup.sh                                                    # delete the resource group

# 5) (Optional) Re-verify the committed evidence pack without re-deploying (Phase B — Evidence-pack verification).
bash verify.sh                                                  # Phase B — pure file processor, 4 gates / 15 sub-gates
ls evidence/{14,15,16,17}-*-gate.json                           # emitted gate JSONs
```

## Phase A vs Phase B

This lab is delivered in two phases that share the same `labs/cpu-throttling/` directory but have distinct purposes:

- **Phase A — Live-Azure reproduction.** The original lab that deploys real infrastructure to Azure, switches the Container App to the inline `python:3.12-slim` CPU-burn HTTP server (no ACR build — the workload is small enough to inline as a Python `-c` argument in the Bicep `command` field), runs a 100-request / 20-concurrent load test against the FQDN at `cpu=0.25, memory=0.5Gi`, captures the baseline CPU pressure signal (p95=2574.8 ms, 100/100 ok), then applies the fix via `az containerapp update --cpu 1.0 --memory 2.0Gi` and captures the post-fix recovery (p95=773.2 ms, 100/100 ok, recovery ratio 0.3003). Phase A produced the canonical cohort that lives under `evidence/` (anchored on the 2026-06-22T08:49:38Z → 2026-06-22T08:51:13Z `koreacentral` traffic window, 95.0 s span end-to-end including the 15-second revision activation). Scripts: `trigger.sh` (103 lines, Phases 1-5 — initial app config + initial revision list + 5 warm-up GETs + cpu=0.25 baseline 100/20 load test + `UsageNanoCores` metric snapshot), `fix-and-capture.sh` (188 lines, Phases 6-12 — `az containerapp update --cpu 1.0 --memory 2.0Gi` + revision-activation poll + post-fix app config + post-fix revision list + 5 warm-up GETs + cpu=1.0 post-fix 100/20 load test + post-fix `UsageNanoCores` metric snapshot + H1 and H2 evaluation + literal `[CPU-THROTTLING HYPOTHESIS SUPPORTED]` marker; formerly `verify.sh`), `cleanup.sh`. Cost: well under USD $0.10 per full run.
- **Phase B — Evidence-pack verification.** A pure file processor (`verify.sh`, 1262 lines, no Azure calls) that reads only the 15 committed canonical Phase A files under `evidence/` and emits four falsifiable gate JSONs (`14-cohort-integrity-gate.json` through `17-single-variable-falsification-gate.json`). Phase B exists so a reviewer or future maintainer can re-verify the published claims without re-deploying — running `bash verify.sh` on the committed evidence reproduces the four-gate verdict on disk (15/15 sub-gates PASS on the 2026-06-22 cohort, overall Phase B verdict PASS). See [`evidence/README.md`](evidence/README.md) for the full provenance + capture timeline + claim-ceiling disclosure + per-file integrity table.

The historical pre-Phase-B `verify.sh` was the Phase A recovery script (Phases 6-12 — apply the `--cpu 1.0 --memory 2.0Gi` update, poll for the new revision to reach `runningState=RunningAtMaxScale`, warm up the new replica, re-run the byte-identical 100/20 load test, capture the post-fix `UsageNanoCores` metric, evaluate H1+H2, print the `[CPU-THROTTLING HYPOTHESIS SUPPORTED]` marker); the Phase B refactor renamed it to `fix-and-capture.sh` and assigned `verify.sh` to the new gate-emission role. The Phase A workflow above still runs the recovery + post-fix measurement, just under its new name. The captured log file `00-verify-run.txt` keeps its name for schema stability across the rename.

## What this lab demonstrates

- The Container App is provisioned by `infra/main.bicep` with `cpu: '0.25'`, `memory: '0.5Gi'`, `minReplicas: 1`, `maxReplicas: 1`. The container runs `python:3.12-slim` with an inline HTTP server that executes 80 SHA-256 iterations over a 200 KiB buffer per GET. The script and image are byte-identical across the baseline and post-fix runs; the ONLY variable that changes is the per-replica CPU/memory allocation. Gate 17 sub-gate (a) confirms the shared-keys diff on `01-app-config-before.json` and `06-app-config-after.json` is exactly `{cpu, memory}` (with `minReplicas` and `maxReplicas` unchanged at `1`).
- `trigger.sh` Phase 3 warms up the replica with 5 discarded GETs (so cold-start latency does not contaminate the baseline). Phase 4 then runs a 100-request / 20-concurrent load test against the FQDN and records p50/p95/p99/max/avg to `03-loadtest-cpu025.json`. Phase 5 captures the `UsageNanoCores` metric for the same window.
- `fix-and-capture.sh` Phase 6 applies the fix (`az containerapp update --cpu 1.0 --memory 2.0Gi`), which creates a new revision under `activeRevisionsMode: 'Single'`. Phase 7 polls until the new revision reports `runningState=RunningAtMaxScale` (max 5 min; observed transition: `08:50:45Z runningState=Activating` → `08:51:00Z runningState=RunningAtMaxScale`, 15 s activation latency). Phase 10 warms up the new replica, Phase 11 re-runs the byte-identical 100/20 load test, Phase 12 captures the post-fix `UsageNanoCores` metric.
- The pass/fail logic encodes two outcomes plus two invalid-run guards:
    - **H1 PASS + H2 PASS** ⇒ the CPU-throttling hypothesis is SUPPORTED. Exit 0. `fix-and-capture.sh` prints the literal `[CPU-THROTTLING HYPOTHESIS SUPPORTED]` marker.
    - **H2 FALSIFIED** (cpu=1.0 p95 is NOT < 50% of cpu=0.25 p95) ⇒ CPU is not the dominant bottleneck. Investigate concurrency/network/memory. Exit 2.
    - **H1 FALSIFIED** (cpu=0.25 p95 < 100 ms) or low success count ⇒ INVALID RUN. The workload was too light or network errors corrupted the measurement. Re-run. Exit 1.

> **Metric capture timing — known limitation.** Phase 5 and Phase 12 each query `UsageNanoCores` immediately after their load test completes. The captured evidence files (`04-metrics-cpu025.json`, `09-metrics-cpu1.json`) therefore document a real Azure Monitor behavior: per-minute aggregated metrics typically materialize 1-3 minutes after the event, and `PT1M` aggregation further averages a short-duration load (~3-9 s) across a full minute. In the reproduction captured here, `04` has no populated Average/Maximum samples and `09` has only one trailing minute with samples (`average=820660.5 nC`, well below peak instantaneous usage). The **load-test latency** in `03-loadtest-cpu025.json` and `08-loadtest-cpu1.json` is therefore the lab's primary evidence; the metric snapshots are kept as an honest record of the timing constraint. Phase B Gates 15, 16, and 17 anchor on the load-test latency and on the app-config / revisions captures (`01`, `02`, `06`, `07`), NOT on the metric values, so the short-event averaging behavior does not weaken the falsification. For a production diagnosis, wait 3-5 minutes after the load event before querying `UsageNanoCores`, and prefer the `Maximum` aggregation over `Average` for short-duration events.

## Why this workload (and not helloworld)

The repository's other labs use `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` because it is the cheapest path to a working Container App. For CPU throttling specifically, helloworld is the wrong choice:

- Helloworld returns immediately without measurable CPU work, so the difference between cpu=0.25 and cpu=1.0 is dominated by cold-start (~6 s spike on first request), image-pull (~1-2 s), and TLS/TCP setup (~50-100 ms) rather than steady-state CPU throttling.
- Operators reading the evidence would mis-attribute the latency difference to CPU when it is actually startup variance.

The inline `python:3.12-slim` server gives each GET a deterministic ~40 ms of CPU work on a full vCPU (80 SHA-256 hashes over 200 KiB, measured on Azure Container Apps Consumption profile). Under Linux CFS throttling at 0.25 vCPU, that same work takes ~160 ms minimum per request, plus queuing time when concurrent requests share the throttled CPU budget. The signal is large enough to dwarf network jitter and isolated from cold-start (because the lab warms up the replica before measuring).

## Cost notes

- Resources provisioned: 1 Log Analytics workspace (PerGB), 1 Container Apps Environment (Consumption), 1 Container App with `minReplicas: 1`, `maxReplicas: 1` — first 5-7 min at 0.25 vCPU + 0.5 GiB, last 3-5 min at 1.0 vCPU + 2.0 GiB.
- No ACR (uses public Docker Hub image), no Application Insights, no public IP, no private endpoint.
- With `minReplicas: 1`, the replica stays warm throughout the lab (this is intentional — it removes cold-start as a confounding variable). The cost floor is small but non-zero.
- Total cost for one end-to-end lab run is well under USD $0.10. Container Apps Consumption pricing as of this lab: $0.000024/vCPU-sec + $0.000003/GiB-sec.
- Run `./cleanup.sh` immediately after capturing evidence to keep the bill near zero.

## What to record in your evidence write-up

When you ship this lab's evidence into a docs PR or a support ticket, ALWAYS record the following alongside the JSON captures:

- **Azure region** (e.g., `koreacentral`) — captured automatically in `12-region.json`.
- **Azure CLI version** and **`containerapp` extension version** — captured automatically in `10-cli-versions.json` and `11-cli-containerapp-ext.json`.
- **Date of the run in UTC** — visible in the first line of `00-trigger-run.txt` and `00-verify-run.txt`, plus the `started_utc` / `finished_utc` fields of `03-loadtest-cpu025.json` and `08-loadtest-cpu1.json`.
- **The exit code of `trigger.sh`, `fix-and-capture.sh`, and Phase B `verify.sh`** (0 = hypothesis supported / all gates PASS, 1 = invalid run / verifier infra error, 2 = falsified / any gate FAIL).
- **The before-fix and after-fix `template.containers[0].resources` blocks** (`01-app-config-before.json` and `06-app-config-after.json`) so that the resource-envelope diff (the single experimental variable) can be inspected directly. Phase B Gate 17 sub-gate (a) confirms the shared-keys diff equals exactly `{cpu, memory}`.
- **The revision pair lifecycle** (`02-revisions-before.json` and `07-revisions-after.json`) showing the old `--8pz2nir` revision in `02` (active=true, runningState=RunningAtMaxScale, trafficWeight=100) becoming `--8pz2nir` (active=true, runningState=Deprovisioning, trafficWeight=0) plus the new `--0000001` (active=true, runningState=RunningAtMaxScale, trafficWeight=100) in `07` — Phase B Gate 16 sub-gate (d) and Gate 17 sub-gate (b) anchor on this lineage with explicit `trafficWeight==100 AND runningState ∈ {Running, RunningAtMaxScale}` predicates (NOT `active==true`) to exclude the tearing-down old revision.

The exact CPU work per request (80 SHA-256 iterations over 200 KiB) is a deliberate choice that produces ~40 ms of work on a full vCPU at the time of this lab's reproduction. Future CPU generations or Container Apps platform updates may shift this baseline, which is why every run captures `10-cli-versions.json` and `12-region.json` alongside the load-test JSON.

## Operator takeaway

Per-replica CPU is a configurable knob, not an environmental constant. When latency rises under load:

1. Confirm CPU is the bottleneck with `az monitor metrics list --metric UsageNanoCores --aggregation Average,Maximum` — if average usage is pinned near the configured limit, CPU is at least one constraint.
2. Choose between scaling UP (raise per-replica CPU when each request needs more compute) and scaling OUT (raise `maxReplicas` and tune scale rules when total throughput is the constraint). The two are not interchangeable.
3. If a single request is the unit of work that needs the headroom, scale UP. If the workload is many small independent requests competing for a shared budget, scale OUT.
4. Use `az containerapp update --cpu <new> --memory <new>` to change the per-replica envelope. The platform creates a new revision and swaps traffic under `activeRevisionsMode: 'Single'`; cold-start adds a few seconds during the swap.
