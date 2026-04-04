# Lab: Scale Rule Mismatch

This lab now contains full infrastructure and automation scripts to reproduce/fix scaling misconfiguration.

## Structure

```text
labs/scale-rule-mismatch/
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
export RG="rg-aca-lab-scale"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create --resource-group "$RG" --template-file ./infra/main.bicep --parameters baseName="labscale"

# Set APP_NAME and ACR_NAME from deployment outputs.
./trigger.sh
./verify.sh
./cleanup.sh
```
