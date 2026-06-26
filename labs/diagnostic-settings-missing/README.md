# Lab: Diagnostic Settings Missing

Reproducible **falsification** lab for the Azure Container Apps environment-level setting `properties.appLogsConfiguration` (CLI flag set: `az containerapp env update --logs-destination`, `--logs-workspace-id`, `--logs-workspace-key`).

The lab provisions one Container App in an environment that is intentionally created WITHOUT `appLogsConfiguration` populated (the property is simply omitted from the Bicep). This lab observed (2026-06-22 reproduction in `koreacentral`) that omitting the property leaves the live environment at `destination: null`. The lab then drives traffic, waits for the documented log ingestion window, and verifies that neither `ContainerAppConsoleLogs_CL` nor `ContainerAppSystemLogs_CL` receive a single row — proving that without the environment-level setting, no log path exists from this environment to the workspace, regardless of any app-level configuration. After the baseline is captured, the same environment is mutated via `az containerapp env update --logs-destination log-analytics ...`, a new revision is forced (so the platform has a fresh `RevisionReady` event to emit), and the same KQL is rerun. Both tables now return rows — proving the environment setting is the controlling variable.

The lab tests two hypotheses:

1. **H1 — Baseline is silent.** With `properties.appLogsConfiguration.destination = null` on the Container Apps environment, both `ContainerAppConsoleLogs_CL` and `ContainerAppSystemLogs_CL` return 0 rows for the app, even after 5 minutes of ingestion wait following request traffic.
2. **H2 — Fix restores ingestion.** After `az containerapp env update --logs-destination log-analytics --logs-workspace-id <customerId> --logs-workspace-key <sharedKey>`, plus a forced new revision and a second 5-minute ingestion wait, both tables return ≥ 1 row.

If both hold, the lab proves that the environment-level `appLogsConfiguration` is the single controlling variable for Log Analytics ingestion from Container Apps. The application image, the ingress configuration, the workspace itself, and the KQL queries are all held constant across the baseline and the post-fix runs; the only experimental variable is the environment setting.

> **Why the environment setting (not the app setting) is the controlling variable.** Microsoft Learn documents that Container Apps log routing is configured at the **environment** scope, not the **app** scope ([Log options in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/log-options) and [Logging in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash)). Every Container App inside an environment inherits the environment's `appLogsConfiguration`; there is no per-app override. What Learn does NOT directly document is the operational consequence of omitting `appLogsConfiguration` from IaC. This lab observed (2026-06-22 reproduction in `koreacentral`) that omitting the property leaves the live environment at `destination: null` and that under that state every app inside the environment is silent in Log Analytics until the environment is updated. The lab is a falsification proof for that observation.

## Structure

