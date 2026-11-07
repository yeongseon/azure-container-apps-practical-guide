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
    - claim: Azure Container Apps can send application console logs to a Log Analytics workspace for querying.
      source: https://learn.microsoft.com/en-us/azure/container-apps/logging
      verified: true
    - claim: Log Analytics uses Kusto Query Language to filter, summarize, and visualize collected log data.
      source: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-tutorial
      verified: true
---
# TLS Handshake Errors

Use this query to investigate ingress TLS configuration events such as certificate binding changes, SNI mismatch signals, and custom domain handshake failures.

## Data Source

| Table | Schema Note |
|---|---|
| `ContainerAppSystemLogs_CL` | This query uses the legacy Log Analytics schema (`_CL` table and `_s` columns). Translate both the table and column names before using a resource-specific schema. |

## Query Pipeline

<!-- diagram-id: query-pipeline -->
```mermaid
flowchart TD
    accTitle: Query legacy system logs for TLS and custom-domain signals
    accDescr: The query selects one app, keeps TLS, certificate, custom-domain, SNI, hostname, and binding terms, projects revision and reason context, and sorts results from newest to oldest.

    SOURCE[Legacy system logs<br/>ContainerAppSystemLogs_CL] --> APP[Select ContainerAppName_s]
    APP --> SIGNALS[Keep TLS, certificate,<br/>SNI, hostname, and binding terms]
    SIGNALS --> CONTEXT[Project timestamp, revision,<br/>reason, and message]
    CONTEXT --> RESULT[Order newest first]
```

*Figure: The pipeline locates platform messages related to TLS configuration. These rows do not reproduce the client-side handshake or prove which certificate a client received.*

## Query

```kusto
let AppName = "my-container-app";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("TLS", "certificate", "custom domain", "SNI", "hostname", "binding")
| project TimeGenerated, RevisionName_s, Reason_s, Log_s
| order by TimeGenerated desc
```

## Example Output

| TimeGenerated | RevisionName_s | Reason_s | Log_s |
|---|---|---|---|
| 2026-04-12T09:22:41.118Z | ca-myapp--0000007 | CustomDomainUpdate | TLS certificate binding updated for host api.contoso.example |
| 2026-04-12T09:22:38.642Z | ca-myapp--0000007 | IngressConfiguration | SNI hostname api.contoso.example did not match active certificate binding |
| 2026-04-12T09:22:35.004Z | ca-myapp--0000007 | CertificateSync | custom domain certificate secret sync failed during handshake configuration refresh |

## Interpretation Notes

- SNI mismatch signals usually point to hostname-to-certificate binding drift or an incomplete custom domain rollout.
- Certificate sync failures can explain why clients see intermittent TLS errors even when the app revision is healthy.
- Normal pattern: certificate binding updates are rare and align with planned ingress or custom domain changes.

## Limitations

- System logs expose platform TLS events, not full client-side certificate negotiation details.
- Exact handshake symptoms still need correlation with caller telemetry or browser output.

## See Also

- [Ingress Error Analysis](ingress-error-analysis.md)
- [DNS and Connectivity Failures](dns-and-connectivity-failures.md)

## Sources

- [Microsoft Learn source 1](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Microsoft Learn source 2](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Microsoft Learn source 3](https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting)
- [Microsoft Learn source 4](https://learn.microsoft.com/en-us/azure/container-apps/logging)
- [Microsoft Learn source 5](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-tutorial)
