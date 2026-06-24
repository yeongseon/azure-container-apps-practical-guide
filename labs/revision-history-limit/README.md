# Lab: Revision History Limit

Reproducible **bounded-observation** lab for the Azure Container Apps preview setting `maxInactiveRevisions` (CLI flag: `--max-inactive-revisions`, alias `--revision-history-limit`).

The lab provisions one Container App with `maxInactiveRevisions: 2`, forces a burst of 10 env-var-only revision updates, and then samples the live revision list at three fixed offsets after the burst (**t+0, t+5m, t+15m**). The lab does NOT assume pruning is prompt — it tests two things only:

1. **H1 — Setting is persisted.** After the burst and the 15-minute observation window, `properties.configuration.maxInactiveRevisions` still reads `2`.
2. **H2 — Pruning is NOT prompt within the bounded window.** At t+15m the inactive revision count is still greater than the configured limit of 2.

If both hold, the lab proves that `maxInactiveRevisions` is honored as a *target*, not as a short-window cleanup SLA. Operators should not rely on this preview setting for deterministic, time-bounded cleanup; for that, use explicit lifecycle commands such as `az containerapp revision deactivate`.

> **Preview feature.** `maxInactiveRevisions` is documented as preview in Microsoft Learn ([Container Apps revisions](https://learn.microsoft.com/en-us/azure/container-apps/revisions)). The default cap is 100 inactive revisions (not 10). The pruning interval is not documented anywhere — there is no SLA.
>
> **Property name note.** In the `Microsoft.App/containerApps@2023-05-01` schema this property is `properties.configuration.maxInactiveRevisions`. The Azure CLI exposes the same backing field via the preview flag `--max-inactive-revisions` (preferred, requires `az extension add --name containerapp --upgrade --allow-preview true`) and the older alias `--revision-history-limit`. This lab sets the value in **Bicep only** and never mutates it via the CLI, so the difference does not affect this lab's evidence.

## Structure

```text
labs/revision-history-limit/
├── infra/main.bicep      # LAW + Container Apps env + 1 app (helloworld image, maxInactiveRevisions=2, minReplicas=0)
├── trigger.sh            # Phase A — Phases 1-4: config check, initial revisions, burst 10 updates, capture t+0
├── capture-window.sh     # Phase A — Phases 5-7: capture at t+5m, t+15m, config readback at t+15m (formerly verify.sh)
├── verify.sh             # Phase B — Evidence-pack verifier (4 gates / 12 sub-gates, no Azure calls)
├── cleanup.sh            # Delete the resource group
└── evidence/             # Captured CLI evidence
    ├── 00-trigger-run.txt           # Full trigger.sh stdout/stderr
    ├── 00-verify-run.txt            # Full capture-window.sh stdout/stderr (filename preserved for schema stability across the Phase B verify.sh → capture-window.sh rename)
    ├── 01-app-config-before.json    # Phase 1: config read before burst (expect maxInactiveRevisions=2)
    ├── 02-revisions-initial.json    # Phase 2: revision list before burst
    ├── 03-revisions-t0.json         # Phase 4: revision list immediately after burst
    ├── 04-revisions-t5m.json        # Phase 5: revision list at burst+5m
    ├── 05-revisions-t15m.json       # Phase 6: revision list at burst+15m (primary hypothesis check)
    ├── 06-app-config-t15m.json      # Phase 7: config readback at t+15m (prove setting persisted)
    ├── burst-completed-epoch.txt    # Unix epoch when the 10-update burst finished
    └── burst-completed-iso.txt      # Same timestamp in ISO 8601 UTC (human-readable)
```

## Quick Start

These commands assume the working directory is `labs/revision-history-limit/`. All `az` invocations pin `--subscription` explicitly to immunize the run against Azure CLI default-subscription drift, and the deployment is given the explicit name `main` so its outputs can be read back deterministically. Total wall-clock runtime is approximately 18-20 minutes (3 min deploy + 2 min trigger + 15 min verify wait).

```bash
cd labs/revision-history-limit/

# 1) Base inputs.
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-revhist"
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
    --parameters baseName="revhist"

# 3) Read the deployment outputs the scripts need.
export APP_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.containerAppName.value" \
    --output tsv)

# 4) Run the bounded-observation experiment.
./trigger.sh           # Phase A — config check + initial revisions + burst 10 updates + capture t+0
./capture-window.sh    # Phase A — wait to t+5m + wait to t+15m + config readback at t+15m
./cleanup.sh           # delete the resource group

# 5) (Optional) Re-verify the committed evidence pack without re-deploying.
bash verify.sh                                       # Phase B — pure file processor, 4 gates / 12 sub-gates
ls evidence/{20,21,22,23}-*-gate.json                # emitted gate JSONs
```

## Phase A vs Phase B

This lab is delivered in two phases that share the same `labs/revision-history-limit/` directory but have distinct purposes:

- **Phase A — Live-Azure reproduction.** The original lab that deploys real infrastructure to Azure, runs the 10-update env-var burst, and samples the live revision list at t+0, t+5m, and t+15m. Phase A produced the canonical cohort that lives under `evidence/` (anchored on `burst-20260622-080146`). Scripts: `trigger.sh` (Phases 1-4), `capture-window.sh` (Phases 5-7, formerly `verify.sh`), `cleanup.sh`. Cost: well under USD $0.05 per full run.
- **Phase B — Evidence-pack verification.** A pure file processor (`verify.sh`, no Azure calls) that reads the committed canonical cohort from `evidence/` and emits four falsifiable gate JSONs (`20-cohort-integrity-gate.json` through `23-bounded-window-non-pruning-gate.json`). Phase B exists so a reviewer or future maintainer can re-verify the published claims without re-deploying — running `bash verify.sh` on the committed evidence reproduces the four-gate verdict on disk. See [`evidence/README.md`](evidence/README.md) for the full provenance + capture timeline + claim-ceiling disclosure + per-file integrity table.

The historical pre-Phase-B `verify.sh` was the Phase A observation-window sampler (Phases 5-7); the Phase B refactor renamed it to `capture-window.sh` and assigned `verify.sh` to the new gate-emission role. The Phase A workflow above still runs the observation-window sampling, just under its new name. The captured log file `00-verify-run.txt` keeps its name for schema stability across the rename.

## What this lab demonstrates

- The Container App is provisioned by `infra/main.bicep` with `properties.configuration.maxInactiveRevisions = 2` and the public placeholder image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`. The lab never switches off this image; every revision created by `trigger.sh` keeps the same image and only changes the `REV` env var, so the only experimental variable is the inactive-revision retention limit.
- `trigger.sh` Phase 3 issues 10 sequential `az containerapp update --set-env-vars REV=<nonce>-N` calls (N=1..10). Each update creates a NEW revision (the env var change is enough to invalidate the previous template hash) and makes it the active revision under `activeRevisionsMode: 'Single'`. The previously active revision drops to Inactive. The nonce is a per-run UTC timestamp, so reruns produce distinct env var values and reliably create new revisions even after a fresh deploy.
- `capture-window.sh` Phases 5-6 sample the revision list at fixed offsets after the burst (t+5m and t+15m). Phase 7 re-reads the configuration to prove the value was not mutated mid-run.
- The pass/fail logic encodes two outcomes plus two invalid-run guards:
    - **H1 PASS + H2 PASS** ⇒ the bounded-observation hypothesis is SUPPORTED (the preview setting is real but pruning is not prompt within 15 min). Exit 0.
    - **H2 FALSIFIED** ⇒ pruning IS prompt within 15 min. Update the lab and the playbook to reflect the new platform behavior. Exit 2.
    - **H1 FALSIFIED** (config did not persist) or burst did not create enough revisions ⇒ INVALID RUN. Re-deploy and re-run. Exit 1.

## Why `maxInactiveRevisions=2` instead of the default `100`

`maxInactiveRevisions` defaults to 100 (documented on [Microsoft Learn](https://learn.microsoft.com/en-us/azure/container-apps/revisions)). With the default, an experiment would need 101+ revisions before pruning becomes observable, which inflates the lab cost and runtime for no analytical benefit. Setting the limit to 2 from the start makes the *target* value observable after just a few revisions — and lets the lab cleanly demonstrate the gap between the configured target and the live inactive count during the 15-minute observation window.

## Why the experiment uses env-var-only updates

Microsoft Learn documents that any change to the template — including environment variables — triggers a new revision. Using `--set-env-vars REV=<nonce>-N` is the cheapest possible way to create a NEW revision deterministically:

- No image rebuild required.
- No image pull from a remote registry.
- No actual workload change inside the container.
- The container restarts and reports a new revision suffix within seconds.

This lets us isolate the experimental variable (the inactive-revision retention limit) without any other moving parts.

## Cost notes

- Resources provisioned: 1 Log Analytics workspace (PerGB), 1 Container Apps Environment (Consumption), 1 Container App with `minReplicas: 0`, `maxReplicas: 1`, `0.25 vCPU`, `0.5 Gi` memory.
- No ACR, no Application Insights, no public IP, no private endpoint.
- With `minReplicas: 0`, the active revision scales to zero between observation windows, so the only ongoing cost is the Log Analytics workspace (which charges per-GB on ingestion only).
- Total cost for one end-to-end lab run is well under USD $0.05.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.

## What to record in your evidence write-up

When you ship this lab's evidence into a docs PR or a support ticket, ALWAYS record the following alongside the JSON captures:

- **Azure region** (e.g., `koreacentral`).
- **Azure CLI version** and **`containerapp` extension version** (`az version`, `az extension list --query "[?name=='containerapp']"`).
- **Date of the run in UTC** (also visible in `burst-completed-iso.txt`).
- **The exit code of `trigger.sh` and `capture-window.sh`** (0 = hypothesis supported, 1 = invalid run, 2 = falsified).

The pruning interval is not documented in Microsoft Learn and is not part of any published SLA, so reproducibility of this lab's conclusions depends on recording when and where the measurement was taken. A second observer in a different region or after a platform update may see different behavior.

## Operator takeaway

Do not rely on `maxInactiveRevisions` (preview) as a short-window cleanup mechanism. The setting represents a *target steady-state cap*, not a 15-minute SLA. When determinism matters (compliance review windows, post-incident cleanup, automated audits), use explicit lifecycle commands such as `az containerapp revision deactivate --name <revision-name>` so cleanup is observable in your own audit trail rather than waiting on the platform's asynchronous reconciliation loop.
