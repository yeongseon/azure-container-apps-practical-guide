---
description: How Azure Application Gateway reaches an internal Container Apps environment through app FQDN resolution, and why workload-profile NSG rules target the Container Apps subnet rather than staticIp.
content_sources:
  diagrams:
    - id: appgw-to-internal-aca-architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway
        - https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom-internal
        - https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
        - https://learn.microsoft.com/en-us/azure/application-gateway/configuration-http-settings
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
    - id: nsg-evaluation-behind-ilb
      type: flowchart
      source: self-generated
      justification: Synthesized from the Microsoft Learn firewall-integration workload-profile NSG table and the Azure network-security-groups overview on how NSGs behind load-balanced pools evaluate destination.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
        - https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview
content_validation:
  status: verified
  last_reviewed: 2026-11-07
  reviewer: agent
  core_claims:
    - claim: An internal Container Apps environment has an internal load balancer IP, and the Application Gateway integration guidance uses the environment `staticIp` in private DNS A records.
      source: https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway
      verified: true
    - claim: For an internal Container Apps environment fronted by Application Gateway, the recommended pattern is a Private DNS Zone named after the environment `defaultDomain` with wildcard and apex A records pointing to `staticIp`.
      source: https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway
      verified: true
    - claim: In a workload profiles environment, the inbound NSG rule for HTTPS from client IPs uses Destination = the container app's subnet and Destination ports 443 and 31443, where 31443 is the port on which the Container Apps environment edge proxy responds to HTTPS traffic behind the internal load balancer.
      source: https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
      verified: true
    - claim: In a workload profiles environment, the inbound NSG rule for HTTP from client IPs uses Destination = the container app's subnet and Destination ports 80 and 31080, where 31080 is the port on which the Container Apps environment edge proxy responds to HTTP traffic behind the internal load balancer.
      source: https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
      verified: true
    - claim: In a workload profiles environment, the inbound NSG rule for Azure Load Balancer health probes uses Source = AzureLoadBalancer and Destination ports 30000-32767.
      source: https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
      verified: true
    - claim: For virtual machines in load-balanced pools, Azure NSG destination address and port refer to the destination computer rather than the load balancer.
      source: https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview
      verified: true
---
# Application Gateway Integration with an Internal Container Apps Environment

Fronting an internal Container Apps environment with Azure Application Gateway is a common enterprise pattern: Application Gateway (with or without WAF) provides the public edge, DNS, TLS, and header rewrites; the Container Apps environment stays internal to the virtual network. Getting this pattern to work end-to-end forces two decisions that regularly get answered incorrectly:

1. What role does the environment `staticIp` actually play?
2. What does the inbound NSG on the Container Apps subnet need to allow, and against which destination?

This page answers both. If you already have Application Gateway configured and the health probe is failing with the backend showing `Unhealthy`, jump to the [AppGW to Internal Azure Container Apps NSG Destination playbook](../../troubleshooting/playbooks/ingress-and-networking/appgw-to-internal-aca-nsg-destination.md).

## Overview

The reference topology is documented in [Protect Azure Container Apps with Application Gateway and Web Application Firewall (WAF)](https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway). At a high level:

- Application Gateway lives in its own subnet inside the same virtual network as the Container Apps environment.
- The Container Apps environment is created as internal (`internal: true` / `--internal-only true`).
- A Private DNS Zone named after the environment `defaultDomain` (for example, `<env-suffix>.<region>.azurecontainerapps.io`) is created and linked to the virtual network.
- Wildcard (`*`) and apex (`@`) A records in that Private DNS Zone point to the environment `staticIp`.
- Application Gateway's backend pool targets the container app's FQDN, and Application Gateway resolves that FQDN to `staticIp` through the linked Private DNS Zone.

## Architecture

**Takeaway:** Application Gateway targets the app FQDN, resolves it through the VNet-linked private DNS zone, terminates the client TLS connection, and—when its backend setting uses HTTPS—starts a separate TLS connection to the Container Apps ingress endpoint. Container Apps terminates that backend TLS connection at managed ingress before routing the request to a replica.

