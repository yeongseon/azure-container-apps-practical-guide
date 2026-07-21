# Evidence pack — `aca-secret-kv-ref-mi-network-path-h4e` lab

This directory is the local workspace for the **reader-generated** Phase B evidence pack for `aca-secret-kv-ref-mi-network-path-h4e`. The repository does not ship a committed cohort for this lab; the files below are created by your own run.

- `labs/aca-secret-kv-ref-mi-network-path-h4e/trigger.sh` writes the H0 baseline raw files (`01`-`05`).
- `labs/aca-secret-kv-ref-mi-network-path-h4e/falsify.sh` writes the H1 DNS-override and H2 override-removal raw files (`06`-`13`).
- `labs/aca-secret-kv-ref-mi-network-path-h4e/verify.sh` reads only those local raw files and writes the derived gate JSONs (`14`-`17`).

The claim ceiling is intentionally narrow. A passing run proves only one live reproduction of the Container Apps → Azure-provided DNS → custom linked Private DNS override → Entra authority path where H0 succeeds with no override, H1 fails with the override pointed at `192.0.2.1`, and H2 succeeds again after the override is removed and the post-removal wait exceeds TTL.

## Capture timeline

1. **H0 baseline.** `trigger.sh` writes `01`-`05`: infrastructure deployment, healthy app baseline, out-of-band Key Vault secret creation, successful `az containerapp secret set`, `kvref-h0` present, and baseline revision anchored.
2. **H1 DNS override.** `falsify.sh` writes `06`-`09`: custom Private DNS zones for `login.microsoftonline.com` and `login.microsoft.com` are created, linked to the ACA VNet, both apex A records point to `192.0.2.1`, `az containerapp secret set` fails, the app still serves HTTP 200 on the same revision, `kvref-h1` stays absent, and replica `nslookup login.microsoftonline.com` resolves to `192.0.2.1`.
3. **H2 override removal.** `falsify.sh` continues with `10`-`13`: both links/zones are removed, the script waits beyond TTL, a **new** `az containerapp secret set` succeeds, `kvref-h2` appears, and replica `nslookup login.microsoftonline.com` no longer resolves to `192.0.2.1`.
4. **Phase B overlay.** `verify.sh` re-parses the raw cohort and deterministically writes Gate 14 through Gate 17.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates file presence, parseability, monotonic UTC ordering, cross-file anchor consistency, the revision silence invariant, and the explicit non-H4a baseline topology (no Azure Firewall, no UDR, Azure-provided DNS).
- **Gate 15 — `15-h1-dns-override-produces-failure-gate.json`**: proves H1 created the custom DNS override, failed the secret-set call, kept `kvref-h1` absent, preserved ingress HTTP 200, and showed the sink IP in the replica DNS view.
- **Gate 16 — `16-h2-override-removal-restores-success-gate.json`**: proves H2 removed the override, waited beyond TTL, succeeded on a new secret-set call, restored `kvref-h2`, preserved ingress HTTP 200, and removed the sink IP from the replica DNS view.
- **Gate 17 — `17-bounded-falsification-gate.json`**: states the bounded H1↔H2 claim explicitly — the custom DNS override changed, while the rest of the topology stayed constant.

## File index

| File | Purpose |
|---|---|
| `01-deployment-outputs.json` | Bicep deployment outputs and topology anchors proving no Azure Firewall, no UDR, and Azure-provided DNS |
| `02-h0-app-state-before.json` | Container app baseline surface before H0 secret set |
| `03-h0-kv-secret-created.json` | Key Vault secret created out-of-band for H0 |
| `04-h0-secret-set-outcome.json` | H0 outcome: secret set succeeds |
| `05-h0-app-state-after.json` | H0 post-state: revision unchanged, `kvref-h0` present |
| `06-h1-dns-override-created.json` | H1 state: both custom Private DNS zones linked to the VNet with apex A records → `192.0.2.1` |
| `07-h1-secret-set-outcome.json` | H1 outcome: secret set fails |
| `08-h1-app-state.json` | H1 silence gate: revision unchanged, ingress HTTP 200, `kvref-h1` absent |
| `09-h1-replica-dns-view.json` | H1 replica data-plane DNS view showing `login.microsoftonline.com -> 192.0.2.1` |
| `10-h2-dns-override-removed.json` | H2 state: links/zones removed, post-removal wait exceeds TTL |
| `11-h2-secret-set-outcome.json` | H2 outcome: new secret-set attempt succeeds |
| `12-h2-app-state.json` | H2 success gate: revision unchanged, ingress HTTP 200, `kvref-h2` present |
| `13-h2-replica-dns-view.json` | H2 replica data-plane DNS view showing the sink IP no longer resolves |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-dns-override-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-override-removal-restores-success-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4e/

export RG="rg-aca-secret-kv-ref-mi-network-path-h4e"
export LOCATION="koreacentral"
export BASE_NAME="acasech4e01"

az group create --name "$RG" --location "$LOCATION"
az deployment group create \
    --resource-group "$RG" \
    --name aca-secret-kv-ref-mi-network-path-h4e \
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
| `az deployment group create` | Deploy the H4e lab infrastructure into that resource group. |
| `--resource-group` | Target the resource group for the deployment. |
| `--name` | Use the H4e deployment name expected by the scripts. |
| `--template-file` | Point Azure CLI at the local H4e Bicep file. |
| `--parameters` | Pass required Bicep parameters, including the required deployment principal object ID. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter from the signed-in user's object ID. |

The verifier is hermetic once the raw cohort exists: `verify.sh` reads only local files `01`-`13`, rewrites the four derived gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and makes no Azure calls. You can re-run `verify.sh` offline after `cleanup.sh` deletes the resource group, provided the local raw files remain in place.
