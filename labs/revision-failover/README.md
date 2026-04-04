# Lab: Revision Failover and Rollback

This lab now includes deployable infrastructure, a reproducible workload, and scripts to trigger/verify rollback.

## Structure

```text
labs/revision-failover/
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
export RG="rg-aca-lab-revision"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create --resource-group "$RG" --template-file ./infra/main.bicep --parameters baseName="labrevision"

# Set APP_NAME and ACR_NAME from deployment outputs.
./trigger.sh
./verify.sh
./cleanup.sh
```
