# Dapr Sidecar Logs

Use this query when Dapr sidecar startup, component loading, or invocation behaviors are failing.

## Data Source

| Table | Schema Note |
|---|---|
| `ContainerAppConsoleLogs_CL` | Legacy schema. If empty, try `ContainerAppConsoleLogs` (non-`_CL`). |

## Query Pipeline

```mermaid
flowchart LR
    A[Filter by app] --> B[Filter Dapr and component terms] --> C[Project runtime context] --> D[Sort by time]
```

## Query

```kusto
let AppName = "my-container-app";
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("dapr", "sidecar", "component", "pubsub", "state", "invoke")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

## Example Output

| TimeGenerated | RevisionName_s | Log_s |
|---|---|---|
| 2026-04-04T11:39:03.024Z | ca-myapp--0000001 | dapr sidecar started. app id=ca-myapp |
| 2026-04-04T11:39:03.410Z | ca-myapp--0000001 | component loaded: statestore (redis) |
| 2026-04-04T11:39:14.102Z | ca-myapp--0000001 | invoke error: target app not found |

## Interpretation Notes

- Component initialization errors usually include metadata or auth hints.
- Sidecar health failures often appear before app-level request failures.
- Normal pattern: startup logs then low-error steady-state operation.

## Limitations

- Requires Dapr logs to be routed into console log stream.
- May include app logs that mention `dapr` without sidecar failure.

## See Also

- [Job Execution History](job-execution-history.md)
- [Dapr Sidecar or Component Failure Playbook](../../playbooks/platform-features/dapr-sidecar-or-component-failure.md)
