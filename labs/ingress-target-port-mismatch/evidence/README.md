# Evidence pack — `ingress-target-port-mismatch` lab

This directory carries the canonical 2026-06-22 Phase A evidence cohort for the `ingress-target-port-mismatch` lab plus the derived Phase B gate outputs emitted by `labs/ingress-target-port-mismatch/verify.sh`. The claim ceiling is deliberately narrow: this pack proves only what this single `koreacentral` reproduction can support about the app-scope ingress field `properties.configuration.ingress.targetPort`, the edge failure signature it produced, and the bounded post-fix recovery window.

## Capture timeline

Three carry-over framings make the evidence pack readable:

1. **Silent baseline → trigger populated → fix silenced.** The healthy baseline is `targetPort=80` with 10/10 HTTP 200. The trigger changes only the ingress target port to `8081`, after which edge traffic falls to 0/10 HTTP 200 and `ContainerAppSystemLogs_CL` populates with `Pending:PortMismatch` rows. The fix restores `targetPort=80`, the edge returns to 10/10 HTTP 200, and the strictly post-fix KQL window becomes silent for PortMismatch again.
2. **The single-variable claim is bounded to the integer `ingress.targetPort`.** The cohort directly shows that `external`, `transport`, `fqdn`, revision name, and Container App identity stay constant across baseline, trigger, and fix, while the target-port integer changes `80 → 8081 → 80`. The cohort does not directly capture image digest, pod UID reuse, or the container's runtime port table.
3. **The post-fix silence claim is anchored to a strict UTC cutoff.** Gate 16 does not rely on `ago(5m)`. It proves the query was bounded to `TimeGenerated > datetime(2026-06-22T12:25:06Z)`, which is the only valid way to avoid pre-fix tail events contaminating the post-fix window.

Capture phases:

- **Phase A — Live reproduction** (`2026-06-22`): `trigger.sh` captured the healthy baseline, applied the ingress trigger (`targetPort=8081`), drove failed traffic, waited for system-log ingestion, and captured the populated PortMismatch window. `fix-and-capture.sh` then restored `targetPort=80`, re-ran traffic, waited for the post-fix ingestion window, and captured the silent PortMismatch result in the strict post-fix UTC window. The experiment anchors are `03-curl-before.json.utc_completed = 2026-06-22T12:17:34Z`, `09-kql-after-trigger.json.trigger_utc = 2026-06-22T12:17:44Z`, `15-kql-after-fix.json.fix_utc = 2026-06-22T12:25:06Z`, and `15-kql-after-fix.json.utc_query = 2026-06-22T12:31:23Z`.
- **Phase B — Runtime overlay** (`verify.sh` execution time): `verify.sh` is a pure offline file processor. It reads the committed Phase A files already present in this directory, plus `README.md` and the `evidence/` directory listing for Gate 14 integrity checks, and emits `14-cohort-integrity-gate.json`, `15-h1-trigger-produces-failure-gate.json`, `16-h2-fix-restores-recovery-gate.json`, and `17-single-variable-falsification-gate.json`.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: checks (a) canonical-file presence with Strong exact-25 and Fallback ≥23-plus-required-inputs paths, (b) monotonic baseline→trigger→fix→post-fix temporal coherence with Strong ≤30-minute and Fallback ≤90-minute windows, (c) no unexpected non-junk extras, and (d) this README's literal cross-reference to all four gate filenames.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: checks (a) ingress changed `80 → 8081`, (b) edge traffic broke to `requests_ok <= 1`, (c) `portmismatch_rows >= 1` with `gate_classification == populated_table`, and (d) the sample rows include the smoking-gun platform attribution `The TargetPort 8081 does not match the listening port 80.`.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: checks (a) ingress changed back to `80`, (b) edge traffic recovered to `requests_ok >= 8`, (c) `portmismatch_rows == 0` with `gate_classification == silent_valid_baseline`, and (d) the KQL query string itself proves a strict `datetime(${FIX_UTC})` post-fix cutoff.
- **Gate 17 — `17-single-variable-falsification-gate.json`**: checks (a) only the integer `ingress.targetPort` changed across the three-state ingress surface, (b) no new revision was created, (c) the same Container App identity and FQDN were preserved, and (d) the smoking-gun Log_s string substantiates listening-port constancy at `:80` during the trigger.

## Honest disclosure

- The file name `00-verify-run.txt` is preserved for schema stability even though the live Phase A recovery script was renamed to `fix-and-capture.sh` during the Phase B overlay.
- `09-kql-after-trigger.json` and `15-kql-after-fix.json` store row counts such as `portmismatch_rows` and `probefailed_rows` as JSON strings, not numeric JSON values. Phase B casts them with `int(...)` before threshold checks.
- The strongest direct cause attribution comes from `Log_s`, not from a dedicated structured `listeningPort` field. The platform row says `The TargetPort 8081 does not match the listening port 80.` and Gate 17 explicitly treats that as an inference surface, not a raw socket capture.
- The workspace customer ID is present in `23-deployment-outputs.json` and in the historical Phase A stdout, but Phase B gate JSON prose and observed-values deliberately redact it as `<redacted>`.
- The cohort directly proves revision-name constancy across the ingress updates, which is consistent with Microsoft Learn's app-scope ingress documentation. It does not prove that the platform will always preserve revision name forever under every future ACA implementation.
- Pod reuse is not claimed. Replica count varied `1 → 2 → 1` across `02-replicas-before.json`, `06-replicas-after-trigger.json`, and `12-replicas-after-fix.json`, so different pod UIDs may have existed within the same revision.
- Image byte-identity is not cohort-evidenced. The lab uses `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`, but the cohort does not capture digest values.
- The 300-second wait windows are per-reproduction observations, not Azure ingestion SLAs. Microsoft Learn does not publish a strict SLA for how quickly `ContainerAppSystemLogs_CL` rows must appear after the platform emits them.
- The post-fix window is intentionally strict. A relative `ago(5m)` query could include delayed-trigger events and would weaken the falsification.
- `07-revision-status-after-trigger.json` reported `healthState: Healthy` even while the edge returned 503 and PortMismatch rows were materializing. This lab therefore anchors on edge behavior plus KQL attribution, not on a single healthState field.
- The helloworld image is used because this lab tests ingress-to-container port wiring, not application logic, ACR pull path, or custom stdout behavior.
- The sample KQL rows all came from one revision (`distinct_revisions = "1"`), which strengthens the bounded claim that the same revision experienced baseline success, trigger failure, and post-fix recovery.

