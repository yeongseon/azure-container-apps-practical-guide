# Python Reference Job for Azure Container Apps

This reference job shows how to implement a production-style **Container Apps Job** in Python for short-lived, repeatable workloads.

## What this job demonstrates

- Structured JSON logging for Log Analytics ingestion
- Environment-driven configuration for repeatable deployments
- Managed identity authentication with `DefaultAzureCredential`
- Blob Storage read operation using `azure-storage-blob`
- Graceful error handling with explicit exit codes
- Execution metadata (start time, completion, duration, status)

## Prerequisites

- Python 3.11+
- Docker (for containerized local testing)
- Azure CLI authenticated to your subscription
- Existing Azure Storage account and test blob
- Managed identity with `Storage Blob Data Reader` on target container

## Local run instructions

Install dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install --no-cache-dir -r requirements.txt
```

Set required environment variables:

```bash
export STORAGE_ACCOUNT_URL="https://<storage-account-name>.blob.core.windows.net"
export STORAGE_CONTAINER_NAME="samples"
export STORAGE_BLOB_NAME="input/demo.txt"
export LOG_LEVEL="INFO"
```

Run the job locally:

```bash
python src/job.py
echo $?
```

## Build and run as a container

```bash
docker build --tag aca-python-job:local .
docker run --rm \
  --env STORAGE_ACCOUNT_URL="$STORAGE_ACCOUNT_URL" \
  --env STORAGE_CONTAINER_NAME="$STORAGE_CONTAINER_NAME" \
  --env STORAGE_BLOB_NAME="$STORAGE_BLOB_NAME" \
  --env LOG_LEVEL="INFO" \
  aca-python-job:local
```

## Deploy to Azure Container Apps Jobs

Set deployment variables:

```bash
export RG="rg-myapp"
export LOCATION="koreacentral"
export ENVIRONMENT_NAME="cae-myapp"
export JOB_NAME="job-python-blob-reader"
export ACR_NAME="acrmyapp"
export IDENTITY_NAME="id-job-reader"
```

Build and push image:

```bash
az acr build \
  --registry "$ACR_NAME" \
  --image "python-job:v1" \
  --file "jobs/python/Dockerfile" \
  "jobs/python"
```

Create a manual-trigger job:

```bash
az containerapp job create \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --environment "$ENVIRONMENT_NAME" \
  --trigger-type "Manual" \
  --replica-timeout 1800 \
  --replica-retry-limit 2 \
  --parallelism 1 \
  --replica-completion-count 1 \
  --image "$ACR_NAME.azurecr.io/python-job:v1" \
  --cpu 0.5 \
  --memory 1Gi
```

Start an execution:

```bash
az containerapp job start \
  --name "$JOB_NAME" \
  --resource-group "$RG"
```

## Configuration

### Required environment variables

- `STORAGE_ACCOUNT_URL` — Blob endpoint URL
- `STORAGE_CONTAINER_NAME` — Container to read
- `STORAGE_BLOB_NAME` — Blob path within container

### Optional environment variables

- `LOG_LEVEL` — Logging verbosity (`DEBUG`, `INFO`, `WARNING`, `ERROR`)
- `CONTAINER_APP_JOB_EXECUTION_NAME` — Runtime execution identifier set by platform

### Secret and identity notes

- Use managed identity for Azure auth; avoid embedding credentials.
- Keep sensitive values in Container Apps secrets or Key Vault references.
- Grant least privilege (`Storage Blob Data Reader`) on target scope.

## Capabilities checklist

- [x] Structured JSON logging
- [x] Managed identity authentication
- [x] Blob Storage integration
- [x] Environment-based configuration
- [x] Error classification with exit codes (`0`, `1`, `2`)
- [x] Execution metadata and duration logging
