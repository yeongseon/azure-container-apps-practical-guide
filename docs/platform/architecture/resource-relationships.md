---
hide:
  - toc
---

# Resource Relationships

This overview maps how Azure Container Apps runtime components, identities, and dependent Azure services interact in a typical production deployment.

## Architecture

```mermaid
flowchart LR
    C[Client] --> I[Container Apps Ingress]

    subgraph ENV[Container Apps Environment]
        APP[Container App]
        REV[Active Revision]
        APP --> REV
        DAPR["Dapr sidecar (optional)"]
        APP -.-> DAPR
    end

    I --> REV

    APP --> COSMOS[Azure Cosmos DB]
    APP --> SQL[Azure SQL Database]
    APP --> REDIS[Azure Cache for Redis]
    APP --> KV[Azure Key Vault]
    APP --> STG[Azure Storage]
    APP -.->|image pull at startup| ACR[Azure Container Registry]

    APP -.-> MI[Managed Identity]
    MI -.-> ENTRA[Microsoft Entra ID]

    DAPR -.-> APP2["Container App (peer service)"]

    MI -.-> COSMOS
    MI -.-> SQL
    MI -.-> REDIS
    MI -.-> KV
    MI -.-> STG
    MI -.-> ACR
```

Solid arrows show runtime data flow. Dashed arrows show identity, authentication, and deployment-time dependencies.

!!! warning "Shared dependencies become shared failure domains"
    Multiple apps using the same database, cache, or Key Vault can fail together during dependency incidents.
    Design for graceful degradation and fallback behavior per service.

!!! tip "Separate control and data concerns"
    Keep deployment-time concerns (image pull, identity assignment, RBAC) in infrastructure automation,
    and runtime concerns (timeouts, retries, circuit breaking) in application configuration.

## Dependency Classification Matrix

| Dependency | Access Pattern | Primary Risk | Mitigation Baseline |
|---|---|---|---|
| Azure Container Registry | Startup/image pull | Revision stuck in provisioning | Private access path, pull permissions, image tag discipline |
| Key Vault | Runtime secret retrieval | Auth/RBAC or network failures | Managed identity + retry/backoff + cached defaults where safe |
| Azure SQL/Cosmos DB | Runtime data plane | Latency spikes or throttling | Connection pooling, bounded retries, schema compatibility |
| Redis/Storage | Runtime cache/object plane | Transient unavailability | Timeout tuning, fallback reads/writes, idempotent operations |

## Advanced Topics

- Add private networking controls with VNet integration and private endpoints for data services.
- Use workload profiles and KEDA scale rules to match resource behavior to traffic patterns.
- Standardize service-to-service communication and trace context propagation with Dapr.

!!! note "Model blast radius explicitly"
    During architecture review, document which services share environment, identity, network path,
    and backing stores so incident responders can quickly estimate impact scope.

## See Also
- [How Container Apps Works](../../start-here/overview.md)
- [Networking](../networking/index.md)

## Sources
- [Azure Container Apps architecture (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/architecture)
- [Managed identities in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/managed-identity)
