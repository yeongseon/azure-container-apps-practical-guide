---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/billing
  diagrams:
    - id: min-replicas-cost-surprise-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/billing
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app
        - https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: agent
  core_claims:
    - claim: Azure Container Apps uses per-revision scale settings including minimum replica count.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
    - claim: Scale-to-zero affects Azure Container Apps billing behavior.
      source: https://learn.microsoft.com/en-us/azure/container-apps/billing
      verified: true
    - claim: Workload profiles change the cost model because dedicated capacity is reserved at the profile level.
      source: https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
      verified: true
---
# Min Replicas Cost Surprise

## Symptom

There is no runtime failure, but Azure Cost Management shows continuous spend during quiet periods. The app appears idle, yet charges continue because at least one replica or one dedicated node stays allocated.

<!-- diagram-id: min-replicas-cost-surprise-flow -->
```mermaid
flowchart TD
    accTitle: Diagnose baseline cost during quiet periods
    accDescr: Decide whether revision minimum replicas or dedicated workload profile instances explain continuing Container Apps charges during low traffic.

    QUIET[Little or no application traffic]
    PLAN{Consumption or Dedicated plan?}
    MIN{Minimum replicas greater than zero?}
    IDLE[At least one replica remains allocated]
    ZERO[Revision can scale to zero]
    PROFILE[Workload profile instances remain allocated]
    COST[Review the applicable idle or dedicated charges]

    QUIET --> PLAN
    PLAN -->|Consumption| MIN
    PLAN -->|Dedicated| PROFILE
    MIN -->|Yes| IDLE
    MIN -->|No| ZERO
    IDLE --> COST
    PROFILE --> COST

    LEGEND["Arrow key<br/>solid = diagnostic progression"]
```

*Figure: Separate app-level minimum replicas from Dedicated plan workload profile capacity before attributing quiet-period cost.*

## Possible Causes

- `minReplicas` is set to `1` or higher on a workload that is idle for long periods.
- Multiple active revisions each keep a baseline replica.
- The app runs in a dedicated workload profile, so node cost remains even when traffic is light.
- A performance optimization kept replicas warm without documenting the ongoing cost trade-off.

## Diagnosis Steps

1. Inspect the app scale configuration:

```bash
az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "properties.template.scale" \
    --output json
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the selected Container App so the operator can evaluate the template scale evidence. |
| `--name` (`az containerapp show`) | Selects `$APP_NAME`, the resource whose state contributes to the Azure state that distinguishes this hypothesis. |
| `--resource-group` (`az containerapp show`) | Finds the target in `$RG`, keeping this lookup within the deployment being diagnosed. |
| `--query` (`az containerapp show`) | Returns only the scale block so `minReplicas` and its cost-driving baseline are visible together. |
| `--output` (`az containerapp show`) | Emits the response as `json` so the decisive fields remain usable in this diagnostic step. |


2. Check whether more than one active revision is holding replicas:

```bash
az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "[].{name:name,active:properties.active,replicas:properties.replicas}"
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp revision list` | Lists revisions and their current lifecycle state to evaluate the Azure state that distinguishes this hypothesis. |
| `--name` (`az containerapp revision list`) | Selects `$APP_NAME`, the resource whose state contributes to the Azure state that distinguishes this hypothesis. |
| `--resource-group` (`az containerapp revision list`) | Finds the target in `$RG`, keeping this lookup within the deployment being diagnosed. |
| `--query` (`az containerapp revision list`) | Shapes each revision into its name, active state, and replica count to reveal which revisions keep billable replicas running. |


3. Review the replica metric during an idle window:

```bash
az monitor metrics list \
    --resource "/subscriptions/<subscription-id>/resourceGroups/$RG/providers/Microsoft.App/containerApps/$APP_NAME" \
    --metric Replicas \
    --aggregation Average \
    --offset 1d
```

| Command/Parameter | Purpose |
|---|---|
| `az monitor metrics list` | Lists `az monitor metrics list` to obtain or change the Azure state that distinguishes this hypothesis. |
| `--resource` (`az monitor metrics list`) | Sets the resource input to `/subscriptions/<subscription-id>/resourceGroups/$RG/providers/Microsoft…`, the value used by `az monitor metrics list` to evaluate or correct the Azure state that distinguishes this hypothesis. |
| `--metric` (`az monitor metrics list`) | Sets the metric input to `Replicas`, the value used by `az monitor metrics list` to evaluate or correct the Azure state that distinguishes this hypothesis. |
| `--aggregation` (`az monitor metrics list`) | Sets the aggregation input to `Average`, the value used by `az monitor metrics list` to evaluate or correct the Azure state that distinguishes this hypothesis. |
| `--offset` (`az monitor metrics list`) | Limits the replica series to the preceding 24 hours so idle periods remain visible in the cost investigation. |


4. If the environment uses dedicated workload profiles, check whether the issue is actually reserved node cost instead of app-level runtime cost.

## Resolution

1. **Set `minReplicas` to `0`** for workloads that can tolerate cold starts:

```bash
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --min-replicas 0 \
    --max-replicas 3
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp update` | Lowers the idle replica floor so this workload can stop accruing replica runtime cost when no requests arrive. |
| `--name` (`az containerapp update`) | Applies the scale-to-zero correction to `$APP_NAME`, the app whose idle replicas produced the measured cost. |
| `--resource-group` (`az containerapp update`) | Locates `$APP_NAME` in `$RG` before changing its scale bounds. |
| `--min-replicas` (`az containerapp update`) | Sets the min replicas input to `0`, the value used by `az containerapp update` to evaluate or correct the Azure state that distinguishes this hypothesis. |
| `--max-replicas` (`az containerapp update`) | Sets the max replicas input to `3`, the value used by `az containerapp update` to evaluate or correct the Azure state that distinguishes this hypothesis. |


2. **Keep `minReplicas` above zero intentionally** only when latency, cache warmness, or queue pickup time justifies the baseline spend.
3. **Reduce active revisions** if old revisions are still holding warm replicas.
4. **Right-size dedicated profiles** when the real cost driver is reserved dedicated capacity rather than `minReplicas` itself.

| Command | Why it is used |
|---|---|
| `az containerapp update --min-replicas 0 --max-replicas 3` | Removes the always-on replica baseline for workloads that can scale to zero. |

## Prevention

- Treat `minReplicas` as a cost decision, not only a performance setting.
- Document which apps are allowed to scale to zero and which must stay warm.
- Review idle replica metrics during monthly cost reviews.
- When using dedicated workload profiles, separate app-level replica tuning from environment-level node reservation decisions.

## See Also

- [Min Replicas Cost Surprise Lab](../../lab-guides/min-replicas-cost-surprise.md)
- [Cold Start and Scale-to-Zero Lab](../../lab-guides/cold-start-scale-to-zero.md)
- [Cost-Aware Best Practices](../../../best-practices/cost.md)
- [Workload Profiles](../../../platform/environments/workload-profiles.md)

## Sources

- [Microsoft Learn: Azure Container Apps billing](https://learn.microsoft.com/en-us/azure/container-apps/billing)
- [Microsoft Learn: Set scaling rules in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Microsoft Learn: Workload profiles in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview)
