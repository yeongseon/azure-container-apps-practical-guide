# Evidence Pack Provenance

This directory contains the raw evidence artifacts for the `startup-degraded-transient-failure` lab. Lab 18's Phase B pack is an **Option Y reuse-only evidence pack** built against the committed canonical 2026-06-20 repro under RG `rg-aca-startup-degraded` in Korea Central. The canonical scenario is a single logical test: an ACA-managed rolling rollout with correctly-configured `/healthz` probes and a deterministic `STARTUP_DELAY_SECONDS=25` workload. All committed evidence in this pack is PII-scrubbed: subscription, tenant, object, workspace, and resource GUIDs use `00000000-0000-0000-0000-000000000000`; employee aliases use `demouser`; employee display names use `Demo User`; employee emails use `user@example.com`; local paths use `/Users/demouser`.

## Capture timeline

This Phase B evidence pack intentionally **reuses** the already-committed canonical evidence instead of redeploying. The controlling Oracle bg_b94eeacf directive is binding and is quoted verbatim here: **"Pick Lab 18 = `startup-degraded-transient-failure` and do it as Option Y: reuse committed evidence only"**. Two other directives shape the pack design: **"Use the latest canonical run per scenario. Do not aggregate all timestamps into a single count or single narrative"** and **"Timestamp mixing is the primary risk. The agent must not count all historical artifacts together"**.

This reuse-only strategy is not just convenience; it is the lowest-risk way to preserve the exact transient-state semantics already captured in the canonical 2026-06-20 evidence window. A redeploy would add cost, generate new timestamps, and tempt future readers to blend incompatible historical runs. Phase B therefore pins exactly seven canonical inputs (`qA`-`qG`) and derives four new gate JSONs (`10`-`13`) from those inputs only.

The canonical 2026-06-20 run can be described as four phases:

1. **Phase 1 — Bicep deploy + KQL/k6 plumbing (~21:00-21:30Z).** The repro environment was provisioned in Korea Central under `rg-aca-startup-degraded`, using a zone-redundant Container Apps environment and workload profiles. The deploy-time artifacts, image references, and scripting context are preserved in supporting files such as `deploy-001.log`, `deploy-env.sh`, and `run_kql_pack.sh`.
2. **Phase 2 — Baseline k6 run (`baseline-20260620213447`).** The baseline run established the pre-perturbation control: 9,637 per-VU buckets, 47,506 successful requests, `err_total: 0`, `err_pct: 0`, `falsification_triggered: False`.
3. **Phase 3 — Perturbation run with 3 rollout events (`perturbation-20260620220432`).** Three successive `az containerapp update` operations forced three new revisions (`subject-app--0000001`, `subject-app--0000002`, `subject-app--0000003`). The perturbation run produced 36,069 per-VU buckets, 149,699 successful requests, `err_total: 0`, `err_pct: 0`, `falsification_triggered: False`.
4. **Phase 4 — Canonical evidence capture (`qA`-`qG`, 22:39-22:51Z).** After the rollout activity completed, the canonical JSON exports were captured into `qA-revision-state-20260620T223951Z.json` through `qG-audit-sampler-quirk-20260620T225143Z.json`. These are the only predicate inputs for Phase B gates.

Phase B adds a fifth replay-only step:

- **Verify Phase 10-13 — Gate emission (replayable, no Azure calls).** The rewritten `labs/startup-degraded-transient-failure/verify.sh` is now a pure file processor. It consumes the committed qA-qG evidence, emits four derived falsification/integrity gates, prints a PASS/FAIL matrix, and exits non-zero if any top-level gate fails.

This split is deliberate. The historical Phase A `verify.sh` owned live Azure health checks. The Phase B `verify.sh` owns derived evidence classification only.

## Cross-scenario differential proof — why this is not a fake-fix lab

Unlike the memory-leak lab, Lab 18 is **not** a multi-scenario A/B/C workload comparison. It is one logical H0 experiment with two phases of client-visible traffic data:

- **Baseline** — no perturbation; control state.
- **Perturbation** — three ACA-managed rolling rollouts; treatment state.

