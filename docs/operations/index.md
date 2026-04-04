# Operations: Running Container Apps in Production

This section covers **day-2 operations** for running workloads on Azure Container Apps in production, including deployment, management, monitoring, and recovery.

While the [Platform](../platform/index.md) section covers how to *design* your architecture, the Operations hub focuses on how to *run* it effectively.

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

## Operations Areas

-   **[Deployment](deployment/networking.md)**: Standardized patterns for CI/CD and production rollouts.
-   **[Revision Management](revision-management/index.md)**: Lifecycle of immutable revisions and traffic splitting.
-   **[Monitoring](monitoring/index.md)**: Logs, metrics, distributed tracing, and Log Analytics integration.
-   **[Scaling](scaling/index.md)**: Managing KEDA scale rules, manual scaling, and concurrency limits.
-   **[Alerts](monitoring/index.md)**: Setting up SLO-driven alerts for availability, latency, and resource usage.
-   **[Image Pull & Registry](deployment/networking.md)**: Authenticating to private registries using managed identity.
-   **[Secret Rotation](../platform/identity-and-secrets/security-operations.md)**: Securely updating credentials without downtime.
-   **[Recovery](../platform/reliability/health-recovery.md)**: Handling failed revisions, pod restarts, and regional outages.

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

## Advanced Topics

- Build a production runbook with change windows, rollback criteria, and ownership.
- Automate common operations with GitHub Actions or Azure DevOps.
- Define SLO-driven alerts that map directly to customer-facing impact.

## See Also

- [Platform - Architecture](../platform/index.md)
- [Troubleshooting Hub](../troubleshooting/index.md)
- [Language Guides](../language-guides/index.md)
