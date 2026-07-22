# Lab: ACA Secret Key Vault Reference — Managed Identity Network Path (H4g Azure Firewall Premium TLS Inspection)

Reproduce the failure surface documented in
[Container Apps: Secret and Key Vault Reference Failure](../../docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)
for Hypothesis **H4 — MI OIDC discovery blocked before the Entra authority is reached**.

This H4g variant is the **Azure Firewall Premium TLS-inspection inversion** of H4c. The topology adds an Azure Firewall Premium, a Premium Firewall Policy with TLS inspection configured through an intermediate CA certificate, and a route table that sends `0.0.0.0/0` from the ACA workload subnet to the firewall private IP. The secret-set operation in this lab uses the scripted Key Vault reference form `--secrets <name>=keyvaultref:<url>,identityref:system`, which is the equivalent CLI surface for a system-assigned-identity Key Vault reference. What changes between H0/H1/H2 is only whether the Entra-authority application rule terminates TLS:

- **H0** — Entra-authority rule exists with `terminateTLS=false` → secret set succeeds.
- **H1** — the same rule flips to `terminateTLS=true` for `login.microsoftonline.com` and `login.microsoft.com` → secret set fails.
- **H2** — the same rule flips back to `terminateTLS=false` (the TLS-inspection exemption) → a **new** secret-set attempt succeeds again.

The lesson is narrow: in this reproducer, **TLS inspection of the Entra authority FQDNs is the controlled variable**. The lab does **not** claim direct control-plane TLS-chain capture, identical workload/control-plane egress, proof beyond the two exercised Entra FQDNs, any NVA/third-party proxy behavior, or Key Vault data-plane failure.

## Architecture

```text
Container App (system-assigned MI)
  in subnet snet-aca (10.90.0.0/23)
       │  az containerapp secret set --secrets <name>=keyvaultref:<url>,identityref:system
       ▼
UDR 0.0.0.0/0 -> Azure Firewall private IP
       ▼
Azure Firewall Premium + Firewall Policy Premium
       │  TLS inspection configured with lab intermediate CA
       │
       │  Entra-authority application rule:
       │    - H0/H2: terminateTLS=false
       │    - H1:    terminateTLS=true
       ▼
Entra authority
  login.microsoftonline.com
  login.microsoft.com
       │
       │  H1 workload proof: openssl s_client sees the lab interception CA
       │  H2 workload proof: that interception CA disappears again
       ▼
Key Vault (public endpoint, RBAC-granted "Key Vault Secrets User" to the MI)
```

## Structure

```text
labs/aca-secret-kv-ref-mi-network-path-h4g/
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
export RG="rg-aca-secret-kv-ref-mi-network-path-h4g"
export LOCATION="koreacentral"
export BASE_NAME="acasech4g01"
export TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID="https://<ca-vault>.vault.azure.net/secrets/<ca-secret>/<version>"
export TLS_INSPECTION_CA_CERTIFICATE_NAME="lab-h4g-intermediate-ca"
export TLS_INSPECTION_IDENTITY_RESOURCE_ID="/subscriptions/<subscription-id>/resourceGroups/<identity-rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<identity-name>"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" \
    --name aca-secret-kv-ref-mi-network-path-h4g \
    --template-file labs/aca-secret-kv-ref-mi-network-path-h4g/infra/main.bicep \
    --parameters baseName="$BASE_NAME" \
    --parameters deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)" \
    --parameters tlsInspectionCaKeyVaultSecretId="$TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID" \
    --parameters tlsInspectionCaCertificateName="$TLS_INSPECTION_CA_CERTIFICATE_NAME" \
    --parameters tlsInspectionIdentityResourceId="$TLS_INSPECTION_IDENTITY_RESOURCE_ID"

bash labs/aca-secret-kv-ref-mi-network-path-h4g/trigger.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4g/falsify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4g/verify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4g/cleanup.sh
```

| Command/Parameter | Purpose |
| --- | --- |
| `az group create` | Create the resource group for the lab run. |
| `--name` | Set the resource group name. |
| `--location` | Set the Azure region for the resource group. |
| `az deployment group create` | Deploy the H4g lab infrastructure into the resource group. |
| `--resource-group` | Target the resource group created for the lab. |
| `--name` | Give the deployment a stable H4g deployment name. |
| `--template-file` | Point Azure CLI at the H4g Bicep template. |
| `--parameters` | Pass required Bicep parameters, including the deployment principal object ID and the TLS-inspection CA reference. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the base naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter expected by `main.bicep`. |
| `tlsInspectionCaKeyVaultSecretId="$TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID"` | Supply the Key Vault secret ID for the intermediate CA PFX used by Firewall Premium TLS inspection. |
| `tlsInspectionCaCertificateName="$TLS_INSPECTION_CA_CERTIFICATE_NAME"` | Supply the Firewall Policy display name for that CA reference. |
| `tlsInspectionIdentityResourceId="$TLS_INSPECTION_IDENTITY_RESOURCE_ID"` | Supply the resource ID of the pre-created user-assigned identity that already has Get/List access to the CA vault. |

Before you run the deployment above, complete these reader-owned prerequisites:

1. Create a **user-assigned managed identity** in your subscription.
2. Grant that identity **Get** and **List** permission on the Key Vault that stores the intermediate CA certificate secret used for TLS inspection.
3. Export that identity's resource ID as `TLS_INSPECTION_IDENTITY_RESOURCE_ID` and pass it into `main.bicep`.

Without those three pre-steps, a clean one-pass deployment cannot attach the TLS-inspection CA to the Firewall Policy because Azure Firewall Premium must already be able to read the CA secret through that user-assigned identity.

## What "Success" Looks Like

The lab is reproduced when all of the following hold:

1. **H0 baseline**: with the Entra-authority rule present and `terminateTLS=false`, `az containerapp secret set --secrets kvref-h0=keyvaultref:<url>,identityref:system` succeeds. The secret `kvref-h0` appears in `configuration.secrets`, and `latestReadyRevisionName` does not change.
2. **H1 TLS-inspection trigger**: after redeploying the firewall policy so the same Entra-authority rule has `terminateTLS=true`, the same command fails with a managed-identity / OIDC clue plus a TLS / certificate clue. The exit code is non-zero. `kvref-h1` is absent from `configuration.secrets`. The revision name is unchanged. Ingress still returns HTTP 200. The workload-replica `openssl s_client` capture shows the lab interception CA chain.
3. **H2 falsification**: after redeploying the firewall policy so the same Entra-authority rule returns to `terminateTLS=false`, a **new** secret-set attempt succeeds. `kvref-h2` is present in `configuration.secrets`. The revision name is still unchanged from baseline. Ingress still returns HTTP 200. The workload-replica `openssl s_client` capture no longer shows the lab interception CA chain.

## Phase B Evidence Pack (reader-generated)

The 17-gate Phase B workflow is reader-generated. Running `trigger.sh` and `falsify.sh` writes the raw cohort files (`01`-`13`) into your local [`evidence/`](evidence/README.md) directory; then `verify.sh` reads only those local files and deterministically emits the four derived gate JSONs (`14`-`17`). `verify.sh` makes no live Azure calls.

- **Gate 14** proves cohort integrity: canonical files present, parseable, bounded in one UTC lineage, anchor-consistent, bound to the same `latestReadyRevisionName` across `02/05/08/12`, and explicitly anchored to the H4g topology: Azure Firewall Premium present, Premium Firewall Policy present, TLS inspection configured, route table attached, no NSG deny trigger, no custom DNS override, and no Virtual WAN routing intent.
- **Gate 15** proves H1: the Entra-authority rule exists with `terminateTLS=true`, the secret-set command exits non-zero with the classifier signature, `kvref-h1` is absent, ingress stays HTTP 200, and the workload `openssl` capture shows the unexpected lab CA.
- **Gate 16** proves H2: the Entra-authority rule exists with `terminateTLS=false`, a **new** H2 secret-set attempt succeeds, `kvref-h2` is present, ingress stays HTTP 200, and the workload `openssl` capture no longer shows the lab CA.
- **Gate 17** performs the bounded H1↔H2 diff and states the narrow claim ceiling explicitly: only the Entra-authority TLS-inspection flag changed; DNS, NSG, route table presence, firewall presence, Key Vault, identity, RBAC, app, revision, and ingress stayed constant.

Once you have generated the local cohort, you can re-run `verify.sh` offline as often as needed, even after `cleanup.sh` has deleted the resource group, provided the local files `01-13` remain in place:

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4g/
bash verify.sh
```

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| Azure Firewall Premium + public IP | dominant cost for the run |
| Firewall Policy Premium + TLS inspection | included in the dominant Firewall Premium spend |
| Container Apps + Log Analytics | <$0.25 / hour |
| Key Vault (Standard) | negligible |
| **Total for a short 1-2 hour run** | **several US dollars** |

This lab uses **Azure Firewall Premium**, which is billed at a significantly higher rate than the other H4 variants and is expected to cost **several US dollars even for a short 1-2 hour run**. Delete the resource group immediately after capturing evidence.

## Claim ceiling

- [Observed] A workload replica's data-plane `openssl s_client` to `login.microsoftonline.com:443` can show the lab interception CA chain during H1 and its absence during H2.
- [Strongly Suggested] The ACA-managed control-plane secret resolver is affected by the same Entra-authority TLS-inspection change because H0 succeeds, H1 fails, and H2 succeeds while the rest of the cohort stays constant.
- [Not Proven] No control-plane packet capture exists.
- [Not Proven] No direct control-plane TLS-chain observation exists.
- [Not Proven] The lab does not prove workload and control-plane egress are identical.
- [Not Proven] The lab proves behavior only for `login.microsoftonline.com` and `login.microsoft.com`.
- [Not Proven] The lab does not claim anything about non-Azure NVAs or third-party proxies.
- [Not Proven] The lab does not claim Key Vault data-plane failure.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/aca-secret-kv-ref-mi-network-path-h4g.md`
- Playbook: `docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md` (H4 hypothesis)
- Platform: `docs/platform/networking/egress-control.md`
- Related playbook: `docs/troubleshooting/playbooks/identity-and-configuration/managed-identity-auth-failure.md`
