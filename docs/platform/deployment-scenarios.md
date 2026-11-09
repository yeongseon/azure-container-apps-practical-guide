---
description: Compare public managed-network, private VNet-integrated, and mixed Consumption and Dedicated Azure Container Apps deployment scenarios.
content_sources:
  diagrams:
    - id: scenario-overview
      type: flowchart
      source: self-generated
      justification: Synthesizes the three reference deployment scenarios used throughout this guide from Microsoft Learn environment, workload profiles, and networking topics.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/environment
        - https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
    - id: scenario-a-public-consumption
      type: flowchart
      source: self-generated
      justification: Illustrates the public Consumption-only scenario described in MSLearn environment and networking guidance.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/environment
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
    - id: scenario-b-internal-vnet
      type: flowchart
      source: self-generated
      justification: Illustrates the internal VNet scenario based on MSLearn vnet-custom and networking guidance.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints
    - id: scenario-c-workload-profiles
      type: flowchart
      source: self-generated
      justification: Illustrates the Workload Profiles scenario based on MSLearn workload-profiles-overview.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: ai-agent
  core_claims:
    - claim: Workload profiles environments support both Consumption and Dedicated plan types.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Workload profiles environments support user-defined routes and egress through NAT Gateway.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Consumption only environments do not support user-defined routes or egress through NAT Gateway.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: An existing virtual network deployment requires a subnet dedicated exclusively to the Container Apps environment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Managed identity can authenticate with a private Azure Container Registry without a username and password.
      source: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
      verified: true
---
# Deployment Scenarios

This page compares the reference deployment patterns used in this guide across different Azure Container Apps environment configurations.

!!! info "Guide defaults, not platform limits"
    The tables below reflect the deployment patterns implemented in this repository's Bicep templates and tutorials. Azure supports additional configurations beyond what is shown here.

## Scenario Overview

<!-- diagram-id: scenario-overview -->
```mermaid
flowchart TD
    accTitle: Three Container Apps deployment scenarios
    accDescr: Scenario A uses a legacy Consumption-only environment with a managed network and public ingress. Scenario B uses an internal, VNet-integrated workload profiles environment whose virtual IP maps to an internal load balancer endpoint. Scenario C compares Consumption and Dedicated workload profiles in one environment; Flexible profiles are another supported profile type but are outside this guide scenario. Thin arrows compare design choices and are not network traffic.

    START["Deployment requirements"]
    PUBLIC["A: Public managed network<br/>legacy Consumption-only<br/>public app endpoint"]
    PRIVATE["B: Internal custom VNet<br/>workload profiles environment<br/>internal load balancer endpoint"]
    MIXED["C: Mixed compute<br/>Consumption and Dedicated profiles<br/>per-app profile selection"]

    START -->|"Fastest public entry"| PUBLIC
    START -->|"Private network boundary"| PRIVATE
    START -->|"Mixed compute requirements"| MIXED
```

*Figure: Requirement-oriented comparison of the three guide scenarios. The arrows are design branches, not an upgrade sequence or packet path. Workload profiles environments are the current default; Scenario A retains the legacy Consumption-only model only as a simple reference pattern.*

## Matrix A — Networking and Security

| Feature | Scenario A: Public Consumption | Scenario B: Internal VNet | Scenario C: Workload Profiles |
|---|---|---|---|
| **Environment Type** | Legacy Consumption-only | Workload profiles | Workload profiles |
| **Environment accessibility** | External | Internal | Internal or external |
| **VNet Integration** | :material-close: No (Managed) | :material-check: Yes (Custom) | :material-check: Yes (Custom) |
| **App ingress in this example** | External app ingress on a public environment | External app ingress published at the environment's internal load balancer endpoint | Per app; independent of profile selection |
| **Registry identity in this example** | None; admin credentials | User-assigned managed identity | Not configured by the Scenario C command |
| **Registry Auth** | Admin credentials | Managed identity | Not configured by the example command |
| **Default domain reachability** | Public DNS and endpoint | Internal load balancer endpoint; connected clients need working DNS | Determined by environment accessibility and app ingress, not profile type |

