---
content_sources:
  diagrams:
    - id: use-this-page-as-a-quick
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/quotas
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: ai-agent
  core_claims:
    - claim: Azure Container Apps can scale to zero when the minimum replica count is set to 0.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
    - claim: Azure Container Apps revisions are immutable snapshots of a container app version.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: Azure Container Apps supports splitting traffic between active revisions.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: Azure Container Apps documents quotas and limits for the service.
      source: https://learn.microsoft.com/en-us/azure/container-apps/quotas
      verified: true
---
# Platform Limits

Use this page as a quick checkpoint before scaling, rollout, or incident response.

<!-- diagram-id: use-this-page-as-a-quick -->
```mermaid
flowchart TD
    accTitle: Decide whether a workload fits synchronous Container Apps ingress and scaling constraints
    accDescr: Check request duration, replica sizing, scaling bounds, and subscription quota. Long-running work branches to an asynchronous pattern, while synchronous work continues through capacity checks.

    REQ["Incoming workload"]
    DURATION{"Can the operation finish<br/>within the documented<br/>ingress request timeout?"}
    ASYNC["Use an asynchronous pattern<br/>such as a queue and worker"]
    SIZING{"Does one replica have<br/>enough CPU and memory?"}
    RESIZE["Adjust container<br/>CPU and memory"]
    BOUNDS{"Do min/max replicas and<br/>the scale rule cover demand?"}
    TUNE["Adjust replica bounds<br/>or scaling threshold"]
    QUOTA{"Does subscription quota<br/>allow the requested capacity?"}
    REQUEST["Review quota usage<br/>or request an increase"]
    READY["Proceed with a bounded<br/>load test"]

    REQ --> DURATION
    DURATION -->|No| ASYNC
    DURATION -->|Yes| SIZING
    SIZING -->|No| RESIZE
    SIZING -->|Yes| BOUNDS
    BOUNDS -->|No| TUNE
    BOUNDS -->|Yes| QUOTA
    QUOTA -->|No| REQUEST
    QUOTA -->|Yes| READY
```

Each decision has an explicit remediation branch. Passing the checks does not prove production capacity; it establishes the inputs for a bounded load test.

## Common Limits and Timeouts

| Area | Typical value / behavior | Notes |
| --- | --- | --- |
| Ingress request timeout | ~240 seconds | Long-running HTTP should move to async/background patterns |
| Scale to zero | Supported (`minReplicas=0`) | First request may incur cold start latency |
| Revision model | Immutable revisions | Any template/config change creates a new revision |
| Log ingestion delay | Usually 1-2 minutes | Use `az containerapp logs show --follow` for near real-time |
| Traffic split granularity | Percentage per active revision | Multiple revision mode required |

## Resource Sizing Reference

| Setting | Where configured | Practical guidance |
| --- | --- | --- |
| CPU / Memory per replica | Container template resources | Right-size for startup + peak load |
| `minReplicas` | Scale section | `0` for cost, `>=1` for lower latency |
| `maxReplicas` | Scale section | Set high enough for burst traffic |
| HTTP concurrency threshold | HTTP scale rule | Lower value = faster scale-out |

## Quota / Capacity Checks

```bash
# Region resource availability and subscription constraints
az containerapp env list --resource-group "$RG"

# Current app scaling bounds
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.template.scale"
```

| Command | Purpose |
|---|---|
| `az containerapp env list` | Lists environments in the resource group before capacity and quota investigation. |
| `az containerapp show` | Reads the selected app's configured scale bounds and rules. |
| `--resource-group` | Selects the resource group containing the environments and app. |
| `--name` | Selects the Container App inspected by `az containerapp show`. |
| `--query` | Makes `az containerapp show` extract only `properties.template.scale` from the app resource. |

Observed baseline before limit testing:

```text
$ az containerapp show --name "$APP_NAME" --resource-group "$RG" --query provisioningState --output tsv
Succeeded

$ az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
Name               Active    TrafficWeight    Replicas    HealthState    RunningState
-----------------  --------  ---------------  ----------  -------------  ------------
ca-myapp--0000001  True      100              1           Healthy        Running
```

## Symptoms That Often Indicate Limits

| Symptom | Likely limit area | First action |
| --- | --- | --- |
| Frequent 504s on heavy endpoints | Ingress timeout | Move to async job pattern; shorten sync request path |
| High latency after idle period | Scale-to-zero cold start | Increase `minReplicas` |
| Throttled/slow during burst | `maxReplicas` too low or high concurrency target | Raise `maxReplicas`, lower concurrency threshold |
| New revision unhealthy under load | CPU/memory under-sized | Increase container resources |

## Design Guardrails

| Workload type | Recommendation |
| --- | --- |
| API calls < 30s | Standard HTTP ingress pattern |
| API calls 30-240s | Careful timeout handling, aggressive observability |
| API calls > 240s | Queue + worker revision (non-HTTP trigger) |
| High burst traffic | Pre-warm with `minReplicas >= 1` + tuned scale rules |

For architecture-level implications, see [How Container Apps Works](../../start-here/overview.md).
## See Also

- [Repository map](../../start-here/repository-map.md)
## Sources
- [Azure Container Apps quotas and limits (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/quotas)
- [Container Apps scale rules and replicas (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
