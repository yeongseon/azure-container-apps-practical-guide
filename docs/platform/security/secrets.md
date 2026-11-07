---
content_sources:
  diagrams:
    - id: secretref-resolution-path
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
        - https://learn.microsoft.com/en-us/azure/container-apps/environment-variables
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
content_validation:
  status: verified
  last_reviewed: 2026-11-07
  reviewer: agent
  core_claims:
    - claim: Container Apps secrets are application-scoped, outside any specific revision, and changing a secret does not create a new revision.
      source: https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
      verified: true
    - claim: Container Apps supports inline secrets with a value field and Key Vault-backed secrets with keyVaultUrl and identity fields.
      source: https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
      verified: true
    - claim: Environment variables can reference a secret by using the secretRef field.
      source: https://learn.microsoft.com/en-us/azure/container-apps/environment-variables
      verified: true
    - claim: Application-level secrets can be mounted as files in a secret volume, with all or selected secrets exposed to a revision.
      source: https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
      verified: true
    - claim: If a Key Vault URI omits the secret version, Container Apps retrieves the latest version within 30 minutes and restarts active revisions that reference the secret in an environment variable.
      source: https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
      verified: true
---
# Secrets in Azure Container Apps

Azure Container Apps supports application-scoped secrets stored directly in the app definition or referenced from Azure Key Vault. This page focuses on how those secret mechanisms work inside Container Apps and when secret changes actually reach running revisions.

## Secret exposure model

Container Apps exposes secrets through two layers:

1. **Secret definitions** in the app configuration.
2. **Secret references** from a revision's containers, through environment variables or secret volume mounts.

Microsoft Learn documents two supported secret definition patterns:

- **Inline secret**: the secret value is stored directly in the Container Apps secret store.
- **Key Vault reference**: the secret definition stores a `keyVaultUrl` and an `identity` that Container Apps uses to resolve the value from Azure Key Vault.

!!! note "Secrets are app-scoped, not revision-scoped"
    Secrets are scoped to the container app, outside any specific revision. Adding, changing, or deleting a secret does not create a new revision by itself.

## Inline secrets vs Key Vault references

| Pattern | Secret definition | Identity required | Rotation behavior | Best fit |
|---|---|---|---|---|
| Inline secret | `name` + `value` | No external identity for the secret store itself | Update secret, then deploy a new revision or restart an existing revision to apply it | Low-sensitivity or bootstrap values |
| Key Vault reference | `name` + `keyVaultUrl` + `identity` | Yes — system-assigned or user-assigned managed identity with Key Vault access | If no version is pinned, Container Apps retrieves the latest version within 30 minutes and restarts active revisions that reference it in environment variables | Production secrets with centralized governance |

### Inline secret shape

Microsoft Learn shows inline secrets as name/value pairs:

```json
{
  "name": "queue-connection-string",
  "value": "<secret-value>"
}
```

### Key Vault reference shape

Microsoft Learn shows Key Vault-backed secrets with `keyVaultUrl` and `identity`:

```json
{
  "name": "queue-connection-string",
  "keyVaultUrl": "https://<key-vault-name>.vault.azure.net/secrets/queue-connection-string",
  "identity": "system"
}
```

For a user-assigned identity, Microsoft Learn documents replacing `system` with the user-assigned identity resource ID.

## How containers consume secrets

A revision can expose an application-level secret to a container in two documented ways:

- An environment variable uses `secretRef`; the container reads a process environment value.
- A secret volume uses `secretRef`; the container reads the secret from a mounted file. The volume can mount all application secrets or a selected set with chosen file paths.

**Takeaway:** Choosing environment variable or file consumption does not change where the secret is defined. Inline values and Key Vault references both become application-level Container Apps secrets before a revision consumes them.

