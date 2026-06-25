# Lab: Application Insights Connection String Missing

Reproducible **falsification** lab for the Azure Container Apps observability behavior when a Container App runs an OpenTelemetry-instrumented image without `APPLICATIONINSIGHTS_CONNECTION_STRING`.

The lab provisions one Container App and switches it to a custom image `acrappiconnx2lcxd.azurecr.io/hellotelemetry:v3` — a Flask + gunicorn application built with `azure-monitor-opentelemetry==1.6.4` whose `configure_azure_monitor()` initialization is guarded behind an `APPLICATIONINSIGHTS_CONNECTION_STRING` env-var presence check. The lab then exercises two states of the same image: the failure baseline with no env var set (revision `--0000006`, healthState=Healthy), and the recovered state after adding the env var via `az containerapp update --set-env-vars` (revision `--0000007`, healthState=Healthy, byte-identical container config minus the env array). This lab observed (2026-06-22 reproduction in `koreacentral`) that without the connection string env var the app responds HTTP 200 to all 20 sequential `curl` requests AND the revision reaches `healthState=Healthy` AND `ContainerAppSystemLogs_CL` records normal startup, but `AppRequests` and `AppTraces` in the workspace-based Application Insights both return zero rows for the app's `cloud_RoleName` (empirically `"unknown_service"`) after a 240-second post-traffic ingestion-lag sleep. After adding the env var, the same image on a new revision serves the next 20 `curl` requests as HTTP 200 and now `AppRequests` ingests 20 rows + `AppTraces` ingests 21 rows (1 startup `Azure Monitor configured: telemetry export enabled` log plus 20 per-request `/ endpoint hit (conn_str_present=True)` logs) under the same `cloud_RoleName` within the same 240-second sleep window. The before-fix and after-fix traffic-completed UTC timestamps captured by the two scripts span 408.0 s (`2026-06-22T05:02:57Z` → `2026-06-22T05:09:45Z`), well within the documented 2-5 minute App Insights ingestion-latency envelope.

The lab tests two hypotheses:

1. **H1 — Trigger produces the documented failure (silent observability gap).** With the instrumented `:v3` image deployed WITHOUT `APPLICATIONINSIGHTS_CONNECTION_STRING`, the app's first 20 client requests all return HTTP 200, the revision reaches `healthState=Healthy`, the `template.containers[0].env` field is `null`, AND `AppRequests` and `AppTraces` for the app's `cloud_RoleName` both contain zero rows after the 240-second post-traffic sleep.
2. **H2 — Fix restores telemetry.** After `az containerapp update --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING=<connstr>` (the connection string read from the App Insights resource and never echoed to logs), the new revision reaches `healthState=Healthy` with `template.containers[0].env` containing exactly the `APPLICATIONINSIGHTS_CONNECTION_STRING` entry, the next 20 client requests still all return HTTP 200, AND `AppRequests` ingests `requestCount=20` + `AppTraces` ingests `traceCount=21` (1 startup + 20 endpoint) for the same `cloud_RoleName` within the 240-second post-traffic sleep window.

If both hold, the lab proves that the presence of `APPLICATIONINSIGHTS_CONNECTION_STRING` in the Container App's `template.containers[].env` array is the single controlling variable for telemetry export to Application Insights when the image already ships an OpenTelemetry-instrumented runtime. The resource group, the Application Insights resource, the Log Analytics workspace, the ACR registry, the container image (`hellotelemetry:v3` byte-identical), the container name (`app`), the container `resources` block (`cpu=0.5`, `memory=1Gi`, `ephemeralStorage=2Gi`), the ingress configuration, the target port, the traffic generator, and the Container Apps environment (deployed WITHOUT environment-level `appInsightsConfiguration`, so the env-level OpenTelemetry agent is OFF) are all held constant across the failing baseline and the recovered state; the only experimental variable is whether the env array contains `APPLICATIONINSIGHTS_CONNECTION_STRING`.

