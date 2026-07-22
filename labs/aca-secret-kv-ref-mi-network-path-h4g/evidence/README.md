# Evidence pack — `aca-secret-kv-ref-mi-network-path-h4g` lab

This directory is the local workspace for the **reader-generated** Phase B evidence pack for `aca-secret-kv-ref-mi-network-path-h4g`. The repository does not ship a committed cohort for this lab; the files below are created by your own run.

- `labs/aca-secret-kv-ref-mi-network-path-h4g/trigger.sh` writes the H0 baseline raw files (`01`-`05`).
- `labs/aca-secret-kv-ref-mi-network-path-h4g/falsify.sh` writes the H1 Azure Firewall Premium TLS-inspection and H2 exemption-remediation raw files (`06`-`13`).
- `labs/aca-secret-kv-ref-mi-network-path-h4g/verify.sh` reads only those local raw files and writes the derived gate JSONs (`14`-`17`).

The claim ceiling is intentionally narrow. A passing run directly observes only that the firewall policy TLS-inspection setting for the **Entra authority FQDNs** and the secret-set outcomes flip together: H0 succeeds with `terminateTLS=false`, H1 fails with `terminateTLS=true`, and H2 succeeds again when the exemption is restored with `terminateTLS=false`.

- [Observed] The workload-replica `openssl s_client` capture can prove whether **workload** traffic to `login.microsoftonline.com:443` saw the lab interception CA chain during H1 and whether that CA disappeared again during H2.
- [Strongly Suggested] The ACA-managed **control-plane** secret resolver is affected by the same Entra-authority TLS-inspection change because H0 succeeds, H1 fails, and H2 succeeds with the same app, Key Vault, identity, RBAC, revision, ingress, firewall, route table, and DNS state.
- [Not Proven] The evidence pack does **not** directly observe the control-plane TLS chain, does **not** prove identical workload/control-plane egress, does **not** generalize beyond the two exercised Entra authority FQDNs, and does **not** claim anything about third-party NVAs or Key Vault data-plane failure.

## Capture timeline

1. **H0 baseline.** `trigger.sh` writes `01`-`05`: infrastructure deployment, healthy app baseline, out-of-band Key Vault secret creation, successful `az containerapp secret set`, and `kvref-h0` present.
2. **H1 trigger.** `falsify.sh` writes `06`-`09`: the Entra-authority rule flips to `terminateTLS=true`, the secret-set command fails with a managed-identity / OIDC clue plus a TLS / certificate clue, the app keeps serving HTTP 200 on the same revision, `kvref-h1` stays absent, and the H1 reader-generated workload `openssl` capture records the unexpected interception CA chain.
3. **H2 fix.** `falsify.sh` continues with `10`-`13`: the Entra-authority rule is set back to `terminateTLS=false`, a **new** secret-set attempt succeeds, `kvref-h2` appears, and the H2 reader-generated workload `openssl` capture shows that the interception CA no longer appears on that workload path.
4. **Phase B overlay.** `verify.sh` re-parses the raw cohort and deterministically writes Gate 14 through Gate 17.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates file presence, parseability, monotonic UTC ordering, cross-file anchor consistency, the revision silence invariant, and the explicit H4g topology anchors: Azure Firewall Premium present, Firewall Policy Premium present, TLS inspection configured, route table attached, no NSG deny trigger, no custom DNS override, and no Virtual WAN routing intent.
- **Gate 15 — `15-h1-tls-inspection-produces-failure-gate.json`**: proves H1 changed the Entra-authority rule to `terminateTLS=true`, the secret-set command failed with the classifier signature, `kvref-h1` stayed absent, ingress stayed HTTP 200, and the workload `openssl` evidence shows the lab interception CA chain.
- **Gate 16 — `16-h2-exemption-restores-success-gate.json`**: proves H2 restored the Entra-authority exemption (`terminateTLS=false`), a new secret-set attempt succeeded, `kvref-h2` appeared, ingress stayed HTTP 200, and the workload `openssl` evidence shows the lab interception CA no longer appears.
- **Gate 17 — `17-bounded-falsification-gate.json`**: states the bounded H1↔H2 claim explicitly — only the Entra-authority TLS-inspection flag changed while firewall presence, route-table presence, Key Vault, identity, RBAC, revision, ingress, NSG, and DNS stayed constant.

