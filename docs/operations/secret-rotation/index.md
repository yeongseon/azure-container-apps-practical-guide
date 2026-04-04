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

Design applications to re-read credentials on restart so a new revision can apply fresh secret values deterministically.

## Key Vault Integration for Automatic Rotation

Best-practice flow:

1. Rotate secret in Key Vault.
2. Update secret version reference or allow latest-version policy.
3. Trigger app/job revision rollout.
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

Use revisions to avoid hard cutovers:

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "db-conn=<new-connection-string>"
```

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars "DB_CONNECTION=secretref:db-conn"
```

Then shift traffic gradually to the new healthy revision.

## Monitoring Secret Expiry

Operational controls:

- Alert before certificate/client-secret expiry (30/14/7 days)
- Track authentication failure spikes after rotation windows
- Audit Key Vault secret version changes and access logs

Document secret owners and rotation cadence per dependency.

## See Also

- [Identity and Secrets](../../platform/identity-and-secrets/managed-identity.md)
- [Alerts](../alerts/index.md)
- [Recovery and Incident Readiness](../recovery/index.md)
