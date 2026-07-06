# Evidence pack — `aca-secret-kv-ref-mi-network-path` lab

This directory is the workspace where the **reader-generated** Phase B evidence pack for the `aca-secret-kv-ref-mi-network-path` lab lives after you run the workflow against your own Azure subscription. This repository does not ship a committed evidence cohort for this lab — the files below are populated by your local execution.

- `labs/aca-secret-kv-ref-mi-network-path/trigger.sh` writes the H0 baseline raw files (`01`-`05`) into this directory.
- `labs/aca-secret-kv-ref-mi-network-path/falsify.sh` writes the H1 failure and H2 recovery raw files (`06`-`13`) into this directory.
- `labs/aca-secret-kv-ref-mi-network-path/verify.sh` then reads only those local raw files and deterministically writes the four derived Phase B gate JSONs (`14`-`17`) alongside them.

The claim ceiling is deliberately narrow: a passing run of this workflow proves only what one live reproduction can support about the Container Apps → UDR → Azure Firewall → Entra authority network path with one Azure Firewall Basic instance, one Application Rule Collection controlling access to `login.microsoftonline.com` and `login.microsoft.com`, one system-assigned managed identity granted `Key Vault Secrets User` on a Standard-tier Key Vault, and three sequential `az containerapp secret set --identity system --key-vault-url ...` invocations (H0 baseline succeed, H1 fail after rule removal, H2 succeed after rule restore).

The workflow does **not** claim anything about: user-assigned identities, workload identity federation, private endpoints on Key Vault, other Entra authority FQDNs (`graph.microsoft.com`, `vault.azure.net` for token audience), Firewall Premium/Standard, log ingestion latency other than what the workflow's own retry loop tolerates, or other regions.

## Capture timeline (what each phase writes)

1. **Baseline-presence proof.** `trigger.sh` writes files `01`-`05` capturing the H0 window: infrastructure deployed with the Application Rule present, container app in `Healthy` state, Key Vault secret created out-of-band, `az containerapp secret set` succeeds, and the resulting `configuration.secrets` list contains `kvref-h0`. `05` also anchors the baseline `latestReadyRevisionName` used by the silence-gate invariant.
2. **H1 failure surface.** `falsify.sh` writes files `06`-`09` capturing the H1 window: the `allow-entra-authority` Application Rule Collection is removed; `az containerapp secret set` fails with the OIDC discovery EOF surface; the app is still serving HTTP 200 with the unchanged revision name (silence gate proved); the firewall `AZFWApplicationRule` log carries a `Deny` action row for `login.microsoftonline.com` from the ACA subnet source IP.
3. **H2 recovery surface.** `falsify.sh` continues by writing files `10`-`13` capturing the H2 window: the Application Rule Collection is restored with **both** `login.microsoftonline.com` and `login.microsoft.com` in one atomic rule; `az containerapp secret set` succeeds; `configuration.secrets` now contains `kvref-h2`; the revision name is still unchanged from baseline; the firewall log carries an `Allow` action row for the same destination FQDN.
4. **Phase B overlay.** `verify.sh` re-parses the raw files that phases 1-3 just wrote locally and deterministically writes Gate 14 through Gate 17.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, bounded UTC coherence, monotonic timestamp ordering (baseline → H1 → H2), pre/post lineage equality, anchor consistency (app FQDN, firewall policy name, LAW customer ID, ACA subnet prefix, rule collection name), and the non-vacuous **revision silence invariant** — `latestReadyRevisionName` identical across files 02 (baseline before), 05 (baseline after), 08 (H1), and 12 (H2). Secret updates do not create new revisions, so if any snapshot shows a different revision name the pack is compromised.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves baseline presence (H0 succeeded when the rule was present), confirms the rule collection is absent after removal, proves `az containerapp secret set` exit code is non-zero for H1, proves `kvref-h1` is absent from `configuration.secrets`, proves the silence gate (revision unchanged + HTTP 200 + secret absent), and proves the firewall log contains a `Deny` action row for `login.microsoftonline.com` from the ACA subnet source IP within the H1 window.
- **Gate 16 — `16-h2-fix-restores-success-gate.json`**: proves the rule collection is restored with both FQDNs in one atomic rule, proves `az containerapp secret set` exit code is 0 for H2, proves `kvref-h2` is present in `configuration.secrets` with a `keyVaultUrl` field, proves ingress still returns HTTP 200, and proves the firewall log contains an `Allow` action row for the same destination FQDN within the H2 window.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the bounded H1↔H2 diff (baseline-presence, trigger-absence in H1, recovery-presence in H2, revision silence invariant, controlled variable uniqueness), and enumerates the documented explicit drops (`stderr wording`, `log ingestion latency`, `retry cadence`, `component identity`, `response body shape`, `token caching`, `SKU generality`, `region generality`) — the eight properties this workflow explicitly does not claim.