```text
labs/diagnostic-settings-missing/
├── infra/main.bicep      # LAW + Container Apps env (NO appLogsConfiguration) + 1 helloworld app (minReplicas=1, maxReplicas=1)
├── trigger.sh            # Phase A — Phases 1-5: env config check, app config check, 10 HTTP requests, 5m wait, KQL baseline (expect 0 rows)
├── fix-and-capture.sh    # Phase A — Phases 6-12: env update, env config readback, force new revision, wait Running, 10 HTTP requests, 5m wait, KQL post-fix (expect ≥1 row) (renamed from verify.sh)
├── verify.sh             # Phase B — Evidence-pack verifier (4 gates / 15 sub-gates, no Azure calls). Reads only committed evidence and emits 4 derived gate JSONs.
├── cleanup.sh            # Delete the resource group
└── evidence/             # Captured CLI evidence
    ├── 00-trigger-run.txt          # Full trigger.sh stdout/stderr
    ├── 00-verify-run.txt           # Full fix-and-capture.sh stdout/stderr (filename preserved across the Phase B rename)
    ├── 01-env-config-before.json   # Phase 1: env appLogsConfiguration before fix (expect destination=null)
    ├── 02-app-config-before.json   # Phase 2: app config + active revision before fix
    ├── 03-curl-before.json         # Phase 3: 10 HTTP request results to baseline revision
    ├── 04-kql-before.json          # Phase 5: KQL on both *_CL tables (expect 0 rows)
    ├── 05-env-update-result.json   # Phase 6: az containerapp env update result
    ├── 06-env-config-after.json    # Phase 7: env appLogsConfiguration after fix (expect destination=log-analytics)
    ├── 07-revisions-after.json     # Phase 9: revision list after FIXAPPLIED env-var update
    ├── 08-curl-after.json          # Phase 10: 10 HTTP request results to post-fix revision
    ├── 09-kql-after.json           # Phase 12: KQL on both *_CL tables (expect ≥1 row)
    ├── 10-cli-versions.json        # Post-run: `az version`
    ├── 11-cli-containerapp-ext.json # Post-run: containerapp extension version
    ├── 12-region.json              # Post-run: deployment region
    ├── 13-deployment-outputs.json  # Post-run: full deployment outputs
    ├── 14-cohort-integrity-gate.json # Phase B Gate 14: Strong/Fallback cohort integrity
    ├── 15-baseline-silent-gate.json # Phase B Gate 15 (H1): null env config + zero-row baseline
    ├── 16-post-fix-populated-gate.json # Phase B Gate 16 (H2): destination restored + populated tables
    ├── 17-single-variable-falsification-gate.json # Phase B Gate 17 (H3): bounded env-config diff + revision lineage
    └── README.md                   # Phase B evidence tour: timeline, gate descriptions, disclosures, file index
```

## Quick Start

These commands assume the working directory is `labs/diagnostic-settings-missing/`. All `az` invocations pin `--subscription` explicitly to immunize the run against Azure CLI default-subscription drift, and the deployment is given the explicit name `main` so its outputs can be read back deterministically. Total wall-clock runtime is approximately 25 minutes (3 min deploy + 7 min trigger including 5 min ingestion wait + 13 min fix-and-capture including 5 min ingestion wait + 1 min offline Phase B verify + 1 min cleanup initiation).

```bash
cd labs/diagnostic-settings-missing/

# 1) Base inputs.
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-diagsetting"
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
    --parameters baseName="diagsetting"

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
export ENV_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.environmentName.value" \
    --output tsv)
export WORKSPACE_CUSTOMER_ID=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.logAnalyticsCustomerId.value" \
    --output tsv)
export WORKSPACE_RESOURCE_ID=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.logAnalyticsWorkspaceId.value" \
    --output tsv)

# 4) Run Phase A (capture the live Azure evidence cohort).
./trigger.sh            2>&1 | tee evidence/00-trigger-run.txt   # env config + app config + 10 requests + 5m wait + KQL (expect 0 rows)
./fix-and-capture.sh    2>&1 | tee evidence/00-verify-run.txt    # env update + force new revision + 10 requests + 5m wait + KQL (expect ≥1 row)

# 5) Run Phase B (offline evidence-pack verification) and clean up.
bash verify.sh                                                # emits Gate 14/15/16/17 JSONs; expect 15/15 PASS
./cleanup.sh                                                  # delete the resource group
```

## Phase A vs Phase B

This lab now splits the live-Azure reproduction from the offline evidence-pack verification:

- **Phase A — Live Azure reproduction.** `trigger.sh` captures the null-destination baseline, then `fix-and-capture.sh` applies the environment-level fix, forces a new revision, waits for the new revision to run, drives post-fix traffic, and captures the populated KQL result. The historical Phase A script name was `verify.sh`; it was renamed to `fix-and-capture.sh` so `verify.sh` could become the offline verifier. The captured log file remains `00-verify-run.txt` for schema stability.
- **Phase B — Offline evidence-pack verification.** `verify.sh` is now a pure file processor that reads the committed evidence cohort under `evidence/`, emits four derived gate JSONs, and exits 0 only when all 15 sub-gates pass. See [`evidence/README.md`](evidence/README.md) for the full evidence-pack tour.

