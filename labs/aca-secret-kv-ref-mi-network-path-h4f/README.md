# Lab: ACA Secret Key Vault Reference — Managed Identity Network Path (H4f Linux NVA Surrogate)

Reproduce the failure surface documented in
[Container Apps: Secret and Key Vault Reference Failure](../../docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)
for Hypothesis **H4 — MI OIDC discovery blocked before the Entra authority is reached**.

This H4f variant is the **3rd-party NVA-surrogate inversion** of H4c. There is **no Azure Firewall** and **no TLS inspection** anywhere in this topology. Instead, the ACA workload subnet uses a route table that sends `0.0.0.0/0` to a **small Linux forwarding VM** whose NIC has Azure IP forwarding enabled and whose guest OS enables IP forwarding plus nftables NAT/masquerade. The secret-set operation in this lab uses the scripted Key Vault reference form `--secrets <name>=keyvaultref:<url>,identityref:system`, which is the equivalent CLI surface for a system-assigned-identity Key Vault reference. What changes between H0/H1/H2 is only whether that Linux VM has the single forwarding-plane DROP rule for outbound tcp/443 to AzureActiveDirectory service-tag destinations:

- **H0** — route table already points `0.0.0.0/0` to the Linux NVA surrogate and forwarding/NAT are enabled, but no Entra drop rule exists → secret set succeeds.
- **H1** — the Linux NVA surrogate installs one nftables forwarding-plane DROP rule for outbound tcp/443 to `AzureActiveDirectory` service-tag IPv4 prefixes → secret set fails.
- **H2** — that same DROP rule is removed from the same Linux NVA surrogate → a **new** secret-set attempt succeeds again.

The lesson is narrow: in this reproducer, **the NVA-surrogate forwarding-plane DROP rule is the controlled variable**. The lab does **not** claim direct control-plane packet capture, identical workload/control-plane egress, proof beyond the two exercised Entra authority hosts, vendor-specific NVA behavior, or any Azure Firewall bypass claim.

## Architecture

```text
Container App (system-assigned MI)
  in subnet snet-aca (10.90.0.0/23)
       │  az containerapp secret set --secrets <name>=keyvaultref:<url>,identityref:system
       ▼
UDR 0.0.0.0/0 -> Linux NVA surrogate private IP
       ▼
Linux forwarding VM
       │  Azure NIC enableIPForwarding=true
       │  OS net.ipv4.ip_forward=1, rp_filter disabled
       │  nftables NAT/masquerade baseline
       │
       │  H0/H2: no Entra DROP rule
       │  H1:    DROP forwarded tcp/443 to AzureActiveDirectory service-tag prefixes
       ▼
Entra authority
  login.microsoftonline.com
  login.microsoft.com
       │
       │  H1 workload proof: curl -4 / openssl from the replica fail to both hosts
       │  H2 workload proof: the same probes succeed again
       ▼
Key Vault (public endpoint, RBAC-granted "Key Vault Secrets User" to the MI)
```

## Structure

```text
labs/aca-secret-kv-ref-mi-network-path-h4f/
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
export RG="rg-aca-secret-kv-ref-mi-network-path-h4f"
export LOCATION="koreacentral"
export BASE_NAME="acasech4f01"
export NVA_VM_ADMIN_PASSWORD="$(openssl rand -base64 24)Aa1!"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" \
    --name aca-secret-kv-ref-mi-network-path-h4f \
    --template-file labs/aca-secret-kv-ref-mi-network-path-h4f/infra/main.bicep \
    --parameters baseName="$BASE_NAME" \
    --parameters deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)" \
    --parameters nvaVmAdminPassword="$NVA_VM_ADMIN_PASSWORD"

bash labs/aca-secret-kv-ref-mi-network-path-h4f/trigger.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4f/falsify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4f/verify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4f/cleanup.sh
```

| Command/Parameter | Purpose |
| --- | --- |
| `az group create` | Create the resource group for the lab run. |
| `--name` | Set the resource group name. |
| `--location` | Set the Azure region for the resource group. |
| `az deployment group create` | Deploy the H4f lab infrastructure into the resource group. |
| `--resource-group` | Target the resource group created for the lab. |
| `--name` | Give the deployment a stable H4f deployment name. |
| `--template-file` | Point Azure CLI at the H4f Bicep template. |
| `--parameters` | Pass required Bicep parameters, including the deployment principal object ID and the VM admin password required by Azure VM provisioning. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the base naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter expected by `main.bicep`. |
| `nvaVmAdminPassword="$NVA_VM_ADMIN_PASSWORD"` | Supply the one deployment-time VM credential required by Azure even though the lab uses `az vm run-command invoke` instead of SSH. |

## What "Success" Looks Like

The lab is reproduced when all of the following hold:

