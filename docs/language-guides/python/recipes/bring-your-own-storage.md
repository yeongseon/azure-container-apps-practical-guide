# Recipe: Bring Your Own Storage with Azure Files Mounts

Mount Azure Files into your Python Container App when you need shared, persistent filesystem access across replicas.

## Prerequisites

- Existing Storage account (`$STORAGE_ACCOUNT`) in `$RG`
- Existing Container Apps environment (`$ENVIRONMENT_NAME`)
- Existing app (`$APP_NAME`) in the same environment
- Azure CLI with Container Apps extension

```bash
az extension add --name containerapp --upgrade
```

## Create an Azure Files share

```bash
az storage share-rm create \
  --resource-group "$RG" \
  --storage-account "$STORAGE_ACCOUNT" \
  --name "aca-shared"

export STORAGE_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RG" \
  --query "[0].value" \
  --output tsv)
```

## Configure the storage mount in Container Apps

Register the Azure Files share at the environment level.

```bash
az containerapp env storage set \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RG" \
  --storage-name "sharedfiles" \
  --azure-file-account-name "$STORAGE_ACCOUNT" \
  --azure-file-account-key "$STORAGE_KEY" \
  --azure-file-share-name "aca-shared" \
  --access-mode ReadWrite
```

Attach it to the app.

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --yaml "containerapp-with-volume.yaml"
```

Example YAML fragment:

```yaml
properties:
  template:
    volumes:
      - name: shared-files
        storageType: AzureFile
        storageName: sharedfiles
    containers:
      - name: app
        image: <image>
        volumeMounts:
          - volumeName: shared-files
            mountPath: /mnt/shared
```

## Read and write mounted files in Python

```python
from pathlib import Path
from flask import Flask, jsonify

app = Flask(__name__)
MOUNT_PATH = Path("/mnt/shared")

@app.post("/write")
def write_file():
    MOUNT_PATH.mkdir(parents=True, exist_ok=True)
    target = MOUNT_PATH / "status.txt"
    target.write_text("written from container app", encoding="utf-8")
    return jsonify(file=str(target), written=True), 200

@app.get("/read")
def read_file():
    target = MOUNT_PATH / "status.txt"
    return jsonify(content=target.read_text(encoding="utf-8")), 200
```

## Bicep example for storage mount

```bicep
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: environmentName
}

resource storage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  name: 'sharedfiles'
  parent: environment
  properties: {
    azureFile: {
      accountName: storageAccountName
      accountKey: storageAccountKey
      shareName: 'aca-shared'
      accessMode: 'ReadWrite'
    }
  }
}
```

## Performance considerations

- Azure Files adds network latency versus local ephemeral disk.
- Many small file operations can be slower than blob/object access patterns.
- Use mounted shares for coordination/state handoff, not high-throughput analytics pipelines.

## Typical use cases

- Shared config rendered at runtime
- Upload staging before async processing
- Temporary exported artifacts that must survive restarts

## Limitations

- Container Apps supports **Azure Files mounts**, not Blob filesystem mounts.
- Throughput depends on storage account/file share limits.
- Mount configuration changes create a new app revision.

## Advanced Topics

- Combine mount access with queue-based processing for resilient workflows.
- Store storage keys in Key Vault and rotate periodically.
- For high-scale binary workloads, prefer Blob SDK over filesystem semantics.

## See Also

- [Storage](storage.md)
- [Key Vault Reference](key-vault-reference.md)
- [Environments](../../../platform/environments/index.md)
- [Microsoft Learn: Use Azure Files in Container Apps](https://learn.microsoft.com/azure/container-apps/storage-mounts)