## Matrix B — Deployment and Container Registry Mechanics

| Feature | Scenario A: Public Consumption | Scenario B: Internal VNet | Scenario C: Workload Profiles |
|---|---|---|---|
| **Compute Billing** | Consumption usage | Consumption profile usage | Dedicated instance allocation + Consumption profile usage |
| **Scaling behavior** | Consumption scaling rules | Consumption scaling rules | Profile-specific scaling and capacity limits |
| **Deployment Source** | ACR / Docker Hub | Private ACR | Private ACR / Artifact Registry |
| **Registry network path in this example** | Public ACR endpoint | Private ACR endpoint and private DNS | Chosen independently; not configured by the Scenario C command |
| **CLI Command** | `az containerapp up` | `az containerapp create` | `az containerapp create` |
| **Key Gotcha** | Admin keys must be enabled on ACR | Requires VNet DNS for image pull | Profile must be added to Environment first |

## Scenario A — Public Consumption (Simplest)

This guide keeps the legacy Consumption-only environment as its simplest public reference. New environments default to workload profiles, but the managed-network request path remains useful when you do not need custom VNet controls.

<!-- diagram-id: scenario-a-public-consumption -->
```mermaid
flowchart TD
    accTitle: Public Consumption-only request and image paths
    accDescr: An internet client sends HTTPS through managed ingress to a revision replica in a legacy Consumption-only environment. Separately, the platform pulls the image from the public endpoint of Azure Container Registry using configured registry credentials in this guide example.

    CLIENT["Internet client"]
    ACR["Azure Container Registry<br/>public endpoint"]

    subgraph ENV["Managed environment — legacy Consumption-only"]
        INGRESS["Managed ingress<br/>public environment endpoint"]
        APP["Container app<br/>external app ingress"]
        REV_ACTIVE["Active revision"]
        REPLICAS["Revision replicas<br/>Consumption compute"]
        IMAGE_PULL["Container Apps image pull<br/>during replica provisioning"]
    end

    CLIENT ==>|"HTTPS request"| INGRESS
    INGRESS ==>|"Select replica under revision traffic rules"| REPLICAS
    APP -.->|"Logical grouping"| REV_ACTIVE
    REV_ACTIVE -.->|"Revision configuration"| REPLICAS
    IMAGE_PULL ==> ACR
    ACR ==>|"Image pull response<br/>and returned layers"| IMAGE_PULL
    APP -.->|"Configured registry authorization"| ACR

    LEGEND["Arrow key<br/>thick = request or image transport<br/>dotted = logical grouping or authorization"]
```

*Figure: Public request path and separate image-pull dependency. Azure Container Registry is an associated Azure resource outside the managed environment. Registry authorization permits the pull; it is not itself a transport hop.*

**When to use**: Web apps, APIs, and microservices that require public internet access and don't need complex networking.

### CLI Implementation

```bash
# Create a container app with public ingress using admin credentials
az containerapp up \
    --resource-group $RG \
    --name $APP_NAME \
    --environment $ACA_ENV_NAME \
    --image $ACR_NAME.azurecr.io/$IMAGE_NAME:$TAG \
    --ingress external \
    --target-port 8080 \
    --registry-server $ACR_NAME.azurecr.io \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp up` | Creates or updates the container app from the supplied image. |
| `--resource-group` | Selects the resource group. |
| `--name` | Selects the container app name. |
| `--environment` | Selects the Container Apps environment. |
| `--image` | Selects the image and tag to deploy. |
| `--ingress` | Enables external app ingress. |
| `--target-port` | Sets the port on which the container listens. |
| `--registry-server` | Identifies the registry endpoint. |
| `--registry-username` | Supplies the registry username for this guide example. |
| `--registry-password` | Supplies the matching registry password. |

