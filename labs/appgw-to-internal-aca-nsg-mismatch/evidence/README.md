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
| `broken-curl.txt` | `curl -w '%{http_code}'` against AppGW public IP (after misconfig) | End-to-end HTTP `502` from AppGW proves the failure is observable from a client. |

## Files produced by `fix.sh`

| File | Source | Purpose |
|---|---|---|
| `fixed-backend-health.json` | `az network application-gateway show-backend-health` (after Destination -> CAE CIDR) | Falsification evidence: backend returns to `Healthy` when the ONLY changed variable is rule 100's Destination. |
| `fixed-nsg-rules.json` | `az network nsg rule list` (after fix) | Confirms rule 100 Destination is now the CAE subnet CIDR (e.g. `10.0.2.0/23`) and no other rule changed. |
| `fixed-curl.txt` | `curl -w '%{http_code}'` against AppGW public IP (after fix) | End-to-end HTTP `200` returns. |

## Files produced by `verify.sh`

| File | Purpose |
|---|---|
| `verify-result.json` | Derived gate JSON. Five gates plus a verdict (`HYPOTHESIS_CONFIRMED` / `HYPOTHESIS_NOT_CONFIRMED`) plus a falsification status (`NOT_YET_TESTED` / `FIX_VERIFIED` / `FIX_DID_NOT_RECOVER`). This is the single machine-readable output the lab guide references. |

## Not committed

This lab does not carry a committed evidence pack. Every file listed above is
generated on demand when an operator runs the Quick Start sequence in the
lab's [`README.md`](../README.md). The lab guide (`docs/troubleshooting/lab-guides/appgw-to-internal-aca-nsg-mismatch.md`)
describes the expected evidence shape without pointing at committed sample
files.
