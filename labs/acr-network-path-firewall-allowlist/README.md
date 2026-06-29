# Lab: ACR Network Path A — Firewall Allowlist

Reproduce **Scenario A** from
[ACR Network Path Selection](../../docs/platform/networking/acr-network-path-selection.md):
the Container Apps replica reaches ACR over ACR's **public** FQDN, but
that egress is forced through an Azure Firewall whose SNAT public IP
is the **only** entry in ACR's `networkRuleSet.ipRules` allowlist.

The selected-networks IP rule on ACR is therefore keyed on the
**firewall's outbound public IP**, not on any replica IP. In the final
Phase B form, the lab carries a committed evidence pack that proves the
full baseline → broken → recovery arc with one cached `v1` revision,
one failed `v-broken` revision, and one recovered `v-recover` revision.

## Architecture

```text
Container App replica (10.80.0.x in snet-aca)
       │  docker login + image pull over public ACR FQDN
       ▼
UDR 0.0.0.0/0 -> Azure Firewall private IP
       ▼
Azure Firewall Basic
       │  application rules allow ACR login + data FQDNs
       │  SNAT to firewall public IP
       ▼
ACR Premium (public endpoint)
  publicNetworkAccess=Enabled
  networkRuleSet.defaultAction=Deny
  networkRuleBypassOptions=None
  ipRules=[<firewall public IP>]  <-- controlled variable
```

## Structure

```text
labs/acr-network-path-firewall-allowlist/
├── infra/main.bicep
├── workload/
├── trigger.sh
├── verify.sh
├── falsify.sh
├── fix-and-capture.sh
├── cleanup.sh
├── evidence/
│   ├── 01-12 raw cohort
│   ├── 14-17 derived gate JSONs
│   └── README.md
└── README.md
```

## Quick Start

```bash
export RG="rg-acr-firewall-allowlist-lab"
export LOCATION="koreacentral"
export BASE_NAME="acrfwallow"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" --name acr-firewall-allowlist \
    --template-file labs/acr-network-path-firewall-allowlist/infra/main.bicep \
    --parameters baseName="$BASE_NAME"

bash labs/acr-network-path-firewall-allowlist/trigger.sh
bash labs/acr-network-path-firewall-allowlist/verify.sh
bash labs/acr-network-path-firewall-allowlist/falsify.sh
bash labs/acr-network-path-firewall-allowlist/cleanup.sh
```

## What “Success” Looks Like

The lab is reproduced when all of the following hold:

1. The baseline `v1` revision is `Healthy`, ACR is locked down, and `/` returns `build_tag=v1`.
2. Removing the firewall public IP from `networkRuleSet.ipRules` causes the `v-broken` revision to fail with a DENIED/403 surface naming that firewall public IP.
3. The already-cached `v1` revision keeps serving `/` with `build_tag=v1` during H1.
4. Re-adding the firewall public IP restores fresh-pull behavior and the latest `v-recover` revision becomes `Healthy` with `/` returning `build_tag=v-recover`.

## Phase B Evidence Pack

The committed Phase B cohort lives in [`evidence/`](evidence/README.md).

- The raw cohort contains 12 files (`01`-`12`) plus four derived gate JSONs (`14`-`17`).
- Gate 14 proves cohort integrity: canonical files present, parseable, bounded in one UTC window, same lineage, and all four cohort anchors consistent.
- Gate 15 proves H1: baseline-presence, pre-fix allowlist removal, DENIED/403 naming the firewall public IP, failed `v-broken`, and cached `v1` silence.
- Gate 16 proves H2: allowlist restored, healthy `v-recover`, successful recovery pull markers, and the post-fix evidence shows `v-broken` was not retroactively repaired after explicit deactivation.
- Gate 17 performs the bounded H1↔H2 diff and carries the non-vacuous silence-gate proof required for this final Path A pack.

For future live reproductions:

```bash
cd labs/acr-network-path-firewall-allowlist/
bash fix-and-capture.sh
```

For offline reruns:

```bash
cd labs/acr-network-path-firewall-allowlist/
bash verify.sh
```

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| Azure Firewall Basic + 2 public IPs | ~$24 / day |
| ACR Premium | $1.67 / day |
| Container Apps + Log Analytics | <$0.25 / hour |
| **Total for a 2-3 hour run** | **~$3-4** |

Delete the resource group immediately after capturing evidence; the firewall dominates the cost.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md`
- Platform: `docs/platform/networking/acr-network-path-selection.md`
- Related lab: `labs/acr-network-path-pe-direct/`
- Related lab: `labs/acr-network-path-pe-forced-inspection/`
