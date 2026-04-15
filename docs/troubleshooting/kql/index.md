---
content_sources:
  diagrams:
    - id: use-this-section-as-a-query
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/log-monitoring
        - https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerappconsolelogs
        - https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerappsystemlogs
---

# KQL Queries

Use this section as a query catalog. Each page includes scenario context, data-source notes, query pipeline, interpretation guidance, and limitations.

<!-- diagram-id: use-this-section-as-a-query -->
```mermaid
flowchart TD
    subgraph Sources["Data Sources"]
        SYS["ContainerAppSystemLogs_CL"]
        CON["ContainerAppConsoleLogs_CL"]
    end
    subgraph Categories["Query Categories"]
        HTTP["HTTP"]
        RST["Restarts"]
        SYSREV["System and Revisions"]
        CONRT["Console and Runtime"]
        ING["Ingress and Networking"]
        SCL["Scaling and Replicas"]
        IDSEC["Identity and Secrets"]
        DAPR["Dapr and Jobs"]
        COR["Correlation"]
    end
    SYS --> RST
    SYS --> SYSREV
    SYS --> SCL
    SYS --> DAPR
    CON --> HTTP
    CON --> CONRT
    CON --> ING
    CON --> IDSEC
    SYS --> COR
    CON --> COR
```

## Schema Note

| Workspace table | Common columns |
| --- | --- |
| `ContainerAppConsoleLogs_CL` | `ContainerAppName_s`, `ContainerJobName_s`, `RevisionName_s`, `ContainerName_s`, `Log_s`, `Stream_s`, `ContainerImage_s`, `EnvironmentName_s`, `ContainerGroupName_s` |
| `ContainerAppSystemLogs_CL` | `ContainerAppName_s`, `RevisionName_s`, `Reason_s`, `Type_s`, `Log_s`, `Level`, `EventSource_s`, `ReplicaName_s`, `JobName_s`, `ExecutionName_s`, `EnvironmentName_s` |
| `ContainerAppConsoleLogs` | Newer schema in some workspaces |
| `ContainerAppSystemLogs` | Newer schema in some workspaces |

If `_CL` tables are empty, check non-`_CL` tables in your workspace.

## Sample Result

Real lifecycle summary from a deployed Container Apps environment (`ca-cakqltest-54kxmtjeuidri`, captured 2026-04-12):

| Reason_s | Type_s | count_ |
|---|---|---:|
| RevisionUpdate | Normal | 10 |
| ContainerAppUpdate | Normal | 7 |
| ContainerAppReady | Normal | 4 |
| RevisionReady | Normal | 3 |
| KEDAScalersStarted | Normal | 3 |
| RevisionDeactivating | Normal | 3 |
| RollingRevisionCompleted | Normal | 1 |
| AssigningReplica | Normal | 1 |
| ContainerStarted | Normal | 1 |
| PullingImage | Normal | 1 |
| PulledImage | Normal | 1 |
| ProbeFailed | Warning | 1 |
| ContainerCreated | Normal | 1 |

## Query Categories

### HTTP

- [HTTP Query Pack](http/index.md)
- [Latency Trend by Status Code](http/latency-trend-by-status-code.md)
- [5xx Trend Over Time](http/5xx-trend-over-time.md)
- [Slowest Requests by Path](http/slowest-requests-by-path.md)

### Restarts

- [Restarts Query Pack](restarts/index.md)
- [Restart Timing Correlation](restarts/restart-timing-correlation.md)
- [Repeated Startup Attempts](restarts/repeated-startup-attempts.md)

### System and Revisions

- [Revision Failures and Startup](system-and-revisions/revision-failures-and-startup.md)
- [Image Pull and Auth Errors](system-and-revisions/image-pull-and-auth-errors.md)
- [Replica Crash Signals](system-and-revisions/replica-crash-signals.md)
- [Health Probe Timeline](system-and-revisions/health-probe-timeline.md)
- [Deployment Progression](system-and-revisions/deployment-progression.md)

### Console and Runtime

- [Latest Errors and Exceptions](console-and-runtime/latest-errors-and-exceptions.md)
- [Request Latency from Logs](console-and-runtime/request-latency-from-logs.md)
- [Top Noisy Messages](console-and-runtime/top-noisy-messages.md)
- [Memory Usage Patterns](console-and-runtime/memory-usage-patterns.md)
- [Startup Duration Analysis](console-and-runtime/startup-duration-analysis.md)

### Ingress and Networking

- [Ingress Error Analysis](ingress-and-networking/ingress-error-analysis.md)
- [DNS and Connectivity Failures](ingress-and-networking/dns-and-connectivity-failures.md)
- [Request Routing Analysis](ingress-and-networking/request-routing-analysis.md)
- [TLS Handshake Errors](ingress-and-networking/tls-handshake-errors.md)
- [Timeout and Retry Patterns](ingress-and-networking/timeout-and-retry-patterns.md)

### Scaling and Replicas

- [Scaling Events](scaling-and-replicas/scaling-events.md)
- [Replica Count Over Time](scaling-and-replicas/replica-count-over-time.md)
- [KEDA Scaler Metrics](scaling-and-replicas/keda-scaler-metrics.md)
- [Scale-In Delay Analysis](scaling-and-replicas/scale-in-delay-analysis.md)
- [Replica Distribution by Revision](scaling-and-replicas/replica-distribution-by-revision.md)

### Identity and Secrets

- [Managed Identity Token Errors](identity-and-secrets/managed-identity-token-errors.md)
- [Secret Reference Failures](identity-and-secrets/secret-reference-failures.md)
- [Authentication Failure Timeline](identity-and-secrets/authentication-failure-timeline.md)
- [Key Vault Access Errors](identity-and-secrets/keyvault-access-errors.md)
- [Authentication Failure Timeline](identity-and-secrets/authentication-failure-timeline.md)
- [Key Vault Access Errors](identity-and-secrets/keyvault-access-errors.md)

### Dapr and Jobs

- [Dapr Sidecar Logs](dapr-and-jobs/dapr-sidecar-logs.md)
- [Job Execution History](dapr-and-jobs/job-execution-history.md)

### Correlation

- [Errors by Revision](correlation/errors-by-revision.md)
- [Failed Requests App Insights](correlation/failed-requests-app-insights.md)
- [Link Exceptions to Operations](correlation/link-exceptions-to-operations.md)

## See Also

- [Troubleshooting Hub](../index.md)
- [First 10 Minutes Checklist](../first-10-minutes/index.md)
- [Evidence Map](../evidence-map.md)

## Sources
- [Log monitoring in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/log-monitoring)
- [ContainerAppConsoleLogs table reference (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerappconsolelogs)
- [ContainerAppSystemLogs table reference (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/reference/tables/containerappsystemlogs)