> **Why H1 evidence here is silent rather than loud.** Unlike availability-loss failure modes (e.g., `acr-pull-failure`, `cpu-throttling`, `memory-leak-oomkilled`), this failure mode does not affect the user-facing HTTP response. The container starts, gunicorn binds `:8000`, the Flask route returns HTTP 200, and `ContainerAppSystemLogs_CL` records normal startup. The only observable defect is the absence of telemetry rows in Application Insights — operators relying on `AppRequests`-based latency dashboards or `requests`-based availability alerts will see no data and may incorrectly conclude that the app has no traffic. Gate 17 of the Phase B falsification gates carries an explicit `cohort_binding_note` field stating that the two empty-table sub-gates (b and c) are interpretable as missing-env-var evidence ONLY in conjunction with sub-gate (a) `env=null` AND sub-gate (d) `00-trigger-run.txt` recording 20 HTTP 200 responses, because without that binding an empty `AppRequests` table could be misread as "no traffic was generated" rather than "traffic was generated but the SDK was not wired".

> **Why this lab uses the SDK instrumentation path, not the environment-level OpenTelemetry agent.** The Container Apps environment is intentionally deployed without `appInsightsConfiguration` on the environment resource (see `infra/main.bicep`), so `evidence/06-env-telemetry-config.json` captures the expected `ERROR: The containerapp environment 'cae-appiconn-x2lcxd' does not have app insights enabled.` from `az containerapp env telemetry app-insights show`. The lab's falsification target is the per-container env var `APPLICATIONINSIGHTS_CONNECTION_STRING` consumed by `azure-monitor-opentelemetry==1.6.4` inside the Python app, NOT the env-level managed agent that auto-instruments without code changes. The env-level agent is a separate failure-mode dimension that would require a different lab (and a different controlling variable). The `ERROR` line is captured to document that the platform-level agent is OFF, so the SDK path is the only telemetry path under test.

## Structure

