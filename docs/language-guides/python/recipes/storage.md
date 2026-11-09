---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts
        - https://learn.microsoft.com/en-us/python/api/overview/azure/storage-blob-readme
        - https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts#storage-types
    - id: container-apps-containers-are-ephemeral-by
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts
        - https://learn.microsoft.com/en-us/python/api/overview/azure/storage-blob-readme
        - https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts#storage-types
---
# Storage: Volume Mounts and Blob Storage

Connect your Container App to Azure Storage — either by mounting an Azure Files share directly into the container filesystem, or by accessing Blob Storage programmatically via the SDK with Managed Identity.

## Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Choose persistent object or file storage for a Python app
    accDescr: The Python app can use its managed identity with the Blob SDK for object storage, or mount a classic Azure Files share through an environment storage definition for shared filesystem access.

    APP_ID[App managed identity]
    ENV_ID[Environment managed identity<br/>recommended for new SMB mounts]
    BLOB[Azure Blob Storage]
    FILES[Classic Azure Files share]

    ENV[Container Apps environment]
    APP[Python container app]
    STORAGE[Environment storage definition]
    MOUNT[Mounted path<br/>/mnt/appfiles]

    ENV -->|Hosts| APP
    ENV -->|Contains| STORAGE
    APP -.->|Uses for SDK authentication| APP_ID
    APP_ID -.->|Blob data role| BLOB
    APP ==>|Blob SDK requests| BLOB
    ENV_ID -.->|Assigned to environment| STORAGE
    STORAGE -.->|References share| FILES
    APP ==>|Filesystem read and write| MOUNT
    MOUNT ==>|SMB file operations| FILES
```

Thick arrows show object or file transport. Dotted arrows show identity, authorization, and storage-definition associations.

!!! note "Blob mounts are not supported in Container Apps"
    Unlike App Service, Azure Container Apps **cannot mount Blob Storage as a filesystem path**. Use the Azure Storage Blob SDK with Managed Identity for blob access. For shared filesystem access, use **Azure Files volume mounts**.

## Overview

Container Apps containers are ephemeral by default — all writes to the local filesystem are lost when a replica restarts or scales down. To persist data or share files across replicas, you need external storage.

<!-- diagram-id: container-apps-containers-are-ephemeral-by -->
```mermaid
flowchart TD
    accTitle: Compare Container Apps storage lifetimes
    accDescr: Container-scoped filesystem data lasts until that container stops or restarts. EmptyDir data is shared by containers in one replica and lasts for the replica lifetime, including individual container restarts. Azure Files persists outside replicas and can be shared across replicas, revisions, and apps.

    WRITE[Application writes data]
    CHOICE[Choose required lifetime and access]
    LOCAL[Container-scoped filesystem]
    EMPTY[Replica-scoped EmptyDir]
    FILES[Azure Files volume]
    LOCAL_END[Removed when container<br/>stops or restarts]
    EMPTY_END[Persists across container restart<br/>removed when replica stops]
    FILES_KEEP[Persists in Azure Files<br/>shareable across replicas and apps]

    subgraph OPTIONS[Storage lifetime options]
        LOCAL
        EMPTY
        FILES
    end

    WRITE --> CHOICE
    CHOICE -->|Current container only| LOCAL
    CHOICE -->|Containers in one replica| EMPTY
    CHOICE -->|Persistent shared files| FILES
    LOCAL --> LOCAL_END
    EMPTY --> EMPTY_END
    FILES --> FILES_KEEP