<!-- diagram-id: appgw-to-internal-aca-architecture -->
```mermaid
flowchart TD
    accTitle: Application Gateway to an internal Container Apps environment
    accDescr: A public client establishes HTTPS to Application Gateway, where client TLS terminates. Application Gateway resolves the container app FQDN through private DNS and, with an HTTPS backend setting, establishes a separate HTTPS connection to the internal environment entry. Container Apps terminates backend TLS at managed ingress before routing the request to an active revision replica. Thick arrows show request transport; only explicitly labelled segments are HTTPS.

    CLIENT["Public client"]
    PIP["Application Gateway<br/>public frontend"]
    PDNS["Private DNS zone<br/>environment default domain<br/>wildcard and apex A records → staticIp"]

    subgraph VNET["Customer-managed virtual network"]
        subgraph AGW_SUBNET["Application Gateway subnet"]
            AGW["Azure Application Gateway<br/>client TLS terminates here<br/>backend target = app FQDN"]
        end
        subgraph ENV_SUBNET["Dedicated Container Apps environment subnet"]
            ENV_LINK["Internal environment entry<br/>staticIp"]
        end
    end

    subgraph ENV["Managed Container Apps environment — logical boundary"]
        INGRESS["Managed ingress proxy<br/>backend TLS terminates here<br/>request routing"]
        APP["Container app<br/>logical grouping"]
        REV_ACTIVE["Active revision<br/>immutable app version"]
        REPLICAS["Revision replicas<br/>running instances"]
    end

    CLIENT ==>|"1  HTTPS"| PIP
    PIP ==>|"2  Client HTTPS connection"| AGW
    AGW -.->|"3  Resolve app FQDN"| PDNS
    PDNS -.->|"4  Return staticIp"| AGW
    PDNS -.->|"zone linked to VNet"| VNET
    AGW ==>|"5  New HTTPS connection<br/>when backend protocol = HTTPS"| ENV_LINK
    ENV_LINK ==>|"6  Backend HTTPS connection"| INGRESS
    INGRESS ==>|"7  Request after TLS termination"| REV_ACTIVE
    REV_ACTIVE ==>|"8  Select replica"| REPLICAS
    APP -.->|"Logical revision membership"| REV_ACTIVE
    ENV -.->|"uses dedicated subnet"| ENV_LINK

    LEGEND["Arrow key<br/>thick = request transport; HTTPS only where labelled<br/>dotted = DNS, association, or logical relationship"]
```

*Figure: Application Gateway is in its own subnet and reaches the internal environment by the app FQDN. The managed environment remains a logical Azure-managed boundary; the figure does not place hidden platform nodes in the customer VNet.*

Two things in this diagram matter for NSG design:

- Application Gateway sends the packet to the address returned for the app FQDN: `staticIp`, the internal environment ingress address used by the walkthrough.
- For workload-profile environments, Microsoft Learn specifies the Container Apps subnet—not `staticIp`—as the NSG rule destination for this inbound path. That distinction is the source of the most common misconfiguration in this topology.

## Environment `staticIp` in an internal environment

For an internal Container Apps environment, `properties.staticIp` is the environment's ingress virtual IP. Microsoft Learn documents it as the value you write into the wildcard A record in the Private DNS Zone that fronts the environment. Retrieve it as follows:

```bash
az containerapp env show \
  --name "$ACA_ENV_NAME" \
  --resource-group "$RG" \
  --query "properties.staticIp" \
  --output tsv
```

| Command | Why it is used |
|---|---|
| `az containerapp env show ...` | Retrieves the environment properties, including `staticIp`, `defaultDomain`, and `vnetConfiguration`. |

For the purpose of Application Gateway backend pool configuration, do not target `staticIp` directly — target the container app FQDN and let Application Gateway resolve it to `staticIp` through the linked Private DNS Zone. `staticIp` is what appears on the wire as the packet destination (after DNS resolution), and it is the value written into the Private DNS A record for the environment default domain, but it is **not** the address an NSG evaluates against on the Container Apps subnet. That distinction is covered next.

## How workload-profile NSG rules are evaluated

In a workload profiles environment, the dedicated Container Apps subnet carries the internal environment path. When Application Gateway sends a packet to `staticIp:443`, the documented model is:

1. Application Gateway connects to the `staticIp` returned by private DNS for the app FQDN; the internal environment uses an internal load balancer ingress path.
2. The environment forwards the connection to the managed ingress backend path in the Container Apps subnet.
3. The workload-profile NSG rule must name the Container Apps subnet as its destination and allow the documented ingress ports; a rule that names only `staticIp` does not match the documented destination contract.

The Azure Virtual Network documentation explains the general load-balanced-pool rule: destination port and address refer to the destination computer rather than the load balancer. The Container Apps firewall-integration table then gives the service-specific contract for workload-profile environments: use **the container app's subnet**—not `staticIp`—as the Destination. The diagram below stays at that documented boundary and does not invent managed NICs or proxy instances.

