# Evidence Pack Provenance

This directory contains the raw evidence artifacts for the `probe-and-port-mismatch` lab run on **2026-06-23**. All files are PII-scrubbed (subscription/tenant GUIDs replaced with the zero-GUID placeholder, employee aliases replaced with `demouser`, employee emails replaced with `user@example.com`, long uppercase hex tokens replaced with `AAAA…A` placeholders).

## Capture timeline

The lab evidence was assembled in two phases on **2026-06-23**:

1. **Original fault injection (14:05–14:06 UTC).** The trigger script's ACR build and image-update phases minted revision `ca-labport-zopng3--0000001` into the Failed/Degraded state. This phase produced `03-acr-build.log`, `04-registry-set.json`, `05-containerapp-update-image.json`, `05-containerapp-update-image.stderr`, and `06-wait-provisioning.log`. The `build_window.start_utc` (`2026-06-23T14:05:12Z`) and `trigger_window.start_utc` (`2026-06-23T14:05:47Z`) fields embedded in `11-h1-gate.json` reflect this original fault-injection window, NOT the snapshot capture time.

2. **Strengthened snapshot capture (22:23–22:40 UTC).** After the trigger script's Phase 5 provisioning poll was strengthened to **30 attempts × 10 s** (5-minute ceiling), the evidence-capture phases (`07-*` through `24-*`) were re-run against the still-failed revision `ca-labport-zopng3--0000001` without re-building or re-updating the image. This phase produced the failed-state revision snapshots (`07-revision-list-failed.json`, `08-revision-show-failed.json`), the client-probe results (`09-curl-probes-failed.json`), the system-log tail (`10-system-logs-tail.log`), and the H1/H2 gate decisions (`11-h1-gate.json`, `22-h2-gate.json`). The `utc_captured` field on each gate JSON (`2026-06-23T22:23:35Z` for H1) reflects this strengthened-window snapshot time.

All H1 and H2 sub-gate decisions reference artifacts from the strengthened-window capture (`07-*` through `24-*`). The earlier `01-*` through `06-*` files are preserved as honest evidence of the infra-resolve and fault-injection chain.

## Non-gating artifact: `06-wait-provisioning.log`

`06-wait-provisioning.log` is a **single-line snapshot** from the original 14:05–14:06 UTC fault-injection phase that pre-dates the Phase 5 strengthening (which moved from 1 attempt to 30 attempts). It is preserved as honest historical evidence of the polling-window variance described in the lab guide's `### Observed Evidence (Live Azure Test — 2026-06-23)` subsection, but it is **explicitly non-gating**:

- The H1 gate file (`11-h1-gate.json`) does NOT reference `06-wait-provisioning.log` for any sub-gate decision. The H1 `c_probe_failure_evidence_present` sub-gate evaluates `08-revision-show-failed.json` (revision state + runningStateDetails) and `10-system-logs-tail.log` (ProbeFailed count), not the wait-poll log.
- The H2 gate file (`22-h2-gate.json`) makes no reference to the wait-poll log at all.
- Future runs of the current `trigger.sh` will produce a multi-attempt `06-wait-provisioning.log` reflecting the strengthened polling logic. The 06 file therefore documents a one-time historical capture window, not a recurring evidence shape.

## File index

| Phase | Files | Source |
|---|---|---|
| Trigger setup | `01-*` through `04-*` | `trigger.sh` infra resolve, baseline, ACR build |
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
