---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/how-to-zone-redundancy
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/planned-maintenance
  diagrams:
    - id: best-effort-decision-flow
      type: flowchart
      source: self-generated
      justification: "No single MS Learn article presents a four-layer mitigation decision flow for ACA zone redundancy. Synthesized from the reliability, zone-redundancy, planned-maintenance, and Front Door articles."
      based_on:
        - https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps
        - https://learn.microsoft.com/en-us/azure/container-apps/how-to-zone-redundancy
        - https://learn.microsoft.com/en-us/azure/container-apps/planned-maintenance
        - https://learn.microsoft.com/en-us/azure/frontdoor/front-door-overview
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: agent
  core_claims:
    - claim: In a zone-redundant environment, Container Apps automatically schedules app replicas across availability zones; setting at least two minimum replicas helps ensure distribution across multiple zones.
      source: https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps
      verified: true
    - claim: Setting resource requests and limits helps the Container Apps scheduler make optimal placement decisions across zones, and underspecified resource requirements can lead to uneven distribution.
      source: https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps
      verified: true
    - claim: Container Apps applies noncritical platform updates during configured maintenance windows, while critical or urgent updates can occur outside those windows.
      source: https://learn.microsoft.com/en-us/azure/container-apps/planned-maintenance
      verified: true
    - claim: For resilience to a regional outage, Microsoft Learn describes deploying Container Apps environments in multiple regions with global load balancing or failover.
      source: https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps
      verified: true
---
# Zone Redundancy Incident Response

Use this playbook when a zone-redundant environment experiences customer impact and you need to verify minimum replicas, healthy-zone capacity, application resilience, and regional recovery requirements.

## Symptom

- A zone-redundant Container Apps environment serving an app with `minReplicas >= 2` shows a brief but complete 503 outage that does not match a deployment, scale event, or known upstream incident.
- Clustered replica turnover: two or more replicas of the same app stop and are replaced inside a 60-second window.
- The Azure Portal "Availability + zones" tile shows the environment as zone-redundant, yet a single Availability Zone fault correlated with measurable customer impact.
- The environment is zone redundant, but minimum replicas, health probes, client retries, or healthy-zone capacity are insufficient for the observed failure.

<!-- diagram-id: best-effort-decision-flow -->
```mermaid
flowchart TD
    accTitle: Choose the next reliability layer after a zone-related incident
    accDescr: Verify zone redundancy and minimum replicas, then validate resource sizing, probes, client resilience, and whether the recovery objective requires a separate regional deployment.

    START[Availability loss in a<br/>zone-redundant design] --> ENABLED{Environment created<br/>with zone redundancy?}
    ENABLED -->|No| MIGRATE[Create a new zone-redundant<br/>environment and redeploy]
    ENABLED -->|Yes| MINIMUM{Minimum replicas at least two<br/>and sufficient for lost capacity?}
    MINIMUM -->|No| CAPACITY[Raise minimum replicas<br/>and plan healthy-zone capacity]
    MINIMUM -->|Yes| INPUTS{Resource sizing and<br/>health probes appropriate?}
    INPUTS -->|No| TUNE[Set resource requirements<br/>and tune probes]
    INPUTS -->|Yes| RETRIES{Clients tolerate transient<br/>timeouts and dropped requests?}
    RETRIES -->|No| RESILIENCE[Add bounded retry<br/>and idempotence]
    RETRIES -->|Yes| REGION{Recovery objective survives<br/>a region outage?}
    REGION -->|No| MULTIREGION[Deploy another region<br/>and configure global routing]
    REGION -->|Yes| MONITOR[Monitor replica loss,<br/>failure rate, and recovery]
```

*Figure: Zone redundancy reduces zone-failure risk but does not replace capacity planning, transient-fault handling, or a multi-region design for regional outages.*

## Possible Causes

| Cause | Why it matters |
|---|---|
| Insufficient minimum replicas | Microsoft Learn recommends at least two minimum replicas to help ensure distribution across multiple zones; higher minimums can be necessary for peak load or stricter recovery targets. |
| Underspecified resource requirements | Resource requests and limits help the scheduler make placement decisions; underspecified requirements can contribute to uneven distribution or placement failures under load. |
| Image pull serialization on first cold zone | Container images are pulled into each zone the first time a replica is scheduled there. If the lab/test never scales out, the second zone may never warm up. |
| Platform update timing | A configured maintenance window controls noncritical update timing, but critical or urgent updates can occur outside the window; correlate the incident with Service Health rather than assuming a replica restart pattern. |
| Single-region single-environment design | Even ideal zone-spread does not survive a regional incident; the assumption that one zone-redundant environment alone meets a multi-zone RTO is the root organizational error. |
| Client without retry / backoff | If clients abort on first 503 instead of retrying the replacement replica, every clustered churn surfaces as a customer-visible failure. |

## Diagnosis Steps

1. **Confirm the environment is actually zone-redundant** — both `zoneRedundant=true` and a workload-profile (not Consumption-only) plan.
2. **Inspect the app's resource requests and limits**. Check whether they are set and appropriately sized for the workload.
3. **Run the [Mass-Reschedule KQL pack](../../kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md)** to look for clustered churn events in your incident window.
4. **Compare baseline vs perturbation** with the same KQL (Q6) to separate platform-caused churn from your own deploys.
5. **Check Azure Resource Health and the Service Health blade** for region-wide or zone-specific advisories.

