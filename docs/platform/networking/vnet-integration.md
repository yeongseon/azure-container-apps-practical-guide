---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: self-generated
      justification: ACA custom-VNet topology synthesized from Microsoft Learn and the shared cross-guide private-dependency contract; it distinguishes the dedicated environment subnet relationship, downstream Storage private endpoint, optional inbound environment private endpoint, external Private DNS zones, and transport paths.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint
        - https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: agent
  core_claims:
    - claim: A Container Apps environment can use either the default Azure network or an existing virtual network, and the network type cannot be changed after creation.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: A subnet provided for an existing virtual network deployment must be dedicated exclusively to the Container Apps environment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Using an existing virtual network enables Network Security Groups, Azure Firewall integration, outbound traffic control, and access to resources behind private endpoints.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: An internal Container Apps environment does not use a public static IP and uses internal IP addresses from the custom virtual network.
      source: https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom
      verified: true
    - claim: Container apps deployed to the same environment are deployed in the same virtual network and write logs to the same Log Analytics workspace.
      source: https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom
      verified: true
---
# VNet Integration

Deploy Container Apps in a custom virtual network to use customer-managed network controls and private connectivity.

## Overview

Container Apps can be deployed into a custom VNet to:
- Support private ingress when the environment accessibility and public network access settings are configured for it
- Connect to private resources (databases, storage)
- Control ingress/egress with NSG rules

!!! warning "Subnet sizing depends on the environment type"
    Workload profiles environments and legacy Consumption-only environments have different minimum subnet sizes. Use the current Microsoft Learn sizing table and plan additional capacity for revisions and replicas; do not apply one prefix universally.

## Architecture

**Takeaway:** ACA attaches the managed environment to a dedicated environment subnet—not through an App Service-style integration NIC—while downstream and inbound private endpoints use separate endpoint NICs for different directions and targets.

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Azure Container Apps custom VNet and private endpoint topology
    accDescr: The managed Container Apps environment is a logical boundary associated with a dedicated environment subnet. A replica reaches a Storage account through a separate downstream private endpoint subnet after private DNS resolution. An optional inbound private endpoint to the environment occupies another endpoint subnet and requires a workload profiles environment with public network access disabled.

    PRIVATE_CLIENT["1  Private client"]
    ACA_ZONE["2  DNS lookup<br/>environment name resolves to PE IP<br/>privatelink.region.azurecontainerapps.io"]

    subgraph ENV["Managed Container Apps environment — logical boundary"]
        INGRESS["4  Managed ingress proxy"]
        REV_ACTIVE["5  Active revision"]
        REPLICAS["6  Revision replica"]
    end

    subgraph VNET["Customer-managed virtual network"]
        subgraph INBOUND_SUBNET["Optional inbound endpoint subnet"]
            ACA_PE["3  Container Apps environment PE NIC<br/>workload profiles environment<br/>public network access disabled"]
        end
        ENV_SUBNET["Dedicated environment subnet<br/>ACA environment relationship<br/>not an app integration NIC"]
        TARGET_SUBNET["8  Target-side PE subnet<br/>Storage private endpoint NIC"]
    end

    STORAGE_ZONE["7  DNS lookup<br/>Storage name resolves to PE IP<br/>privatelink.blob.core.windows.net"]
    STORAGE["9  Storage account<br/>outside customer VNet"]

    ENV_SUBNET -.-> ENV
    PRIVATE_CLIENT -.->|"Resolve environment name"| ACA_ZONE
    ACA_ZONE -.->|"Return environment PE IP"| ACA_PE
    PRIVATE_CLIENT ==>|"Inbound HTTPS"| ACA_PE
    ACA_PE ==>|"Private Link to environment"| INGRESS
    INGRESS ==>|"Route request"| REV_ACTIVE
    REV_ACTIVE ==>|"Continue request to replica"| REPLICAS

    REPLICAS -.->|"Resolve Storage name"| STORAGE_ZONE
    STORAGE_ZONE -.->|"Return Storage PE IP"| TARGET_SUBNET
    REPLICAS ==>|"Outbound HTTPS"| TARGET_SUBNET
    TARGET_SUBNET ==>|"Private Link"| STORAGE

    LEGEND["Arrow key<br/>thick = HTTPS/data transport<br/>dotted = DNS, requirement, or logical relationship"]
```

*Figure: The downstream Storage private endpoint and optional inbound environment private endpoint are not interchangeable. Neither endpoint represents app-level internal ingress, and the managed environment is not drawn as a customer-owned subnet workload.*

## Portal view: non-integrated baseline for the Bicep example

This screenshot is used here as a visual contrast baseline for the Bicep example in [Deploy Container Apps Environment with VNet](#deploy-container-apps-environment-with-vnet).

![Networking blade showing "General" selected; "Public Network Access" with "Enable: Allows incoming traffic from the public internet." selected; "Virtual network" section reading "This environment isn't integrated"; tab strip lists "General", "Ingress settings", "Request Routing", "Encryption", "Custom DNS Suffix"](../../assets/platform/environments/03-networking.png)

[Observed] The `Public Network Access` section has `Enable: Allows incoming traffic from the public internet.` selected. The `Virtual network` section reads `This environment isn't integrated`. The tab strip lists `General`, `Ingress settings`, `Request Routing`, `Encryption`, `Custom DNS Suffix`. No subnet resource ID or CIDR value is visible in the shown content.

