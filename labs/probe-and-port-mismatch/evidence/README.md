# Evidence Pack Provenance

This directory contains the raw evidence artifacts for the `probe-and-port-mismatch` lab run on **2026-06-23**. All files are PII-scrubbed (subscription/tenant GUIDs replaced with the zero-GUID placeholder, employee aliases replaced with `demouser`, employee emails replaced with `user@example.com`, long uppercase hex tokens replaced with `AAAA…A` placeholders).

## Capture timeline

Most artifacts (`07-*` through `24-*`) were captured during a single coherent run on **2026-06-23 22:23–22:40 UTC**, after the trigger script's Phase 5 provisioning poll was strengthened to **30 attempts × 10 s** (5-minute ceiling). All H1 and H2 sub-gate decisions reference artifacts from this strengthened window.

## Non-gating artifact: `06-wait-provisioning.log`

`06-wait-provisioning.log` is a **single-line snapshot** from an earlier trigger run (2026-06-23 14:06 UTC) that pre-dates the Phase 5 strengthening (which moved from 1 attempt to 30 attempts). It is preserved as honest historical evidence of the polling-window variance described in the lab guide's `### Observed Evidence (Live Azure Test — 2026-06-23)` subsection, but it is **explicitly non-gating**:

- The H1 gate file (`11-h1-gate.json`) does NOT reference `06-wait-provisioning.log` for any sub-gate decision. The H1 `c_probe_failure_evidence_present` sub-gate evaluates `08-revision-show-failed.json` (revision state + runningStateDetails) and `10-system-log-tail.log` (ProbeFailed count), not the wait-poll log.
- The H2 gate file (`22-h2-gate.json`) makes no reference to the wait-poll log at all.
- Future runs of the current `trigger.sh` will produce a multi-attempt `06-wait-provisioning.log` reflecting the strengthened polling logic. The 06 file therefore documents a one-time historical capture window, not a recurring evidence shape.

## File index

| Phase | Files | Source |
|---|---|---|
| Trigger setup | `00-*` through `04-*` | `trigger.sh` infra resolve, baseline, ACR build |
| Trigger fault injection | `05-*` through `10-*` | `trigger.sh` update image, wait, capture failure state |
| H1 gate | `11-h1-gate.json` | `trigger.sh` Phase 9 — 5 sub-gates evaluated |
| Verify pre-fix | `12-*` through `13-*` | `verify.sh` re-confirm failure state + client probes |
| Verify fix | `14-*` through `15-*` | `verify.sh` ingress update + recovery poll |
| Verify post-fix | `16-*` through `21-*` | `verify.sh` post-fix revision state + client probes + metadata |
| H2 gate | `22-h2-gate.json` | `verify.sh` Phase 18 — 6 sub-gates evaluated |
| Cleanup | `23-*`, `24-*` | `cleanup.sh` pre-cleanup inventory + async delete |

## Reproducibility

To reproduce this evidence pack against a fresh Azure subscription:

```bash
cd labs/probe-and-port-mismatch
bash deploy-infra.sh    # provisions ACR + Container Apps env + initial app
bash trigger.sh         # ACR build + image update + capture failure (emits 11-h1-gate.json)
bash verify.sh          # ingress fix + recovery capture (emits 22-h2-gate.json)
bash cleanup.sh         # async resource group delete
```

Expected runtime: ~30 minutes total. Estimated cost: <$0.50 USD (Consumption plan, single container, Basic ACR SKU, single 5 KB Python image).
