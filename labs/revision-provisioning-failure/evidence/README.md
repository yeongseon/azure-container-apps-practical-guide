# Evidence pack — `revision-provisioning-failure` lab

This directory carries the reusable Jun 20 / Jun 21 raw evidence cohort for the `revision-provisioning-failure` lab plus the derived Phase B gate outputs emitted by `labs/revision-provisioning-failure/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what this single `koreacentral` reproduction can support about the wrong-path startup-probe failure on `ca-labrevprov-e2upm2`, the recovered `badpath3` revision, and the bounded causal claim that probe-path reachability is the mechanically observable trigger field.

## Capture timeline

1. **Baseline / H1 surface.** `01-revision-list.json`, `02-failed-revision-detail.json`, `03-containerapp-spec.yaml`, `04-system-logs.json`, `05-replicas-failed.json`, `06-console-logs.json`, `07-kql-probefailed-rows.json`, `08-kql-event-correlation.json`, `09-kql-summary-by-reason.json`, and `10-kql-console-logs.json` capture the failing `badpath2` revision.
2. **H2 recovery surface.** `11-kql-postfix-verification.json` and `12-revision-list-recovered.json` capture the recovered `badpath3` revision after the probe path is corrected to `/`.
3. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, temporal boundedness, lineage coherence, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves the wrong-path startup probe produced the documented failure.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves the corrected `/` probe produced a healthy recovered revision.
- **Gate 17 — `17-bounded-falsification-gate.json`**: bounds the causal claim to probe-path reachability and explicitly lists the confounders that are not bounded.

## Honest disclosure

- The pack reuses committed raw captures; no fresh Azure deployment was needed for Phase B.
- `04-system-logs.json` and `06-console-logs.json` are JSONL/NDJSON files, not JSON arrays; `verify.sh` parses them one record per line.
- The pack does not capture image digests, pod UIDs, or direct socket inspection; those gaps are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.
- The full baseline-to-fix cohort spans ~53 minutes, so Gate 14 uses the documented `5400`-second fallback ceiling instead of the `1800`-second strong ceiling.

## File index

| File | Size | Captured | Purpose |
|---|---:|---|---|
| `01-revision-list.json` | 3.7 KB | 2026-06-20 | H1 revision baseline: `badpath` + failed `badpath2` |
| `02-failed-revision-detail.json` | 1.7 KB | 2026-06-20 | Failed revision smoking gun (`Unhealthy`, `Failed`, `Container crashing: app`) |
| `03-containerapp-spec.yaml` | 5.8 KB | 2026-06-20 | Cohort spec and bad-path startup probe |
| `04-system-logs.json` | 13.5 KB | 2026-06-20 | Raw system restart-loop evidence (`ProbeFailed`, `ContainerTerminated`) |
| `05-replicas-failed.json` | 1.8 KB | 2026-06-20 | Failed replica surface (`CrashLoopBackOff`, `NotRunning`) |
| `06-console-logs.json` | 6.7 KB | 2026-06-20 | Raw nginx startup, 404, and shutdown evidence |
| `07-kql-probefailed-rows.json` | 16.7 KB | 2026-06-20 | KQL ProbeFailed evidence for `badpath2` |
| `08-kql-event-correlation.json` | 26.4 KB | 2026-06-20 | KQL lifecycle correlation (`ContainerStarted` → `ProbeFailed` → `ContainerTerminated`) |
| `09-kql-summary-by-reason.json` | 5.9 KB | 2026-06-20 | H1 summary counts by reason |
| `10-kql-console-logs.json` | 26.7 KB | 2026-06-20 | Application-level KQL smoking gun: nginx 404 on the bad path |
| `11-kql-postfix-verification.json` | 7.1 KB | 2026-06-20 | Post-fix KQL verification by revision |
| `12-revision-list-recovered.json` | 1.6 KB | 2026-06-20 | H2 recovered revision `badpath3` with path `/` |
| `14-cohort-integrity-gate.json` | 9.3 KB | Phase B runtime | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | 4.6 KB | Phase B runtime | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | 5.2 KB | Phase B runtime | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | 7.8 KB | Phase B runtime | Derived Gate 17 output |

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/revision-provisioning-failure/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort. |

```bash
cd labs/revision-provisioning-failure/
bash verify.sh
```

The verifier reads only the committed files in this directory, emits four gate JSONs, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
