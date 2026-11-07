---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/dotnet/api/overview/azure/storage.blobs-readme
        - https://learn.microsoft.com/en-us/azure/storage/blobs/assign-azure-role-data-access
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
---
# Blob Storage Integration (Managed Identity)

Use this recipe to connect a .NET Container App to Azure Blob Storage with managed identity first and a connection string fallback when you still depend on shared keys.

## Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Passwordless Blob Storage request from an ASP.NET Core container app
    accDescr: A client request reaches the app through managed ingress. DefaultAzureCredential obtains a Storage access token through the app's managed identity, then the Blob SDK sends a data request. Storage separately evaluates the identity's Blob data role assignment.
    CLIENT[Client]
    INGRESS[Managed ingress]
    APP[ASP.NET Core app<br/>Blob SDK]
    ENDPOINT[Container Apps identity endpoint]
    ENTRA[Microsoft Entra ID]
    BLOB[Azure Blob Storage]
    AUTHZ{Blob data role<br/>allows operation?}
    RESULT[Blob operation result]
    DENIED[Authorization failure]

    CLIENT ==>|"HTTPS request"| INGRESS
    INGRESS ==>|"Routed request"| APP
    APP ==>|"Request Storage token"| ENDPOINT
    ENDPOINT ==>|"Token request and response"| ENTRA
    ENDPOINT ==>|"Return access token"| APP
    APP ==>|"Blob request + token"| BLOB
    BLOB -->|"Evaluate Blob data role"| AUTHZ
    AUTHZ -->|"Allowed"| RESULT
    AUTHZ -.->|"Denied"| DENIED
```

*Figure: Token acquisition, Blob transport, and Storage data-plane authorization are separate steps. This SDK-access recipe does not depict an Azure Files or BlobFuse volume mount.*

## Prerequisites

- Existing Container App: `$APP_NAME` in `$RG`
- Existing storage account and blob container
- Azure CLI with the Container Apps extension

```bash
az extension add --name containerapp --upgrade
```

| Command | Why it is used |
|---|---|
| `az extension add ...` | Installs or updates the Container Apps Azure CLI extension. |

## Step 1: Enable managed identity on the Container App

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
```

| Command | Why it is used |
|---|---|
| `az containerapp identity assign ...` | Assigns or inspects managed identity configuration for the Container App. |

## Step 2: Grant Blob data access

```bash
export STORAGE_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RG" \
  --query "id" \
  --output tsv)

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_ID"
```

| Command | Why it is used |
|---|---|
| `az storage account ...` | Creates or inspects Storage resources used by volume, state, or sample app scenarios. |

## Step 3: Configure non-secret settings

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars STORAGE_ACCOUNT_URL="https://$STORAGE_ACCOUNT.blob.core.windows.net" STORAGE_CONTAINER="$STORAGE_CONTAINER"
```

| Command | Why it is used |
|---|---|
| `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

## Step 4: .NET code (managed identity)

Add dependencies:

```bash
dotnet add package Azure.Storage.Blobs
dotnet add package Azure.Identity
```

Upload and download a blob with `DefaultAzureCredential`:

```csharp
using Azure.Identity;
using Azure.Storage.Blobs;

static BlobServiceClient CreateBlobServiceClient()
{
    var connectionString = Environment.GetEnvironmentVariable("AZURE_STORAGE_CONNECTION_STRING");
    if (!string.IsNullOrWhiteSpace(connectionString))
    {
        return new BlobServiceClient(connectionString);
    }

    var accountUrl = Environment.GetEnvironmentVariable("STORAGE_ACCOUNT_URL")!;
    return new BlobServiceClient(new Uri(accountUrl), new DefaultAzureCredential());
}

var serviceClient = CreateBlobServiceClient();
var container = serviceClient.GetBlobContainerClient(Environment.GetEnvironmentVariable("STORAGE_CONTAINER"));
var blob = container.GetBlobClient("hello.txt");

await blob.UploadAsync(BinaryData.FromString("hello from aca"), overwrite: true);
var content = await blob.DownloadContentAsync();
Console.WriteLine(content.Value.Content.ToString());
```

## Step 5: Connection string fallback

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets storage-connection-string="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT;AccountKey=<storage-account-key>;EndpointSuffix=core.windows.net"

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars AZURE_STORAGE_CONNECTION_STRING=secretref:storage-connection-string STORAGE_CONTAINER="$STORAGE_CONTAINER"
```

| Command | Why it is used |
|---|---|
| `az containerapp secret set ...` | Manages Container Apps secrets without exposing secret values in plain configuration. |

## Verification

1. Confirm RBAC assignment exists.
2. Confirm the uploaded blob exists with `az storage blob list --auth-mode login`.
3. Check app logs for successful upload and download operations.

## See Also

- [Managed Identity](managed-identity.md)
- [Key Vault Reference](key-vault-reference.md)
- [.NET Tutorials](../index.md)

## Sources

- [Azure Storage Blob client library for .NET](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/storage.blobs-readme)
- [Assign an Azure role for Blob data access](https://learn.microsoft.com/en-us/azure/storage/blobs/assign-azure-role-data-access)
- [Managed identities in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
