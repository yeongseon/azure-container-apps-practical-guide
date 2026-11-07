---
description: Azure Container Apps networking — managed ingress, environment accessibility, VNet integration, private endpoints, and revision traffic routing.
content_sources:
  diagrams:
    - id: high-level-network-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
    - id: traffic-flow-external-vs-internal-ingress
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
    - id: vnet-integration-architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks
        - https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
        - https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints
    - id: ingress-routes-traffic-to-active-revisions
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
content_validation:
  status: verified
  last_reviewed: 2026-11-07
  reviewer: agent
  core_claims:
    - claim: External app ingress publishes an app at the environment inbound boundary, while public internet reachability also depends on the environment virtual IP and public network access configuration.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      verified: true
    - claim: A custom-VNet Container Apps environment requires a dedicated subnet that is unavailable to other services.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: A Storage private endpoint is a network interface with a private IP from the virtual network, while the Storage resource remains a service reached over Private Link.
      source: https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints
      verified: true
    - claim: The recommended private DNS zone for a Blob Storage private endpoint is `privatelink.blob.core.windows.net`.
      source: https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
      verified: true
    - claim: Container Apps can split incoming traffic between active revisions by configured percentage.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      verified: true
---
# Networking in Azure Container Apps

Networking in Azure Container Apps combines managed ingress with optional private networking controls. Understanding ingress mode, service discovery, and environment boundaries is key to secure and reliable architectures.

Start with [Ingress in Azure Container Apps](ingress.md) when you need the canonical explanation of external vs internal exposure, transport modes, TCP ingress, headers, and ingress edge features. Use this page for the broader networking map.

## High-Level Network Flow

**Takeaway:** An accepted request crosses the managed environment entry and ingress path before it reaches an active revision replica; outbound dependency calls are a separate path from that replica.

<!-- diagram-id: high-level-network-flow -->
```mermaid
graph TD
    accTitle: High-level Azure Container Apps network flow
    accDescr: An allowed caller reaches the environment entry, then the managed ingress proxy routes the request to an active revision and a running replica. The replica can make a separate outbound call to a downstream dependency. Logical revision membership uses dotted arrows; request and dependency transport use thick arrows.

    CALLER["Allowed caller<br/>public, private, or same environment"]
    DEPENDENCY["Downstream dependency<br/>public or private endpoint path"]

    subgraph ENV["Managed Container Apps environment — logical boundary"]
        ENTRY["Allowed environment entry<br/>public or private"]
        INGRESS["Managed ingress proxy<br/>TLS and request routing"]
        APP["Container app<br/>logical grouping"]
        REV_ACTIVE["Active revision<br/>immutable app version"]
        REPLICAS["Revision replicas<br/>running instances"]
    end

    CALLER ==>|"1  Accepted inbound request"| ENTRY
    ENTRY ==>|"2  Forward to managed ingress"| INGRESS
    INGRESS ==>|"3  Route by revision traffic rule"| REV_ACTIVE
    REV_ACTIVE ==>|"4  Select replica"| REPLICAS
    REPLICAS ==>|"5  Separate outbound call"| DEPENDENCY
    APP -.->|"Logical revision membership"| REV_ACTIVE

    LEGEND["Arrow key<br/>thick = request or dependency transport<br/>dotted = logical relationship"]
```

*Figure: The networking hub reuses the shared `ENV` → `INGRESS` → `REV_ACTIVE` → `REPLICAS` vocabulary without claiming that the logical managed environment is physically contained in a customer VNet.*

The managed ingress proxy handles accepted inbound requests and revision routing. Microsoft Learn separately identifies Envoy for internal traffic routing; this overview does not overstate the public edge implementation.

### Portal view: environment Networking blade

The **Networking** blade on a Container Apps environment is where the environment-wide network posture is configured. App-level ingress (the [Ingress](ingress.md) page) sits underneath whatever this environment-level blade exposes.

![Azure Portal Networking blade for cae-basics-d38538 environment showing tabs General, Ingress settings, Request Routing, Encryption, Custom DNS Suffix, with Public Network Access set to Enable and Virtual network section reporting "This environment isn't integrated".](../../assets/platform/networking/02-environment-networking.png)

