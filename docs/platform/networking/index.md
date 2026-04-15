---
content_sources:
  diagrams:
    - id: high-level-network-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/networking
        - https://learn.microsoft.com/azure/container-apps/ingress-overview
    - id: traffic-flow-external-vs-internal-ingress
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/networking
        - https://learn.microsoft.com/azure/container-apps/ingress-overview
    - id: vnet-integration-architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/networking
        - https://learn.microsoft.com/azure/container-apps/ingress-overview
    - id: ingress-routes-traffic-to-active-revisions
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/networking
        - https://learn.microsoft.com/azure/container-apps/ingress-overview
---

# Networking in Azure Container Apps

Networking in Azure Container Apps combines managed ingress with optional private networking controls. Understanding ingress mode, service discovery, and environment boundaries is key to secure and reliable architectures.

## High-Level Network Flow

<!-- diagram-id: high-level-network-flow -->
```mermaid
graph LR
    C[Client] --> E[Envoy Ingress]
    E --> A[Container App: Public API]
    A --> B[Container App: Internal Worker]
    A --> D[External Dependency]

    subgraph ENV[Container Apps Environment]
      E
      A
      B
    end
```

Envoy acts as the managed ingress layer, handling routing into app revisions and enforcing transport behavior.

!!! warning "Ingress mode is a security boundary"
    Accidentally enabling external ingress for internal-only workloads exposes endpoints to the public internet.
    Validate ingress mode in deployment reviews and policy checks.

## Ingress Modes

| Mode | Reachability | Typical Use |
|---|---|---|
| External ingress | Public internet entry point | Public APIs and web backends |
| Internal ingress | Environment-internal access | Private microservice endpoints |
| No ingress | Not directly addressable by HTTP clients | Queue-driven/background workers |

### Traffic Flow: External vs Internal Ingress

<!-- diagram-id: traffic-flow-external-vs-internal-ingress -->
```mermaid
flowchart TD
    subgraph Public [Public Internet]
        U[Public User]
    end

    subgraph VNet [Virtual Network]
        subgraph CASubnet [Container Apps Subnet]
            subgraph Env [Environment]
                EXT[App: External Ingress]
                INT[App: Internal Ingress]
                ING[Managed Ingress: Envoy]
            end
        end

        subgraph PeeredVNet [Peered VNet / VPN / ER]
            C[Internal Client]
        end
    end

    U -- Public IP / DNS --> ING
    C -- Private IP / VNet DNS --> ING
    ING -- Public Hostname --> EXT
    ING -- Internal Hostname --> INT
```

## VNet Integration and Isolation

Container Apps environments can integrate with virtual networks to control east-west and north-south traffic patterns.

### VNet Integration Architecture

<!-- diagram-id: vnet-integration-architecture -->
```mermaid
flowchart LR
    subgraph VNet ["Virtual Network (10.0.0.0/16)"]
        subgraph Subnet ["CAE Subnet (10.0.0.0/23)"]
            APP[Container App]
        end

        subgraph PE_Subnet ["PE Subnet (10.0.2.0/24)"]
            PE[Private Endpoint]
        end
    end

    subgraph Backbone [Microsoft Backbone]
        DB[Azure SQL / Storage]
    end

    APP -- 1. DNS Query --> VNET_DNS[VNet DNS Resolver]
    VNET_DNS -- 2. Returns Private IP --> APP
    APP -- 3. Connection --> PE
    PE -- 4. Private Link --> DB
```

Use VNet integration when you need:

- Private access to internal services.
- Controlled egress paths to dependencies.
- Alignment with enterprise network governance.

## Service Discovery and East-West Calls

Apps in the same environment can use internal naming/service invocation patterns for service-to-service communication.

With optional Dapr integration, service invocation becomes more uniform across services while keeping networking concerns centralized.

!!! tip "Use internal ingress by default for backend services"
    Reserve external ingress for entry-point APIs. This reduces attack surface and simplifies network governance.

## Revisions and Traffic Routing

Ingress routes traffic to active revisions based on configured weights.

<!-- diagram-id: ingress-routes-traffic-to-active-revisions -->
```mermaid
graph TD
    I[Envoy Ingress] --> R1[Revision v1 - 70%]
    I --> R2[Revision v2 - 30%]
```

This model supports canary testing without introducing an external traffic manager for basic progressive delivery.

## TLS and Managed Certificates

For custom domains, managed certificates simplify HTTPS lifecycle operations:

- Certificate issuance and renewal are platform-managed.
- Teams avoid manual certificate rotation overhead.
- HTTPS posture remains consistent as apps evolve.

## Practical Example: Public Edge + Private Backend

| Component | Network Posture |
|---|---|
| API app | External ingress with TLS |
| Orders/worker app | Internal ingress only |
| Data services | Private connectivity through VNet design |

This pattern reduces attack surface while keeping the public API straightforward.

## Advanced Topics

- Combining internal ingress with private endpoints for end-to-end private data paths.
- Zero-trust service segmentation across multiple environments.
- Egress governance and outbound allow-list strategies.

## See Also
- [How Container Apps Works](../../start-here/overview.md)
- [Environments and Apps](../environments/index.md)
- [Scaling with KEDA](../scaling/index.md)
- [Container Apps vs Others](../../start-here/when-to-use-container-apps.md)
- [VNet Integration Recipe](vnet-integration.md)
- [Private Endpoint Recipe](private-endpoints.md)

## Sources
- [Networking in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/networking)
- [Ingress in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/ingress-overview)
