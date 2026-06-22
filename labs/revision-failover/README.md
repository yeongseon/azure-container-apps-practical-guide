# Lab: Revision Failover and Rollback

Reproducible **falsification** lab for the Azure Container Apps platform behavior when the active revision's ingress `targetPort` is reconfigured to a port the workload is not listening on, causing the platform startup probe to fail repeatedly and the same revision to transition from `Healthy` to non-`Healthy` in-place.

The lab provisions one Container App with a Flask + Gunicorn workload listening on port 8000 (the canonical baseline), then flips ingress `targetPort` from 8000 to 9999 via `az containerapp ingress update` (an app-level configuration change that modifies the same revision in place — it does NOT create a new revision). The platform startup probe is re-targeted to port 9999 where nothing is listening, so the same revision transitions from `Healthy` to non-`Healthy` after accumulated probe failures (measured at 261 s on the 2026-06-23 reproduction; the platform's exact threshold depends on probe configuration and retry budgets and is not publicly documented). HTTP requests to the FQDN start failing because the platform deems the revision non-Healthy. The lab then applies the in-place fix by flipping `targetPort` back to 8000; the probe re-targets to the port the Gunicorn container has been listening on the entire time, and the same revision recovers to `Healthy` within ~30 s without a new revision being created. This is the canonical **path b** recovery semantics that the existing 2026-06-03 Portal capture sequence in [`docs/troubleshooting/lab-guides/revision-failover.md`](../../docs/troubleshooting/lab-guides/revision-failover.md) documents.

The lab tests two hypotheses:

1. **H1 — Trigger produces the documented failure (in-place probe failure on same revision).** With the baseline revision Healthy and serving HTTP 200, `az containerapp ingress update --target-port 9999` flips the app-level ingress configuration. Within `trigger.sh`'s 420 s polling budget (tuned from a 2026-06-23 measurement of 261 s wall clock from break command to non-Healthy transition; the platform applies a probe retry budget before reclassifying the revision and the exact threshold is not publicly documented) the platform startup probe (now targeting port 9999) fails repeatedly, the same revision (`latestRevisionName` unchanged) transitions from `Healthy` to non-`Healthy`, and HTTP requests to the FQDN return non-200 codes. `ContainerAppSystemLogs_CL` records probe / deployment failure events for the affected revision in the break window.
2. **H2 — Fix restores the same revision in place.** After `az containerapp ingress update --target-port 8000` (which also modifies the same revision in place, no new revision created), within 240 s the same revision (`latestRevisionName` still unchanged) returns to `Healthy`, the FQDN starts returning HTTP 200 again, and `configuration.ingress.targetPort` reads `8000`. This is the canonical "path b" in-place recovery.

If both hold, the lab proves that ingress `targetPort` is the single controlling variable for this failure mode AND that the recovery path is in-place on the same revision (not a new-revision rollout). The resource group, the Container Apps environment, the ACR registry, the registry credentials (ACR admin user), the workload image, and the container's listening port (8000) are all held constant across the failing state and the recovered state; the only experimental variable is `configuration.ingress.targetPort`.

> **Why this lab's H1 gate is health-state + curl + KQL and not deployment-level.** The other labs in this evidence pack that test pre-revision failures (e.g., `acr-pull-failure`) use a deployment-level H1 gate because no revision is ever created and no rows are emitted into `ContainerAppSystemLogs_CL`. Revision failover is structurally different: a revision IS created and IS initially Healthy, and the workload IS serving requests before the break. The failure mode is purely observational on the active revision (probe failure + curl regression + KQL probe-failure rows) rather than a deployment error message.

> **Why the lab uses ACR admin user and not managed identity.** The point of this lab is to prove that ingress `targetPort` is the controlling variable, not the registry credential mechanism. Using ACR admin user (enabled in Bicep, password set via `az containerapp registry set`) keeps the credential path uniform across the failing state and the recovered state; the same revision (same image, same digest, same credentials) is probed in both states, so the difference in health cannot be attributed to a credential issue.

## Structure

```text
labs/revision-failover/
├── infra/main.bicep      # LAW + Container Apps env (appLogsConfiguration populated) + ACR (Basic, admin user) + 1 Container App with placeholder image and ingress.targetPort=8000
├── infra/main.json       # ARM JSON compiled from main.bicep
├── workload/Dockerfile   # python:3.11-slim + Flask + Gunicorn on :8000
├── workload/app.py       # Flask app exposing GET / returning HTTP 200 "hello from revision failover lab"
├── workload/requirements.txt
├── trigger.sh            # Phases 1-12: az acr build + az containerapp registry set + az containerapp update --image (baseline) + revision-Healthy poll + baseline curl + ingress update --target-port 9999 (break) + post-break health poll + post-break curl + KQL probe-failures + H1 gate JSON
├── verify.sh             # Phases 13-22: az containerapp ingress update --target-port 8000 (in-place fix) + revision-Healthy poll on same revision + post-fix curl + post-fix containerapp show + KQL recovery events + H2 gate JSON + metadata
├── cleanup.sh            # Delete the resource group
└── evidence/             # Captured CLI evidence
    ├── 00-trigger-run.txt                              # Full trigger.sh stdout/stderr
    ├── 00-verify-run.txt                               # Full verify.sh stdout/stderr
    ├── 00-cleanup-run.txt                              # Full cleanup.sh stdout/stderr
    ├── 01-acr-build-result.txt                         # Phase 1: az acr build streaming log (the build log is plain text — az acr build does not honor --output json)
    ├── 02-containerapp-update-baseline.json            # Phase 2: az containerapp update result establishing baseline (image=labrevision:v1, registry credentials attached via separate `registry set` call per CLI 2.71.0+ argument-conflict rule)
    ├── 03-containerapp-show-baseline.json              # Phase 4: az containerapp show post-baseline (expect targetPort=8000, healthState=Healthy, activeRevisionsMode=Single)
    ├── 04-revision-list-baseline.json                  # Phase 5: az containerapp revision list baseline (expect 1 active revision Healthy at 100% traffic)
    ├── 05-curl-baseline.txt                            # Phase 6: curl baseline FQDN (expect HTTP 200)
    ├── 06-containerapp-ingress-update-broken.json      # Phase 7: az containerapp ingress update --target-port 9999 result (BREAK)
    ├── 07-revision-list-after-break.json               # Phase 9: revision list post-break (expect same revision name, healthState=Degraded or similar non-Healthy state)
    ├── 08-containerapp-show-after-break.json           # Phase 9: containerapp show post-break (expect targetPort=9999, latestRevisionName=baseline)
    ├── 09-system-logs-probe-failures.json              # Phase 10: az monitor log-analytics query for ContainerAppSystemLogs_CL probe/deployment failure events in the break window (expect >=1 row with Reason_s=ProbeFailed and Log_s="Probe of StartUp failed with status code: 1" on the affected revision; the Portal Diagnose-and-Solve flyout text "TargetPort 9999 does not match the listening port 8000" is rendered separately in the Portal blade and is preserved as PNG 03 in the 2026-06-03 section of docs/troubleshooting/lab-guides/revision-failover.md)
    ├── 10-curl-after-break.txt                         # Phase 11: curl post-break FQDN (expect non-200 or timeout)
    ├── 11-h1-gate.json                                 # Phase 12: parsed H1 gate classification (expect revision_failover_broken_revision_unhealthy)
    ├── 12-containerapp-ingress-update-fix.json         # Phase 14: az containerapp ingress update --target-port 8000 result (FIX, in-place on same revision)
    ├── 13-revision-list-after-fix.json                 # Phase 16: revision list post-fix (expect same revision name, healthState=Healthy)
    ├── 14-containerapp-show-after-fix.json             # Phase 17: containerapp show post-fix (expect targetPort=8000, latestRevisionName=baseline, same name as Phase 4)
    ├── 15-curl-after-fix.txt                           # Phase 18: curl post-fix FQDN (expect HTTP 200)
    ├── 16-system-logs-recovery.json                    # Phase 19: az monitor log-analytics query for ContainerAppSystemLogs_CL in the fix window
    ├── 17-h2-gate.json                                 # Phase 20: parsed H2 gate classification (expect revision_failover_recovered_in_place_no_new_revision)
    ├── 18-cli-versions.json                            # Post-run: `az version`
    ├── 19-cli-containerapp-ext.json                    # Post-run: containerapp extension version
    ├── 20-region.json                                  # Post-run: deployment region
    └── 21-deployment-outputs.json                      # Post-run: `properties.outputs` of the Bicep deployment (six outputs: containerAppName, containerAppUrl, containerRegistryName, containerRegistryLoginServer, environmentName, logAnalyticsWorkspaceName — the LAW customer ID is queried separately via `az monitor log-analytics workspace show --query customerId`)
```

## Quick Start

These commands assume the working directory is the repository root. All `az` invocations pin `--subscription` explicitly to immunize the run against Azure CLI default-subscription drift, and the deployment is given the explicit name `main` so the deployment resource itself can be inspected deterministically (its `properties.outputs` is populated by Bicep with all six resource names). Total wall-clock runtime is approximately 10-18 minutes (3 min Bicep deploy + 4-9 min trigger including the variable wait for non-Healthy transition under the 420 s budget + 1-2 min verify including 240 s Healthy-poll budget for in-place recovery + 1 min cleanup initiation). The 2026-06-23 reproduction ran end-to-end in ~10 minutes (3 min deploy + 6 min trigger including a 261 s wait for non-Healthy + 1 min verify with 21 s wait for Healthy + 1 min cleanup), but the break time is platform-variable so plan for the longer end of the range.

```bash
# 1) Base inputs.
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-revision"
export LOCATION="koreacentral"

# 2) Provision the resource group and lab infra. The deployment is expected to succeed (the
#    placeholder Container App image used at deploy time is later replaced by trigger.sh).
az group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --location "$LOCATION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --template-file ./labs/revision-failover/infra/main.bicep \
    --parameters baseName="labrevision"

# 3) Derive the resource names the scripts need from the deployment outputs.
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
    --query "properties.outputs.containerRegistryName.value" \
    --output tsv)
export ACR_LOGIN_SERVER=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.containerRegistryLoginServer.value" \
    --output tsv)
export WORKSPACE_CUSTOMER_ID=$(az monitor log-analytics workspace show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --workspace-name "$(az deployment group show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name main \
        --query "properties.outputs.logAnalyticsWorkspaceName.value" \
        --output tsv)" \
    --query "customerId" \
    --output tsv)

# 4) Run the falsification experiment.
cd labs/revision-failover/
./trigger.sh 2>&1 | tee evidence/00-trigger-run.txt   # Build custom image, deploy baseline Healthy, flip ingress targetPort 8000->9999, poll for non-Healthy, capture curl + KQL evidence (expect revision_failover_broken_revision_unhealthy)
./verify.sh  2>&1 | tee evidence/00-verify-run.txt    # Apply in-place fix (targetPort 9999->8000), poll for Healthy recovery on same revision, capture curl + KQL evidence (expect revision_failover_recovered_in_place_no_new_revision)
./cleanup.sh 2>&1 | tee evidence/00-cleanup-run.txt   # Delete the resource group (async, --no-wait)
```

## What this lab demonstrates

- The Container Apps environment is provisioned by `infra/main.bicep` with `appLogsConfiguration.destination='log-analytics'` so that `ContainerAppSystemLogs_CL` ingests platform events. The H1 KQL query against this table is expected to return at least one row in the break window matching probe / deployment failure event families (`Reason_s contains 'Probe'` OR `'Deployment'` OR `'Unhealthy'` OR `'TargetPort'` OR `'Failed'`) for the affected revision; on the 2026-06-23 reproduction the rows have `Reason_s = ProbeFailed` and `Log_s = "Probe of StartUp failed with status code: 1"`. The user-facing smoking-gun string "Deployment Progress Deadline Exceeded. 0/1 replicas ready. The TargetPort 9999 does not match the listening port 8000." is rendered by the Portal Diagnose-and-Solve flyout (captured at PNG 03 in the 2026-06-03 section of [`docs/troubleshooting/lab-guides/revision-failover.md`](../../docs/troubleshooting/lab-guides/revision-failover.md)) and is not returned by this KQL query.
- The Container App is provisioned in `infra/main.bicep` with a placeholder image (`mcr.microsoft.com/k8se/quickstart:latest`) and `ingress.targetPort=8000`. `trigger.sh` Phase 1 calls `az acr build --image labrevision:v1 ./workload` to build and push the custom Flask + Gunicorn image (listening on 0.0.0.0:8000), and Phase 2 calls `az containerapp registry set` followed by `az containerapp update --image` to attach the ACR credential and swap to the custom image. The split into two `az` calls is required: Azure CLI 2.71.0+ rejects the combined `az containerapp update --image --registry-server --registry-username --registry-password` form with an argument-conflict error. Phase 3 polls the revision until `healthState=Healthy` (300 s budget, 10 s interval), confirming the baseline serves HTTP 200 (Phase 6).
- `trigger.sh` Phase 7 calls `az containerapp ingress update --target-port 9999`. This is the controlled break. Ingress is an **app-level** configuration (not a revision-level template field), so the update modifies the same revision in place. The platform startup probe is re-targeted to port 9999 where nothing is listening (the Gunicorn container still binds to 8000), and the revision transitions from `Healthy` to non-`Healthy` (`Degraded`, `Unhealthy`, or similar) after a platform-variable interval — the 2026-06-23 reproduction in `koreacentral` measured 261 s wall clock from the break command to `healthState=Unhealthy`, but the exact threshold depends on the probe retry budget the platform applies before reclassifying the revision and is not publicly documented. Phase 8 polls for the health transition with a 420 s budget; the measured `seconds_to_non_healthy` is recorded on the H1 gate JSON.
- `trigger.sh` Phase 10 queries `ContainerAppSystemLogs_CL` for the strict break window `[break_utc, break_end_utc]` filtered to probe / deployment failure event families for the baseline revision. Phase 11 issues a single curl to the FQDN and expects a non-200 code (typically `503` or `000` for timeout).
- `trigger.sh` Phase 12 emits the H1 gate JSON with one of three `gate_classification` values:
    - `revision_failover_broken_revision_unhealthy` — all four sub-gates pass: baseline curl 200 AND post-break targetPort 9999 AND revision non-Healthy AND post-break curl failed (expected here)
    - `revision_failover_break_did_not_materialize` — revision stayed Healthy AND curl 200 (H1 FALSIFIED — the probe-retarget did not cause the failure; verify.sh aborts)
    - `partial_observation_some_subgates_failed` — mixed sub-gate results (investigate before proceeding)
- The H1 gate JSON also records `revision_name_unchanged` as a separate observation (not a sub-gate) because revision name should stay the same across baseline → post-break (in-place app-level config change), but Azure may occasionally emit a new revision name for the same in-place change depending on `activeRevisionsMode` and the CLI version. Recording this as an observation rather than a hard sub-gate prevents brittle test failures on platform-version-dependent behavior.
- `verify.sh` Phase 14 calls `az containerapp ingress update --target-port 8000` — the mirror of the break action. Ingress is app-level, so this modifies the same revision in place; no new revision is created (this is the canonical "path b" recovery). Phase 15 polls the same revision name (read from the H1 gate JSON) up to 240 s for `healthState=Healthy`. Phase 18 issues a single curl to the FQDN and expects HTTP 200.
- `verify.sh` Phase 19 queries `ContainerAppSystemLogs_CL` for the fix window `[fix_utc, recovery_end_utc]` for the same revision. The expected outcome inverts: probe success / revision-Healthy events instead of probe failures. The query is informational (not gated) because the controlling signal for H2 is the revision health state + curl 200 + targetPort 8000 combination, not the KQL row count.
- `verify.sh` Phase 20 emits the H2 gate JSON with one of four `gate_classification` values:
    - `revision_failover_recovered_in_place_no_new_revision` — all four sub-gates pass: post-fix revision Healthy AND same revision name as baseline AND curl 200 AND targetPort 8000 (canonical path b; expected here)
    - `revision_failover_recovered_via_new_revision` — Healthy + curl 200 + targetPort 8000 but revision name DIFFERS from baseline (alternative recovery path, accepted as alternative PASS; the docs lab guide calls this "path a")
    - `revision_failover_did_not_recover` — revision is still non-Healthy OR curl still fails OR targetPort still 9999 after 240 s poll budget (H2 FALSIFIED)
    - `partial_observation_some_subgates_failed` — mixed sub-gate results (investigate)
- The pass/fail logic encodes three outcomes plus one invalid-run guard:
    - **H1 PASS + H2 PASS** ⇒ the falsification hypothesis is SUPPORTED. `verify.sh` exits 0.
    - **H1 FALSIFIED in `trigger.sh`** (`gate_classification == revision_failover_break_did_not_materialize`) ⇒ the probe-retarget unexpectedly did not cause the failure. `verify.sh` exits 1 (INVALID RUN — cannot test the fix because the baseline failure state did not materialize).
    - **H2 FALSIFIED in `verify.sh`** (`gate_classification == revision_failover_did_not_recover`) ⇒ the in-place fix did not restore the revision to Healthy. `verify.sh` exits 2.
    - **INVALID RUN** (a required environment variable is unset, `az acr build` failed, the trigger.sh evidence file is missing, or the post-fix FQDN is empty) ⇒ exit 1.

## Why the lab uses in-place ingress flip (path b) and not a new-revision rollout (path a)

The existing 2026-06-03 Portal capture sequence for this lab documents two recovery paths: **path a** (deploy a fresh image with `az containerapp update --image`, which creates a new revision `--0000002` that becomes the active revision while the broken `--0000001` is deactivated) and **path b** (flip ingress targetPort back to 8000 with `az containerapp ingress update`, which modifies the same revision in place and recovers the original `--0000001`). Both paths recover the app, but they test different platform behaviors. This 2026-06-23 evidence pack focuses on **path b** because:

1. It directly tests the claim that ingress is an app-level configuration (not revision-level), which is the controlling variable for the H1 failure mode. If path b did not work (i.e., the platform required a new revision to pick up the targetPort change), the entire premise of the H1 break would be wrong.
2. It is the cheapest recovery (no new revision means no new container image pull, no startup time, no traffic shift; the existing replica just gets its probe re-targeted).
3. It validates the in-place-recovery promise for the `b_same_revision_name_recovered` sub-gate on H2. If an operator sees in production that an ingress misconfiguration broke their revision, they should know that flipping it back is sufficient — they do not need to ship a new image.

The H2 gate accepts path a (`revision_failover_recovered_via_new_revision`) as an alternative PASS for completeness, but the canonical expected outcome is path b.

## Why the experiment uses a custom Flask + Gunicorn image listening on port 8000

This lab is the entry point of the revision-failover scenario in the playbook chain. Using a custom image (rather than `mcr.microsoft.com/k8se/quickstart` or `containerapps-helloworld`) is required because the experiment depends on a deterministic, known listening port (8000). The placeholder image used in `infra/main.bicep` (`mcr.microsoft.com/k8se/quickstart:latest`) listens on port 80, but the Bicep declares `ingress.targetPort=8000`; this mismatch is intentionally tolerated at deploy time because Phase 2 swaps to the custom Flask + Gunicorn image (listening on 0.0.0.0:8000) before the baseline-Healthy poll runs. The workload itself is intentionally minimal (Flask + Gunicorn on `:8000`, `GET /` returns 200 with `"hello from revision failover lab"`) so the focus stays on the platform behavior (ingress targetPort → startup probe → revision health), not on the application.

## Cost notes

- Resources provisioned: 1 Log Analytics workspace (PerGB, 30-day retention), 1 Container Apps Environment (Consumption), 1 ACR (Basic SKU), 1 Container App (`minReplicas: 1, maxReplicas: 2`, `0.5 vCPU`, `1 Gi` memory, `activeRevisionsMode: Single`).
- No public IP, no private endpoint, no VNet integration.
- The lab runs end-to-end in approximately 14 minutes. The Container App is held at 1 replica throughout (no scale-out is exercised; this lab is about probe/health behavior, not scaling).
- ACR Basic is approximately USD $0.167/day prorated to the hour; the lab is designed to run and clean up in under 15 minutes, so the ACR charge is approximately USD $0.001.
- `az acr build` runs on a Microsoft-hosted worker and is billed per-build-minute; the workload Dockerfile is small (python:3.11-slim base + Flask + Gunicorn install) and typically builds in under 1 minute, which is well under USD $0.01.
- Total cost for one end-to-end lab run is well under USD $0.05.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.

## What to record in your evidence write-up

When you ship this lab's evidence into a docs PR or a support ticket, ALWAYS record the following alongside the JSON captures:

- **Azure region** (e.g., `koreacentral`). Captured to `evidence/20-region.json`.
- **Azure CLI version** and **`containerapp` extension version** (`az version`, `az extension list --query "[?name=='containerapp']"`). Captured to `evidence/18-cli-versions.json` and `evidence/19-cli-containerapp-ext.json`.
- **Date of the run in UTC** (visible at the top of `00-trigger-run.txt` and `00-verify-run.txt`, and on the `utc_captured` field of `11-h1-gate.json` and `17-h2-gate.json`).
- **The exit code of `trigger.sh` and `verify.sh`** (0 = hypothesis supported, 1 = invalid run, 2 = falsified).
- **The deployment outputs blob** captured to `evidence/21-deployment-outputs.json`. Six resource identifiers are returned by the Bicep template: Container App name and URL, ACR name and login server, environment name, and Log Analytics workspace name. The LAW customer ID is queried separately via `az monitor log-analytics workspace show --query customerId` because it is a resource property, not a Bicep output.
- **The break window UTC range** captured as `break_window.start_utc` / `end_utc` on `11-h1-gate.json` and the fix window as `fix_window.start_utc` / `end_utc` on `17-h2-gate.json`. The KQL queries in Phase 10 (probe failures) and Phase 19 (recovery events) use these exact windows; widening them risks pulling in noise from outside the experimental windows.
- **The revision-name observation** from both gates. `11-h1-gate.json` records `revision_name_unchanged` (expected `true` for in-place break), `baseline_revision_name`, and `post_break_revision_name`. `17-h2-gate.json` records `baseline_revision_name` and `post_fix_revision_name` and the `b_same_revision_name_recovered` sub-gate result. If `post_fix_revision_name` differs from `baseline_revision_name`, recovery happened via path a (new revision) instead of path b (in-place), and the gate classification will be `revision_failover_recovered_via_new_revision` instead of `revision_failover_recovered_in_place_no_new_revision`.

## Operator takeaway

This lab demonstrates that the Azure Container Apps platform treats ingress `targetPort` as an **app-level** configuration that modifies the active revision in place when changed via `az containerapp ingress update` — no new revision is created. When the targetPort is set to a value the workload is not listening on (e.g., 9999 when Gunicorn binds 8000), the platform startup probe begins failing repeatedly and the same revision transitions from `Healthy` to non-`Healthy` after a platform-variable interval (measured at 261 s on the 2026-06-23 reproduction in `koreacentral`; the platform applies a probe retry budget before reclassifying the revision and the exact threshold is not publicly documented). HTTP requests to the FQDN start failing because the platform deems the revision non-Healthy. The recovery path is symmetric and cheap: `az containerapp ingress update --target-port <correct-port>` modifies the same revision in place, the startup probe re-targets to the correct port where the container has been listening the whole time, and the same revision recovers to `Healthy` within ~30 s. No new image, no new revision, no traffic shift — just a probe re-target. The smoking-gun diagnostic for this failure mode is the Activity Log entry "Deployment Progress Deadline Exceeded. 0/1 replicas ready. The TargetPort 9999 does not match the listening port 8000." combined with the revision's `healthState` transitioning from `Healthy` to `Degraded` while `latestRevisionName` stays unchanged. The matching playbook is [`docs/troubleshooting/playbooks/platform-features/bad-revision-rollout-and-rollback.md`](../../docs/troubleshooting/playbooks/platform-features/bad-revision-rollout-and-rollback.md); reproduce locally with `./trigger.sh` and `./verify.sh` to validate it against your own environment before training on-call engineers.
