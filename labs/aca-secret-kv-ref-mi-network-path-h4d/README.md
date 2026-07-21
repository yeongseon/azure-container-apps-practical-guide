# Lab: ACA Secret Key Vault Reference — Managed Identity Network Path (H4d Virtual WAN + Routing Intent)

> **Cost warning**
> Virtual WAN secured-hub deployments are expensive. Prefer **existing secured-hub mode** whenever possible. Use **full synthetic mode** only with explicit opt-in (`DEPLOY_VIRTUAL_WAN=true`) and delete the resource group immediately after capturing evidence.
>
> **Shared-hub warning**
> Existing secured-hub mode enables Routing Intent on the hub you point it at, which applies to **every** connection on that hub, not just this lab's ACA VNet. Run existing secured-hub mode **only against a dedicated non-production secured hub** — never against a production or shared hub.

Reproduce the failure surface documented in
[Container Apps: Secret and Key Vault Reference Failure](../../docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)
for Hypothesis **H4 — MI OIDC discovery blocked before the Entra authority is reached**.

This H4d variant is the **Virtual WAN + Routing Intent inversion**. The firewall policy stays intentionally restrictive throughout: it allows `*.vault.azure.net` but does **not** allow `login.microsoftonline.com` or `login.microsoft.com`. What flips between H0/H1/H2 is **Routing Intent state**, not the firewall policy:

- **H0** — No active Routing Intent path through the secured hub firewall → secret set succeeds.
- **H1** — Connect the ACTUAL ACA infrastructure VNet to the Virtual Hub and enable Routing Intent (`InternetTraffic + PrivateTraffic -> hub AzFW`) → secret set fails with the managed-identity OIDC discovery surface.
- **H2** — Remove Routing Intent while leaving the firewall policy unchanged → a **new** secret-set attempt succeeds again.

The lesson is narrow: in this reproducer, **Routing Intent is the controlled route-state variable**. The lab does **not** prove packet capture, dataplane bypass, or that Azure Firewall never saw the packet.

## Architecture

```text
Container App (system-assigned MI)
  in subnet snet-aca (10.90.0.0/23)
       │  az containerapp secret set --identity system --key-vault-url ...
       ▼
ACA infrastructure VNet
       │
       │  H0: not connected to a Routing-Intent path through the secured hub
       │  H1: HubVirtualNetworkConnection + Routing Intent ON
       │  H2: same connection, Routing Intent OFF
       ▼
Virtual WAN Hub
       │  Routing Intent policies:
       │    - InternetTraffic -> Azure Firewall
       │    - PrivateTraffic  -> Azure Firewall
       ▼
Secured-hub Azure Firewall
       │  Firewall policy intentionally ALLOWS only Key Vault public FQDNs
       │  (*.vault.azure.net) and does NOT allow Entra authority FQDNs
       ▼
Entra authority OIDC discovery
       │  H1: blocked when Routing Intent forces the path through AzFW
       │  H0/H2: succeeds when that route-state is absent
       ▼
Key Vault (public endpoint, RBAC-granted "Key Vault Secrets User" to the MI)
```

## Structure

```text
labs/aca-secret-kv-ref-mi-network-path-h4d/
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

### Mode A — existing secured-hub mode (preferred)

Set the external hub IDs first, then run the scripts:

```bash
export RG="rg-aca-secret-kv-ref-mi-network-path-h4d"
export LOCATION="koreacentral"
export BASE_NAME="acasech4d01"

export EXISTING_VIRTUAL_HUB_RESOURCE_ID="/subscriptions/<subscription-id>/resourceGroups/<vwan-rg>/providers/Microsoft.Network/virtualHubs/<vhub-name>"
export EXISTING_AZURE_FIREWALL_RESOURCE_ID="/subscriptions/<subscription-id>/resourceGroups/<vwan-rg>/providers/Microsoft.Network/azureFirewalls/<azfw-name>"
export EXISTING_FIREWALL_POLICY_RESOURCE_ID="/subscriptions/<subscription-id>/resourceGroups/<vwan-rg>/providers/Microsoft.Network/firewallPolicies/<policy-name>"
export EXISTING_FIREWALL_LOG_ANALYTICS_CUSTOMER_ID="00000000-0000-0000-0000-000000000000"

