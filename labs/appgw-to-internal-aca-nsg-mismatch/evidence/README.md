# Evidence Pack

This directory holds the raw evidence produced by `trigger.sh` and `fix.sh`,
plus the derived gate JSON produced by `verify.sh`.

## Files produced by `trigger.sh`

| File | Source | Purpose |
|---|---|---|
| `deploy-outputs.json` | `az deployment group show ... --query properties.outputs` | Canonical source of resource names, `staticIp`, subnet CIDRs, AppGW public IP. Consumed by every downstream script. |
| `baseline-backend-health.json` | `az network application-gateway show-backend-health` (before misconfig) | Proves the deployment starts in a Healthy state — the H1 argument requires this positive control. |
| `baseline-nsg-rules.json` | `az network nsg rule list` (before misconfig) | Proves the CAE subnet NSG had only Azure defaults before rule 100 was added. |
| `baseline-curl.txt` | `curl -w '%{http_code}'` against AppGW public IP (before misconfig) | End-to-end HTTP `200` proves the AppGW routes to the container app. |
| `broken-backend-health.json` | `az network application-gateway show-backend-health` (after misconfig) | The failure evidence — every backend server transitions to `Unhealthy` once rule 100 pins Destination to `staticIp/32`. |
| `broken-nsg-rules.json` | `az network nsg rule list` (after misconfig) | Documents the exact 3-rule state (100 Allow-appgw, 200 Allow-LB, 4096 Deny-all) so a reviewer can verify only rule 100 is misconfigured. |
| `broken-curl.txt` | `curl -w '%{http_code}'` against AppGW public IP (after misconfig) | End-to-end HTTP `502` from AppGW OR HTTP `000` from client timeout — either is consistent with H1. On the currently committed evidence pack (`2026-07-04` re-executed live run) the observed value was HTTP `502` in ~0.3 s, matching the original hypothesis prediction. See the lab guide's [`Client-side evidence`](../../../docs/troubleshooting/lab-guides/appgw-to-internal-aca-nsg-mismatch.md#client-side-evidence) section for the full explanation. |

## Files produced by `fix.sh`

| File | Source | Purpose |
|---|---|---|
| `fixed-backend-health.json` | `az network application-gateway show-backend-health` (after Destination -> CAE CIDR) | Falsification evidence: backend returns to `Healthy` when the ONLY changed variable is rule 100's Destination. |
| `fixed-nsg-rules.json` | `az network nsg rule list` (after fix) | Confirms rule 100 Destination is now the CAE subnet CIDR (e.g. `10.0.2.0/23`) and no other rule changed. |
| `fixed-curl.txt` | `curl -w '%{http_code}'` against AppGW public IP (after fix) | End-to-end HTTP `200` returns. |

## Files produced by `verify.sh`

| File | Purpose |
|---|---|
| `verify-result.json` | Derived gate JSON. Seven gates (A/B/C for H1 confirmation, D/E for falsification, F/G for H2 and H3 exclusion) plus a verdict (`HYPOTHESIS_CONFIRMED` / `HYPOTHESIS_NOT_CONFIRMED`) plus a falsification status (`NOT_YET_TESTED` / `FIX_VERIFIED` / `FIX_DID_NOT_RECOVER`). This is the single machine-readable output the lab guide references. |

## Committed evidence pack (2026-07-04 re-executed live run)

This directory carries a committed evidence pack captured on the `2026-07-04` re-executed live run of this lab in Korea Central (azure-cli `2.79.0`). The initial `2026-07-03` live run surfaced a CAE FQDN routing quirk that is now fixed in `infra/main.bicep` (see the lab guide's success admonition for the full explanation); the `2026-07-04` re-execution captured the artifact set now in-tree against a fresh deployment. Every file listed above is a real artifact from the `2026-07-04` re-execution, with all real GUIDs (subscription ID, ETags, Log Analytics workspace `customerId`) masked to the [zero-GUID placeholder](../../../AGENTS.md#pii-removal-quality-gate) `00000000-0000-0000-0000-000000000000` (with numeric suffixes `-001`, `-002`, `-003` used to keep distinct ETag values distinguishable in JSON diffs). All non-GUID fields (resource names, subnet CIDRs, ports, health-status strings, probe error text) are unmodified from the raw `az` CLI output. Reproducing the lab from `README.md` will regenerate these files with your subscription's real GUIDs — commit only after re-sanitizing.

The `2026-07-04` re-executed run yielded `verify-result.json` with all seven gates `true`, `verdict = HYPOTHESIS_CONFIRMED`, `falsification = FIX_VERIFIED`, and `verify.sh` exit `0`. The lab guide's `## 4) Experiment Log` cites each committed file above by name.
