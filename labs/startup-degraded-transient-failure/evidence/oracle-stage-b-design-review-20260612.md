# Oracle Stage B Design Review (REVISE_AND_RESUBMIT)

| Field | Value |
| --- | --- |
| Date (UTC) | 2026-06-12T12:43:00Z |
| Background task | `bg_1534fb43` |
| Oracle session ID | `ses_14429826cffeXthi0x6tgTdLOW` |
| Resumable consult session | `ses_155f8bbb1ffei2kheT5Gw7S5Mf` |
| Prior binding verdict (Stage A) | `ses_144f3ce9cffeyOLLgO8doWTal3` |
| Tracking issue | [#205](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/205) |
| Overall verdict | **REVISE_AND_RESUBMIT** |
| Effort estimate | Medium |

## Section 1: Overall Verdict

REVISE_AND_RESUBMIT. The current Stage B shape is structurally close, but the primary perturbation, subject workload, probe endpoint choice, and sampling cadence would make either a pass or a fail hard to trust.

## Section 2: D1-D10 item-by-item verdict

| ID | Topic | Verdict | Required Change |
| --- | --- | --- | --- |
| D1 | Architecture (single subject + same env/VNet/UAMI/LAW + koreacentral) | REVISE | Change `loadgen` from long-running app to **manual Container Apps Job** in same environment |
| D2 | Subject app workload (containerapps-helloworld + args injection for 25s sleep) | REVISE | Use **small custom image** with known entrypoint, deterministic 25s startup delay, dedicated lightweight `/healthz` |
| D3 | Probe configuration (startup 40s budget / readiness 10s removal / liveness 90s) | REVISE | Timing OK as primary baseline; probes must hit **`/healthz`** not `/`. Keep ONE fixed primary profile before first run |
| D4 | Perturbation mechanism (`az containerapp revision restart` every 10min × 6) | **REJECT** | Primary perturbation must be **ACA-managed new revision rollout** via env-var or revision-suffix change. Restart is supplemental only |
| D5 | Load generator (k6 Linux container, 200 RPS, 60min) | REVISE | k6 right tool. Run as **ACA Job inside same env**, target **public FQDN**, emit **client-side 10s buckets with timestamps**, disable connection reuse, add preflight RPS staircase |
| D6 | Statistical power (6 events / 60min) | REVISE | **12 events over ~2 hours**; falsification rule: ANY sustained window of ≥3 consecutive 10s buckets above 0.5% during an event suffices |
| D7 | Evidence corpus structure (mirror Stage A) | REVISE | Add **high-frequency perturbation evidence**. 5-min audit too coarse for 10s-bucket lab. Include **RevisionStateSample**, k6 script + image digest, per-event execution IDs, raw KQL exports |
| D8 | KQL pack (Q1-Q7 mirroring Stage A) | REVISE | Q5 must include **control comparison outside perturbation windows**. All joins use **embedded client bucket timestamps**, not ingestion time |
| D9 | Cost / wall-clock ($8-14, 12-16h) | APPROVE | 1 vCPU / 2 GiB k6 runner reasonable starting point; validate during preflight |
| D10 | Risks / failure modes | REVISE | Missing risks: **200 RPS may be too easy for sample app**, **5-min sampling cannot explain sub-minute failures**, **using `/` as both workload + probe path confounds result** |

## Section 3: Required revisions

1. Replace subject image with **deterministic custom image** implementing `STARTUP_DELAY_SECONDS=25` and dedicated **`/healthz`** endpoint.
2. Change primary perturbation from `revision restart` to **ACA-managed new revision rollout** caused by dummy env-var or revision-suffix change.
3. Keep **one fixed correctly-configured probe profile** for primary run, point startup/readiness/liveness at **`/healthz`**.
4. Use **k6 as a manual ACA Job** in same environment, targeting **public FQDN**, with structured **10s bucket logs** including execution ID and perturbation ID.
5. Add **high-frequency perturbation sampling** every **5-10s** for replica/revision state around each event; keep 5-min audit job; include **RevisionStateSample**.
6. Increase perturbation run to **~12 events / 2 hours**, keep issue's falsification rule unchanged.
7. Update KQL/evidence plan so **control buckets**, **timestamp-safe joins**, **raw exports** are first-class artifacts.

## Section 4: Optional revisions

1. After primary rollout-based run, add one supplemental `revision restart` run as harsher comparison.
2. Custom app emits console markers `startup-delay-begin` and `listening` for tighter KQL correlation.
3. Brief 100/200/400 RPS preflight even if 200 RPS remains formal acceptance load.

## Section 5: Binding constraints

1. Keeping wording "scheduled platform-initiated rolling restart" while using synthetic trigger: cap event-cause portion at **[Strongly Suggested]**. Client-visible 5xx outcome can still be **[Measured]** if surrogate labeled honestly.
2. Zero-5xx result only meaningful if **200 RPS shown to consume nontrivial headroom**.
3. **5-min audit samples alone insufficient** for 10s-bucket transition lab. High-frequency perturbation evidence mandatory.
4. Do NOT use `/` as both workload path AND health endpoint if workload carries artificial delay or load sensitivity.
5. No final verdict credible without committed raw evidence corpus; no `/tmp`-only evidence.

## Section 6: Final approval gate

**NO-GO** on the original design. **GO** once ALL of:

- Primary perturbation changed to **rollout surrogate** (not revision restart)
- Subject app is **deterministic custom image** with **`/healthz`**
- k6 defined as **bounded ACA Job** with structured **10s buckets**
- **5-10s perturbation sampler** AND **RevisionStateSample** part of evidence plan
- Falsification logic and event count corrected to match issue #205

If these incorporated, design consistent with same Hybrid A standard as Stage A.

## Revised Design Lock (post-Oracle)

| Component | Original | Revised |
| --- | --- | --- |
| Subject image | `containerapps-helloworld:latest` with args | Custom Python image, `STARTUP_DELAY_SECONDS=25`, dedicated `/healthz` |
| Probe paths (startup/readiness/liveness) | `/` | `/healthz` (all three) |
| Probe timings | startup 40s budget / readiness 10s removal / liveness 90s | UNCHANGED (Oracle approved as primary baseline) |
| Loadgen form factor | Long-running app | Manual Container Apps Job |
| Loadgen target | Internal FQDN | Public FQDN, connection reuse disabled |
| Perturbation primary | `az containerapp revision restart` | `az containerapp update --revision-suffix evN` (rollout) |
| Perturbation supplemental | none | `revision restart` (after primary run) |
| Event count | 6 / 60min | 12 / 120min |
| Audit cadence | 5min (only) | 5min audit + 5-10s perturbation sampler |
| New evidence types | (none) | RevisionStateSample, perturbation-sampler logs, k6 image digest, per-event execution IDs, raw KQL JSON exports |
| KQL Q5 | (per-event 5xx) | + control comparison outside perturbation windows |
| KQL join basis | ingestion time | embedded client bucket timestamps |
| Evidence-level cap for "platform-initiated cause" | [Measured] | **[Strongly Suggested]** (per binding constraint #1) |
| Evidence level for "client-visible 5xx outcome" | [Measured] | **[Measured]** (preserved) |

This revised design is the binding plan for Stage B implementation.
