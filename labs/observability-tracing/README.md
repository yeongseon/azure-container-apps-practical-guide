# Lab: Observability / Tracing Misconfiguration

Reproducible lab demonstrating that the controlling variable for an Application Insights telemetry-export misconfiguration is the **env-var Source flip** (`secretRef` → literal) at the Container App template layer, and that restoring `secretref:` sourcing repairs the configuration in a single revision update while the managed-environment secret store stays untouched throughout.

The lab deploys one Container App with `APPLICATIONINSIGHTS_CONNECTION_STRING` sourced from the managed-environment secret `appinsights-connection-string`, flips that env var to an invalid literal value via `az containerapp update --set-env-vars`, then restores `secretref:` sourcing and proves the app data plane was never affected. Two hypotheses are tested:

1. **H1 — Trigger flips the env-var source.** Applying the invalid literal changes the env var's Source from `secretRef` to a literal value, mints a new revision, leaves the secret store unchanged, and keeps the data plane serving HTTP 200.
2. **H2 — Fix restores the source.** Applying `--set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string` restores `secretRef` sourcing, preserves secret-store integrity across all three states, advances through three distinct revision names with strictly increasing `createdTime`, and keeps the data plane at HTTP 200.

> **Honest scope — telemetry-blocking is `[Not Proven]`.** The baseline image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` ships **no** Application Insights SDK, so Application Insights reports zero traces in all three states (baseline / post-trigger / post-fix) regardless of the env var. The H1/H2 gates therefore assert only the env-var Source/Value, revision progression, secret-store integrity, and data-plane HTTP 200 facts that are directly observable today. Proving that the misconfigured env var actually drops traces would require an SDK-instrumented baseline image. See [`evidence/README.md`](evidence/README.md) for the full disclosure.

## Structure

```text
labs/observability-tracing/
├── infra/main.bicep     # Log Analytics + App Insights + Container Apps env + 1 app (secretRef-sourced connection string)
├── trigger.sh           # H1 — resolve infra, capture baseline, apply invalid literal, capture post-trigger, emit 12-h1-gate.json
├── verify.sh            # H2 — re-confirm literal, apply secretref restore, capture post-fix, emit 24-h2-gate.json
├── cleanup.sh           # Async resource group delete (--no-wait)
└── evidence/            # Captured CLI evidence (24 numbered prefixes; see evidence/README.md)
```

## Quick Start

The trigger and verify scripts require `AZ_SUBSCRIPTION`, `RG`, `APP_NAME`, and `APPINSIGHTS_NAME` in the environment; the last two come from the Bicep deployment outputs.

```bash
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-observability2"
export LOCATION="koreacentral"

az group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --location "$LOCATION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --template-file labs/observability-tracing/infra/main.bicep \
    --parameters baseName=labobs

export APP_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.containerAppName.value" \
    --output tsv)
export APPINSIGHTS_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.appInsightsName.value" \
    --output tsv)

bash labs/observability-tracing/trigger.sh   # H1 — emits 01-* through 12-h1-gate.json
bash labs/observability-tracing/verify.sh    # H2 — emits 13-* through 24-h2-gate.json
bash labs/observability-tracing/cleanup.sh   # async resource group delete
```

Run `trigger.sh` and `verify.sh` in sequence without an intervening manual revision update — the H2 gate reconstructs the three-revision progression from snapshots taken when each revision was the latest, because Container Apps prunes deactivated revisions in single-revision mode.

## Evidence summary

The committed evidence pack was captured on **2026-06-24** against Container App `ca-labobs-ewwmkr` (RG `rg-aca-lab-observability2`, Korea Central):

- **H1** flipped the env var to the invalid literal `InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/`, minted revision `--0000003`, and confirmed 5/5 HTTP 200 client probes with the secret store unchanged. All 5 sub-gates PASS.
- **H2** restored `secretref:` sourcing, minted revision `--0000004`, and confirmed secret-store integrity across all three states plus 5/5 HTTP 200 probes. All 6 sub-gates PASS.

Secret-store snapshots redact the resolved connection string value (a real instrumentation key would be a P0 PII leak); the gates compare only `name`, `value_present`, `keyVaultUrl`, and `identity`. See [`evidence/README.md`](evidence/README.md) for the full file index, PII policy, and CLI versions.

## Cost and cleanup

Expected runtime ~10 minutes; estimated cost <$0.10 USD (Consumption plan, three short-lived helloworld revisions, one Log Analytics workspace, one Application Insights component, Korea Central). Run `cleanup.sh` immediately after capturing evidence.

## Related Playbook

- Lab guide: [Observability / Tracing Misconfiguration](../../docs/troubleshooting/lab-guides/observability-tracing.md)

## See Also

- [`evidence/README.md`](evidence/README.md) — evidence pack provenance, capture timeline, and honest-disclosure notes.