```bash
export RG="rg-myapp"
export APP_NAME="ca-myapp"
export ENV_NAME="cae-myapp"

az containerapp env show \
    --resource-group "$RG" \
    --name "$ENV_NAME" \
    --query "{zoneRedundant: properties.zoneRedundant, profiles: properties.workloadProfiles}" \
    --output json

az containerapp show \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.template.containers[].{name:name, cpu:resources.cpu, memory:resources.memory}" \
    --output table

az containerapp show \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.template.scale" \
    --output json
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp env show` | Reads the environment configuration to verify zone-redundancy enablement and workload profile assignment. |
| `az containerapp show` | Reads container resource requests and limits, plus the scale configuration including minReplicas. |
| `--name` | Targets the environment name (for env show) or app name (for show). |
| `--output` | Formats as JSON (for parsing) or table (for human review). |
| `--query` | Filters to zone-redundancy and workload-profile fields (env) or container resource fields (app). |
| `--resource-group` | Keeps the environment and app sizing comparison within the deployment whose zone posture is being assessed. |

## Resolution — Four-Layer Mitigation Matrix

> Zone redundancy is one layer in a multi-layer reliability strategy. Pick layers based on your RTO and the evidence you collected above; do not assume any single layer is sufficient.

### L1 — Tune Container Apps inputs (in-platform)

| Lever | What to do | Why it helps |
|---|---|---|
| Explicit resource requirements | Size CPU and memory for the real working set. | Microsoft Learn states that resource requests and limits help the scheduler make optimal placement decisions across zones. |
| `minReplicas >= 3` (when the budget allows) | Larger `minReplicas` dilutes the impact of any single clustered-churn event. | Q7 in the KQL pack measures the per-app churn frequency at `min={2,3,6}`. Higher minimums reduce — but do not eliminate — clustered churn. |
| Startup, readiness, and liveness probes that reflect dependency readiness | Don't pass the readiness probe before the app can actually serve traffic. | A probe that lies green during cold start lets the ingress send traffic to a replica that will 503. |
| Pre-pull the image into the second zone | Force at least one scale-out event during deploy validation. | Avoids the documented "first scheduling into a zone pulls the image" delay during a real failure. |

### L2 — Application resilience

| Lever | What to do | Why it helps |
|---|---|---|
| Client retry with capped exponential backoff | 3–4 retries, `~0.2s, 0.4s, 0.8s, 1.6s`. | Bridges the seconds-scale gap between a replica termination and its replacement coming healthy. The lab measures this explicitly via `trigger.sh --client no-retry` vs `--client retry-backoff`. |
| Circuit breakers on downstream calls | Open-state for the failing replica's downstream, half-open after backoff. | Prevents cascade when several replicas churn at once. |
| Warm caches / connection pools survive replica turnover | Externalize hot caches; let connection pools self-heal. | A 503 caused by a single cold replica should not also blow away a regional cache. |

### L3 — Multi-region (escalation when L1+L2 are insufficient)

| Lever | What to do | Why it helps |
|---|---|---|
| Active-passive multi-region with Azure Front Door | Deploy the app in a second region; let Front Door probe both and shift traffic. | Survives **regional** incidents that no single zone-redundant environment can. See the [Multi-Region Failover Playbook](./multi-region-failover.md) and [Lab](../../lab-guides/multi-region-failover.md). |
| **Escalate to AKS** when zone placement must be operator-controlled | Move the workload to Azure Kubernetes Service with `topologySpreadConstraints`. | Azure Container Apps does not surface per-replica zone placement to operators. If your reliability requirements demand explicit zone placement guarantees, you have outgrown what Container Apps' best-effort scheduler can offer. |

### L4 — Observability and SLO honesty

| Lever | What to do | Why it helps |
|---|---|---|
| Alert on clustered churn | Use the [Mass-Reschedule KQL pack Q3](../../kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md#q3-clustered-churn-detection) in an Azure Monitor alert rule. | Detects the failure mode before customers do, even when zone redundancy was working. |
| Baseline your real MTTR | Run the KQL pack's Q4 over a 7-day window; treat its 95th percentile as your true platform MTTR. | Lets you set SLOs you can actually meet, instead of inheriting the "redundant therefore fast" assumption. |
| Document the assumption in your runbook | Replace any "zone-redundant means zero 5xx" wording with "zone-redundant means platform makes a best-effort spread; expect clustered churn at low frequency." | Stops the same incident from recurring as a postmortem item with no operator action. |

## Prevention

- **Set requests + limits on every container** during the first deploy. Treat unset resource shapes as a deploy-time CI check failure.
- **Pick `minReplicas` from your RTO**, not from cost intuition. Higher minimums reduce — not eliminate — clustered-churn impact.
- **Treat zone redundancy as one layer**, not a complete regional recovery design. Document minimum capacity, transient-fault handling, and multi-region requirements together.
- **Schedule quarterly fault injection** using `trigger.sh --perturb restart` (or the equivalent runbook) so the team sees clustered churn in a controlled window and can verify the L2 retry path actually works.
- **Subscribe to Azure Service Health alerts** for the region, and configure a maintenance window when you need noncritical platform updates scheduled within a preferred time range.

## See Also

- [Lab: Zone redundancy is best-effort](../../lab-guides/zone-redundancy-best-effort.md)
- [KQL: Mass-Reschedule pack](../../kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md)
- [Multi-Region Failover Playbook](./multi-region-failover.md)
- [Multi-Region Failover Lab](../../lab-guides/multi-region-failover.md)
- [Replica Load Imbalance Playbook](../scaling-and-runtime/replica-load-imbalance.md)
- [Replica Load Imbalance Lab](../../lab-guides/replica-load-imbalance.md)

## Sources

- [Reliability in Azure Container Apps](https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps)
- [Set up zone redundancy in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/how-to-zone-redundancy)
- [Planned maintenance for Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/planned-maintenance)
- [Scale an app in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Workload profiles in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview)
- [What is Azure Front Door?](https://learn.microsoft.com/en-us/azure/frontdoor/front-door-overview)
