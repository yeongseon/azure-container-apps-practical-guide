---
content_sources:
  diagrams:
    - id: startup-degraded-evidence-flow
      type: flowchart
      source: self-generated
      justification: Repository-only evidence flow synthesized from the lab deployment, perturbation, sampling, and verification scripts.
      based_on:
        - https://github.com/yeongseon/azure-container-apps-practical-guide/tree/main/labs/startup-degraded-transient-failure
---
# Lab: Startup-degraded transient failure (issue #205)

This lab provides the runnable infrastructure and scripts for the
[Startup-degraded transient failure during rolling rollout](../../docs/troubleshooting/lab-guides/startup-degraded-transient-failure.md)
experimental lab. The lab tests the operator assumption that ACA
masks all transient unavailability behind health probes during a
rolling rollout, even when the subject app has a deterministic
25-second startup delay.

## Lab design binding

This lab follows the same design standard as
`labs/zone-redundancy-best-effort/`. The binding design constraints
are documented in
[`evidence/design-constraints-20260612.md`](evidence/design-constraints-20260612.md).

Key bindings:

1. The **primary perturbation** is an ACA-managed new revision rollout
    triggered by a `ROLLOUT_GENERATION` env-var change. `revision restart`
    is supplemental only.
2. The subject app is a **deterministic custom Python image** with
    `STARTUP_DELAY_SECONDS=25` and a dedicated **`/healthz`** endpoint;
    all three probes target `/healthz`, not `/`.
3. The k6 loadgen runs as a **manual Container Apps Job** in the same
    environment, targets the **public FQDN**, and emits client-side
    **10s buckets** with embedded timestamps.
4. A **high-frequency perturbation sampler** (5-second cadence) is
    mandatory; the 5-minute audit cron is supplemental.
5. The falsification rule from issue #205 is: ANY sustained window of
    ≥3 consecutive 10s buckets above 0.5% `err_pct` during an event
    is sufficient to falsify the "ACA masks all transients" claim.
6. Conclusions about "**platform-initiated** cause" are capped at
    **[Strongly Suggested]**; the client-visible 5xx outcome is
    **[Measured]**.

## Structure

```text
labs/startup-degraded-transient-failure/
├── infra/
│   ├── main.bicep                # Env + subject + 3 Jobs (audit, sampler, k6)
│   └── main.parameters.json
├── subject/
│   ├── Dockerfile                # Python 3.12 slim, deterministic 25s startup
│   └── server.py                 # /healthz + / endpoints, stdlib only
├── loadgen/
│   ├── Dockerfile                # grafana/k6 + baked k6-script.js
│   └── k6-script.js              # constant-arrival-rate 200 RPS, 10s buckets
├── audit/
│   ├── Dockerfile                # Mariner + bash + curl + jq
│   └── sample.sh                 # 30s cadence, ReplicaInventory + RevisionState
├── perturbation-sampler/
│   ├── Dockerfile                # Mariner + bash + curl + jq
│   └── sample.sh                 # 5s cadence, bounded duration, manual trigger
├── deploy.sh                     # Resource group + Bicep deployment wrapper
├── verify.sh                     # Phase B pure file processor (qA-qG -> 10-13 gates)
├── trigger.sh                    # Preflight / baseline / perturbation / supplemental modes
├── cleanup.sh                    # Destructive teardown with confirmation
└── README.md
```

## Prerequisites

- Azure subscription with quota for:
    - One workload-profile Container Apps environment (zone-redundant)
    - One subject app consuming 0.5 vCPU / 1 GiB at min=max=3 (3 replicas)
    - Three Container Apps Jobs (audit-sampler, perturbation-sampler, loadgen-k6)
- Region must support Container Apps **workload profiles**.
- Azure CLI `2.60+` with the `containerapp` extension.
- (Strongly recommended) Container registry to host the four custom
  images: `subject`, `audit`, `perturbation-sampler`, `loadgen`. The
  default `*Image` parameters fall back to public placeholders that
  emit a single notice line, so the deployment succeeds before custom
  images are built, but the lab produces no real signal until they
  are.

## Quick start

```bash
export RG="rg-aca-startup-degraded"
export LOCATION="koreacentral"
export ACR_NAME="<your-acr-without-azurecrio>"

./deploy.sh

az acr build --registry "$ACR_NAME" --image startup-degraded/subject:latest               ./subject
az acr build --registry "$ACR_NAME" --image startup-degraded/audit:latest                 ./audit
az acr build --registry "$ACR_NAME" --image startup-degraded/perturbation-sampler:latest  ./perturbation-sampler
az acr build --registry "$ACR_NAME" --image startup-degraded/loadgen:latest               ./loadgen

export SUBJECT_IMAGE="${ACR_NAME}.azurecr.io/startup-degraded/subject:latest"
export AUDIT_IMAGE="${ACR_NAME}.azurecr.io/startup-degraded/audit:latest"
export PERTURBATION_SAMPLER_IMAGE="${ACR_NAME}.azurecr.io/startup-degraded/perturbation-sampler:latest"
export LOADGEN_IMAGE="${ACR_NAME}.azurecr.io/startup-degraded/loadgen:latest"
./deploy.sh   # redeploys with the custom images

./trigger.sh --preflight
./trigger.sh --baseline --duration 1800
./trigger.sh --perturbation --events 12 --interval 600
./trigger.sh --supplemental-restart --events 3 --interval 600

# Replay the committed evidence pack or newly captured qA-qG files
./verify.sh
```

