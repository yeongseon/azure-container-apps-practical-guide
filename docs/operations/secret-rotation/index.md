---
description: Rotate Azure Container Apps inline and Key Vault-backed secrets safely with refresh, revision, validation, traffic-shift, and retirement procedures.
content_sources:
  diagrams:
    - id: secret-rotation-lifecycle
      type: sequence
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
---
# Secret Rotation

Secret rotation in Container Apps should be planned as an operational routine, not an emergency-only action. This guide outlines secure rotation patterns with minimal downtime.

## Secret Types in Container Apps

Container Apps supports two common secret patterns:

- **Manual secret values** stored directly in Container Apps configuration
- **Key Vault references** resolved from Azure Key Vault

Manual secrets are simple but require explicit update workflows. Key Vault references improve central governance and auditing.

## Rotation Strategies

Use one of these patterns based on dependency behavior:

1. **Dual secret versioning** (active + next)
2. **Blue/green secret cutover** via new revision
3. **Rolling replacement** with health-validated traffic shifting

Design applications to re-read credentials on restart so a restarted or new revision can apply fresh secret values deterministically.

## Key Vault Integration for Automatic Rotation

Best-practice flow:

1. Rotate secret in Key Vault.
2. For a version-pinned URI, update the Container Apps reference; for a versionless URI, allow the platform refresh cycle to retrieve the latest version.
3. For an inline update or version-pinned reference change, restart an existing revision or deploy a new revision. A versionless Key Vault reference is refreshed automatically within the documented refresh window, and active revisions that consume it through environment variables are restarted.
4. Validate authentication and transaction success.

Grant managed identity the minimum required Key Vault permissions.

## Connection String Rotation Patterns

For data stores that support multiple active credentials:

- Create new credential first.
- Deploy with new secret while old credential remains valid.
- Confirm successful reads/writes.
- Revoke old credential after validation window.

For single-credential systems, schedule maintenance window and prepare rollback credential artifacts.

## Zero-Downtime Secret Updates

Updating an app-level secret does not create a revision. After an inline-secret or version-pinned reference update, either restart each active revision that consumes the secret or explicitly copy a revision when you need an independently testable rollout point. The example below chooses the second path. Because single-revision mode is the default and moves traffic after a new revision becomes ready, first enable multiple-revision mode and pin traffic to the current revision.

```bash
export OLD_REVISION=$(az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "[?properties.active].name | [0]" \
  --output tsv)

az containerapp revision set-mode \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --mode multiple

az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$OLD_REVISION=100"

az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "db-conn=<new-connection-string>"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp ingress traffic set` | Pins application traffic to the captured known-good revision before the new revision is created. |
| `az containerapp revision list` | Captures the active revision name before changing revision mode. |
| `az containerapp revision set-mode` | Enables multiple active revisions for canary testing and traffic splitting. |
| `az containerapp secret set` | Runs `az containerapp secret set` for this documented operation. |
| `--mode` | Selects multiple-revision mode. |
| `--name` | Selects the named resource for this operation. |
| `--output` | Returns the captured revision name as plain text. |
| `--query` | Selects the current active revision name. |
| `--resource-group` | Selects the resource group containing the resource. |
| `--revision-weight` | Pins 100% of application traffic to the known-good revision. |
| `--secrets` | Defines or updates the named app-level secret. |

```bash
export ROTATION_SUFFIX="secret-$(date -u +%Y%m%d%H%M%S)"

az containerapp revision copy \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --from-revision "$OLD_REVISION" \
  --revision-suffix "$ROTATION_SUFFIX"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp revision copy` | Runs `az containerapp revision copy` for this documented operation. |
| `--from-revision` | Copies the captured known-good revision rather than whichever revision happens to be latest. |
| `--name` | Selects the named resource for this operation. |
| `--resource-group` | Selects the resource group containing the resource. |
| `--revision-suffix` | Assigns a unique suffix to the copied revision. |

The explicit `revision copy` action creates the rollout target; the app-level secret update does not. Smoke test the copied revision through its revision-specific endpoint before shifting traffic gradually to `${APP_NAME}--${ROTATION_SUFFIX}`.

