---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/javascript/api/overview/azure/storage-blob-readme
        - https://learn.microsoft.com/en-us/azure/storage/blobs/assign-azure-role-data-access
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
---
# Blob Storage Integration (Managed Identity)

Use this recipe to connect a Node.js Container App to Azure Blob Storage with managed identity first and a connection string fallback when you still depend on shared keys.

## Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Passwordless Blob Storage request from an Express container app
    accDescr: A client request reaches Express through managed ingress. DefaultAzureCredential obtains a Storage access token through the app's managed identity, then BlobServiceClient sends a data request. Storage separately evaluates the identity's Blob data role assignment.
    CLIENT[Client]
    INGRESS[Managed ingress]
    APP[Express app<br/>BlobServiceClient]
    ENDPOINT[Container Apps identity endpoint]
    ENTRA[Microsoft Entra ID]
    BLOB[Azure Blob Storage]
    AUTHZ[Blob authorization result]
    RESULT[Blob operation result]
    DENIED[Authorization failure]

    CLIENT ==>|"HTTPS request"| INGRESS
    INGRESS ==>|"Routed request"| APP
    APP ==>|"Request Storage token"| ENDPOINT
    ENDPOINT ==>|"Token request"| ENTRA
    ENTRA ==>|"Access token response"| ENDPOINT
    ENDPOINT ==>|"Return access token"| APP
    APP ==>|"Blob request + token"| BLOB
    BLOB -->|"Evaluate Blob data role"| AUTHZ
    AUTHZ -->|"Allowed"| RESULT
    AUTHZ -.->|"Denied"| DENIED
    RESULT ==>|"Blob response"| APP
    DENIED -.->|"Authorization error"| APP
    APP ==>|"Application response"| INGRESS
    INGRESS ==>|"HTTPS response"| CLIENT
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

Azure Container Apps does **not** inject Blob Storage account URLs automatically.

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars STORAGE_ACCOUNT_URL="https://$STORAGE_ACCOUNT.blob.core.windows.net" STORAGE_CONTAINER="$STORAGE_CONTAINER"
```

| Command | Why it is used |
|---|---|
| `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

## Step 4: Node.js code (managed identity)

Install dependencies:

```bash
npm install @azure/identity @azure/storage-blob
```

Upload and download a blob with `DefaultAzureCredential`:

```javascript
const { DefaultAzureCredential } = require("@azure/identity");
const { BlobServiceClient } = require("@azure/storage-blob");

async function streamToBuffer(readable) {
  const chunks = [];
  for await (const chunk of readable) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

function createBlobServiceClient() {
  if (process.env.AZURE_STORAGE_CONNECTION_STRING) {
    return BlobServiceClient.fromConnectionString(process.env.AZURE_STORAGE_CONNECTION_STRING);
  }

  return new BlobServiceClient(
    process.env.STORAGE_ACCOUNT_URL,
    new DefaultAzureCredential(),
  );
}

async function run() {
  const service = createBlobServiceClient();
  const container = service.getContainerClient(process.env.STORAGE_CONTAINER);
  const blob = container.getBlockBlobClient("hello.txt");

  await blob.uploadData(Buffer.from("hello from aca"), { overwrite: true });

  const response = await blob.download();
  const content = await streamToBuffer(response.readableStreamBody);
  console.log(content.toString("utf8"));
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
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

1. Confirm RBAC assignment:

```bash
az role assignment list \
  --assignee "$PRINCIPAL_ID" \
  --scope "$STORAGE_ID" \
  --output table
```

| Command | Why it is used |
|---|---|
| `az role assignment list ...` | Lists Azure RBAC assignments to verify access or diagnose conflicts. |

2. Confirm the uploaded blob exists:

```bash
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$STORAGE_CONTAINER" \
  --auth-mode login \
  --output table
```

| Command | Why it is used |
|---|---|
| `az storage blob ...` | Creates or inspects Storage resources used by volume, state, or sample app scenarios. |

3. Check app logs for successful upload and download operations:

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --follow false
```

| Command | Why it is used |
|---|---|
| `az containerapp logs show ...` | Runs the Azure CLI operation required by the documented step. |

## See Also

- [Managed Identity](managed-identity.md)
- [Key Vault Reference](key-vault-reference.md)
- [Node.js Tutorials](../index.md)

## Sources

- [Azure Storage Blob client library for JavaScript](https://learn.microsoft.com/en-us/javascript/api/overview/azure/storage-blob-readme)
- [Assign an Azure role for Blob data access](https://learn.microsoft.com/en-us/azure/storage/blobs/assign-azure-role-data-access)
- [Managed identities in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