```text
labs/appinsights-connection-string-missing/
├── infra/main.bicep         # LAW (PerGB) + workspace-based App Insights + ACR Basic + Container Apps env (Consumption, NO env-level OpenTelemetry agent) + 1 Container App (placeholder image, no env var, system identity + AcrPull role on lab ACR)
├── app/Dockerfile           # python:3.11-slim + Flask + gunicorn 23.0.0 + azure-monitor-opentelemetry==1.6.4 on :8000
├── app/app.py               # Flask app with GUARDED configure_azure_monitor() + GET / endpoint logging conn_str_present
├── app/requirements.txt
├── trigger.sh               # Phase A — switch the Container App to the instrumented :v3 image WITHOUT setting APPLICATIONINSIGHTS_CONNECTION_STRING, poll revision Provisioned + Running, capture env (expect env=null), generate 20 curl requests (expect HTTP 200), sleep 240 s, query AppRequests + AppTraces (expect 0 rows), capture full config + env-level telemetry config
├── fix-and-capture.sh       # Phase A — read connection string from App Insights resource (never echoed), apply env var via az containerapp update --set-env-vars, poll new revision Provisioned + Running, capture env (expect APPLICATIONINSIGHTS_CONNECTION_STRING in envNames, value redacted), generate 20 fresh curl requests, sleep 240 s, query AppRequests + AppTraces (expect 20 + 21 rows), capture full config + per-5-minute timeline + per-message traces + revisions lifecycle + per-request requests detail, print PASS marker (formerly verify.sh)
├── verify.sh                # Phase B — Evidence-pack verifier (4 gates / 16 sub-gates, no Azure calls). Pure file processor that reads only the 20 canonical Phase A files and emits 4 derived gate JSONs.
├── cleanup.sh               # Delete the resource group
└── evidence/                # Captured CLI + KQL evidence
    ├── 00-trigger-run.txt                                # Full trigger.sh stdout/stderr (93 lines, includes 20 HTTP 200 lines)
    ├── 00-verify-run.txt                                 # Full fix-and-capture.sh stdout/stderr (111 lines, includes 20 HTTP 200 lines + literal "PASS: After adding APPLICATIONINSIGHTS_CONNECTION_STRING" marker; filename preserved across the Phase B verify.sh → fix-and-capture.sh rename)
    ├── 01-env-before-fix.json                            # Before fix: az containerapp show --query template.containers[0] (expect containerName=app, env=null, image=:v3)
    ├── 02-traffic-completed-before-fix.txt               # Before fix: `date -u +"%Y-%m-%dT%H:%M:%SZ"` recorded after the 20-curl loop (2026-06-22T05:02:57Z)
    ├── 03-ai-requests-before-fix.json                    # Before fix: az monitor app-insights query AppRequests | summarize by cloud_RoleName (expect tables[0].rows == [])
    ├── 04-ai-traces-before-fix.json                      # Before fix: az monitor app-insights query AppTraces | summarize by cloud_RoleName (expect tables[0].rows == [])
    ├── 05-containerapp-full-config-before-fix.json       # Before fix: az containerapp show --output json (full ARM resource snapshot)
    ├── 06-env-telemetry-config.json                      # az containerapp env telemetry app-insights show — expected ERROR captured to document the SDK-only path (env-level agent is intentionally OFF)
    ├── 07-env-after-fix.json                             # After fix: az containerapp show --query template.containers[0] (expect envNames=["APPLICATIONINSIGHTS_CONNECTION_STRING"], image=:v3 unchanged, value redacted at capture time)
    ├── 08-traffic-completed-after-fix.txt                # After fix: `date -u +"%Y-%m-%dT%H:%M:%SZ"` recorded after the 20-curl loop (2026-06-22T05:09:45Z, 408.0 s after the before-fix timestamp)
    ├── 09-ai-requests-after-fix.json                     # After fix: az monitor app-insights query AppRequests | summarize by cloud_RoleName (expect one row: cloud_RoleName="unknown_service", requestCount=20)
    ├── 10-ai-traces-after-fix.json                       # After fix: az monitor app-insights query AppTraces | summarize by cloud_RoleName (expect one row: cloud_RoleName="unknown_service", traceCount=21)
    ├── 11-containerapp-full-config-after-fix.json        # After fix: az containerapp show --output json (full ARM resource snapshot — byte-identical to 05 in template.containers[0] minus the env array)
    ├── 12-kql-requests-timeline.json                     # After fix: az monitor app-insights query AppRequests | summarize count() by bin(timestamp, 5m) (per-5-minute timeline binning showing the 20 requests landed in one 5-minute bin)
    ├── 13-ai-traces-messages-after-fix.json              # After fix: az monitor app-insights query AppTraces | project timestamp, message, severityLevel | take 25 (21 rows: 1 startup log + 20 endpoint-hit logs)
    ├── 14-revisions-lifecycle.json                       # az containerapp revision list decorated with a hasConnStr field computed in a python3 - <<'PY' heredoc per Lab 14 lesson 29 (8 revisions, the last 2 are the canonical Phase B cohort pair --0000006 and --0000007)
    ├── 15-ai-requests-detail-after-fix.json              # After fix: az monitor app-insights query AppRequests | project per-row detail (cloud_RoleName, timestamp, name, success, duration, url)
    ├── A1-v1-unguarded-sdk-crash-logs.json               # Image-lineage: az containerapp logs show --type system against the :v1 UNGUARDED revision documenting the CrashLoopBackOff failure mode (NOT a :v3 cohort member)
    ├── A2-v1-unguarded-crashloop-replica-state.json      # Image-lineage: az containerapp replica list against the :v1 UNGUARDED revision (runningState=Waiting, runningStateDetails="Container is waiting with reason: CrashLoopBackOff on legion.", restartCount=7)
    ├── A3-revisions-pre-patch.json                       # Image-lineage: az containerapp revision list captured before the :v3 canonical image was built (shows the placeholder helloworld revision + the :v1 crash revision)
    ├── 16-cohort-integrity-gate.json                     # Phase B Gate 16: 4 sub-gates (a) all 20 canonical Phase A files present, (b) temporal coherence — 02 and 08 timestamps both strict ISO-8601 UTC + monotonic + 408 s span within the 30-min Strong window, (c) no unexpected non-junk extras in evidence/, (d) this README cross-references all 4 Phase B gate JSON filenames literally
    ├── 17-failure-attribution-gate.json                  # Phase B Gate 17: 4 sub-gates (a) before-fix env=null + image=:v3 + container name=app, (b) AppRequests empty before fix, (c) AppTraces empty before fix, (d) 00-trigger-run.txt records 20 HTTP 200 lines + 93 total lines. Carries an explicit cohort_binding_note that sub-gates (b) and (c) are interpretable as missing-env-var evidence ONLY in conjunction with (a) and (d).
    ├── 18-recovery-materialization-gate.json             # Phase B Gate 18: 5 sub-gates (a) after-fix envNames=["APPLICATIONINSIGHTS_CONNECTION_STRING"] + image=:v3 unchanged + container name=app unchanged, (b) AppRequests after fix = one row [unknown_service, 20], (c) AppTraces after fix = one row [unknown_service, 21], (d) 13-ai-traces-messages-after-fix.json contains 21 records (1 startup + 20 endpoint-hit), (e) 00-verify-run.txt records 20 HTTP 200 lines + 111 total lines + literal "PASS: After adding APPLICATIONINSIGHTS_CONNECTION_STRING" marker
    ├── 19-single-variable-falsification-gate.json        # Phase B Gate 19: 3 sub-gates (a) before-fix and after-fix template.containers[0] records are byte-identical after stripping env, (b) revision pair --0000006 (hasConnStr=false, active=false) → --0000007 (hasConnStr=true, active=true) with same image and contiguous createdTime, (c) registry prefix byte-identical (acrappiconnx2lcxd.azurecr.io). Tear-down/no-recreation claims are dropped per Lab 21 Q1 directive.
    └── README.md                                         # Phase B evidence tour: provenance + capture timeline + claim ceiling + per-file integrity table + honest disclosure
```

