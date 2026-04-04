# KQL Queries

Use this section as a query catalog. Each page includes scenario context, data-source notes, query pipeline, interpretation guidance, and limitations.

## Schema Note

| Workspace table | Common columns |
| --- | --- |
| `ContainerAppConsoleLogs_CL` | `ContainerAppName_s`, `RevisionName_s`, `ReplicaName_s`, `Log_s` |
| `ContainerAppSystemLogs_CL` | `ContainerAppName_s`, `RevisionName_s`, `ReplicaName_s`, `Log_s`, `Reason_s` |
| `ContainerAppConsoleLogs` | Newer schema in some workspaces |
| `ContainerAppSystemLogs` | Newer schema in some workspaces |

If `_CL` tables are empty, check non-`_CL` tables in your workspace.

## Query Categories

### System and Revisions

- [Revision Failures and Startup](system-and-revisions/revision-failures-and-startup.md)
- [Image Pull and Auth Errors](system-and-revisions/image-pull-and-auth-errors.md)
- [Replica Crash Signals](system-and-revisions/replica-crash-signals.md)

### Console and Runtime

- [Latest Errors and Exceptions](console-and-runtime/latest-errors-and-exceptions.md)
- [Request Latency from Logs](console-and-runtime/request-latency-from-logs.md)
- [Top Noisy Messages](console-and-runtime/top-noisy-messages.md)

### Ingress and Networking

- [Ingress Error Analysis](ingress-and-networking/ingress-error-analysis.md)
- [DNS and Connectivity Failures](ingress-and-networking/dns-and-connectivity-failures.md)

### Scaling and Replicas

- [Scaling Events](scaling-and-replicas/scaling-events.md)
- [Replica Count Over Time](scaling-and-replicas/replica-count-over-time.md)

### Identity and Secrets

- [Managed Identity Token Errors](identity-and-secrets/managed-identity-token-errors.md)
- [Secret Reference Failures](identity-and-secrets/secret-reference-failures.md)

### Dapr and Jobs

- [Dapr Sidecar Logs](dapr-and-jobs/dapr-sidecar-logs.md)
- [Job Execution History](dapr-and-jobs/job-execution-history.md)

### Correlation

- [Errors by Revision](correlation/errors-by-revision.md)
- [Failed Requests App Insights](correlation/failed-requests-app-insights.md)
- [Link Exceptions to Operations](correlation/link-exceptions-to-operations.md)

## References
- [Log monitoring in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/log-monitoring)
- [ContainerAppConsoleLogs table reference (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerappconsolelogs)
- [ContainerAppSystemLogs table reference (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerappsystemlogs)
