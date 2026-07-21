# Evidence pack — `aca-secret-kv-ref-mi-network-path-h4c` lab

This directory is the local workspace for the **reader-generated** Phase B evidence pack for `aca-secret-kv-ref-mi-network-path-h4c`. The repository does not ship a committed cohort for this lab; the files below are created by your own run.

- `labs/aca-secret-kv-ref-mi-network-path-h4c/trigger.sh` writes the H0 baseline raw files (`01`-`05`).
- `labs/aca-secret-kv-ref-mi-network-path-h4c/falsify.sh` writes the H1 NSG-deny and H2 allow-remediation raw files (`06`-`13`).
- `labs/aca-secret-kv-ref-mi-network-path-h4c/verify.sh` reads only those local raw files and writes the derived gate JSONs (`14`-`17`).

The claim ceiling is intentionally narrow. A passing run directly observes only that the NSG configuration and the secret-set outcomes flip together: H0 succeeds with the NSG attached but no custom AAD rule, H1 fails with `deny-aad-443-h4c`, and H2 succeeds again after `allow-aad-443-h4c` is added at higher priority. That the ACA-managed control-plane secret resolver actually traverses the Container Apps → workload-subnet NSG → Entra authority path is `[Inferred]` / `[Strongly Suggested]` from that flip — it is not directly observed.

## Capture timeline

1. **H0 baseline.** `trigger.sh` writes `01`-`05`: infrastructure deployment, healthy app baseline, out-of-band Key Vault secret creation, successful `az containerapp secret set`, `kvref-h0` present, baseline revision anchored, and baseline NSG rule enumeration proving the H4c deny/allow rules do not exist yet.
2. **H1 NSG deny.** `falsify.sh` writes `06`-`09`: custom outbound Deny rule `deny-aad-443-h4c` is created for `AzureActiveDirectory:443`, `az containerapp secret set` fails, the app still serves HTTP 200 on the same revision, `kvref-h1` stays absent, and NSG rule enumeration proves no higher-priority matching Allow exists.
3. **H2 allow remediation.** `falsify.sh` continues with `10`-`13`: custom outbound Allow rule `allow-aad-443-h4c` is created at higher priority while the Deny remains, a **new** `az containerapp secret set` succeeds, `kvref-h2` appears, and NSG rule enumeration proves the Allow now governs.
4. **Phase B overlay.** `verify.sh` re-parses the raw cohort and deterministically writes Gate 14 through Gate 17.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates file presence, parseability, monotonic UTC ordering, cross-file anchor consistency, the revision silence invariant, the explicit non-H4a baseline topology (NSG attached, no Azure Firewall, no UDR, Azure-provided DNS), and the absence of storage-account / flow-log artifacts.
- **Gate 15 — `15-h1-nsg-deny-produces-failure-gate.json`**: proves H1 created the outbound NSG deny rule, failed the secret-set call with the managed-identity OIDC signature, kept `kvref-h1` absent, preserved ingress HTTP 200, and had no higher-priority matching Allow at H1.
- **Gate 16 — `16-h2-allow-remediation-restores-success-gate.json`**: proves H2 created the higher-priority Allow, succeeded on a new secret-set call, restored `kvref-h2`, preserved ingress HTTP 200, and showed the Allow priority wins over the Deny priority.
- **Gate 17 — `17-bounded-falsification-gate.json`**: states the bounded H1↔H2 claim explicitly — only the documented higher-priority Allow rule changed, while the rest of the topology stayed constant.

## File index

| File | Purpose |
|---|---|
| `01-deployment-outputs.json` | Bicep deployment outputs and topology anchors proving NSG attached, no Azure Firewall, no UDR, Azure-provided DNS, and no baseline H4c deny/allow rule |
| `02-h0-app-state-before.json` | Container app baseline surface before H0 secret set |
| `03-h0-kv-secret-created.json` | Key Vault secret created out-of-band for H0 |
| `04-h0-secret-set-outcome.json` | H0 outcome: secret set succeeds |
| `05-h0-app-state-after.json` | H0 post-state: revision unchanged, `kvref-h0` present |
| `06-h1-nsg-deny-created.json` | H1 state: `deny-aad-443-h4c` created for outbound `AzureActiveDirectory:443` with no higher-priority matching Allow |
| `07-h1-secret-set-outcome.json` | H1 outcome: secret set fails |
| `08-h1-app-state.json` | H1 silence gate: revision unchanged, ingress HTTP 200, `kvref-h1` absent |
| `09-h1-nsg-effective-rules.json` | H1 NSG rule view showing the Deny governs outbound `AzureActiveDirectory:443` |
| `10-h2-nsg-allow-created.json` | H2 state: `allow-aad-443-h4c` created at priority `100`, lower than the Deny priority `200` |
| `11-h2-secret-set-outcome.json` | H2 outcome: new secret-set attempt succeeds |
| `12-h2-app-state.json` | H2 success gate: revision unchanged, ingress HTTP 200, `kvref-h2` present |
| `13-h2-nsg-effective-rules.json` | H2 NSG rule view showing the Allow now governs outbound `AzureActiveDirectory:443` |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-nsg-deny-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-allow-remediation-restores-success-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4c/

export RG="rg-aca-secret-kv-ref-mi-network-path-h4c"
export LOCATION="koreacentral"
export BASE_NAME="acasech4c01"

az group create --name "$RG" --location "$LOCATION"
az deployment group create \
    --resource-group "$RG" \
    --name aca-secret-kv-ref-mi-network-path-h4c \
    --template-file infra/main.bicep \
    --parameters baseName="$BASE_NAME" deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"

bash trigger.sh
bash falsify.sh
bash verify.sh
```

| Command/Parameter | Purpose |
| --- | --- |
| `az group create` | Create the resource group used by the local reproduction. |
| `--name` | Set the resource group name. |
| `--location` | Set the Azure region for the resource group. |
| `az deployment group create` | Deploy the H4c lab infrastructure into that resource group. |
| `--resource-group` | Target the resource group for the deployment. |
| `--name` | Use the H4c deployment name expected by the scripts. |
| `--template-file` | Point Azure CLI at the local H4c Bicep file. |
| `--parameters` | Pass required Bicep parameters, including the required deployment principal object ID. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter from the signed-in user's object ID. |

The verifier is hermetic once the raw cohort exists: `verify.sh` reads only local files `01`-`13`, rewrites the four derived gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and makes no Azure calls. You can re-run `verify.sh` offline after `cleanup.sh` deletes the resource group, provided the local raw files remain in place.