[Inferred] The visible `This environment isn't integrated` text is consistent with the Bicep example in [Deploy Container Apps Environment with VNet](#deploy-container-apps-environment-with-vnet) introducing networking properties that are not shown on this blade. The absence of any visible subnet resource ID value appears to map to the `infrastructureSubnetId` property in that same example.

[Not Proven] This image does not show the `infrastructureSubnetId` property from [Deploy Container Apps Environment with VNet](#deploy-container-apps-environment-with-vnet). It does not show the `internal: true` vs `internal: false` choice from [Internal vs External Ingress](#internal-vs-external-ingress). It does not show the environment-type-specific subnet sizing and delegation requirements from [Overview](#overview). It does not show the NSG rules from [Network Security Groups](#network-security-groups). It does not show the private endpoint connectivity discussed in [Access Private Resources](#access-private-resources).

## Prerequisites

- Azure subscription with VNet creation permissions
- Existing VNet or create new one

## Create VNet with Subnets

This example explicitly targets a **workload profiles environment**. It uses a dedicated subnet, delegates that subnet to `Microsoft.App/environments`, and accepts the prefix as a placeholder so you can size it for expected scale. The documented minimum is `/27`; legacy Consumption-only environments instead require `/23` or larger and must not delegate the subnet.

### Using Azure CLI:
```bash
export VNET_ADDRESS_PREFIX="<virtual-network-cidr>"
export CONTAINER_APPS_SUBNET_PREFIX="<workload-profiles-subnet-cidr>"

# Create VNet
az network vnet create \
  --name vnet-containerapp \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --address-prefix $VNET_ADDRESS_PREFIX

# Create a delegated subnet for a workload profiles environment
az network vnet subnet create \
  --name snet-containerapp \
  --vnet-name vnet-containerapp \
  --resource-group $RESOURCE_GROUP \
  --address-prefixes $CONTAINER_APPS_SUBNET_PREFIX \
  --delegations Microsoft.App/environments
```

| Command | Why it is used |
|---|---|
| `export VNET_ADDRESS_PREFIX="<virtual-network-cidr>"` | Sets the VNet address-space placeholder for this example. |
| `export CONTAINER_APPS_SUBNET_PREFIX="<workload-profiles-subnet-cidr>"` | Sets a workload-profiles subnet placeholder; choose `/27` or larger and size for expected scale. |
| `az network vnet create ...` | Creates or inspects networking resources such as VNets, DNS zones, routes, or private endpoints. |
| `--address-prefix` | Applies the VNet address-space placeholder. |
| `az network vnet subnet create` | Creates the dedicated environment subnet. |
| `--address-prefixes` | Uses the workload-specific prefix supplied in `$CONTAINER_APPS_SUBNET_PREFIX`; choose `/27` or larger for workload profiles and size for expected scale. |
| `--delegations` | Delegates this workload-profiles subnet to `Microsoft.App/environments`. Do not use this delegation for a legacy Consumption-only environment. |

### Using Bicep:
```bicep
@description('Virtual network address prefix')
param vnetAddressPrefix string

@description('Dedicated workload profiles environment subnet prefix (/27 or larger)')
param containerAppsSubnetPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-containerapp'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-containerapp'
        properties: {
          addressPrefix: containerAppsSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}
```

## Deploy Container Apps Environment with VNet

```bicep
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: 'cae-${baseName}'
  location: location
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: vnet.properties.subnets[0].id
      internal: false  // true for internal-only access
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}
```

## Internal vs External Ingress

For the full ingress model, including the app-level `external` property, transport selection, TCP rules, headers, and request handling behavior, see [Ingress in Azure Container Apps](ingress.md). This section focuses on the environment-level VNet posture.

| Mode | Description | Use Case |
|------|-------------|----------|
| `internal: false` | Public IP + VNet | Public APIs with VNet backend access |
| `internal: true` | Private IP only | Internal microservices, no public access |

## Access Private Resources

Once in a VNet, Container Apps can access:
- Private Endpoints (Azure SQL, Storage, Key Vault)
- VNet-peered resources
- On-premises via VPN/ExpressRoute

!!! tip "Treat DNS as part of networking design"
    Private endpoint connectivity depends on DNS zone linkage and name resolution.
    Validate DNS records before investigating application code.

### Example: Connect to Private Azure SQL
```python
import os
import pyodbc

# Connection string uses private endpoint DNS
conn_str = os.environ['SQL_CONNECTION_STRING']
# Server=myserver.database.windows.net -> resolves to private IP
```

## Network Security Groups

Apply NSG rules to the Container Apps subnet:

```bicep
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-containerapp'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}
```

## Troubleshooting

### Container can't reach private endpoint
1. Check DNS resolution inside container
2. Verify private endpoint is in same/peered VNet
3. Check NSG rules allow outbound traffic

### Public access not working
1. Verify `internal: false` in environment config
2. Check ingress is enabled on container app
3. Verify FQDN is correctly configured

## See Also
- [Ingress in Azure Container Apps](ingress.md)
- [Private Endpoints](private-endpoints.md)
- [Application Gateway Integration](application-gateway-integration.md)
- [Egress Control](egress-control.md)
- [Service-to-Service Communication](service-to-service.md)
- [Environment Networking and CIDR](../environments/networking-and-cidr.md)
- [Azure SQL](../../language-guides/python/recipes/azure-sql.md)

## Sources
- [Custom virtual networks in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom)
- [Networking architecture in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Use a private endpoint with a Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint)
- [Azure Private Endpoint DNS zone values (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