## Scenario B — Internal VNet (Private Environment)

For workloads that need an internal environment endpoint, create an internal, VNet-integrated workload profiles environment. The environment's virtual IP maps to an Azure internal load balancer endpoint; this is distinct from an Azure Private Endpoint resource. In this example the app uses **external app ingress relative to the environment**, so connected VNet clients can reach it through the environment's internal load balancer. Setting the app itself to internal ingress would instead limit its direct FQDN to the Container Apps environment and would not make it directly reachable from arbitrary VNet clients.

<!-- diagram-id: scenario-b-internal-vnet -->
```mermaid
flowchart TD
    accTitle: Private VNet-integrated Container Apps environment
    accDescr: A connected client resolves the internal environment endpoint, reaches its internal load balancer, and managed ingress selects a replica under revision traffic rules. The environment uses an exclusive delegated subnet of at least /27. A separate ACR private endpoint NIC and private DNS zone support image pulls; managed identity authorization is shown separately from transport.

    CLIENT["Connected client<br/>VNet or peered network"]
    DNS_ENV["Private DNS for<br/>environment domain"]
    DNS_ACR["Private DNS zone<br/>privatelink.azurecr.io"]
    ACR["Azure Container Registry"]
    IDENTITY["Managed identity<br/>registry authorization"]

    subgraph ENV["Internal workload profiles environment"]
        ENV_ENDPOINT["Internal environment endpoint"]
        INGRESS["Managed ingress<br/>internal load balancer endpoint"]
        APP["Container app<br/>external app ingress"]
        REV_ACTIVE["Active revision"]
        REPLICAS["Revision replicas"]
        IMAGE_PULL["Container Apps image pull<br/>during replica provisioning"]
        VNET_LINK["VNet integration boundary"]
    end

    subgraph VNET["Customer virtual network"]
        INFRA_SUB["Exclusive environment subnet<br/>/27 or larger; Microsoft.App/environments delegated"]
        subgraph PE_SUB["Private endpoint subnet"]
            PE_ACR["ACR private endpoint NIC"]
        end
    end

    CLIENT -.->|"Resolve environment name"| DNS_ENV
    DNS_ENV -.->|"Return private endpoint address"| ENV_ENDPOINT
    CLIENT ==>|"HTTPS request"| ENV_ENDPOINT
    ENV_ENDPOINT ==>|"Forward to managed ingress"| INGRESS
    INGRESS ==>|"Select replica under traffic rules"| REPLICAS
    APP -.->|"Logical grouping"| REV_ACTIVE
    REV_ACTIVE -.->|"Revision configuration"| REPLICAS
    INFRA_SUB -.->|"Environment VNet integration"| VNET_LINK
    DNS_ACR -.->|"ACR private address"| PE_ACR
    IMAGE_PULL ==> PE_ACR
    PE_ACR ==>|"Private Link pull"| ACR
    ACR ==>|"Image layers"| PE_ACR
    PE_ACR ==> IMAGE_PULL
    IDENTITY -.->|"ACR authorization"| ACR

    LEGEND["Arrow key<br/>thick = request or image transport<br/>dotted = DNS, authorization, or logical relationship"]
```