```

Arrows show storage-selection and lifetime outcomes, not network transport.

### When to use which storage type

| Scenario | Recommended approach |
|----------|---------------------|
| User file uploads, blob data | **Blob Storage SDK** (Managed Identity) |
| Shared files across replicas (config, exports) | **Azure Files volume mount** |
| Large objects, static assets | **Blob Storage SDK** |
| Temporary processing scratch space | **EmptyDir volume** |
| Secrets as files | **Secret volume** |
| SQLite database | ⚠️ Azure Files mount — but see [limitations](#limitations-and-caveats) |
| High-frequency writes (> 100/sec) | **Blob SDK directly** — mounts add latency |

### Storage options comparison

| Option | Persistence | Shared across replicas | Access type | Authentication |
|--------|-------------|----------------------|-------------|----------------|
| Container local disk | ❌ Ephemeral | ❌ No | Filesystem | N/A |
| EmptyDir volume | ❌ Replica lifetime | ✅ Between containers in one replica | Filesystem | N/A |
| Azure Files mount | ✅ Persistent | ✅ Yes | Filesystem | Environment managed identity for new SMB mounts (preview), storage key alternative, or network controls for NFS |
| Blob Storage SDK | ✅ Persistent | ✅ Yes | SDK / HTTP | Managed Identity or key |

### I/O performance

| Storage | Latency (approx.) | Throughput | Notes |
|---------|------------------|------------|-------|
| Container local disk | ~1ms | High | Lost on restart |
| EmptyDir (tmpfs) | ~1ms | High | Lost on revision change |
| Azure Files mount | ~10–50ms | Medium | Shared, persistent, SMB over network |
| Blob Storage SDK | ~5–20ms | High | Full read/write, passwordless |

## Prerequisites

- Existing Container App: `$APP_NAME` in `$RG`
- Existing Container Apps environment: `$ACA_ENV_NAME`
- Existing Storage account: `$STORAGE_ACCOUNT`
- Azure CLI with Container Apps extension: `az extension add --name containerapp`

## Part 1: Blob Storage via SDK (Managed Identity)

Access Blob Storage from your app code using a system-assigned managed identity — no storage keys required.

### Step 1: Enable managed identity

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
| `az containerapp identity assign` | Assigns the Container App identity to enable the Blob Storage workload identity. |
| `az containerapp show` | Obtains the app principal that will receive permission to upload and download blobs. |
| `--name` | Targets `$APP_NAME` for workload identity assignment and Container App property inspection. |
| `--resource-group` | Scopes workload identity assignment and Container App property inspection to `$RG`. |
| `az containerapp identity assign --system-assigned` | Enables the system-assigned identity on the resource modified by `az containerapp identity assign` to enable the Blob Storage workload identity. |
| `az containerapp show --query` | Selects the system identity's principal ID for the Blob data role assignment. |
| `az containerapp show --output` | Captures the principal ID as unquoted text in `PRINCIPAL_ID`. |


### Step 2: Assign Storage Blob Data Contributor role

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
| `az storage account show` | Retrieves `$STORAGE_ACCOUNT`'s resource ID to define the Blob data permission boundary. |
| `az role assignment create` | Grants the app principal Blob Data Contributor access at the selected storage account scope. |
| `az storage account show --name` | Targets `$STORAGE_ACCOUNT` for storage account scope lookup. |
| `az storage account show --resource-group` | Finds `$STORAGE_ACCOUNT` in `$RG` before extracting the role-assignment scope. |
| `az storage account show --query` | Extracts the storage account resource ID that defines the Blob contributor grant boundary. |
| `az storage account show --output` | Saves the account ID as plain text in `STORAGE_ID` for the next command. |
| `az role assignment create --assignee-object-id` | Configures the principal receiving the role as `$PRINCIPAL_ID` on `az role assignment create` to grant Blob data-plane access. |
| `az role assignment create --assignee-principal-type` | Configures the role-assignment principal type as `ServicePrincipal` on `az role assignment create` to grant Blob data-plane access. |
| `az role assignment create --role` | Allows the Python workload to create, read, and update blobs without using account keys. |
| `az role assignment create --scope` | Limits the contributor permission to the selected storage account. |


### Step 3: Configure the Blob endpoint

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars STORAGE_ACCOUNT_URL="https://$STORAGE_ACCOUNT.blob.core.windows.net"
```

| Command | Why it is used |
|---|---|
| `az containerapp update` | Adds the Blob service URL that the passwordless Python client uses in a new app revision. |
| `--name` | Targets `$APP_NAME`, which receives the Blob service endpoint. |
| `--resource-group` | Locates `$APP_NAME` in `$RG` before adding the Blob service URL. |
| `--set-env-vars` | Configures the environment variables written to the workload as `STORAGE_ACCOUNT_URL=https://$STORAGE_ACCOUNT.blob.core.windows.net` on `az containerapp update`. |


### Step 4: Python code for Blob operations

Install dependencies:

```bash
pip install azure-identity azure-storage-blob
```