1. **H0 baseline**: with the route table already sending `0.0.0.0/0` to the Linux NVA surrogate private IP, and with forwarding plus NAT enabled but no Entra drop rule, `az containerapp secret set --secrets kvref-h0=keyvaultref:<url>,identityref:system` succeeds. The secret `kvref-h0` appears in `configuration.secrets`, and `latestReadyRevisionName` does not change.
2. **H1 NVA-surrogate trigger**: after installing the single nftables forwarding-plane DROP rule for `AzureActiveDirectory` service-tag destinations on tcp/443, the same command fails with a managed-identity / OIDC clue plus a connectivity / timeout clue. The exit code is non-zero. `kvref-h1` is absent from `configuration.secrets`. The revision name is unchanged. Ingress still returns HTTP 200. Workload probes to both `login.microsoftonline.com` and `login.microsoft.com` fail while the DROP rule is installed.
3. **H2 falsification**: after removing that same DROP rule from the same Linux NVA surrogate, a **new** secret-set attempt succeeds. `kvref-h2` is present in `configuration.secrets`. The revision name is still unchanged from baseline. Ingress still returns HTTP 200. Workload probes to both Entra hosts succeed again, and the DROP rule is absent.

## Phase B Evidence Pack (reader-generated)

The 17-gate Phase B workflow is reader-generated. Running `trigger.sh` and `falsify.sh` writes the raw cohort files (`01`-`13`) into your local [`evidence/`](evidence/README.md) directory; then `verify.sh` reads only those local files and deterministically emits the four derived gate JSONs (`14`-`17`). `verify.sh` makes no live Azure calls.

- **Gate 14** proves cohort integrity: canonical files present, parseable, bounded in one UTC lineage, anchor-consistent, bound to the same `latestReadyRevisionName` across `02/05/08/12`, and explicitly anchored to the H4f topology: Linux NVA surrogate present, NIC IP forwarding enabled, OS IP forwarding enabled, NAT enabled, route table attached, no Azure Firewall, no Firewall Policy, no TLS inspection, no NSG deny trigger, no custom DNS override, and no Virtual WAN routing intent.
- **Gate 15** proves H1: the DROP rule exists for `AzureActiveDirectory` service-tag destinations on tcp/443, the secret-set command exits non-zero with the classifier signature, `kvref-h1` is absent, ingress stays HTTP 200, and workload probes to both Entra hosts fail.
- **Gate 16** proves H2: the DROP rule is absent, a **new** H2 secret-set attempt succeeds, `kvref-h2` is present, ingress stays HTTP 200, and workload probes to both Entra hosts succeed.
- **Gate 17** performs the bounded H1↔H2 diff and states the narrow claim ceiling explicitly: only the Linux NVA surrogate DROP rule changed; route table, forwarding, NAT, DNS, NSG, Key Vault, identity, RBAC, app, revision, and ingress stayed constant.

Once you have generated the local cohort, you can re-run `verify.sh` offline as often as needed, even after `cleanup.sh` has deleted the resource group, provided the local files `01-13` remain in place:

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4f/
bash verify.sh
```

## Estimated Cost

| Resource | Approx. cost |
|---|---|
| Small Linux VM (dominant cost) | cents per hour depending on SKU and region |
| VM public IP + managed disk | small incremental cost |
| Container Apps + Log Analytics | low for a short run |
| Key Vault (Standard) | negligible |
| **Total for a short 1-2 hour run** | **low-dollar or sub-dollar in many regions** |

This lab is **much cheaper than H4g** because it uses a small Linux VM instead of Azure Firewall Premium. For a short 1-2 hour run, expect a low-dollar or sub-dollar lab in many regions. Delete the resource group immediately after capturing evidence.

## Claim ceiling

- [Observed] The ACA subnet route table sends 0.0.0.0/0 to the Linux NVA surrogate private IP.
- [Observed] The NVA surrogate has Azure NIC IP forwarding, OS IP forwarding, and NAT enabled.
- [Observed] H1 installs a forwarding-plane DROP rule (with an attached nft `counter`) for tcp/443 to Entra/AzureActiveDirectory destinations.
- [Observed] Workload replica probes to login.microsoftonline.com and login.microsoft.com fail in H1 and succeed again in H2.
- [Observed] az containerapp secret set succeeds in H0, fails in H1, and succeeds again in H2 while revision and ingress stay stable.
- [Strongly Suggested] The ACA-managed secret resolver is affected by the same NVA-surrogate Entra block because the only intended H1<->H2 change is removal of that NVA rule.
- [Not Proven] This does not prove Palo Alto, Check Point, Fortinet, or any vendor-specific policy/logging behavior.
- [Not Proven] This does not provide direct ACA control-plane packet capture.
- [Not Proven] This does not prove workload and ACA control-plane egress are identical.
- [Not Proven] This does not prove an Azure Firewall was bypassed, because the cheap H4f topology intentionally has no Azure Firewall.
- [Not Proven] The DROP rule's nft `counter` is recorded as raw evidence but is **not** asserted to be non-zero and is **not** a gate signal, because a non-zero forward-chain counter would require the control-plane resolver's traffic to traverse this chain — which this lab does not prove.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/aca-secret-kv-ref-mi-network-path-h4f.md`
- Playbook: `docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md` (H4 hypothesis)
- Platform: `docs/platform/networking/egress-control.md`
- Related playbook: `docs/troubleshooting/playbooks/identity-and-configuration/managed-identity-auth-failure.md`
