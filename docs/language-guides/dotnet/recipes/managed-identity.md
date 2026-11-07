---
content_sources:
  diagrams:
    - id: use-defaultazurecredential-and-asp-net-core-dependency
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
        - https://learn.microsoft.com/en-us/dotnet/api/overview/azure/identity-readme
---
# Recipe: Managed Identity in .NET Apps on Azure Container Apps

Use `DefaultAzureCredential` and ASP.NET Core dependency injection to access Azure resources without connection secrets.

<!-- diagram-id: use-defaultazurecredential-and-asp-net-core-dependency -->
```mermaid
flowchart TD
    accTitle: DefaultAzureCredential access from ASP.NET Core
    accDescr: ASP.NET Core uses DefaultAzureCredential to request a resource-scoped token from the local Container Apps identity endpoint. Microsoft Entra ID issues the token, and Blob Storage independently evaluates the identity's Blob data role before allowing or denying the operation.
    CLIENT[Client]
    APP[ASP.NET Core app<br/>BlobServiceClient]
    CREDENTIAL[DefaultAzureCredential]
    ENDPOINT[Container Apps identity endpoint]
    IDENTITY[System- or user-assigned identity]
    ENTRA[Microsoft Entra ID]
    BLOB[Azure Blob Storage]
    AUTHZ[Blob authorization result]
    RESULT[Blob list result]
    DENIED[Authorization failure]

    CLIENT ==>|"Application request"| APP
    APP ==>|"Acquire resource token"| CREDENTIAL
    CREDENTIAL ==>|"Local token request"| ENDPOINT
    IDENTITY -.->|"Selected identity"| ENDPOINT
    ENDPOINT ==>|"Token request"| ENTRA
    ENTRA ==>|"Access token response"| ENDPOINT
    ENDPOINT ==>|"Return token"| CREDENTIAL
    APP ==>|"Blob request + token"| BLOB
    BLOB -->|"Evaluate data role"| AUTHZ
    AUTHZ -->|"Allowed"| RESULT
    AUTHZ -.->|"Denied"| DENIED
    RESULT ==>|"Blob list response"| APP
    DENIED -.->|"Authorization error"| APP
    APP ==>|"Application response"| CLIENT
```

*Figure: Managed identity removes application credentials; it does not grant data access by itself. Blob Storage still requires a matching data-plane role assignment at the intended scope.*

## Prerequisites

- Existing Container App (`$APP_NAME`) in resource group (`$RG`)
- Storage account (`$STORAGE_ACCOUNT`) and container (`$STORAGE_CONTAINER`)
- Azure CLI with Container Apps extension

## Enable managed identity and RBAC

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
  --role "Storage Blob Data Reader" \
  --scope "$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RG" --query id --output tsv)"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp identity assign` | Assigns the managed identity used by this integration. |
| `--name` | Selects the app, job, deployment, registry, identity, or service used by this command. |
| `--resource-group` | Selects the resource group containing the resources in this step. |
| `--system-assigned` | Enables the app's system-assigned managed identity. |
| `az containerapp show` | Reads the app property needed by this procedure. |
| `--output` | Returns the queried value as plain text or displays the verification list as a table. |
| `--query` | Extracts the exact resource property consumed by the next step. |
| `az role assignment create` | Grants the selected managed identity the role required by this step. |
| `--assignee-object-id` | Targets the managed identity principal without a Microsoft Graph lookup. |
| `--assignee-principal-type` | Declares the managed identity as a service principal for role assignment. |
| `--role` | Selects the data-plane or registry role required by this integration. |
| `--scope` | Sets the Azure or service data-plane scope of this role assignment. |

## ASP.NET Core 8 DI pattern

```csharp
using Azure.Identity;
using Azure.Storage.Blobs;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton(_ =>
{
    var accountUrl = builder.Configuration["Storage:AccountUrl"]!;
    return new BlobServiceClient(new Uri(accountUrl), new DefaultAzureCredential());
});

var app = builder.Build();

app.MapGet("/blobs", async (BlobServiceClient blobService, IConfiguration config) =>
{
    var containerName = config["Storage:Container"] ?? "app-data";
    var container = blobService.GetBlobContainerClient(containerName);
    var names = new List<string>();
    await foreach (var blob in container.GetBlobsAsync())
    {
        names.Add(blob.Name);
    }
    return Results.Ok(new { blobs = names });
});

app.Run();
```

## Advanced Topics

- Use separate user-assigned identities for read-only and write paths.
- Add readiness checks that validate token acquisition and service authorization.
- Use policy-based authorization for resource-specific routes.

## See Also

- [Key Vault Reference](key-vault-reference.md)
- [Easy Auth](easy-auth.md)
- [Managed Identity Platform Guide](../../../platform/identity-and-secrets/managed-identity.md)

## Sources

- [Managed identities in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
- [Azure SDK for .NET identity](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/identity-readme)
