# Blob Storage and File Mounts

Use this recipe to combine Azure Blob Storage (SDK access with managed identity) and Azure Files volume mounts in Azure Container Apps.

## Prerequisites

- Existing Container App: `$APP_NAME` in `$RG`
- Existing Container Apps environment: `$ENVIRONMENT_NAME`
- Existing Storage account: `$STORAGE_ACCOUNT`

## Step 1: Enable managed identity for Blob Storage access

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

Assign Blob data role:

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

## Step 2: Configure Blob endpoint for your app

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars STORAGE_ACCOUNT_URL="https://$STORAGE_ACCOUNT.blob.core.windows.net"
```

## Step 3: Python code for Blob operations (passwordless)

Install dependencies:

```bash
pip install azure-identity azure-storage-blob
```

Use `DefaultAzureCredential`:

```python
import os
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

credential = DefaultAzureCredential()
account_url = os.environ["STORAGE_ACCOUNT_URL"]

service_client = BlobServiceClient(account_url=account_url, credential=credential)
container_client = service_client.get_container_client("app-data")
container_client.upload_blob(name="hello.txt", data=b"hello from aca", overwrite=True)
```

## Step 4: Configure Azure Files volume mount for Container Apps

Create file share:

```bash
az storage share-rm create \
  --storage-account "$STORAGE_ACCOUNT" \
  --resource-group "$RG" \
  --name "app-files"
```

Register storage in the Container Apps environment:

```bash
export STORAGE_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RG" \
  --query "[0].value" \
  --output tsv)

az containerapp env storage set \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RG" \
  --storage-name "appfiles" \
  --azure-file-account-name "$STORAGE_ACCOUNT" \
  --azure-file-account-key "$STORAGE_KEY" \
  --azure-file-share-name "app-files" \
  --access-mode ReadWrite
```

Attach the volume mount using a YAML update:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output yaml > app-volume.yaml
```

Update `app-volume.yaml` with:

```yaml
template:
  containers:
    - name: app
      volumeMounts:
        - volumeName: appfiles
          mountPath: /mnt/appfiles
  volumes:
    - name: appfiles
      storageType: AzureFile
      storageName: appfiles
```

Apply the updated template:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --yaml app-volume.yaml
```

## Verification steps

1. Verify mounted volume in running container:

```bash
az containerapp exec \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --command "ls -la /mnt/appfiles"
```

2. Verify Blob upload and list:

```bash
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "app-data" \
  --auth-mode login \
  --output table
```

3. Check app logs for Blob and file mount usage:

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --follow false
```

## See Also

- [Managed Identity](./managed-identity.md)
- [Private Endpoints](./networking-private-endpoint.md)
- [Azure Storage Blob SDK for Python](https://learn.microsoft.com/python/api/overview/azure/storage-blob-readme)
