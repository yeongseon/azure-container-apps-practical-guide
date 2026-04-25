---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/vnet-custom
        - https://learn.microsoft.com/azure/container-apps/networking
content_validation:
  status: verified
  last_reviewed: "2026-04-12"
  reviewer: ai-agent
  core_claims:
    - claim: "A Container Apps environment can use either the default Azure network or an existing virtual network, and the network type cannot be changed after creation."
      source: "https://learn.microsoft.com/azure/container-apps/networking"
      verified: true
    - claim: "A subnet provided for an existing virtual network deployment must be dedicated exclusively to the Container Apps environment."
      source: "https://learn.microsoft.com/azure/container-apps/networking"
      verified: true
    - claim: "Using an existing virtual network enables Network Security Groups, Azure Firewall integration, outbound traffic control, and access to resources behind private endpoints."
      source: "https://learn.microsoft.com/azure/container-apps/networking"
      verified: true
    - claim: "An internal Container Apps environment does not use a public static IP and uses internal IP addresses from the custom virtual network."
      source: "https://learn.microsoft.com/azure/container-apps/vnet-custom"
      verified: true
    - claim: "Container apps deployed to the same environment are deployed in the same virtual network and write logs to the same Log Analytics workspace."
      source: "https://learn.microsoft.com/azure/container-apps/vnet-custom"
      verified: true
---

# VNet Integration

Deploy Container Apps in a custom virtual network for network isolation.

## Overview

Container Apps can be deployed into a custom VNet to:
- Isolate traffic from the public internet
- Connect to private resources (databases, storage)
- Control ingress/egress with NSG rules

!!! warning "Subnet sizing is not optional"
    The Container Apps infrastructure subnet must be at least /23.
    Smaller subnets commonly fail at environment provisioning time.

## Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    subgraph VNet ["Virtual Network (10.0.0.0/16)"]
        subgraph CASubnet ["Container Apps Subnet (10.0.0.0/23)"]
            subgraph Environment ["Container Apps Environment"]
                CA1[App 1]
                CA2[App 2]
                INV[Ingress: Envoy]
            end
        end

        subgraph PESubnet ["Private Endpoint Subnet (10.0.2.0/24)"]
            PE[Private Endpoint]
        end
    end

    subgraph Internet [Public Internet]
        U[User]
    end

    U -- External Ingress --> INV
    INV -- Routing --> CA1
    CA1 -- VNet-Local Call --> CA2
    CA1 -- Private Link --> PE
```

## Prerequisites

- Azure subscription with VNet creation permissions
- Existing VNet or create new one

## Create VNet with Subnets

Container Apps requires a dedicated subnet with minimum /23 CIDR block.

### Using Azure CLI:
```bash
# Create VNet
az network vnet create \
  --name vnet-containerapp \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --address-prefix 10.0.0.0/16

# Create subnet for Container Apps (minimum /23)
az network vnet subnet create \
  --name snet-containerapp \
  --vnet-name vnet-containerapp \
  --resource-group $RESOURCE_GROUP \
  --address-prefix 10.0.0.0/23
```

### Using Bicep:
```bicep
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-containerapp'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'snet-containerapp'
        properties: {
          addressPrefix: '10.0.0.0/23'
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
- [Egress Control](egress-control.md)
- [Service-to-Service Communication](service-to-service.md)
- [Azure SQL](../../language-guides/python/recipes/azure-sql.md)

## Sources
- [Custom virtual networks in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/vnet-custom)
- [Networking architecture in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/networking)
