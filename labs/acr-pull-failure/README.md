# Lab: ACR Image Pull Failure

Reproducible **falsification** lab for the Azure Container Apps platform behavior when a Container App is configured with an image tag that does not exist in its referenced Azure Container Registry.

The lab provisions one Container App with `image: '${ACR_LOGIN_SERVER}/labacr:does-not-exist'` (a tag that is never pushed to the registry), which causes the platform to fail manifest resolution during deployment. This lab observed (2026-06-22 reproduction in `koreacentral`) that the Bicep `az deployment group create` call exits with `DeploymentFailed` and an error message containing `MANIFEST_UNKNOWN: manifest tagged by "does-not-exist" is not found`, the Container App resource is created in `provisioningState=Failed` with `latestRevisionName=null`, no revision row is materialized (`az containerapp revision list` returns `[]`), and `ContainerAppSystemLogs_CL` never ingests any rows for the app (no container ever started). The deployment-level failure signature is recovered by building a known-good image with `az acr build --image labacr:v1` and updating the app via `az containerapp update --image <acr>/labacr:v1`; the platform then creates a Healthy revision serving 100% of traffic, and `ContainerAppSystemLogs_CL` begins ingesting normal rows.

The lab tests two hypotheses:

1. **H1 — Trigger produces the documented failure (deployment-level).** After `az deployment group create` with the bad image tag, the deployment exits with `provisioningState=Failed` whose error message contains `MANIFEST_UNKNOWN`, the Container App resource exists with `provisioningState=Failed` and `latestRevisionName=null`, `az containerapp revision list` returns an empty array, and `az acr repository list` does not list a `labacr` repository.
2. **H2 — Fix restores recovery.** After `az acr build --image labacr:v1` (which succeeds and creates the `labacr` repository in ACR) and `az containerapp update --image <acr>/labacr:v1` (which succeeds), within 5 minutes the latest revision reaches `healthState=Healthy` with `trafficWeight=100`, the assigned FQDN returns HTTP 200 on at least 8/10 sequential HTTPS requests, and `ContainerAppSystemLogs_CL` begins ingesting normal platform events in the strictly post-fix UTC window.

If both hold, the lab proves that the existence of the referenced image tag in ACR is the single controlling variable for this failure mode. The resource group, the Container Apps environment, the ACR registry, the registry credentials (ACR admin user via the `registry-password` secret), the ingress configuration, and the Log Analytics workspace are all held constant across the failing baseline and the recovered state; the only experimental variable is whether the tag exists in the registry.

> **Why this lab's H1 gate is deployment-level and not KQL-level.** The other labs in this evidence pack (e.g., `ingress-target-port-mismatch`, `cpu-throttling`, `memory-leak-oomkilled`) test failure modes where the container starts and the platform emits attribution rows into `ContainerAppSystemLogs_CL` that a KQL query can detect. ACR pull failure is structurally different: when the manifest lookup fails, the platform never creates a revision, never starts a container, and never emits any rows into the system log table. The `ContainerAppSystemLogs_CL` table is not even materialized in the Log Analytics workspace during the failed-deployment window. The H1 gate therefore reads three deployment-level signals — the deployment's `properties.error.message`, the Container App's `provisioningState` and `latestRevisionName`, and the empty `az containerapp revision list` result — instead of a KQL row count. Operators searching Log Analytics for evidence of this failure mode will find an empty workspace and may incorrectly conclude that diagnostics are misconfigured; this lab documents that absence as evidence.

> **Why the lab uses ACR admin user and not managed identity.** The point of this lab is to prove that the image tag is the controlling variable, not the registry credential mechanism. Using ACR admin user (enabled in Bicep, password stored in the `registry-password` secret) keeps the credential path uniform across the failing run and the recovered run; the v1 image pull succeeds with the same admin credential that was already present during the bad-tag run, so the failure cannot be attributed to a credential issue. A managed-identity variant of this failure mode (with the `AcrPull` role missing) is documented separately in [`docs/troubleshooting/playbooks/startup-and-provisioning/image-pull-failure.md`](../../docs/troubleshooting/playbooks/startup-and-provisioning/image-pull-failure.md) and is not part of this scripted reproduction.

