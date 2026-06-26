# Evidence pack — `dapr-integration` lab

This directory carries the live raw evidence cohort for the `dapr-integration` lab plus the derived Phase B gate outputs emitted by `labs/dapr-integration/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what a single `koreacentral` Flask-on-8000 reproduction can support about the Dapr `appPort` mismatch on one Azure Container Apps deployment. It preserves the historical 2026-06-03 helloworld Portal captures as additive context, but the bounded causal claim is based on the new Flask cohort because that workload actually listens on `8000`.

## Capture timeline

1. **H1 failure surface.** `01-app-spec-pre-fix.json` through `08-kql-console-logs-pre-fix.json` capture the triggered `appPort=8081` state, the active broken revision, the Dapr config, the still-healthy ingress response, the failing loopback Dapr invocation, system logs, the full pre-fix app spec, and Log Analytics context.
2. **H2 recovery surface.** `09-dapr-config-post-fix.json` through `12-kql-recovery-summary-post-fix.json` capture the restored `appPort=8000` state, successful ingress response, recovered revision, and post-fix KQL reason summary.
3. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, temporal boundedness, lineage coherence, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves the pre-fix Dapr config changed to `appPort=8081`, ingress `/` still returned HTTP 200, and loopback Dapr invoke failed.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves the post-fix Dapr config restored `appPort=8000`, ingress `/` still returns HTTP 200, the post-fix capture window is healthy/running, and the recovery summary still shows startup activity in that restore window.
- **Gate 17 — `17-bounded-falsification-gate.json`**: bounds the causal claim to the Dapr `appPort` field while explicitly listing unsupported inferences.

## Honest disclosure

- The pack captures a single live Azure cohort; it is not a statistical sample across regions or tenants.
- `06-system-logs-pre-fix.json` is JSONL/NDJSON, not a JSON array; `verify.sh` parses it one record per line.
- The historical 2026-06-03 Portal screenshots remain important because they document the original `containerapps-helloworld` limitation that kept the older reproduction `[Not Proven]` for clean falsification.
- The pack does not prove image byte identity, pod UID continuity, Dapr sidecar PID continuity, exact Dapr health-probe timing, or exact DNS-resolution timing. Those ceilings are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Pre-fix app + Dapr + ingress surface after the trigger |
| `02-revision-list-pre-fix.json` | Active broken revision carrying `appPort=8081` |
| `03-dapr-config-pre-fix.json` | Pre-fix Dapr config with `enabled=true` and `appPort=8081` |
| `04-http-response-pre-fix.json` | Pre-fix ingress root response showing HTTP 200 reachability |
| `05-dapr-invoke-pre-fix.json` | Pre-fix loopback Dapr invocation attempt showing failure |
| `06-system-logs-pre-fix.json` | Raw system-log capture around the reproduction window |
| `07-containerapp-spec-pre-fix.yaml` | Full pre-fix container app spec |
| `08-kql-console-logs-pre-fix.json` | Log Analytics context around the failure window |
| `09-dapr-config-post-fix.json` | Post-fix Dapr config with `appPort=8000` |
| `10-http-response-post-fix.json` | Post-fix ingress root response |
| `11-revision-list-post-fix.json` | Post-fix recovered revision |
| `12-kql-recovery-summary-post-fix.json` | Post-fix KQL reason summary by revision |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/dapr-integration/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort without touching Azure. |

```bash
cd labs/dapr-integration/
bash verify.sh
```