<!-- diagram-id: secretref-resolution-path -->
```mermaid
flowchart TD
    accTitle: Resolve and consume an Azure Container Apps secret
    accDescr: A decision flow starts with an application-level secret definition. An inline value is stored by Container Apps. For a Key Vault reference, the Container Apps secret resolver uses the selected managed identity, requests authorization from Key Vault, returns a failure when access is denied, and retrieves the value only after authorization succeeds. A revision then consumes the resolved app secret through either a secretRef environment variable or a mounted secret file.

    DEFINE{"Application-level<br/>secret definition?"}
    INLINE["Inline Container Apps secret<br/>name and value"]
    KVREF["Key Vault reference<br/>keyVaultUrl and identity"]
    RESOLVER["Container Apps secret resolver<br/>platform requester"]
    IDENTITY["Assigned managed identity<br/>system or user assigned"]
    RBAC["Key Vault access policy or RBAC<br/>for example, Secrets User"]
    AUTHZ{"Key Vault authorization<br/>succeeds?"}
    VAULT["Azure Key Vault secret"]
    FAILURE["Secret retrieval fails<br/>identity, permission, or access error"]
    APP_SECRET["Resolved Container Apps secret<br/>application scope"]

    CONSUME{"How does the revision<br/>consume the secret?"}
    ENV_REF["Environment variable<br/>secretRef"]
    VOLUME_REF["Secret volume<br/>secretRef file"]
    PROCESS["Revision container process"]
    FILE["Mounted secret file"]

    DEFINE -->|"Inline value"| INLINE
    DEFINE -->|"Key Vault source"| KVREF
    INLINE -->|"Store value"| APP_SECRET
    KVREF -->|"Configure source"| RESOLVER
    IDENTITY -.->|"Selected identity"| RESOLVER
    RESOLVER -->|"Request secret read"| AUTHZ
    RBAC -.->|"Evaluate permission"| AUTHZ
    AUTHZ -->|"Denied"| FAILURE
    AUTHZ -->|"Allowed"| VAULT
    VAULT ==>|"Return secret value"| RESOLVER
    RESOLVER ==>|"Store resolved value"| APP_SECRET

    APP_SECRET --> CONSUME
    CONSUME -->|"Environment variable"| ENV_REF
    CONSUME -->|"Mounted file"| VOLUME_REF
    ENV_REF -->|"Populate at revision start"| PROCESS
    VOLUME_REF -->|"Mount file"| FILE
    FILE -->|"Application reads file"| PROCESS

    LEGEND["Arrow key<br/>thick = secret-value transport<br/>solid = configuration, request, or decision flow<br/>dotted = identity or policy input"]
```

*Figure: The Container Apps secret resolver is the platform requester. It uses the selected managed identity, but Key Vault returns the secret value only after its access policy or RBAC evaluation allows the read; denial ends in a retrieval failure rather than an application-level secret.*

Example environment variable reference:

```json
{
  "name": "ConnectionString",
  "secretRef": "queue-connection-string"
}
```

The same secret name can be referenced by multiple revisions because the secret definition lives at the application level.

For a file-based consumer, define a revision-scoped secret volume and mount it into the container. Creating or changing the volume or its mount is a template change and therefore creates a new revision. Microsoft Learn documents that mounted secrets appear as files, but the current Container Apps secret page does not promise live in-place updates to those files after an application-level secret changes. Plan a new revision or restart when the mounted value must refresh.

## Managed identity requirements for Key Vault

Container Apps requires a managed identity before it can resolve a Key Vault-backed secret. Microsoft Learn documents these requirements:

- Enable either a **system-assigned** or **user-assigned** managed identity on the container app.
- Grant the identity access to the secret in Key Vault, typically through Azure RBAC such as `Key Vault Secrets User`.
- Ensure the app has a valid network path to Key Vault if the vault is behind private endpoints or other network restrictions.

!!! warning "CLI sequencing matters for system-assigned identity"
    Microsoft Learn notes that a system-assigned identity is not available until after the app is created. When you need to configure Key Vault references during initial deployment automation, verify whether your workflow should use a user-assigned identity first.

## Rotation and refresh behavior

Rotation behavior is where inline secrets and Key Vault references diverge most.

### Inline secrets

When you update or delete an inline secret:

- Existing revisions do **not** automatically receive the new value.
- You must either:
    - Deploy a new revision, or
    - Restart an existing revision.

This makes inline secrets operationally simple, but they do not provide automatic refresh behavior.

### Key Vault references

When the `keyVaultUrl` omits a secret version:

- Container Apps uses the latest Key Vault version.
- When a newer version becomes available, Container Apps automatically retrieves it within 30 minutes.
- Active revisions that reference that secret in an environment variable are automatically restarted to pick up the new value.

If you pin a specific secret version in the URI, you control promotion explicitly, but you also give up automatic latest-version refresh.

!!! note "Refresh behavior depends on the consumption path"
    Microsoft Learn explicitly promises the automatic restart for active revisions that reference the versionless Key Vault secret in an **environment variable**. It documents secret volume mounts as files, but does not state that those files update in place. For mounted secrets, use a deliberate revision rollout or restart rather than assuming live refresh.

