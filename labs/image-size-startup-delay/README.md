# Lab: Image Size Startup Delay

Reproducible comparison of how the size of a container image affects revision provisioning time and cold-start window on Azure Container Apps.

## Structure

```text
labs/image-size-startup-delay/
├── infra/main.bicep      # Log Analytics + Container Apps env + 1 app initially using a large image
├── trigger.sh            # Drive the three image scenarios and capture raw evidence
├── verify.sh             # Evaluate the committed raw evidence offline
├── cleanup.sh            # Delete the resource group
└── evidence/             # Captured system logs from trigger/verify runs
```

## Quick Start

```bash
export RG="rg-aca-lab-imagesize"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
  --resource-group "$RG" \
  --template-file ./infra/main.bicep \
  --parameters baseName="imgsize"

export APP_NAME=$(az deployment group show \
  --resource-group "$RG" \
  --name main \
  --query "properties.outputs.containerAppName.value" \
  --output tsv)

./trigger.sh   # capture the large, runtime-mismatch, and trimmed-image scenarios
./verify.sh    # emit the four derived gates without Azure calls
./cleanup.sh   # delete the resource group
```

## What this lab demonstrates

- The initial revision pulls `python:3.11` (~408 MB), recorded in `ContainerAppSystemLogs` as `Successfully pulled image "python:3.11" in <N>s`.
- `trigger.sh` deploys the trimmed-image revision; `verify.sh` compares the captured pull events without deploying anything.
- Both revisions run the same workload (`python -m http.server 8080`) on the same port, so the only variable that changes is base-image size.

## Cost notes

The original Phase B emission on 2026-06-24 was later re-evaluated offline
from the unchanged 2026-06-22 raw cohort. Each replay writes its own execution
time in top-level `evaluated_at_utc`, not a capture date. The committed cohort
reproduces the same non-time gate fields; no new capture or Azure validation
is implied. See [evidence provenance](evidence/README.md).

- Only standard Container Apps Consumption compute + 1 Log Analytics workspace are provisioned.
- Both images are pulled from public Docker Hub (`python:3.11`, `python:3.11-alpine`); no private ACR is required.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.