*Figure: Internal environment topology extending the [architecture base](architecture/index.md#managed-environment-ingress-revisions-and-scaling). The managed environment is logically associated with the delegated subnet; the ACR private endpoint NIC is a separate resource in its own subnet, while ACR, managed identity, and private DNS remain associated Azure resources.*

**When to use**: Internal microservices, backend APIs, or applications that require private inbound reachability from a VNet or connected network. If outbound traffic must also avoid public paths, add controlled egress and private endpoints for the required dependencies.

### CLI Implementation

```bash
# Create a container app in an internal environment using Managed Identity for registry pull
az containerapp create \
    --resource-group $RG \
    --name $APP_NAME \
    --environment $ACA_ENV_NAME \
    --image $ACR_NAME.azurecr.io/$IMAGE_NAME:$TAG \
    --ingress external \
    --target-port 80 \
    --user-assigned $UAMI_ID \
    --registry-server $ACR_NAME.azurecr.io \
    --registry-identity $UAMI_ID
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp create` | Creates the app in an existing internal environment. |
| `--resource-group` | Selects the resource group. |
| `--name` | Selects the container app name. |
| `--environment` | Selects the already-created internal Container Apps environment. |
| `--image` | Selects the image and tag to deploy. |
| `--ingress` | Enables app ingress at the environment endpoint; the environment remains private. |
| `--target-port` | Sets the port on which the container listens. |
| `--user-assigned` | Associates a user-assigned managed identity with the app. |
| `--registry-server` | Identifies the registry endpoint. |
| `--registry-identity` | Uses the managed identity for registry authorization instead of a password. |

## Scenario C — Workload Profiles (Dedicated Compute)

A workload profiles environment always includes the Consumption profile and can also contain Dedicated profiles. Flexible profiles are a third profile type, currently in preview, but are outside this two-profile scenario. Each app selects one profile; multiple apps can share one Dedicated profile instance, so use separate profiles or environments when workloads must not share compute.

<!-- diagram-id: scenario-c-workload-profiles -->
```mermaid
flowchart TD
    accTitle: Consumption and Dedicated placement in one workload profiles environment
    accDescr: Managed ingress routes requests to two container apps. One app's replicas use the Consumption profile and the other app's replicas use a selected Dedicated profile. Profile placement is a logical relationship rather than request transport.

    CLIENT["Request caller"]

    subgraph ENV["Managed environment — workload profiles"]
        INGRESS["Managed ingress"]
        APP_CONS["API container app"]
        REV_CONS["API active revision"]
        REP_CONS["API replicas"]
        APP_DED["Memory-intensive container app"]
        REV_DED["Memory app active revision"]
        REP_DED["Memory app replicas"]
        PROFILE_CONS["Consumption profile<br/>serverless placement"]
        PROFILE_DED["Selected Dedicated profile<br/>reserved instance placement"]
    end

    CLIENT ==>|"HTTPS request"| INGRESS
    INGRESS ==>|"Select API replica under traffic rules"| REP_CONS
    INGRESS ==>|"Select memory-app replica under traffic rules"| REP_DED
    APP_CONS -.->|"Logical grouping"| REV_CONS
    APP_DED -.->|"Logical grouping"| REV_DED
    REV_CONS -.->|"Revision configuration"| REP_CONS
    REV_DED -.->|"Revision configuration"| REP_DED
    PROFILE_CONS -.->|"Compute placement"| REP_CONS
    PROFILE_DED -.->|"Compute placement"| REP_DED

    LEGEND["Arrow key<br/>thick = runtime request<br/>dotted = grouping or compute placement"]
```

*Figure: Workload-profile placement extending the [architecture base](architecture/index.md#managed-environment-ingress-revisions-and-scaling). Consumption and Dedicated are profile choices inside one managed environment; they are not separate ingress paths or customer-managed node pools.*

**When to use**: High-performance applications, memory-intensive jobs, or workloads that need reserved capacity, larger resource sizes, or profile-specific hardware. Use separate profiles or environments when strict workload separation is required.

### CLI Implementation

```bash
# Create a container app using a specific workload profile
az containerapp create \
    --resource-group $RG \
    --name $APP_NAME \
    --environment $ACA_ENV_NAME \
    --workload-profile-name "D4" \
    --cpu 2.0 \
    --memory 4Gi \
    --image $IMAGE_NAME
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp create` | Creates the app in an existing workload profiles environment. |
| `--resource-group` | Selects the resource group. |
| `--name` | Selects the container app name. |
| `--environment` | Selects the Container Apps environment. |
| `--workload-profile-name` | Selects a profile that already exists in the environment. |
| `--cpu` | Sets the requested CPU within the selected profile's supported resources. |
| `--memory` | Sets the requested memory within the selected profile's supported resources. |
| `--image` | Selects the image to deploy. |

## Pre-Deployment Checklist

Before deploying any scenario, verify:

- [ ] **Resource group** exists in a region supporting Container Apps
- [ ] **Environment Name** is unique within the resource group
- [ ] **Subnet model** matches the environment type: workload profiles use an exclusive delegated `/27` or larger subnet; legacy Consumption-only uses an exclusive undelegated `/23` or larger subnet
- [ ] **Managed identity** has `AcrPull` on a registry using the RBAC Registry Permissions mode, or `Container Registry Repository Reader` on an ABAC-enabled registry
- [ ] **Port mapping** matches the container's listening port
- [ ] **Scale rules** (min/max replicas) are defined to prevent unexpected costs
- [ ] **Private DNS** resolves the internal environment domain and every required ACR private-endpoint record (Scenario B)

## Verify deployment-scenario surfaces in Azure Portal

![ca-sample-d38538 | Ingress | Container App | Refresh | Send us your feedback | Ingress | Ingress traffic | Limited to Container Apps Environment | Accepting traffic from anywhere | Ingress type | HTTP | TCP | Client certificate mode | Ignore | Accept | Require | Transport | Auto | Insecure connections | Target port | 80 | Endpoint(s) | https://<app-name>.<unique-id>.<region>.azurecontainerapps.io | Session affinity | Additional TCP ports | IP Restrictions | IP Security Restrictions Mode | Allow all traffic (default) | Save | Discard](../assets/platform/deployment-scenarios-ingress-blade.png)

**[Observed]** `ca-sample-d38538 | Ingress` `Container App` `Refresh` `Send us your feedback` `Ingress` `Ingress traffic` `Limited to Container Apps Environment` `Accepting traffic from anywhere` `Ingress type` `HTTP` `TCP` `Client certificate mode` `Ignore` `Accept` `Require` `Transport` `Auto` `Insecure connections` `Target port` `80` `Endpoint(s)` `https://<app-name>.<unique-id>.<region>.azurecontainerapps.io` `Session affinity` `Additional TCP ports` `IP Restrictions` `IP Security Restrictions Mode` `Allow all traffic (default)` `Save` `Discard`.

**[Inferred]** The `Limited to Container Apps Environment` radio option represents internal **app ingress**, which is narrower than the private **environment endpoint** used in [Scenario B — Internal VNet (Private Environment)](#scenario-b-internal-vnet-private-environment). The `Accepting traffic from anywhere` radio paired with the external `Endpoint(s)` value appears to map to the external app-ingress setting used in both Scenario A and Scenario B; whether that endpoint is public or private depends on environment accessibility. The `IP Restrictions` section with the `IP Security Restrictions Mode` `Allow all traffic (default)` value is consistent with the networking-and-security comparison surface listed in [Matrix A — Networking and Security](#matrix-a-networking-and-security).

**[Not Proven]** Additional environment configuration detail, networking binding detail, registry authentication detail, and workload profile detail are not visible on this view.

## See Also

- [Environments](environments/index.md) — differences between Consumption and Workload Profiles
- [Networking](networking/index.md) — internal vs external ingress and VNet integration
- [Managed Identity](identity-and-secrets/managed-identity.md) — securing access to registries and other Azure resources
- [Scaling](scaling/index.md) — configuring KEDA-based scaling rules

## Sources

- [Azure Container Apps environments (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/environment)
- [Workload profiles in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview)
- [Networking in Azure Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Provide a virtual network to an Azure Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom)
- [Managed identity image pulls in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Azure Container Registry roles and ABAC repository permissions (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-abac-repository-permissions)
- [Private endpoints with DNS in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/private-endpoints-with-dns)
- [Private endpoints for Azure Container Registry (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints)
- [Containers in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/containers)
