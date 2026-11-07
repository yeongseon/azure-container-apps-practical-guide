---
content_sources:
  diagrams:
    - id: enable-system-assigned-managed-identity
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
        - https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
        - https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-access-policy
content_validation:
  status: verified
  last_reviewed: 2026-11-07
  reviewer: agent
  core_claims:
    - claim: Azure Container Apps supports both system-assigned and user-assigned managed identities.
      source: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
      verified: true
    - claim: When a managed identity is added, deleted, or modified on a running container app, the app does not automatically restart and a new revision is not created.
      source: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
      verified: true
    - claim: A managed identity alone does not grant resource access; the target resource must authorize the identity, for example through an Azure RBAC role assignment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
      verified: true
    - claim: Updating an inline Container Apps secret requires a new revision or an existing-revision restart before running revisions use the updated value.
      source: https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
      verified: true
    - claim: Before deleting a Container Apps secret, an operator must deploy a revision without its reference and deactivate every revision that still references it.
      source: https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
      verified: true
    - claim: Azure RBAC is the recommended Key Vault data-plane authorization model, while Key Vault access policies remain a legacy alternative.
      source: https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-access-policy
      verified: true
---
# Security Operations

This guide covers daily and periodic security operations: managed identity lifecycle, secret rotation, and Easy Auth policy management.

## Prerequisites

- A user-assigned or system-assigned managed identity strategy
- Secret owners and rotation intervals documented

```bash
export RG="rg-myapp"
export APP_NAME="ca-myapp"
export ACA_ENV_NAME="cae-myapp"
```

## Managed Identity Operations

Enable system-assigned managed identity:

<!-- diagram-id: enable-system-assigned-managed-identity -->
```mermaid
flowchart TD
    accTitle: Enable and verify a system-assigned managed identity
    accDescr: An operator enables the app-owned identity and records its principal ID. A security administrator grants a least-privilege role at the target scope. Application code then requests a resource-scoped token from the local identity endpoint and sends it to the target service. The target separately evaluates authorization. Changing identity configuration does not restart the app or create a revision.

    subgraph CONTROL["Configuration and authorization"]
        OPERATOR["Operator"]
        APP_RESOURCE["Container app resource"]
        SYSTEM["System-assigned identity<br/>app-owned lifecycle"]
        PRINCIPAL["Principal ID<br/>security principal"]
        ROLE_DEF["Role definition<br/>allowed operations"]
        TARGET_SCOPE["Target scope<br/>resource or resource group"]
        ROLE["Role assignment<br/>principal + role + scope"]
        OPERATOR -->|"1  Enable identity"| APP_RESOURCE
        APP_RESOURCE -->|"2  Create or expose"| SYSTEM
        SYSTEM -->|"3  Record"| PRINCIPAL
        PRINCIPAL -->|"4  Bind principal"| ROLE
        ROLE_DEF -->|"Bind permissions"| ROLE
        TARGET_SCOPE -->|"Bind boundary"| ROLE
    end

    subgraph IDENTITY_SERVICE["External identity service"]
        ENTRA["Microsoft Entra ID<br/>token issuer"]
    end

    subgraph RUNTIME["Runtime verification"]
        CODE["Application code"]
        ENDPOINT["Local identity endpoint"]
        TARGET["Target Azure service"]
        AUTHZ{"Role or service policy<br/>allows operation?"}
        SUCCESS["Operation succeeds"]
        FAILURE["Authorization failure"]
        CODE ==>|"5  Local token request"| ENDPOINT
        ENDPOINT ==>|"6  Token acquisition"| ENTRA
        ENTRA ==>|"7  Access token"| ENDPOINT
        ENDPOINT ==>|"8  Token response"| CODE
        CODE ==>|"9  Authenticated service request + token"| TARGET
        TARGET -->|"evaluate"| AUTHZ
        AUTHZ -->|"Allowed"| SUCCESS
        AUTHZ -.->|"Denied"| FAILURE
    end

    SYSTEM -.->|"selected identity"| ENDPOINT
    ROLE -.->|"authorization input"| AUTHZ
    NO_REV["Identity configuration change<br/>no automatic restart or new revision"]
    APP_RESOURCE -.-> NO_REV

    LEGEND["Arrow key<br/>thick = token or service transport<br/>solid = configuration or authorization result<br/>dotted = identity, policy, lifecycle note, or denied result"]
```