## Quick Start

These commands assume the working directory is `labs/appinsights-connection-string-missing/` (so the relative `./infra/main.bicep`, `./app`, `./trigger.sh`, `./fix-and-capture.sh`, `./verify.sh`, and `./cleanup.sh` paths resolve). All `az` invocations pin `--subscription` explicitly to immunize the run against Azure CLI default-subscription drift, and the deployment is given the explicit name `main` so its outputs can be read back deterministically. Total wall-clock runtime is approximately 15 minutes (3 min deploy + 2 min `az acr build` + 5 min `trigger.sh` including 240 s post-traffic sleep + 5 min `fix-and-capture.sh` including 240 s post-traffic sleep + 1 min cleanup initiation).

```bash
cd labs/appinsights-connection-string-missing/

# 1) Base inputs — set these before any az command runs.
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-aiconn"
export LOCATION="koreacentral"

# 2) Provision the resource group and the lab infra (LAW + AI + ACR + CAE + app).
az group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --location "$LOCATION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --template-file ./infra/main.bicep \
    --parameters baseName="appiconn"

# 3) Read the deployment outputs the scripts need.
export APP_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.containerAppName.value" \
    --output tsv)
export ACR_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.acrName.value" \
    --output tsv)
export ACR_LOGIN_SERVER=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.acrLoginServer.value" \
    --output tsv)
export APP_INSIGHTS_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.appInsightsName.value" \
    --output tsv)
export IMAGE_TAG="hellotelemetry:v3"

# 4) Build the instrumented Python image directly inside the lab's ACR (no local Docker required).
az acr build \
    --subscription "$AZ_SUBSCRIPTION" \
    --registry "$ACR_NAME" \
    --image "$IMAGE_TAG" \
    ./app

# 5) Run the falsification experiment (Phase A — Live-Azure reproduction).
./trigger.sh         2>&1 | tee evidence/00-trigger-run.txt   # Switch to :v3 image WITHOUT env var, capture before-fix state, 20 curl HTTP 200, 240 s sleep, AppRequests/AppTraces (expect 0 rows)
./fix-and-capture.sh 2>&1 | tee evidence/00-verify-run.txt    # Add APPLICATIONINSIGHTS_CONNECTION_STRING, capture after-fix state, 20 curl HTTP 200, 240 s sleep, AppRequests/AppTraces (expect 20 + 21 rows)
./cleanup.sh                                                  # Delete the resource group

# 6) (Optional) Re-verify the committed evidence pack without re-deploying (Phase B — Evidence-pack verification).
bash verify.sh                                                # Phase B — pure file processor, 4 gates / 16 sub-gates
ls evidence/{16,17,18,19}-*-gate.json                         # emitted gate JSONs
```