bash labs/aca-secret-kv-ref-mi-network-path-h4d/trigger.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4d/falsify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4d/verify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4d/cleanup.sh
```

### Mode B — full synthetic mode (explicit opt-in)

```bash
export RG="rg-aca-secret-kv-ref-mi-network-path-h4d"
export LOCATION="koreacentral"
export BASE_NAME="acasech4d01"
export DEPLOY_VIRTUAL_WAN="true"

bash labs/aca-secret-kv-ref-mi-network-path-h4d/trigger.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4d/falsify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4d/verify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4d/cleanup.sh
```

## What "Success" Looks Like

The lab is reproduced when all of the following hold:

1. **H0 baseline**: with no active Routing Intent path through the secured hub firewall, `az containerapp secret set --identity system --key-vault-url ...` succeeds. The secret `kvref-h0` appears in `configuration.secrets`, and `latestReadyRevisionName` does not change.
2. **H1 Routing Intent trigger**: after connecting the ACA infrastructure VNet to the Virtual Hub and enabling Routing Intent toward the hub Azure Firewall, `az network vhub routing-intent show` confirms the policy, `az network vhub get-effective-routes --resource-type HubVirtualNetworkConnection --resource-id $ACA_VNET_CONNECTION_ID ...` shows `0.0.0.0/0` targeting the hub firewall, and the same secret-set command fails with `Unable to get value using Managed identity` plus `openid-configuration`. `kvref-h1` is absent. The revision name is unchanged. Ingress still returns HTTP 200.
3. **H2 falsification**: after removing Routing Intent while leaving the firewall policy unchanged, the effective-route table no longer shows `0.0.0.0/0` targeting the hub firewall, a **new** secret-set attempt succeeds, `kvref-h2` is present, the revision name is still unchanged, and ingress still returns HTTP 200.

## Phase B Evidence Pack (reader-generated)

The 17-gate Phase B workflow is reader-generated. Running `trigger.sh` and `falsify.sh` writes the raw cohort files (`01`-`13`) into your local [`evidence/`](evidence/README.md) directory; then `verify.sh` reads only those local files and deterministically emits the four derived gate JSONs (`14`-`17`). `verify.sh` makes no live Azure calls.

- **Gate 14** proves cohort integrity: canonical files present, parseable, bounded in one UTC lineage, anchor-consistent, and bound to the same `latestReadyRevisionName` across 02/05/08/12.
- **Gate 15** proves H1: Routing Intent is enabled, effective routes show `0.0.0.0/0` targeting the hub firewall, `az containerapp secret set` exits non-zero, stderr contains the MI / `openid-configuration` markers, `kvref-h1` is absent, and ingress stays HTTP 200.
- **Gate 16** proves H2: Routing Intent is removed, effective routes no longer show `0.0.0.0/0` targeting the hub firewall, a **new** secret-set attempt succeeds, `kvref-h2` is present, and ingress stays HTTP 200.
- **Gate 17** performs the bounded H1↔H2 diff and states the narrow claim ceiling explicitly: Routing Intent is the controlled route-state variable; DNS override, Key Vault private endpoint behavior, and packet capture are explicitly out of scope.

Once you have generated the local cohort, you can re-run `verify.sh` offline as often as needed, even after `cleanup.sh` has deleted the resource group, provided the local files 01-13 remain in place:

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4d/
bash verify.sh
```

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| Existing secured-hub mode | Reuses existing vWAN spend |
| Synthetic Virtual WAN + secured hub | High; dominant cost for the run |
| Container Apps + Log Analytics | <$0.25 / hour |
| Key Vault (Standard) | negligible |

Delete the resource group immediately after capturing evidence. In synthetic mode, the Virtual WAN secured hub dominates cost.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/aca-secret-kv-ref-mi-network-path-h4d.md`
- Playbook: `docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md` (H4 hypothesis)
- Platform: `docs/platform/networking/egress-control.md`
- Related playbook: `docs/troubleshooting/playbooks/identity-and-configuration/managed-identity-auth-failure.md`
