# Azure Container Apps CLI Reference

This reference summarizes commonly used Azure Container Apps CLI command groups with production-friendly examples that use long flags.

## Prerequisites

- Azure CLI 2.57+
- Container Apps extension installed and updated

```bash
az extension add --name containerapp --upgrade
```

## `az containerapp` commands

### Create

```bash
az containerapp create \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --environment "$ENVIRONMENT_NAME" \
  --image "$ACR_NAME.azurecr.io/$APP_NAME:latest" \
  --target-port 8000 \
  --ingress external \
  --registry-server "$ACR_NAME.azurecr.io" \
  --min-replicas 1 \
  --max-replicas 5
```

### Update

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/$APP_NAME:$IMAGE_TAG" \
  --cpu 0.5 \
  --memory 1.0Gi \
  --set-env-vars "ENV=prod" "LOG_LEVEL=info"
```

### Show

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output json
```

### List

```bash
az containerapp list \
  --resource-group "$RG" \
  --output table
```

### Delete

```bash
az containerapp delete \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --yes
```

## `az containerapp revision` commands

```bash
az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table

az containerapp revision show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "$REVISION_NAME" \
  --output json

az containerapp revision deactivate \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "$REVISION_NAME"

az containerapp revision restart \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "$REVISION_NAME"
```

## `az containerapp replica` commands

```bash
az containerapp replica list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "$REVISION_NAME" \
  --output table

az containerapp replica show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --replica "$REPLICA_NAME" \
  --revision "$REVISION_NAME" \
  --output json
```

## `az containerapp logs` commands

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --follow false

az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "$REVISION_NAME" \
  --tail 200
```

## `az containerapp env` commands

```bash
az containerapp env create \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION"

az containerapp env show \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RG" \
  --output json

az containerapp env list \
  --resource-group "$RG" \
  --output table
```

## `az containerapp job` commands

```bash
az containerapp job create \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --environment "$ENVIRONMENT_NAME" \
  --trigger-type Schedule \
  --cron-expression "*/15 * * * *" \
  --image "$ACR_NAME.azurecr.io/$JOB_NAME:latest"

az containerapp job start \
  --name "$JOB_NAME" \
  --resource-group "$RG"

az containerapp job execution list \
  --name "$JOB_NAME" \
  --resource-group "$RG" \
  --output table
```

## `az containerapp ingress` commands

```bash
az containerapp ingress enable \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type external \
  --target-port 8000

az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$REVISION_STABLE=90" "$REVISION_CANARY=10"

az containerapp ingress show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output json
```

## `az containerapp secret` commands

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "redis-password=<redacted>" "api-key=<redacted>"

az containerapp secret list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table

az containerapp secret remove \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secret-names "api-key"
```

## `az containerapp identity` commands

```bash
az containerapp identity assign \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --system-assigned

az containerapp identity assign \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --user-assigned "$UAMI_ID"

az containerapp identity show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output json
```

## Common flag combinations

| Scenario | Useful flags |
|---|---|
| Script-friendly output | `--output json`, `--query <JMESPath>` |
| Non-interactive execution | `--yes`, `--only-show-errors` |
| Targeting revisions | `--revision <name>`, `--revision-weight` |
| Environment/app targeting | `--resource-group`, `--name`, `--environment` |

## Advanced Topics

- Pin CLI and extension versions in CI to avoid drift.
- Use `--query` and structured outputs for deterministic automation.
- Wrap high-risk operations (`delete`, `deactivate`) with change controls.

## See Also

- [Environment Variables Reference](environment-variables.md)
- [Platform Limits](platform-limits.md)
- [Microsoft Learn: Azure Container Apps CLI](https://learn.microsoft.com/cli/azure/containerapp)