- **[Observed]** The blade shows a tab strip with **General**, **Ingress settings**, **Request Routing**, **Encryption**, and **Custom DNS Suffix**. The General tab displays **Public Network Access** with two radios — `Enable: Allows incoming traffic from the public internet.` (selected) and `Disable: Block all incoming traffic from the public internet.` — and a **Virtual network** section reporting `This environment isn't integrated`. The left navigation under **Settings** lists Dapr components, Certificates, Quota, Workload profiles, **Networking** (selected), Volume mounts, Identity, Planned Maintenance, and Locks.
- **[Inferred]** Two of the networking dimensions discussed on this page appear to map to controls on this blade. `Public Network Access` is consistent with the environment-level public entry point that the **Ingress Modes** table describes, and its `Disable` option is consistent with the description ("Block all incoming traffic from the public internet.") rendered next to that radio. The `Virtual network` row appears to reflect whether the environment is VNet-integrated as covered in **VNet Integration and Isolation**; this sample environment is not integrated, which is consistent with no subnet, peering, or DNS settings being shown.
- **[Not Proven]** Many networking features that this guide covers are not visible in this capture. App-level ingress (external/internal, transport, IP restrictions, CORS, client certificates) and the per-app revision traffic split are not shown here. Workload profile placement, private endpoint configuration, custom DNS suffix details, and request-routing rules are not visible in the General tab captured above; whether they are reached through the other tabs visible here or through separate resources is not proven by this PNG alone.

!!! warning "Ingress mode is a security boundary"
    External app ingress publishes an app at the environment inbound boundary; it becomes internet reachable only when that boundary is public and public network access is enabled. Validate both the app setting and the environment network posture.

## Ingress Modes

| Mode | Reachability | Typical Use |
|---|---|---|
| External ingress | Published at the environment inbound boundary; public or private reachability follows the environment network posture | Public APIs on public environments, or VNet-facing apps on internal environments |
| Internal ingress | Directly reachable only inside the environment by default; an environment HTTP route can explicitly target it | Private microservice endpoints |
| No ingress | Not directly addressable by HTTP clients | Queue-driven/background workers |

### Traffic Flow: External vs Internal Ingress

**Takeaway:** App ingress visibility and environment accessibility are separate controls: external app ingress publishes at the available environment entry, while internal app ingress stays directly reachable only within the environment unless an HTTP route explicitly targets it.

<!-- diagram-id: traffic-flow-external-vs-internal-ingress -->
```mermaid
flowchart TD
    accTitle: External and internal app ingress across environment boundaries
    accDescr: Public and private callers can reach only an environment entry that the environment network posture permits. The managed ingress proxy publishes an external-ingress app at that entry. A same-environment caller can directly reach an internal-ingress app. An optional environment HTTP route can also target the internal-ingress app.

    PUBLIC["Public caller"]
    PRIVATE["Private caller<br/>connected network"]
    CONFIG["Environment accessibility<br/>and public access"]

    subgraph ENV["Managed Container Apps environment — logical boundary"]
        ENTRY["Available entry<br/>public or internal"]
        INGRESS["Managed ingress proxy"]
        EXT["External-ingress app<br/>published at entry"]
        INT["Internal-ingress app<br/>environment-only by default"]
        ROUTE["Optional HTTP route<br/>explicit target"]
        SAME_ENV["Same-environment caller"]
    end

    PUBLIC ==>|"Public entry enabled"| ENTRY
    PRIVATE ==>|"Private entry reachable"| ENTRY
    CONFIG -.->|"Controls entry"| ENTRY
    ENTRY ==>|"Accepted request"| INGRESS
    INGRESS ==>|"Published app"| EXT
    INGRESS ==>|"Explicit route"| ROUTE
    ROUTE ==>|"Forward"| INT
    SAME_ENV ==>|"Direct call"| INT

    LEGEND["Arrow key<br/>thick = request path<br/>dotted = environment configuration"]
```

*Figure: External and internal describe an app's visibility relative to its environment, not a universal public-versus-private split. The optional HTTP-route branch prevents the internal-ingress path from being shown as an absolute outside-access prohibition.*

## VNet Integration and Isolation

Container Apps environments can integrate with virtual networks to control east-west and north-south traffic patterns.

### VNet Integration Architecture

**Takeaway:** A custom-VNet Container Apps environment uses a dedicated environment subnet; a downstream Blob private endpoint is a separate NIC/private IP in its own subnet, and private DNS resolution precedes—but does not prove—TCP connectivity or data authorization.

