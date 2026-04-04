# Scaling Operations

This guide explains how to operate scaling in production, including manual replica control, KEDA-based autoscaling, and scale-to-zero behavior.

## Prerequisites

- Existing Container App in a managed environment
- Baseline performance targets (latency, throughput, queue delay)

```bash
export RG="rg-aca-prod"
export APP_NAME="app-python-api-prod"
export ENVIRONMENT_NAME="aca-env-prod"
```

## Manual Scaling for Controlled Events

Use manual scaling for maintenance windows or expected short-term load.

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --min-replicas 3 \
  --max-replicas 10
```

Check current replica settings:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.template.scale" \
  --output json
```

## KEDA Rule Operations

Scale based on HTTP concurrency:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --scale-rule-name "http-concurrency" \
  --scale-rule-type "http" \
  --scale-rule-metadata "concurrentRequests=100" \
  --min-replicas 1 \
  --max-replicas 20
```

Example queue scaler operation (Azure Service Bus):

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --scale-rule-name "sb-queue" \
  --scale-rule-type "azure-servicebus" \
  --scale-rule-metadata "queueName=orders" "messageCount=50" "namespace=<servicebus-namespace>.servicebus.windows.net"
```

Use Azure Monitor metrics to tune thresholds:

```bash
az monitor metrics list \
  --resource "/subscriptions/<subscription-id>/resourceGroups/$RG/providers/Microsoft.App/containerApps/$APP_NAME" \
  --metric "Requests" \
  --interval "PT1M" \
  --output table
```

## Scale-to-Zero Operations

Enable scale-to-zero for event-driven or intermittent workloads:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --min-replicas 0 \
  --max-replicas 10
```

Use this mode only when cold start impact is acceptable.

## Verification Steps

```bash
az containerapp replica list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table
```

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "{minReplicas:properties.template.scale.minReplicas,maxReplicas:properties.template.scale.maxReplicas,rules:properties.template.scale.rules}" \
  --output json
```

Example output (PII masked):

```json
{
  "minReplicas": 0,
  "maxReplicas": 20,
  "rules": [
    {
      "name": "http-concurrency",
      "custom": {
        "type": "http",
        "metadata": {
          "concurrentRequests": "100"
        }
      }
    }
  ]
}
```

## Troubleshooting

### Autoscaling does not trigger

- Confirm scaler metadata values and key names.
- Check if incoming load actually reaches configured thresholds.
- Validate identity/secret references for external event sources.

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type system \
  --follow false
```

## Advanced Topics

- Combine multiple KEDA rules and set max replica guardrails.
- Separate interactive and batch workloads into different apps.
- Define pre-warming strategies for predictable peak windows.

## See Also
- [Cost Optimization](../../platform/reliability/cost-optimization.md)
- [Observability](../monitoring/index.md)
- [Scaling with KEDA (Concepts)](../../platform/scaling/index.md)

## Sources
- [Azure Container Apps scaling](https://learn.microsoft.com/azure/container-apps/scale-app)
- [KEDA scalers reference (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/scale-app#scale-triggers)
