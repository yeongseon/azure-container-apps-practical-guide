# Lab: ACA Secret Key Vault Reference — Managed Identity Network Path

Reproduce the failure surface documented in
[Container Apps: Secret and Key Vault Reference Failure](../../docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)
Hypothesis **H4 — MI OIDC discovery blocked by egress control**:

`az containerapp secret set --identity system --key-vault-url ...` fails with

```text
Failed to update secrets. Error details: Unable to get value using Managed identity.
Get "https://login.microsoftonline.com/<tenant>/.well-known/openid-configuration": EOF
```

The root cause is not a Key Vault permission problem and not a network path to Key Vault itself. The Container Apps workload subnet's UDR (`0.0.0.0/0 → Azure Firewall`) forces egress through an Azure Firewall Policy that does not permit the Entra ID authority FQDNs (`login.microsoftonline.com` and `login.microsoft.com`). Managed identity OIDC discovery fails **before** any token acquisition attempt, so the caller never reaches Key Vault at all. The pack proves that adding an Application Rule for those two FQDNs is the sole controlled variable that restores success.

## Architecture

```text
Container App (system-assigned MI)
  in subnet snet-aca (10.90.0.0/23)
       │  az containerapp secret set --identity system --key-vault-url ...
       │  → control-plane worker resolves the KV URL, then must reach the
       │    Entra authority to fetch OIDC discovery before acquiring a token
       ▼
UDR 0.0.0.0/0 → Azure Firewall private IP
       ▼
Azure Firewall Basic  (Policy: fp-aca-secret-kv-ref-mi-network-path)
       │  Application Rule Collection: allow-entra-authority
       │  Rule: allow-entra-login
       │  Destination FQDNs:
       │    - login.microsoftonline.com   ← controlled variable
       │    - login.microsoft.com         ← controlled variable (both together)
       ▼
Entra ID authority (public)
       │  .well-known/openid-configuration → token endpoint
       ▼
Key Vault (public endpoint, RBAC-granted "Key Vault Secrets User" to the MI)
```

## Structure

```text
labs/aca-secret-kv-ref-mi-network-path/
├── infra/main.bicep
├── trigger.sh
├── falsify.sh
├── verify.sh
├── cleanup.sh
├── evidence/
│   ├── 01-13 raw cohort (written locally by trigger.sh and falsify.sh)
│   ├── 14-17 derived gate JSONs (written locally by verify.sh)
│   └── README.md
└── README.md
```

## Quick Start

```bash
export RG="rg-aca-secret-kv-ref-mi-network-path"
export LOCATION="koreacentral"
export BASE_NAME="acasecretmi"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" --name aca-secret-kv-ref-mi-network-path \
    --template-file labs/aca-secret-kv-ref-mi-network-path/infra/main.bicep \
    --parameters baseName="$BASE_NAME"

bash labs/aca-secret-kv-ref-mi-network-path/trigger.sh
bash labs/aca-secret-kv-ref-mi-network-path/falsify.sh
bash labs/aca-secret-kv-ref-mi-network-path/verify.sh
bash labs/aca-secret-kv-ref-mi-network-path/cleanup.sh
```

## What "Success" Looks Like

The lab is reproduced when all of the following hold:

1. **H0 baseline**: With the Application Rule present, `az containerapp secret set --identity system --key-vault-url ...` succeeds. The secret `kvref-h0` appears in `configuration.secrets` with a `keyVaultUrl` field. The app's `latestReadyRevisionName` does not change (secret updates do not create new revisions).
2. **H1 failure surface**: After removing the Application Rule Collection `allow-entra-authority`, the same command fails with `Failed to update secrets` → `Unable to get value using Managed identity` → `Get https://login.microsoftonline.com/<tenant>/.well-known/openid-configuration: EOF`. The exit code is non-zero. `kvref-h1` is absent from `configuration.secrets`. The revision name is unchanged. Ingress still returns HTTP 200 (silence gate: the app is not degraded, only the control-plane secret update is blocked). The firewall log carries a `Deny` action row for `login.microsoftonline.com` from the ACA subnet source IP.
3. **H2 recovery surface**: After restoring the Application Rule Collection with **both** `login.microsoftonline.com` and `login.microsoft.com` in one atomic rule, the command succeeds. `kvref-h2` appears in `configuration.secrets`. The revision name is still unchanged from baseline. The firewall log carries an `Allow` action row for the same destination FQDN.

## Phase B Evidence Pack (reader-generated)

The 17-gate Phase B workflow is reader-generated: this repository does not ship a committed evidence cohort for this lab. Running `trigger.sh` and `falsify.sh` writes the raw cohort files (`01`-`13`) into your local [`evidence/`](evidence/README.md) directory; then `verify.sh` reads only those local files and deterministically emits the four derived gate JSONs (`14`-`17`). No live Azure calls happen inside `verify.sh`.

- Gate 14 proves cohort integrity: canonical files present, parseable, bounded in one UTC window, same lineage, and four cohort anchors consistent (app FQDN, firewall policy name, LAW customer ID, ACA subnet prefix). Sub-gate `revision_silence_invariant` proves the `latestReadyRevisionName` is identical across the four cohort snapshots (02, 05, 08, 12) — this is the non-vacuous silence-gate proof required for a secret-update lab, since secret updates never create new revisions.
- Gate 15 proves H1: rule collection removed and confirmed absent, `az containerapp secret set` exit code non-zero, `kvref-h1` absent from `configuration.secrets`, ingress HTTP 200 (silence), and a firewall Deny row for the Entra authority FQDN from the ACA subnet.
- Gate 16 proves H2: rule collection restored with BOTH FQDNs in the same rule (one atomic remove reverses to one atomic add), `az containerapp secret set` exit code 0, `kvref-h2` present in `configuration.secrets`, ingress HTTP 200, and a firewall Allow row for the Entra authority FQDN.
- Gate 17 performs the bounded H1↔H2 diff and enumerates the explicit drops (stderr wording, log ingestion latency, retry cadence, component identity, response body shape, token caching, SKU generality, region generality) that the workflow does **not** claim.

Once you have generated the local cohort, you can re-run `verify.sh` offline (no Azure calls) as often as needed, even after `cleanup.sh` has deleted the resource group — provided the local files 01-13 remain in place:

```bash
cd labs/aca-secret-kv-ref-mi-network-path/
bash verify.sh
```

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| Azure Firewall Basic + 2 public IPs | ~$24 / day |
| Container Apps + Log Analytics | <$0.25 / hour |
| Key Vault (Standard) | negligible |
| **Total for a 1-2 hour run** | **~$1-2** |

Delete the resource group immediately after capturing evidence; the firewall dominates the cost.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/aca-secret-kv-ref-mi-network-path.md`
- Playbook: `docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md` (H4 hypothesis)
- Platform: `docs/platform/networking/egress-control.md`
- Related playbook: `docs/troubleshooting/playbooks/identity-and-configuration/managed-identity-auth-failure.md`