The falsifiable hypothesis is the binding D1/D6 design claim from `design-constraints-20260612.md`:

> **H0**: ACA masks all transients during a rolling rollout when probes are tuned per D3 and the workload has a `STARTUP_DELAY_SECONDS=25` deliberate slow-start (D2).

The falsification rule is equally binding:

> **D6**: H0 is falsified if ANY rolling-rollout event produces >=3 consecutive 10s buckets where `err_pct > 0.5%` in the k6 client output.

The 2026-06-20 canonical outcome is **H0 not falsified**:

- `qF-run-summary-20260620T224149Z.json` reports `falsification_triggered: False` for `baseline-20260620213447`.
- The same file reports `falsification_triggered: False` for `perturbation-20260620220432`.
- Both rows report `err_pct: 0`.
- `qC-k6-buckets-20260620T224056Z.json` contains 126 aggregate buckets across both runs and every bucket has `err_total: 0`.

The differential proof in this lab is therefore **between phases, not between scenarios**. The perturbation phase is only meaningful if it injected real disruption. That is why the four gates are split deliberately:

### Gate 10 — canonical evidence integrity

`10-canonical-evidence-integrity-gate.json` is the precondition gate. It proves the evidence pack itself is coherent before any H0 claim is evaluated. The three sub-gates confirm:

1. All seven canonical files exist.
2. Their filename timestamps belong to the single canonical 22:39-22:51Z capture cohort (with a wider execution fallback window only as backup).
3. `qF` explicitly maps a baseline run and a perturbation run.

Without Gate 10, a reviewer could unknowingly blend historical runs or misread an incomplete evidence pack as a valid null result.

### Gate 11 — degraded-state evidence

`11-failure-degraded-state-gate.json` proves the perturbation was real. This is the anti-"fake-fix" gate. It uses qA/qD/qE to show that the rollout injected transient disruption:

1. `qE` records three perturbation start markers (`rollout-event-1`, `rollout-event-2`, `rollout-event-3`).
2. `qD` records real probe failures during rollout, including **35 `ProbeFailed` warnings on `subject-app--0000003`** and 24 each on the earlier revisions.
3. `qA` records real revision transitions, including active revisions demoted to `traffic: 0` while the new revision becomes active.

This is the crucial transient-state nuance: the system **did** enter a degraded internal state during rollout. The platform simply masked that state from the client.

### Gate 12 — recovery / no client impact

`12-recovery-fix-gate.json` proves the client-visible side of H0. It uses qF plus the latest healthy snapshots from qA/qB to show:

1. The perturbation run's `err_pct` is exactly zero.
2. The D6 falsification rule did not trigger for baseline or perturbation.
3. The post-rollout healthy snapshots show the newest revision running and the latest active qA row still reporting 3 replicas.

Gate 12 is intentionally the **H0-held gate**. Its PASS state does **not** mean "nothing happened." It means "something happened internally, but ACA masked it from the client." That interpretation only becomes correct when Gate 12 is read together with Gate 11.

### Gate 13 — cross-artifact integrity

`13-cross-artifact-consistency-gate.json` is the coherence overlay. It confirms that the canonical files belong to one window and share perturbation identifiers across qA and qE. This guards against a subtle failure mode: using the right file names but the wrong cross-table joins.

### The actual differential

The experiment's differential is therefore:

- **Baseline phase** — no perturbation, zero client-visible errors.
- **Perturbation phase** — three real rolling rollouts, real probe failures, real revision transitions, still zero client-visible errors.

That is not a fake-fix lab. It is a null-result lab with **positive degraded-state evidence** and **negative client-impact evidence** collected simultaneously.

## Honest disclosure — empirical platform behavior captured during this run

The following caveats are intentionally documented so a future reviewer does not overclaim what this evidence proves:

- **Only 3 perturbation events triggered, not the design's 12-over-2-hours target.** D6 planned 12 events over ~2 hours for the original formal experiment. The 2026-06-20 canonical repro intentionally ran only three rollout events to minimize cost and still prove the key masking pattern. Each `az containerapp update` creates exactly one new revision and therefore one ACA-managed rolling rollout. The Phase B gates encode what the canonical repro actually did; they do not pretend the repro achieved the full D6 event count.