<!-- diagram-id: vnet-integration-architecture -->
```mermaid
flowchart TD
    accTitle: Container Apps custom VNet access to Blob Storage through Private Link
    accDescr: A Container Apps replica uses a dedicated environment subnet relationship. A linked private DNS zone resolves the Blob hostname to a private endpoint NIC in a separate subnet. The replica opens HTTPS through that endpoint to Storage. Storage then evaluates data authorization: allow permits a response over the established transport, while reject is a data-authorization failure rather than a connectivity failure.

    DNS_NAME["Blob endpoint FQDN"]
    PDNS["Private DNS zone<br/>privatelink.blob.core.windows.net"]

    subgraph ENV["Managed Container Apps environment — logical boundary"]
        APP["Container app"]
        REV_ACTIVE["Active revision"]
        REPLICAS["Replica"]
        APP -.-> REV_ACTIVE
        REV_ACTIVE -.-> REPLICAS
    end

    subgraph VNET["Customer-managed virtual network"]
        subgraph ENV_SUBNET["Dedicated Container Apps environment subnet"]
            ENV_LINK["ACA subnet relationship"]
        end
        subgraph PE_SUBNET["Private endpoint subnet"]
            PE["Blob private endpoint<br/>NIC with private IP"]
        end
    end

    STORAGE["Azure Storage<br/>Blob service"]
    AUTH{"Data authorization<br/>succeeds?"}
    ALLOW["ALLOW<br/>response permitted"]
    DENY["DENY<br/>data authorization failure"]

    ENV -.->|"uses dedicated subnet"| ENV_LINK
    PDNS -.->|"zone linked to VNet"| VNET
    REPLICAS -.->|"1  Resolve hostname"| DNS_NAME
    DNS_NAME -.-> PDNS
    PDNS -.->|"2  Return private endpoint IP"| REPLICAS
    REPLICAS ==>|"3  HTTPS request"| ENV_LINK
    ENV_LINK ==>|"4  Private IP path"| PE
    PE ==>|"5  Private Link request"| STORAGE
    STORAGE -->|"6  Evaluate data access"| AUTH
    AUTH -->|"Allow"| ALLOW
    AUTH -.->|"Reject"| DENY
    ALLOW -->|"Enables response"| STORAGE
    STORAGE ==>|"7  HTTPS response"| PE
    PE ==>|"8  Established flow"| REPLICAS

    LEGEND["Arrow key<br/>thick = TCP/HTTPS data transport<br/>solid = authorization result<br/>dotted = DNS, association, or logical relationship"]
```

*Figure: The downstream Storage private endpoint is not an inbound private endpoint for the Container Apps environment. The environment and Storage resource stay outside VNet containment; only their documented subnet relationship and private endpoint NIC are shown inside the customer VNet.*

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

**Takeaway:** The managed ingress proxy applies traffic weights across active revisions, and each selected revision serves the request through one of its running replicas.

<!-- diagram-id: ingress-routes-traffic-to-active-revisions -->
```mermaid
graph TD
    accTitle: Managed ingress routes traffic to active revisions
    accDescr: The managed ingress proxy sends 70 percent of incoming requests to one active revision and 30 percent to another. Each revision then selects a running replica. Revisions and replicas are logical platform groupings rather than customer-managed network resources.

    CALLER["Request caller"]
    INGRESS["Managed ingress proxy<br/>revision traffic routing"]
    REV_STABLE["Active revision v1<br/>70% traffic weight"]
    REV_CANARY["Active revision v2<br/>30% traffic weight"]
    REPLICAS_STABLE["Revision v1 replicas<br/>running instances"]
    REPLICAS_CANARY["Revision v2 replicas<br/>running instances"]

    CALLER ==>|"Incoming request"| INGRESS
    INGRESS ==>|"70% of requests"| REV_STABLE
    INGRESS ==>|"30% of requests"| REV_CANARY
    REV_STABLE ==>|"Select replica"| REPLICAS_STABLE
    REV_CANARY ==>|"Select replica"| REPLICAS_CANARY

    LEGEND["Arrow key<br/>thick = request path<br/>percentages = configured revision traffic weights"]
```

*Figure: Weighted routing extends the shared `INGRESS` → active revision → replicas path. The percentages are configuration examples, not measured request counts.*

This model supports canary testing without introducing an external traffic manager for basic progressive delivery. Traffic weights apply across active revisions rather than directly selecting individual replicas.

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
- [Ingress in Azure Container Apps](ingress.md)
- [Environments and Apps](../environments/index.md)
- [Scaling with KEDA](../scaling/index.md)
- [Container Apps vs Others](../../start-here/when-to-use-container-apps.md)
- [VNet Integration Recipe](vnet-integration.md)
- [Private Endpoint Recipe](private-endpoints.md)
- [Application Gateway Integration](application-gateway-integration.md)

## Sources
- [Networking in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Ingress in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Configure virtual networks in Azure Container Apps environments (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks)
- [Azure Private Endpoint DNS configuration (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Use private endpoints for Azure Storage (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)