## Structure

```text
labs/acr-pull-failure/
├── infra/main.bicep      # LAW + Container Apps env (appLogsConfiguration populated) + ACR (Basic, admin user) + 1 Container App referencing labacr:does-not-exist
├── infra/main.json       # ARM JSON compiled from main.bicep
├── workload/Dockerfile   # python:3.11-slim + Flask + Gunicorn on :8000
├── workload/app.py       # Flask app exposing GET / and GET /health
├── workload/requirements.txt
├── trigger.sh            # Phases 1-6: capture deployment failure result + per-operation MANIFEST_UNKNOWN, container app state, revision list, ACR repository list, system log KeyError, activity log entries (deployment-level H1 gate)
├── verify.sh             # Phases 7-16: az acr build + az containerapp update + Healthy poll + post-fix container app state + revision list + ACR repository list + curl FQDN + optional post-fix KQL + metadata (H2 gate)
├── cleanup.sh            # Delete the resource group
└── evidence/             # Captured CLI evidence
    ├── 00-trigger-run.txt                            # Full trigger.sh stdout/stderr
    ├── 00-verify-run.txt                             # Full verify.sh stdout/stderr
    ├── 01-deployment-result.json                     # Phase 1: az deployment group show with provisioningState=Failed + error.message (MANIFEST_UNKNOWN is NOT here — `details` is null at the leaf)
    ├── 01-deployment-operations-failed.json          # Phase 1b: az deployment operation group list — per-operation statusMessage.error.message carries the MANIFEST_UNKNOWN smoking gun
    ├── 02-containerapp-show-baseline.json            # Phase 2: az containerapp show (expect provisioningState=Failed, latestRevisionName=null)
    ├── 03-revisions-list-baseline.json               # Phase 3: az containerapp revision list (expect [])
    ├── 04-acr-repository-list-baseline.json          # Phase 4: az acr repository list (expect labacr absent)
    ├── 05-system-logs-show-error.txt                 # Phase 5: az containerapp logs show --type system (expect KeyError: 'eventStreamEndpoint')
    ├── 06-activity-log-failed.json                   # Phase 6: az monitor activity-log list filtered to ContainerApps Failed operations
    ├── 06-h1-gate.json                               # Phase 6: parsed deployment-level gate classification (expect deployment_failed_manifest_unknown)
    ├── 07-acr-build-result.json                      # Phase 8: az acr build --image labacr:v1 result
    ├── 08-containerapp-update-result.json            # Phase 9: az containerapp update --image <acr>/labacr:v1 result
    ├── 09-containerapp-show-after-fix.json           # Phase 11: az containerapp show post-fix (expect provisioningState=Succeeded, latestRevisionName populated)
    ├── 10-revisions-list-after-fix.json              # Phase 12: az containerapp revision list (expect Healthy + traffic=100)
    ├── 11-acr-repository-list-after-fix.json         # Phase 13: az acr repository list (expect labacr present)
    ├── 12-curl-after-fix.json                        # Phase 14: 10 HTTPS request results to recovered FQDN (expect >=8/10 HTTP 200)
    ├── 13-kql-after-fix.json                         # Phase 15: parsed KQL ContainerAppSystemLogs_CL post-fix sanity check (expect ingestion or graceful "table not materialized" gate)
    ├── 13-kql-after-fix-raw.txt                      # Phase 15: raw az monitor log-analytics query stdout
    ├── 14-h2-gate.json                               # Phase 16: parsed H2 gate classification (expect revision_healthy_traffic_100_curl_ok)
    ├── 20-cli-versions.json                          # Post-run: `az version`
    ├── 21-cli-containerapp-ext.json                  # Post-run: containerapp extension version
    ├── 22-region.json                                # Post-run: deployment region
    └── 23-deployment-outputs.json                    # Post-run: `properties.outputs` of the failed Bicep deployment (null in failed state — captured intentionally to document this platform behavior)
```

## Quick Start

