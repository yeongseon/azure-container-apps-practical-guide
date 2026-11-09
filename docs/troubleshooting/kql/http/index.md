---
description: KQL query pack for investigating Azure Container Apps HTTP latency, 5xx trends, and slow request paths with Application Insights or structured logs.
content_sources:
  diagrams:
    - id: query-pipeline-overview
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring
        - https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents
        - https://learn.microsoft.com/en-us/kusto/query/
---
# HTTP Query Pack

HTTP request analysis queries for Azure Container Apps. Use these to investigate latency, error rates, and request patterns.

## Data Sources

| Table | Description |
|---|---|
| `ContainerAppConsoleLogs_CL` | Application logs including HTTP request details |
| `requests` | Application Insights request telemetry (if configured) |
| `dependencies` | Application Insights dependency calls |

!!! note "Schema Variation"
    If `_CL` tables are empty, try the non-`_CL` variants (`ContainerAppConsoleLogs`).

## Query Pipeline Overview

<!-- diagram-id: query-pipeline-overview -->
```mermaid
flowchart TD
    accTitle: HTTP telemetry analysis pipeline
    accDescr: Select Application Insights request telemetry or structured legacy console logs, isolate HTTP records, extract request dimensions, calculate aggregates, and present trends or ranked paths.

    AI["Application Insights<br/>requests and dependencies"]
    CONSOLE["ContainerAppConsoleLogs_CL<br/>structured HTTP messages"]
    FILTER["Filter the target app,<br/>time window, and HTTP records"]
    EXTRACT["Read or parse status,<br/>duration, and request path"]
    AGGREGATE["Calculate counts,<br/>percentiles, or rates"]
    OUTPUT["Trend by time or<br/>rank by request path"]

    AI --> FILTER
    CONSOLE --> FILTER
    FILTER --> EXTRACT
    EXTRACT --> AGGREGATE
    AGGREGATE --> OUTPUT
```

Choose one schema before running a query. Application Insights uses request fields such as `resultCode` and `duration`; the legacy console-log fallback parses equivalent values from `Log_s` only when the application emits a consistent format.

## Available Queries

| Query | Purpose |
|---|---|
| [Latency Trend by Status Code](latency-trend-by-status-code.md) | P50/P95/P99 latency split by HTTP status |
| [5xx Trend Over Time](5xx-trend-over-time.md) | Server error volume and spike detection |
| [Slowest Requests by Path](slowest-requests-by-path.md) | Identify slow endpoints |

## When to Use

- Performance degradation reported by users
- Intermittent 5xx errors in monitoring alerts
- Latency SLA breaches
- Post-incident analysis of HTTP behavior

## See Also

- [KQL Query Catalog](../index.md)
- [Ingress Error Analysis](../ingress-and-networking/ingress-error-analysis.md)
- [Ingress Not Reachable Playbook](../../playbooks/ingress-and-networking/ingress-not-reachable.md)

## Sources

- [Log monitoring in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring)
- [Application Insights for Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents)
- [Kusto Query Language (KQL) overview](https://learn.microsoft.com/en-us/kusto/query/)