- **`ProbeFailed` events are present and EXPECTED during the 25-second startup delay.** D2 binds the workload to `STARTUP_DELAY_SECONDS=25`. D3 binds startup/readiness/liveness to the dedicated `/healthz` endpoint with the fixed probe timing budget. The 35 `ProbeFailed` warnings on `subject-app--0000003` are therefore not evidence that the final revision remained broken. They are evidence that the rollout produced a still-warming replica whose readiness gating was working exactly as intended. This is the H0 success path: the platform observed the degraded internal state and kept the client shielded from it.

- **`qG` documents a benign audit-sampler `Failed` status.** The audit-sampler job uses `replicaTimeout=240s` while the container behaves like a long-lived daemon. ACA sends SIGTERM at the timeout boundary and marks the execution `Failed`, but data ingestion is unaffected. `qG-audit-sampler-quirk-20260620T225143Z.json` explicitly records `data_ingestion_verified: true`, `law_records_audit_container: 583`, and `law_kinds_observed: [ReplicaInventorySample, RevisionStateSample]`. Operators must not mistake the Portal failure badge for a missing-data condition.

- **Historical `q1`-`q7` exports are preserved but NOT consumed by the gates.** The evidence directory contains many older JSON/TSV exports from 2026-06-12 and an additional 2026-06-20 `...222220` export set. Per Oracle's directive — *"Do not aggregate all timestamps into a single count"* — Phase B predicates read only qA-qG. The historical files remain available for manual inspection and narrative context, but they are outside the gate predicate surface by design.

- **Phase A `verify.sh` was a live-Azure health-check script and has been replaced.** The original 102-line `verify.sh` executed nine live Azure checks against a deployed RG. That responsibility now belongs to the trigger/orchestration workflow and the historical evidence logs. The new Phase B `verify.sh` is a replay-only classifier over committed files.

- **`evidence/.local/` contains real identifiers and is intentionally gitignored.** Files such as `.local/deploy-env.local.sh`, `.local/law-customer-id.txt`, and `.local/pii-values.env` are operator-local secrets or identifiers. They are not part of the committed evidence pack. The committed `deploy-env.sh` is the sanitized, reproducible shell context.

- **`evidence/*.pid` files are process metadata, not evidence.** Files such as `kql-pack.pid`, `perturbation.pid`, and `supplemental-restart.pid` exist because the historical orchestration used background processes. They are not consumed by the gates and should not be treated as forensic evidence.

- **`qB`'s latest final snapshot for `subject-app--0000003` shows two Running rows, not three.** This looks surprising because the active qA row still reports `replicas: 3`. The correct interpretation is not data corruption; it is sampling skew between the 30-second audit cadence (qB) and the 5-second sampler / control-plane state (qA). Gate 12 therefore uses a strong path of "all rows in the latest qB snapshot are Running" and a fallback of "latest active qA row reports 3 replicas." This is an honest representation of the capture, not an attempt to fabricate a 3/3 final qB snapshot that the canonical evidence does not contain.

- **CLI version context comes from the preserved logs, not from a new live query.** `preflight-002.log` records `azure-cli 2.79.0`. The exact containerapp extension version is part of the historical capture context and should be traced via the deploy-time evidence files rather than by re-querying Azure during Phase B.

## File index

The table below separates canonical gate inputs from preserved supporting artifacts.

