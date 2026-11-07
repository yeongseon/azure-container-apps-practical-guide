---
description: KQL queries for correlating Azure Container Apps restart signals with application startup and shutdown evidence across supported log schemas.
content_sources:
  diagrams:
    - id: query-pipeline-overview
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring
        - https://learn.microsoft.com/en-us/azure/container-apps/health-probes
        - https://learn.microsoft.com/en-us/kusto/query/
---
# Restarts Query Pack

Queries for analyzing container and replica restart patterns in Azure Container Apps. Use these to correlate restarts with latency spikes and error incidents.

## Data Sources

| Table | Description |
|---|---|
| `ContainerAppSystemLogs_CL` | Platform events including restart signals |
| `ContainerAppConsoleLogs_CL` | Application logs showing shutdown/startup sequences |

!!! note "Schema Variation"
    The queries in this pack use the legacy direct Log Analytics schema: `ContainerAppConsoleLogs_CL` and `ContainerAppSystemLogs_CL`, with fields such as `Log_s`, `RevisionName_s`, and `ContainerGroupName_s`. Azure Monitor diagnostic settings instead populate the resource-specific `ContainerAppConsoleLogs` and `ContainerAppSystemLogs` tables, whose corresponding fields include `Log`, `RevisionName`, and `ReplicaName`. Choose the query variant for the ingestion path; do not only remove the `_CL` suffix because the column names also differ.

## Query Pipeline Overview

<!-- diagram-id: query-pipeline-overview -->
```mermaid
flowchart TD
    accTitle: Build restart evidence from legacy Container Apps logs
    accDescr: Platform system logs provide restart and lifecycle signals while application console logs provide shutdown and startup context. The investigation aligns both sources by time, revision, and replica before testing a root-cause hypothesis.

    SOURCES[Legacy system and console logs<br/>platform plus application evidence] --> SCOPE[Scope app and incident window]
    SCOPE --> ALIGN[Align timestamps,<br/>revisions, and replicas]
    ALIGN --> PATTERN[Identify repeated or<br/>clustered restart patterns]
    PATTERN --> HYPOTHESIS[Test a root-cause hypothesis<br/>with supporting evidence]
```

*Figure: Restart analysis correlates platform and application evidence. Temporal alignment supports an investigation but does not by itself prove why a replica restarted.*

## Available Queries

| Query | Purpose |
|---|---|
| [Restart Timing Correlation](restart-timing-correlation.md) | Correlate restarts with incident windows |
| [Repeated Startup Attempts](repeated-startup-attempts.md) | Detect crash loops and startup failures |

## When to Use

- Latency or error spikes coincide with unknown events
- Users report intermittent failures
- Replica count fluctuations in monitoring
- Post-deployment stability analysis

## Container Apps Restart Triggers

| Trigger | Reason_s Pattern | Description |
|---|---|---|
| Probe failure | `ProbeFailed` | Liveness/readiness probe failed |
| OOM kill | `ContainerTerminated`, `OOMKilled` | Memory limit exceeded |
| Crash | `ContainerTerminated`, `Error` | Application crash or unhandled exception |
| Scaling | `AssigningReplica`, `TerminatingReplica` | KEDA scale-in/out events |
| Revision update | `RevisionUpdate` | New revision deployed |
| Platform maintenance | `ContainerRestarted` | Platform-initiated restart |

## See Also

- [KQL Query Catalog](../index.md)
- [Replica Crash Signals](../system-and-revisions/replica-crash-signals.md)
- [Revision Failures and Startup](../system-and-revisions/revision-failures-and-startup.md)

## Sources

- [Log monitoring in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring)
- [Health probes in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/health-probes)
- [Kusto Query Language (KQL) overview](https://learn.microsoft.com/en-us/kusto/query/)
