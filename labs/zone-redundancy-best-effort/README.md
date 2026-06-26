# Lab: Zone-redundancy best-effort

Phase B for this lab is a **non-falsification with bounded coverage** evidence pack. It reuses the committed 24-hour reproduction corpus from Jun 12-Jun 14 and does **not** require a fresh Azure deployment to validate the claims carried by the lab guide.

The committed cohort supports two narrow conclusions only: (1) the fixed-range 24-hour baseline did **not** observe clustered churn for `app-min2`, `app-min3`, or `app-min6`; and (2) three deterministic perturbations against `app-min3` produced measurable churn/recovery while the two client-bearing runs at `10 RPS` for `180 s` still observed `0` failures. This is intentionally **not** a fix-and-falsify loop.

## Structure

```text
labs/zone-redundancy-best-effort/
├── infra/                         # Baseline environment + three subject apps + audit Job
├── audit/                         # Replica inventory sampler image and script
├── apps/                          # Optional custom subject-app image for richer telemetry
├── workbook/                      # Optional Azure Monitor workbook assets
├── deploy.sh                      # Live deployment wrapper for future fresh reproductions
├── verify.sh                      # Live-health gate + offline 16-sub-gate Phase B verifier
├── trigger.sh                     # Deterministic restart/load perturbation harness
├── cleanup.sh                     # Destructive teardown for live reproductions
├── evidence/                      # 50 committed raw/derived artifacts + gate README
└── README.md                      # This Phase B overview
```

## Phase B gate semantics

Phase B follows Oracle's approved **4-gate × 4-sub-gate** design:

1. **Gate 14 — Cohort / corpus integrity**
    - Validates required files, app identity, 24-hour temporal ordering, and audit sample math.
2. **Gate 15 — Negative-control baseline validity**
    - Confirms the fixed-range baseline is trustworthy: ingestion health is sufficient, steady state held, and both baseline Q3 variants returned zero rows.
3. **Gate 16 — Positive-control perturbation validity**
    - Confirms the three successful perturbations are present, Q3/Q4 see the intended churn/recovery windows, and the H0b primary metric remains unfalsified under the tested load.
4. **Gate 17 — Bounded coverage / uncertainty ceilings**
    - Explicitly constrains scope to `app-min3`, the two client-bearing 10-RPS runs, the excluded Q6 artifacts, and the evidence ceilings on Claim 2 / Claim 3.

## Bounded scope

- **Subject app for perturbation evidence:** `app-min3` only
- **Baseline cohort:** exactly 24 hours (`2026-06-12T11:51:46Z` → `2026-06-13T11:51:46Z`)
- **Client-bearing variants:** 2
    - Variant B — `no-retry`, `rps=10`, `durationSec=180`
    - Variant C — `retry-backoff`, `rps=10`, `durationSec=180`
- **Restart-only variant:** Variant A, no client load
- **Local H0b outcome under tested load:** `0 / 990` failures for Variant B, `0 / 960` failures for Variant C

## Confounders, exclusions, and ceilings

- **Excluded artifact 1:** `evidence/q6-baseline-vs-perturb-20260614114318.json`
    - Unparsable due to `datetime(...ZZ)` syntax error; retained as evidence of the exclusion rationale.
- **Excluded artifact 2:** `evidence/q6-baseline-vs-perturb-20260614114522.json`
    - Parseable, but the `Baseline (no perturb)` bucket is contaminated by earlier partial perturbations and is therefore invalid for H0a.
- **Evidence ceiling — Claim 2:** zone distribution remains capped at `[Strongly Suggested]` because ACA does not expose per-replica Availability Zone identity.
- **Evidence ceiling — Claim 3:** multi-replica platform events remain capped at `[Strongly Suggested]` because the measured clustered churn in this corpus is operator-triggered, not platform-triggered.

## Why there is no `fix-and-capture.sh`

This lab is observational, not a repair-loop lab. The Jun 12-Jun 14 corpus already contains the full 24-hour baseline plus the three bounded perturbations, so Phase B needs only an **offline verifier** that re-checks the committed evidence and emits the four derived gate JSONs. A `fix-and-capture.sh` workflow would imply a canonical H1-trigger / H2-fix model that does not apply here.

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/zone-redundancy-best-effort/` | Enters the lab directory so verifier-relative paths resolve correctly. |
| `bash verify.sh --phase-b-only` | Re-emits the four Phase B gate JSON files from the committed corpus without querying Azure. |
| `bash verify.sh` | Runs the same Phase B verifier plus a single live-health gate; if the live resource group is unavailable, the verifier falls back to the committed live-health snapshot and still remains Azure-free. |

```bash
cd labs/zone-redundancy-best-effort/
bash verify.sh --phase-b-only
```

## Documentation cross-reference

- Lab guide: [`docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md`](../../docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md)
- Evidence inventory: [`evidence/README.md`](evidence/README.md)
- Companion playbook: [`docs/troubleshooting/playbooks/platform-features/zone-redundancy-best-effort.md`](../../docs/troubleshooting/playbooks/platform-features/zone-redundancy-best-effort.md)
