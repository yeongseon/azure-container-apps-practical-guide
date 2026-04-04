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

    I --> APP

    APP --> COSMOS[Azure Cosmos DB]
    APP --> SQL[Azure SQL Database]
    APP --> REDIS[Azure Cache for Redis]
    APP --> KV[Azure Key Vault]
    APP --> STG[Azure Storage]
    APP --> ACR[Azure Container Registry]

    APP -.-> MI[Managed Identity]
    MI -.-> ENTRA[Microsoft Entra ID]

    DAPR -.-> APP2[Container App (peer service)]

    MI -.-> COSMOS
    MI -.-> SQL
    MI -.-> REDIS
    MI -.-> KV
    MI -.-> STG
    MI -.-> ACR
```

Solid arrows show runtime data flow. Dashed arrows show identity and authentication.

## Advanced Topics

- Add private networking controls with VNet integration and private endpoints for data services.
- Use workload profiles and KEDA scale rules to match resource behavior to traffic patterns.
- Standardize service-to-service communication and trace context propagation with Dapr.

## See Also
- [How Container Apps Works](../../start-here/overview.md)
- [Networking](../networking/index.md)

## Sources
- [Azure Container Apps architecture (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/architecture)
- [Managed identities in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/managed-identity)
