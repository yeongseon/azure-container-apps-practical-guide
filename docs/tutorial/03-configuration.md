# 03 - Configuration, Secrets, and Dapr

This step configures runtime settings in Azure Container Apps, including environment variables, secrets, KEDA scaling rules, and Dapr sidecar options.

## Prerequisites

- Completed [02 - First Deploy to Azure Container Apps](02-first-deploy.md)
- A running Container App

## Step-by-step

1. **Set standard variables**

   ```bash
   RG="rg-aca-python-demo"
   APP_NAME="app-aca-python-demo"
   ENVIRONMENT_NAME="aca-env-python-demo"
   ACR_NAME="acrpythondemo12345"
   ```

2. **Set environment variables**

   ```bash
   az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --set-env-vars "LOG_LEVEL=INFO" "FEATURE_FLAG=true"
   ```

3. **Store and reference a secret**

   ```bash
   az containerapp secret set \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --secrets "db-password=<secret-value>"

   az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --set-env-vars "DB_PASSWORD=secretref:db-password"
   ```

4. **Configure KEDA HTTP autoscaling**

   ```bash
   az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --min-replicas 0 \
     --max-replicas 10 \
     --scale-rule-name "http-scale" \
     --scale-rule-type "http" \
     --scale-rule-http-concurrency 50
   ```

5. **Configure queue-driven KEDA scaling (example)**

   ```bash
   az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --scale-rule-name "queue-scale" \
     --scale-rule-type "azure-servicebus" \
     --scale-rule-metadata "queueName=orders" "namespace=sb-namespace" \
     --scale-rule-auth "connection=servicebus-connection"
   ```

6. **Enable Dapr sidecar**

   ```bash
   az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --enable-dapr \
     --dapr-app-id "$APP_NAME" \
     --dapr-app-port 8000
   ```

## Python example: read config safely

```python
import os

LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
FEATURE_FLAG = os.environ.get("FEATURE_FLAG", "false").lower() == "true"
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
```

## Advanced Topics

- Use Key Vault + managed identity instead of direct secret values.
- Tune KEDA thresholds differently for API and background worker apps.
- Add Dapr pub/sub and state store components for event-driven workflows.

## See Also

- [Containers (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/containers)
- [04 - Logging, Monitoring, and Observability](04-logging-monitoring.md)
- [07 - Revisions and Traffic Splitting](07-revisions-traffic.md)
- [Dapr Integration Recipe](../recipes/dapr-integration.md)
