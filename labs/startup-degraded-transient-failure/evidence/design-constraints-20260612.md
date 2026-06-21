# Design Constraints (2026-06-12)

| Field | Value |
| --- | --- |
| Date (UTC) | 2026-06-12T12:43:00Z |
| Tracking issue | [#205](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/205) |
| Status | Binding (implementation plan) |

This document records the binding design constraints for the
`labs/startup-degraded-transient-failure/` reproduction. The lab
guide's "Hybrid A design constraints (immutable)" section is the
reader-facing summary of these constraints; this document carries the
component-by-component rationale.

## Component-by-component design decisions

| ID | Component | Decision | Rationale |
| --- | --- | --- | --- |
| D1 | Architecture | Single subject + same env / VNet / UAMI / LAW + `koreacentral`; `loadgen` runs as a **manual Container Apps Job** in the same environment | Matches the Hybrid A standard used by `labs/zone-redundancy-best-effort/`; the manual Job form factor avoids the long-running-loadgen-app failure mode |
| D2 | Subject app workload | **Small custom Python image** with `STARTUP_DELAY_SECONDS=25` and a dedicated lightweight `/healthz` endpoint | A deterministic startup delay is required to test the "ACA masks all transients" claim; a separate `/healthz` decouples probe behaviour from the workload path |
| D3 | Probe configuration | Startup 40s budget / readiness 10s removal / liveness 90s; all three probes target `/healthz` | One fixed primary probe profile is required before the first run to keep the experimental variable contained; `/healthz` avoids confounding probe behaviour with workload `/` behaviour |
| D4 | Perturbation mechanism | **ACA-managed new revision rollout** via env-var or revision-suffix change (primary); `az containerapp revision restart` is supplemental only | The primary perturbation must exercise the platform's normal rollout path, not the operator-side restart path |
| D5 | Load generator | k6 Linux container as an ACA Job inside the same environment, targets the **public FQDN**, emits **client-side 10s buckets with timestamps**, connection reuse disabled, preflight RPS staircase added | Public FQDN exercises the ingress path; client-side timestamps are required because ingestion-time joins are too coarse for a 10s bucket lab |
| D6 | Statistical power | **12 events over ~2 hours**; falsification rule: ANY sustained window of ≥3 consecutive 10s buckets above 0.5% during an event is sufficient | 6 events over 60 minutes underpowers the test; the 12-event, 2-hour design is the minimum credible event count for a 10s-bucket lab |
| D7 | Evidence corpus | Add high-frequency perturbation evidence (5s sampler); 5-min audit is supplemental only; include `RevisionStateSample`, k6 script + image digest, per-event execution IDs, raw KQL exports | 5-min audit cadence is too coarse for a 10s-bucket transition lab; high-frequency sampling is mandatory |
| D8 | KQL pack | Q5 includes a **control comparison outside perturbation windows**; all joins use embedded client bucket timestamps (not ingestion time) | Without a control comparison, a per-event 5xx rate is unmeaning; ingestion-time joins drift relative to the 10s buckets |
| D9 | Cost / wall-clock | 1 vCPU / 2 GiB k6 runner; validated during preflight (estimated $8-14, 12-16h total wall-clock) | Modest k6 runner sufficient for 200 RPS; validated by the preflight staircase before the baseline run |
| D10 | Risks / failure modes | Document: 200 RPS may be too easy for the sample app, 5-min sampling cannot explain sub-minute failures, using `/` as both workload + probe path confounds the result | These three risks were the highest-impact gaps identified during design and are mitigated by D2, D7, and D3 respectively |

## Binding constraints (methodological)

1. Keeping the wording "scheduled platform-initiated rolling restart" while using a synthetic trigger: cap the event-cause portion of any conclusion at **[Strongly Suggested]**. The client-visible 5xx outcome can still be **[Measured]** if the surrogate is labeled honestly.
2. A zero-5xx result is only meaningful if 200 RPS is shown to consume nontrivial headroom — verified by the preflight RPS staircase (100/200/400).
3. 5-min audit samples alone are insufficient for a 10s-bucket transition lab. High-frequency perturbation evidence is mandatory.
4. Do NOT use `/` as both the workload path AND the health endpoint if the workload carries an artificial delay or load sensitivity.
5. No final verdict is credible without a committed raw evidence corpus; no `/tmp`-only evidence.

## Optional enhancements

1. After the primary rollout-based run, add one supplemental `revision restart` run as a harsher comparison.
2. The custom app emits console markers `startup-delay-begin` and `listening` for tighter KQL correlation.
3. A brief 100/200/400 RPS preflight even if 200 RPS remains the formal acceptance load.

## Implementation checklist

All must hold before the lab's verdict is considered credible:

- Primary perturbation is the **rollout surrogate** (not `revision restart`)
- Subject app is a **deterministic custom image** with **`/healthz`**
- k6 is defined as a **bounded ACA Job** with structured **10s buckets**
- A **5-10s perturbation sampler** AND `RevisionStateSample` are part of the evidence plan
- The falsification logic and event count match issue [#205](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/205)

## Final design summary

| Component | Implementation |
| --- | --- |
| Subject image | Custom Python image, `STARTUP_DELAY_SECONDS=25`, dedicated `/healthz` |
| Probe paths (startup / readiness / liveness) | `/healthz` (all three) |
| Probe timings | startup 40s budget / readiness 10s removal / liveness 90s |
| Loadgen form factor | Manual Container Apps Job |
| Loadgen target | Public FQDN, connection reuse disabled |
| Perturbation primary | `az containerapp update --revision-suffix evN` (rollout) |
| Perturbation supplemental | `revision restart` (after primary run) |
| Event count | 12 events over 120 minutes |
| Audit cadence | 5 min audit + 5-10s perturbation sampler |
| Evidence types | `RevisionStateSample`, perturbation-sampler logs, k6 image digest, per-event execution IDs, raw KQL JSON exports |
| KQL Q5 | per-event 5xx + control comparison outside perturbation windows |
| KQL join basis | embedded client bucket timestamps |
| Evidence-level cap for "platform-initiated cause" | **[Strongly Suggested]** (per binding constraint #1) |
| Evidence level for "client-visible 5xx outcome" | **[Measured]** |
