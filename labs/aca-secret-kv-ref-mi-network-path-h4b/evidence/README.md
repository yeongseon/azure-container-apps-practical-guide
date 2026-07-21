# Evidence pack — `aca-secret-kv-ref-mi-network-path-h4b` lab

This directory is the local workspace for the **reader-generated** Phase B evidence pack for `aca-secret-kv-ref-mi-network-path-h4b`. The repository does not ship a committed cohort for this lab; the files below are created by your own run.

- `labs/aca-secret-kv-ref-mi-network-path-h4b/trigger.sh` writes the H0 baseline raw files (`01`-`05`).
- `labs/aca-secret-kv-ref-mi-network-path-h4b/falsify.sh` writes the H1 logging-gap and H2 observability raw files (`06`-`13`).
- `labs/aca-secret-kv-ref-mi-network-path-h4b/verify.sh` reads only those local raw files and writes the derived gate JSONs (`14`-`17`).

The claim ceiling is intentionally narrow. A passing run proves only one live reproduction of the Container Apps → UDR → Azure Firewall → Entra authority path where H0 succeeds with the Entra rule present, H1 fails with the rule absent and `AzureFirewallApplicationRule` logging disabled, and H2 still fails with the rule absent after `AzureFirewallApplicationRule` logging is re-enabled for a **new** attempt.

## Capture timeline

1. **H0 baseline.** `trigger.sh` writes `01`-`05`: infrastructure deployment, healthy app baseline, out-of-band Key Vault secret creation, successful `az containerapp secret set`, `kvref-h0` present, and baseline revision anchored.
2. **H1 logging-gap trap.** `falsify.sh` writes `06`-`09`: the Entra rule collection is removed, `AzureFirewallApplicationRule` logging is disabled, `az containerapp secret set` fails, the app still serves HTTP 200 on the same revision, `kvref-h1` stays absent, and the H1 firewall query returns **0** Deny rows.
3. **H2 observability restoration.** `falsify.sh` continues with `10`-`13`: `AzureFirewallApplicationRule` logging is re-enabled while the Entra rule stays absent, a pre-H2 guard window proves **0** Deny rows exist before the new attempt, a **new** `az containerapp secret set` still fails, `kvref-h2` stays absent, and the H2 firewall query returns **>=1** Deny row.
4. **Phase B overlay.** `verify.sh` re-parses the raw cohort and deterministically writes Gate 14 through Gate 17.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates file presence, parseability, monotonic UTC ordering, cross-file anchor consistency, H1-before-H2 temporal ordering, and the revision silence invariant.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves H1 removed the rule, disabled `AzureFirewallApplicationRule` logging, failed the secret-set call, kept `kvref-h1` absent, preserved ingress HTTP 200, and produced **0** Deny rows.
- **Gate 16 — `16-h2-observability-restored-gate.json`**: proves H2 re-enabled `AzureFirewallApplicationRule` logging while the rule stayed absent, preserved a **0**-row pre-H2 guard window, still failed the H2 secret-set call, kept `kvref-h2` absent, preserved ingress HTTP 200, and produced **>=1** Deny row after the new attempt.
- **Gate 17 — `17-bounded-falsification-gate.json`**: states the bounded H1↔H2 claim explicitly — observability changed, connectivity did not.

## File index

| File | Purpose |
|---|---|
| `01-deployment-outputs.json` | Bicep deployment outputs and cross-file anchors, including firewall resource ID |
| `02-h0-app-state-before.json` | Container app baseline surface before H0 secret set |
| `03-h0-kv-secret-created.json` | Key Vault secret created out-of-band for H0 |
| `04-h0-secret-set-outcome.json` | H0 outcome: secret set succeeds |
| `05-h0-app-state-after.json` | H0 post-state: revision unchanged, `kvref-h0` present |
| `06-h1-firewall-rule-removed.json` | H1 state: Entra rule removed and `AzureFirewallApplicationRule` logging disabled |
| `07-h1-secret-set-outcome.json` | H1 outcome: secret set fails |
| `08-h1-app-state.json` | H1 silence gate: revision unchanged, ingress HTTP 200, `kvref-h1` absent |
| `09-h1-firewall-deny-log-absent.json` | H1 firewall query proving `final_deny_row_count == 0` |
| `10-h2-firewall-diagnostics-enabled.json` | H2 state: logging re-enabled, rule still absent, pre-H2 guard row count = 0 |
| `11-h2-secret-set-outcome.json` | H2 outcome: new secret-set attempt still fails |
| `12-h2-app-state.json` | H2 silence gate: revision unchanged, ingress HTTP 200, `kvref-h2` absent |
| `13-h2-firewall-deny-log.json` | H2 firewall query proving `final_deny_row_count >= 1` after the new attempt |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-observability-restored-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4b/

export RG="rg-aca-secret-kv-ref-mi-network-path-h4b"
export LOCATION="koreacentral"
export BASE_NAME="acasecretmi"

az group create --name "$RG" --location "$LOCATION"
az deployment group create \
    --resource-group "$RG" \
    --name aca-secret-kv-ref-mi-network-path-h4b \
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
| `az deployment group create` | Deploy the H4b lab infrastructure into that resource group. |
| `--resource-group` | Target the resource group for the deployment. |
| `--name` | Use the H4b deployment name expected by the scripts. |
| `--template-file` | Point Azure CLI at the local H4b Bicep file. |
| `--parameters` | Pass required Bicep parameters, including the required deployment principal object ID. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter from the signed-in user's object ID. |

The verifier is hermetic once the raw cohort exists: `verify.sh` reads only local files `01`-`13`, rewrites the four derived gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and makes no Azure calls. You can re-run `verify.sh` offline after `cleanup.sh` deletes the resource group, provided the local raw files remain in place.
