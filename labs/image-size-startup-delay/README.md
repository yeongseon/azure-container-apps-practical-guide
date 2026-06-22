# Lab: Image Size Startup Delay

Reproducible comparison of how the size of a container image affects revision provisioning time and cold-start window on Azure Container Apps.

## Structure

```text
labs/image-size-startup-delay/
├── infra/main.bicep      # Log Analytics + Container Apps env + 1 app initially using a large image
├── trigger.sh            # Wait for the large-image revision and capture pull timing from system logs
├── verify.sh             # Switch the app to a small image and confirm a faster pull
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

./trigger.sh   # observe slow pull of python:3.11 (~408 MB)
./verify.sh    # switch to python:3.11-alpine (~50 MB) and compare
./cleanup.sh   # delete the resource group
```

## What this lab demonstrates

- The initial revision pulls `python:3.11` (~408 MB), recorded in `ContainerAppSystemLogs` as `Successfully pulled image "python:3.11" in <N>s`.
- `verify.sh` deploys a new revision with `python:3.11-alpine` (~50 MB) and the same Log Analytics query shows the second pull is several times faster.
- Both revisions run the same workload (`python -m http.server 8080`) on the same port, so the only variable that changes is base-image size.

## Cost notes

- Only standard Container Apps Consumption compute + 1 Log Analytics workspace are provisioned.
- Both images are pulled from public Docker Hub (`python:3.11`, `python:3.11-alpine`); no private ACR is required.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.
