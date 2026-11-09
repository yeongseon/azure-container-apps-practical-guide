---
content_sources:
  diagrams:
    - id: use-managed-identity-and-defaultazurecredential-so
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
        - https://learn.microsoft.com/en-us/javascript/api/overview/azure/identity-readme
        - https://learn.microsoft.com/en-us/javascript/api/overview/azure/storage-blob-readme
---
# Recipe: Managed Identity in Node.js Apps on Azure Container Apps

Use managed identity and `DefaultAzureCredential` so your Express app can call Azure services without storing secrets.

<!-- diagram-id: use-managed-identity-and-defaultazurecredential-so -->
```mermaid
flowchart TD
    accTitle: DefaultAzureCredential access from Express
    accDescr: Express uses DefaultAzureCredential to request a resource-scoped token from the local Container Apps identity endpoint. Microsoft Entra ID issues the token, and Blob Storage independently evaluates the identity's Blob data role before allowing or denying the operation.
    CLIENT[Client]
    APP[Express app<br/>BlobServiceClient]
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
- Azure Storage account (`$STORAGE_ACCOUNT`) and container (`$STORAGE_CONTAINER`)
- Azure CLI with Container Apps extension

```bash
az extension add --name containerapp --upgrade
```

| Command | Why it is used |
|---|---|
| `az extension add ...` | Installs or updates the Container Apps Azure CLI extension. |

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

| Command | Why it is used |
|---|---|
| `az containerapp identity assign ...` | Assigns or inspects managed identity configuration for the Container App. |

## Use `DefaultAzureCredential` in Express

```javascript
const express = require("express");
const { DefaultAzureCredential } = require("@azure/identity");
const { BlobServiceClient } = require("@azure/storage-blob");

const app = express();
const credential = new DefaultAzureCredential();
const accountUrl = process.env.STORAGE_ACCOUNT_URL;
const containerName = process.env.STORAGE_CONTAINER || "app-data";

app.get("/blobs", async (_req, res) => {
  const service = new BlobServiceClient(accountUrl, credential);
  const container = service.getContainerClient(containerName);
  const names = [];
  for await (const blob of container.listBlobsFlat()) {
    names.push(blob.name);
  }
  res.status(200).json({ blobs: names });
});

app.listen(8000, () => console.log("listening on 8000"));
```

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars \
    STORAGE_ACCOUNT_URL="https://$STORAGE_ACCOUNT.blob.core.windows.net" \
    STORAGE_CONTAINER="$STORAGE_CONTAINER"
```

| Command | Why it is used |
|---|---|
| `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

## Advanced Topics

- Use user-assigned identities when multiple apps must share the same RBAC profile.
- Separate read and write access into distinct identities for tighter blast-radius control.
- Add startup probes that verify token acquisition and service authorization before traffic.

## See Also

- [Key Vault Reference](key-vault-reference.md)
- [Easy Auth](easy-auth.md)
- [Managed Identity Platform Guide](../../../platform/identity-and-secrets/managed-identity.md)

## Sources

- [Managed identities in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
- [Azure Identity client library for JavaScript](https://learn.microsoft.com/en-us/javascript/api/overview/azure/identity-readme)
- [Azure Storage Blob SDK for JavaScript](https://learn.microsoft.com/en-us/javascript/api/overview/azure/storage-blob-readme)