## Phase A vs Phase B

This lab is delivered in two phases that share the same `labs/appinsights-connection-string-missing/` directory but have distinct purposes:

- **Phase A — Live-Azure reproduction.** The original lab that deploys real infrastructure to Azure, builds the instrumented `:v3` image inside the lab's ACR with `az acr build`, switches the Container App to that image WITHOUT the connection string env var, captures the silent observability gap (`AppRequests`/`AppTraces` zero rows under any `cloud_RoleName` after the 240-second post-traffic sleep), then recovers via `az containerapp update --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING=<connstr>` and captures the post-fix telemetry materialization (`AppRequests` = 20 rows + `AppTraces` = 21 rows under `cloud_RoleName="unknown_service"`). Phase A produced the canonical cohort that lives under `evidence/` (anchored on the 2026-06-22T05:02:57Z → 2026-06-22T05:09:45Z `koreacentral` traffic window, 408.0 s span). Scripts: `trigger.sh` (93 lines, before-fix evidence + 20 HTTP 200 + 240 s sleep + AppRequests/AppTraces query), `fix-and-capture.sh` (224 lines, env var add + 20 HTTP 200 + 240 s sleep + AppRequests/AppTraces query + post-fix evidence; formerly `verify.sh`), `cleanup.sh`. Cost: well under USD $0.05 per full run.
- **Phase B — Evidence-pack verification.** A pure file processor (`verify.sh`, 1360 lines, no Azure calls) that reads only the 20 committed canonical Phase A files under `evidence/` and emits four falsifiable gate JSONs (`16-cohort-integrity-gate.json` through `19-single-variable-falsification-gate.json`). Phase B exists so a reviewer or future maintainer can re-verify the published claims without re-deploying — running `bash verify.sh` on the committed evidence reproduces the four-gate verdict on disk (16/16 sub-gates PASS on the 2026-06-22 cohort, `overall_phase_b_verdict=PASS`). See [`evidence/README.md`](evidence/README.md) for the full provenance + capture timeline + claim-ceiling disclosure + per-file integrity table.

The historical pre-Phase-B `verify.sh` was the Phase A recovery + post-fix sampler (env var add + 20 requests + 240 s sleep + AppRequests/AppTraces query); the Phase B refactor renamed it to `fix-and-capture.sh` and assigned `verify.sh` to the new gate-emission role. The Phase A workflow above still runs the recovery + post-fix sampling, just under its new name. The captured log file `00-verify-run.txt` keeps its name for schema stability across the rename.

## What this lab demonstrates