## File index

| Category | File | Size | Source |
|---|---|---:|---|
| Script log | `00-trigger-run.txt` | 6.4 KB | `bash trigger.sh \| tee evidence/00-trigger-run.txt` |
| Script log | `00-verify-run.txt` | 4.2 KB | `bash fix-and-capture.sh \| tee evidence/00-verify-run.txt` |
| Baseline capture | `01-ingress-config-before.json` | 568 B | `az containerapp show --query "{name, latestRevisionName, ingress: properties.configuration.ingress}"` before trigger |
| Baseline capture | `02-replicas-before.json` | 139 B | `az containerapp replica list --query "[].{name, runningState: properties.runningState, createdTime: properties.createdTime}"` before trigger |
| Baseline traffic | `03-curl-before.json` | 878 B | Python HTTPS loop against the healthy baseline revision |
| Trigger result | `04-ingress-update-result.json` | 138 B | `az containerapp ingress update --target-port 8081 --query "{external, targetPort, transport, fqdn}"` |
| Trigger capture | `05-ingress-config-after-trigger.json` | 570 B | Post-trigger ingress readback |
| Trigger capture | `06-replicas-after-trigger.json` | 276 B | Replica list after trigger propagation |
| Trigger capture | `07-revision-status-after-trigger.json` | 136 B | `az containerapp revision show` on the unchanged revision after trigger |
| Trigger traffic | `08-curl-after-trigger.json` | 970 B | Python HTTPS loop against the triggered state (0/10 HTTP 200) |
| Trigger KQL raw | `09-kql-after-trigger-portmismatch-raw.txt` | 126 B | Raw summarize-query output for the strictly post-trigger PortMismatch window |
| Trigger KQL raw | `09-kql-after-trigger-portmismatch-sample-raw.txt` | 1.6 KB | Raw sample-query output showing the smoking-gun rows |
| Trigger KQL parsed | `09-kql-after-trigger.json` | 3.0 KB | Parsed trigger-window KQL result and classification |
| Fix result | `10-ingress-update-fix-result.json` | 136 B | `az containerapp ingress update --target-port 80 --query "{external, targetPort, transport, fqdn}"` |
| Fix capture | `11-ingress-config-after-fix.json` | 568 B | Post-fix ingress readback |
| Fix capture | `12-replicas-after-fix.json` | 139 B | Replica list after fix propagation |
| Fix capture | `13-revision-status-after-fix.json` | 136 B | `az containerapp revision show` on the unchanged revision after fix |
| Fix traffic | `14-curl-after-fix.json` | 877 B | Python HTTPS loop against the fixed state (10/10 HTTP 200) |
| Fix KQL raw | `15-kql-after-fix-portmismatch-raw.txt` | 124 B | Raw summarize-query output for the strict post-fix PortMismatch window |
| Fix KQL raw | `15-kql-after-fix-portmismatch-sample-raw.txt` | 3 B | Raw sample-query output for the strict post-fix window (`[]`) |
| Fix KQL parsed | `15-kql-after-fix.json` | 1.4 KB | Parsed post-fix KQL result and classification |
| Environment capture | `20-cli-versions.json` | 272 B | `az version --output json` |
| Environment capture | `21-cli-containerapp-ext.json` | 126 B | `az extension list --query "[?name=='containerapp']" --output json` |
| Environment capture | `22-region.json` | 26 B | Region anchor |
| Deployment outputs | `23-deployment-outputs.json` | 868 B | `az deployment group show --name main --query properties.outputs --output json` |
| Phase B gate JSON | `14-cohort-integrity-gate.json` | generated | `bash verify.sh` Gate 14 output |
| Phase B gate JSON | `15-h1-trigger-produces-failure-gate.json` | generated | `bash verify.sh` Gate 15 output |
| Phase B gate JSON | `16-h2-fix-restores-recovery-gate.json` | generated | `bash verify.sh` Gate 16 output |
| Phase B gate JSON | `17-single-variable-falsification-gate.json` | generated | `bash verify.sh` Gate 17 output |
| Documentation | `README.md` | this file | Phase B evidence-pack tour, gate descriptions, disclosures, and file index |

## CLI versions and platform context

- Azure CLI context is preserved in `20-cli-versions.json` and `21-cli-containerapp-ext.json` (`azure-cli 2.79.0`, `containerapp 1.3.0b4`).
- Region anchor is preserved in `22-region.json` (`koreacentral`).
- The deployed Container App name is `ca-ingressport-2inkav`; the environment is `cae-ingressport-2inkav`; the workspace name is `log-ingressport-2inkav`.
- The application image is the public placeholder image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`.
- The evidence directory totals 30 files after Phase B: 25 canonical Phase A inputs + 4 derived gate JSONs + this README.

## Reproducibility

```bash
cd labs/ingress-target-port-mismatch/
bash verify.sh
```

The verifier reads only the committed evidence files in this directory, emits the four gate JSONs, prints per-gate and total sub-gate pass counts, and exits 0 only when all 16 sub-gates pass.
