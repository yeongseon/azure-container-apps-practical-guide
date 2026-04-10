---
hide:
  - toc
content_sources:
  diagrams:
    - id: query-pipeline
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/observability
        - https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring
        - https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting
---

# Latest Errors and Exceptions

Use this query for quick inspection of recent application exceptions and error logs.

## Data Source

| Table | Schema Note |
|---|---|
| `ContainerAppConsoleLogs_CL` | Legacy schema. If empty, try `ContainerAppConsoleLogs` (non-`_CL`). |

## Query Pipeline

<!-- diagram-id: query-pipeline -->
```mermaid
flowchart LR
    A[Filter by app] --> B[Filter error patterns] --> C[Project key runtime fields] --> D[Sort by newest]
```

## Query

```kusto
let AppName = "my-container-app";
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("error", "exception", "traceback", "failed")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

## Example Output

| TimeGenerated | RevisionName_s | Log_s |
|---|---|---|
| 2026-04-04T11:41:12.917Z | ca-myapp--0000002 | ERROR: dependency call failed: connection refused |
| 2026-04-04T11:41:12.916Z | ca-myapp--0000002 | Traceback (most recent call last): RuntimeError: upstream timeout |
| 2026-04-04T11:40:58.104Z | ca-myapp--0000002 | request failed status=500 path=/api/items |

## Interpretation Notes

- Capture the first exception after deployment for root-cause context.
- Compare error text across revisions to identify rollout regressions.
- Normal pattern: occasional warnings, not sustained exception streams.

## Limitations

- Requires app to emit logs to stdout/stderr.
- Large multi-line traces may be split across rows.

## See Also

- [Top Noisy Messages](top-noisy-messages.md)
- [Container Start Failure Playbook](../../playbooks/startup-and-provisioning/container-start-failure.md)
