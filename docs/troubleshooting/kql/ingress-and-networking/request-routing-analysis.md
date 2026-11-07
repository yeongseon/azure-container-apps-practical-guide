---
content_sources:
  diagrams:
    - id: query-pipeline
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: ai-agent
  core_claims:
    - claim: Azure Container Apps can send system logs that record platform events to a Log Analytics workspace.
      source: https://learn.microsoft.com/en-us/azure/container-apps/logging
      verified: true
    - claim: Log Analytics uses Kusto Query Language to filter, summarize, and visualize collected log data.
      source: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-tutorial
      verified: true
---
# Request Routing Analysis

Use this query to trace ingress routing decisions such as path matching, revision selection, and traffic split changes.

## Data Source

| Table | Schema Note |
|---|---|
| `ContainerAppSystemLogs_CL` | This query uses the legacy Log Analytics schema (`_CL` table and `_s` columns). Translate both the table and column names before using a resource-specific schema. |

## Query Pipeline

<!-- diagram-id: query-pipeline -->
```mermaid
flowchart TD
    accTitle: Query legacy system logs for routing-related signals
    accDescr: The query selects one app, keeps routing, path, traffic split, and revision terms, projects revision and reason context, and sorts the evidence from newest to oldest.

    SOURCE[Legacy system logs<br/>ContainerAppSystemLogs_CL] --> APP[Select ContainerAppName_s]
    APP --> SIGNALS[Keep route, path,<br/>traffic split, and revision terms]
    SIGNALS --> CONTEXT[Project timestamp, revision,<br/>reason, and message]
    CONTEXT --> RESULT[Order newest first]
```

*Figure: The query finds routing-related platform text; it is not an end-to-end request trace. Validate actual request paths and selected replicas with ingress HTTP telemetry when that diagnostic category is enabled.*

## Query

```kusto
let AppName = "my-container-app";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("route", "routing", "path", "traffic split", "matched", "revision")
| project TimeGenerated, RevisionName_s, Reason_s, Log_s
| order by TimeGenerated desc
```

## Example Output

| TimeGenerated | RevisionName_s | Reason_s | Log_s |
|---|---|---|---|
| 2026-04-12T09:14:37.904Z | ca-myapp--0000007 | TrafficWeightUpdate | ingress routing updated traffic split: ca-myapp--0000007=90, ca-myapp--0000006=10 |
| 2026-04-12T09:14:33.287Z | ca-myapp--0000007 | RequestRouting | request matched path prefix /api/orders and routed to revision ca-myapp--0000007 |
| 2026-04-12T09:14:28.551Z | ca-myapp--0000006 | RequestRouting | request matched catch-all path / and routed to revision ca-myapp--0000006 |

## Interpretation Notes

- Routing entries that suddenly switch revisions can explain behavior differences during rollout windows.
- Repeated fallback to catch-all paths suggests an ingress rule mismatch or unexpected request path shape.
- Normal pattern: path matches and traffic split updates align with intentional revision deployment activity.

## Limitations

- System logs show platform routing signals, not complete end-to-end application request traces.
- Path-level detail depends on what ingress events are emitted in the environment.

## See Also

- [Ingress Error Analysis](ingress-error-analysis.md)
- [Timeout and Retry Patterns](timeout-and-retry-patterns.md)

## Sources

- [Microsoft Learn source 1](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Microsoft Learn source 2](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Microsoft Learn source 3](https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting)
- [Microsoft Learn source 4](https://learn.microsoft.com/en-us/azure/container-apps/logging)
- [Microsoft Learn source 5](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-tutorial)
