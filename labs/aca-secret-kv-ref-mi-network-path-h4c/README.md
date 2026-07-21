# Lab: ACA Secret Key Vault Reference — Managed Identity Network Path (H4c NSG Deny)

Reproduce the failure surface documented in
[Container Apps: Secret and Key Vault Reference Failure](../../docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)
for Hypothesis **H4 — MI OIDC discovery blocked before the Entra authority is reached**.

This H4c variant is the **NSG-deny inversion** of H4a. In H4a, H1 and H2 flip connectivity by removing and restoring the Entra firewall rule. In H4c there is **no Azure Firewall and no UDR at all**. What changes between H0/H1/H2 is only whether the ACA workload subnet NSG contains a custom outbound rule that denies 443/TCP to the `AzureActiveDirectory` service tag:

- **H0** — NSG attached, but no custom AAD deny/allow rule → secret set succeeds.
- **H1** — NSG outbound Deny rule `deny-aad-443-h4c` (priority `200`) blocks `AzureActiveDirectory:443` → secret set fails.
- **H2** — Higher-priority NSG outbound Allow rule `allow-aad-443-h4c` (priority `100`) is added while the Deny remains → a **new** secret-set attempt succeeds again.

The lesson is narrow: when the ACA workload subnet NSG denies outbound `AzureActiveDirectory:443`, managed-identity OIDC discovery fails with no firewall anywhere in the path. This lab does not assert NSG-versus-firewall evaluation ordering. Adding the documented explicit Allow restores success with the same Key Vault, identity, and RBAC state.

## Architecture

```text
Container App (system-assigned MI)
  in subnet snet-aca (10.90.0.0/23)
       │  az containerapp secret set --identity system --key-vault-url ...
       │  → control-plane worker resolves the KV URL, then must reach the
       │    Entra authority before fetching OIDC discovery metadata
       ▼
Subnet NSG nsg-<baseName>-<suffix>
       │
       │  H4c phase behavior:
       │    - H0: NSG attached; only Azure default rules -> outbound allowed
       │    - H1: deny-aad-443-h4c priority 200 -> AzureActiveDirectory:443 denied
       │    - H2: allow-aad-443-h4c priority 100 + deny 200 retained -> allow wins
       ▼
Entra ID authority
       │  H0/H2 -> OIDC discovery succeeds
       │  H1    -> NSG deny blocks outbound 443 (no firewall in this topology)
       ▼
Key Vault (public endpoint, RBAC-granted "Key Vault Secrets User" to the MI)
```

## Structure

```text
labs/aca-secret-kv-ref-mi-network-path-h4c/
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
export RG="rg-aca-secret-kv-ref-mi-network-path-h4c"
export LOCATION="koreacentral"
export BASE_NAME="acasech4c01"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" \
    --name aca-secret-kv-ref-mi-network-path-h4c \
    --template-file labs/aca-secret-kv-ref-mi-network-path-h4c/infra/main.bicep \
    --parameters baseName="$BASE_NAME" deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"

bash labs/aca-secret-kv-ref-mi-network-path-h4c/trigger.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4c/falsify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4c/verify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4c/cleanup.sh
```

| Command/Parameter | Purpose |
| --- | --- |
| `az group create` | Create the resource group for the lab run. |
| `--name` | Set the resource group name. |
| `--location` | Set the Azure region for the resource group. |
| `az deployment group create` | Deploy the H4c lab infrastructure into the resource group. |
| `--resource-group` | Target the resource group created for the lab. |
| `--name` | Give the deployment a stable H4c deployment name. |
| `--template-file` | Point Azure CLI at the H4c Bicep template. |
| `--parameters` | Pass required Bicep parameters, including the required deployment principal object ID. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the base naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter expected by `main.bicep`. |

## What "Success" Looks Like

The lab is reproduced when all of the following hold:

1. **H0 baseline**: With the NSG attached but no custom `AzureActiveDirectory:443` deny/allow rule, `az containerapp secret set --identity system --key-vault-url ...` succeeds. The secret `kvref-h0` appears in `configuration.secrets`, and `latestReadyRevisionName` does not change.
2. **H1 NSG-deny trigger**: After creating outbound rule `deny-aad-443-h4c` at priority `200`, the same command fails with the managed-identity OIDC discovery EOF surface. The exit code is non-zero. `kvref-h1` is absent from `configuration.secrets`. The revision name is unchanged. Ingress still returns HTTP 200. NSG rule enumeration shows the Deny exists and no higher-priority matching Allow exists.
3. **H2 falsification**: After creating outbound rule `allow-aad-443-h4c` at priority `100` while keeping the Deny, a **new** secret-set attempt succeeds. `kvref-h2` is present in `configuration.secrets`. The revision name is still unchanged from baseline. Ingress still returns HTTP 200. NSG rule enumeration shows the Allow now governs because `100 < 200`.

## Phase B Evidence Pack (reader-generated)

The 17-gate Phase B workflow is reader-generated. Running `trigger.sh` and `falsify.sh` writes the raw cohort files (`01`-`13`) into your local [`evidence/`](evidence/README.md) directory; then `verify.sh` reads only those local files and deterministically emits the four derived gate JSONs (`14`-`17`). `verify.sh` makes no live Azure calls.

- **Gate 14** proves cohort integrity: canonical files present, parseable, bounded in one UTC lineage, anchor-consistent, bound to the same `latestReadyRevisionName` across 02/05/08/12, explicitly **not H4a** (NSG attached, no Azure Firewall, no route table, Azure-provided DNS), and free of storage-account / flow-log artifacts.
- **Gate 15** proves H1: the NSG deny rule exists for `AzureActiveDirectory:443`, `az containerapp secret set` exits non-zero with the managed-identity + OIDC discovery signature, `kvref-h1` is absent, ingress stays HTTP 200, and no higher-priority matching Allow existed.
- **Gate 16** proves H2: the higher-priority NSG Allow exists for `AzureActiveDirectory:443`, a **new** H2 secret-set attempt succeeds, `kvref-h2` is present, ingress stays HTTP 200, and the Allow priority is numerically lower than the Deny priority.
- **Gate 17** performs the bounded H1↔H2 diff and states the narrow claim ceiling explicitly: H1→H2 adds only the documented higher-priority Allow rule; DNS, route table, firewall presence, Key Vault, identity, RBAC, app, revision, and ingress stay constant.

Once you have generated the local cohort, you can re-run `verify.sh` offline as often as needed, even after `cleanup.sh` has deleted the resource group, provided the local files 01-13 remain in place:

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4c/
bash verify.sh
```

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| Container Apps + Log Analytics | <$0.25 / hour |
| Key Vault (Standard) | negligible |
| Network Security Group | free |
| **Total for a 1-2 hour run** | **well under $1** |

Delete the resource group immediately after capturing evidence.

## Claim ceiling

This reproducer is intentionally **not-H4a** and intentionally narrow. A passing evidence pack proves only the H4c NSG-deny inversion described above. It does **not** prove NSG-before-Azure-Firewall ordering, NSG flow-log behavior, universal ACA control-plane egress-path uniformity, exact Entra IP resolution at failure time, or Key Vault firewall/RBAC failure.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/aca-secret-kv-ref-mi-network-path-h4c.md`
- Playbook: `docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md` (H4 hypothesis)
- Platform: `docs/platform/networking/egress-control.md`
- Related playbook: `docs/troubleshooting/playbooks/identity-and-configuration/managed-identity-auth-failure.md`