## File index (populated locally after you run the workflow)

| File | Purpose |
|---|---|
| `01-deployment-outputs.json` | Bicep deployment outputs: resource anchors (app name, environment name, KV name/URI, firewall policy name, LAW customer ID, rule collection/rule names) |
| `02-h0-app-state-before.json` | Container app baseline surface before secret set: revision name, ingress FQDN, `configuration.secrets`, capture UTC |
| `03-h0-kv-secret-created.json` | Key Vault secret created out-of-band (versionless KV URL used by the reference) |
| `04-h0-secret-set-outcome.json` | H0 outcome: `az containerapp secret set` exit code (0), stdout, stderr, UTC boundaries |
| `05-h0-app-state-after.json` | Container app surface after successful H0 secret set: revision name unchanged, `kvref-h0` present in `configuration.secrets` |
| `06-h1-firewall-rule-removed.json` | Firewall Policy state after `az network firewall policy rule-collection-group collection remove` for `allow-entra-authority`: rule collection absent, capture UTC, controlled variable state |
| `07-h1-secret-set-outcome.json` | H1 outcome: `az containerapp secret set` exit code (non-zero), stdout, stderr (contains `Unable to get value using Managed identity` + `.well-known/openid-configuration` EOF surface), UTC boundaries |
| `08-h1-app-state.json` | Silence-gate evidence: revision name (unchanged from baseline), ingress HTTP status (200), `kvref-h1` absent from `configuration.secrets` |
| `09-h1-firewall-deny-log.json` | Firewall log query: KQL results from `AZFWApplicationRule` ∪ `AzureDiagnostics` for the H1 UTC window showing `Deny` action for `login.microsoftonline.com` from the ACA subnet source IP |
| `10-h2-firewall-rule-restored.json` | Firewall Policy state after `az network firewall policy rule-collection-group collection add-filter-collection` restoring `allow-entra-authority` with both FQDNs in one rule: rule collection present, capture UTC |
| `11-h2-secret-set-outcome.json` | H2 outcome: `az containerapp secret set` exit code (0), stdout, stderr, UTC boundaries |
| `12-h2-app-state.json` | Post-H2 evidence: revision name (still unchanged from baseline), ingress HTTP status (200), `kvref-h2` present in `configuration.secrets` |
| `13-h2-firewall-allow-log.json` | Firewall log query: KQL results from `AZFWApplicationRule` ∪ `AzureDiagnostics` for the H2 UTC window showing `Allow` action for the Entra authority FQDN |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-success-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

```bash
cd labs/aca-secret-kv-ref-mi-network-path/

# First, generate the raw cohort by running the lab against your Azure subscription:
export RG="rg-aca-secret-kv-ref-mi-network-path"
export LOCATION="koreacentral"
export BASE_NAME="acasecretmi"
az group create --name "$RG" --location "$LOCATION"
az deployment group create \
    --resource-group "$RG" --name aca-secret-kv-ref-mi-network-path \
    --template-file infra/main.bicep --parameters baseName="$BASE_NAME"
bash trigger.sh    # writes evidence/01-05 (H0 baseline)
bash falsify.sh    # writes evidence/06-13 (H1 failure + H2 recovery)

# Then re-run the verifier over the locally generated cohort as often as needed:
bash verify.sh
```

The verifier is hermetic once the raw cohort is present: `verify.sh` reads only the local files 01-13 in this directory, rewrites the four Phase B gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes. It does not call Azure — you can re-run `verify.sh` offline after `cleanup.sh` deletes the resource group, provided the local files 01-13 remain in place.
