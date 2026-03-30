# Private Endpoints

Connect Container Apps to Azure services using Private Endpoints.

## Overview

Private Endpoints provide:
- Private IP addresses for Azure services
- Traffic stays on Microsoft backbone
- No public internet exposure

## Supported Services

- Azure SQL Database
- Azure Storage (Blob, Queue, Table, File)
- Azure Key Vault
- Azure Cosmos DB
- Azure Service Bus
- Azure Redis Cache

## Architecture

```
Container App (VNet) --> Private Endpoint --> Azure SQL (Private IP)
                    \-> Private Endpoint --> Key Vault (Private IP)
```

## Create Private Endpoint for Azure SQL

### Bicep:
```bicep
resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: 'sql-${baseName}'
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Disabled'  // Disable public access
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'pe-sql-${baseName}'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id
    }
    privateLinkServiceConnections: [
      {
        name: 'sql-connection'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: ['sqlServer']
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.database.windows.net'
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'vnet-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}
```

## Configure DNS Resolution

Private DNS zones are required for name resolution:

| Service | Private DNS Zone |
|---------|------------------|
| Azure SQL | privatelink.database.windows.net |
| Blob Storage | privatelink.blob.core.windows.net |
| Key Vault | privatelink.vaultcore.azure.net |
| Cosmos DB | privatelink.documents.azure.com |

## Use in Container App

```python
import os
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

# Key Vault URL uses standard DNS (resolves to private IP via Private DNS Zone)
vault_url = os.environ['KEY_VAULT_URL']  # https://kv-myapp.vault.azure.net
credential = DefaultAzureCredential()
client = SecretClient(vault_url=vault_url, credential=credential)

secret = client.get_secret("my-secret")
```

## Verify Connectivity

From container logs or console:
```bash
# Check DNS resolution
nslookup myserver.database.windows.net
# Should return private IP (10.x.x.x)

# Test connectivity
nc -zv myserver.database.windows.net 1433
```
