# Evidence pack — `managed-identity-key-vault-failure` lab

This directory carries the Jun 26 raw evidence cohort for the `managed-identity-key-vault-failure` lab plus the derived Phase B gate outputs emitted by `labs/managed-identity-key-vault-failure/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what this single `koreacentral` reproduction can support about the `ForbiddenByRbac` managed-identity failure on `ca-labkv-b3erju`, the recovered `0000002` revision, and the bounded causal claim that the presence versus absence of the `Key Vault Secrets User` role assignment at the Key Vault scope is the mechanically observable trigger field.

## Capture timeline

1. **H1 failure surface.** `01-app-identity-pre-fix.json` through `08-kql-console-logs-pre-fix.json` capture the system-assigned identity, empty pre-fix role surface, RBAC-mode vault configuration, active healthy revision, failing `/health` body, system logs, full app spec, and KQL console-log context.
2. **H2 recovery surface.** `09-role-assignment-post-fix.json` through `12-kql-recovery-summary-post-fix.json` capture the scoped role assignment, successful `/health` body, new revision, and post-fix KQL reason summary.
3. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, temporal boundedness, lineage coherence, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves the pre-fix state had no `Key Vault Secrets User` assignment at the vault scope and that `/health` failed with `ForbiddenByRbac` while the revision stayed healthy.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves the post-fix state had the scoped role assignment, a successful HTTP 200 body, and a newer healthy revision with clean startup/readiness summary rows on the recovered revision only (older revisions may still show `ProbeFailed` entries).
- **Gate 17 — `17-bounded-falsification-gate.json`**: bounds the causal claim to role-assignment presence at Key Vault scope and explicitly lists the unsupported inferences.

## Honest disclosure

- The pack captures a single live Azure cohort from Jun 26 2026; it is not a statistical sample across regions or tenants.
- `06-system-logs-pre-fix.json` is JSONL/NDJSON, not a JSON array; `verify.sh` parses it one record per line.
- `08-kql-console-logs-pre-fix.json` does not contain request-body smoking-gun text because the Flask handler does not emit application logs for the caught exception. The smoking gun is the captured HTTP 500 body in `05-http-response-pre-fix.json`.
- The pack does not capture image digests, pod UID continuity, exact RBAC propagation latency, or token-cache-only recovery. Those gaps are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.

## File index

| File | Purpose |
|---|---|
| `01-app-identity-pre-fix.json` | Pre-fix system-assigned identity surface |
| `02-role-assignments-pre-fix.json` | Pre-fix assignee role list showing no Key Vault Secrets User at vault scope |
| `03-kv-rbac-config.json` | Key Vault RBAC-mode configuration |
| `04-revision-list-pre-fix.json` | Active healthy pre-fix revision carrying the failing app image |
| `05-http-response-pre-fix.json` | Pre-fix HTTP 500 response body with `ForbiddenByRbac` |
| `06-system-logs-pre-fix.json` | Raw system-log capture around the reproduction window |
| `07-containerapp-spec-pre-fix.yaml` | Full pre-fix container app spec |
| `08-kql-console-logs-pre-fix.json` | KQL console-log context around the failure window |
| `09-role-assignment-post-fix.json` | Post-fix vault-scoped `Key Vault Secrets User` role assignment |
| `10-http-response-post-fix.json` | Post-fix HTTP 200 success response |
| `11-revision-list-post-fix.json` | Post-fix recovered revision with `RESTART_TOKEN` |
| `12-kql-recovery-summary-post-fix.json` | Post-fix KQL reason summary by revision |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Cohort summary

- **Deployment date:** 2026-06-26
- **Resource group:** `rg-aca-lab-kv`
- **Region:** `koreacentral`
- **Container app:** `ca-labkv-b3erju`
- **Key Vault:** `kv-labkv-b3erju`
- **Principal ID:** `00000000-0000-0000-0000-000000000000` (masked)
- **Raw capture count:** 12
- **Derived gate count:** 4

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/managed-identity-key-vault-failure/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort without touching Azure. |

```bash
cd labs/managed-identity-key-vault-failure/
bash verify.sh
```

The verifier reads only the committed files in this directory, emits four gate JSONs, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