*Figure: Operational separation between configuring **who** the app is, authorizing **what** it may do at a target scope, and verifying token/service transport. Identity assignment itself does not restart the app or create a revision.*

!!! warning "Identity and secret changes must be auditable"
    Apply security operations through automation and change records.
    Ad-hoc portal changes make incident forensics difficult.

```bash
az containerapp identity assign \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --system-assigned
```

| Command | Why it is used |
|---|---|
| `az containerapp identity assign` | Enables the system-assigned identity. |
| `--name "$APP_NAME"` | Selects the container app. |
| `--resource-group "$RG"` | Selects the resource group. |
| `--system-assigned` | Creates or enables the app-owned identity. |

Check principal details:

```bash
az containerapp identity show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp identity show` | Reads assigned identity details. |
| `--name "$APP_NAME"` | Selects the container app. |
| `--resource-group "$RG"` | Selects the resource group. |
| `--output json` | Preserves the identity object structure for review. |

Example output (PII masked):

```json
{
  "type": "SystemAssigned",
  "principalId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "<tenant-id>"
}
```

Grant least-privilege role assignment:

```bash
az role assignment create \
  --assignee-object-id "<object-id>" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/<key-vault-name>"
```

| Command | Purpose |
|---|---|
| `az role assignment create` | Grants the app identity the Azure RBAC permission required to read secrets from Key Vault during runtime or rotation workflows. |
| `--assignee-object-id "<object-id>"` | Targets the managed identity object directly so access is bound to the workload, not to an operator account. |
| `--assignee-principal-type ServicePrincipal` | Identifies the managed identity's Microsoft Entra principal type. |
| `--role "Key Vault Secrets User"` | Chooses the least-privilege read role needed for secret retrieval rather than a broader vault management role. |
| `--scope "/subscriptions/.../vaults/<key-vault-name>"` | Restricts access to one vault, which contains blast radius if other vaults exist in the same resource group. |

## Secret Operations

