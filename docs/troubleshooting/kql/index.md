# KQL Queries

Set once in Log Analytics:

```kusto
let AppName = "my-python-app";
```

## App Logs (Console)

### Latest errors/exceptions

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("error", "exception", "traceback")
| project TimeGenerated, RevisionName_s, ReplicaName_s, Log_s
| order by TimeGenerated desc
```

### Request latency from app logs (if logged)

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has "duration_ms"
| parse Log_s with * "duration_ms=" duration:long *
| summarize p50=percentile(duration, 50), p95=percentile(duration, 95), max=max(duration) by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

### Top noisy messages

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| summarize count() by Log_s
| top 20 by count_
```

## System Logs

### Revision failures and startup problems

```kusto
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("Failed", "CrashLoopBackOff", "ImagePull", "probe", "timeout")
| project TimeGenerated, RevisionName_s, Log_s, Reason_s
| order by TimeGenerated desc
```

### Image pull/auth errors

```kusto
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("pull", "unauthorized", "manifest", "denied")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

## Revision Health

### Errors by revision

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("error", "exception", "traceback")
| summarize errors=count() by RevisionName_s
| order by errors desc
```

### Replica crash signals

```kusto
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("exited", "terminated", "restart")
| summarize events=count() by ReplicaName_s, RevisionName_s
| order by events desc
```

## Correlation with OpenTelemetry (App Insights)

### Failed requests (Application Insights workspace-based)

```kusto
requests
| where cloud_RoleName == AppName
| where success == false
| project timestamp, name, resultCode, duration, operation_Id
| order by timestamp desc
```

### Link exceptions to operation IDs

```kusto
exceptions
| where cloud_RoleName == AppName
| project timestamp, type, outerMessage, operation_Id
| order by timestamp desc
```

## Schema Note

| Workspace table | Common columns |
| --- | --- |
| `ContainerAppConsoleLogs_CL` | `ContainerAppName_s`, `RevisionName_s`, `ReplicaName_s`, `Log_s` |
| `ContainerAppSystemLogs_CL` | `ContainerAppName_s`, `RevisionName_s`, `ReplicaName_s`, `Log_s`, `Reason_s` |
| `ContainerAppConsoleLogs` | Newer schema in some workspaces |
| `ContainerAppSystemLogs` | Newer schema in some workspaces |

If `_CL` tables are empty, check non-`_CL` tables in your workspace.

## References
- [Log monitoring in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/log-monitoring)
- [ContainerAppConsoleLogs table reference (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerappconsolelogs)
- [ContainerAppSystemLogs table reference (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerappsystemlogs)
