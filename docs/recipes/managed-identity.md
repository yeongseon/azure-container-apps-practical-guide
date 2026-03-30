# Passwordless Access with Managed Identity

Azure Container Apps (ACA) supports managed identities, allowing your Python application to securely access other Azure services without managing credentials like connection strings or API keys.

## Types of Managed Identity

- **System-assigned:** Tied to the lifecycle of the Container App.
- **User-assigned:** Created as a separate resource and can be shared among multiple apps.

## Enabling Managed Identity

To enable a system-assigned managed identity for your app:

```bash
az containerapp identity assign \
  --name my-python-app \
  --resource-group my-aca-rg \
  --system-assigned
```

## Assigning Roles

Assign roles to the managed identity to grant access to other resources (e.g., Azure SQL, Blob Storage, Key Vault).

```bash
# Get the principal ID of the system-assigned identity
principalId=$(az containerapp show --name my-python-app --resource-group my-aca-rg --query identity.principalId -o tsv)

# Assign the 'Storage Blob Data Reader' role
az role assignment create \
  --assignee $principalId \
  --role "Storage Blob Data Reader" \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/my-aca-rg/providers/Microsoft.Storage/storageAccounts/mystorageaccount
```

## Python Implementation

Use the `azure-identity` library in your Python code to authenticate using the managed identity.

```python
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

# DefaultAzureCredential will automatically pick up the managed identity
credential = DefaultAzureCredential()

# Connect to the storage account using the credential
blob_service_client = BlobServiceClient(
    account_url="https://mystorageaccount.blob.core.windows.net",
    credential=credential
)
```

## Why use Managed Identity?

- **Zero Secret Management:** No need to rotate passwords or API keys.
- **Improved Security:** Access is granted based on the identity of the application itself.
- **Simplified Configuration:** No more connection strings in environment variables or secrets.