## Monitoring Secret Expiry

Operational controls:

- Alert before certificate/client-secret expiry (30/14/7 days)
- Track authentication failure spikes after rotation windows
- Audit Key Vault secret version changes and access logs

Document secret owners and rotation cadence per dependency.

## Secret Rotation Lifecycle

The sequence distinguishes the automatic refresh path for a versionless Key Vault reference from an explicit inline-secret or version-pinned update. In both paths, retire the old backing credential only after the new value is serving verified requests.

<!-- diagram-id: secret-rotation-lifecycle -->
```mermaid
sequenceDiagram
    accTitle: Secret rotation, refresh, validation, and retirement
    accDescr: Operations creates a new credential in Key Vault. The Container Apps control plane refreshes a versionless Key Vault reference and restarts active revisions that consume it as an environment variable. An inline secret or version-pinned reference requires an explicit app-level update followed by a revision restart or an explicit revision copy. Operations tests the restarted or copied revision before the control plane shifts traffic and before revoking the old credential.
    participant Ops as Operations Team
    participant KV as Azure Key Vault
    participant ACA as Container Apps control plane
    participant Rev as Active or new revision
    participant Dep as Protected dependency
    Ops->>KV: Create new backing credential or secret version
    KV-->>Ops: New version available
    alt Versionless Key Vault reference
        KV-->>ACA: Latest value retrieved within refresh window
        ACA->>Rev: Restart active revisions using env secretref
    else Inline secret or version-pinned reference
        Ops->>ACA: Update secret value or version URI
        Ops->>ACA: Restart active revision or explicitly copy revision
        ACA->>Rev: Start with updated secretref value
    end
    Ops->>Rev: Run readiness and smoke tests
    Rev->>Dep: Authenticated test request
    Dep-->>Rev: Success or failure response
    Rev-->>Ops: Test evidence
    Ops->>ACA: Shift traffic when using a new revision
    Ops->>Dep: Revoke old backing credential after validation
```

*Figure: Solid sequence messages are operations or platform actions; dashed returns originate from the system providing the value, response, or evidence. The automatic path applies to a versionless Key Vault reference. It does not mean every inline-secret update creates a revision.*

To delete an inline Container Apps secret, first deploy a revision that no longer references it, deactivate every revision that still contains the reference, and only then delete the secret. Updating and deleting are different operations; do not model deletion as a normal rotation overwrite.

## Rotation Pattern Decision Matrix

| Pattern | Downtime Risk | Complexity | Best Fit |
|---|---|---|---|
| Dual secret versioning | Low | Medium | Services supporting parallel credentials |
| Blue/green cutover | Low | Medium | User-facing APIs requiring traffic control |
| Immediate replacement | Medium/High | Low | Non-critical internal tools only |

!!! tip "Use revision-based cutover for safer rotations"
    A secret update does not create a revision by itself. After the update, create an independently testable revision through a revision-scope change when you need readiness checks, traffic shifting, and a clean rollback point.

!!! warning "Do not revoke old credentials immediately"
    Keep the previous credential active until post-rotation validation confirms successful reads/writes and no authentication errors.

### Version-Pinned Key Vault Reference Example

