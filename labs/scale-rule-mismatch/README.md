# Lab: Scale Rule Mismatch

Reproducible **falsification** lab for the Azure Container Apps platform behavior when an HTTP scale rule is configured with a concurrency threshold far above the realistic concurrent load the workload receives.

The lab provisions one Container App with an HTTP scale rule of `concurrentRequests=500` and `maxReplicas=2`, then drives the app with 60 concurrent HTTPS requests sustained for 90 s against a CPU-busy `/load` endpoint. This lab observed (2026-06-22 reproduction in `koreacentral`) that the replica count stays at exactly 1 throughout the entire 90 s load window (samples at +15 s / +30 s / +60 s / +90 s all returned 1 replica), `ContainerAppSystemLogs_CL` records zero scale-up events for the active revision during the load window, and the platform appears to be ignoring the load. This is the documented KEDA HTTP add-on behavior, not a platform bug: 60 in-flight requests divided across the threshold of 500 produces zero pending scale events. The behavior is recovered by updating the scale rule to `concurrentRequests=10` and raising `maxReplicas` to 10, then re-running the identical load shape; the platform creates a new revision (`--0000002`), KEDA scales the new revision up to 7 replicas during the same 90 s load window, and `ContainerAppSystemLogs_CL` records 19 scale-event rows tied to the post-fix revision.

The lab tests two hypotheses:

1. **H1 — Trigger produces the documented failure (replicas capped under load).** With the HTTP scale rule configured as `concurrentRequests=500` and `maxReplicas=2`, and the workload receiving 60 concurrent requests sustained for 90 s, the pre-load replica count is 1, the replica count remains at 1 at +15 s / +30 s / +60 s / +90 s into the load window, and `ContainerAppSystemLogs_CL` records zero scale-event rows for the active revision in the load window.
2. **H2 — Fix restores scaling.** After `az containerapp update --scale-rule-metadata "concurrentRequests=10" --max-replicas 10` (which creates a new revision), within 5 minutes the new revision reaches `healthState=Healthy`, the same 60-concurrent / 90 s load shape against the same FQDN drives the replica count above 1 (observed maximum 7), and `ContainerAppSystemLogs_CL` records at least one scale-event row for the post-fix revision during the post-fix load window.

If both hold, the lab proves that the HTTP scale rule's `concurrentRequests` threshold (in combination with `maxReplicas`) is the single controlling variable for this failure mode. The resource group, the Container Apps environment, the ACR registry, the registry credentials (ACR admin user), the ingress configuration, the workload image, the load generator, and the load shape (60 concurrent for 90 s) are all held constant across the failing baseline and the recovered state; the only experimental variables are the `concurrentRequests` metadata value and the `maxReplicas` cap.

> **Why this lab's H1 gate is replica-count + KQL-attributed and not deployment-level.** The other labs in this evidence pack that test pre-revision failures (e.g., `acr-pull-failure`) use a deployment-level H1 gate because no revision is ever created and no rows are emitted into `ContainerAppSystemLogs_CL`. Scale rule mismatch is structurally different: a revision IS created and IS Healthy, and the workload IS serving requests; the failure mode is purely observational (no scale-out). The H1 gate therefore reads two replica-count signals (pre-load baseline of 1, samples during the load window) and one KQL signal (zero scale-event rows for the active revision in the load window) instead of a deployment error message.

> **Why the lab uses ACR admin user and not managed identity.** The point of this lab is to prove that the scale rule threshold is the controlling variable, not the registry credential mechanism. Using ACR admin user (enabled in Bicep, password set via `az containerapp registry set`) keeps the credential path uniform across the failing run and the recovered run; both revisions pull from the same ACR with the same admin credential, so the difference in scaling behavior cannot be attributed to a credential issue.

## Structure

