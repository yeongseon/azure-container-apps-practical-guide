---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/overview
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
        - https://learn.microsoft.com/en-us/azure/container-apps/containers
content_validation:
  status: verified
  last_reviewed: 2026-11-08
  reviewer: agent
  core_claims:
    - claim: Azure Container Apps uses revisions to manage different versions of a container app.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: A managed identity from Microsoft Entra ID allows a container app to access other Microsoft Entra protected resources.
      source: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
      verified: true
    - claim: Azure Container Apps supports internal ingress and service discovery for secure internal-only endpoints with built-in DNS-based service discovery.
      source: https://learn.microsoft.com/en-us/azure/container-apps/overview
      verified: true
    - claim: Azure Container Apps can run containers from public or private registries, including Azure Container Registry.
      source: https://learn.microsoft.com/en-us/azure/container-apps/overview
      verified: true
---
# Resource Relationships

This overview maps how Azure Container Apps runtime components, identities, and dependent Azure services interact in a typical production deployment.

## Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Container Apps resource and dependency relationships
    accDescr: A client request enters managed ingress and reaches an active revision replica. The running app exchanges data with external Azure services after its managed identity receives authorization, while Azure Container Registry supplies image layers during revision startup.

    CLIENT[Request caller]
    ACR[Azure Container Registry<br/>startup dependency]
    IDENTITY[App managed identity<br/>principal used for authorization]
    TOKEN_ENDPOINT[Container Apps local identity endpoint]
    ENTRA[Microsoft Entra ID<br/>token issuer]
    AUTHORIZED_RUNTIME[Authorized runtime access<br/>RBAC or data-plane permission]
    REGISTRY_ACCESS[Authorized image pull<br/>registry role or repository permission]
    IMAGE_PULL[Container Apps image pull<br/>during replica provisioning]
    RUNTIME_DEPENDENCY[Runtime Azure dependency<br/>data service or Key Vault]

    subgraph ENV[Managed Container Apps environment]
        INGRESS[Managed ingress<br/>TLS and request routing]
        APP[Container app<br/>logical resource]
        REV[Active revision<br/>immutable version]
        REPLICA[Revision replica<br/>running containers]
        DAPR[Dapr sidecar<br/>optional]
    end

    APP -.->|Defines| REV
    REV -.->|Creates| REPLICA
    REPLICA -.->|May include| DAPR

    CLIENT ==>|HTTPS request| INGRESS
    INGRESS ==>|Routed request| REV
    REV ==>|Serves request| REPLICA

    REPLICA -->|Requests token| TOKEN_ENDPOINT
    TOKEN_ENDPOINT -->|Requests token using identity| ENTRA
    ENTRA -->|Returns access token| TOKEN_ENDPOINT
    TOKEN_ENDPOINT -->|Returns access token| REPLICA
    IDENTITY -.->|Identifies principal| TOKEN_ENDPOINT
    IDENTITY -.-> AUTHORIZED_RUNTIME
    IDENTITY -.-> REGISTRY_ACCESS
    AUTHORIZED_RUNTIME -.-> RUNTIME_DEPENDENCY
    REGISTRY_ACCESS -.-> ACR
    REPLICA ==>|Runtime request| RUNTIME_DEPENDENCY
    RUNTIME_DEPENDENCY ==>|Runtime response| REPLICA
    IMAGE_PULL ==>|Image manifest and layer request| ACR
    ACR ==>|Image response and layers| IMAGE_PULL
    REV -.->|Provisioning requires| IMAGE_PULL
```

Thick arrows show request or data transport, including the bidirectional runtime exchange and the platform image pull during replica provisioning. Thin arrows show token requests and responses through the local identity endpoint and Microsoft Entra ID; dotted arrows show resource, principal, provisioning, or authorization relationships rather than traffic.

!!! warning "Shared dependencies become shared failure domains"
    Multiple apps using the same database, cache, or Key Vault can fail together during dependency incidents.
    Design for graceful degradation and fallback behavior per service.

!!! tip "Separate control and data concerns"
    Keep deployment-time concerns (image pull, identity assignment, RBAC) in infrastructure automation,
    and runtime concerns (timeouts, retries, circuit breaking) in application configuration.

## Portal view: resource group as the visible dependency boundary

This screenshot is used here as a visual companion to the [Architecture](#architecture) diagram and the [Dependency Classification Matrix](#dependency-classification-matrix), focusing on the resource types visibly listed in the resource group.

![Resource group overview blade showing four resources: "acrbasicsd38538" (Container registry), "ca-sample-d38538" (Container App), "cae-basics-d38538" (Container Apps Environment), and "law-basics-d38538" (Log Analytics workspace); Essentials panel showing "Location" Korea Central and "Deployments" No deployments](../../assets/platform/architecture/02-resource-group-overview.png)

[Observed] The Resources list shows four rows: "acrbasicsd38538" with Type "Container registry", "ca-sample-d38538" with Type "Container App", "cae-basics-d38538" with Type "Container Apps Environment", and "law-basics-d38538" with Type "Log Analytics workspace". The Essentials panel shows "Location : Korea Central" and "Deployments : No deployments".

[Inferred] The separate `Container registry`, `Container App`, and `Container Apps Environment` rows are consistent with this page's [Architecture](#architecture) diagram treating image source, application runtime, and environment boundary as different parts of the deployment. The `Container registry` row appears to map directly to the `Azure Container Registry` row in the [Dependency Classification Matrix](#dependency-classification-matrix).

[Not Proven] This blade does not show which Container App uses which Container Registry. It does not show the managed identity dashed-arrow relationships shown in [Architecture](#architecture). It does not show the Microsoft Entra ID node from the same diagram. It does not show whether `Key Vault`, `Azure SQL/Cosmos DB`, or `Redis/Storage` dependencies from the [Dependency Classification Matrix](#dependency-classification-matrix) exist in this deployment. It does not show the Dapr sidecar relationship from [Architecture](#architecture).

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
- [Azure Container Apps architecture (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/overview)
- [Managed identities in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
- [Containers in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/containers)
