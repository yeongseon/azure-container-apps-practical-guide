# Recipes: Integration Patterns for Azure Container Apps (Python)

Use these practical recipes to implement common production patterns for Python apps running on Azure Container Apps.

## Prerequisites

- Azure CLI 2.57+ with the Container Apps extension
- Existing Azure Container Apps environment (`$ENVIRONMENT_NAME`) and app (`$APP_NAME`)
- Resource group (`$RG`) and region (`$LOCATION`) variables set

```bash
az extension add --name containerapp --upgrade
az login
```

## Recipe Catalog

### Container & Runtime

- [Custom Container](custom-container.md): Build optimized Python images with non-root runtime and probe-ready configuration.
- [Native Dependencies](native-dependencies.md): Package and run Python dependencies that require system libraries or compilation.

### Deployment & Revisions

- [Container Registry](container-registry.md): Pull private images from Azure Container Registry with managed identity.
- [Revision Validation](revision-validation.md): Validate new revisions at 0% traffic and promote safely with canary routing.

### Data & Storage

- [Cosmos DB](cosmosdb.md): Connect to Azure Cosmos DB with managed identity and RBAC.
- [Azure SQL](azure-sql.md): Access Azure SQL using Microsoft Entra authentication.
- [Redis](redis.md): Integrate Azure Cache for Redis from Python apps.
- [Storage](storage.md): Use Blob SDK patterns and Azure Files mounts.
- [Bring Your Own Storage](bring-your-own-storage.md): Mount Azure Files shares as persistent volumes.

### Security & Identity

- [Managed Identity](managed-identity.md): Use `DefaultAzureCredential` and RBAC to access Azure services.
- [Key Vault Reference](key-vault-reference.md): Reference Key Vault secrets in Container Apps configuration.
- [Easy Auth](easy-auth.md): Enable built-in authentication and consume identity claims in Flask.

### Integration

- [Dapr Integration](dapr-integration.md): Add pub/sub, service invocation, and state API patterns.
- [Custom Domains](custom-domains.md): Configure custom domains and certificates for ingress.

## Verification Steps

Confirm your app is healthy before applying any recipe:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "{name:name,provisioningState:properties.provisioningState,runningStatus:properties.runningStatus}" \
  --output json
```

## See Also

- [Python Tutorials](../index.md)
- [Operations](../../../operations/index.md)
- [Platform Architecture](../../../platform/architecture/resource-relationships.md)