Use `DefaultAzureCredential` for passwordless access:

```python
import os
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

credential = DefaultAzureCredential()
account_url = os.environ["STORAGE_ACCOUNT_URL"]
service_client = BlobServiceClient(account_url=account_url, credential=credential)
container_client = service_client.get_container_client("app-data")

# Upload
container_client.upload_blob(name="hello.txt", data=b"hello from aca", overwrite=True)

# Download
blob = container_client.download_blob("hello.txt")
content = blob.readall()

# List blobs
for b in container_client.list_blobs():
    print(b.name)
```

### Verification

Check blob upload from CLI:

```bash
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "app-data" \
  --auth-mode login \
  --output table
```

| Command | Why it is used |
|---|---|
| `az storage blob list` | Lists `app-data` blobs to confirm the workload uploaded the expected object. |
| `--account-name` | Inspects `$STORAGE_ACCOUNT` for the blob uploaded by the sample app. |
| `--container-name` | Configures the application container as `app-data` on `az storage blob list`. |
| `--auth-mode` | Configures the auth mode as `login` on `az storage blob list`. |
| `--output` | Presents uploaded blob names and properties in columns for the post-upload check. |


Check app logs:

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --follow false
```

| Command | Why it is used |
|---|---|
| `az containerapp logs show` | Retrieves `$APP_NAME` runtime logs to inspect Blob access logs. |
| `--name` | Targets `$APP_NAME`, whose logs reveal Blob data-plane access. |
| `--resource-group` | Finds `$APP_NAME` in `$RG` for the Blob operation log check. |
| `--follow` | Returns the completed upload and download evidence without streaming new logs. |


---

## Part 2: Azure Files Volume Mount

Mount an Azure Files share into the container as a local directory. All replicas share the same mounted filesystem.

!!! important "Azure Files storage is registered at the environment level"
    In Container Apps, storage is registered on the **Environment**, not the app. Once registered, any app in that environment can reference it. A change to volume mounts creates a new **revision**.

### Step 1: Create an Azure Files share

```bash
az storage share-rm create \
  --storage-account "$STORAGE_ACCOUNT" \
  --resource-group "$RG" \
  --name "app-files"
```

| Command | Why it is used |
|---|---|
| `az storage share-rm create` | Provisions the `app-files` share that all Container App replicas will mount. |
| `--storage-account` | Hosts the new `app-files` share in `$STORAGE_ACCOUNT`. |
| `--resource-group` | Creates the Azure Files share in the `$RG` containing `$STORAGE_ACCOUNT`. |
| `--name` | Names the new persistent share `app-files` for environment registration. |


### Step 2: Register storage in the Container Apps Environment

#### Using CLI

```bash
export STORAGE_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RG" \
  --query "[0].value" \
  --output tsv)

az containerapp env storage set \
  --name "$ACA_ENV_NAME" \
  --resource-group "$RG" \
  --storage-name "appfiles" \
  --azure-file-account-name "$STORAGE_ACCOUNT" \
  --azure-file-account-key "$STORAGE_KEY" \
  --azure-file-share-name "app-files" \
  --access-mode ReadWrite
```

| Command | Why it is used |
|---|---|
| `az storage account keys list` | Retrieves the first storage key used to register the Azure Files share. |
| `az containerapp env storage set` | Registers `$STORAGE_ACCOUNT` and `app-files` as the environment storage definition `appfiles`. |
| `az storage account keys list --account-name` | Retrieves the account key from `$STORAGE_ACCOUNT` for environment-level share registration. |
| `--resource-group` | Scopes storage access-key retrieval and environment storage definition to `$RG`. |
| `az storage account keys list --query` | Chooses the first account key needed by the Azure Files environment registration. |
| `az storage account keys list --output` | Places only the key text in `STORAGE_KEY`, omitting the key metadata. |
| `az containerapp env storage set --name` | Targets `$ACA_ENV_NAME` for environment storage definition. |
| `az containerapp env storage set --storage-name` | Configures the environment storage definition as `appfiles` on `az containerapp env storage set`. |
| `az containerapp env storage set --azure-file-account-name` | Configures the azure file account name as `$STORAGE_ACCOUNT` on `az containerapp env storage set`. |
| `az containerapp env storage set --azure-file-account-key` | Configures the azure file account key as `$STORAGE_KEY` on `az containerapp env storage set`. |
| `az containerapp env storage set --azure-file-share-name` | Configures the azure file share name as `app-files` on `az containerapp env storage set`. |
| `az containerapp env storage set --access-mode` | Configures the access mode as `ReadWrite` on `az containerapp env storage set`. |


Verify the environment storage was registered:

```bash
az containerapp env storage show \
  --name "$ACA_ENV_NAME" \
  --resource-group "$RG" \
  --storage-name "appfiles"
