# Evidence Pack Provenance

This directory contains the raw evidence artifacts for the `observability-tracing` lab run on **2026-06-24**. All files are PII-scrubbed (subscription/tenant GUIDs replaced with the zero-GUID placeholder, employee aliases replaced with `demouser`, employee emails replaced with `user@example.com`, long uppercase hex tokens replaced with `AAAA…A` placeholders, local user paths replaced with `/Users/demouser`).

## Capture timeline

The lab evidence was captured in a single live-Azure window on **2026-06-24** against Container App `ca-labobs-ewwmkr` (RG `rg-aca-lab-observability2`, Korea Central):

- **H1 trigger window (01:12–01:13 UTC).** `trigger.sh` resolved infrastructure (FQDN, environment, baseline `latestRevisionName`), captured the baseline state — env var `APPLICATIONINSIGHTS_CONNECTION_STRING` sourced from secretRef `appinsights-connection-string`, single healthy revision `ca-labobs-ewwmkr--0000002` (createdTime `2026-06-24T01:10:03+00:00`), 5/5 HTTP 200 client probes, single managed-env secret present — then applied the documented invalid literal value (`InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/`) via `az containerapp update --set-env-vars`, minted a new revision `ca-labobs-ewwmkr--0000003` (createdTime `2026-06-24T01:12:50+00:00`), waited 1 polling attempt (~10 s) for `provisioningState=Provisioned`, captured the post-trigger state (env var Source flipped to literal with value matching the expected invalid string, secret store entry name + value_present + keyVaultUrl + identity all unchanged, 5/5 HTTP 200 client probes — data plane unaffected), and emitted `12-h1-gate.json` (`gate_classification: telemetry_misconfiguration_env_var_source_flipped_to_literal`, all 5 sub-gates PASS).

- **H2 verify window (01:13–01:14 UTC).** `verify.sh` reloaded the trigger context from `12-h1-gate.json`, captured the pre-fix state (env var still literal — trigger persisted across the gap), ran a pre-fix 5-request curl probe (5/5 HTTP 200), applied the fix via `az containerapp update --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string`, minted a third revision `ca-labobs-ewwmkr--0000004` (createdTime `2026-06-24T01:13:43+00:00`), captured the post-fix state (env var Source restored to secretRef with value empty, secret store integrity preserved across all THREE states, 5/5 HTTP 200 post-fix client probes), and emitted `24-h2-gate.json` (`gate_classification: telemetry_configuration_restored_to_secretref_app_intact`, all 6 sub-gates PASS).

Both gates pass, supporting the lab's hypothesis: the controlling variable for telemetry export misconfiguration is the env-var Source flip (secretRef → literal) at the Container App template layer; the managed-environment secret store remains untouched throughout. The documented fix (`az containerapp update --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string`) restores secretRef sourcing AND data-plane integrity in a single revision update, with full revision progression visible through three distinct names with strictly increasing createdTime.

## Honest disclosure — telemetry-blocking is `[Not Proven]`

The baseline image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` does **NOT** ship an Application Insights SDK. Application Insights / Log Analytics will report **zero traces** in ALL THREE states (baseline / post-trigger / post-fix) because there is no SDK instrumented to emit them. The H1 and H2 gates therefore intentionally restrict their falsifiable claims to:

- **H1**: env-var Source/Value flip (directly observable from `properties.template.containers[0].env[0]`) + revision advancement + secret-store integrity + data-plane HTTP 200.
- **H2**: env-var Source/Value restoration + secret-store integrity across three states + three-distinct-revision progression with strictly increasing createdTime + data-plane HTTP 200.

The upstream hypothesis "the misconfigured env var actually drops traces in production-grade SDK-instrumented workloads" is **[Not Proven]** in this evidence pack and is documented as such in the lab guide under `## 2) Hypothesis`. A future evidence pack using an SDK-instrumented baseline image (e.g. `.NET` or `Java` app with `Microsoft.ApplicationInsights.AspNetCore`) would be required to lift the telemetry-blocking claim from `[Not Proven]` to `[Observed]`. The H1/H2 gates in this pack are passable WITHOUT that SDK because they only assert the env-var/revision/secret-store/data-plane facts that ARE observable today.

## Secret-store PII safety policy

The Container App's managed-environment secret store entry `appinsights-connection-string` contains a real Application Insights connection string with a real instrumentation key. **Logging the resolved secret value to an evidence file would be a P0 PII leak.** The `05-baseline-secrets.json`, `10-post-trigger-secrets.json`, and `19-post-fix-secrets.json` snapshots therefore redact the secret value to a placeholder string (`REDACTED_NEVER_LOG_REAL_CONNECTION_STRINGS`) and emit only `name`, `value_present` (boolean), `keyVaultUrl` (None for this lab — secrets are inline), and `identity` (None for this lab — no managed identity reference). The raw secret-store output is captured to a `-raw.json` temp file and immediately deleted by `trigger.sh` Phase 5 / Phase 10 and `verify.sh` Phase 19. The H1 sub-gate `d_secret_store_unchanged` and H2 sub-gate `d_secret_store_value_unchanged_after_fix` compare the redacted snapshots' `name + keyVaultUrl + identity + value_present` fields — they **explicitly do NOT compare the resolved value** for this PII reason.

