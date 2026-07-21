# Evidence pack — `aca-secret-kv-ref-mi-network-path-h4d` lab

This directory is the local workspace for the **reader-generated** Phase B evidence pack for `aca-secret-kv-ref-mi-network-path-h4d`. The repository does not ship a committed cohort for this lab; the files below are created by your own run.

- `labs/aca-secret-kv-ref-mi-network-path-h4d/trigger.sh` writes the H0 baseline raw files (`01`-`05`).
- `labs/aca-secret-kv-ref-mi-network-path-h4d/falsify.sh` writes the H1 Routing-Intent and H2 Routing-Intent-removal raw files (`06`-`13`).
- `labs/aca-secret-kv-ref-mi-network-path-h4d/verify.sh` reads only those local raw files and writes the derived gate JSONs (`14`-`17`).

The claim ceiling is intentionally narrow. A passing run proves only one live reproduction where H0 succeeds without an active Routing Intent path through the secured hub, H1 fails when Routing Intent converges and the HubVirtualNetworkConnection effective route for `0.0.0.0/0` targets the hub firewall, and H2 succeeds again after Routing Intent is removed while the firewall policy stays unchanged.

## Capture timeline

1. **H0 baseline.** `trigger.sh` writes `01`-`05`: workload deployment, healthy app baseline, out-of-band Key Vault secret creation, successful `az containerapp secret set`, `kvref-h0` present, and baseline revision anchored.
2. **H1 Routing Intent trigger.** `falsify.sh` writes `06`-`09`: the ACTUAL ACA infrastructure VNet is connected to the Virtual Hub, Routing Intent is enabled toward the hub Azure Firewall, effective routes show `0.0.0.0/0` targeting the firewall, `az containerapp secret set` fails, the app still serves HTTP 200 on the same revision, `kvref-h1` stays absent, and an optional Azure Firewall diagnostic clue is captured without being used as the pass condition.
3. **H2 Routing Intent removal.** `falsify.sh` continues with `10`-`13`: Routing Intent is removed, the effective routes no longer show `0.0.0.0/0` targeting the firewall, a **new** `az containerapp secret set` succeeds, `kvref-h2` appears, and an optional post-removal Azure Firewall clue is captured.
4. **Phase B overlay.** `verify.sh` re-parses the raw cohort and deterministically writes Gate 14 through Gate 17.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates file presence, parseability, monotonic UTC ordering, cross-file anchor consistency, the revision silence invariant, and the same HubVirtualNetworkConnection anchor across H1/H2.
- **Gate 15 — `15-h1-routing-intent-produces-failure-gate.json`**: proves H1 enabled Routing Intent, effective routes targeted the hub firewall, the secret-set call failed with the MI / `openid-configuration` markers, and `kvref-h1` stayed absent while ingress remained HTTP 200.
- **Gate 16 — `16-h2-routing-intent-removal-restores-success-gate.json`**: proves H2 removed Routing Intent, effective routes no longer targeted the hub firewall, the new secret-set call succeeded, and `kvref-h2` appeared while ingress remained HTTP 200.
- **Gate 17 — `17-bounded-falsification-gate.json`**: states the bounded H1↔H2 claim explicitly — Routing Intent changed, while Key Vault, identity, app health, connection anchor, and firewall policy stayed constant.

## File index

| File | Purpose |
|---|---|
| `01-deployment-outputs.json` | Bicep deployment outputs and topology anchors |
| `02-h0-app-state-before.json` | Container app baseline surface before H0 secret set |
| `03-h0-kv-secret-created.json` | Key Vault secret created out-of-band for H0 |
| `04-h0-secret-set-outcome.json` | H0 outcome: secret set succeeds |
| `05-h0-app-state-after.json` | H0 post-state: revision unchanged, `kvref-h0` present |
| `06-h1-routing-intent-enabled.json` | H1 route-state proof: HubVirtualNetworkConnection + Routing Intent converged, effective routes show `0.0.0.0/0` targeting the hub firewall |
| `07-h1-secret-set-outcome.json` | H1 outcome: secret set fails with MI / `openid-configuration` markers |
| `08-h1-app-state.json` | H1 silence gate: revision unchanged, ingress HTTP 200, `kvref-h1` absent |
| `09-h1-azfw-diagnostic-clue.json` | Optional Azure Firewall log clue; never the deterministic pass condition |
| `10-h2-routing-intent-removed.json` | H2 route-state proof: Routing Intent removed, effective routes no longer target the hub firewall |
| `11-h2-secret-set-outcome.json` | H2 outcome: new secret-set attempt succeeds |
| `12-h2-app-state.json` | H2 success gate: revision unchanged, ingress HTTP 200, `kvref-h2` present |
| `13-h2-azfw-diagnostic-clue.json` | Optional post-removal Azure Firewall log clue |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-routing-intent-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-routing-intent-removal-restores-success-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

The verifier is hermetic once the raw cohort exists: `verify.sh` reads only local files `01`-`13`, rewrites the four derived gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and makes no Azure calls. You can re-run `verify.sh` offline after `cleanup.sh` deletes the resource group, provided the local raw files remain in place.