```

| Command | Why it is used |
|---|---|
| `az containerapp env storage show` | Displays `appfiles` to verify the environment storage definition. |
| `--name` | Targets `$ACA_ENV_NAME` for environment storage verification. |
| `--resource-group` | Finds `$ACA_ENV_NAME` in `$RG` for the `appfiles` registration check. |
| `--storage-name` | Configures the environment storage definition as `appfiles` on `az containerapp env storage show`. |


Expected output:

```json
{
  "name": "appfiles",
  "properties": {
    "azureFile": {
      "accessMode": "ReadWrite",
      "accountName": "mystorageaccount",
      "shareName": "app-files"
    }
  }
}
```

#### Using Bicep

```bicep
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: environmentName
}

resource environmentStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  parent: environment
  name: 'appfiles'
  properties: {
    azureFile: {
      accountName: storageAccountName
      accountKey: storageAccountKey  // Store in Key Vault — see Security section
      shareName: 'app-files'
      accessMode: 'ReadWrite'
    }
  }
}
```

### Step 3: Attach the volume mount to your Container App

#### Using YAML update

Export the current app definition:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output yaml > app-volume.yaml
```

| Command | Why it is used |
|---|---|
| `az containerapp show` | Exports the current app template as the starting point for adding `appfiles`. |
| `--name` | Targets `$APP_NAME`, whose current template is exported before adding a volume. |
| `--resource-group` | Locates `$APP_NAME` in `$RG` before exporting its template to YAML. |
| `--output` | Serializes the app definition as YAML; shell redirection writes it to `app-volume.yaml`. |


Edit `app-volume.yaml` to add volumes and volumeMounts under `template`:

```yaml
template:
  containers:
    - name: app
      image: <your-image>
      volumeMounts:
        - volumeName: appfiles
          mountPath: /mnt/appfiles
  volumes:
    - name: appfiles
      storageType: AzureFile
      storageName: appfiles   # Must match the name registered in the environment
```

Apply the updated template:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --yaml app-volume.yaml
```

| Command | Why it is used |
|---|---|
| `az containerapp update` | Applies `app-volume.yaml` to create a revision that mounts the registered `appfiles` share. |
| `--name` | Targets `$APP_NAME`, which receives the Azure Files volume YAML. |
| `--resource-group` | Finds `$APP_NAME` in `$RG` before applying the volume-enabled YAML. |
| `--yaml` | Configures the declarative Container Apps configuration file as `app-volume.yaml` on `az containerapp update`. |


This creates a **new revision**. Traffic will shift to the new revision automatically unless you are using manual revision mode.

#### Using Bicep

```bicep
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  properties: {
    environmentId: environment.id
    template: {
      containers: [
        {
          name: 'app'
          image: containerImage
          volumeMounts: [
            {
              volumeName: 'appfiles'
              mountPath: '/mnt/appfiles'
            }
          ]
        }
      ]
      volumes: [
        {
          name: 'appfiles'
          storageType: 'AzureFile'
          storageName: 'appfiles'  // References the environment storage name
        }
      ]
    }
  }
}
```

### Step 4: Python code for mounted filesystem

Once mounted, use standard Python file I/O — no special SDK required:

```python
import os

MOUNT_PATH = os.environ.get("FILES_MOUNT_PATH", "/mnt/appfiles")

# Write a file
def save_report(filename: str, content: str) -> None:
    filepath = os.path.join(MOUNT_PATH, filename)
    with open(filepath, "w") as f:
        f.write(content)

# Read a file
def load_report(filename: str) -> str:
    filepath = os.path.join(MOUNT_PATH, filename)
    with open(filepath, "r") as f:
        return f.read()

