# Lab: Application Insights Connection String Missing

Reproducible demonstration that an Azure Container App without `APPLICATIONINSIGHTS_CONNECTION_STRING` keeps serving HTTP 200 to clients but emits zero telemetry to Application Insights, then proves the fix by adding the env var and observing telemetry appear.

## Structure

```text
labs/appinsights-connection-string-missing/
├── infra/main.bicep      # LAW + workspace-based App Insights + ACR Basic + Container Apps env + 1 app (placeholder image, no env var, system identity + AcrPull)
├── app/                  # Minimal Flask + azure-monitor-opentelemetry app built into the lab's ACR
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
├── trigger.sh            # Switch to ACR image (no env var), generate traffic, query App Insights → expect 0 rows
├── verify.sh             # Add env var, generate traffic, query App Insights → expect > 0 rows
├── cleanup.sh            # Delete the resource group
└── evidence/             # Captured CLI + KQL evidence from trigger/verify runs
```

## Quick Start

These commands assume the working directory is `labs/appinsights-connection-string-missing/` (so the relative `./infra/main.bicep`, `./app`, `./trigger.sh`, `./verify.sh`, and `./cleanup.sh` paths resolve). All `az` invocations pin `--subscription` explicitly to immunize the run against Azure CLI default-subscription drift, and the deployment is given the explicit name `main` so its outputs can be read back deterministically.

```bash
cd labs/appinsights-connection-string-missing/

# 1) Base inputs — set these before any az command runs.
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-aiconn"
export LOCATION="koreacentral"

# 2) Provision the resource group and the lab infra (LAW + AI + ACR + CAE + app).
az group create \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$RG" \
  --location "$LOCATION"

az deployment group create \
  --subscription "$AZ_SUBSCRIPTION" \
  --resource-group "$RG" \
  --name main \
  --template-file ./infra/main.bicep \
  --parameters baseName="appiconn"

# 3) Read the deployment outputs the scripts need.
export APP_NAME=$(az deployment group show --subscription "$AZ_SUBSCRIPTION" --resource-group "$RG" --name main --query "properties.outputs.containerAppName.value" --output tsv)
export ACR_NAME=$(az deployment group show --subscription "$AZ_SUBSCRIPTION" --resource-group "$RG" --name main --query "properties.outputs.acrName.value" --output tsv)
export ACR_LOGIN_SERVER=$(az deployment group show --subscription "$AZ_SUBSCRIPTION" --resource-group "$RG" --name main --query "properties.outputs.acrLoginServer.value" --output tsv)
export APP_INSIGHTS_NAME=$(az deployment group show --subscription "$AZ_SUBSCRIPTION" --resource-group "$RG" --name main --query "properties.outputs.appInsightsName.value" --output tsv)
export IMAGE_TAG="hellotelemetry:v3"

# 4) Build the instrumented Python image directly inside the lab's ACR (no local Docker required).
az acr build \
  --subscription "$AZ_SUBSCRIPTION" \
  --registry "$ACR_NAME" \
  --image "$IMAGE_TAG" \
  ./app

./trigger.sh   # switch to ACR image WITHOUT env var → AI 'requests' table = 0 rows
./verify.sh    # add APPLICATIONINSIGHTS_CONNECTION_STRING env var → AI 'requests' table > 0 rows
./cleanup.sh   # delete the resource group
```

## What this lab demonstrates

- The initial Container App revision running `mcr.microsoft.com/azuredocs/containerapps-helloworld` has no Application Insights instrumentation at all (no SDK in the image).
- `trigger.sh` switches the app to a custom Python image (`hellotelemetry:v3`) built with `azure-monitor-opentelemetry==1.6.4` but does NOT set `APPLICATIONINSIGHTS_CONNECTION_STRING`. The app responds HTTP 200 to all 20 curl requests, but `configure_azure_monitor()` is guarded behind an env-var presence check and skipped — the App Insights `requests` and `traces` tables stay empty.
- `verify.sh` adds `APPLICATIONINSIGHTS_CONNECTION_STRING` via `az containerapp update --set-env-vars`, generates 20 fresh requests, then re-queries Application Insights. The `requests` table now shows > 0 rows attributed to the Container App's `cloud_RoleName`, and the `traces` table shows the app's startup log plus per-request `/ endpoint hit` messages.
- The only changed variable between the failed run and the working run is the env var. Image, ingress, target port, workload, and traffic pattern are all held constant.

## Why the canonical image is `:v3` (not `:v1` or `:v2`)

This lab carries two earlier image tags that document distinct failure modes encountered while building the lab. They are kept in the ACR and in the evidence pack so the lab itself documents what was tried and why the current image is what it is:

- `:v1` — `configure_azure_monitor()` called UNGUARDED. With `APPLICATIONINSIGHTS_CONNECTION_STRING` unset, `azure-monitor-opentelemetry==1.6.4` raises `ValueError: Instrumentation key cannot be none or empty.` at import time, the gunicorn worker exits with code 3, and the container enters CrashLoopBackOff. This is a DIFFERENT failure mode (availability loss, not silent observability gap) and is captured under `evidence/A1-v1-unguarded-sdk-crash-logs.json`. Not used as the canonical scenario because production apps in real escalations typically wrap SDK init defensively.
- `:v2` — `configure_azure_monitor()` is guarded by an env-var presence check, but Flask is imported with `from flask import Flask` BEFORE `configure_azure_monitor()` runs. In this lab's development experience the Flask auto-instrumentation hook could not wrap the `Flask` class after it had been fully imported, so `AppRequests` stayed empty even when the env var was present. This is the kind of subtle Python distro instrumentation gotcha that easily masquerades as "connection string missing" in production. The `:v2` source variant is described here as a lab-development observation; no per-revision `AppRequests`/`AppTraces` capture file is committed for it (the canonical falsification pair in this lab is the `:v3` before/after run, not a `:v2`/`:v3` comparison).
- `:v3` — canonical image. Same guard as `:v2`, plus two fixes: (1) `import flask` as a module (deferring the `Flask` class lookup until AFTER `configure_azure_monitor()` runs), and (2) `configure_azure_monitor(connection_string=CONN_STR, logger_name=__name__)` with explicit `logger_name` so module-level `logger.info(...)` calls export to `AppTraces`.

## Cost notes

- Resources provisioned: 1 Log Analytics workspace (PerGB), 1 workspace-based App Insights, 1 ACR Basic registry, 1 Container Apps Environment (Consumption), 1 Container App with min/max replicas = 1.
- ACR Basic prorates to roughly USD $0.167/day; total cost for a 2-hour lab run is well under USD $0.05.
- Run `cleanup.sh` immediately after capturing evidence to keep the bill near zero.

## App Insights ingestion latency

- App Insights typically ingests fresh telemetry within 2 to 5 minutes. Both scripts sleep 240 seconds after sending traffic before running the KQL query.
- If the post-fix query still shows 0 rows, wait another 2 minutes and re-run the query manually:

  ```bash
  az monitor app-insights query \
    --subscription "$AZ_SUBSCRIPTION" \
    --app "$APP_INSIGHTS_NAME" \
    --resource-group "$RG" \
    --analytics-query 'requests | where timestamp > ago(15m) | summarize count() by cloud_RoleName'
  ```