## Container Apps single-revision-mode pruning note

The baseline revision visible to `trigger.sh` Phase 2 (`02-baseline-revisions.json`) may not be visible to `verify.sh` Phase 18 (`18-post-fix-revisions.json`). The Container Apps platform applies revision history pruning in single-revision mode, so by the time the third revision (post-fix) is created, the oldest deactivated revision (the one before this trigger.sh run started) may have been removed from the revision list. The H2 sub-gate `f_revision_progression_documented` therefore looks up `createdTime` from the snapshot taken **when each revision was the latest** — baseline from `02-baseline-revisions.json`, post-trigger from `09-post-trigger-revisions.json`, post-fix from `18-post-fix-revisions.json` — rather than relying on the post-fix snapshot to preserve all three. This is also why the lab requires running `trigger.sh` and `verify.sh` in sequence without an intervening manual revision update.

## File index

| Phase | Files | Source |
|---|---|---|
| Trigger setup | `01-infra-resolve.json`, `02-baseline-revisions.json`, `03-baseline-curl.json`, `04-baseline-env-var.json` | `trigger.sh` Phases 1–4 — infra resolve, baseline revisions, baseline 5-request curl, baseline env var snapshot |
| Trigger secret-store baseline | `05-baseline-secrets.json` | `trigger.sh` Phase 5 — redacted secret-store snapshot (raw values immediately deleted) |
| Trigger fault injection | `06-trigger-update.json` + `.stderr`, `07-wait-trigger-revision.log` | `trigger.sh` Phases 6–7 — apply invalid literal connection string, wait for new revision to provision |
| Trigger post-state | `08-post-trigger-env-var.json`, `09-post-trigger-revisions.json`, `10-post-trigger-secrets.json`, `11-curl-after-trigger.json` | `trigger.sh` Phases 8–11 — env var now literal, two revisions in list, redacted secret-store unchanged, 5-request curl (data plane unaffected) |
| H1 gate | `12-h1-gate.json` | `trigger.sh` Phase 12 — 5 sub-gates evaluated |
| Verify pre-fix | `13-pre-fix-env-var.json`, `14-curl-pre-fix.json` | `verify.sh` Phases 13–14 — re-confirm env var is still literal (trigger persisted), pre-fix 5-request curl |
| Verify fix | `15-fix-update.json` + `.stderr`, `16-wait-fix-revision.log` | `verify.sh` Phases 15–16 — apply `secretref:appinsights-connection-string` restore, wait for fix revision to provision |
| Verify post-fix | `17-post-fix-env-var.json`, `18-post-fix-revisions.json`, `19-post-fix-secrets.json`, `20-curl-post-fix.json`, `21-cli-versions.json`, `22-cli-containerapp-ext.json`, `23-region.json` | `verify.sh` Phases 17–23 — env var back to secretRef, post-fix revisions snapshot, redacted secret-store unchanged across 3 states, 5-request curl, CLI/extension/region metadata |
| H2 gate | `24-h2-gate.json` | `verify.sh` Phase 24 — 6 sub-gates evaluated |

The pack contains **24 numbered evidence prefixes** (`01-*` through `24-*`) totaling **26 physical files** when counting `.stderr` companions to `06-*` and `15-*` (2 extra files). Prefixes `07-*` and `16-*` use a `.log` extension instead of `.json`.

## Reproducibility

To reproduce this evidence pack against a fresh Azure subscription:

```bash
export AZ_SUBSCRIPTION="<your-subscription-id>"
export RG="rg-aca-lab-observability2"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION" --subscription "$AZ_SUBSCRIPTION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --template-file labs/observability-tracing/infra/main.bicep \
    --parameters baseName=labobs

export APP_NAME=$(az deployment group list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --query "[0].properties.outputs.containerAppName.value" \
    --output tsv)
export APPINSIGHTS_NAME=$(az deployment group list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --query "[0].properties.outputs.appInsightsName.value" \
    --output tsv)

bash labs/observability-tracing/trigger.sh   # emits 01-* through 12-h1-gate.json
bash labs/observability-tracing/verify.sh    # emits 13-* through 24-h2-gate.json
bash labs/observability-tracing/cleanup.sh   # async resource group delete (--no-wait)
```

Expected runtime: ~10 minutes total (~3 min Bicep deploy, ~2 min trigger, ~2 min verify, immediate cleanup queue). Estimated cost: <$0.10 USD (Consumption plan, three short-lived helloworld revisions, single Log Analytics workspace, single Application Insights component, Korea Central).

## CLI versions

The captures in this pack were produced with the CLI versions recorded in `21-cli-versions.json` and `22-cli-containerapp-ext.json`. The `az containerapp update --set-env-vars` response shape (full Container App resource with `properties.latestRevisionName` reflecting the newly minted revision) was empirically observed with this CLI version; `trigger.sh` Phase 6 and `verify.sh` Phase 15 both parse `properties.latestRevisionName` and cross-verify the new revision against the post-trigger / post-fix revisions snapshot, so a future CLI revision shape change would surface as a sub-gate `b` failure rather than a silent regression.
