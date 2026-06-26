# Evidence pack — `zone-redundancy-best-effort` lab

This directory contains the committed Jun 12-Jun 14 reproduction corpus for the `zone-redundancy-best-effort` lab plus the four derived Phase B gate outputs emitted by `labs/zone-redundancy-best-effort/verify.sh`.

The claim ceiling is intentionally narrow. The corpus supports a **non-falsification with bounded coverage** verdict for one fixed 24-hour baseline and three deterministic perturbations against `app-min3`; it does **not** generalize beyond the two client-bearing `10 RPS / 180 s` runs, and it does **not** prove per-replica Availability Zone identity or platform-internal causality.

## Phase B gate files

- **`14-cohort-integrity-gate.json`** — corpus presence, app identity, 24-hour ordering, and audit sample math
- **`15-negative-control-baseline-validity-gate.json`** — fixed-range baseline validity with zero-row Q3 variants
- **`16-positive-control-perturbation-validity-gate.json`** — successful perturbation sequence plus Q3/Q4 alignment and H0b primary metric
- **`17-bounded-coverage-uncertainty-gate.json`** — bounded scope, excluded artifacts, and evidence ceilings for Claim 2 / Claim 3

## Excluded artifacts

| File | Why excluded |
|---|---|
| `q6-baseline-vs-perturb-20260614114318.json` | Unparsable (`BadArgumentError` / `datetime(...ZZ)` syntax error). Retained so the exclusion is auditable. |
| `q6-baseline-vs-perturb-20260614114522.json` | Parseable, but its `Baseline (no perturb)` bucket includes earlier partial perturbations and is therefore contaminated for H0a. |

## Inventory

### Deployment and environment capture

- `acr-build.log`
- `acr-creation.log`
- `audit-executions-initial.log`
- `audit-job-config.json`
- `audit-job-manual-trigger.log`
- `audit-sample-stdout.log`
- `baseline-window-start.txt`
- `baseline-window.txt`
- `deploy-config.md`
- `deploy-env.sh`
- `deployment.log`
- `deployment-name.txt`
- `deployment-outputs.json`
- `law-audit-samples-initial.log`
- `law-audit-samples-phase1-final.log`
- `law-ingestion-check-initial.log`
- `phase-1-complete.md`
- `phase-2-health-snapshot-20260612123848.log`
- `RESUME-PLAYBOOK.md`
- `resources-after-deploy.log`
- `rg-creation.log`
- `run_kql_pack.sh`
- `verify-20260612115024.log`

### KQL query outputs

- `q1-baseline-fixed-ingestion-20260614114618.json`
- `q1-baseline-fixed-ingestion-20260614114618.table.txt`
- `q1-ingestion-check-20260612121931.json`
- `q1-ingestion-check-20260612121931.table.txt`
- `q1-ingestion-check-20260614114318.json`
- `q1-ingestion-check-20260614114318.table.txt`
- `q2-baseline-fixed-steady-state-20260614114618.json`
- `q2-baseline-fixed-steady-state-20260614114618.table.txt`
- `q2-per-app-baseline-20260614114318.json`
- `q2-per-app-baseline-20260614114318.table.txt`
- `q3-baseline-fixed-any-termination-20260614114618.json`
- `q3-baseline-fixed-any-termination-20260614114618.table.txt`
- `q3-baseline-fixed-clustered-churn-20260614114618.json`
- `q3-baseline-fixed-clustered-churn-20260614114618.table.txt`
- `q3-clustered-churn-20260614114318.json`
- `q3-clustered-churn-20260614114318.table.txt`
- `q4-recovery-duration-20260614114318.json`
- `q4-recovery-duration-20260614114318.table.txt`
- `q6-baseline-vs-perturb-20260614114318.json` **(excluded)**
- `q6-baseline-vs-perturb-20260614114318.table.txt` **(excluded companion output)**
- `q6-baseline-vs-perturb-20260614114522.json` **(excluded from H0a)**
- `q6-baseline-vs-perturb-20260614114522.table.txt` **(excluded companion output)**
- `q7-multi-app-comparison-20260614114318.json`
- `q7-multi-app-comparison-20260614114318.table.txt`

### Perturbation logs

- `perturbation-variant-a-restart-only-20260614110433.log`
- `perturbation-variant-b-restart-load-20260614111457.log`
- `perturbation-variant-c-retry-backoff-20260614112821.log`

### Derived Phase B outputs

- `14-cohort-integrity-gate.json`
- `15-negative-control-baseline-validity-gate.json`
- `16-positive-control-perturbation-validity-gate.json`
- `17-bounded-coverage-uncertainty-gate.json`

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/zone-redundancy-best-effort/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh --phase-b-only` | Re-emits the four gate JSON files from the committed raw evidence without touching Azure. |

```bash
cd labs/zone-redundancy-best-effort/
bash verify.sh --phase-b-only
```