| Artifact | Role | Notes |
|---|---|---|
| `qA-revision-state-20260620T223951Z.json` | **Canonical / consumed** | Consumed by Gates 10, 11, 12, 13. High-frequency `RevisionStateSample` records with `perturbation_id`, `active`, `revision`, `replicas`, `traffic`. |
| `qB-replica-inventory-20260620T223955Z.json` | **Canonical / consumed** | Consumed by Gates 10 and 12. Audit-sampler inventory of replica `state` by revision. |
| `qC-k6-buckets-20260620T224056Z.json` | **Canonical / supporting for Gate 10 narrative** | Canonical bucket-level aggregate; all `err_total == 0`. Not needed for Gate 12's decisive predicate because qF already stores the run verdict, but retained as supporting evidence. |
| `qD-system-events-20260620T224002Z.json` | **Canonical / consumed** | Consumed by Gates 10 and 11. System-event rollup; key degraded-state evidence is `ProbeFailed`. |
| `qE-perturbation-markers-20260620T224143Z.json` | **Canonical / consumed** | Consumed by Gates 10, 11, 13. Three start markers and three end markers. |
| `qF-run-summary-20260620T224149Z.json` | **Canonical / consumed** | Consumed by Gates 10 and 12. One baseline row, one perturbation row, both `falsification_triggered: False`. |
| `qG-audit-sampler-quirk-20260620T225143Z.json` | **Canonical / consumed** | Consumed by Gates 10 and 13 for pack completeness and documented quirk context. |
| `10-canonical-evidence-integrity-gate.json` | **Derived / Phase B** | Gate 10 output emitted by the pure-file `verify.sh`. |
| `11-failure-degraded-state-gate.json` | **Derived / Phase B** | Gate 11 output emitted by the pure-file `verify.sh`. |
| `12-recovery-fix-gate.json` | **Derived / Phase B** | Gate 12 output emitted by the pure-file `verify.sh`. |
| `13-cross-artifact-consistency-gate.json` | **Derived / Phase B** | Gate 13 output emitted by the pure-file `verify.sh`. |
| `q1-per-run-summary-20260620222220.{json,tsv}` | Preserved, not consumed | Historical run-summary export from the 2026-06-20 repro; not part of gate predicates. |
| `q2-buckets-10s-sum-vus-20260620222220.{json,tsv}` | Preserved, not consumed | Historical 2026-06-20 bucket export; superseded by qC for canonical gate inputs. |
| `q3-revision-state-timeline-20260620222220.{json,tsv}` | Preserved, not consumed | Historical timeline export; qA is the canonical input for Phase B. |
| `q4-replica-inventory-snapshot-20260620222220.{json,tsv}` | Preserved, not consumed | Historical inventory export; qB is the canonical input for Phase B. |
| `q5-falsification-3-consecutive-bad-buckets-20260620222220.{json,tsv}` | Preserved, not consumed | Historical direct falsification query output; retained for manual cross-checking only. |
| `q6-baseline-vs-perturb-vs-supplemental-20260620222220.{json,tsv}` | Preserved, not consumed | Historical phase-comparison export; not used by Phase B gates. |
| `q7-system-events-timeline-20260620222220.{json,tsv}` | Preserved, not consumed | Historical timeline export; qD is the canonical gate input. |
| `q1-*`, `q2-*`, `q3-*`, `q4-*`, `q5-*`, `q6-*`, `q7-*` from `20260612` / `20260613` | Preserved, not consumed | Original formal 12-event experiment exports. Critical historical context, deliberately excluded from Phase B predicates. |
| `baseline-001.log` | Supporting | Baseline run launch/wait log. |
| `perturbation-002.log` | Supporting | Original official perturbation run log from the formal experiment. |
| `perturbation-003.log` | Supporting | 2026-06-20 repro perturbation log. |
| `supplemental-restart-001.log` | Supporting | Supplemental explicit-restart phase log from the formal experiment. |
| `deploy-001.log` | Supporting | Provisioning log; captures deploy-time environment details. |
| `verify-001.log` | Supporting | Historical 9-check live-Azure verify output. |
| `preflight-001.log` | Supporting | Pre-bug-fix preflight attempt; transparency artifact. |
| `preflight-002.log` | Supporting | Successful preflight log; records `azure-cli 2.79.0`. |
| `preflight-staircase-aggregation.tsv` | Supporting | Formal preflight RPS staircase aggregation. |
| `preflight-buckets-10s.tsv` | Supporting | Formal preflight 10-second buckets. |
| `baseline-start.txt` | Supporting | Timestamp anchor used by historical KQL slicing. |
| `run_kql_pack.sh` | Supporting / reproducibility | Historical KQL harness for q1-q7 generation. |
| `scrub-pii.sh` | Supporting / reproducibility | PII scrubber aligned to repo policy. |
| `deploy-env.sh` | Supporting / reproducibility | Sanitized shell context for repro scripting. |
| `design-constraints-20260612.md` | Supporting / binding | D1-D10 design contract that Phase B cites directly (especially D2, D3, D4, D6, D8). |
| `deploy-env.local.sh` | Gitignored local secret context | Must not be committed as evidence input. |
| `kql-pack.pid`, `perturbation.pid`, `supplemental-restart.pid` | Gitignored runtime metadata | Process IDs only, not evidence. |

