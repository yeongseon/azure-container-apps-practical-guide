---
description: Azure Container Apps egress control with user-defined routes, Azure Firewall, NAT Gateway, DNS, NSGs, and managed-identity dependencies.
content_sources:
  diagrams:
    - id: route-outbound-traffic-through-azure-firewall
      type: flowchart
      source: self-generated
      justification: Logical egress topology synthesized from Microsoft Learn; it separates the logical ACA runtime, dedicated environment subnet relationship, DNS, NSG, route selection, firewall policy, and public transport without depicting undocumented managed internals.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes
        - https://learn.microsoft.com/en-us/azure/container-apps/use-azure-firewall
        - https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview
    - id: nat-gateway-architecture
      type: flowchart
      source: self-generated
      justification: Logical NAT Gateway extension synthesized from Microsoft Learn; NAT association and SNAT are shown separately from DNS, NSG evaluation, and destination authorization.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks#azure-nat-gateway-integration
        - https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview
    - id: managed-identity-acr-egress-dependencies
      type: flowchart
      source: self-generated
      justification: Dependency flow synthesized from Microsoft Learn; DNS resolution, managed-identity token acquisition, registry authorization, and image transport are distinct checks rather than one inferred network path.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
        - https://learn.microsoft.com/en-us/azure/container-apps/use-azure-firewall
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: ai-agent
  core_claims:
    - claim: Workload profiles environments support user-defined routes and egress through NAT Gateway.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Consumption only environments do not support user-defined routes or egress through NAT Gateway.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Using an existing virtual network enables Azure Firewall integration for Container Apps.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Using a NAT Gateway or other outbound proxy for outbound traffic from a Container Apps environment is supported only in a workload profiles environment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Managed identity-based pulls from Azure Container Registry in restricted egress environments require outbound access to AzureActiveDirectory, and ACR image pulls also depend on registry and regional storage endpoints.
      source: https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
      verified: true
---
# Egress Control

Control outbound traffic from Container Apps.

## Default Behavior

By default, Container Apps can access:
- Public internet
- Azure services via public endpoints
- Resources in the same VNet (if VNet integrated)

!!! warning "Uncontrolled egress increases data exfiltration risk"
    Production workloads should define explicit outbound paths and approved destinations,
    especially when handling regulated or sensitive data.

## Egress Strategy Comparison

| Strategy | Primary Goal | Trade-off | Typical Fit |
|---|---|---|---|
| Default outbound | Fast setup | Minimal governance | Dev/test environments |
| UDR + Azure Firewall | Domain/IP filtering and inspection | Higher complexity and cost | Regulated production workloads |
| NAT Gateway | Static outbound IP for allow-lists | No L7 filtering by itself | SaaS allow-list integrations |

## Portal view: non-integrated starting point for UDR and NAT Gateway recipes