<!-- diagram-id: nsg-evaluation-behind-ilb -->
```mermaid
flowchart TD
    accTitle: Workload-profile NSG destination behind the internal environment entry
    accDescr: Application Gateway sends HTTPS to the internal environment static IP. After internal load balancing, the Container Apps subnet NSG rule is evaluated against the documented subnet destination and ingress ports. A subnet-scoped rule allows the request to managed ingress; a rule scoped only to staticIp can leave the backend unhealthy.

    AGW["Application Gateway<br/>HTTPS to app FQDN"]
    ENTRY["Internal environment entry<br/>resolved address = staticIp"]
    BACKEND["Managed ingress backend path<br/>in the Container Apps subnet"]
    RULE{"NSG rule destination<br/>and ports?"}
    ALLOW["ALLOW<br/>Destination = Container Apps subnet<br/>ports 443 and 31443"]
    WRONG["MISMATCH<br/>Destination = staticIp only"]
    INGRESS["Managed ingress proxy<br/>route to active revision"]
    UNHEALTHY["SYMPTOM<br/>Application Gateway backend unhealthy"]

    AGW ==>|"1  HTTPS packet"| ENTRY
    ENTRY ==>|"2  Internal load balancing"| BACKEND
    BACKEND -->|"3  Evaluate inbound flow"| RULE
    RULE -->|"Documented workload-profile rule"| ALLOW
    RULE -.->|"Incorrect staticIp-only rule"| WRONG
    ALLOW ==>|"4  Accepted request"| INGRESS
    WRONG -.-> UNHEALTHY

    LEGEND["Arrow key<br/>thick = packet or request transport<br/>solid = NSG evaluation result<br/>dotted = misconfiguration and symptom"]
```

*Figure: The decision preserves the packet path and the policy result as separate semantics. It states the documented subnet destination without depicting an undocumented managed NIC or proxy fleet.*

The `Destination = staticIp only` branch is the classic misconfiguration. It appears plausible because DNS returns `staticIp`, but it does not match the workload-profile destination documented in the Container Apps NSG table. Use the Container Apps subnet as the rule destination and validate the resulting flow rather than inferring hidden platform implementation details.

!!! warning "Consumption-only environments follow a different rule"
    In the legacy **Consumption-only** environment type, the Microsoft Learn NSG table lists both `Your container app's subnet` and `The staticIP value of your Container Apps environment` as valid Destination values for the client-IP HTTP/HTTPS rule. In a **workload profiles** environment, only `Your container app's subnet` appears in the Destination column. If you are migrating from Consumption-only to workload profiles and reusing your old NSG, expect this exact rule to break.

## Required inbound NSG rules on the Container Apps subnet (workload profiles)

The Microsoft Learn [firewall-integration reference for workload profiles](https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration?tabs=workload-profiles) documents the following inbound rules. Every rule below uses **the container app's subnet** as the Destination.

| Rule | Protocol | Source | Source ports | Destination | Destination ports | Why |
|---|---|---|---|---|---|---|
| Client HTTPS | TCP | Client subnet or CIDR (for AppGW: the Application Gateway subnet) | `*` | Container app's subnet | `443`, `31443` | `31443` is the port on which the Container Apps environment edge proxy responds to HTTPS traffic behind the internal load balancer. |
| Client HTTP | TCP | Client subnet or CIDR | `*` | Container app's subnet | `80`, `31080` | `31080` is the port on which the Container Apps environment edge proxy responds to HTTP traffic behind the internal load balancer. |
| Load balancer health probes | TCP | `AzureLoadBalancer` service tag | `*` | Container app's subnet | `30000-32767` | Allows Azure Load Balancer to probe backend pools. Azure NSGs include the default `AllowAzureLoadBalancerInBound` rule at priority 65001, but a custom deny rule with a numerically lower priority can take precedence; place any explicit allow ahead of the deny rule it must override. |
| TCP apps (only if used) | TCP | Client subnet or CIDR | `*` | Container app's subnet | Exposed TCP ports and `30000-32767` | Applies only to TCP ingress apps. Not required for HTTP-only workloads. |

The workload-profile NSG table in Microsoft Learn explicitly notes: "You need the full range when creating your container apps as a port within the range is dynamically allocated. After you create the container apps, the required ports are two immutable, static values, and you can update your NSG rules." In practice, most operators keep the `30000-32767` range in place because the two static values are not documented as stable across every deployment path.

## Recommended AppGW-facing inbound NSG rule (concrete example)