```text
labs/scale-rule-mismatch/
├── infra/main.bicep      # LAW + Container Apps env (appLogsConfiguration populated) + ACR (Basic, admin user) + 1 Container App with placeholder image
├── infra/main.json       # ARM JSON compiled from main.bicep
├── workload/Dockerfile   # python:3.11-slim + Flask + Gunicorn on :8000
├── workload/app.py       # Flask app exposing GET /health and CPU-busy GET /load
├── workload/requirements.txt
├── trigger.sh            # Phases 1-9: az acr build + az containerapp update with mismatched scale rule + revision-Healthy poll + baseline replica capture + load generation + per-interval replica polling + post-load KQL + H1 gate JSON
├── verify.sh             # Phases 10-18: az containerapp update with corrected scale rule + revision-Healthy poll + post-fix replica capture + load generation + per-interval replica polling + post-fix KQL + H2 gate JSON + metadata
├── cleanup.sh            # Delete the resource group
└── evidence/             # Captured CLI evidence
    ├── 00-trigger-run.txt                            # Full trigger.sh stdout/stderr
    ├── 00-verify-run.txt                             # Full verify.sh stdout/stderr
    ├── 00-cleanup-run.txt                            # Full cleanup.sh stdout/stderr
    ├── 01-acr-build-result.txt                       # Phase 1: az acr build streaming log (the build log is plain text — az acr build does not honor --output json)
    ├── 02-containerapp-update-baseline.json          # Phase 2: az containerapp update result establishing baseline (image=labscale:v1, concurrentRequests=500, maxReplicas=2)
    ├── 03-containerapp-show-baseline.json            # Phase 4: az containerapp show post-update (expect scaleConfig.rules[0].http.metadata.concurrentRequests=500, maxReplicas=2)
    ├── 04-replicas-pre-load.json                     # Phase 5: az containerapp replica list pre-load (expect 1 replica)
    ├── 05-replicas-load-15s.json                     # Phase 7: replica list at load+15 s (expect 1 replica)
    ├── 06-replicas-load-30s.json                     # Phase 7: replica list at load+30 s (expect 1 replica)
    ├── 07-replicas-load-60s.json                     # Phase 7: replica list at load+60 s (expect 1 replica)
    ├── 08-replicas-load-90s.json                     # Phase 7: replica list at load+90 s (expect 1 replica)
    ├── 09-system-logs-scale-events-pre-fix.json      # Phase 8: az monitor log-analytics query for ContainerAppSystemLogs_CL scale events in the load window (expect 0 rows)
    ├── 10-h1-gate.json                               # Phase 9: parsed H1 gate classification (expect scale_rule_mismatch_replicas_capped)
    ├── 11-containerapp-update-fix.json               # Phase 11: az containerapp update applying the fix (concurrentRequests=10, maxReplicas=10) — creates new revision
    ├── 12-containerapp-show-after-fix.json           # Phase 13: az containerapp show post-fix (expect concurrentRequests=10, maxReplicas=10)
    ├── 13-replicas-pre-load-after-fix.json           # Phase 14: replica list post-fix pre-load (expect 1 replica after KEDA stabilizes)
    ├── 14-replicas-load-15s-after-fix.json           # Phase 16: replica list post-fix at load+15 s
    ├── 15-replicas-load-30s-after-fix.json           # Phase 16: replica list post-fix at load+30 s
    ├── 16-replicas-load-60s-after-fix.json           # Phase 16: replica list post-fix at load+60 s
    ├── 17-replicas-load-90s-after-fix.json           # Phase 16: replica list post-fix at load+90 s
    ├── 18-system-logs-scale-events-after-fix.json    # Phase 17: az monitor log-analytics query for ContainerAppSystemLogs_CL scale events in the post-fix load window (expect >=1 row)
    ├── 19-h2-gate.json                               # Phase 18: parsed H2 gate classification (expect scale_rule_fixed_replicas_scaled_events_observed)
    ├── 20-cli-versions.json                          # Post-run: `az version`
    ├── 21-cli-containerapp-ext.json                  # Post-run: containerapp extension version
    ├── 22-region.json                                # Post-run: deployment region
    └── 23-deployment-outputs.json                    # Post-run: `properties.outputs` of the Bicep deployment (container app name, ACR name, environment name, LAW name)
```

## Quick Start

These commands assume the working directory is the repository root. All `az` invocations pin `--subscription` explicitly to immunize the run against Azure CLI default-subscription drift, and the deployment is given the explicit name `main` so the deployment resource itself can be inspected deterministically (its `properties.outputs` is populated by Bicep with all six resource names). Total wall-clock runtime is approximately 15 minutes (3 min Bicep deploy + 4 min trigger + 6 min verify including 5 min Healthy-poll budget for the post-fix revision + 1 min cleanup initiation).

