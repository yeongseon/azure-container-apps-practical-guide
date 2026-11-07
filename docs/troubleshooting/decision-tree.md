---
description: Evidence-led Azure Container Apps decision trees that route incidents by revision health, HTTP outcomes, replicas, dependencies, and scaling signals.
content_sources:
  diagrams:
    - id: main-triage-decision-tree
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/overview
        - https://learn.microsoft.com/en-us/azure/container-apps/observability
        - https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting
        - https://learn.microsoft.com/en-us/azure/container-apps/health-probes
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app
        - https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring
        - https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/containerapphttplogs
    - id: 5xx-branch-deep-dive-tree
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/overview
        - https://learn.microsoft.com/en-us/azure/container-apps/observability
        - https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting
        - https://learn.microsoft.com/en-us/azure/container-apps/health-probes
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app
        - https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring
        - https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/containerapphttplogs
content_validation:
  status: verified
  last_reviewed: 2026-11-08
  reviewer: agent
  core_claims:
    - claim: ContainerAppHTTPLogs includes status, duration, revision, replica, and upstream fields for ingress-request diagnosis.
      source: https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/containerapphttplogs
      verified: true
    - claim: Health probe failures can prevent a revision from becoming healthy in Azure Container Apps.
      source: https://learn.microsoft.com/en-us/azure/container-apps/health-probes
      verified: true
    - claim: Azure Container Apps supports automatic scaling with HTTP and event-driven scale rules.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
    - claim: Azure Container Apps troubleshooting guidance recommends checking logs and deployment events during investigations.
      source: https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting
      verified: true
---
# Troubleshooting Decision Tree

Use this page when you need to triage quickly from symptom to likely failure category and then open the right playbook.

The tree is intentionally symptom-first and optimized for the first 10–15 minutes of incident response.

## Main triage decision tree

<!-- diagram-id: main-triage-decision-tree -->
```mermaid
flowchart TD
    START[User-visible incident]
    REVISION{Latest active revision healthy?}
    SYSTEM{System logs identify pull,<br/>startup, or probe failure?}
    IMAGE[Image Pull Failure]
    PROBE[Probe Failure and Slow Start]
    PROVISION[Revision Provisioning Failure]
    HTTP{HTTP ingress record exists<br/>for the failed request?}
    STATUS{Response status and details?}
    APP[Application or console-log investigation]
    INGRESS[Ingress Not Reachable]
    REPLICAS{Healthy replicas available<br/>during the failure window?}
    RUNTIME[CrashLoop OOM and Resource Pressure]
    SCALE[HTTP Scaling Not Triggering]
    DEPENDENCY{Failure isolated to a<br/>downstream dependency?}
    NETWORK[DNS or Service Connectivity playbook]
    IDENTITY[Identity or Secret playbook]
    METHOD[Methodology: build competing hypotheses]

    START --> REVISION
    REVISION -->|No| SYSTEM
    REVISION -->|Yes| HTTP
    SYSTEM -->|Image pull evidence| IMAGE
    SYSTEM -->|Probe evidence| PROBE
    SYSTEM -->|Neither| PROVISION
    HTTP -->|Yes| STATUS
    HTTP -->|No| INGRESS
    STATUS -->|500 or app exception| APP
    STATUS -->|502 or 503| REPLICAS
    REPLICAS -->|No, restarts or exits| RUNTIME
    REPLICAS -->|No, demand exceeds supply| SCALE
    REPLICAS -->|Yes| DEPENDENCY
    DEPENDENCY -->|DNS, route, or refusal| NETWORK
    DEPENDENCY -->|401, 403, or secret error| IDENTITY
    DEPENDENCY -->|No| METHOD
```

The main tree asks for a distinguishing signal at every branch: revision health, system-log evidence, an HTTP ingress record, replica availability, or a dependency-specific error.

## 5xx branch deep-dive tree

<!-- diagram-id: 5xx-branch-deep-dive-tree -->
```mermaid
flowchart TD
    ERROR[Observed 5xx]
    RECORD{Matching ContainerAppHTTPLogs<br/>record available?}
    DETAILS{StatusCode and<br/>ResponseCodeDetails}
    NORECORD[Check front door, DNS,<br/>and ingress reachability]
    UPSTREAM{Upstream attempt or<br/>replica recorded?}
    APP[Correlate console logs<br/>for the same revision and replica]
    REPLICAS{Healthy replica count<br/>dropped in the same window?}
    PROBES{Probe or container-exit<br/>event in system logs?}
    SCALE{Demand rose while<br/>replica count stayed low?}
    STARTUP[Probe Failure or Container Start playbook]
    AUTOSCALE[HTTP Scaling Not Triggering]
    ROUTING[Ingress or Revision Routing playbook]
    METHOD[Collect more evidence;<br/>status code alone is insufficient]

    ERROR --> RECORD
    RECORD -->|Yes| DETAILS
    RECORD -->|No| NORECORD
    DETAILS -->|Application 500| APP
    DETAILS -->|Upstream 502 or 503| UPSTREAM
    UPSTREAM -->|No upstream selected| ROUTING
    UPSTREAM -->|Replica identified| REPLICAS
    REPLICAS -->|Yes| PROBES
    REPLICAS -->|No| METHOD
    PROBES -->|Yes| STARTUP
    PROBES -->|No| SCALE
    SCALE -->|Yes| AUTOSCALE
    SCALE -->|No| METHOD
```