The following example scopes Source to the Application Gateway subnet and Destination to the Container Apps subnet CIDR. Replace the CIDRs with your actual subnet ranges.

```bash
# Example values — replace with your subnets.
APPGW_SUBNET_CIDR="10.0.1.0/24"
ACA_SUBNET_CIDR="10.0.2.0/23"

az network nsg rule create \
  --name "allow-appgw-to-aca-https" \
  --nsg-name "$ACA_SUBNET_NSG_NAME" \
  --resource-group "$RG" \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "$APPGW_SUBNET_CIDR" \
  --source-port-ranges "*" \
  --destination-address-prefixes "$ACA_SUBNET_CIDR" \
  --destination-port-ranges "443" "31443"

az network nsg rule create \
  --name "allow-azure-lb-probes-to-aca" \
  --nsg-name "$ACA_SUBNET_NSG_NAME" \
  --resource-group "$RG" \
  --priority 210 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "AzureLoadBalancer" \
  --source-port-ranges "*" \
  --destination-address-prefixes "$ACA_SUBNET_CIDR" \
  --destination-port-ranges "30000-32767"
```

| Command | Why it is used |
|---|---|
| `az network nsg rule create ... allow-appgw-to-aca-https` | Allows HTTPS from the Application Gateway subnet to reach the edge proxy on the two ports the Container Apps platform documents (`443`, `31443`). |
| `az network nsg rule create ... allow-azure-lb-probes-to-aca` | Allows Azure Load Balancer probes to the documented Container Apps subnet port range. Priority `210` is evaluated before custom deny rules that use numerically higher priority values. |

If you need the HTTP path as well (for redirects or health checks), add a third rule using `80` and `31080`. Do not use `staticIp` as the Destination.

## Private DNS Zone and Application Gateway backend

Application Gateway needs a way to resolve the container app FQDN to `staticIp`. The Microsoft Learn walkthrough uses a Private DNS Zone whose name matches the environment `defaultDomain`:

```bash
# Retrieve the two values you need.
STATIC_IP=$(az containerapp env show \
  --name "$ACA_ENV_NAME" \
  --resource-group "$RG" \
  --query "properties.staticIp" \
  --output tsv)

DEFAULT_DOMAIN=$(az containerapp env show \
  --name "$ACA_ENV_NAME" \
  --resource-group "$RG" \
  --query "properties.defaultDomain" \
  --output tsv)

# Create the Private DNS Zone using the environment default domain as the zone name.
az network private-dns zone create \
  --resource-group "$RG" \
  --name "$DEFAULT_DOMAIN"

# Wildcard A record so every app under the environment resolves to staticIp.
az network private-dns record-set a add-record \
  --resource-group "$RG" \
  --zone-name "$DEFAULT_DOMAIN" \
  --record-set-name "*" \
  --ipv4-address "$STATIC_IP"

# Apex A record for the environment default domain itself.
az network private-dns record-set a add-record \
  --resource-group "$RG" \
  --zone-name "$DEFAULT_DOMAIN" \
  --record-set-name "@" \
  --ipv4-address "$STATIC_IP"

# Link the zone to the VNet so Application Gateway's DNS resolves the record.
az network private-dns link vnet create \
  --resource-group "$RG" \
  --zone-name "$DEFAULT_DOMAIN" \
  --name "link-appgw-vnet" \
  --virtual-network "$VNET_ID" \
  --registration-enabled false
```

| Command | Why it is used |
|---|---|
| `az containerapp env show ... --query "properties.staticIp"` | Reads the environment ingress IP that the Private DNS Zone A record must point to. |
| `az containerapp env show ... --query "properties.defaultDomain"` | Reads the environment default domain, which is the required Private DNS Zone name. |
| `az network private-dns zone create ...` | Creates the Private DNS Zone using the environment default domain as the zone name. |
| `az network private-dns record-set a add-record ... --record-set-name "*"` | Wildcard record so every container app FQDN under the environment resolves to `staticIp`. |
| `az network private-dns record-set a add-record ... --record-set-name "@"` | Apex record for the environment default domain itself. |
| `az network private-dns link vnet create ...` | Links the zone to the VNet so Application Gateway resolves the record through Azure-provided DNS. |

## Application Gateway backend configuration essentials

Two backend-side settings frequently interact with the NSG behavior above and belong on the same review checklist:

| Setting | Recommended value | Why |
|---|---|---|
| Backend pool target | The container app FQDN (for example, `myapp.<default-domain>`) | Application Gateway resolves this to `staticIp` through the linked Private DNS Zone. Do not target `staticIp` directly with `IP address` target type — you lose the ability to use HTTPS SNI and host-header handling cleanly. |
| Backend protocol | HTTPS | Terminating TLS at Application Gateway and re-encrypting to the edge proxy on `443` keeps end-to-end encryption. |
| Backend port | `443` (or `80` for HTTP-only tests) | Application Gateway targets `443` on the app FQDN. The workload-profile NSG table requires both `443` and `31443` for HTTPS traffic through the internal load balancer path; the gateway does not target `31443` directly. |
| Override with new host name | `Pick host name from backend target` | The container app FQDN is required for the edge proxy to route to the correct revision. Without this, the edge proxy returns `404`. |
| Health probe protocol / path | HTTPS to a path that the app actually returns 2xx or 3xx on | If the app returns 404 on `/`, configure a probe path such as `/healthz`. Application Gateway defaults to marking a backend `Unhealthy` on any non-matching status. |
| Use custom probe | Recommended `Yes` for anything beyond a trivial demo | The default probe pings `/` and requires 200-399. Most real apps need an explicit custom probe. |

## Private Link path (alternative)

The Microsoft Learn walkthrough also documents an [Application Gateway Private Link](https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway) option. Treat it as a separate Application Gateway frontend/private-link configuration, not as evidence for a different Container Apps NSG destination. For a workload-profile Container Apps environment, retain the documented inbound rule destination: **the container app's subnet**, not `staticIp`.

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| NSG inbound rule uses Destination = `staticIp` only | Application Gateway backend shows `Unhealthy`, `curl` from Application Gateway subnet times out | Change Destination to the container app's subnet CIDR; keep Source scoped to the Application Gateway subnet. See the [playbook](../../troubleshooting/playbooks/ingress-and-networking/appgw-to-internal-aca-nsg-destination.md). |
| NSG allows `443` but not `31443` | Application Gateway health probes and client traffic can fail because the documented workload-profile rule requires both HTTPS ports (`443`, `31443`), or both HTTP ports (`80`, `31080`). | Add `31443` (and `31080` for HTTP) to the Destination ports list. |
| Restrictive custom NSG shadows the default `AllowAzureLoadBalancerInBound` rule (priority 65001) with higher-priority Deny rules, or the environment ILB probe path is otherwise blocked | Every backend is marked `Unhealthy` regardless of application state | Add an explicit Allow rule with Source = `AzureLoadBalancer`, Destination = the container app's subnet CIDR, Destination ports = `30000-32767`, at a priority lower than any custom Deny rule (typically 200-500). |
| Application Gateway backend targets an IP address rather than the FQDN | Edge proxy returns `404` (`Container App does not exist`) because the SNI / Host header does not match a bound app | Target the container app FQDN in the backend pool and enable `Pick host name from backend target`. |
| Private DNS Zone not linked to the VNet Application Gateway is in | Application Gateway resolves the FQDN to a public IP, or fails to resolve at all | Create a VNet link on the Private DNS Zone for the VNet that hosts Application Gateway. |
| Reusing a Consumption-only NSG on a new workload-profiles environment | Rules that named `staticIp` as Destination silently stop matching traffic | Rewrite the client-IP rules to use the container app's subnet as Destination; keep `staticIp` only in the Private DNS A record for the environment default domain (the Application Gateway backend pool should target the container app FQDN, and the backend HTTP setting or probe host header should be the FQDN — not `staticIp`). |

## See Also

- [Ingress in Azure Container Apps](ingress.md)
- [VNet Integration](vnet-integration.md)
- [Private Endpoints](private-endpoints.md)
- [Egress Control](egress-control.md)
- [Environment Networking and CIDR](../environments/networking-and-cidr.md)
- [On-Premises DNS to Container Apps Internal Environment via Custom Domain](../../operations/deployment/internal-ingress-on-prem-dns.md)
- [AppGW to Internal Container Apps: NSG Destination Pinned to staticIp Fails (Playbook)](../../troubleshooting/playbooks/ingress-and-networking/appgw-to-internal-aca-nsg-destination.md)
- [Networking Best Practices](../../best-practices/networking.md)

## Sources

- [Protect Azure Container Apps with Application Gateway and Web Application Firewall (WAF) (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway)
- [Azure Application Gateway Backend Settings configuration (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/application-gateway/configuration-http-settings)
- [Ingress in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Securing a Virtual Network in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration?tabs=workload-profiles)
- [Provide an internal environment for Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom-internal)
- [Networking in Azure Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Network security groups (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [What is Azure Application Gateway? (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/application-gateway/overview)
