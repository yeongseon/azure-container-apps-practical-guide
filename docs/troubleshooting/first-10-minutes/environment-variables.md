---
content_sources:
  diagrams:
    - id: environment-variables
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/environment-variables
        - https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: ai-agent
  core_claims:
    - claim: Azure Container Apps lets you define environment variables for containers.
      source: https://learn.microsoft.com/en-us/azure/container-apps/environment-variables
      verified: true
    - claim: Azure Container Apps provides platform environment variables such as CONTAINER_APP_NAME and CONTAINER_APP_REVISION.
      source: https://learn.microsoft.com/en-us/azure/container-apps/environment-variables
      verified: true
    - claim: 'Secrets in Azure Container Apps can be referenced from environment variables by using the secretref: prefix.'
      source: https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
      verified: true
---
# Environment Variables

<!-- diagram-id: environment-variables -->
```mermaid
flowchart TD
    accTitle: Environment variable sources in a Container App
    accDescr: A container receives application configuration, platform-provided metadata, runtime settings, and secret-backed values. A Key Vault reference is resolved through a Container Apps secret before the value is exposed to the container.

    APP_CONFIG["Application configuration<br/>LOG_LEVEL, TELEMETRY_MODE"]
    PLATFORM["Platform-provided metadata<br/>CONTAINER_APP_NAME and REVISION"]
    RUNTIME["Container runtime settings<br/>PORT, PYTHONUNBUFFERED"]
    KV["Azure Key Vault<br/>external secret source"]
    ACA_SECRET["Container Apps secret<br/>inline value or Key Vault reference"]
    SECRET_REF["Environment variable<br/>secretref:secret-name"]
    CONTAINER["Running container<br/>process environment"]

    APP_CONFIG --> CONTAINER
    PLATFORM --> CONTAINER
    RUNTIME --> CONTAINER
    KV -. "referenced by" .-> ACA_SECRET
    ACA_SECRET --> SECRET_REF
    SECRET_REF --> CONTAINER
```

Plain settings and platform metadata enter the process environment directly. Secret-backed variables use a `secretref:` mapping; Key Vault remains a separate Azure resource rather than a child of the Container App.

## Application Variables (Reference App)

| Variable | Used by | Purpose | Default | Example |
| --- | --- | --- | --- | --- |
| `LOG_LEVEL` | `app/src/app.py` | Python logging level | `INFO` | `DEBUG` |
| `FLASK_ENV` | `app/src/routes/info.py` | App environment label | `development` (route fallback) | `production` |
| `TELEMETRY_MODE` | `app/src/config/telemetry.py` | Telemetry behavior | `basic` | `advanced` |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | `app/src/config/telemetry.py` | Azure Monitor/OpenTelemetry connection | _none_ | `InstrumentationKey=<redacted>;...` |
| `DB_CONNECTION_STRING` | App config pattern | Database connection secret mapping | _none_ | `secretref:db-connection` |
| `STORAGE_ACCOUNT_NAME` | App config pattern | Storage account name | _none_ | `mystorageaccount` |

## Container Apps System Variables

| Variable | Description | Example |
| --- | --- | --- |
| `CONTAINER_APP_NAME` | Container App name | `ca-myapp` |
| `CONTAINER_APP_REVISION` | Active revision | `ca-myapp--0000001` |
| `CONTAINER_APP_REPLICA_NAME` | Replica identifier | `ca-myapp--0000001-646779b4c5-bhc2v` |
| `CONTAINER_APP_ENV_DNS_SUFFIX` | Environment DNS suffix | `eastus.azurecontainerapps.io` |

## Runtime Variables

| Variable | Source | Notes |
| --- | --- | --- |
| `PORT` | Container platform / startup command | This app binds Gunicorn to `8000`; keep `targetPort` aligned |
| `PYTHONUNBUFFERED` | Optional app setting | Set to `1` for immediate stdout/stderr flushing |

## Secret Mapping Patterns

| Pattern | Example |
| --- | --- |
| Inline env var | `--set-env-vars "LOG_LEVEL=INFO"` |
| Secret creation | `az containerapp secret set --name "$APP_NAME" --resource-group "$RG" --secrets "db-connection=<redacted>"` |
| Secret reference in env var | `--set-env-vars "DB_CONNECTION_STRING=secretref:db-connection"` |

## Quick Validation

```bash
RG="rg-myapp"
APP_NAME="ca-myapp"

az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.template.containers[0].env"

az containerapp exec \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --command "/bin/bash"

# Inside container
env | sort
```

| Command | Purpose |
|---|---|
| `az containerapp show` | Reads the revision template so the configured environment-variable mappings can be inspected. |
| `az containerapp exec` | Starts an interactive shell in a running replica for runtime environment inspection. |
| `--name` | Selects the Container App being compared at configuration and runtime. |
| `--resource-group` | Selects the resource group containing that app. |
| `--query` | Makes `az containerapp show` extract only the first container's environment-variable array. |
| `--command` | Makes `az containerapp exec` start `/bin/bash` so `env` can be run inside the container. |

Observed output pattern from a healthy replica:

```text
CONTAINER_APP_ENV_DNS_SUFFIX=<region>.azurecontainerapps.io
CONTAINER_APP_NAME=ca-myapp
CONTAINER_APP_REPLICA_NAME=ca-myapp--0000001-646779b4c5-bhc2v
CONTAINER_APP_REVISION=ca-myapp--0000001
PORT=8000
```

## Minimal Best Practices

| Do | Avoid |
| --- | --- |
| Use `secretref:` for sensitive values | Plain text passwords in `--set-env-vars` |
| Keep optional defaults in code (`os.environ.get`) | Hardcoded environment-specific constants |
| Redact connection strings in docs | PII, subscription IDs, keys/tokens |
## See Also

- [Repository map](../../start-here/repository-map.md)
## Sources
- [Environment variables in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/environment-variables)
- [Manage secrets in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