This deep dive avoids assigning a root cause from 500, 502, or 503 alone; it uses the HTTP record, routed upstream, replica availability, and time-correlated system or console evidence.

## Playbook leaves (direct links)

### Startup and Provisioning

- [Image Pull Failure](playbooks/startup-and-provisioning/image-pull-failure.md)
- [Revision Provisioning Failure](playbooks/startup-and-provisioning/revision-provisioning-failure.md)
- [Container Start Failure](playbooks/startup-and-provisioning/container-start-failure.md)
- [Probe Failure and Slow Start](playbooks/startup-and-provisioning/probe-failure-and-slow-start.md)

### Ingress and Networking

- [Ingress Not Reachable](playbooks/ingress-and-networking/ingress-not-reachable.md)
- [Internal DNS and Private Endpoint Failure](playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md)
- [Service-to-Service Connectivity Failure](playbooks/ingress-and-networking/service-to-service-connectivity-failure.md)
- [AppGW to Internal Azure Container Apps NSG Destination](playbooks/ingress-and-networking/appgw-to-internal-aca-nsg-destination.md)

### Scaling and Runtime

- [HTTP Scaling Not Triggering](playbooks/scaling-and-runtime/http-scaling-not-triggering.md)
- [Event Scaler Mismatch](playbooks/scaling-and-runtime/event-scaler-mismatch.md)
- [CrashLoop OOM and Resource Pressure](playbooks/scaling-and-runtime/crashloop-oom-and-resource-pressure.md)

### Identity and Configuration

- [Managed Identity Auth Failure](playbooks/identity-and-configuration/managed-identity-auth-failure.md)
- [Secret and Key Vault Reference Failure](playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)

### Platform Features

- [Dapr Sidecar or Component Failure](playbooks/platform-features/dapr-sidecar-or-component-failure.md)
- [Container App Job Execution Failure](playbooks/platform-features/container-app-job-execution-failure.md)
- [Bad Revision Rollout and Rollback](playbooks/platform-features/bad-revision-rollout-and-rollback.md)

## Quick reference matrix

| Symptom Pattern | Most Likely Cause Category | Playbook Link |
|---|---|---|
| 5xx spikes only during traffic bursts | Replica count insufficient, scaling delay | [HTTP Scaling Not Triggering](playbooks/scaling-and-runtime/http-scaling-not-triggering.md) |
| 503 after revision update | Startup/probe sequence failure | [Revision Provisioning Failure](playbooks/startup-and-provisioning/revision-provisioning-failure.md) |
| 502 with probe failures | Probe configuration or app health issue | [Probe Failure and Slow Start](playbooks/startup-and-provisioning/probe-failure-and-slow-start.md) |
| Container runs but no responses | Port binding mismatch or app not listening | [Container Start Failure](playbooks/startup-and-provisioning/container-start-failure.md) |
| Image pull errors in system logs | ACR authentication or image tag issue | [Image Pull Failure](playbooks/startup-and-provisioning/image-pull-failure.md) |
| Ingress unreachable externally | Ingress configuration or external access disabled | [Ingress Not Reachable](playbooks/ingress-and-networking/ingress-not-reachable.md) |
| Application Gateway backend Unhealthy against an internal Container Apps environment | Workload profile subnet NSG has Destination pinned to environment `staticIp` instead of the container app subnet CIDR, or is missing edge proxy ports (31443/31080), or has a custom Deny rule that shadows the default `AllowAzureLoadBalancerInBound` rule at priority 65001 | [AppGW to Internal Container Apps NSG Destination](playbooks/ingress-and-networking/appgw-to-internal-aca-nsg-destination.md) |
| High latency with restarts | Memory growth and OOM kills | [CrashLoop OOM and Resource Pressure](playbooks/scaling-and-runtime/crashloop-oom-and-resource-pressure.md) |
| Event-driven scaler not firing | KEDA configuration mismatch | [Event Scaler Mismatch](playbooks/scaling-and-runtime/event-scaler-mismatch.md) |
| Private endpoint dependency unreachable | DNS/private zone configuration | [Internal DNS and Private Endpoint Failure](playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md) |
| Managed identity token errors | Identity configuration or RBAC issue | [Managed Identity Auth Failure](playbooks/identity-and-configuration/managed-identity-auth-failure.md) |
| Secret resolution failures | Key Vault reference or secret configuration | [Secret and Key Vault Reference Failure](playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md) |
| Dapr sidecar not starting | Dapr component or configuration issue | [Dapr Sidecar or Component Failure](playbooks/platform-features/dapr-sidecar-or-component-failure.md) |

## Triage prompts to ask in order