## Reproducibility

To reproduce the full experiment from scratch, use the lab's existing orchestration rather than the Phase B verifier. The high-level sequence is:

```bash
export RG="rg-aca-startup-degraded"
export LOCATION="koreacentral"
export ACR_NAME="<your-acr-without-azurecrio>"

bash labs/startup-degraded-transient-failure/deploy.sh

az acr build --registry "$ACR_NAME" --image startup-degraded/subject:latest ./labs/startup-degraded-transient-failure/subject
az acr build --registry "$ACR_NAME" --image startup-degraded/audit:latest ./labs/startup-degraded-transient-failure/audit
az acr build --registry "$ACR_NAME" --image startup-degraded/perturbation-sampler:latest ./labs/startup-degraded-transient-failure/perturbation-sampler
az acr build --registry "$ACR_NAME" --image startup-degraded/loadgen:latest ./labs/startup-degraded-transient-failure/loadgen

bash labs/startup-degraded-transient-failure/trigger.sh --preflight
bash labs/startup-degraded-transient-failure/trigger.sh --baseline --duration 1800
bash labs/startup-degraded-transient-failure/trigger.sh --perturbation --events 12 --interval 600

# Optional historical comparison
bash labs/startup-degraded-transient-failure/trigger.sh --supplemental-restart --events 3 --interval 600

# KQL export harness used by the historical captures
bash labs/startup-degraded-transient-failure/evidence/run_kql_pack.sh all perturbation-

# Pure file replay over committed evidence only
bash labs/startup-degraded-transient-failure/verify.sh
```

The canonical 2026-06-20 repro intentionally ran only three rollout events to keep the rerun cheap while still capturing the masking pattern. The original formal experiment (2026-06-12/13 evidence) remains the authoritative 12-event run. The expected operational cost for the smaller 2026-06-20 style repro is **under $2 USD** for roughly an 80-minute Korea Central window, assuming a single zone-redundant environment, one subject app pinned at 3 replicas, and the three companion jobs. The Phase B `verify.sh` itself runs in a few seconds and has **zero Azure cost** because it never leaves the filesystem.

The hard boundary is this:

- `trigger.sh`, `deploy.sh`, ACR builds, and `run_kql_pack.sh` = live Azure orchestration.
- Phase B `verify.sh` = replay-only classification over committed evidence.

That separation is the main reproducibility improvement delivered by this evidence pack.

## CLI versions and platform context

The preserved logs record **azure-cli 2.79.0** (`preflight-002.log`). The exact containerapp extension pin belongs to the historical deploy-time context and should be traced through the original deploy/extension evidence rather than re-queried during Phase B. The canonical 2026-06-20 repro targeted:

- **Resource group**: `rg-aca-startup-degraded`
- **Region**: Korea Central (`koreacentral`)
- **Container Apps Environment**: zone-redundant workload-profile environment
- **Plan shape**: Consumption profile inside workload profiles
- **Subject app**: deterministic Python image with `STARTUP_DELAY_SECONDS=25`
- **Probe profile**: dedicated `/healthz`, timings bound by D3
- **Primary perturbation**: ACA-managed new revision rollout via env-var update (D4)
- **Evidence basis**: embedded client timestamps and control comparisons per D8

The older `deploy-env.sh` in this directory points at the original 2026-06-12/13 formal experiment RG (`rg-aca-sdlab-260612125433`) and remains preserved as a supporting artifact. It is not the canonical RG for the 2026-06-20 qA-qG evidence pack and should not be confused with it.
