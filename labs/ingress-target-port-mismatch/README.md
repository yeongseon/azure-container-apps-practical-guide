# Lab: Ingress Target Port Mismatch

Reproducible **falsification** lab for the Azure Container Apps app-scope ingress setting `properties.configuration.ingress.targetPort` (CLI: `az containerapp ingress update --target-port`).

The lab provisions one Container App in the documented healthy baseline (`ingress.external=true`, `ingress.targetPort=80`, `transport=auto`, helloworld image listening on `:80`), verifies the baseline returns HTTP 200, then mutates `ingress.targetPort` to `8081` (a port no process is listening on inside the container) and observes the documented failure signature. This lab observed (2026-06-22 reproduction in `koreacentral`) that the mutation produces edge HTTP 503 responses on every request AND rows in `ContainerAppSystemLogs_CL` whose `Reason_s == "Pending:PortMismatch"` and whose `Log_s` carries the smoking-gun string `The TargetPort <X> does not match the listening port <Y>.` — the platform's own attribution that the configured ingress port does not match what the container is listening on. The mutation is then reversed (`--target-port 80`) and the same KQL is rerun against a strictly post-fix UTC window; the table is silent for PortMismatch in that window, and the edge returns HTTP 200 again.

The lab tests two hypotheses:

1. **H1 — Trigger produces the documented failure.** After `az containerapp ingress update --target-port 8081`, within 60 s the edge returns ≤ 1/10 HTTP 200 responses, and within a 300 s ingestion window `ContainerAppSystemLogs_CL` records ≥ 1 row whose `Reason_s == "Pending:PortMismatch"` or whose `Log_s` contains `TargetPort`, scoped to `TimeGenerated > datetime(<TRIGGER_UTC>)`.
2. **H2 — Fix restores recovery.** After `az containerapp ingress update --target-port 80`, within 30 s the edge returns ≥ 8/10 HTTP 200 responses, and a 300 s post-fix ingestion window shows 0 PortMismatch rows when scoped to `TimeGenerated > datetime(<FIX_UTC>)`.