## Data flow

Offline Gate 10(c) requires qF to map at least one baseline run and one perturbation run through the documented prefixes; two arbitrary distinct IDs do not satisfy the mapping. Gate 12(b) requires exactly one baseline run and one perturbation run in qF, both reporting no falsification; Gate 13(b) requires a shared qA/qE perturbation ID. The error-rate, snapshot and capture-window checks retain their strong and lower-evidence fallback tiers. Gate 12(a) additionally requires the perturbation run's `err_pct` to be present and a finite, non-negative number: an absent, null, empty or malformed value fails the gate (with an `a_input_problem` note) instead of counting as a zero error rate. The value is compared as an exact decimal (JSON numbers are decoded without float rounding), so `-1e-400` is rejected and `0.49999999999999999` stays inside the lower-evidence tier; when the value does not survive conversion to a float unchanged, the gate also records its exact decimal text as `observed_perturbation_err_pct_exact`. Only plain decimal notation is accepted: underscores, non-ASCII digits and bare `NaN` or `Infinity` tokens fail the gate. Missing perturbation rows or empty qA input produce complete Gate 10-13 reports with failed owning sub-gates instead of aborting midway. All four emitted gates record replay time in `evaluated_at_utc`, not a new capture date.

<!-- diagram-id: startup-degraded-evidence-flow -->
```mermaid
flowchart TD
    accTitle: Startup-degraded perturbation and evidence flow
    accDescr: Correlate a controlled revision rollout with high-frequency revision sampling, client-side request buckets, and legacy Log Analytics console and system tables.

    AUDIT[Audit job<br/>supplemental cadence]
    ARM[Azure Resource Manager<br/>revision and replica reads]
    TRIGGER[Perturbation trigger]
    SAMPLER[Perturbation sampler<br/>high-frequency cadence]
    UPDATE[Change rollout-generation<br/>environment value]
    ROLLOUT[Container Apps<br/>new revision rollout]
    SUBJECT[Subject revision<br/>deterministic startup delay]
    LOAD[Load-generator job]
    FQDN[Public app FQDN]
    CONSOLE[Legacy Log Analytics<br/>ContainerAppConsoleLogs_CL]
    SYSTEM[Legacy Log Analytics<br/>ContainerAppSystemLogs_CL]
    QUERY[Correlate request buckets,<br/>revision state, and system events]

    AUDIT ==>|Management requests| ARM
    ARM ==>|Revision and replica state| AUDIT
    AUDIT -.->|Inventory samples| CONSOLE
    TRIGGER --> SAMPLER
    SAMPLER ==>|Management requests| ARM
    ARM ==>|High-frequency state| SAMPLER
    SAMPLER -.->|Window markers and samples| CONSOLE
    TRIGGER --> UPDATE
    UPDATE --> ROLLOUT
    ROLLOUT --> SUBJECT
    SUBJECT -.->|Revision and replica events| SYSTEM
    LOAD ==>|Requests| FQDN
    FQDN ==>|Routed requests| SUBJECT
    SUBJECT ==>|Responses| FQDN
    FQDN ==>|Responses| LOAD
    LOAD -.->|Timestamped request buckets| CONSOLE
    CONSOLE --> QUERY
    SYSTEM --> QUERY
```

The `_CL` table names match this lab's direct Log Analytics destination. Client requests and responses are separate from management reads and telemetry associations.

## Cleanup

The deployment tags every resource with `expires-at` set to deploy time +
`expiryHours` (default 48). The `cleanup.sh` script issues
`az group delete --yes --no-wait` after explicit confirmation. The Log
Analytics workspace is destroyed too; export raw KQL results into
`evidence/` BEFORE running cleanup if you want them preserved beyond
the workspace's 90-day retention.

## Related documentation

- Lab guide: `docs/troubleshooting/lab-guides/startup-degraded-transient-failure.md`
- KQL pack: `docs/troubleshooting/kql/scaling-and-replicas/startup-degraded-bucketed-5xx.md`
- Operations: `docs/operations/deployment/revision-management.md`
- Best practices: `docs/best-practices/reliability.md`
- Integration page: `docs/best-practices/availability-and-non-guarantees.md`