- The initial Container App revision running `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` has no Application Insights instrumentation at all (no SDK in the image). The `:v3` image is built into the lab's ACR by step 4 of Quick Start and is switched in by `trigger.sh`.
- `trigger.sh` (Phase A failure-reproduction script) switches the app to the custom Python image (`hellotelemetry:v3`) built with `azure-monitor-opentelemetry==1.6.4` but does NOT set `APPLICATIONINSIGHTS_CONNECTION_STRING`. The app responds HTTP 200 to all 20 curl requests, but `configure_azure_monitor()` is guarded behind an env-var presence check and skipped — the App Insights `AppRequests` and `AppTraces` tables both stay empty under any `cloud_RoleName` after the 240-second post-traffic sleep.
- `fix-and-capture.sh` (Phase A recovery script) adds `APPLICATIONINSIGHTS_CONNECTION_STRING` via `az containerapp update --set-env-vars`, generates 20 fresh requests, sleeps 240 s, then re-queries Application Insights. The `AppRequests` table now shows exactly one row under `cloud_RoleName="unknown_service"` with `requestCount=20`, and the `AppTraces` table shows exactly one row under the same `cloud_RoleName` with `traceCount=21` (decomposing into 1 startup `Azure Monitor configured: telemetry export enabled` log + 20 per-request `/ endpoint hit (conn_str_present=True)` logs).
- The only changed variable between the failing run and the working run is the env var. Image (`acrappiconnx2lcxd.azurecr.io/hellotelemetry:v3`), container name (`app`), container `resources` block (`cpu=0.5`, `memory=1Gi`, `ephemeralStorage=2Gi`), ingress configuration, target port (`:8000`), workload (Flask + gunicorn 23.0.0), and traffic pattern (20 sequential `curl` requests) are all held constant. Gate 19 sub-gate (a) confirms the `template.containers[0]` records are byte-identical after stripping the `env` field.
- The pass/fail logic encodes three outcomes plus one invalid-run guard:
    - **H1 PASS + H2 PASS** ⇒ the falsification hypothesis is SUPPORTED. `fix-and-capture.sh` exits 0 and the literal `PASS: After adding APPLICATIONINSIGHTS_CONNECTION_STRING` marker is printed to `evidence/00-verify-run.txt`.
    - **H1 FALSIFIED in `trigger.sh`** (`AppRequests` or `AppTraces` shows rows BEFORE the env var is added — i.e., the SDK is exporting telemetry without the documented configuration mechanism) ⇒ `trigger.sh` exits non-zero and `fix-and-capture.sh` is never reached.
    - **H2 FALSIFIED in `fix-and-capture.sh`** (`AppRequests` is still empty OR `AppTraces` rowcount is not 21 AFTER the env var is added) ⇒ `fix-and-capture.sh` exits non-zero.
    - **INVALID RUN** (a required environment variable is unset, the `az acr build` failed, or the trigger.sh evidence file is missing) ⇒ exit 1.

## Why the canonical image is `:v3` (not `:v1` or `:v2`)

This lab carries two earlier image tags that document distinct failure modes encountered while building the lab. They are kept in the ACR and in the evidence pack so the lab itself documents what was tried and why the current image is what it is:

- `:v1` — `configure_azure_monitor()` called UNGUARDED. With `APPLICATIONINSIGHTS_CONNECTION_STRING` unset, `azure-monitor-opentelemetry==1.6.4` raises `ValueError: Instrumentation key cannot be none or empty.` at import time inside `/usr/local/lib/python3.11/site-packages/azure/monitor/opentelemetry/exporter/_connection_string_parser.py:106`, the gunicorn worker (pid 8) exits with code 3 "Worker failed to boot", and the container enters CrashLoopBackOff (`runningState=Waiting`, `runningStateDetails="Container is waiting with reason: CrashLoopBackOff on legion."`, `restartCount=7`). This is a DIFFERENT failure mode (availability loss, not silent observability gap) and is captured under `evidence/A1-v1-unguarded-sdk-crash-logs.json` and `evidence/A2-v1-unguarded-crashloop-replica-state.json`. Not used as the canonical scenario because production apps in real escalations typically wrap SDK init defensively.
- `:v2` — `configure_azure_monitor()` is guarded by an env-var presence check, but Flask is imported with `from flask import Flask` BEFORE `configure_azure_monitor()` runs. In this lab's development experience the Flask auto-instrumentation hook could not wrap the `Flask` class after it had been fully imported, so `AppRequests` stayed empty even when the env var was present. This is the kind of subtle Python distro instrumentation gotcha that easily masquerades as "connection string missing" in production. The `:v2` source variant is described here as a lab-development observation; no per-revision `AppRequests`/`AppTraces` capture file is committed for it (the canonical falsification pair in this lab is the `:v3` before/after run, not a `:v2`/`:v3` comparison).
- `:v3` — canonical image. Same guard as `:v2`, plus two fixes: (1) `import flask` as a module (deferring the `Flask` class lookup until AFTER `configure_azure_monitor()` runs), and (2) `configure_azure_monitor(connection_string=CONN_STR, logger_name=__name__)` with explicit `logger_name` so module-level `logger.info(...)` calls export to `AppTraces`.