This screenshot is used here as a visual starting point for the Bicep examples in [User-Defined Routes (UDR)](#user-defined-routes-udr) and [NAT Gateway for Static Outbound IP](#nat-gateway-for-static-outbound-ip).

![Networking blade showing "General" selected; "Public Network Access" with "Enable: Allows incoming traffic from the public internet." selected; "Virtual network" section reading "This environment isn't integrated"; tab strip lists "General", "Ingress settings", "Request Routing", "Encryption", "Custom DNS Suffix"](../../assets/platform/environments/03-networking.png)

[Observed] The `Public Network Access` section has `Enable: Allows incoming traffic from the public internet.` selected. The `Virtual network` section reads `This environment isn't integrated`. The tab strip lists `General`, `Ingress settings`, `Request Routing`, `Encryption`, `Custom DNS Suffix`. No route table, NAT gateway, or firewall reference is visible in the shown content.

[Inferred] The visible `This environment isn't integrated` text is consistent with this page using the screenshot as a contrast point for the Bicep examples in [User-Defined Routes (UDR)](#user-defined-routes-udr) and [NAT Gateway for Static Outbound IP](#nat-gateway-for-static-outbound-ip). The screenshot appears to map to a configuration context separate from the `routeTable` and `natGateway` subnet properties shown in those examples.

[Not Proven] This image does not show the `Microsoft.Network/routeTables` resource from [User-Defined Routes (UDR)](#user-defined-routes-udr). It does not show the `Microsoft.Network/natGateways` resource from [NAT Gateway for Static Outbound IP](#nat-gateway-for-static-outbound-ip). It does not show the `Microsoft.Network/firewallPolicies` resource from [Azure Firewall Rules](#azure-firewall-rules). It does not show the service tags listed in [Required Outbound Dependencies](#required-outbound-dependencies). It does not show the managed identity ACR egress dependencies discussed later in [Required Outbound Dependencies](#required-outbound-dependencies).

## User-Defined Routes (UDR)

Route outbound traffic through Azure Firewall or NVA:

### Route selection, inspection, and transport

**Takeaway:** A workload-profiles environment can use a dedicated environment subnet whose route table sends matching outbound packets to Azure Firewall; DNS resolution, NSG evaluation, route selection, firewall policy, and the destination response remain separate decisions.

<!-- diagram-id: route-outbound-traffic-through-azure-firewall -->
```mermaid
flowchart TD
    accTitle: Container Apps outbound traffic through Azure Firewall
    accDescr: A logical Container Apps revision and replica use a dedicated environment subnet relationship. DNS resolution is separate from the packet path. The subnet NSG and route table evaluate outbound traffic before a default user-defined route selects Azure Firewall, whose policy allows or denies transport to a public dependency.

    DNS_NAME["Dependency FQDN"]
    DNS["DNS resolver<br/>name to destination IP"]

    subgraph ENV["Managed Container Apps environment — logical boundary"]
        APP["Container app — logical grouping"]
        REV_ACTIVE["Active revision — immutable app version"]
        REPLICAS["Revision replicas — running instances"]
        APP -.-> REV_ACTIVE
        REV_ACTIVE -.-> REPLICAS
    end

    subgraph VNET["Customer-managed virtual network"]
        subgraph ENV_SUBNET["Dedicated environment subnet"]
            SUBNET_LINK["ACA environment subnet relationship"]
            NSG{"NSG outbound rule<br/>allows destination?"}
            ROUTE{"Route table<br/>matching UDR?"}
        end

        subgraph FW_SUBNET["Firewall subnet — AzureFirewallSubnet"]
            FW["Azure Firewall<br/>private next hop"]
            POLICY{"Firewall policy<br/>allows destination?"}
        end
    end

    DEST["Approved public dependency"]
    DENY["DENY<br/>blocked before destination"]

    ENV -.->|"uses dedicated subnet"| SUBNET_LINK
    REPLICAS -.->|"1  Resolve name"| DNS_NAME
    DNS_NAME -.-> DNS
    DNS -.->|"2  Return destination IP"| REPLICAS
    REPLICAS ==>|"3  Outbound packet"| NSG
    NSG ==>|"Allow"| ROUTE
    NSG -.->|"Deny"| DENY
    ROUTE ==>|"4  UDR: virtual appliance"| FW
    FW -->|"5  Evaluate"| POLICY
    POLICY ==>|"Allow and forward"| DEST
    POLICY -.->|"Deny"| DENY
    DEST ==>|"6  Response on established flow"| FW

    LEGEND["Arrow key<br/>thick = packet transport<br/>solid = policy evaluation<br/>dotted = DNS, logical relationship, or denied branch"]
```

*Figure: Azure Firewall egress extension of the shared `ENV` → `APP` → `REV_ACTIVE` → `REPLICAS` vocabulary. The customer VNet owns the dedicated environment subnet controls and firewall resources; the managed runtime stays a logical Azure-managed boundary.*

```bicep
resource routeTable 'Microsoft.Network/routeTables@2023-05-01' = {
  name: 'rt-containerapp'
  location: location
  properties: {
    routes: [
      {
        name: 'default-route'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}
```

## Azure Firewall Rules

Allow required outbound traffic:

### NAT Gateway Architecture

**Takeaway:** Associating NAT Gateway with the dedicated environment subnet gives supported workload-profiles environments a predictable public source address for internet egress, but it does not perform DNS resolution, application-layer filtering, or destination authorization.

<!-- diagram-id: nat-gateway-architecture -->
```mermaid
flowchart TD
    accTitle: Container Apps egress through NAT Gateway
    accDescr: A logical Container Apps replica resolves a public dependency name, then sends a packet through subnet network controls. A NAT Gateway associated with the dedicated environment subnet translates the source to its public IP before the packet reaches the internet dependency. DNS and destination authorization are independent.

    DNS_NAME["Dependency FQDN"]
    DNS["DNS resolver<br/>name to destination IP"]

    subgraph ENV["Managed Container Apps environment — logical boundary"]
        APP["Container app — logical grouping"]
        REV_ACTIVE["Active revision — immutable app version"]
        REPLICAS["Revision replicas — running instances"]
        APP -.-> REV_ACTIVE
        REV_ACTIVE -.-> REPLICAS
    end

    subgraph VNET["Customer-managed virtual network"]
        subgraph ENV_SUBNET["Dedicated environment subnet"]
            SUBNET_LINK["ACA environment subnet relationship"]
            NSG{"NSG outbound rule<br/>allows destination?"}
        end

        NAT["Azure NAT Gateway<br/>associated with subnet"]
        PIP["Public IP address<br/>predictable SNAT source"]
    end

    DEST["Public dependency"]
    AUTH{"Destination authorization<br/>accepts request?"}
    DENY["DENY<br/>blocked by NSG or destination"]

    ENV -.->|"uses dedicated subnet"| SUBNET_LINK
    NAT -.->|"subnet association"| ENV_SUBNET
    NAT -->|"uses for SNAT"| PIP
    REPLICAS -.->|"1  Resolve name"| DNS_NAME
    DNS_NAME -.-> DNS
    DNS -.->|"2  Return destination IP"| REPLICAS
    REPLICAS ==>|"3  Outbound packet"| NSG
    NSG ==>|"Allow"| NAT
    NSG -.->|"Deny"| DENY
    PIP ==>|"4  SNAT source to internet"| DEST
    DEST -->|"5  Evaluate request"| AUTH
    AUTH ==>|"Accept; response flow"| NAT
    AUTH -.->|"Reject"| DENY

    LEGEND["Arrow key<br/>thick = packet transport<br/>solid = evaluation or resource use<br/>dotted = DNS, association, logical relationship, or denied branch"]
```

*Figure: NAT Gateway extension of the same logical ACA runtime vocabulary. The NAT resource is associated with the customer-managed subnet; it is not drawn as an App Service-style integration NIC or as an Azure-managed component inside the environment.*

```bicep
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-05-01' = {
  name: 'fw-policy'
  properties: {
    sku: { tier: 'Standard' }
  }
}
```

## Azure Firewall Rules

Allow required outbound traffic:

```bicep
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-05-01' = {
  name: 'fw-policy'
  properties: {
    sku: { tier: 'Standard' }
  }
}

resource appRuleCollection 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-05-01' = {
  parent: firewallPolicy
  name: 'container-apps-rules'
  properties: {
    priority: 100
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-external-apis'
        priority: 100
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-jsonplaceholder'
            protocols: [{ protocolType: 'Https', port: 443 }]
            targetFqdns: ['jsonplaceholder.typicode.com']
            sourceAddresses: ['10.0.0.0/23']
          }
        ]
      }
    ]
  }
}
```

## NAT Gateway for Static Outbound IP

Assign static IP for outbound traffic:

```bicep
resource natGateway 'Microsoft.Network/natGateways@2023-05-01' = {
  name: 'nat-containerapp'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIpAddresses: [{ id: publicIp.id }]
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  name: 'snet-containerapp'
  properties: {
    addressPrefix: '10.0.0.0/23'
    natGateway: { id: natGateway.id }
  }
}
```

!!! tip "Combine NAT and firewall when needed"
    Use NAT Gateway for predictable source IP and Azure Firewall for destination governance
    when both compliance and partner allow-list requirements exist.

## Verify Outbound IP

```python
import requests

@app.route('/api/my-ip')
def my_ip():
    # Use standard service to verify public outbound IP
    response = requests.get('https://api.ipify.org?format=json')
    return response.json()  # Returns NAT Gateway's public IP
```

## Required Outbound Dependencies

If you restrict egress and pull application images from Azure Container Registry (ACR) by using managed identity, allow the dependency categories that support both token acquisition and image download.

| Service Tag / Dependency | Port | When Required |
|---|---|---|
| `AzureActiveDirectory` | 443 | Required when the container app uses managed identity to obtain an access token for ACR. |
| `ACR login server` | 443 | Required for the registry endpoint (for example, `<registry-name>.azurecr.io`) unless you use a private endpoint for the registry. |
| `Storage.<Region>` | 443 | Required for ACR-backed image layer downloads from regional storage. |
| `MicrosoftContainerRegistry` | 443 | Required for Microsoft-managed system container dependencies in the environment. |
| `AzureContainerRegistry` | 443 | Required when pulling images from ACR without a private endpoint. When using a private endpoint for ACR, this tag is not required. |
| `AzureFrontDoor.FirstParty` | 443 | Required as a dependency of Microsoft Container Registry. |

When using Azure Firewall application rules instead of (or in addition to) NSG service tags, allow these FQDNs for managed identity token acquisition:

| FQDN | When Required |
|---|---|
| `login.microsoftonline.com` | Token issuance for managed identity |
| `*.login.microsoftonline.com` | Regional token endpoints |
| `login.microsoft.com` | Primary Microsoft login endpoint |
| `*.login.microsoft.com` | Alternative login endpoints |
| `*.identity.azure.net` | Managed identity metadata |

Use service tags where Azure provides them, and use private endpoints or FQDN-aware firewall rules for registry-specific destinations.

### Identity, authorization, DNS, and image transport

**Takeaway:** A successful managed-identity image pull needs separate successes for DNS, token acquisition, ACR authorization, and registry/image-layer transport; a failure in one stage does not prove a failure in the others.

<!-- diagram-id: managed-identity-acr-egress-dependencies -->
```mermaid
flowchart TD
    accTitle: Managed-identity ACR image-pull dependencies
    accDescr: A logical Container Apps revision requires DNS answers, a managed-identity token from Microsoft Entra ID, ACR authorization, and allowed HTTPS transport to registry and image-layer dependencies. Network controls evaluate transport separately. Failure labels distinguish DNS, routing or filtering, authorization, and image download symptoms.

    subgraph ENV["Managed Container Apps environment — logical boundary"]
        APP["Container app — logical grouping"]
        REV_ACTIVE["Active revision<br/>image reference and identity"]
        REPLICAS["Revision replicas<br/>start after image is available"]
        APP -.-> REV_ACTIVE
        REV_ACTIVE -.-> REPLICAS
    end

    DNS["DNS resolver<br/>dependency names to IPs"]
    NET{"Customer egress controls<br/>NSG, route, firewall policy"}
    ENTRA["Microsoft Entra ID<br/>managed-identity token"]
    MCR["Microsoft Artifact Registry<br/>required system dependencies"]
    ACR_AUTH{"Azure Container Registry<br/>authorize image pull?"}
    ACR_DATA["ACR login and data endpoints<br/>HTTPS transport"]
    STORAGE["Regional storage dependency<br/>image layers"]

    DNS_FAIL["DNS FAILURE<br/>name does not resolve"]
    NET_FAIL["TRANSPORT FAILURE<br/>route or policy blocks HTTPS"]
    AUTH_FAIL["AUTHORIZATION FAILURE<br/>token or role rejected"]
    PULL_FAIL["OBSERVED OUTCOME<br/>image pull or revision start fails"]

    REV_ACTIVE -.->|"1  DNS query"| DNS
    DNS -.->|"DNS answer"| REV_ACTIVE
    DNS -.->|"No answer"| DNS_FAIL

    REV_ACTIVE ==>|"2  HTTPS token request"| NET
    NET ==>|"Allowed transport"| ENTRA
    NET ==>|"Required platform HTTPS"| MCR
    NET -.->|"Blocked transport"| NET_FAIL
    ENTRA -->|"3  Token"| ACR_AUTH
    ACR_AUTH ==>|"4  Authorized pull"| ACR_DATA
    ACR_AUTH -.->|"Rejected"| AUTH_FAIL
    ACR_DATA ==>|"5  Download image data"| STORAGE
    STORAGE ==>|"6  Image available"| REV_ACTIVE

    DNS_FAIL -.-> PULL_FAIL
    NET_FAIL -.-> PULL_FAIL
    AUTH_FAIL -.-> PULL_FAIL

    LEGEND["Arrow key<br/>thick = HTTPS or image-data transport<br/>solid = identity or authorization result<br/>dotted = DNS, logical relationship, or fault correlation"]
```

*Figure: ACR dependency extension of the shared `ENV` → `APP` → `REV_ACTIVE` → `REPLICAS` vocabulary. This is a dependency model, not an ACR Path A–E topology and not proof of any observed packet route.*

!!! warning "Private ACR does not remove all outbound requirements"
    Even when ACR uses a private endpoint, managed identity image pulls still require outbound access to `AzureActiveDirectory` on port `443` so the platform can acquire a token.

Also keep DNS to `168.63.129.16:53` available; blocking platform DNS breaks name resolution for these dependencies.

For the failure symptoms and validation steps, see [Image Pull Failure](../../troubleshooting/playbooks/startup-and-provisioning/image-pull-failure.md).

The same egress dependency applies to control-plane operations that authenticate with the app's managed identity — for example, `az containerapp secret set --identity ... --key-vault-url ...` performs OIDC discovery against `login.microsoftonline.com/<tenant>/.well-known/openid-configuration` before token acquisition. When a UDR routes the workload subnet through Azure Firewall and the firewall policy lacks an Application Rule for `login.microsoftonline.com` and `login.microsoft.com`, the discovery request fails with a transport-level `EOF` and the secret update returns `Unable to get value using Managed identity`. For the reproducible falsification proof, see [ACA Secret Key Vault Reference — Managed Identity Network Path Lab](../../troubleshooting/lab-guides/aca-secret-kv-ref-mi-network-path.md) and [Secret and Key Vault Reference Failure — H4](../../troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md#h4-managed-identity-oidc-discovery-blocked-by-egress-control-udr-azure-firewall).

## See Also
- [VNet Integration](vnet-integration.md)
- [Private Endpoints](private-endpoints.md)
- [ACR Network Path Selection](acr-network-path-selection.md)
- [Service-to-Service Communication](service-to-service.md)

## Sources
- [Outbound FQDN requirements in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking#outbound-fqdn-requirements)
- [User-defined routes in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes)
- [Firewall integration in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration)
- [Use Azure Firewall with Azure Container Apps — outbound FQDNs (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/use-azure-firewall)
