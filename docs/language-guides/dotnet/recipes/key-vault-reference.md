---
content_sources:
  diagrams:
    - id: use-key-vault-references-and-azure
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
        - https://learn.microsoft.com/en-us/aspnet/core/security/key-vault-configuration
        - https://learn.microsoft.com/en-us/dotnet/api/overview/azure/security.keyvault.secrets-readme
---
# Recipe: Key Vault Reference in .NET Apps on Azure Container Apps

Use Key Vault references and Azure SDK integration to keep ASP.NET Core secrets externalized and auditable.

<!-- diagram-id: use-key-vault-references-and-azure -->
```mermaid
flowchart TD
    accTitle: Key Vault reference and direct SDK access are separate secret paths
    accDescr: For a Container Apps Key Vault reference, the platform uses the selected managed identity to resolve a vault secret into a Container Apps secret, which the revision consumes through secretRef. For direct SDK access, ASP.NET Core obtains a token and calls Key Vault at runtime.
    IDENTITY[Managed identity]
    ENTRA[Microsoft Entra ID]
    KV[Azure Key Vault]
    PLATFORM[Container Apps secret resolver]
    SECRET[Container Apps secret<br/>Key Vault reference]
    REVISION[ASP.NET Core revision<br/>environment secretRef]
    SDK[ASP.NET Core<br/>Key Vault SDK client]

    IDENTITY -.->|"Selected identity"| PLATFORM
    PLATFORM ==>|"Resolve Key Vault secret"| KV
    KV ==>|"Secret value"| PLATFORM
    PLATFORM -->|"Populate reference"| SECRET
    SECRET -.->|"Inject through secretRef"| REVISION
    SDK ==>|"Request access token"| ENTRA
    ENTRA ==>|"Return access token"| SDK
    SDK ==>|"Runtime secret request + token"| KV
    IDENTITY -.->|"Identity used by SDK credential"| SDK
```

*Figure: A Container Apps Key Vault reference is platform-resolved configuration; direct SDK access is an application runtime call. Both require an identity with Key Vault secret permissions, but they have different consumers and rotation behavior.*

## Prerequisites

- Existing Container App (`$APP_NAME`) and resource group (`$RG`)
- Existing Key Vault (`$KEYVAULT_NAME`) with secret `db-password`
- Azure CLI with Container Apps extension

## Configure Key Vault reference in Container Apps

```bash
az containerapp identity assign \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --system-assigned

export PRINCIPAL_ID=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "identity.principalId" \
  --output tsv)

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "$(az keyvault show --name "$KEYVAULT_NAME" --query id --output tsv)"

az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "db-password=keyvaultref:https://$KEYVAULT_NAME.vault.azure.net/secrets/db-password,identityref:system"

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars "DB_PASSWORD=secretref:db-password"
```

| Command | Why it is used |
|---|---|
| `az containerapp identity assign ...` | Assigns or inspects managed identity configuration for the Container App. |

## ASP.NET Core configuration with Key Vault provider

```csharp
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

var builder = WebApplication.CreateBuilder(args);

var vaultUri = new Uri($"https://{builder.Configuration["KeyVaultName"]}.vault.azure.net/");
builder.Configuration.AddAzureKeyVault(vaultUri, new DefaultAzureCredential());

builder.Services.AddSingleton(new SecretClient(vaultUri, new DefaultAzureCredential()));

var app = builder.Build();
app.MapGet("/config-check", (IConfiguration config) =>
    Results.Ok(new { dbPasswordConfigured = !string.IsNullOrEmpty(config["db-password"]) }));
app.Run();
```

## Advanced Topics

- Use one vault per environment and strict RBAC scopes per app identity.
- Prefer revision rollouts after high-risk secret rotations.
- Keep both `secretref` and direct SDK access patterns for operational flexibility.

## See Also

- [Managed Identity](managed-identity.md)
- [Container Registry](container-registry.md)
- [Key Vault Platform Guide](../../../platform/identity-and-secrets/key-vault.md)

## Sources

- [Manage secrets in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [Azure Key Vault configuration provider in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/security/key-vault-configuration)
- [Azure Key Vault Secrets client library for .NET](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/security.keyvault.secrets-readme)