## Why `cloud_RoleName == "unknown_service"`

The `azure-monitor-opentelemetry==1.6.4` distro does not infer a meaningful service name from the Container App or revision name; it defaults to `unknown_service` unless `OTEL_SERVICE_NAME` is set in the container env. This lab intentionally does not set `OTEL_SERVICE_NAME` because the falsification target is the connection string env var alone — adding a second env var would dilute the single-variable claim. Gates 17 and 18 both anchor on the literal string `"unknown_service"` because that is what the captured JSON contains; a real production app would set `OTEL_SERVICE_NAME` and would see a different role name in its `AppRequests` and `AppTraces` rows.

## Cost notes

- Resources provisioned: 1 Log Analytics workspace (PerGB, 30-day retention), 1 workspace-based Application Insights, 1 ACR Basic registry, 1 Container Apps Environment (Consumption), 1 Container App with `minReplicas: 1, maxReplicas: 1, cpu: 0.5, memory: 1Gi`.
- No public IP, no private endpoint, no VNet integration.
- ACR Basic prorates to roughly USD $0.167/day; the lab is designed to run end-to-end and clean up in under 20 minutes, so the ACR charge is approximately USD $0.002.
- The Container App runs with `minReplicas: 1` for the full lab duration (approximately 15 minutes including both 240-second post-traffic sleeps), which costs well under USD $0.01.
- `az acr build` runs on a Microsoft-hosted worker and is billed per-build-minute; the workload Dockerfile is small (python:3.11-slim base + Flask + gunicorn + azure-monitor-opentelemetry install) and typically builds in under 2 minutes, which is well under USD $0.01.
- Application Insights ingestion of 20 `AppRequests` rows + 21 `AppTraces` rows is well under the workspace's daily free quota and incurs no charge for this lab.
- Total cost for one end-to-end lab run is well under USD $0.05.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.

## App Insights ingestion latency

- Application Insights typically ingests fresh telemetry within 2 to 5 minutes. Both `trigger.sh` and `fix-and-capture.sh` sleep 240 seconds after sending traffic before running the KQL query.
- If the post-fix query in `evidence/09-ai-requests-after-fix.json` still shows 0 rows, wait another 2 minutes and re-run the query manually:

    ```bash
    az monitor app-insights query \
        --subscription "$AZ_SUBSCRIPTION" \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RG" \
        --analytics-query 'requests | where timestamp > ago(15m) | summarize count() by cloud_RoleName'
    ```

- The Phase B verifier (`verify.sh`) does NOT re-introduce this latency — it reads the already-captured KQL files and emits its four gate JSONs in under 5 seconds.

## What to record in your evidence write-up

When you ship this lab's evidence into a docs PR or a support ticket, ALWAYS record the following alongside the JSON captures:

- **Azure region** (e.g., `koreacentral`). Visible in `evidence/00-trigger-run.txt` startup banner and in the gate JSONs' anchor metadata.
- **Azure CLI version** and **`containerapp` extension version** (`az version`, `az extension list --query "[?name=='containerapp']"`). Captured into `evidence/README.md` "CLI versions and platform context" section.
- **Date of the run in UTC** (visible at the top of `evidence/00-trigger-run.txt` and `evidence/00-verify-run.txt`, plus the dedicated traffic-completion timestamp files `evidence/02-traffic-completed-before-fix.txt` and `evidence/08-traffic-completed-after-fix.txt`).
- **The exit code of `trigger.sh`, `fix-and-capture.sh`, and Phase B `verify.sh`** (0 = hypothesis supported / all gates PASS, 1 = invalid run / verifier infra error, 2 = any gate FAIL).
- **The before-fix and after-fix `cloud_RoleName` aggregation** (`evidence/03-ai-requests-before-fix.json` showing `tables[0].rows == []` and `evidence/09-ai-requests-after-fix.json` showing `[["unknown_service", 20]]`). The same `cloud_RoleName` value materializes after the fix is part of the evidence that the app identity is held constant.
- **The before-fix and after-fix `template.containers[0]` arrays** (`evidence/05-containerapp-full-config-before-fix.json` and `evidence/11-containerapp-full-config-after-fix.json`) so that the env-diff (the single experimental variable) can be inspected directly. Gate 19 sub-gate (a) confirms these are byte-identical after stripping the `env` field.
- **The revision pair lifecycle** (`evidence/14-revisions-lifecycle.json`) showing `--0000006` (`hasConnStr=false`, `active=false`, `createdTime=2026-06-22T05:01:48+00:00`) and `--0000007` (`hasConnStr=true`, `active=true`, `createdTime=2026-06-22T05:08:34+00:00`) — Gate 19 sub-gate (b) record-scopes its iteration to this pair, NOT to the full revision history (the lab carries 8 revisions in total, of which the first 6 are image-lineage and cohort-irrelevant).

