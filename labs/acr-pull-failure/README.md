# Lab: ACR Image Pull Failure

This lab is now fully runnable with infrastructure, workload, and automation scripts.

## Structure

```text
labs/acr-pull-failure/
├── infra/main.bicep
├── workload/app.py
├── workload/requirements.txt
├── workload/Dockerfile
├── trigger.sh
├── verify.sh
└── cleanup.sh
```

## Quick Start

```bash
export RG="rg-aca-lab-acr"
export LOCATION="koreacentral"
export APP_NAME="ca-lab-acr"
export ACR_NAME="acrlabacr"

az group create --name "$RG" --location "$LOCATION"
az deployment group create --resource-group "$RG" --template-file ./infra/main.bicep --parameters baseName="labacr"

# Set APP_NAME and ACR_NAME from deployment outputs when needed.
./trigger.sh
./verify.sh
./cleanup.sh
```

## Notes

- `infra/main.bicep` intentionally uses a non-existent tag to trigger image pull failure.
- ACR `adminUserEnabled: true` is enabled only for lab simplicity.