1. Is it a 5xx issue? If yes, is it intermittent or constant?
2. Was there a recent revision update or deployment in the incident window?
3. Is startup failing (image pull, container crash, probe timeout)?
4. Is outbound dependency failing (DNS, private endpoint, service-to-service)?
5. Is it a scaling issue (HTTP scaling, event-driven scaling, resource pressure)?

## Minimal evidence before choosing a branch

- 15-minute system log timeline (`ContainerAppSystemLogs_CL`)
- Console logs for startup and errors (`ContainerAppConsoleLogs_CL`)
- Revision list to correlate timing (`az containerapp revision list`)

```kusto
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(2h)
| where ContainerAppName_s == "<app-name>"
| summarize count() by Reason_s
| order by count_ desc
```

```kusto
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(24h)
| where ContainerAppName_s == "<app-name>"
| where Reason_s has_any ("ProbeFailed", "ContainerStarted", "ContainerTerminated", "ImagePullBackOff")
| project TimeGenerated, Reason_s, Log_s
| order by TimeGenerated desc
```

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(6h)
| where ContainerAppName_s == "<app-name>"
| where Log_s has_any ("Exception", "Error", "timeout", "failed", "could not")
| project TimeGenerated, Log_s
| order by TimeGenerated desc
```

## CLI triage bundle

```bash
az containerapp revision list --name $APP_NAME --resource-group $RG --output table
az containerapp logs show --name $APP_NAME --resource-group $RG --type system --tail 50
az containerapp logs show --name $APP_NAME --resource-group $RG --type console --tail 50
az containerapp show --name $APP_NAME --resource-group $RG --query "properties.latestRevisionName"
az monitor activity-log list --resource-group $RG --offset 24h
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp revision list` | Lists revision state so the decision tree can distinguish rollout failures from runtime failures. |
| `--name` | Selects the container app being triaged across revision, log, and configuration checks. |
| `--output` | Formats the revision inventory as a table for rapid comparison. |
| `--resource-group` | Scopes the triage bundle to the resource group containing the app. |
| `az containerapp logs show` | Retrieves both platform system events and application console output for branch selection. |
| `--tail` | Limits each log stream to the 50 most recent lines for first-pass triage. |
| `--type` | Selects `system` events for platform branches or `console` output for application branches. |
| `az containerapp show` | Reads the current app resource to identify its latest revision. |
| `--query` | Extracts only `properties.latestRevisionName` for timestamp correlation. |
| `az monitor activity-log list` | Lists recent management-plane changes that could explain the symptom onset. |
| `--offset` | Restricts Activity Log results to the preceding 24 hours. |


!!! warning "Avoid branch bias"
    Do not choose a branch only because it matches a familiar past issue.
    If the first branch is disproven by timestamps, return to the top and re-classify.
    Decision trees accelerate triage, but evidence still decides root cause.

## Decision Tree Limits

- This tree is optimized for Azure Container Apps consumption workloads.
- Multi-cause incidents can map to more than one branch.
- If no branch matches cleanly, use [Troubleshooting Method](methodology/index.md) and build explicit competing hypotheses.

## Branch-specific first checks

### If you choose the startup branch

- Confirm expected port (8000) and startup command alignment.
- Check whether probe path depends on unavailable dependencies.
- Validate image tag and ACR authentication.

### If you choose the networking branch

- Verify whether only one dependency host fails.
- Compare failure windows against outbound-heavy endpoints.
- Test DNS resolution from within the container using exec.

### If you choose the scaling branch

- Compare replica count with request volume.
- Check KEDA scaling events in system logs.
- Identify whether high latency leads 5xx or follows it.

## Practical triage examples

1. **Intermittent 502 + probe failures + traffic bursts**
    - Decision tree branch: 5xx → intermittent → scaling candidate.
    - Start with [HTTP Scaling Not Triggering](playbooks/scaling-and-runtime/http-scaling-not-triggering.md).

2. **Revision created + immediate 503 + image pull errors**
    - Decision tree branch: restart/deployment → startup failing.
    - Start with [Image Pull Failure](playbooks/startup-and-provisioning/image-pull-failure.md).

3. **Container starts but exits repeatedly + OOM in logs**
    - Decision tree branch: runtime → resource pressure.
    - Start with [CrashLoop OOM and Resource Pressure](playbooks/scaling-and-runtime/crashloop-oom-and-resource-pressure.md).

## See Also

- [Troubleshooting Method](methodology/index.md)
- [Detector Map](methodology/detector-map.md)
- [Architecture Overview](architecture-overview.md)
- [Evidence Map](evidence-map.md)
- [First 10 Minutes Index](first-10-minutes/index.md)

## Sources

- [Azure Container Apps overview](https://learn.microsoft.com/en-us/azure/container-apps/overview)
- [Monitor Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/observability)
- [Troubleshoot Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting)
- [Health probes in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/health-probes)
- [Scale rules in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Monitor logs with Log Analytics](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring)
- [ContainerAppHTTPLogs table](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/containerapphttplogs)