```bash
# 1) Base inputs.
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-scale"
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
    --template-file ./labs/scale-rule-mismatch/infra/main.bicep \
    --parameters baseName="labscale"

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
cd labs/scale-rule-mismatch/
./trigger.sh 2>&1 | tee evidence/00-trigger-run.txt   # Build custom image, apply mismatched scale rule, generate 60-concurrent / 90 s load, capture replica + KQL evidence (expect scale_rule_mismatch_replicas_capped)
./verify.sh  2>&1 | tee evidence/00-verify-run.txt    # Apply fix, generate identical load against post-fix revision, capture replica + KQL evidence (expect scale_rule_fixed_replicas_scaled_events_observed)
./cleanup.sh 2>&1 | tee evidence/00-cleanup-run.txt   # Delete the resource group (async, --no-wait)
```

## What this lab demonstrates

- The Container Apps environment is provisioned by `infra/main.bicep` with `appLogsConfiguration.destination='log-analytics'` so that `ContainerAppSystemLogs_CL` ingests platform events. The H1 KQL query against this table returns zero scale-event rows during the pre-fix load window (filter: `Reason_s startswith "Scal"` AND `RevisionName_s == latestRevisionName_at_trigger_time`) because KEDA's HTTP add-on computes zero pending scale events when 60 in-flight requests are divided across the threshold of 500.
- The Container App is provisioned in `infra/main.bicep` with a placeholder image (`mcr.microsoft.com/k8se/quickstart:latest`) and a placeholder scale rule. `trigger.sh` Phase 1 calls `az acr build --image labscale:v1 ./workload` to build and push the custom Flask + Gunicorn image, and Phase 2 calls `az containerapp update` to swap the image and apply the mismatched scale rule (`concurrentRequests=500`, `maxReplicas=2`). The placeholder-then-update pattern keeps the Bicep template self-contained and reproducible across environments.
- The workload exposes two endpoints. `GET /health` is a trivial 200 OK for the platform probe. `GET /load` is intentionally CPU-busy (a tight loop that holds the worker thread for approximately 1 second) so a single replica saturates quickly under concurrent load. This forces the test to depend on the scale rule rather than on app efficiency: at 60 concurrent requests the per-request latency degrades visibly, but KEDA still sees zero pending scale events because 60 is far below the configured threshold of 500.
- `trigger.sh` Phase 6 generates load with 60 concurrent background `curl` processes against `/load` and `wait`s for them, sustained for 90 s. The replica count is sampled at +15 s, +30 s, +60 s, and +90 s into the load window (`az containerapp replica list` followed by `--query "length(@)"`). The expected per-sample observation is 1 replica at every interval (replicas_observed.max_during_load = 1).
- `trigger.sh` Phase 8 queries `ContainerAppSystemLogs_CL` for the strict load window `[load_start_utc, load_end_utc]` filtered to scale-related `Reason_s` values for the active revision. The expected row count is 0. This is the KEDA-attribution leg of the H1 gate; combined with the per-sample replica count of 1, it rules out the alternative theory "KEDA tried to scale but the platform refused."
- `trigger.sh` Phase 9 emits the H1 gate JSON with one of three `gate_classification` values:
    - `scale_rule_mismatch_replicas_capped` — all three sub-gates pass: baseline 1 replica AND max-during-load <= 1 AND zero scale events (expected here)
    - `scale_rule_responded_unexpectedly` — max-during-load >= 2 (H1 FALSIFIED — the mismatched threshold unexpectedly produced scale events; verify.sh aborts)
    - `partial_observation_some_subgates_failed` — mixed sub-gate results (investigate before proceeding)
- `verify.sh` Phase 11 calls `az containerapp update --scale-rule-metadata "concurrentRequests=10" --max-replicas 10`. Updating any scale-rule flag on `az containerapp update` creates a new revision (`--0000002`), so verify.sh Phase 12 polls revision health on the new revision up to 5 minutes (10 s interval) until `healthState=Healthy`. Phase 14 waits an additional 30 s for KEDA's HTTP add-on to drain the old revision's replicas and stabilize on the new revision before sampling the post-fix baseline replica count (KEDA may transiently hold >1 replica during revision swap before settling at minReplicas=1; the 30 s drain prevents this transient from being captured as the baseline).
- `verify.sh` Phase 15 generates the identical load shape as `trigger.sh` Phase 6 (60 concurrent `curl` against `/load`, 90 s sustained) against the post-fix FQDN. Phase 16 samples the replica count at the same intervals (+15 s, +30 s, +60 s, +90 s). The expected observation is the replica count climbing from 1 to >=2 by +15 s and reaching at least 5-7 by +60 s, with a `max_during_load >= 2` sub-gate threshold.
- `verify.sh` Phase 17 queries `ContainerAppSystemLogs_CL` for the strict post-fix load window filtered to scale-related `Reason_s` values for the post-fix revision. The expected row count is `>= 1` (typical observation is 15-20 rows of `AssigningReplica` / scale-up events). This is the KEDA-attribution leg of the H2 gate.
- `verify.sh` Phase 18 emits the H2 gate JSON with one of four `gate_classification` values:
    - `scale_rule_fixed_replicas_scaled_events_observed` — all three sub-gates pass: post-fix revision Healthy AND max-during-load >= 2 AND scale events >= 1 (expected here)
    - `scale_rule_fixed_replicas_scaled_no_events` — Healthy + replicas scaled but no KEDA attribution rows (partial pass; the replica count is the controlling signal, so this is treated as a soft pass with a follow-up note)
    - `scale_rule_fixed_replicas_did_not_scale` — Healthy but max-during-load < 2 (H2 FALSIFIED — the fix did not restore scaling)
    - `fix_revision_unhealthy` — Healthy poll exceeded 5 minutes (H2 FALSIFIED — the post-fix revision did not become Healthy)
