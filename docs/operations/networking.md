# Networking Operations

This guide covers day-2 networking operations for Container Apps: ingress updates, VNet-related checks, and service discovery between apps.

## Prerequisites

- Container Apps environment deployed with required network model
- Ingress requirements documented (internal vs external)

```bash
export RG="rg-aca-prod"
export APP_NAME="app-python-api-prod"
export ENVIRONMENT_NAME="aca-env-prod"
```

## Ingress Configuration Operations

Enable external ingress with explicit target port:

```bash
az containerapp ingress enable \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type external \
  --target-port 8000
```

Switch to internal ingress for private-only access:

```bash
az containerapp ingress disable \
  --name "$APP_NAME" \
  --resource-group "$RG"
```

```bash
az containerapp ingress enable \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type internal \
  --target-port 8000
```

## VNet and Environment Checks

Inspect managed environment network profile:

```bash
az containerapp env show \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RG" \
  --output json
```

Validate subnet details (Azure CLI network command):

```bash
az network vnet subnet show \
  --resource-group "$RG" \
  --vnet-name "vnet-aca-prod" \
  --name "snet-containerapps" \
  --output table
```

## Service Discovery Operations

For app-to-app calls in the same environment, use internal FQDN from ingress settings.

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv
```

## Verification Steps

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress" \
  --output json
```

Example output (PII masked):

```json
{
  "external": false,
  "targetPort": 8000,
  "transport": "auto",
  "fqdn": "app-python-api-prod.internal.<region>.azurecontainerapps.io"
}
```

## Troubleshooting

### Requests time out

- Confirm ingress type matches caller location.
- Verify application port and `targetPort` alignment.
- Check NSG or route table updates affecting VNet path.

```bash
az network watcher test-connectivity \
  --resource-group "$RG" \
  --source-resource "/subscriptions/<subscription-id>/resourceGroups/$RG/providers/Microsoft.App/containerApps/$APP_NAME" \
  --dest-address "<dependency-hostname>" \
  --dest-port 443
```

## Advanced Topics

- Use internal ingress plus Application Gateway for centralized WAF.
- Define egress allow-list controls with Azure Firewall or NVA.
- Standardize DNS and naming for service-to-service resilience.

## See Also

- [Security](./security.md)
- [Health and Recovery](./health-recovery.md)
- [Container Apps networking](https://learn.microsoft.com/azure/container-apps/networking)
