# Operations Guide for Azure Container Apps

This section covers day-2 operations for running Python workloads on Azure Container Apps in production, including scaling, revisions, networking, security, observability, and cost control.

## Prerequisites

- An existing Container Apps environment and app
- Azure CLI with Container Apps extension installed
- Permissions to view and update Container App resources

```bash
export RG="rg-aca-prod"
export APP_NAME="app-python-api-prod"
export ENVIRONMENT_NAME="aca-env-prod"

az extension add --name containerapp --upgrade
az account show --output table
```

## Operations Areas

- [Scaling](./scaling.md): manual scaling, KEDA rules, and scale-to-zero behavior
- [Revisions](./revisions.md): revision lifecycle, traffic splitting, and rollback
- [Health and Recovery](./health-recovery.md): probes, restarts, and recovery workflows
- [Networking](./networking.md): ingress, VNet operations, and service discovery
- [Security](./security.md): managed identity, secret handling, and Easy Auth
- [Cost Optimization](./cost-optimization.md): profile selection and spend controls
- [Observability](./observability.md): logs, metrics, traces, and alerting

## Verification Steps

Validate that the operations baseline is healthy before changing configuration.

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "{name:name,environmentId:properties.managedEnvironmentId,provisioningState:properties.provisioningState,runningStatus:properties.runningStatus}" \
  --output json
```

Example output (PII masked):

```json
{
  "name": "app-python-api-prod",
  "environmentId": "/subscriptions/<subscription-id>/resourceGroups/rg-aca-prod/providers/Microsoft.App/managedEnvironments/aca-env-prod",
  "provisioningState": "Succeeded",
  "runningStatus": "Running"
}
```

## Troubleshooting

If the app is not running:

1. Check latest system logs.
2. Confirm environment-level health and quotas.
3. Review latest revision status before applying new changes.

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type system \
  --follow false
```

## Advanced Topics

- Build a production runbook with change windows, rollback criteria, and ownership.
- Automate common operations with GitHub Actions or Azure DevOps.
- Define SLO-driven alerts that map directly to customer-facing impact.

## See Also
- [Scaling](./scaling.md)
- [Revisions](./revisions.md)
- [Health and Recovery](./health-recovery.md)
- [Observability](./observability.md)

## References
- [Azure Container Apps documentation](https://learn.microsoft.com/azure/container-apps/)