## Practical configuration patterns

### Pattern 1: Inline secret stored in Container Apps

Use this when the value is app-local and you already have a controlled revision rollout process.

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "api-key=<secret-value>"

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars "API_KEY=secretref:api-key"
```

| Command | Why it is used |
|---|---|
| `az containerapp secret set` | Creates or updates an application-level secret. |
| `az containerapp update` | Updates the app template and creates a revision for the environment-variable reference. |
| `--name` | Selects the container app. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--secrets` | Supplies the named application-level secret definition. |
| `--set-env-vars` | Creates the environment variable that points to the secret with `secretref:`. |

### Pattern 2: Key Vault-backed secret with managed identity

Use this when you want centralized secret lifecycle management and auditability.

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "db-password=keyvaultref:https://<key-vault-name>.vault.azure.net/secrets/db-password,identityref:system"

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars "DB_PASSWORD=secretref:db-password"
```

| Command | Why it is used |
|---|---|
| `az containerapp secret set` | Creates or updates an application-level Key Vault reference. |
| `az containerapp update` | Updates the app template and creates a revision for the environment-variable reference. |
| `--name` | Selects the container app. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--secrets` | Supplies the Key Vault URL and managed identity reference. |
| `--set-env-vars` | Creates the environment variable that points to the resolved app secret. |

!!! tip "Use Key Vault references for production defaults"
    Key Vault references reduce secret sprawl inside app configuration and align better with centralized rotation, RBAC, and audit requirements.

## Security design guidance

Use these rules of thumb to avoid duplicating the full identity guidance elsewhere in the repo:

- Prefer **managed identity + Key Vault** for production secrets.
- Use **inline secrets** only when the operational simplicity is worth the manual refresh workflow.
- Keep the **secret definition** and the **container reference** conceptually separate when reviewing revisions.
- Treat **revision restart behavior** as part of your rotation plan, not as an implementation detail.

## Portal view: Secrets blade

![Secrets blade for a Container App showing the description that secrets are valid across all revisions, a Key Value Edit Delete table header, and the No secrets to display empty state](../../assets/platform/identity-and-secrets/03-secrets-blade.png)

[Observed] The blade header reads `<your-app-name> | Secrets` with the subtitle `Container App`. The command bar exposes `Add`, `Refresh`, and `Send us your feedback`. A description paragraph reads "Secrets are key/value pairs that can be used to protect sensitive data like passwords and connection strings. Secrets that you store here will be valid across all your revisions. Note that changing secrets will not create a new revision." A table header lists four columns: `Key`, `Value`, `Edit`, and `Delete`. The central area shows a padlock illustration with the text "No secrets to display." and "Add your first secret." The left navigation shows `Security` highlighted in the Settings group.

[Inferred] The phrase "valid across all your revisions" in the blade description is consistent with the "Secrets are app-scoped, not revision-scoped" note in the [Secret exposure model](#secret-exposure-model) section, which describes the same lifetime: the secret store lives on the app, not on any individual revision. The four-column `Key` / `Value` / `Edit` / `Delete` table header is consistent with the per-entry management surface that the [Inline secrets vs Key Vault references](#inline-secrets-vs-key-vault-references) table assumes — a flat list of named entries that callers reach by `secretRef`, regardless of whether the value is stored inline or sourced from Key Vault. The `Security` highlight under `Settings` is consistent with this page's framing of secrets as a per-app security setting rather than a per-revision deployment artifact.

[Not Proven] The image does not include any populated secret rows, any secret-creation form, any inline-value or Key Vault reference selector, any `keyVaultUrl` or `identity` field, any `secretRef` consumption flow from the [How containers consume secrets](#how-containers-consume-secrets) section, or any evidence of the Key Vault refresh timing described in the [Rotation and refresh behavior](#rotation-and-refresh-behavior) section.

## See Also

- [Security Overview](index.md)
- [Key Vault Secrets Management (Managed Identity)](../identity-and-secrets/key-vault.md)
- [Managed Identity](../identity-and-secrets/managed-identity.md)
- [Secret Rotation](../../operations/secret-rotation/index.md)
- [Identity and Secrets Best Practices](../../best-practices/identity-and-secrets.md)

## Sources

- [Manage secrets in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [Manage environment variables in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/environment-variables)
- [Managed identities in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