## Operator takeaway

This lab observed (2026-06-22 reproduction in `koreacentral`) that when an Azure Container App runs an OpenTelemetry-instrumented image (`azure-monitor-opentelemetry==1.6.4` with `configure_azure_monitor()` guarded behind an env-var presence check) without setting `APPLICATIONINSIGHTS_CONNECTION_STRING`, the platform produces a deterministic silent observability gap: the app serves HTTP 200 to all client requests, the revision reaches `healthState=Healthy`, and `ContainerAppSystemLogs_CL` records normal startup, but `AppRequests` and `AppTraces` in the workspace-based Application Insights both stay at zero rows for the app's `cloud_RoleName` indefinitely (the 240-second post-traffic sleep is well past the documented 2-5 minute ingestion lag). Microsoft Learn documents that the Azure Monitor OpenTelemetry distro reads its connection string from the `APPLICATIONINSIGHTS_CONNECTION_STRING` env var by default ([Connection strings in Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/connection-strings), [Enable Azure Monitor OpenTelemetry for Python](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-python), [OpenTelemetry agents in Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents)); when that env var is absent, the distro's `configure_azure_monitor()` initialization either raises `ValueError: Instrumentation key cannot be none or empty.` (the `:v1` failure mode this lab captures as image-lineage in `evidence/A1-v1-unguarded-sdk-crash-logs.json`, which produces a loud CrashLoopBackOff) OR is bypassed entirely if the app code guards it (the `:v3` silent-gap failure mode this lab's canonical cohort captures, which produces healthy HTTP 200 responses and empty telemetry tables). The fix is to add the env var via `az containerapp update --name "$APP_NAME" --resource-group "$RG" --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING="$(az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RG" --query connectionString --output tsv)"`. After the fix, the platform creates a new Healthy revision serving 100% of traffic with the env var present, the 20 fresh client requests still return HTTP 200, and `AppRequests` ingests 20 rows + `AppTraces` ingests 21 rows (1 startup + 20 endpoint-hit) for the same `cloud_RoleName` within the same 240-second post-traffic sleep. The cheapest live-incident diagnostic for this failure mode is the combination of (1) the env array from `az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers[].env"` checked for an entry with `name=APPLICATIONINSIGHTS_CONNECTION_STRING`, and (2) the per-`cloud_RoleName` row count from `az monitor app-insights query --app "$APP_INSIGHTS_NAME" --resource-group "$RG" --analytics-query 'requests | where timestamp > ago(15m) | summarize count() by cloud_RoleName'` filtered to the app's role name; either alone is suggestive, but the two together (env array missing the entry + 0 rows in `AppRequests`) are the smoking gun. Note that a production app would set `OTEL_SERVICE_NAME` to a meaningful role name; this lab's empirical `cloud_RoleName="unknown_service"` is the distro's default and is anchored in Gates 17 and 18 precisely because it is what the captured JSON contains. The matching playbook is [`docs/troubleshooting/playbooks/observability/appinsights-connection-string-missing.md`](../../docs/troubleshooting/playbooks/observability/appinsights-connection-string-missing.md); reproduce locally with `./trigger.sh` and `./fix-and-capture.sh` to validate it against your own environment before training on-call engineers.
