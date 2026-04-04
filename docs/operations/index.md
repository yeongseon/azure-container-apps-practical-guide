# Operations

This section covers production operations and day-2 practices for Azure Container Apps. It is language-agnostic and focuses on platform behavior, reliability, and cost control in running systems.

!!! note "Variable naming in this section"
    Operations guides use production-style variable names (e.g., `RG="rg-aca-prod"`) to reflect real operational contexts. Tutorial guides use demo-style names (e.g., `RG="rg-aca-python-demo"`). Substitute your own resource names as appropriate.

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

## Main Content

### Operations Documents

| Document | Description |
|---|---|
| [Deployment](deployment/index.md) | CI/CD patterns, image build, registry authentication, production rollouts |
| [Networking](deployment/networking.md) | VNet deployment, private endpoints, egress controls |
| [Revision Management](revision-management/index.md) | Revision lifecycle, traffic splitting, rollback procedures |
| [Monitoring](monitoring/index.md) | Log Analytics, metrics, distributed tracing, alerting |
| [Scaling](scaling/index.md) | KEDA scale rules, manual scaling, concurrency limits |
| [Alerts](alerts/index.md) | SLO-driven alerts for availability, latency, and resource usage |
| [Image Pull and Registry](image-pull-and-registry/index.md) | Private registry authentication, managed identity pull |
| [Secret Rotation](secret-rotation/index.md) | Credential rotation without downtime |
| [Recovery](recovery/index.md) | Failed revision handling, replica restarts, regional failover |

### Quick Operational Commands

```bash
az containerapp show --resource-group $RG --name $APP_NAME --output json
az containerapp restart --resource-group $RG --name $APP_NAME
az containerapp revision list --resource-group $RG --name $APP_NAME --output table
az containerapp logs show --resource-group $RG --name $APP_NAME --type system --follow
```

### Verification Steps

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

## Advanced Topics

- Build an SLO-based operating model mapping each control to measurable service outcomes.
- Keep runbooks and IaC synchronized so recovery steps are deterministic during incidents.
- Validate production controls regularly through game days and restore exercises.

## Language-Specific Details

For language-specific operational guidance, see:
- [Python Guide](../language-guides/python/index.md)

## See Also

- [Platform](../platform/index.md)
- [Best Practices](../best-practices/index.md)
- [Reference](../reference/index.md)

## Sources

- [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/)
