# Phase 1 Milestone — Azure Deploy + Verify Complete

**Issue**: [#204](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/204)
**Branch**: `lab/zone-redundancy-best-effort-reproduce`
**Date**: 2026-06-12T11:55Z (UTC)
**Phase 0 commit**: `222151f` (honesty fix on lab guide)
**Phase 1 commit**: this commit

## Outcome

All 13 verify.sh checks passed. Audit job emitting `ReplicaInventorySample`
JSON every 5 min. Log Analytics ingestion confirmed
([`law-audit-samples-phase1-final.log`](law-audit-samples-phase1-final.log)).

## Baseline state (T=0)

| App | Min replicas | Observed replicas | Status |
|---|---|---|---|
| `app-min2` | 2 | 2 | All Running |
| `app-min3` | 3 | 3 | All Running |
| `app-min6` | 6 | 6 | All Running |

Total: 11/11 replicas Running. Zone redundancy enabled on environment
`cae-zrlab-5yi4px` in `koreacentral`.

## Audit pipeline validation

| Time (UTC) | App | Min | Observed | Source |
|---|---|---|---|---|
| `2026-06-12T11:50:23Z` | app-min2 | 2 | 2 | Scheduled cron |
| `2026-06-12T11:50:24Z` | app-min3 | 3 | 3 | Scheduled cron |
| `2026-06-12T11:50:24Z` | app-min6 | 6 | 6 | Scheduled cron |
| `2026-06-12T11:52:29Z` | app-min2 | 2 | 2 | Manual trigger |
| `2026-06-12T11:52:31Z` | app-min3 | 3 | 3 | Manual trigger |
| `2026-06-12T11:52:31Z` | app-min6 | 6 | 6 | Manual trigger |
| `2026-06-12T11:55:23Z` | app-min2 | 2 | 2 | Scheduled cron |
| `2026-06-12T11:55:24Z` | app-min3 | 3 | 3 | Scheduled cron |
| `2026-06-12T11:55:24Z` | app-min6 | 6 | 6 | Scheduled cron |

Ingestion latency: stdout to `ContainerAppConsoleLogs_CL` observed at ~2 min
([Observed]; sample size n=9, single observation window). Standard ACA
ingestion delay applies.

## Subscription / tenant note

- Original plan target: a corp-managed subscription on the corp tenant
- Actual deploy target: **`Visual Studio Enterprise Subscription`** (personal MSDN sub on a personal tenant)
- Reason: the deploying user did NOT have `Microsoft.Resources/subscriptions/resourcegroups/write` permission on the two corp-managed subscriptions that were the original candidates
- Four candidate subscriptions were tested in parallel for RG-write access
  (real names redacted; full trace including AuthorizationFailed error bodies
  lives in gitignored `.local/rg-creation-raw.log`):

    | Candidate | Tenant class | Result |
    |---|---|---|
    | Corp-managed Subscription A | Corp tenant | AuthorizationFailed |
    | Corp-managed Subscription B | Corp tenant | AuthorizationFailed |
    | Corp-managed Subscription C (MCAPS Support class) | Corp tenant | Write granted |
    | `Visual Studio Enterprise Subscription` | Personal MSDN tenant | Write granted (chosen) |

Personal sub chosen because it has full owner permissions, is self-funded,
and isolates the lab from any corp policy or budget. Cost estimate revised
upward to ~$14-17 for 24h baseline + 2h perturbation (see "Cost incurred so
far" below).

## Cost incurred so far (Phase 1)

| Resource | SKU | Cost basis |
|---|---|---|
| ACR Basic | `acrzrlab260612114313` | $0.167/day |
| 11 ACA replicas | 0.5 vCPU / 1 GiB each | $2.07/vCPU/day + $0.26/GiB/day = ~$14.22/day after free tier |
| Log Analytics ingestion | Pay-as-you-go | ~$1-2/day estimated |
| Audit Job executions | 12 runs/hour × 288/day | Negligible (sub-second) |

Estimated 24h baseline cost: **~$14-17** (revised upward; original estimate of $9-12 underestimated the post-free-tier per-vCPU rate).

## What runs autonomously now (Phase 2 = passive 24h baseline)

The audit Job (`audit-sampler`) runs `*/5 * * * *` for 24 hours. No human
intervention required for Phase 2 — Log Analytics ingests the JSON events.

## Sanity check before resuming Phase 3+

Per [`RESUME-PLAYBOOK.md`](RESUME-PLAYBOOK.md), the resume session should run
Q1 (audit completeness) and expect:

- 288 audit samples per app over 24h window (12/hr × 24)
- All `observedReplicaCount >= configuredMinReplicas` (no clustered churn)
- If any sample shows `observedReplicaCount < configuredMinReplicas` for >5 min →
  H0a is FALSIFIED and this becomes the smoking gun for Claim 2/3

## Files committed in Phase 1

| File | Purpose |
|---|---|
| `RESUME-PLAYBOOK.md` | Step-by-step resume runbook for Phases 2-7 |
| `phase-1-complete.md` | This file (milestone snapshot) |
| `deploy-config.md` | Bicep parameter values used |
| `deploy-env.sh` | Public env vars (sources `.local/deploy-env.local.sh` if present) |
| `rg-creation.log` | RG create trace (including 3 failed candidates) |
| `acr-creation.log` | ACR Basic creation output |
| `acr-build.log` | Audit image build trace |
| `deployment.log` | Bicep deployment summary |
| `deployment-outputs.json` | Bicep outputs (sanitized) |
| `deployment-name.txt` | Bicep deployment name for re-fetch |
| `resources-after-deploy.log` | Resource inventory after deploy |
| `verify-20260612115024.log` | All 13 verify.sh checks (PASS) |
| `audit-job-config.json` | Audit cron + timeout config |
| `audit-job-manual-trigger.log` | Manual trigger run name |
| `audit-executions-initial.log` | First few executions (Succeeded) |
| `audit-sample-stdout.log` | Raw audit container stdout (9 samples) |
| `law-ingestion-check-initial.log` | First Log Analytics count query |
| `law-audit-samples-initial.log` | Initial parsed audit events (5) |
| `law-audit-samples-phase1-final.log` | Final Phase 1 audit events (9) |
| `baseline-window-start.txt` | UTC timestamp of T=0 |
| `baseline-window.txt` | Window start → end |

## PII sanitization applied

All real Azure GUIDs in committed evidence files are replaced with
placeholder values:

| Identifier type | Placeholder |
|---|---|
| Subscription ID | `00000000-0000-0000-0000-000000000000` |
| Tenant ID | `11111111-1111-1111-1111-111111111111` |
| LAW customer ID | `22222222-2222-2222-2222-222222222222` |
| UAMI principal ID | `33333333-3333-3333-3333-333333333333` |
| UAMI client ID | `44444444-4444-4444-4444-444444444444` |

Real values for resumption live in gitignored `.local/deploy-env.local.sh`
and are re-fetchable via `az account show` and
`az monitor log-analytics workspace show --query customerId`.

## See also

- [`RESUME-PLAYBOOK.md`](RESUME-PLAYBOOK.md) — Phase 2-7 resume runbook
- Lab guide: [`../../../docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md`](../../../docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md)
- Issue: [#204](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/204)
