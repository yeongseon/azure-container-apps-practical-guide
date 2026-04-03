# Recipes: Integration Patterns for Azure Container Apps

Use these recipes to add common production integrations to Python apps running on Azure Container Apps.

## Prerequisites

- Azure CLI 2.57+ with Container Apps extension
- An existing Azure Container Apps environment and app
- A system-assigned or user-assigned managed identity for your app

```bash
az extension add --name containerapp --upgrade
az login
```

## Recipe Catalog

### Data and Secrets

- [Cosmos DB](./cosmosdb.md): Use Azure Cosmos DB (NoSQL) with managed identity and RBAC.
- [Azure SQL](./azure-sql.md): Connect to Azure SQL Database using Microsoft Entra tokens (passwordless).
- [Redis Cache](./redis.md): Access Azure Cache for Redis with managed identity and Entra authentication.
- [Key Vault](./key-vault.md): Load secrets securely from Key Vault using managed identity.
- [Blob Storage and File Mounts](./storage.md): Read/write blobs with managed identity and mount Azure Files volumes.

### Platform and Networking

- [Managed Identity](./managed-identity.md): Assign identities and RBAC roles.
- [Easy Auth](./easy-auth.md): Add built-in authentication without application-side OAuth flow.
- [Dapr Integration](./dapr-integration.md): Use Dapr sidecars for pub/sub, state, and service invocation.
- [VNet Integration](./networking-vnet.md): Run apps in private networks.
- [Private Endpoints](./networking-private-endpoint.md): Reach PaaS services privately.
- [Egress Control](./networking-egress.md): Route outbound traffic with firewall and NAT patterns.
- [Service-to-Service Communication](./networking-service-to-service.md): Internal DNS and Dapr invocation between apps.

## Verification Steps

Confirm your app is healthy before applying a recipe:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "{name:name,provisioningState:properties.provisioningState,runningStatus:properties.runningStatus}" \
  --output json
```

## See Also
- [Tutorial](../tutorial/index.md)
- [Operations Guide](../operations/index.md)
- [Managed Identity Recipe](./managed-identity.md)