- The pass/fail logic encodes three outcomes plus one invalid-run guard:
    - **H1 PASS + H2 PASS** ⇒ the falsification hypothesis is SUPPORTED. `verify.sh` exits 0.
    - **H1 FALSIFIED in `trigger.sh`** (`gate_classification == scale_rule_responded_unexpectedly`) ⇒ the mismatched threshold unexpectedly produced scale events. `verify.sh` exits 1 (INVALID RUN — cannot test the fix because the baseline failure state did not materialize).
    - **H2 FALSIFIED in `verify.sh`** (`gate_classification == scale_rule_fixed_replicas_did_not_scale` or `fix_revision_unhealthy`) ⇒ the fix did not restore scaling. `verify.sh` exits 2.
    - **INVALID RUN** (a required environment variable is unset, `az acr build` failed, the trigger.sh evidence file is missing, or the post-fix provisioningState did not reach Succeeded) ⇒ exit 1.

## Why the lab uses 60 concurrent requests and not `hey -z 8m -c 80`

A previous capture run for this lab used `hey -z 8m -c 80` (80 concurrent for 8 minutes) generated by a separate load-generator host. That works, but it has three reproducibility problems: it requires `hey` to be installed on the operator's machine (not always available), it costs more (8 minutes of replica time at maxReplicas=10 is 10x the cost of 90 seconds), and the 8-minute window makes the KQL load-window filter loose enough that benign teardown noise from previous revisions can leak in. The current 60-concurrent / 90 s shape is generated by 60 background `curl` processes against `/load` in `trigger.sh` and `verify.sh` directly (no external load generator), keeps the H1 and H2 load windows tight (under 2 minutes each), and costs well under USD $0.01. The trade-off is that 60 concurrent is less than 80 concurrent, but the H1 gate's controlling variable is still the threshold (500 >> 60, so KEDA still sees zero pending scale events) and the H2 gate still observes 7 replicas at peak — well above the `>= 2` sub-gate threshold.

## Why the experiment uses a custom Flask + Gunicorn image with a CPU-busy `/load` endpoint

This lab is the entry point of the scale-rule misconfiguration scenario in the playbook chain. Using a custom image (rather than `mcr.microsoft.com/k8se/quickstart` or `containerapps-helloworld`) is required because the CPU-busy `/load` endpoint is essential for forcing a single replica to saturate quickly. A trivial 200-OK endpoint would not produce visible per-request latency under 60 concurrent, which would make it ambiguous whether the test was actually exercising the scale rule or just hitting a never-saturating endpoint. The workload itself is intentionally minimal (Flask + Gunicorn on `:8000`, `GET /health` returns 200, `GET /load` runs a tight 1-second CPU loop and then returns 200) so the focus stays on the scale rule behavior, not on the application.

## Cost notes

