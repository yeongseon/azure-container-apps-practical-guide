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
├── infra/main.bicep      # LAW + Container Apps env + 1 app (python:3.12-slim inline CPU-burn HTTP server, cpu=0.25, single replica)
├── load_test.py          # Concurrent HTTP load generator with JSON output (p50/p95/p99/max/avg)
├── trigger.sh            # Phases 1-5: config check, revisions, warm-up, load test at cpu=0.25, capture metrics
├── verify.sh             # Phases 6-12: apply fix, wait for new revision, warm-up, load test at cpu=1.0, capture metrics, evaluate H1+H2
├── cleanup.sh            # Delete the resource group (async)
└── evidence/             # Captured CLI evidence
    ├── 00-trigger-run.txt           # Full trigger.sh stdout/stderr
    ├── 00-verify-run.txt            # Full verify.sh stdout/stderr
    ├── 01-app-config-before.json    # Phase 1: cpu/memory/replicas before fix (expect cpu=0.25)
    ├── 02-revisions-before.json     # Phase 2: revision list before fix
    ├── 03-loadtest-cpu025.json      # Phase 4: load test at cpu=0.25 (baseline)
    ├── 04-metrics-cpu025.json       # Phase 5: UsageNanoCores metric snapshot during baseline load
    ├── 05-update-result.json        # Phase 6: az containerapp update output (new revision name)
    ├── 06-app-config-after.json     # Phase 8: cpu/memory/replicas after fix (expect cpu=1.0)
    ├── 07-revisions-after.json      # Phase 9: revision list after fix
    ├── 08-loadtest-cpu1.json        # Phase 11: load test at cpu=1.0 (post-fix)
    ├── 09-metrics-cpu1.json         # Phase 12: UsageNanoCores metric snapshot during post-fix load
    ├── 10-cli-versions.json         # Azure CLI version
    ├── 11-cli-containerapp-ext.json # containerapp extension version
    ├── 12-region.json               # Azure region used
    └── 13-deployment-outputs.json   # Bicep deployment outputs
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

# 4) Run the experiment.
./trigger.sh   # load test at cpu=0.25 (baseline)
./verify.sh    # apply fix to cpu=1.0, wait for new revision, load test, evaluate H1+H2
./cleanup.sh   # delete the resource group
```

## What this lab demonstrates

- The Container App is provisioned by `infra/main.bicep` with `cpu: '0.25'`, `memory: '0.5Gi'`, `minReplicas: 1`, `maxReplicas: 1`. The container runs `python:3.12-slim` with an inline HTTP server that executes 80 SHA-256 iterations over a 200 KiB buffer per GET. The script and image are byte-identical across the baseline and post-fix runs; the ONLY variable that changes is the per-replica CPU/memory allocation.
- `trigger.sh` Phase 3 warms up the replica with 5 discarded GETs (so cold-start latency does not contaminate the baseline). Phase 4 then runs a 100-request / 20-concurrent load test against the FQDN and records p50/p95/p99/max/avg to `03-loadtest-cpu025.json`. Phase 5 captures the `UsageNanoCores` metric for the same window.
- `verify.sh` Phase 6 applies the fix (`az containerapp update --cpu 1.0 --memory 2.0Gi`), which creates a new revision under `activeRevisionsMode: 'Single'`. Phase 7 polls until the new revision reports `runningState=Running` (max 5 min). Phase 10 warms up the new replica, Phase 11 re-runs the byte-identical 100/20 load test, Phase 12 captures the post-fix `UsageNanoCores` metric.
- The pass/fail logic encodes two outcomes plus two invalid-run guards:
    - **H1 PASS + H2 PASS** ⇒ the CPU-throttling hypothesis is SUPPORTED. Exit 0.
    - **H2 FALSIFIED** (cpu=1.0 p95 is NOT < 50% of cpu=0.25 p95) ⇒ CPU is not the dominant bottleneck. Investigate concurrency/network/memory. Exit 2.
    - **H1 FALSIFIED** (cpu=0.25 p95 < 100 ms) or low success count ⇒ INVALID RUN. The workload was too light or network errors corrupted the measurement. Re-run. Exit 1.

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
- **Date of the run in UTC** — visible in the first line of `00-trigger-run.txt` and `00-verify-run.txt`.
- **The exit code of `trigger.sh` and `verify.sh`** (0 = hypothesis supported, 1 = invalid run, 2 = falsified).

The exact CPU work per request (80 SHA-256 iterations over 200 KiB) is a deliberate choice that produces ~40 ms of work on a full vCPU at the time of this lab's reproduction. Future CPU generations or Container Apps platform updates may shift this baseline, which is why every run captures `10-cli-versions.json` and `12-region.json` alongside the load-test JSON.

## Operator takeaway

Per-replica CPU is a configurable knob, not an environmental constant. When latency rises under load:

1. Confirm CPU is the bottleneck with `az monitor metrics list --metric UsageNanoCores --aggregation Average,Maximum` — if average usage is pinned near the configured limit, CPU is at least one constraint.
2. Choose between scaling UP (raise per-replica CPU when each request needs more compute) and scaling OUT (raise `maxReplicas` and tune scale rules when total throughput is the constraint). The two are not interchangeable.
3. If a single request is the unit of work that needs the headroom, scale UP. If the workload is many small independent requests competing for a shared budget, scale OUT.
4. Use `az containerapp update --cpu <new> --memory <new>` to change the per-replica envelope. The platform creates a new revision and swaps traffic under `activeRevisionsMode: 'Single'`; cold-start adds a few seconds during the swap.
