---
hide:
  - toc
---

# Managed Identity Token Errors

Use this query to detect token acquisition and authorization failures related to managed identity usage.

## Data Source

| Table | Schema Note |
|---|---|
| `ContainerAppConsoleLogs_CL` | Legacy schema. If empty, try `ContainerAppConsoleLogs` (non-`_CL`). |

## Query Pipeline

```mermaid
flowchart LR
    A[Filter by app] --> B[Filter identity and token terms] --> C[Project revision and replica] --> D[Sort by time]
```

## Query

```kusto
let AppName = "my-container-app";
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("ManagedIdentityCredential", "token", "CredentialUnavailable", "403", "401", "Forbidden")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

## Example Output

| TimeGenerated | RevisionName_s | Log_s |
|---|---|---|
| 2026-04-04T12:54:24.880Z | ca-myapp--0000001 | {"timestamp":"...","level":"INFO","message":"DefaultAzureCredential acquired a token from ManagedIdentityCredential"} |
| 2026-04-04T12:54:24.880Z | ca-myapp--0000001 | {"timestamp":"...","level":"ERROR","message":"Blob read failed with 403 Forbidden"} |
| 2026-04-04T12:54:24.880Z | ca-myapp--0000001 | {"timestamp":"...","level":"ERROR","message":"CredentialUnavailable: Managed identity endpoint unavailable"} |

## Interpretation Notes

- `CredentialUnavailable` suggests identity endpoint/config issue.
- `403` with token success usually means RBAC scope mismatch.
- Normal pattern: low noise token logs and no persistent auth errors.

## Limitations

- Requires app SDK logs to include identity details.
- Cannot alone determine exact missing role assignment.

## See Also

- [Secret Reference Failures](secret-reference-failures.md)
- [Managed Identity Auth Failure Playbook](../../playbooks/identity-and-configuration/managed-identity-auth-failure.md)
