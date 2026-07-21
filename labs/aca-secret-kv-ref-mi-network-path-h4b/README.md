# Lab: ACA Secret Key Vault Reference — Managed Identity Network Path (H4b Logging Gap)

Reproduce the failure surface documented in
[Container Apps: Secret and Key Vault Reference Failure](../../docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)
for Hypothesis **H4 — MI OIDC discovery blocked by egress control**.

This H4b variant is the **logging-gap inversion** of H4a. In H4a, H1 and H2 flip connectivity by removing and restoring the Entra firewall rule. In H4b, the Entra firewall rule is absent in **both** H1 and H2, so `az containerapp secret set --identity system --key-vault-url ...` fails in both phases. What changes between H1 and H2 is **observability**:

- **H0** — Entra rule present + `AzureFirewallApplicationRule` diagnostics enabled → secret set succeeds.
- **H1** — Entra rule removed + `AzureFirewallApplicationRule` diagnostics disabled → secret set fails, but the firewall denial is invisible in KQL.
- **H2** — Entra rule still removed + `AzureFirewallApplicationRule` diagnostics re-enabled → a **new** secret-set attempt still fails, and the firewall denial becomes visible.

The lesson is narrow: enabling diagnostics restores **evidence**, not **connectivity**.

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
Azure Firewall Basic (Policy: afwp-<baseName>-<suffix>)
       │  Application Rule Collection: allow-entra-authority
       │  Rule: allow-entra-login
       │  Destination FQDNs:
       │    - login.microsoftonline.com
       │    - login.microsoft.com
       │
       │  H4b phase behavior:
       │    - H0: rule present, AzureFirewallApplicationRule logging enabled
       │    - H1: rule removed, AzureFirewallApplicationRule logging disabled
       │    - H2: rule still removed, AzureFirewallApplicationRule logging re-enabled
       ▼
Entra ID authority (public)
       │  .well-known/openid-configuration → token endpoint
       ▼
Key Vault (public endpoint, RBAC-granted "Key Vault Secrets User" to the MI)
```

## Structure

```text
labs/aca-secret-kv-ref-mi-network-path-h4b/
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
export RG="rg-aca-secret-kv-ref-mi-network-path-h4b"
export LOCATION="koreacentral"
export BASE_NAME="acasecretmi"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" \
    --name aca-secret-kv-ref-mi-network-path-h4b \
    --template-file labs/aca-secret-kv-ref-mi-network-path-h4b/infra/main.bicep \
    --parameters baseName="$BASE_NAME" deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"

bash labs/aca-secret-kv-ref-mi-network-path-h4b/trigger.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4b/falsify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4b/verify.sh
bash labs/aca-secret-kv-ref-mi-network-path-h4b/cleanup.sh
```

| Command/Parameter | Purpose |
| --- | --- |
| `az group create` | Create the resource group for the lab run. |
| `--name` | Set the resource group name. |
| `--location` | Set the Azure region for the resource group. |
| `az deployment group create` | Deploy the H4b lab infrastructure into the resource group. |
| `--resource-group` | Target the resource group created for the lab. |
| `--name` | Give the deployment a stable H4b deployment name. |
| `--template-file` | Point Azure CLI at the H4b Bicep template. |
| `--parameters` | Pass required Bicep parameters, including the required deployment principal object ID. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the base naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter expected by `main.bicep`. |

## What "Success" Looks Like

The lab is reproduced when all of the following hold:

1. **H0 baseline**: With the Entra Application Rule present and the firewall diagnostic category enabled, `az containerapp secret set --identity system --key-vault-url ...` succeeds. The secret `kvref-h0` appears in `configuration.secrets`, and `latestReadyRevisionName` does not change.
2. **H1 logging-gap trap**: After removing the Application Rule Collection `allow-entra-authority` **and** disabling the `AzureFirewallApplicationRule` diagnostic category, the same command fails with the managed-identity OIDC discovery EOF surface. The exit code is non-zero. `kvref-h1` is absent from `configuration.secrets`. The revision name is unchanged. Ingress still returns HTTP 200. The H1 firewall KQL query over `AZFWApplicationRule` returns **0 Deny rows** because the denial happened but was not logged.
3. **H2 observability restoration**: After re-enabling the `AzureFirewallApplicationRule` diagnostic category while the Entra rule remains absent, a **new** secret-set attempt still fails. `kvref-h2` is absent from `configuration.secrets`. The revision name is still unchanged. Ingress still returns HTTP 200. The H2 firewall KQL query returns **at least one Deny row**, proving that observability was restored without fixing connectivity.

## Phase B Evidence Pack (reader-generated)

The 17-gate Phase B workflow is reader-generated. Running `trigger.sh` and `falsify.sh` writes the raw cohort files (`01`-`13`) into your local [`evidence/`](evidence/README.md) directory; then `verify.sh` reads only those local files and deterministically emits the four derived gate JSONs (`14`-`17`). `verify.sh` makes no live Azure calls.

- **Gate 14** proves cohort integrity: canonical files present, parseable, bounded in one UTC lineage, anchor-consistent, and bound to the same `latestReadyRevisionName` across 02/05/08/12.
- **Gate 15** proves H1: the rule collection is absent, `AzureFirewallApplicationRule` logging is disabled, `az containerapp secret set` exits non-zero, `kvref-h1` is absent, ingress stays HTTP 200, and the H1 firewall query shows **0** Deny rows — the logging gap.
- **Gate 16** proves H2: `AzureFirewallApplicationRule` logging is re-enabled, the rule collection is **still absent**, the pre-H2 guard window still shows **0** Deny rows, a **new** H2 secret-set attempt still fails, `kvref-h2` is absent, ingress stays HTTP 200, and the H2 firewall query now shows **>=1** Deny row.
- **Gate 17** performs the bounded H1↔H2 diff and states the narrow claim ceiling explicitly: H1→H2 flips observability only, not connectivity.

Once you have generated the local cohort, you can re-run `verify.sh` offline as often as needed, even after `cleanup.sh` has deleted the resource group, provided the local files 01-13 remain in place:

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4b/
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

- Lab guide: `docs/troubleshooting/lab-guides/aca-secret-kv-ref-mi-network-path-h4b.md`
- Playbook: `docs/troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md` (H4 hypothesis)
- Platform: `docs/platform/networking/egress-control.md`
- Related playbook: `docs/troubleshooting/playbooks/identity-and-configuration/managed-identity-auth-failure.md`