Use this explicit rollout only when the Key Vault URI includes a version. A versionless URI follows the automatic refresh path: Container Apps retrieves the latest version within 30 minutes and automatically restarts active revisions that consume the secret through environment variables. Before running this example, complete the multiple-revision mode and known-good traffic pinning steps in [Zero-Downtime Secret Updates](#zero-downtime-secret-updates).

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "db-conn=keyvaultref:https://<key-vault-name>.vault.azure.net/secrets/db-conn/<version>,identityref:system"

export ROTATION_SUFFIX="secret-$(date -u +%Y%m%d%H%M%S)"

az containerapp revision copy \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --from-revision "$OLD_REVISION" \
  --revision-suffix "$ROTATION_SUFFIX"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp revision copy` | Explicitly creates a revision from the captured known-good revision after the app-level reference is updated; the preceding secret update does not create this revision. |
| `az containerapp secret set` | Updates the app-level reference to the selected Key Vault version; this command does not create a revision. |
| `--from-revision` | Copies the captured known-good revision rather than whichever revision happens to be latest. |
| `--name` | Selects the Container App whose captured known-good revision is copied. |
| `--resource-group` | Selects the resource group containing the app. |
| `--revision-suffix` | Assigns a unique suffix to the copied revision so operators can identify the rotation rollout target. |
| `--secrets` | Defines or updates the named app-level secret. |

### Post-Rotation Verification Checklist

| Check | Command | Expected Result |
|---|---|---|
| Explicit revision copy completed | `az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table` | A revision ending in `$ROTATION_SUFFIX` exists and is healthy |
| Auth errors not increasing | `az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console --follow false` | No spike in auth failures |
| Traffic served by new revision | `az containerapp ingress traffic show --name "$APP_NAME" --resource-group "$RG" --output table` | Target revision receives expected weight |
| Old secret can be retired | Key Vault audit review | No calls using old version |

### Rotation Run Command Set

```bash
az containerapp secret list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table

az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp revision list` | Verifies that the separate `revision copy` action created the intended rollout target and that its health state is ready for testing. |
| `az containerapp secret list` | Runs `az containerapp secret list` for this documented operation. |
| `--name` | Selects the Container App whose revisions are listed. |
| `--output` | Keeps both checks easy to scan during a live rotation window. |
| `--resource-group` | Selects the resource group containing the app. |

## Portal Walkthrough

Use the Azure Portal to inspect the four surfaces involved in a Key Vault-backed rotation: the Key Vault secrets list, the secret versions blade, the Container App secrets blade, and the Revisions and replicas blade. Capture screenshots at each step so the rotation can be audited after the fact.

### Portal view: Key Vault Secrets list

From the Azure Portal home, open the Key Vault that holds the application credential (`kv-ops-cgedjv` in this lab), then select **Objects → Secrets** in the left navigation.

![Key Vault Secrets blade showing demo-db-password with Status Enabled](../../assets/operations/secret-rotation/01-key-vault-secrets-blade.png)

[Observed] The blade header is `kv-ops-cgedjv | Secrets` under the **Key vault** resource type. The command bar exposes `Generate/Import`, `Refresh`, `Restore Backup`, `Manage deleted secrets`, and `View sample code`. The grid columns are `Name`, `Type`, `Status`, and `Expiration date`. One row is present: `demo-db-password` with Status `✓ Enabled` and empty `Type` and `Expiration date` cells.

[Inferred] The single enabled secret indicates that Key Vault is the central source of truth for the application's database credential, matching the Key Vault reference pattern recommended in **Key Vault Integration for Automatic Rotation** above. The empty `Expiration date` column means no expiry policy is set on this secret, which is the operational risk that the **Monitoring Secret Expiry** section instructs you to alert on.

[Not Proven] This blade does not show which Container App or revision currently resolves this secret, nor which managed identity has `Get` permission on the vault. Those bindings must be verified separately on the Container App secrets blade and the Key Vault `Access policies` (or RBAC) blade.

### Portal view: Secret Versions

From the Secrets list, click `demo-db-password` to open the per-secret **Versions** blade.

![demo-db-password Versions blade with one Current version and one Older version both Enabled](../../assets/operations/secret-rotation/02-secret-versions.png)

[Observed] The breadcrumb reads `Home > kv-ops-cgedjv | Secrets`, with blade title `demo-db-password` under the `Versions` subtitle. The command bar shows `New Version`, `Refresh`, `Delete`, and `Download Backup`. Two sections are visible: `CURRENT VERSION` lists version `08cbe3bc0a1249b682436d24f2b4b070` with Status `✓ Enabled`, and `OLDER VERSIONS` lists version `7cb357926e0940e5a89e96c0ebe339ed` also with Status `✓ Enabled`. Both `Activation date` and `Expiration date` columns are empty for both versions.

[Inferred] Two versions of the same secret are simultaneously `Enabled`, which is the dual-version state required by the **Dual secret versioning** strategy and by the warning **Do not revoke old credentials immediately**. The newer version is promoted to `CURRENT` (used by `keyvaultref:` references without an explicit version), while the older version remains resolvable for any workload still pinned to that specific version GUID. Once the post-rotation validation window in the **Post-Rotation Verification Checklist** completes, the older version should be disabled (not deleted) using the toggle reachable from this blade.

[Not Proven] The Versions blade does not show which Container App revisions or replicas are actively reading each version. The fact that the older version is `Enabled` does not prove any workload is still calling it — to confirm that, correlate Key Vault audit logs (`AzureDiagnostics | where ResourceProvider == "MICROSOFT.KEYVAULT"`) with the revision in capture 04.

### Portal view: Container App Secrets

In the same subscription, open the Container App (`ca-ops-cgedjv`) and select **Security → Secrets** in the left navigation.

![Container App Secrets blade with empty state No secrets to display](../../assets/operations/secret-rotation/03-container-app-secrets-blade.png)

[Observed] The blade header is `ca-ops-cgedjv | Secrets` under the **Container App** resource type. The command bar shows `Add`, `Refresh`, and `Send us your feedback`. The page caption reads "Secrets are key/value pairs that can be used to protect sensitive data like passwords and connection strings. Secrets that you store here will be valid across all your revisions. Note that changing secrets will not create a new revision." The grid columns are `Key`, `Value`, `Edit`, and `Delete`. An empty-state icon is displayed with the text `No secrets to display. Add your first secret.` and an `Add` button.

[Inferred] The empty list confirms only that this view contains no app-level secret entries. It does not prove that the application uses a Key Vault reference elsewhere. The caption "changing secrets will not create a new revision" is the operational warning behind **Zero-Downtime Secret Updates**: after an inline update or a pinned-reference change, restart a revision or make a revision-scope change to create a validation target. A versionless Key Vault reference follows the platform refresh behavior described above.

[Not Proven] This blade does not display the environment variable bindings on the container definition or whether each `secretref:` resolves to a `keyvaultref:` or to a literal value defined elsewhere. To verify the actual binding, inspect `properties.template.containers[].env` via `az containerapp show` or open the **Containers** blade.

### Portal view: Revisions and replicas

From the Container App overview, select **Application → Revisions and replicas** in the left navigation to confirm which revision is currently serving traffic.

![Revisions and replicas blade showing one Running active revision with 100 percent traffic](../../assets/operations/secret-rotation/04-revisions-blade.png)

[Observed] The blade header is `ca-ops-cgedjv | Revisions and replicas`. The command bar shows `Create new revision`, `Save`, `Refresh`, `Deployment mode`, and `Send us your feedback`. The page caption reads "Each revision is an immutable snapshot of your container app, and can have different setups for traffic allocation, container images, autoscaling, or Dapr." Three tabs are visible: `Active revisions`, `Inactive revisions`, `Replicas`. The `Active revisions` tab shows one row: Name `ca-ops-cgedjv--dkckziz`, Date created `6/3/2026, 8:26:15 PM`, Running status `✓ Running` with a `View details` link, `View Logs` `Show Logs`, `Label` column empty, `Traffic` `100`%, `Replicas` `1 (Show replicas)`.

[Inferred] A single active revision is serving 100% of traffic, which is a possible baseline before rotation. A revision-scope update can create a second row for an independently testable revision; the `Traffic` column is then the control surface used for a blue/green cutover. The empty `Label` column means no traffic label is assigned in this capture, but labels are optional rather than a prerequisite for revision-weight traffic shifting.

[Not Proven] This blade does not display the Key Vault secret version that the running replica resolved at startup, nor the value of any `secretref:` environment variable. The Revisions and replicas blade alone cannot prove that a rotation occurred — it must be cross-checked with the `CURRENT VERSION` GUID from capture 02 and the revision's environment variable bindings from the **Containers** blade.

## See Also

- [Identity and Secrets](../../platform/identity-and-secrets/managed-identity.md)
- [Alerts](../alerts/index.md)
- [Recovery and Incident Readiness](../recovery/index.md)

## Sources

- [Manage secrets in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [Use managed identity in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
