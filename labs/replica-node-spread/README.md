# Lab: Replica node-spread

This lab provides the runnable infrastructure and scripts for the
[Replica node-spread on Consumption vs Dedicated D8](../../docs/troubleshooting/lab-guides/replica-node-spread.md)
experimental lab. The lab tests the operator claim that Container Apps
distributes replicas across multiple nodes on the Consumption profile
while a Dedicated D8 workload profile may concentrate all replicas on
a single node.

Evidence-ceiling reminder: this lab uses kernel-context proxies
(`boot_id`, `uptime_seconds`, `boot_time_estimate_ms`) instead of the
underlying `Microsoft.Compute` node id, which Container Apps does not
expose. The highest claim allowed for node placement is
`[Strongly Suggested]`.

## Structure

```text
labs/replica-node-spread/
├── infra/
│   ├── main.bicep                # Workload-profile env + 2 subject apps
│   └── main.parameters.json
├── diag/
│   ├── Dockerfile                # python:3.12-slim + gunicorn
│   ├── app.py                    # Flask /diag returns kernel signals
│   └── requirements.txt
├── deploy.sh                     # RG + ACR + Bicep deployment wrapper
├── verify.sh                     # Health checks on env + 2 apps + /diag
├── scale.sh                      # Scale a named app to N and wait stable
├── sample.sh                     # Poll /diag, append per-sample JSONL
├── falsify.sh                    # H3 proxy validation (gates H1/H2)
├── trigger.sh                    # Master orchestrator
├── analyze.py                    # Counts + cluster verdict
├── cleanup.sh                    # Destructive teardown with confirmation
└── README.md
```

## Prerequisites

- Azure subscription with quota for:
    - One workload-profile Container Apps environment
    - One Consumption workload profile (no minimum count)
    - One Dedicated D8 workload profile (8 vCPU / 32 GiB, 1 node)
    - Two Container Apps, each scaled up to 24-30 replicas of
      0.25 vCPU / 0.5 GiB
    - One Azure Container Registry (Basic SKU)
- Region must support Container Apps **workload profiles** AND the
  **D8** SKU (for example `koreacentral`, `eastus`, `westeurope`).
- Azure CLI `2.60+` with the `containerapp` extension and `az acr build`
  (requires `az acr` ACR Tasks support).
- Local `bash`, `curl`, and `jq`.
- Python 3.10+ for `analyze.py`.

## Quick start

```bash
export RG="rg-aca-rns-lab"
export LOCATION="koreacentral"

./deploy.sh
./verify.sh

# Master orchestrator — includes the H3 falsification gate and runs the
# Consumption + Dedicated D8 scale sequences with 3 repeats at top.
./trigger.sh

python3 ./analyze.py
cat evidence/analysis-summary.md

./cleanup.sh
```

## Experiment shape

```mermaid
flowchart TD
    A[deploy.sh] --> B[ACR + diag image + Bicep env + 2 apps]
    B --> C[verify.sh — env, profiles, /diag responds 200]
    C --> D[falsify.sh — H3 gate]
    D -->|PASS| E[trigger.sh]
    D -->|FAIL| Z[STOP — proxy invalid, do not publish H1/H2]
    E --> F[For each profile: scale 1, 3, 10, top]
    F --> G[At each step: scale.sh + sample.sh]
    G --> H[Top step repeats 3x]
    H --> I[evidence/*.jsonl]
    I --> J[analyze.py]
    J --> K[evidence/analysis-summary.md]
    K --> L[Cross-check verdict vs Issue #202 hypotheses]
```

## Data shape

Each line in `evidence/*.jsonl` is one /diag sample wrapped with
run metadata:

| Field                | Source                                              | Notes                                       |
|----------------------|-----------------------------------------------------|---------------------------------------------|
| boot_id              | /proc/sys/kernel/random/boot_id                     | Primary kernel-context signal               |
| uptime_seconds       | /proc/uptime field 0                                | Monotonicity check                          |
| boot_time_estimate_ms| sample_timestamp - uptime                           | Cluster key for node identity inference     |
| machine_id           | /etc/machine-id (often missing)                     | Secondary signal                            |
| kernel_release       | uname -r                                            | Host-shared                                 |
| microcode            | /proc/cpuinfo microcode                             | Host-shared                                 |
| cpu_model            | /proc/cpuinfo model name                            | Host-shared                                 |
| replica_name         | $CONTAINER_APP_REPLICA_NAME / hostname fallback     | Replica identity                            |
| revision             | $CONTAINER_APP_REVISION                             | Revision identity                           |
| app                  | sample.sh arg                                       | app-consumption \| app-dedicated-d8         |
| profile              | sample.sh arg                                       | Consumption \| Dedicated-D8                 |
| scale_target         | sample.sh arg                                       | 1, 3, 10, top                               |
| run_id               | trigger.sh                                          | <profile>-n<N>-r<R>-<timestamp>             |
| sample_index         | sample.sh loop counter                              | 1..samples                                  |
| client_sample_at     | sample.sh wall clock                                | ISO-8601 UTC                                |

## Building the diag image manually

`deploy.sh` builds the image with `az acr build` and wires it into the
Bicep deployment automatically. To rebuild the image without redeploying
the environment, run:

```bash
ACR_NAME="rnslabacrXXXXXX"   # find with: az acr list -g $RG -o table
az acr build --registry "$ACR_NAME" \
  --image "rns-lab/diag:latest" \
  ./diag
```

The apps re-pull `:latest` on the next revision update; trigger a
revision rollover with `az containerapp update --revision-suffix
$(date +%s)` if you need to force a refresh without changing scale.

## Cleanup

`cleanup.sh` issues `az group delete --yes --no-wait` after explicit
confirmation. Resources soft-delete may persist for up to 24 hours;
charges stop once the delete completes.

## Related documentation

- Lab guide: `docs/troubleshooting/lab-guides/replica-node-spread.md`
- Platform: `docs/platform/environments/plans-and-workload-profiles.md`
- Platform: `docs/platform/environments/consumption-plan.md`
- Issue: <https://github.com/yeongseon/azure-container-apps-practical-guide/issues/202>