These commands assume the working directory is `labs/acr-pull-failure/`. All `az` invocations pin `--subscription` explicitly to immunize the run against Azure CLI default-subscription drift, and the deployment is given the explicit name `main` so the deployment resource itself can be inspected deterministically (its `properties.outputs` is `null` in the Failed state — the platform only populates outputs on `Succeeded` deployments — so the scripts derive resource names from `az containerapp list` / `az acr list` / `az monitor log-analytics workspace list` against the dedicated RG instead). The `|| true` after `az deployment group create` is mandatory because the deployment is expected to fail with `MANIFEST_UNKNOWN` — that failure is the trigger this lab observes, not an error to abort on. Total wall-clock runtime is approximately 12 minutes (3 min deploy attempt + 2 min trigger + 6 min verify including 5 min Healthy-poll budget + 1 min cleanup initiation).

```bash
cd labs/acr-pull-failure/

# 1) Base inputs.
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-acr"
export LOCATION="koreacentral"

# 2) Provision the resource group and lab infra. The deployment is EXPECTED to fail with MANIFEST_UNKNOWN;
#    `|| true` lets the script proceed past the failure so the failed-deployment state can be captured.
az group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --location "$LOCATION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --template-file ./infra/main.bicep \
    --parameters baseName="labacr" || true

# 3) Derive the resource names the scripts need. We cannot use `az deployment group show
#    --query "properties.outputs"` here because `properties.outputs` is null when the
#    deployment is in Failed state (the platform only populates outputs on Succeeded
#    deployments). Instead, we list the resources directly: the RG is dedicated to this
#    lab and contains exactly one Container App, one ACR, and one Log Analytics workspace,
#    so a single-row query is unambiguous.
export APP_NAME=$(az containerapp list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --query "[0].name" \
    --output tsv)
export ACR_NAME=$(az acr list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --query "[0].name" \
    --output tsv)
export ACR_LOGIN_SERVER=$(az acr list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --query "[0].loginServer" \
    --output tsv)
export WORKSPACE_CUSTOMER_ID=$(az monitor log-analytics workspace list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --query "[0].customerId" \
    --output tsv)