# List files
def list_reports() -> list[str]:
    return os.listdir(MOUNT_PATH)
```

Set the mount path as an env var so local development can override it:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars FILES_MOUNT_PATH=/mnt/appfiles
```

| Command | Why it is used |
|---|---|
| `az containerapp update` | Sets `/mnt/appfiles` as the filesystem path consumed by the Python mounted-storage sample. |
| `--name` | Targets `$APP_NAME`, which receives the mounted-filesystem path. |
| `--resource-group` | Locates `$APP_NAME` in `$RG` before setting its mounted-filesystem path. |
| `--set-env-vars` | Configures the environment variables written to the workload as `FILES_MOUNT_PATH=/mnt/appfiles` on `az containerapp update`. |


### Verification

Verify the mount is active and accessible in a running replica:

```bash
az containerapp exec \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --command "ls -la /mnt/appfiles"
```

| Command | Why it is used |
|---|---|
| `az containerapp exec` | Opens a process in `$APP_NAME` to inspect the mounted Azure Files directory. |
| `--name` | Targets `$APP_NAME`, where the mounted directory is listed. |
| `--resource-group` | Finds the running `$APP_NAME` replica in `$RG` for the mount listing. |
| `--command` | Lists `/mnt/appfiles` so the mounted share contents are visible from the app. |


Expected output (if the share has files):

```
total 8
drwxrwxrwx 2 root root 4096 Jan 01 00:00 .
drwxr-xr-x 3 root root 4096 Jan 01 00:00 ..
-rw-r--r-- 1 root root   14 Jan 01 00:00 hello.txt
```

Write a test file from inside the container and confirm it persists across replicas:

```bash
# Write from one replica
az containerapp exec \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --command "sh -c 'echo test > /mnt/appfiles/test.txt'"

# Verify via Azure Files
az storage file list \
  --account-name "$STORAGE_ACCOUNT" \
  --share-name "app-files" \
  --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp exec` | Opens a process in `$APP_NAME` to write a persistence probe through the mount. |
| `az storage file list` | Lists files in `app-files` to confirm the probe reached Azure Files. |
| `az containerapp exec --name` | Targets `$APP_NAME`, where the persistence probe is written. |
| `az containerapp exec --resource-group` | Locates `$APP_NAME` in `$RG` before writing the persistence probe through its mount. |
| `az containerapp exec --command` | Writes `test.txt` through `/mnt/appfiles` to test persistence on the share. |
| `az storage file list --account-name` | Checks `$STORAGE_ACCOUNT` for the file written through the app mount. |
| `az storage file list --share-name` | Configures the Azure Files share as `app-files` on `az storage file list`. |
| `az storage file list --output` | Shows the share contents in columns so `test.txt` can be confirmed after the mounted write. |


---

## Part 3: EmptyDir Volume (Ephemeral Scratch Space)

Use `EmptyDir` for temporary per-replica working directories — faster than Azure Files, but data is lost when the replica restarts or the revision changes.

Use EmptyDir when:
- You need a fast temp directory for in-flight processing (image resize, zip/unzip)
- You want to share temp files between **multiple containers in the same replica** (sidecar pattern)
- You explicitly do NOT need persistence

```yaml
template:
  containers:
    - name: app
      image: <your-image>
      volumeMounts:
        - volumeName: tmpdata
          mountPath: /tmp/processing
  volumes:
    - name: tmpdata
      storageType: EmptyDir
```

!!! warning "EmptyDir is not shared across replicas"
    Each replica gets its own EmptyDir. If you scale to 3 replicas, each has an independent `/tmp/processing` directory.

---

## Security: Choose the Azure Files authentication mode

For new SMB mounts, Microsoft recommends managed identity authentication in preview. The identity is assigned to the **Container Apps environment**, not the individual app. Existing storage-account-key mounts remain supported. NFS mounts use network-based access controls rather than SMB authentication settings.

The key-based commands below document the alternative path. Avoid storing the key in scripts or CI pipelines.

### Store the storage key in Key Vault

```bash
az keyvault secret set \
  --vault-name "$KEY_VAULT_NAME" \
  --name "storage-account-key" \
  --value "$STORAGE_KEY"
```

