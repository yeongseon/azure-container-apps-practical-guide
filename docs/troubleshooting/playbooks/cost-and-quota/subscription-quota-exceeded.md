---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/quotas
  diagrams:
    - id: subscription-quota-exceeded-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/quotas
        - https://learn.microsoft.com/en-us/azure/quotas/quickstart-increase-quota-portal
        - https://learn.microsoft.com/en-us/azure/container-apps/environment
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: agent
  core_claims:
    - claim: Azure Container Apps quota limits are enforced at least at the subscription and region scope.
      source: https://learn.microsoft.com/en-us/azure/container-apps/quotas
      verified: true
    - claim: Azure exposes Container Apps usage information for an environment through Azure CLI.
      source: https://learn.microsoft.com/en-us/azure/container-apps/quotas
      verified: true
    - claim: Quota increases can be requested through the Azure Usage + quotas experience.
      source: https://learn.microsoft.com/en-us/azure/quotas/quickstart-increase-quota-portal
      verified: true
---
# Subscription Quota Exceeded

## Symptom

Deployments, revisions, or scale operations fail with messages such as `QuotaExceeded`, `The subscription does not have enough quota to create the resource`, or `Maximum Allowed Cores exceeded for the Managed Environment.` The environment can remain in a failed or partially provisioned state while the app never reaches the requested replica count.

<!-- diagram-id: subscription-quota-exceeded-flow -->
```mermaid
flowchart TD
    accTitle: Diagnose a Container Apps quota failure
    accDescr: A create or scale operation is compared with environment usage and subscription-region quota before the operator reduces demand or requests more quota.

    REQUEST[Create environment, deploy revision, or scale replicas]
    SCOPE{Which limit rejected the request?}
    ENVIRONMENT[Managed environment usage and limit]
    REGIONAL[Subscription and region quota]
    CAPACITY{Requested capacity fits?}
    PROVISION[Operation can continue]
    BLOCKED[Quota or limit error]
    ACTION[Reduce demand, use another region, or request an increase]

    REQUEST --> SCOPE
    SCOPE -->|Environment usage| ENVIRONMENT
    SCOPE -->|Subscription and region| REGIONAL
    ENVIRONMENT --> CAPACITY
    REGIONAL --> CAPACITY
    CAPACITY -->|Yes| PROVISION
    CAPACITY -->|No| BLOCKED
    BLOCKED --> ACTION

    LEGEND["Arrow key<br/>solid = diagnostic progression"]
```

*Figure: Distinguish managed-environment usage from subscription-and-region quota before selecting a mitigation.*

## Possible Causes

- Regional core quota for Azure Container Apps is already consumed by existing environments or replicas.
- Public IP or related regional quota is exhausted before compute quota is exhausted.
- The requested replica count or CPU allocation pushes the managed environment past its allowed core envelope.
- A new environment is being created in a region where the subscription has insufficient Container Apps capacity.

## Diagnosis Steps

1. Capture the exact Azure error text from the failed deployment, revision event, or CLI response.
2. Check whether the environment itself is healthy:

```bash
az containerapp env show \
    --name "$ACA_ENV_NAME" \
    --resource-group "$RG" \
    --query "properties.provisioningState" \
    --output tsv
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp env show` | Returns the environment provisioning state to distinguish a quota rejection from an app-level deployment failure. |
| `--name` (`az containerapp env show`) | Checks `$ACA_ENV_NAME`, the environment whose provisioning request reported insufficient quota. |
| `--resource-group` (`az containerapp env show`) | Finds the target in `$RG`, keeping this lookup within the deployment being diagnosed. |
| `--query` (`az containerapp env show`) | Selects the environment provisioning state to distinguish a completed deployment from one blocked during capacity allocation. |
| `--output` (`az containerapp env show`) | Prints the provisioning state as plain text for an immediate success-or-failure check. |


3. Inspect current environment usage:

```bash
az containerapp env list-usages \
    --name "$ACA_ENV_NAME" \
    --resource-group "$RG"
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp env list-usages` | Returns the managed-environment usage counters and limits that can block another workload-profile or replica allocation. |
| `--name` (`az containerapp env list-usages`) | Checks capacity consumption for `$ACA_ENV_NAME`, the environment reporting the quota-related deployment failure. |
| `--resource-group` (`az containerapp env list-usages`) | Finds `$ACA_ENV_NAME` in `$RG` so the usage evidence comes from the affected environment. |


4. Inspect subscription quota for the target region:

```bash
az quota list \
    --scope "/subscriptions/<subscription-id>/providers/Microsoft.App/locations/$LOCATION"
```

| Command/Parameter | Purpose |
|---|---|
| `az quota list` | Returns Microsoft.App quota limits and current usage for the selected subscription and region. |
| `--scope` (`az quota list`) | Queries the Microsoft.App provider scope for `$LOCATION`, where the deployment exhausted capacity. |


5. Compare the requested scale change with the current usage numbers. If the gap between current usage and requested capacity is smaller than the requested increase, quota is the likely blocker.
6. In the Azure portal, open **Subscriptions** → **Usage + quotas** and confirm whether the same region shows a pending or exhausted quota state.

## Resolution

1. **Reduce demand temporarily** by lowering `minReplicas`, `maxReplicas`, or per-replica CPU/memory so the request fits inside the current quota.
2. **Retry in another region** if the workload is portable and that region has available quota.
3. **Request a quota increase** through **Usage + quotas** for the affected region.
4. **Re-run the failed operation** only after quota shows available capacity.

Typical mitigation command:

```bash
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --min-replicas 1 \
    --max-replicas 2 \
    --cpu 0.5 \
    --memory "1Gi"
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp update` | Reduces replica and per-replica resource demand so the app fits within the available subscription quota. |
| `--name` (`az containerapp update`) | Targets `$APP_NAME`, the workload whose requested replicas and resource size exceeded available quota. |
| `--resource-group` (`az containerapp update`) | Finds the quota-constrained app in `$RG` before changing its resource envelope. |
| `--min-replicas` (`az containerapp update`) | Reduces always-on demand to one replica. |
| `--max-replicas` (`az containerapp update`) | Caps scale-out at two replicas while quota is constrained. |
| `--cpu` (`az containerapp update`) | Requests `0.5` vCPU per replica to lower core consumption. |
| `--memory` (`az containerapp update`) | Requests `1Gi` per replica to shrink the app's memory envelope. |


## Prevention

- Add a quota pre-check to deployment runbooks for every production region.
- Track environment usage growth before planned scale events, large promotions, or seasonal traffic.
- Separate high-growth workloads so one environment does not unexpectedly consume the whole regional budget.
- Keep a documented fallback region for workloads that must deploy while a quota increase is pending.

## See Also

- [Subscription Quota Exceeded Lab](../../lab-guides/subscription-quota-exceeded.md)
- [Azure Container Apps Limits and Quotas](../../../platform/environments/limits-and-quotas.md)
- [Azure Container Apps Platform Limits and Quotas](../../../reference/platform-limits.md)
- [Cost-Aware Best Practices](../../../best-practices/cost.md)

## Sources

- [Microsoft Learn: Azure Container Apps quotas](https://learn.microsoft.com/en-us/azure/container-apps/quotas)
- [Microsoft Learn: Quickstart to request a quota increase in the Azure portal](https://learn.microsoft.com/en-us/azure/quotas/quickstart-increase-quota-portal)
- [Microsoft Learn: Azure Container Apps environment](https://learn.microsoft.com/en-us/azure/container-apps/environment)
