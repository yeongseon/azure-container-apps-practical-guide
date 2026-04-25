---
content_sources:
  diagrams:
    - id: multi-region-front-door-topology
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/reliability/reliability-azure-container-apps
        - https://learn.microsoft.com/azure/frontdoor/front-door-overview
content_validation:
  status: verified
  last_reviewed: "2026-04-25"
  reviewer: agent
  core_claims:
    - claim: "Reliability guidance for Azure Container Apps should be used when planning zonal or regional resilience."
      source: "https://learn.microsoft.com/azure/reliability/reliability-azure-container-apps"
      verified: true
    - claim: "Azure Front Door provides a global entry point that can be used in front of regional origins."
      source: "https://learn.microsoft.com/azure/frontdoor/front-door-overview"
      verified: true
    - claim: "Container Apps is a single-region service, so multi-region resiliency requires separate regional deployments plus an external load-balancing or failover service."
      source: "https://learn.microsoft.com/azure/reliability/reliability-container-apps"
      verified: true
---

# Disaster Recovery

Azure Container Apps disaster recovery is an architecture decision rather than a single platform toggle: you must decide whether zonal resilience, multi-region deployment, or both are required for the workload.

## Prerequisites

- A documented RTO and RPO for the workload
- Infrastructure as Code for recreating environments in multiple regions
- Replication plans for stateful dependencies such as databases, secrets, and images

```bash
export PRIMARY_LOCATION="eastus"
export SECONDARY_LOCATION="centralus"
export FRONT_DOOR_NAME="afd-aca-prod"
```

## When to Use

- When a single-region outage exceeds workload tolerance
- When you need a documented active-active or active-passive pattern
- When you need a clear distinction between zone redundancy and region failover

## Procedure

1. Decide whether the failure domain to address is **zone**, **region**, or both.
2. Keep the application stateless where possible.
3. Replicate backend dependencies before assuming traffic failover is safe.
4. Put a global routing layer in front of regional environments if region failover is required.

Common production pattern:

- one Container Apps environment per region
- one app deployment per region
- Azure Front Door or Traffic Manager in front
- replicated backend state such as databases, Key Vault strategy, and ACR replication

Microsoft Learn explicitly documents that "Container Apps is a single-region service. If the region becomes unavailable, your environment and apps are also unavailable." For multi-region resiliency, Microsoft Learn directs you to deploy environments across multiple regions and "configure load balancing and failover policies by using a service like Azure Front Door or Azure Traffic Manager."

<!-- diagram-id: multi-region-front-door-topology -->
```mermaid
flowchart TD
    A[Client] --> B[Azure Front Door]
    B --> C[Primary region ACA environment]
    B --> D[Secondary region ACA environment]
    C --> E[Replicated backend services]
    D --> E
```

## Verification

- Confirm regional deployments are functionally equivalent.
- Confirm the global routing layer can stop sending traffic to an unhealthy region.
- Confirm backend state replication meets the workload RPO.

## Rollback / Troubleshooting

- If failover is manual, document exact operator actions and DNS impact.
- If a failed region remains in rotation, inspect global health probe and origin status.
- If backend state diverges, delay failback until data is reconciled.

## See Also

- [Multi-Region Deployment](multi-region-deployment.md)
- [Zone Redundancy](zone-redundancy.md)
- [Recovery and Incident Readiness](../recovery/index.md)

## Sources

- [Reliability in Azure Container Apps](https://learn.microsoft.com/azure/reliability/reliability-azure-container-apps)
- [Reliability in Azure Container Apps](https://learn.microsoft.com/azure/reliability/reliability-container-apps)
- [Azure Front Door overview](https://learn.microsoft.com/azure/frontdoor/front-door-overview)
- [Azure Traffic Manager overview](https://learn.microsoft.com/azure/traffic-manager/traffic-manager-overview)