If both hold, the lab proves that `ingress.targetPort` (relative to the container's listening port) is the single controlling variable for this failure mode. The container image, the listening port, the revision name, the ingress transport, and the workspace are all held constant across the baseline, the triggered state, and the post-fix state; the only experimental variable is the `targetPort` integer.

> **Why the strict post-fix UTC cutoff (and not `ago(5m)`).** The platform may continue emitting PortMismatch attribution rows for a short tail after the underlying ingress was already updated, because the probe-failure events were generated in the triggered window and ingestion is asynchronous. A relative window like `ago(5m)` that begins counting at query time would include that tail and would falsely falsify H2. The lab captures `FIX_UTC` at the exact moment of the `az containerapp ingress update --target-port 80` call and scopes the H2 KQL to `TimeGenerated > datetime(${FIX_UTC})`, which is the only window that can validly demonstrate that the platform stopped attributing PortMismatch failures AFTER the fix. The Microsoft Learn KQL example at [Logging in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash) documents the `ago(...)` pattern for general-purpose queries; the strict cutoff is a lab-specific rigor choice, not a Learn-documented requirement.

> **Why the lab uses `targetPort=8081` and not `8001`.** The earlier 2026-06-02 PR-A Portal captures in this repository used `8081` because that is the port the original 2026-04-29 CLI runbook chose. A subsequent 2026-06-18 production case pattern subsection in the lab guide used `8001` because that was the port the customer environment had configured. This evidence pack uses `8081` to align with the PR-A captures already published in `docs/assets/troubleshooting/ingress-target-port-mismatch/ingress-port-mismatch-*.png` and to keep clean separation from the production case pattern subsection (which is documented separately in the lab guide and is not part of this scripted reproduction).

## Structure

```text
labs/ingress-target-port-mismatch/
├── infra/main.bicep      # LAW + Container Apps env (appLogsConfiguration populated) + 1 helloworld app (targetPort=80, minReplicas=1, maxReplicas=1)
├── trigger.sh            # Phase A — Phases 1-10: baseline ingress + 10 requests, trigger targetPort=8081, failed traffic, 300s wait, KQL PortMismatch (expect populated_table)
├── fix-and-capture.sh    # Phase A — Phases 11-17: restore targetPort=80, post-fix traffic, 300s wait, KQL PortMismatch scoped to TimeGenerated > FIX_UTC (expect silent_valid_baseline) (renamed from verify.sh)
├── verify.sh             # Phase B — Offline evidence-pack verifier (4 gates / 16 sub-gates, no Azure calls). Reads only committed evidence and emits 4 derived gate JSONs.
├── cleanup.sh            # Delete the resource group
└── evidence/             # Captured CLI evidence
    ├── 00-trigger-run.txt                            # Full trigger.sh stdout/stderr
    ├── 00-verify-run.txt                             # Full fix-and-capture.sh stdout/stderr (filename preserved across the Phase B rename)
    ├── 01-ingress-config-before.json                 # Phase 1: ingress + revision before trigger (expect targetPort=80, external=true)
    ├── 02-replicas-before.json                       # Phase 2: replica list before trigger
    ├── 03-curl-before.json                           # Phase 3: 10 HTTPS request results to baseline (expect >=8/10 HTTP 200)
    ├── 04-ingress-update-result.json                 # Phase 4: az containerapp ingress update --target-port 8081 result
    ├── 05-ingress-config-after-trigger.json          # Phase 5: ingress + revision after trigger (expect targetPort=8081)
    ├── 06-replicas-after-trigger.json                # Phase 7: replica list after trigger
    ├── 07-revision-status-after-trigger.json         # Phase 7: revision-show after trigger (replicas + healthState + trafficWeight)
    ├── 08-curl-after-trigger.json                    # Phase 8: 10 HTTPS request results after trigger (expect <=1/10 HTTP 200)
    ├── 09-kql-after-trigger.json                     # Phase 10: parsed KQL summarize + gate_classification (expect populated_table)
    ├── 09-kql-after-trigger-portmismatch-raw.txt     # Phase 10: raw az monitor log-analytics query stdout for summarize KQL
    ├── 09-kql-after-trigger-portmismatch-sample-raw.txt # Phase 10: raw az monitor log-analytics query stdout for sample (project ... take 5) KQL
    ├── 10-ingress-update-fix-result.json             # Phase 11: az containerapp ingress update --target-port 80 result
    ├── 11-ingress-config-after-fix.json              # Phase 12: ingress + revision after fix (expect targetPort=80)
    ├── 12-replicas-after-fix.json                    # Phase 14: replica list after fix
    ├── 13-revision-status-after-fix.json             # Phase 14: revision-show after fix
    ├── 14-curl-after-fix.json                        # Phase 15: 10 HTTPS request results after fix (expect >=8/10 HTTP 200)
    ├── 15-kql-after-fix.json                         # Phase 17: parsed KQL summarize + gate_classification (expect silent_valid_baseline)
    ├── 15-kql-after-fix-portmismatch-raw.txt         # Phase 17: raw az monitor log-analytics query stdout for summarize KQL
    ├── 15-kql-after-fix-portmismatch-sample-raw.txt  # Phase 17: raw az monitor log-analytics query stdout for sample KQL
    ├── 20-cli-versions.json                          # Post-run: `az version`
    ├── 21-cli-containerapp-ext.json                  # Post-run: containerapp extension version
    ├── 22-region.json                                # Post-run: deployment region
    ├── 23-deployment-outputs.json                    # Post-run: full deployment outputs
    ├── 14-cohort-integrity-gate.json                 # Phase B Gate 14: Strong/Fallback cohort integrity over the 25 canonical files
    ├── 15-h1-trigger-produces-failure-gate.json      # Phase B Gate 15 (H1): ingress mutated + traffic broke + KQL populated + smoking-gun sample
    ├── 16-h2-fix-restores-recovery-gate.json         # Phase B Gate 16 (H2): ingress restored + traffic recovered + KQL silenced + strict post-fix UTC cutoff
    ├── 17-single-variable-falsification-gate.json    # Phase B Gate 17 (H3): only targetPort changed + no new revision + identity preserved + listening-port constancy substantiated
    └── README.md                                     # Phase B evidence tour: timeline, gate descriptions, disclosures, file index
```

## Quick Start

These commands assume the working directory is `labs/ingress-target-port-mismatch/`. All `az` invocations pin `--subscription` explicitly to immunize the run against Azure CLI default-subscription drift, and the deployment is given the explicit name `main` so its outputs can be read back deterministically. Total wall-clock runtime is approximately 19 minutes (3 min deploy + 8 min trigger including 60 s propagation wait and 300 s ingestion wait + 6 min fix-and-capture including 30 s propagation wait and 300 s post-fix wait + 1 min offline Phase B verify + 1 min cleanup initiation).

```bash
cd labs/ingress-target-port-mismatch/

# 1) Base inputs.
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-ingress-port"
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
    --parameters baseName="ingressport"

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
export WORKSPACE_CUSTOMER_ID=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.logAnalyticsCustomerId.value" \
    --output tsv)

# 4) Run Phase A (live Azure capture).
./trigger.sh           2>&1 | tee evidence/00-trigger-run.txt   # pre-trigger checks + 10 requests + ingress update + post-trigger 10 requests + 300s wait + KQL (expect populated_table)
./fix-and-capture.sh   2>&1 | tee evidence/00-verify-run.txt    # ingress update --target-port 80 + 10 requests + 300s wait + KQL (expect silent_valid_baseline in strict post-fix window)

# 5) Run Phase B (offline evidence-pack verification).
bash verify.sh                                                # emits Gate 14/15/16/17 JSONs; expect 16/16 PASS

# 6) Clean up.
./cleanup.sh                                                  # delete the resource group
```

## Phase A vs Phase B

This lab now splits the live-Azure reproduction from the offline evidence-pack verification:

- **Phase A — Live Azure reproduction.** `trigger.sh` captures the healthy baseline, applies the trigger (`targetPort=8081`), drives failed traffic, waits for system-log ingestion, and captures the populated PortMismatch window. `fix-and-capture.sh` then restores `targetPort=80`, re-runs traffic, waits for the strict post-fix ingestion window, and captures the silent PortMismatch result. The historical Phase A script name was `verify.sh`; it was renamed to `fix-and-capture.sh` so `verify.sh` could become the offline verifier. The captured log file remains `00-verify-run.txt` for schema stability.
- **Phase B — Offline evidence-pack verification.** `verify.sh` is now a pure file processor that reads the committed Phase A cohort plus `evidence/README.md` and the `evidence/` directory listing for Gate 14 integrity checks, emits four derived gate JSONs, and exits 0 only when all 16 sub-gates pass. See [`evidence/README.md`](evidence/README.md) for the full evidence-pack tour.

## What this lab demonstrates

- The Container Apps environment is provisioned by `infra/main.bicep` with `appLogsConfiguration.destination='log-analytics'` so that `ContainerAppSystemLogs_CL` ingests platform events, which is what the H1 KQL gate reads.
- The Container App is provisioned in the documented healthy baseline: `ingress.external=true`, `ingress.targetPort=80`, `transport='auto'`, image listens on `:80`. The first `trigger.sh` phase verifies this baseline via `az containerapp show` and via 10 sequential HTTPS requests; if the baseline does not hold, the script exits 1 (INVALID RUN) before applying the trigger.
- `activeRevisionsMode: 'Single'` is used so the only revision is the one being modified by the trigger. Ingress updates are documented at [Ingress in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/ingress-how-to) as application-scope (they do not create a new revision); the lab asserts this by capturing `latestRevisionName` before and after the trigger and flagging any change as a `NOTE` (not a hard failure, because the documentation behavior could in principle evolve).
- `minReplicas: 1, maxReplicas: 1` is used so the platform reliably emits probe-failure events into `ContainerAppSystemLogs_CL` with no scale-to-zero confounder. The container itself stays Running across the trigger; what fails is the ingress's ability to reach a process on the configured port.
- `trigger.sh` Phase 4 captures `TRIGGER_UTC` and calls `az containerapp ingress update --target-port 8081`. Phase 6 waits 60 s for the ingress configuration to propagate and for the first probe failures to land. Phase 8 issues 10 HTTPS requests against the public FQDN; the H1 sub-gate A is `requests_ok <= 1/10`. Phase 9 waits 300 s for system log ingestion. Phase 10 runs two KQL queries: a `summarize` to count rows and a `project ... take 5` to capture sample evidence, both scoped to `TimeGenerated > datetime(${TRIGGER_UTC})` to keep the window strictly post-trigger. The KQL summarize is parsed by a phase-aware classifier that emits one of four `gate_classification` values: `populated_table` (≥1 PortMismatch row — expected here), `silent_failure` (0 PortMismatch rows in the post-trigger window — wrong outcome, trigger ineffective or ingestion delayed), `silent_valid_baseline` (used only by `verify.sh`), or `query_error_invalid_run` (the KQL CLI returned an unexpected error signature). The H1 sub-gate B is therefore `gate_classification == populated_table`, which means `portmismatch_rows >= 1` in the strictly post-trigger window.
- `fix-and-capture.sh` Phase 11 captures `FIX_UTC` and calls `az containerapp ingress update --target-port 80`. Phase 13 waits 30 s for the ingress configuration to propagate. Phase 15 issues 10 HTTPS requests; the H2 sub-gate A is `requests_ok >= 8/10`. Phase 16 waits 300 s for any final probe-failure events generated in the post-fix wait to land. Phase 17 runs the same two KQL queries scoped to `TimeGenerated > datetime(${FIX_UTC})`; the same phase-aware classifier emits `silent_valid_baseline` (0 PortMismatch rows — expected post-fix), `populated_table` (≥1 PortMismatch row — fix did not hold), `silent_failure` (used only by `trigger.sh`), or `query_error_invalid_run`. The H2 sub-gate B is therefore `gate_classification == silent_valid_baseline`, which means `portmismatch_rows == 0` in the strictly post-fix window.
- The pass/fail logic encodes three outcomes plus one invalid-run guard:
    - **H1 PASS + H2 PASS** ⇒ the falsification hypothesis is SUPPORTED. `fix-and-capture.sh` exits 0.
    - **H1 FALSIFIED in `trigger.sh`** (post-trigger curl still returned ≥ 2/10 HTTP 200, OR `portmismatch_rows` was 0 in the post-trigger window — `gate_classification == silent_failure`) ⇒ the trigger did not produce the documented failure. `trigger.sh` exits 2 and `fix-and-capture.sh` is never reached.
    - **H2 FALSIFIED in `fix-and-capture.sh`** (post-fix curl did not return ≥ 8/10 HTTP 200, OR PortMismatch rows continued to appear in the strictly post-fix window — `gate_classification == populated_table`) ⇒ the fix did not restore recovery. `fix-and-capture.sh` exits 2.
    - **INVALID RUN** (baseline did not hold, or KQL produced an unexpected error signature that is neither valid JSON nor the documented "table not yet materialized" signature) ⇒ `trigger.sh` or `fix-and-capture.sh` exits 1.
    - **Phase B (`verify.sh`)** — offline only: exits 0 when all 4 gates / 16 sub-gates PASS, else exits 1.

## Why the lab tests `ContainerAppSystemLogs_CL` (not `ContainerAppConsoleLogs_CL`)

The two tables represent two distinct log paths and only one is relevant to this failure mode:

- **`ContainerAppSystemLogs_CL`** carries platform-emitted events such as `ProbeFailed` and `Pending:PortMismatch`, including the platform's own attribution of `TargetPort`-related probe failures (`Log_s` contains `The TargetPort <X> does not match the listening port <Y>.`). This is the table the H1 KQL gate reads, because the platform — not the container — is the source of the diagnostic message that names the offending port.
- **`ContainerAppConsoleLogs_CL`** carries stdout/stderr from the application container. The helloworld image's Nginx process never receives the misrouted requests (because the ingress sends them to port 8081, where nothing is listening), so the application emits no log line attributable to the failure. The lab does not query this table because there is nothing diagnostic to find in it for this failure mode.

The companion KQL pack at [`docs/troubleshooting/kql/system-and-revisions/target-port-mismatch-detection.md`](../../docs/troubleshooting/kql/system-and-revisions/target-port-mismatch-detection.md) documents the smoking-gun query used here (`Reason_s == "Pending:PortMismatch"` OR `Log_s contains "TargetPort"`) and includes an extraction pattern for pulling the configured port and the listening port out of `Log_s`.

## Why the experiment uses the `helloworld` image

This lab measures ingress-to-container port wiring, not application behavior. Using the public Microsoft-hosted `containerapps-helloworld` image avoids the confounders that would come with a custom image:

- No ACR provisioning, no ACR pull authentication failure path.
- Predictable single listening port (`:80`) that matches the documented placeholder image contract.
- The image is identical across the baseline, the triggered state, and the post-fix state, so the only experimental variable is the integer `targetPort`.

## Cost notes

- Resources provisioned: 1 Log Analytics workspace (PerGB, 30-day retention), 1 Container Apps Environment (Consumption), 1 Container App with `minReplicas: 1`, `maxReplicas: 1`, `0.25 vCPU`, `0.5 Gi` memory.
- No ACR, no Application Insights, no public IP, no private endpoint, no VNet integration.
- With `minReplicas: 1`, the app is billed continuously while it exists, but the lab is designed to run end-to-end and clean up in under 20 minutes. The Container Apps Consumption plan at 0.25 vCPU + 0.5 Gi for 20 minutes costs well under USD $0.01; the Log Analytics ingestion of a few KB of platform logs is similarly negligible.
- Total cost for one end-to-end lab run is well under USD $0.05.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.

## What to record in your evidence write-up

When you ship this lab's evidence into a docs PR or a support ticket, ALWAYS record the following alongside the JSON captures:

- **Azure region** (e.g., `koreacentral`). Captured to `evidence/22-region.json`.
- **Azure CLI version** and **`containerapp` extension version** (`az version`, `az extension list --query "[?name=='containerapp']"`). Captured to `evidence/20-cli-versions.json` and `evidence/21-cli-containerapp-ext.json`.
- **Date of the run in UTC** (visible at the top of `00-trigger-run.txt` and `00-verify-run.txt`).
- **The exit code of `trigger.sh`, `fix-and-capture.sh`, and Phase B `verify.sh`** (0 = Phase A supported or Phase B all gates PASS, 1 = invalid run or Phase B gate failure, 2 = Phase A falsified).
- **Full deployment outputs** so the reader can reproduce the LAW guid, env name, app name, FQDN. Captured to `evidence/23-deployment-outputs.json`.
- **The two UTC anchors `TRIGGER_UTC` and `FIX_UTC`** (visible in `00-trigger-run.txt` and `00-verify-run.txt`). These are what the strict KQL window filters are based on; reproducibility of the H2 gate requires both anchors to be recorded alongside the row counts.

The log ingestion lag between platform event emission and KQL queryability in `ContainerAppSystemLogs_CL` is not documented as a strict SLA. This lab uses a 300 s wait window after the trigger and another 300 s after the fix, which has been observed to be sufficient in this reproduction, but a slower region or a busier workspace may need a longer wait. Recording the wait window and the post-wait row counts is critical for reproducibility. The offline Phase B overlay in [`evidence/README.md`](evidence/README.md) documents the four-gate falsification structure over the committed cohort.

## Operator takeaway

This lab observed (2026-06-22 reproduction in `koreacentral`) that when `ingress.targetPort` is configured to a port that no process inside the container is listening on, the Azure Container Apps platform produces a deterministic, machine-readable failure signature: every external HTTPS request to the FQDN returns HTTP 503, and `ContainerAppSystemLogs_CL` ingests rows whose `Reason_s == "Pending:PortMismatch"` and whose `Log_s` carries the smoking-gun string `The TargetPort <X> does not match the listening port <Y>.` (the surrounding text varies — typical form is `Deployment Progress Deadline Exceeded. N/N replicas ready. The TargetPort <X> does not match the listening port <Y>.`). Microsoft Learn documents that ingress is the application-scope routing layer that forwards traffic to the configured target port ([Ingress in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview), [How to configure ingress](https://learn.microsoft.com/en-us/azure/container-apps/ingress-how-to)) and that probes default to the ingress target port when none are defined ([Health probes in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/health-probes)); the consequence of misconfiguring that target port is what this lab demonstrates. The fix is at the app's ingress configuration scope: `az containerapp ingress update --target-port <correct-port>`. After the fix, the platform stops emitting PortMismatch attribution rows in the strictly post-fix UTC window, and the edge returns HTTP 200 within 30 s without requiring a new revision. The cheapest diagnostic during a live incident is the smoking-gun KQL query in [`docs/troubleshooting/kql/system-and-revisions/target-port-mismatch-detection.md`](../../docs/troubleshooting/kql/system-and-revisions/target-port-mismatch-detection.md); reproduce locally with `./trigger.sh`, `./fix-and-capture.sh`, and `bash verify.sh` to validate it against your own environment before training on-call engineers.
