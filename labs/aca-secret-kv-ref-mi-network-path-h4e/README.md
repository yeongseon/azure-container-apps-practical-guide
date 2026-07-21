# Lab: ACA Secret Key Vault Reference — Managed Identity Network Path (H4e Custom DNS Override)

Reproduce the failure surface documented in
[Container Apps: Secret and Key Vault Reference Failure](../../docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)
for Hypothesis **H4 — MI OIDC discovery blocked before the Entra authority is reached**.

This H4e variant is the **DNS-override inversion** of H4a. In H4a, H1 and H2 flip connectivity by removing and restoring the Entra firewall rule. In H4e there is **no Azure Firewall and no UDR at all**. What changes between H0/H1/H2 is only whether the ACA VNet has a custom linked Private DNS override for the Entra authority hosts:

- **H0** — No custom Private DNS override → secret set succeeds.
- **H1** — Two custom Private DNS zones (`login.microsoftonline.com`, `login.microsoft.com`) linked to the ACA VNet, each apex A record → `192.0.2.1` → secret set fails.
- **H2** — Override removed and the post-removal wait exceeds TTL → a **new** secret-set attempt succeeds again.

The lesson is narrow: when the Entra authority FQDN resolves to a sink address through a custom DNS override, managed-identity OIDC discovery fails **before** any packet could have reached a firewall. Removing the override restores success with the same Key Vault, identity, and RBAC state.

## Architecture

```text
Container App (system-assigned MI)
  in subnet snet-aca (10.90.0.0/23)
       │  az containerapp secret set --identity system --key-vault-url ...
       │  → control-plane worker resolves the KV URL, then must resolve the
       │    Entra authority before fetching OIDC discovery metadata
       ▼
Azure-provided DNS for VNet vnet-<baseName>-<suffix>
       │
       │  H4e phase behavior:
       │    - H0: no custom Private DNS override linked to the VNet
       │    - H1: custom zones login.microsoftonline.com + login.microsoft.com
       │          linked to the VNet, apex A records -> 192.0.2.1
       │    - H2: both overrides removed; wait > TTL to clear caches
       ▼
Entra ID authority resolution
       │  H0/H2 -> public Microsoft IPs -> OIDC discovery succeeds
       │  H1    -> 192.0.2.1 sink -> OIDC discovery fails before Key Vault read
       ▼
Key Vault (public endpoint, RBAC-granted "Key Vault Secrets User" to the MI)
```

## Structure

```text
labs/aca-secret-kv-ref-mi-network-path-h4e/
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
export RG="rg-aca-secret-kv-ref-mi-network-path-h4e"
export LOCATION="koreacentral"
export BASE_NAME="acasech4e01"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" \
    --name aca-secret-kv-ref-mi-network-path-h4e \
    --template-file labs/aca-secret-kv-ref-mi-network-path-h4e/infra/main.bicep \
    --parameters baseName="$BASE_NAME" deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"

bash labs/aca-secret-kv-ref-mi-network-path-h4e/trigger.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4e/falsify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4e/verify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4e/cleanup.sh
```

| Command/Parameter | Purpose |
| --- | --- |
| `az group create` | Create the resource group for the lab run. |
| `--name` | Set the resource group name. |
| `--location` | Set the Azure region for the resource group. |
| `az deployment group create` | Deploy the H4e lab infrastructure into the resource group. |
| `--resource-group` | Target the resource group created for the lab. |
| `--name` | Give the deployment a stable H4e deployment name. |
| `--template-file` | Point Azure CLI at the H4e Bicep template. |
| `--parameters` | Pass required Bicep parameters, including the required deployment principal object ID. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the base naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter expected by `main.bicep`. |

## What "Success" Looks Like

The lab is reproduced when all of the following hold:

1. **H0 baseline**: With no custom DNS override, `az containerapp secret set --identity system --key-vault-url ...` succeeds. The secret `kvref-h0` appears in `configuration.secrets`, and `latestReadyRevisionName` does not change.
2. **H1 DNS-override trigger**: After creating the two custom Private DNS zones and linking them to the ACA VNet, the same command fails with the managed-identity OIDC discovery EOF surface. The exit code is non-zero. `kvref-h1` is absent from `configuration.secrets`. The revision name is unchanged. Ingress still returns HTTP 200. Replica `nslookup login.microsoftonline.com` returns `192.0.2.1`.
3. **H2 falsification**: After removing the override and waiting beyond TTL, a **new** secret-set attempt succeeds. `kvref-h2` is present in `configuration.secrets`. The revision name is still unchanged from baseline. Ingress still returns HTTP 200. Replica `nslookup login.microsoftonline.com` no longer returns `192.0.2.1`.

## Phase B Evidence Pack (reader-generated)

The 17-gate Phase B workflow is reader-generated. Running `trigger.sh` and `falsify.sh` writes the raw cohort files (`01`-`13`) into your local [`evidence/`](evidence/README.md) directory; then `verify.sh` reads only those local files and deterministically emits the four derived gate JSONs (`14`-`17`). `verify.sh` makes no live Azure calls.

- **Gate 14** proves cohort integrity: canonical files present, parseable, bounded in one UTC lineage, anchor-consistent, bound to the same `latestReadyRevisionName` across 02/05/08/12, and explicitly **not H4a** (no Azure Firewall, no route table, Azure-provided DNS at baseline).
- **Gate 15** proves H1: the custom Private DNS override exists for both Entra authority zones, `az containerapp secret set` exits non-zero, `kvref-h1` is absent, ingress stays HTTP 200, and the replica DNS view resolves `login.microsoftonline.com` to `192.0.2.1`.
- **Gate 16** proves H2: the custom Private DNS override is removed, the post-removal wait exceeds TTL, a **new** H2 secret-set attempt succeeds, `kvref-h2` is present, ingress stays HTTP 200, and the replica DNS view no longer resolves `login.microsoftonline.com` to `192.0.2.1`.
- **Gate 17** performs the bounded H1↔H2 diff and states the narrow claim ceiling explicitly: H1→H2 flips the custom DNS override only; Key Vault, identity, RBAC, and topology stay constant.

Once you have generated the local cohort, you can re-run `verify.sh` offline as often as needed, even after `cleanup.sh` has deleted the resource group, provided the local files 01-13 remain in place:

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4e/
bash verify.sh
```

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| Container Apps + Log Analytics | <$0.25 / hour |
| Key Vault (Standard) | negligible |
| Private DNS zones (2) | negligible for a short run |
| **Total for a 1-2 hour run** | **well under $1** |

Delete the resource group immediately after capturing evidence.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/aca-secret-kv-ref-mi-network-path-h4e.md`
- Playbook: `docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md` (H4 hypothesis)
- Platform: `docs/platform/networking/egress-control.md`
- Related playbook: `docs/troubleshooting/playbooks/identity-and-configuration/managed-identity-auth-failure.md`