Set or rotate secret values in Container Apps configuration:

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "db-connection=<redacted-secret>"
```

| Command | Purpose |
|---|---|
| `az containerapp secret set` | Adds or rotates an app-level secret in the Container Apps secret store without hardcoding it in the revision template. |
| `--name "$APP_NAME"` | Selects the container app. |
| `--resource-group "$RG"` | Selects the resource group. |
| `--secrets "db-connection=<redacted-secret>"` | Defines the secret by name, which is the identifier your environment variables or scale-rule auth mappings will reference later. |

Reference the secret as an environment variable in app template updates.

After rotating an inline Container Apps secret, deploy a new revision or restart an existing revision before expecting running replicas to use the new value. For a versionless Key Vault reference used by an environment variable, Container Apps instead retrieves a newer version within 30 minutes and restarts active referencing revisions.

Before deleting any Container Apps secret, deploy a revision that no longer references the secret, then deactivate every older revision that still references it. Delete the secret only after those dependencies are removed.

## Security Operations Cadence

| Operation | Suggested Frequency | Validation Signal |
|---|---|---|
| Managed identity review | Monthly | Unused roles removed |
| Secret rotation | Per organization policy | Apps remain healthy after the required revision deployment, restart, or Key Vault reference refresh |
| Easy Auth policy review | Monthly or after app route changes | Unauthorized access paths denied |
| RBAC scope audit | Quarterly | Least-privilege posture maintained |

!!! tip "Rotate secrets with staged rollout"
    Introduce new values, validate app health, then retire old values to avoid abrupt runtime failures.

### Portal view: Access control (IAM) blade

![Access control (IAM) blade for a Container App showing the Check access tab](../../assets/platform/identity-and-secrets/04-iam-blade.png)

[Observed] The blade header reads `ca-sample-d38538 | Access control (IAM)` with the subtitle `Container App`. The command bar exposes `+ Add`, `Download role assignments`, `Edit columns`, `Refresh`, `Delete`, and `Feedback` controls. Four tabs are rendered: `Check access` (selected), `Role assignments`, `Roles`, and `Deny assignments`. The selected tab shows a `My access` section with a `View my access` button, a `Check access` section with a `Check access` button, and three cards titled `Grant access to this resource` (with an `Add role assignment` button), `View access to this resource` (with a `View` button), and `View deny assignments` (with a `View` button). The left navigation lists `Overview`, `Activity log`, `Access control (IAM)` (highlighted), `Tags`, `Diagnose and solve problems`, `Resource visualizer`, and grouped sections for `Application`, `Settings`, `Networking`, `Security`, `Monitoring`, `Automation`, and `Help`.

[Inferred] The four tabs (`Check access`, `Role assignments`, `Roles`, `Deny assignments`) and the three cards (`Grant access`, `View access`, `View deny assignments`) appear to map to the RBAC scope-audit cadence described in the table above. The `+ Add` command and the `Add role assignment` card button are consistent with the role-creation surface invoked by `az role assignment create` shown in the Managed Identity Operations section.

[Not Proven] The screenshot does not include any `Role assignments` tab content, so the captured surface does not reveal which principals or roles are bound to this Container App. The `Check access` and `View my access` buttons are present but their result panels are not visible in this capture, so the rendered shape of those panels is outside the scope of this image.

## Easy Auth Operations

Review and enforce authentication settings:

```bash
az containerapp auth show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp auth show` | Reads the app's authentication configuration. |
| `--name "$APP_NAME"` | Selects the container app. |
| `--resource-group "$RG"` | Selects the resource group. |
| `--output json` | Preserves the authentication configuration structure. |

Update auth to require login by default:

```bash
az containerapp auth update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --enabled true \
  --unauthenticated-client-action Return401
```

| Command | Why it is used |
|---|---|
| `az containerapp auth update` | Updates the app's unauthenticated-request behavior. |
| `--name "$APP_NAME"` | Selects the container app. |
| `--resource-group "$RG"` | Selects the resource group. |
| `--enabled true` | Enables the platform authentication module. |
| `--unauthenticated-client-action Return401` | Rejects unauthenticated requests with HTTP 401 instead of redirecting them. |

## Verification Steps

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query identity \
  --output json

az containerapp auth show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp show` | Reads the container app resource for identity verification. |
| `--name "$APP_NAME"` | Selects the container app for each command. |
| `--resource-group "$RG"` | Selects the resource group for each command. |
| `--query identity` | Limits the first command to the app's managed identity configuration. |
| `--output json` | Preserves structured output for each command. |
| `az containerapp auth show` | Reads the separate Easy Auth child-resource configuration. |

Example output (PII masked):

```json
{
  "type": "SystemAssigned",
  "principalId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "<tenant-id>"
}
```

```json
{
  "platform": {
    "enabled": true
  },
  "globalValidation": {
    "unauthenticatedClientAction": "Return401"
  }
}
```

## Troubleshooting

### Managed identity token requests fail

- Confirm identity is assigned to the app.
- Verify target resource role assignment scope.
- Wait for RBAC propagation, then retry.

### Easy Auth blocks expected traffic

- Validate allowed redirect URI and issuer configuration.
- Exclude health endpoints from auth if required by probes.

## Advanced Topics

- Use user-assigned identities for shared access policies.
- Rotate secrets via Key Vault references and automation.
- Add policy enforcement with Azure Policy for auth and identity baselines.

## See Also
- [Networking](../networking/index.md)
- [Observability](../../operations/monitoring/index.md)
- [Managed Identity Recipe](managed-identity.md)
- [Easy Auth Recipe](easy-auth.md)

## Sources
- [Container Apps security](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [Managed identity in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
- [Azure RBAC versus Key Vault access policies](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-access-policy)