| Command | Why it is used |
|---|---|
| `az keyvault secret set` | Stores the Azure Files account key as `storage-account-key` for secure deployment-time retrieval. |
| `--vault-name` | Configures the vault name as `$KEY_VAULT_NAME` on `az keyvault secret set`. |
| `--name` | Targets `storage-account-key` for Key Vault secret creation and application secret binding. |
| `--value` | Configures the secret value as `$STORAGE_KEY` on `az keyvault secret set`. |


### Reference from Bicep (secure parameter)

```bicep
// Reference key from Key Vault at deployment time
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource environmentStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  parent: environment
  name: 'appfiles'
  properties: {
    azureFile: {
      accountName: storageAccountName
      accountKey: keyVault.getSecret('storage-account-key')
      shareName: 'app-files'
      accessMode: 'ReadWrite'
    }
  }
}
```

!!! note "Managed identity scope differs by storage path"
    Blob SDK access uses the **app** identity. New SMB Azure Files mounts can use a managed identity assigned to the **environment** when the storage account and RBAC prerequisites are configured. Do not combine `--azure-file-identity` with the storage-key authentication options.

See [Key Vault Secrets Management](../../../platform/identity-and-secrets/key-vault.md) for the full setup.

---

## Limitations and Caveats

!!! warning "Know these before relying on Azure Files mounts in production"

    - **Storage is registered at environment level.** All apps in the environment can reference the same storage name. Name your storages clearly (`appfiles-prod`, `appfiles-staging`) to avoid confusion.
    - **Blob Storage cannot be mounted as a filesystem path.** Use the SDK for blob access. Persistent file mounts use classic Azure Files shares over SMB (`AzureFile`) or NFS (`NfsAzureFile`).
    - **Volume mount changes create a new revision.** Updating `volumeMounts` or `volumes` in the app template triggers a revision rollout. Plan for this in production.
    - **Azure Files is network storage.** Measure the selected share and protocol under your workload instead of relying on a universal latency estimate.
    - **SQLite and file-locking workloads are unreliable.** SMB file locks are not fully compatible with SQLite's locking model. Use Azure SQL or Cosmos DB instead.
    - **Scaling to zero disconnects the mount.** When a Container App scales to zero replicas, there is no active mount. On scale-up, the mount reconnects automatically — but do not assume the mount is always live.
    - **Storage account key in environment storage is not rotated automatically.** If you rotate the storage key, you must re-run `az containerapp env storage set` with the new key.
    - **Access mode is set at environment registration, not at mount time.** `ReadOnly` or `ReadWrite` is configured when you register storage in the environment — not per-app.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `/mnt/appfiles` not visible in `containerapp exec` | Volume mount not applied or wrong revision active | Check revision list; verify YAML has `volumes` + `volumeMounts`; ensure latest revision is active |
| `Permission denied` writing to mount | `access-mode` set to `ReadOnly` | Re-register environment storage with `--access-mode ReadWrite` |
| `Transport endpoint is not connected` | SMB connection dropped (transient) | Retry; check storage account firewall — ensure Container Apps environment subnet is allowed |
| Files written on one replica not visible on another | Writing to container local disk, not the mount | Confirm `mountPath` in YAML matches path used in code; use `os.environ.get("FILES_MOUNT_PATH")` |
| `AccountIsDisabled` or `AuthenticationFailed` | Storage key rotated or incorrect | Retrieve new key and re-run `az containerapp env storage set` |
| `az containerapp env storage set` fails | Environment name or resource group mismatch | Verify `$ACA_ENV_NAME` matches the environment your app is in |
| Slow file I/O on mount | Azure Files SMB latency | Use EmptyDir for hot temporary files; only persist final results to the mount |
| Mount missing after scale-out | New replica starting up before mount is ready | Add retry logic on startup; mount reconnects within seconds |

---

## See Also
- [Managed Identity](../../../platform/identity-and-secrets/managed-identity.md)
- [Key Vault Secrets Management](../../../platform/identity-and-secrets/key-vault.md)
- [Private Endpoints](../../../platform/networking/private-endpoints.md)

## Sources
- [Azure Files in Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts)
- [Azure Storage Blob SDK for Python](https://learn.microsoft.com/en-us/python/api/overview/azure/storage-blob-readme)
- [Container Apps volume mount types (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts#storage-types)