- Resources provisioned: 1 Log Analytics workspace (PerGB, 30-day retention), 1 Container Apps Environment (Consumption), 1 ACR (Basic SKU), 1 Container App (initially `minReplicas: 1, maxReplicas: 2`, then `minReplicas: 1, maxReplicas: 10` post-fix; `0.5 vCPU`, `1 Gi` memory).
- No public IP, no private endpoint, no VNet integration.
- Pre-fix load window: 1 replica running for 90 s under load, then 5 minutes of post-load capture. ACR Basic is approximately USD $0.167/day prorated to the hour; the lab is designed to run end-to-end and clean up in under 15 minutes, so the ACR charge is approximately USD $0.001.
- Post-fix load window: up to 7 replicas (observed max) running for 90 s under load; each replica is `0.5 vCPU`, `1 Gi` memory. At Consumption pricing this is well under USD $0.01 for the 90 s burst.
- `az acr build` runs on a Microsoft-hosted worker and is billed per-build-minute; the workload Dockerfile is small (python:3.11-slim base + Flask + Gunicorn install) and typically builds in under 1 minute, which is well under USD $0.01.
- Total cost for one end-to-end lab run is well under USD $0.05.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.

## What to record in your evidence write-up

When you ship this lab's evidence into a docs PR or a support ticket, ALWAYS record the following alongside the JSON captures:

- **Azure region** (e.g., `koreacentral`). Captured to `evidence/22-region.json`.
- **Azure CLI version** and **`containerapp` extension version** (`az version`, `az extension list --query "[?name=='containerapp']"`). Captured to `evidence/20-cli-versions.json` and `evidence/21-cli-containerapp-ext.json`.
- **Date of the run in UTC** (visible at the top of `00-trigger-run.txt` and `00-verify-run.txt`, and on the `utc_captured` field of `10-h1-gate.json` and `19-h2-gate.json`).
- **The exit code of `trigger.sh` and `verify.sh`** (0 = hypothesis supported, 1 = invalid run, 2 = falsified).
- **The deployment outputs blob** captured to `evidence/23-deployment-outputs.json`. The six resource names (Container App, ACR, ACR login server, environment, LAW, LAW customer ID) are derived from these outputs.
- **The load window UTC range** for both H1 and H2. These are recorded as `load_window.start_utc` / `end_utc` on `10-h1-gate.json` and `post_fix_load_window.start_utc` / `end_utc` on `19-h2-gate.json`. The KQL queries in Phase 8 and Phase 17 use these exact windows; widening them risks pulling in benign teardown noise from previous revisions.
- **The per-revision attribution** of scale events. Both `09-system-logs-scale-events-pre-fix.json` (expected empty) and `18-system-logs-scale-events-after-fix.json` (expected >=1 row) filter on `RevisionName_s == ${ACTIVE_REVISION_NAME}` to prevent cross-revision contamination (the post-fix update creates a new revision, and benign teardown of the previous revision can produce `ScaledObjectCheckFailed` / `FailedGetScale` warnings that are NOT scale-up events).

## Operator takeaway

This lab observed (2026-06-22 reproduction in `koreacentral`) that when an HTTP scale rule is configured with a `concurrentRequests` threshold (500) far above realistic in-flight concurrency (60), the Azure Container Apps platform produces a deterministic, observation-only failure signature: the replica count stays pinned at `minReplicas` throughout the load window (1 / 1 / 1 / 1 at +15 s / +30 s / +60 s / +90 s), no KEDA scale-up events are recorded in `ContainerAppSystemLogs_CL`, and operators see degrading per-request latency without any platform error or warning. Microsoft Learn documents that `concurrentRequests` is the average target across all replicas ([Set scaling rules in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)); the consequence of setting it far above observed concurrency is what this lab demonstrates. The fix is to update the scale rule with a threshold proportional to observed in-flight concurrency and raise `maxReplicas` to allow horizontal scale-out: `az containerapp update --scale-rule-name http-rule --scale-rule-type http --scale-rule-metadata concurrentRequests=10 --max-replicas 10`. After the fix, KEDA scales the post-fix revision to 7 replicas under the identical 60-concurrent / 90 s load, and `ContainerAppSystemLogs_CL` records 19 scale-event rows attributed to the post-fix revision. The cheapest live-incident diagnostic for this failure mode is the combination of (1) the replica count from `az containerapp replica list --query "length(@)"` under sustained load (expected to be > 1 if scaling is working) and (2) a tight-window KQL query against `ContainerAppSystemLogs_CL` filtered to `RevisionName_s == <active-revision>` AND `Reason_s startswith "Scal"` (expected to return at least one row per scale-up event); either alone is suggestive, but the two together are the smoking gun. The matching playbook is [`docs/troubleshooting/playbooks/scaling-and-runtime/http-scaling-not-triggering.md`](../../docs/troubleshooting/playbooks/scaling-and-runtime/http-scaling-not-triggering.md); reproduce locally with `./trigger.sh` and `./verify.sh` to validate it against your own environment before training on-call engineers.