# 4) Run the falsification experiment.
./trigger.sh 2>&1 | tee evidence/00-trigger-run.txt   # Capture deployment-level failure signals + activity log evidence (expect deployment_failed_manifest_unknown)
./verify.sh  2>&1 | tee evidence/00-verify-run.txt    # az acr build + az containerapp update + Healthy poll + 10 curl probes + post-fix metadata (expect revision_healthy_traffic_100_curl_ok)
./cleanup.sh                                          # Delete the resource group
```

## What this lab demonstrates

- The Container Apps environment is provisioned by `infra/main.bicep` with `appLogsConfiguration.destination='log-analytics'` so that `ContainerAppSystemLogs_CL` would ingest platform events if any container ever started. In this failure mode no container starts, so the table is never materialized in the workspace during the failed-deployment window. This is an observable absence, not a configuration mistake.
- The Container App is provisioned with `image: '${containerRegistry.properties.loginServer}/${baseName}:does-not-exist'`. The Bicep deployment terminates with `DeploymentFailed` and an error message containing `MANIFEST_UNKNOWN: manifest tagged by "does-not-exist" is not found` before the platform creates a revision row. The Container App resource itself is created with `provisioningState=Failed` and `latestRevisionName=null` so the operator can inspect it from the Portal Overview blade; the Revisions blade renders "No revisions to display" on both Active and Inactive tabs.
- `minReplicas: 1, maxReplicas: 1` is used so that if a revision were ever created, exactly one replica would be expected. In this failure mode no revision is created, so the replica count is moot.
- `trigger.sh` captures six deployment-level evidence files (Phases 1-6) and does NOT mutate state. The failure was already produced by the Bicep deployment in step 2 of Quick Start; trigger.sh's job is to record the failure-state evidence in a structured, parseable form so verify.sh and downstream readers can compare it against the post-fix state. The deployment-level H1 gate emits one of four `gate_classification` values:
    - `deployment_failed_manifest_unknown` — `provisioningState=Failed` AND error message contains `MANIFEST_UNKNOWN` (expected here)
    - `deployment_failed_other` — `provisioningState=Failed` but error message does NOT contain `MANIFEST_UNKNOWN` (the trigger produced a different failure mode; investigate before proceeding)
    - `deployment_succeeded_no_revision` — `provisioningState=Succeeded` but `latestRevisionName=null` (unusual; investigate)
    - `deployment_succeeded_revision_present` — H1 FALSIFIED (the bad image tag did not produce the documented failure; the deployment succeeded and a revision exists)
- `verify.sh` Phase 8 calls `az acr build --image labacr:v1 ./workload` to build and push a known-good image to ACR. Phase 9 calls `az containerapp update --image <acr>/labacr:v1` which transitions the Container App from `Failed` to `Succeeded` and creates a new revision. Phase 10 polls revision health up to 5 minutes (10 s interval) until `healthState=Healthy` or the timeout. Phase 14 issues 10 sequential HTTPS requests to the recovered FQDN; the H2 sub-gate A is `requests_ok >= 8/10`. The H2 gate emits one of four `gate_classification` values:
    - `revision_healthy_traffic_100_curl_ok` — Healthy + traffic=100 + at least 8/10 HTTP 200 (expected)
    - `revision_healthy_no_curl_response` — Healthy + traffic=100 but fewer than 8/10 HTTP 200 (partial recovery; FQDN may need more time)
    - `revision_unhealthy` — Revision exists but not Healthy after 5 min (H2 FALSIFIED)
    - `revision_missing` — No revision created post-fix (H2 FALSIFIED)
- The pass/fail logic encodes three outcomes plus one invalid-run guard:
    - **H1 PASS + H2 PASS** ⇒ the falsification hypothesis is SUPPORTED. `verify.sh` exits 0.
    - **H1 FALSIFIED in `trigger.sh`** (`gate_classification == deployment_succeeded_revision_present`) ⇒ the bad tag did not produce a deployment failure. `trigger.sh` exits 2 and `verify.sh` is never reached.
    - **H2 FALSIFIED in `verify.sh`** (`gate_classification == revision_unhealthy` or `revision_missing`) ⇒ the recovery did not produce a Healthy revision. `verify.sh` exits 2.
    - **INVALID RUN** (a required environment variable is unset, ACR build failed, or the trigger.sh evidence file is missing) ⇒ exit 1.

## Why the lab uses `az acr build` (not `docker build` + `docker push`)

`az acr build` runs the Dockerfile build inside a Microsoft-hosted ACR Tasks worker, so the lab does not depend on a local Docker daemon, Docker login state, or `docker push` upload bandwidth. The build artifact and digest are recorded by ACR Tasks as a build log; the lab captures the result of `az acr build` to `evidence/07-acr-build-result.json`. The recovery is identical in observable behavior to a local `docker build` + `docker push` (both produce a `labacr:v1` tag in ACR with the same image contents), but `az acr build` is more reproducible across operator environments because it does not depend on the presence of a local container runtime.

## Why the experiment uses a custom Flask + Gunicorn image

This lab is the entry point of the ACR pull-failure scenario in the playbook chain. Using a custom image (rather than `mcr.microsoft.com/k8se/quickstart` or `containerapps-helloworld`) ensures the lab actually exercises the ACR pull path; a public Microsoft-hosted image would never trigger the ACR-specific failure mode because there is no ACR pull involved. The workload itself is intentionally minimal (Flask + Gunicorn on `:8000`, exposing `GET /` and `GET /health`) so the focus stays on the registry pull behavior, not on the application.

## Cost notes

- Resources provisioned: 1 Log Analytics workspace (PerGB, 30-day retention), 1 Container Apps Environment (Consumption), 1 ACR (Basic SKU), 1 Container App (in `Failed` state for most of the lab, then `Succeeded` post-recovery with `minReplicas: 1`, `maxReplicas: 1`, `0.5 vCPU`, `1 Gi` memory).
- No public IP, no private endpoint, no VNet integration.
- During the failed-deployment window, no container ever runs, so no Container Apps compute is billed. ACR Basic is approximately USD $0.167/day prorated to the hour; the lab is designed to run end-to-end and clean up in under 15 minutes, so the ACR charge is approximately USD $0.001.
- After recovery, the Container App runs with `minReplicas: 1` for the duration of the curl probes plus the post-fix metadata capture (approximately 2 minutes), which costs well under USD $0.01.
- `az acr build` runs on a Microsoft-hosted worker and is billed per-build-minute; the workload Dockerfile is small (python:3.11-slim base + Flask + Gunicorn install) and typically builds in under 2 minutes, which is well under USD $0.01.
- Total cost for one end-to-end lab run is well under USD $0.05.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.

## What to record in your evidence write-up

When you ship this lab's evidence into a docs PR or a support ticket, ALWAYS record the following alongside the JSON captures:

- **Azure region** (e.g., `koreacentral`). Captured to `evidence/22-region.json`.
- **Azure CLI version** and **`containerapp` extension version** (`az version`, `az extension list --query "[?name=='containerapp']"`). Captured to `evidence/20-cli-versions.json` and `evidence/21-cli-containerapp-ext.json`.
- **Date of the run in UTC** (visible at the top of `00-trigger-run.txt` and `00-verify-run.txt`).
- **The exit code of `trigger.sh` and `verify.sh`** (0 = hypothesis supported, 1 = invalid run, 2 = falsified).
- **The deployment outputs blob** captured to `evidence/23-deployment-outputs.json`. Note this is `null` in the failed-deployment state — the Azure Resource Manager platform only populates `properties.outputs` on `Succeeded` deployments. The resource names the scripts use are derived in Quick Start step 3 from `az containerapp list`, `az acr list`, and `az monitor log-analytics workspace list` (one-row queries) rather than from deployment outputs. The recovered FQDN is recorded in `evidence/09-containerapp-show-after-fix.json` and `evidence/12-curl-after-fix.json`.
- **The full Bicep deployment error message** that contains `MANIFEST_UNKNOWN` (visible in `evidence/01-deployment-result.json`).

The H1 evidence here is a structured absence (no revision, no system log table, no FQDN) which is a different shape than H1 evidence in other labs (where the failure produces rows in `ContainerAppSystemLogs_CL`). Operators new to the platform may find this absence harder to recognize as evidence than a populated log table; recording the deployment error message and the empty `az containerapp revision list` output side-by-side is the most direct way to communicate the failure signature in a support ticket.

## Operator takeaway

This lab observed (2026-06-22 reproduction in `koreacentral`) that when a Container App is configured with an image tag that does not exist in its referenced ACR, the Azure Container Apps platform produces a deterministic, deployment-level failure signature: the Bicep deployment exits `Failed` with an error message containing `MANIFEST_UNKNOWN: manifest tagged by "<tag>" is not found`, the Container App resource is created in `provisioningState=Failed` with `latestRevisionName=null`, no revision row is materialized, no container ever starts, and `ContainerAppSystemLogs_CL` is not populated. Microsoft Learn documents that revisions are immutable snapshots and that the manifest must be resolvable for the revision to start ([Revisions in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/revisions), [Troubleshoot image pull errors](https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-image-pull-failures)); the consequence of referencing a non-existent tag is what this lab demonstrates. The fix is to build and publish a valid image tag and update the app to reference it: `az acr build --registry <acr> --image labacr:v1 <workload-dir>` followed by `az containerapp update --image <acr>/labacr:v1`. After the fix, the platform creates a Healthy revision serving 100% of traffic, the assigned FQDN returns HTTP 200, and `ContainerAppSystemLogs_CL` begins ingesting normal platform events. The cheapest live-incident diagnostic for this failure mode is the combination of (1) the deployment error message in `az deployment group show --query "properties.error.message"` and (2) the empty result from `az containerapp revision list`; either alone is suggestive, but the two together are the smoking gun. The matching playbook is [`docs/troubleshooting/playbooks/startup-and-provisioning/image-pull-failure.md`](../../docs/troubleshooting/playbooks/startup-and-provisioning/image-pull-failure.md); reproduce locally with `./trigger.sh` and `./verify.sh` to validate it against your own environment before training on-call engineers.