## File index

| File | Purpose |
|---|---|
| `01-deployment-outputs.json` | Bicep outputs and topology anchors proving Azure Firewall Premium, Firewall Policy Premium, TLS inspection, and route table presence |
| `02-h0-app-state-before.json` | Container App baseline surface before H0 secret set |
| `03-h0-kv-secret-created.json` | Key Vault secret created out-of-band for H0 |
| `04-h0-secret-set-outcome.json` | H0 outcome: secret set succeeds |
| `05-h0-app-state-after.json` | H0 post-state: revision unchanged, `kvref-h0` present |
| `06-h1-entra-rule-updated.json` | H1 state: Entra-authority application rule now has `terminateTLS=true` |
| `07-h1-secret-set-outcome.json` | H1 outcome: secret set fails with classifier-friendly stderr evidence |
| `08-h1-app-state.json` | H1 silence gate: revision unchanged, ingress HTTP 200, `kvref-h1` absent |
| `09-h1-rule-state-and-openssl.json` | H1 firewall rule snapshot plus reader-generated workload `openssl` capture showing the interception CA |
| `10-h2-entra-rule-updated.json` | H2 state: Entra-authority application rule restored to `terminateTLS=false` |
| `11-h2-secret-set-outcome.json` | H2 outcome: new secret-set attempt succeeds |
| `12-h2-app-state.json` | H2 success gate: revision unchanged, ingress HTTP 200, `kvref-h2` present |
| `13-h2-rule-state-and-openssl.json` | H2 firewall rule snapshot plus reader-generated workload `openssl` capture showing the interception CA is absent |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-tls-inspection-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-exemption-restores-success-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4g/

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
    --template-file infra/main.bicep \
    --parameters baseName="$BASE_NAME" \
    --parameters deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)" \
    --parameters tlsInspectionCaKeyVaultSecretId="$TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID" \
    --parameters tlsInspectionCaCertificateName="$TLS_INSPECTION_CA_CERTIFICATE_NAME" \
    --parameters tlsInspectionIdentityResourceId="$TLS_INSPECTION_IDENTITY_RESOURCE_ID"

bash trigger.sh
bash falsify.sh
bash verify.sh
```

| Command/Parameter | Purpose |
| --- | --- |
| `az group create` | Create the resource group used by the local reproduction. |
| `--name` | Set the resource group name. |
| `--location` | Set the Azure region for the resource group. |
| `az deployment group create` | Deploy the H4g lab infrastructure into that resource group. |
| `--resource-group` | Target the resource group for the deployment. |
| `--name` | Use the H4g deployment name expected by the scripts. |
| `--template-file` | Point Azure CLI at the local H4g Bicep file. |
| `--parameters` | Pass the required Bicep parameters, including the deployer object ID and the TLS-inspection CA secret reference. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter from the signed-in user's object ID. |
| `tlsInspectionCaKeyVaultSecretId="$TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID"` | Supply the Key Vault secret ID for the intermediate CA PFX used by Firewall Premium TLS inspection. |
| `tlsInspectionCaCertificateName="$TLS_INSPECTION_CA_CERTIFICATE_NAME"` | Supply the display name used by the Firewall Policy CA reference. |
| `tlsInspectionIdentityResourceId="$TLS_INSPECTION_IDENTITY_RESOURCE_ID"` | Supply the resource ID of the pre-created user-assigned identity that already has Get/List access to the CA vault. |

Before you run the deployment above, complete these reader-owned prerequisites:

1. Create a **user-assigned managed identity** in your subscription.
2. Grant that identity **Get** and **List** permission on the Key Vault that stores the intermediate CA certificate secret used for TLS inspection.
3. Export that identity's resource ID as `TLS_INSPECTION_IDENTITY_RESOURCE_ID` and pass it into `main.bicep`.

Without those three pre-steps, a clean one-pass deployment cannot attach the TLS-inspection CA to the Firewall Policy because Azure Firewall Premium must already be able to read the CA secret through that user-assigned identity.

The verifier is hermetic once the raw cohort exists: `verify.sh` reads only local files `01`-`13`, rewrites the four derived gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and makes no Azure calls. You can re-run `verify.sh` offline after `cleanup.sh` deletes the resource group, provided the local raw files remain in place.