## What this lab demonstrates

- The Container Apps environment is provisioned by `infra/main.bicep` with `properties: {}` — the `appLogsConfiguration` property is intentionally omitted. The live environment therefore reports `destination: null` and `logAnalyticsConfiguration: null` on its first GET, which is the baseline state the lab needs.
- The Container App uses the public placeholder image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` because this lab does not measure app behavior — it measures whether the environment routes platform/console logs to Log Analytics at all. The image is identical across the baseline and the post-fix runs.
- `minReplicas: 1, maxReplicas: 1` is used so that the platform reliably emits `RevisionReady` and `ContainerStarted` system events into `ContainerAppSystemLogs_CL` on both the baseline revision and the post-fix revision, with no scale-to-zero confounder.
- `trigger.sh` Phase 3 issues 10 sequential HTTPS requests against the public FQDN, then Phase 4 waits 300 seconds for any potential log ingestion lag, then Phase 5 runs the KQL on both `ContainerAppConsoleLogs_CL` and `ContainerAppSystemLogs_CL`. If either table returns rows, H1 is FALSIFIED — the lab exits 1 (INVALID RUN) because the baseline state did not hold.
- `fix-and-capture.sh` Phase 6 calls `az containerapp env update --logs-destination log-analytics --logs-workspace-id <customerId> --logs-workspace-key <sharedKey>`. The shared key is read from `az monitor log-analytics workspace get-shared-keys` at script runtime — it is never persisted to evidence files and never logged to stdout.
- Phase 8 then forces a new revision by setting an env var `FIXAPPLIED=<UTC nonce>` on the app. Any env var change is sufficient to invalidate the previous template hash and create a new revision under `activeRevisionsMode: 'Single'`. This guarantees the platform emits a fresh `RevisionReady` event into `ContainerAppSystemLogs_CL` AFTER the environment was updated.
- Phase 9 polls the revision list until `runningState` is `Running` or `RunningAtMaxScale` (or 30 attempts × 10 s = 5 min ceiling).
- Phase 10 sends another 10 requests against the new revision. Phase 11 waits 300 seconds for ingestion. Phase 12 re-runs the same KQL. Both tables must now report ≥ 1 row, otherwise H2 is FALSIFIED.
- The pass/fail logic now has separate Phase A and Phase B semantics:
    - **Phase A (`fix-and-capture.sh`)** — **H1 PASS + H2 PASS** ⇒ falsification hypothesis SUPPORTED. Exit 0. **H2 FALSIFIED** ⇒ exit 2. **H1 FALSIFIED** ⇒ INVALID RUN, exit 1.
    - **Phase B (`verify.sh`)** — 4 derived gates / 15 sub-gates over the committed evidence pack. Exit 0 only when every sub-gate passes; otherwise exit 1.

## Why the lab tests both `ContainerAppConsoleLogs_CL` AND `ContainerAppSystemLogs_CL`

The two tables represent two distinct log paths:

- **`ContainerAppConsoleLogs_CL`** carries stdout/stderr from the application container. The `mcr.microsoft.com/azuredocs/containerapps-helloworld` image emits an Nginx access log line on each request, so in this reproduction (2026-06-22, `koreacentral`) 10 HTTP requests produced at least 1 row in this table once the environment was properly configured. The H2 gate is `≥ 1 row`; the absolute row count varies with image stdout volume, request pattern, and ingestion timing, so the gate intentionally does not assume a row-per-request correspondence.
- **`ContainerAppSystemLogs_CL`** carries platform-emitted events such as `ContainerStarted`, `RevisionReady`, `ContainerExited`. These are emitted by the Container Apps platform itself, not by the application, so they fire even on revisions that never receive a request.

Both tables share the same `appLogsConfiguration` routing, so they must both be silent at baseline AND both be populated post-fix. If only one of the two tables is populated, that asymmetry would point to a different (and undocumented) ingestion path, and the lab would fail H2 with an investigation flag.

## Why the experiment uses the `helloworld` image

This lab measures environment-level log routing, not application behavior. Using the public Microsoft-hosted `containerapps-helloworld` image avoids the confounders that would come with a custom image:

- No ACR provisioning, no ACR pull authentication failure path.
- No custom logging library, no log level configuration, no application bug that could swallow a log line.
- The image is the same across the baseline and the post-fix runs, so the only experimental variable is the environment setting.

## Cost notes

- Resources provisioned: 1 Log Analytics workspace (PerGB, 30-day retention), 1 Container Apps Environment (Consumption), 1 Container App with `minReplicas: 1`, `maxReplicas: 1`, `0.25 vCPU`, `0.5 Gi` memory.
- No ACR, no Application Insights, no public IP, no private endpoint, no VNet integration.
- With `minReplicas: 1`, the app is billed continuously while it exists, but the lab is designed to run end-to-end and clean up in under 25 minutes. The Container Apps Consumption plan at 0.25 vCPU + 0.5 Gi for 25 minutes costs well under USD $0.01; the Log Analytics ingestion of a few KB of platform logs is similarly negligible.
- Total cost for one end-to-end lab run is well under USD $0.05.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.

## What to record in your evidence write-up

When you ship this lab's evidence into a docs PR or a support ticket, ALWAYS record the following alongside the JSON captures:

- **Azure region** (e.g., `koreacentral`). Captured to `evidence/12-region.json`.
- **Azure CLI version** and **`containerapp` extension version** (`az version`, `az extension list --query "[?name=='containerapp']"`). Captured to `evidence/10-cli-versions.json` and `evidence/11-cli-containerapp-ext.json`.
- **Date of the run in UTC** (visible at the top of `00-trigger-run.txt` and `00-verify-run.txt`).
- **The exit code of `trigger.sh`, `fix-and-capture.sh`, and `verify.sh`** (0 = Phase A supported or Phase B all gates PASS, 1 = invalid run or Phase B gate failure, 2 = Phase A H2 falsified).
- **Full deployment outputs** so the reader can reproduce the LAW guid, env name, app name, FQDN. Captured to `evidence/13-deployment-outputs.json`.

The full evidence-pack tour and the derived gate descriptions live in [`evidence/README.md`](evidence/README.md).

The log ingestion lag between event emission and KQL queryability in `*_CL` tables is not documented as a strict SLA. This lab uses a 5-minute wait window, which has been observed to be sufficient for `ContainerAppConsoleLogs_CL` and `ContainerAppSystemLogs_CL` in this reproduction, but a slower region or a busier workspace may need a longer wait. Recording the wait window and the post-wait row counts is critical for reproducibility.

## Operator takeaway

This lab observed (2026-06-22 reproduction in `koreacentral`) that if you provision a Container Apps environment via Bicep, ARM, or Terraform and you omit `appLogsConfiguration`, the live environment lands at `destination: null` and the entire environment is silent in Log Analytics — no app inside that environment emits a single row into `ContainerAppConsoleLogs_CL` or `ContainerAppSystemLogs_CL`, regardless of any per-app logging configuration. Microsoft Learn documents that Container Apps log routing is configured at the environment scope ([Log options in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/log-options)); the operational consequence of omitting the property from IaC is what this lab demonstrates. The fix is at the environment scope, not the app scope: `az containerapp env update --logs-destination log-analytics --logs-workspace-id <customerId> --logs-workspace-key <sharedKey>`. After the fix, a new revision must be created to guarantee fresh platform events flow to the now-configured destination; the cheapest way to do that is an env-var-only update like `az containerapp update --set-env-vars FIXAPPLIED=<nonce>`.
