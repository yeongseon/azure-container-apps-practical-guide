# Lab: Managed Identity Key Vault Failure

Reproducible bounded-falsification lab for Azure Container Apps workloads that use a system-assigned managed identity to read a Key Vault secret at request time.

The reusable Jun 26 cohort in `evidence/` captures the failure on `ca-labkv-b3erju` in `rg-aca-lab-kv`. H1 shows the app returning HTTP 500 with `ForbiddenByRbac` while the active revision stays Healthy / Provisioned / Running because no `Key Vault Secrets User` role exists at the vault scope. H2 shows `ca-labkv-b3erju--0000002` recovering after the vault-scoped role assignment plus a revision restart.

The lab tests two hypotheses:

1. **H1 — Trigger produces failure.** A Container App using a system-assigned managed identity to read a Key Vault secret returns HTTP 500 with `ForbiddenByRbac` when the principal lacks `Key Vault Secrets User` at the vault scope, even though the revision surface remains healthy.
2. **H2 — Fix restores recovery.** Assigning `Key Vault Secrets User` at the Key Vault scope and starting a new revision restores HTTP 200 on `/health` with the secret-length payload.

This evidence pack falsifies the hypothesis within a bounded scope. Gate 17 demonstrates that the presence versus absence of the `Key Vault Secrets User` assignment at the Key Vault scope is the mechanically observable trigger field. The pack does **not** prove image byte identity, pod UID continuity, exact RBAC propagation timing, or token-cache-only recovery; those ceilings are carried explicitly in `cohort_binding_note.explicit_drops`.

## Structure

```text
labs/managed-identity-key-vault-failure/
├── infra/main.bicep        # Baseline environment + app deployment
├── fix-and-capture.sh      # Phase A live reproduction: deploy/reuse RG, capture 12 raw files, apply H2, run verify.sh, and clean up
├── verify.sh               # Phase B offline verifier: 17 gates total, 4 derived gate JSONs emitted
├── workload/               # Flask + Gunicorn workload that reads Key Vault at request time
├── evidence/               # 12 raw files + 4 derived gate JSONs + evidence README
└── README.md               # This lab overview and claim-ceiling disclosure
```

## Cohort summary

- **Resource group:** `rg-aca-lab-kv`
- **Container app:** `ca-labkv-b3erju`
- **Region:** `koreacentral`
- **Base name:** `labkv`
- **Key Vault:** `kv-labkv-b3erju`
- **Principal ID:** `00000000-0000-0000-0000-000000000000` (masked)
- **Bounded trigger field:** presence versus absence of the `Key Vault Secrets User` assignment at the Key Vault scope
- **Held constant fields:** app name, resource group, image tag `acrlabkvb3erju.azurecr.io/ca-labkv-b3erju:v1`, `KEY_VAULT_URL`, `SECRET_NAME`, CPU `0.5`, memory `1Gi`, ingress targetPort `8000`

## Evidence pack

See [`evidence/README.md`](evidence/README.md) for the 16-file index, capture purposes, and gate descriptions.

## File index

| File | Purpose |
|---|---|
| `infra/main.bicep` | Baseline infrastructure for reproducible redeploys |
| `fix-and-capture.sh` | Live Phase A trigger + fix + capture workflow |
| `verify.sh` | Offline 17-gate verifier that emits Gate 14-17 JSONs |
| `evidence/README.md` | Evidence tour and 16-file index |
| `README.md` | Lab overview and bounded-falsification framing |

## Reproducibility

The committed Phase B verifier is hermetic:

| Command | Why it is used |
|---|---|
| `cd labs/managed-identity-key-vault-failure/` | Enters the lab directory so the relative evidence paths resolve correctly. |
| `bash verify.sh` | Recomputes Gate 14 through Gate 17 from the committed evidence cohort without touching Azure. |

```bash
cd labs/managed-identity-key-vault-failure/
bash verify.sh
```

The live script exists for future reproductions and regenerates the raw evidence before calling the hermetic verifier:

| Command | Why it is used |
|---|---|
| `cd labs/managed-identity-key-vault-failure/` | Enters the lab directory for the live capture workflow. |
| `bash fix-and-capture.sh` | Recreates the raw H1/H2 evidence cohort from Azure, sanitizes it, runs the offline verifier, and starts RG cleanup. |

```bash
cd labs/managed-identity-key-vault-failure/
bash fix-and-capture.sh
```

## Documentation cross-reference

- Lab guide: [`docs/troubleshooting/lab-guides/managed-identity-key-vault-failure.md`](../../docs/troubleshooting/lab-guides/managed-identity-key-vault-failure.md)
- Evidence tour: [`evidence/README.md`](evidence/README.md)
