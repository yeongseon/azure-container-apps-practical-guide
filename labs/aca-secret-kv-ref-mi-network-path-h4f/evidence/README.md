# Evidence pack — `aca-secret-kv-ref-mi-network-path-h4f` lab

This directory is the local workspace for the **reader-generated** Phase B evidence pack for `aca-secret-kv-ref-mi-network-path-h4f`. The repository does not ship a committed cohort for this lab; the files below are created by your own run.

- `labs/aca-secret-kv-ref-mi-network-path-h4f/trigger.sh` writes the H0 baseline raw files (`01`-`05`).
- `labs/aca-secret-kv-ref-mi-network-path-h4f/falsify.sh` writes the H1 Linux NVA-surrogate DROP-rule and H2 remediation raw files (`06`-`13`).
- `labs/aca-secret-kv-ref-mi-network-path-h4f/verify.sh` reads only those local raw files and writes the derived gate JSONs (`14`-`17`).

The claim ceiling is intentionally narrow. A passing run directly observes only that the Linux forwarding VM's Entra DROP rule and the secret-set outcomes flip together: H0 succeeds with no DROP rule, H1 fails with the DROP rule present, and H2 succeeds again when the same DROP rule is removed.

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

## Capture timeline

1. **H0 baseline.** `trigger.sh` writes `01`-`05`: infrastructure deployment, healthy app baseline, out-of-band Key Vault secret creation, successful `az containerapp secret set`, and `kvref-h0` present.
2. **H1 trigger.** `falsify.sh` writes `06`-`09`: the Linux NVA surrogate installs the nftables DROP rule for `AzureActiveDirectory` service-tag prefixes on tcp/443, the secret-set command fails with a managed-identity / OIDC clue plus a connectivity / timeout clue, the app keeps serving HTTP 200 on the same revision, `kvref-h1` stays absent, and the workload probes prove the Entra hosts are blocked from the workload data plane.
3. **H2 fix.** `falsify.sh` continues with `10`-`13`: the same DROP rule is removed, a **new** secret-set attempt succeeds, `kvref-h2` appears, and the same workload probes succeed again while the DROP rule is absent.
4. **Phase B overlay.** `verify.sh` re-parses the raw cohort and deterministically writes Gate 14 through Gate 17.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates file presence, parseability, monotonic UTC ordering, cross-file anchor consistency, the revision silence invariant, and the explicit H4f topology anchors: Linux NVA surrogate present, NIC IP forwarding enabled, OS IP forwarding enabled, NAT enabled, route table attached, no Azure Firewall, no Firewall Policy, no TLS inspection, no NSG deny trigger, no custom DNS override, and no Virtual WAN routing intent.
- **Gate 15 — `15-h1-nva-surrogate-drop-produces-failure-gate.json`**: proves H1 installed the DROP rule, the secret-set command failed with the classifier signature, `kvref-h1` stayed absent, ingress stayed HTTP 200, and workload probes to both Entra hosts failed.
- **Gate 16 — `16-h2-nva-surrogate-allow-restores-success-gate.json`**: proves H2 removed the DROP rule, a new secret-set attempt succeeded, `kvref-h2` appeared, ingress stayed HTTP 200, and workload probes to both Entra hosts succeeded.
- **Gate 17 — `17-bounded-falsification-gate.json`**: states the bounded H1↔H2 claim explicitly — only the NVA DROP rule changed while route-table presence, forwarding, NAT, Key Vault, identity, RBAC, revision, ingress, NSG, and DNS stayed constant.

## File index

| File | Purpose |
|---|---|
| `01-deployment-outputs.json` | Bicep outputs and topology anchors proving the Linux NVA surrogate, route table, forwarding, and NAT baseline |
| `02-h0-app-state-before.json` | Container App baseline surface before H0 secret set |
| `03-h0-kv-secret-created.json` | Key Vault secret created out-of-band for H0 |
| `04-h0-secret-set-outcome.json` | H0 outcome: secret set succeeds |
| `05-h0-app-state-after.json` | H0 post-state: revision unchanged, `kvref-h0` present |
| `06-h1-nva-drop-rule-installed.json` | H1 state: Linux NVA surrogate DROP rule installed for AzureActiveDirectory service-tag prefixes |
| `07-h1-secret-set-outcome.json` | H1 outcome: secret set fails with classifier-friendly stderr evidence |
| `08-h1-app-state.json` | H1 silence gate: revision unchanged, ingress HTTP 200, `kvref-h1` absent |
| `09-h1-nva-rule-state-and-workload-probe.json` | H1 rule snapshot plus the recorded rule counter and workload probes showing both Entra hosts fail |
| `10-h2-nva-drop-rule-removed.json` | H2 state: same DROP rule removed from the Linux NVA surrogate |
| `11-h2-secret-set-outcome.json` | H2 outcome: new secret-set attempt succeeds |
| `12-h2-app-state.json` | H2 success gate: revision unchanged, ingress HTTP 200, `kvref-h2` present |
| `13-h2-nva-rule-state-and-workload-probe.json` | H2 rule snapshot plus workload probes showing both Entra hosts succeed |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-nva-surrogate-drop-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-nva-surrogate-allow-restores-success-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

```bash
cd labs/aca-secret-kv-ref-mi-network-path-h4f/

export RG="rg-aca-secret-kv-ref-mi-network-path-h4f"
export LOCATION="koreacentral"
export BASE_NAME="acasech4f01"
export NVA_VM_ADMIN_PASSWORD="$(openssl rand -base64 24)Aa1!"

az group create --name "$RG" --location "$LOCATION"
az deployment group create \
    --resource-group "$RG" \
    --name aca-secret-kv-ref-mi-network-path-h4f \
    --template-file infra/main.bicep \
    --parameters baseName="$BASE_NAME" \
    --parameters deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)" \
    --parameters nvaVmAdminPassword="$NVA_VM_ADMIN_PASSWORD"

bash trigger.sh
bash falsify.sh
bash verify.sh
```

| Command/Parameter | Purpose |
| --- | --- |
| `az group create` | Create the resource group used by the local reproduction. |
| `--name` | Set the resource group name. |
| `--location` | Set the Azure region for the resource group. |
| `az deployment group create` | Deploy the H4f lab infrastructure into that resource group. |
| `--resource-group` | Target the resource group for the deployment. |
| `--name` | Use the H4f deployment name expected by the scripts. |
| `--template-file` | Point Azure CLI at the local H4f Bicep file. |
| `--parameters` | Pass the required Bicep parameters, including the deployer object ID and the one VM credential Azure requires at provision time. |
| `az ad signed-in-user show` | Resolve the signed-in user's Microsoft Entra object ID for the required deployment parameter. |
| `--query` | Select only the signed-in user's `id` field. |
| `--output` | Return the object ID as plain text for command substitution. |
| `baseName="$BASE_NAME"` | Supply the naming seed used by the template. |
| `deploymentPrincipalId="$(az ad signed-in-user show --query id --output tsv)"` | Supply the required `deploymentPrincipalId` parameter from the signed-in user's object ID. |
| `nvaVmAdminPassword="$NVA_VM_ADMIN_PASSWORD"` | Supply the one deployment-time VM credential required by Azure even though the lab uses `az vm run-command invoke` instead of SSH. |

The verifier is hermetic once the raw cohort exists: `verify.sh` reads only local files `01`-`13`, rewrites the four derived gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and makes no Azure calls. You can re-run `verify.sh` offline after `cleanup.sh` deletes the resource group, provided the local raw files remain in place.
