---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents
        - https://learn.microsoft.com/en-us/azure/container-apps/observability
        - https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-enable
content_validation:
  status: verified
  last_reviewed: '2026-06-24'
  reviewer: ai-agent
  lab_validation:
    status: reproduced
    tested_date: 2026-06-24
    az_cli_version: 2.79.0
    notes: 'Reproduced end-to-end in rg-aca-lab-observability (koreacentral); baseline secretRef → invalid literal → secretRef restored across revisions 0m6ek7p → 0000001 → 0000002; six Portal captures attached with PII-replacement masking. Telemetry-count claim left [Not Proven] because the baseline helloworld image ships no Application Insights SDK. The three env-var anchor captures (02-baseline-secretref on revision 0m6ek7p, 03-after-trigger-literal on revision 0000001, 06-restored-secretref on revision 0000002) directly falsify the env-var-source half of the hypothesis: Source flips Reference a secret → Manual entry → Reference a secret, with the literal value exactly matching the trigger.sh invalid connection string. Second live Azure run completed 2026-06-24 with az CLI 2.79.0 (containerapp extension 1.3.0b4) against rg-aca-lab-observability2 (subscription redacted to placeholder zero-GUID, koreacentral), producing the Phase B-style evidence pack at labs/observability-tracing/evidence/ (24 numbered prefixes totaling 26 physical files including JSON, .stderr companions, and .log waits). H1 (telemetry_misconfiguration_env_var_source_flipped_to_literal) and H2 (telemetry_configuration_restored_to_secretref_app_intact) both PASS with all 11 sub-gates true. Empirical curl: 5/5 HTTP 200 across baseline, post-trigger, pre-fix, and post-fix windows (data plane unaffected by env-var Source flip). Three-distinct-revision progression triangulated via createdTime lookups from per-stage snapshots (baseline from 02-*, post-trigger from 09-*, post-fix from 18-*) because Container Apps single-revision-mode pruning removed the baseline from the post-fix revisions snapshot — the lab requires running trigger.sh and verify.sh in sequence without an intervening manual revision update. Secret-store PII safety: 05/10/19 snapshots redact the connection-string value to REDACTED_NEVER_LOG_REAL_CONNECTION_STRINGS, raw secret-store output captured to a -raw.json temp file and immediately deleted; H1 sub-gate d and H2 sub-gate d compare only name + keyVaultUrl + identity + value_present, never the resolved value. PII scrubbed: subscription/tenant GUIDs replaced with zero-GUID placeholder, customDomainVerificationId replaced with AAAA placeholder, employee email replaced with user@example.com, local user paths replaced with /Users/demouser.'
  core_claims:
    - claim: Azure Container Apps environments can send application and system logs to a Log Analytics workspace for observability.
      source: https://learn.microsoft.com/en-us/azure/container-apps/observability
      verified: true
    - claim: Application Insights uses a connection string to send telemetry to the correct monitoring resource.
      source: https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-enable
      verified: true
validation:
  az_cli:
    last_tested: '2026-06-24'
    cli_version: '2.79.0'
    result: pass
  bicep:
    last_tested: '2026-06-24'
    result: pass
---
# Observability and Distributed Tracing Lab

Troubleshoot Application Insights connectivity issues by simulating a misconfigured telemetry connection string.

## Lab Metadata

| Attribute | Value |
|---|---|
| Difficulty | Intermediate |
| Estimated Duration | 25-35 minutes |
| Tier | Consumption |
| Failure Mode | Application Insights connection string is misconfigured, so traces stop appearing |
| Skills Practiced | Telemetry configuration review, secret reference validation, Log Analytics and Application Insights verification |

## 1) Background

This lab starts with working observability: the Container Apps environment sends logs to Log Analytics, the app has `APPLICATIONINSIGHTS_CONNECTION_STRING` configured through a secret reference, and Application Insights receives telemetry. The trigger replaces that working configuration with an invalid literal connection string, causing telemetry export to fail.

The main troubleshooting pattern is to compare the app's environment variable configuration with the expected secret reference, then validate telemetry absence in Application Insights and Log Analytics.

### Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    A[Container App] --> B[APPLICATIONINSIGHTS_CONNECTION_STRING]
    B -->|Valid secretRef| C[Application Insights]
    A --> D[Container Apps Environment]
    D --> E[Log Analytics Workspace]
    D --> F[daprAIConnectionString]
    B -->|Invalid literal value| G[Telemetry dropped]
```

### Telemetry Flow in Container Apps

| Component | Role |
|---|---|
| Application Insights | Receives traces, metrics, and exceptions |
| Connection String | Identifies the Application Insights resource |
| Secret Reference | Secure way to inject the connection string |
| Dapr AI Connection | Environment-level tracing for Dapr |

## 2) Hypothesis

**IF** `APPLICATIONINSIGHTS_CONNECTION_STRING` is replaced with an invalid literal value instead of the working secret reference, **THEN** the Container App's env var source flips from "Reference a secret" to "Manual entry" with an invalid literal value (the directly-falsifiable half of the hypothesis), and **any application that emits Application Insights telemetry through this env var will stop reaching the real Application Insights resource** until the valid secret-backed configuration is restored.

!!! warning "Telemetry-blocking half is [Not Proven] with the baseline image"
    The baseline `azuredocs/containerapps-helloworld:latest` image shipped by `infra/main.bicep` does not include an Application Insights SDK. Trace counts will be zero in **both** the baseline and the misconfigured state, so a zero count in App Insights / Log Analytics does not by itself confirm causation. The env var source/value flip *is* directly falsifiable from the Container App template. To upgrade the telemetry-blocking claim from `[Not Proven]` to `[Measured]`, swap the lab image for one of the reference apps under `apps/` (for example `apps/python/`) instrumented with the OpenTelemetry Distro for Azure Monitor.

| Variable | Control State | Experimental State | Falsifiability |
|---|---|---|---|
| App env var configuration | `secretRef: appinsights-connection-string` (Source = "Reference a secret") | Invalid literal connection string (Source = "Manual entry") | `[Observable]` from the Containers → Environment variables blade |
| Application Insights telemetry from an SDK-instrumented app | New traces appear | No new traces | `[Not Proven]` with helloworld baseline; requires SDK-instrumented image |
| Log Analytics trace query | Returns recent trace count | Returns zero | `[Not Proven]` with helloworld baseline; requires SDK-instrumented image |
| `verify.sh` env-var check | PASS | FAIL | `[Observable]` from the CLI |

## 3) Runbook

### Deploy baseline infrastructure

Prerequisites:

- Azure CLI with the Container Apps extension
- Basic understanding of Application Insights concepts

```bash
az extension add --name containerapp --upgrade
az login

export RG="rg-aca-lab-observability"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --name "lab-obs" \
    --resource-group "$RG" \
    --template-file "./labs/observability-tracing/infra/main.bicep" \
    --parameters baseName="labobs"
```

| Command | Why it is used |
|---|---|
| `az extension add ...` | Installs or updates the Container Apps Azure CLI extension. |

Expected output:

- Resource group creation succeeds.
- Deployment creates a Container App, Container Apps environment, Application Insights component, and Log Analytics workspace.

### Capture deployment outputs

```bash
export APP_NAME="$(az deployment group show \
    --resource-group "$RG" \
    --name "lab-obs" \
    --query "properties.outputs.containerAppName.value" \
    --output tsv)"

export ACA_ENV_NAME="$(az deployment group show \
    --resource-group "$RG" \
    --name "lab-obs" \
    --query "properties.outputs.containerAppsEnvironmentName.value" \
    --output tsv)"

export APPINSIGHTS_NAME="$(az deployment group show \
    --resource-group "$RG" \
    --name "lab-obs" \
    --query "properties.outputs.appInsightsName.value" \
    --output tsv)"

export LOG_ANALYTICS_WORKSPACE_NAME="$(az deployment group show \
    --resource-group "$RG" \
    --name "lab-obs" \
    --query "properties.outputs.logAnalyticsWorkspaceName.value" \
    --output tsv)"
```

| Command | Purpose |
|---|---|
| `export APP_NAME="$(az deployment group show ... --query "properties.outputs.containerAppName.value" --output tsv)"` | Captures the deployed app name so the telemetry misconfiguration and recovery steps apply to the exact Container App created by the lab. |
| `export ACA_ENV_NAME="$(az deployment group show ... --query "properties.outputs.containerAppsEnvironmentName.value" --output tsv)"` | Captures the environment name for later checks against environment-level observability settings such as the Dapr AI connection string. |
| `export APPINSIGHTS_NAME="$(az deployment group show ... --query "properties.outputs.appInsightsName.value" --output tsv)"` | Captures the Application Insights component name that should receive traces, which is required before querying or restoring its connection string. |
| `export LOG_ANALYTICS_WORKSPACE_NAME="$(az deployment group show ... --query "properties.outputs.logAnalyticsWorkspaceName.value" --output tsv)"` | Captures the Log Analytics workspace name so later KQL checks query the exact workspace wired into the lab deployment. |

Expected output:

- Commands return no console output.
- Variables resolve to the app, environment, Application Insights, and workspace names.

### Verify baseline observability

```bash
az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING']" \
    --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp show ...` | Reads the Container App configuration so the documented setting can be verified. |

Expected output:

- The app shows `secretRef: appinsights-connection-string` for `APPLICATIONINSIGHTS_CONNECTION_STRING`.

### Trigger the failure

```bash
./labs/observability-tracing/trigger.sh
```

The trigger applies this misconfiguration:

```bash
az containerapp update \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/"
```

| Command | Why it is used |
|---|---|
| `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

Expected output:

- The script prints that telemetry settings were misconfigured.
- The Container App now uses an invalid literal connection string.

### Observe the broken state

```bash
az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING']" \
    --output json

APPINSIGHTS_ID="$(az monitor app-insights component show \
    --app "$APPINSIGHTS_NAME" \
    --resource-group "$RG" \
    --query "appId" \
    --output tsv)"

az monitor app-insights query \
    --app "$APPINSIGHTS_ID" \
    --analytics-query "requests | where timestamp > ago(5m) | count"
```

| Command | Why it is used |
|---|---|
| `az containerapp show ...` | Reads the Container App configuration so the documented setting can be verified. |

Expected output:

- The env var now shows a literal invalid value instead of a secret reference.
- Recent Application Insights queries are empty or stale **when the application image is SDK-instrumented**. With the baseline `azuredocs/containerapps-helloworld:latest` image, App Insights queries will also be empty in the baseline state (see the `[Not Proven]` caveat in the Hypothesis).

### Diagnose with additional evidence and restore the valid configuration

Useful debugging commands:

```bash
az containerapp env show --name "$ACA_ENV_NAME" --resource-group "$RG" --query "properties.daprAIConnectionString"
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console --tail 50

WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RG" \
    --workspace-name "$LOG_ANALYTICS_WORKSPACE_NAME" \
    --query customerId \
    --output tsv)

az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "union isfuzzy=true AppTraces, traces | where TimeGenerated > ago(15m) | summarize count()"
```

| Command | Why it is used |
|---|---|
| `az containerapp env show ...` | Reads managed environment settings for networking, logging, or workload profile verification. |

Restore the valid connection string using the original secret reference:

```bash
APPINSIGHTS_CONNECTION_STRING="$(az monitor app-insights component show \
    --app "$APPINSIGHTS_NAME" \
    --resource-group "$RG" \
    --query "connectionString" \
    --output tsv)"

az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string"
```

| Command | Purpose |
|---|---|
| `az containerapp update --name "$APP_NAME" --resource-group "$RG" --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string"` | Updates runtime environment mappings, which is the corrective action this step is validating or applying. |

Expected output:

- The environment-level `daprAIConnectionString` remains configured.
- The app env var returns to the secret reference.
- Telemetry resumes after the new revision is applied **when the application image is SDK-instrumented** (see the `[Not Proven]` caveat in the Hypothesis).

### Verify recovery

```bash
./labs/observability-tracing/verify.sh
```

Expected output (with the baseline `azuredocs/containerapps-helloworld:latest` image):

- `PASS: Application Insights connection string is configured on $APP_NAME.` — this row is directly falsifiable from the Container App template and corresponds to the env-var half of the hypothesis.
- The trace-record check is conditional: `PASS: Found <count> trace record(s) in Log Analytics.` is expected **only when the application image is SDK-instrumented**. With the baseline helloworld image (no Application Insights SDK), the trace count is zero in both the baseline and the misconfigured state, so this row may report zero records and the script may not reach `PASS` on it — see the `[Not Proven]` caveat in the Hypothesis.
- `Verification complete.`

## 4) Experiment Log

| Step | Action | Expected | Actual | Pass/Fail |
|---|---|---|---|---|
| 1 | Deploy baseline infrastructure | Observability resources deploy successfully | | |
| 2 | Verify baseline env var | `APPLICATIONINSIGHTS_CONNECTION_STRING` uses secret reference | | |
| 3 | Run `trigger.sh` | Invalid literal connection string applied | | |
| 4 | Query current env config | Secret reference replaced by literal value | | |
| 5 | Check Application Insights or Log Analytics | Recent traces are missing or stale **(SDK-instrumented image only; `[Not Proven]` with helloworld baseline)** | | |
| 6 | Restore secret-backed configuration | App update succeeds | | |
| 7 | Run `verify.sh` | Connection-string check passes; trace-record check is **SDK-instrumented image only** (see `[Not Proven]` caveat in the Hypothesis) | | |

## Expected Evidence

!!! info "Telemetry rows are conditional on an SDK-instrumented image"
    With the baseline `azuredocs/containerapps-helloworld:latest` image, the App Insights / Log Analytics "trace" rows in the tables below are `[Not Proven]` (a zero count would also occur in the baseline state). Only the **Container env vars** and **`verify.sh` env-var check** rows are directly falsifiable from this lab as-is.

### Before trigger

| Evidence Source | Expected State |
|---|---|
| Container env vars | `APPLICATIONINSIGHTS_CONNECTION_STRING` uses `secretRef` |
| Environment config | `daprAIConnectionString` is set |
| Application Insights or Log Analytics (SDK-instrumented image only) | Recent traces are present |

### During incident

| Evidence Source | Expected State |
|---|---|
| Container env vars | Invalid literal connection string |
| Application Insights query (SDK-instrumented image only) | No new traces or only stale results |
| Console logs | Possible telemetry export errors |
| `./labs/observability-tracing/verify.sh` | FAIL |

### After fix

| Evidence Source | Expected State |
|---|---|
| Container env vars | `APPLICATIONINSIGHTS_CONNECTION_STRING` restored to `secretRef` |
| Log Analytics query (SDK-instrumented image only) | Recent traces return |
| `./labs/observability-tracing/verify.sh` | Connection-string check PASS; trace-record check PASS **only when the application image is SDK-instrumented** (with the baseline `azuredocs/containerapps-helloworld:latest` image this row reports zero traces — see `[Not Proven]` caveat in the Hypothesis) |

### Observed Evidence (Live Azure Reproduction — 2026-06-03)

Reproduced end-to-end in `koreacentral` against resource group `rg-aca-lab-observability` using Azure CLI `2.71.0`. The Container App revisions advanced as follows:

| Revision | State | Source of `APPLICATIONINSIGHTS_CONNECTION_STRING` |
|---|---|---|
| `ca-labobs-622oal--0m6ek7p` | Baseline (active) | `secretRef: appinsights-connection-string` |
| `ca-labobs-622oal--0000001` | After `trigger.sh` (active) | Literal value `InstrumentationKey=...;IngestionEndpoint=https://invalid/` |
| `ca-labobs-622oal--0000002` | After restore (active) | `secretRef: appinsights-connection-string` |

CLI evidence (with PII redacted to placeholder GUIDs and lab-owned resource names):

```text
# Baseline — secret-backed configuration
az containerapp show --name ca-labobs-622oal --resource-group rg-aca-lab-observability \
  --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING']"
→ [{ "name": "APPLICATIONINSIGHTS_CONNECTION_STRING",
     "secretRef": "appinsights-connection-string" }]

# After ./labs/observability-tracing/trigger.sh — literal invalid string applied
az containerapp show --name ca-labobs-622oal --resource-group rg-aca-lab-observability \
  --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING']"
→ [{ "name": "APPLICATIONINSIGHTS_CONNECTION_STRING",
     "value": "InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/" }]

# After restore — secretRef back in place on revision 0000002
az containerapp update --name ca-labobs-622oal --resource-group rg-aca-lab-observability \
  --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string"
→ [{ "name": "APPLICATIONINSIGHTS_CONNECTION_STRING",
     "secretRef": "appinsights-connection-string" }]
```

| Command | Why it is used |
|---|---|
| `az containerapp show ... --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING']"` | Reads the current Container App template and returns just the `APPLICATIONINSIGHTS_CONNECTION_STRING` env var entry, so the reviewer can confirm whether the value is sourced from a `secretRef` (control state) or a literal `value` (experimental state). |
| `az containerapp update ... --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string"` | Restores the env var to its baseline secret-backed configuration. `--set-env-vars` performs an in-place update of the Container App template and triggers a new revision. |

Each Portal capture below documents one observable fact. `[Observed]` paragraphs cite only what is visible in the screenshot at capture time. `[Inferred]` paragraphs connect the captures across revisions to support or falsify the hypothesis.

#### Capture 1 — Container App Overview

`[Observed]` The Overview blade for `ca-labobs-622oal` shows the Essentials panel with `Status: Running`, `Location: Korea Central`, `Environment type: Workload profiles`, an `Application Url` link pointing to `https://ca-labobs-622oal.jollytree-c58df5c9.koreacentral.azurecontaine...`, and Tags `lab: observability-tracing` and `cloud: AzureCloud` at capture time.

![Container App Overview blade for ca-labobs-622oal](../../assets/troubleshooting/observability-tracing/01-overview.png)

`[Inferred]` A `Status: Running` overview at this moment is consistent with the app being deployed and provisioned. It does not on its own prove the app is currently serving requests, nor that telemetry is or is not being emitted — those facts must come from the env var blade (Captures 2, 3, 6) and the App Insights blades (Captures 4, 5).

#### Capture 2 — Baseline environment variables (secret-backed)

`[Observed]` The Containers → Environment variables tab, with the "Based on revision" selector at the top of the blade reading `ca-labobs-622oal--0m6ek7p`, shows a row for `APPLICATIONINSIGHTS_CONNECTION_STRING` with **Source = "Reference a secret"** and **Value = "appinsights-connection-stri..."** (truncated by the table cell).

![Baseline env vars — secretRef on revision 0m6ek7p](../../assets/troubleshooting/observability-tracing/02-env-vars-baseline-secretref.png)

`[Inferred]` This matches the documented control state: the connection string is injected from the secret store, so the runtime resolves it to the real Application Insights connection string at container start.

#### Capture 3 — Misconfigured environment variables (literal invalid value)

`[Observed]` The same Containers → Environment variables tab, with the "Based on revision" selector now reading `ca-labobs-622oal--0000001`, shows the same `APPLICATIONINSIGHTS_CONNECTION_STRING` row with **Source = "Manual entry"** and the Value textarea showing the literal string `InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint` (the rest of the literal value is clipped by the textarea at capture time and is not legible in the screenshot). A second row, `OTEL_SERVICE_NAME`, also shows **Source = "Manual entry"** with **Value = "ca-labobs-622oal"**.

![Misconfigured env vars — literal value on revision 0000001](../../assets/troubleshooting/observability-tracing/03-env-vars-after-trigger-literal.png)

`[Inferred]` Comparing this capture to Capture 2 falsifies any claim that the secret store was modified: only the env var's *Source* changed from "Reference a secret" to "Manual entry", on a different revision ID. The misconfiguration is at the Container App template layer, not the Container Apps environment secret layer.

#### Capture 4 — Application Insights Transaction search blade (no executed result)

`[Observed]` The Transaction search blade for the lab's Application Insights resource (`appi-labobs-622oal`) shows the filter chips `Local Time: Last 24 hours (Automatic)`, `View as: Traces`, and `Event types = All selected`; an empty search input placeholder reading "Place search terms here, e.g. a trace ID or log text (optional)"; and a blue prompt button labeled "See all data in the last 24 hours" with the text "or" / "Visit our syntax query help page to get started" below it. No results table has been rendered at capture time.

![Application Insights Transaction search — no executed result](../../assets/troubleshooting/observability-tracing/04-appinsights-transaction-search.png)

`[Inferred]` Because no search has been executed, this capture documents only the *configured filters* (last 24 hours, Traces view) on the right Application Insights resource. It is consistent with — but does not by itself prove — telemetry absence; the executed `traces | count` measurement in Capture 5 is the stronger evidence, and the `[Not Proven]` caveat below still applies.

#### Capture 5 — Logs blade KQL `traces | count` returns 0

`[Observed]` On the Logs blade for `appi-labobs-622oal`, the query editor shows two lines (`traces` on line 1 and `| count` on line 2), the toolbar shows `Time range: Last hour` and `Show: 500000 results`, the Results tab shows a single column with header `Count` and one row containing the value `0`, the footer reads `0s 881ms` execution time and `1 - 1 of 1`.

![App Insights Logs blade — traces count is 0](../../assets/troubleshooting/observability-tracing/05-appinsights-logs-traces-count-zero.png)

`[Inferred]` The zero count is consistent with telemetry export failing, but as noted in the Hypothesis caveat and Capture 4, the helloworld baseline image's lack of an Application Insights SDK means a zero count would also be observed in the baseline. This capture documents the measurable state during the incident; it does not by itself prove the connection-string change is responsible.

#### Capture 6 — Restored environment variables (secret-backed)

`[Observed]` The Containers → Environment variables tab, with the "Based on revision" selector now reading `ca-labobs-622oal--0000002`, shows the `APPLICATIONINSIGHTS_CONNECTION_STRING` row with **Source = "Reference a secret"** and **Value = "appinsights-connection-stri..."**. A secondary `OTEL_SERVICE_NAME` row is also visible with **Source = "Manual entry"** and **Value = "ca-labobs-622oal"**.

![Restored env vars — secretRef on revision 0000002](../../assets/troubleshooting/observability-tracing/06-env-vars-restored-secretref.png)

`[Inferred]` Captures 2 and 6 together (both showing the same Source / Value for the same env var name, on different revision IDs) falsify any claim that the misconfiguration is still in place. The misconfiguration was bounded to revision `0000001` and is no longer present on the active revision `0000002`.

#### Falsification summary

- `[Inferred]` Three distinct revision IDs are visible across the env-var captures: `0m6ek7p` in Capture 2, `0000001` in Capture 3, `0000002` in Capture 6. Each capture's `[Observed]` paragraph cites the revision selector value plus the Source / Value for `APPLICATIONINSIGHTS_CONNECTION_STRING` at capture time.
- `[Inferred]` The `Reference a secret` ↔ `Manual entry` flip on the same env var name across those three captures, bounded by `trigger.sh` and the restore command, is sufficient to confirm the *configuration-change* half of the hypothesis: the trigger does replace the working secret reference with an invalid literal, and the restore returns it to the baseline.
- `[Not Proven]` The telemetry-blocking half of the hypothesis (that the invalid connection string would actually drop traces *that the SDK is emitting*) cannot be empirically falsified by this reproduction, because the baseline `azuredocs/containerapps-helloworld:latest` image used by `infra/main.bicep` does not ship an Application Insights SDK. Captures 4 and 5 are therefore consistent with the hypothesis but not a smoking gun. To upgrade this to `[Measured]`, swap the lab image for one of the reference apps under `apps/` (e.g. `apps/python/`) instrumented with the OpenTelemetry Distro for Azure Monitor.

Environment: `koreacentral`, `rg-aca-lab-observability`, `cae-labobs-622oal`, `appi-labobs-622oal`, `log-labobs-622oal`.

### Observed Evidence (Live Azure Test — 2026-06-24)

A second end-to-end live Azure run executed on **2026-06-24** with `az` CLI version **2.79.0** (containerapp extension **1.3.0b4**; see `labs/observability-tracing/evidence/21-cli-versions.json` and `22-cli-containerapp-ext.json`) against resource group `rg-aca-lab-observability2` (subscription redacted to placeholder `00000000-0000-0000-0000-000000000000`, Korea Central). The run produced 24 numbered evidence prefixes (`01-*` through `24-*`, totaling 26 physical files when counting `.stderr` companions to `06-*` and `15-*`; prefixes `07-*` and `16-*` use a `.log` extension) under `labs/observability-tracing/evidence/`, covering H1 (telemetry-misconfiguration env-var Source flip) and H2 (env-var restoration with revision progression). All 11 sub-gates across both hypotheses passed.

**H1 reproduction** — `evidence/12-h1-gate.json`:

| Sub-gate | Value | Source |
|---|---|---|
| `a_baseline_env_was_secretref` | true | `evidence/04-baseline-env-var.json` `secretRef="appinsights-connection-string"` (no literal `value` key); `evidence/12-h1-gate.json` `env_var_state.baseline_secretRef="appinsights-connection-string"` and `baseline_value=null` |
| `b_trigger_succeeded_and_revision_advanced` | true | `evidence/06-trigger-update.json` `properties.latestRevisionName="ca-labobs-ewwmkr--0000003"` (new revision minted by `az containerapp update --set-env-vars`); `evidence/12-h1-gate.json` `trigger_window.baseline_revision_name="ca-labobs-ewwmkr--0000002"` vs `post_trigger_revision_name="ca-labobs-ewwmkr--0000003"` (distinct names), `trigger_cli_exit_code=0`, `wait_provisioned=true` |
| `c_env_var_now_literal_with_expected_value` | true | **Strong path:** `evidence/08-post-trigger-env-var.json` `value="InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/"` exactly matches `evidence/12-h1-gate.json` `trigger_window.expected_literal_value`. **Fallback path (also satisfied):** `evidence/12-h1-gate.json` `env_var_state.post_trigger_value` is non-empty AND `post_trigger_secretRef=null` |
| `d_secret_store_unchanged` | true | `evidence/05-baseline-secrets.json` and `evidence/10-post-trigger-secrets.json` both report `secrets_count=1` with identical `name="appinsights-connection-string"`, `keyVaultUrl=null`, `identity=null`, `value_present=false`; `evidence/12-h1-gate.json` `secret_store_integrity.comparison_excludes_resolved_value_for_pii_safety=true` (see honest disclosure below for the PII-safety reason this comparison excludes the resolved value) |
| `e_app_continues_serving_requests` | true | `evidence/03-baseline-curl.json` and `evidence/11-curl-after-trigger.json` both report `success_count_200=5` out of 5 attempts (`timeout_count_000=0`); data plane unaffected by the env-var Source flip |

Gate classification: `telemetry_misconfiguration_env_var_source_flipped_to_literal`.

**H2 restoration** — `evidence/24-h2-gate.json`:

| Sub-gate | Value | Source |
|---|---|---|
| `a_pre_fix_env_var_still_literal` | true | `evidence/13-pre-fix-env-var.json` `value="InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/"` confirms the trigger persisted across the gap between scripts; `evidence/24-h2-gate.json` `env_var_state.pre_fix_matches_expected_literal=true` |
| `b_fix_command_succeeded_and_revision_advanced` | true | `evidence/15-fix-update.json` `properties.latestRevisionName="ca-labobs-ewwmkr--0000004"` (third distinct revision name in this run); `evidence/24-h2-gate.json` `fix_window.fix_cli_exit_code=0`, `wait_provisioned=true` |
| `c_env_var_back_to_secretref` | true | **Strong path:** `evidence/17-post-fix-env-var.json` `secretRef="appinsights-connection-string"` exactly matches `evidence/24-h2-gate.json` `fix_window.expected_secret_name`. **Fallback path (also satisfied):** `evidence/24-h2-gate.json` `env_var_state.post_fix_secretRef` is non-empty AND `post_fix_value=null` |
| `d_secret_store_value_unchanged_after_fix` | true | `evidence/05-baseline-secrets.json`, `evidence/10-post-trigger-secrets.json`, and `evidence/19-post-fix-secrets.json` all report identical `name="appinsights-connection-string"`, `keyVaultUrl=null`, `identity=null`, `value_present=false`; `evidence/24-h2-gate.json` `secret_store_integrity_across_three_states.comparison_excludes_resolved_value_for_pii_safety=true` |
| `e_app_continues_serving_requests_post_fix` | true | `evidence/14-curl-pre-fix.json` and `evidence/20-curl-post-fix.json` both report `success_count_200=5` out of 5 attempts (`timeout_count_000=0`) |
| `f_revision_progression_documented` | true | `evidence/24-h2-gate.json` `revision_progression.three_distinct_names=true` (`ca-labobs-ewwmkr--0000002` → `--0000003` → `--0000004`) AND `createdTime_strictly_increasing=true` (`2026-06-24T01:10:03+00:00` → `T01:12:50+00:00` → `T01:13:43+00:00`). The three `createdTime` values are looked up from the snapshot taken **when each revision was the latest** — baseline from `evidence/02-baseline-revisions.json`, post-trigger from `evidence/09-post-trigger-revisions.json`, post-fix from `evidence/18-post-fix-revisions.json` — because Container Apps single-revision-mode pruning removed the baseline from the post-fix snapshot (see honest disclosure below) |

Gate classification: `telemetry_configuration_restored_to_secretref_app_intact`. The fix command was `az containerapp update --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string` — a Container App template edit that mints a new revision.

#### Honest disclosure of platform behavior

Three platform-behavior observations from this run worth flagging to future maintainers:

1. **Telemetry-blocking is `[Not Proven]` with the helloworld baseline image.** The H1 and H2 gates intentionally restrict their falsifiable claims to the env-var Source/Value flip + revision progression + secret-store integrity + data-plane HTTP 200, all observable from the Container App template and revision list. The upstream claim "the misconfigured connection string actually drops SDK-emitted traces" remains `[Not Proven]` in this evidence pack because `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` ships no Application Insights SDK — App Insights / Log Analytics will report zero traces in ALL THREE states (baseline / post-trigger / post-fix) and a zero count is therefore consistent with both the hypothesis and the null hypothesis. A future evidence pack would need an SDK-instrumented baseline image (e.g. `apps/python/` with `azure-monitor-opentelemetry`, or a `.NET` app with `Microsoft.ApplicationInsights.AspNetCore`) to lift this claim to `[Observed]`. The original 2026-06-03 reproduction recorded the same `[Not Proven]` caveat under the Hypothesis section above; this 2026-06-24 run preserves the same caveat.

2. **Container Apps single-revision-mode revision history pruning.** The post-fix revisions snapshot (`evidence/18-post-fix-revisions.json`) lists only `ca-labobs-ewwmkr--0000003` and `--0000004`; the baseline `--0000002` has been pruned from the revision list by the time the third revision is created. The H2 sub-gate `f_revision_progression_documented` therefore looks up each revision's `createdTime` from the snapshot taken **when that revision was the latest** — baseline from `evidence/02-baseline-revisions.json`, post-trigger from `evidence/09-post-trigger-revisions.json`, post-fix from `evidence/18-post-fix-revisions.json` — rather than relying on a single post-fix snapshot. This is why the lab requires running `trigger.sh` and `verify.sh` in sequence without an intervening manual revision update; a future maintainer changing the cadence must preserve this snapshot-lookup-per-revision pattern, otherwise `verify.sh` `lookup_created_time` will return `None` for the pruned baseline and the sub-gate will fail (`createdTime_strictly_increasing=false`) rather than passing with stale data.

3. **Secret-store PII safety.** The managed-environment secret store entry `appinsights-connection-string` contains a real Application Insights connection string with a real instrumentation key. Logging the resolved value to an evidence file would be a P0 PII leak. The `05-*`, `10-*`, and `19-*` snapshots redact the secret value to `REDACTED_NEVER_LOG_REAL_CONNECTION_STRINGS` and emit only `name`, `value_present` (boolean), `keyVaultUrl` (None for this lab — secrets are inline, not Key Vault references), and `identity` (None for this lab — no managed identity reference). The raw secret-store output is captured to a `-raw.json` temp file and immediately deleted by `trigger.sh` Phase 5 / Phase 10 and `verify.sh` Phase 19. The H1 sub-gate `d_secret_store_unchanged` and H2 sub-gate `d_secret_store_value_unchanged_after_fix` compare the redacted snapshots' `name + keyVaultUrl + identity + value_present` fields — they **explicitly do NOT compare the resolved value**.

#### Evidence provenance note

All 26 physical files (24 numbered prefixes) come from a single coherent 2026-06-24 01:12–01:14 UTC run against `rg-aca-lab-observability2` (Korea Central). The full provenance map, capture timeline, PII-safety policy, and reproducibility instructions are in [`labs/observability-tracing/evidence/README.md`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/labs/observability-tracing/evidence/README.md).

#### Operator caveat

The H1 sub-gate `c_env_var_now_literal_with_expected_value` hard-codes the expected literal value `InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/` (set by `trigger.sh` as `EXPECTED_LITERAL_VALUE`). The H1 sub-gate `a_baseline_env_was_secretref`, the H2 sub-gate `c_env_var_back_to_secretref`, and the secret-store integrity sub-gates hard-code the expected secret name `appinsights-connection-string` (set by `trigger.sh` as `EXPECTED_SECRET_NAME`, and emitted by `infra/main.bicep` as the secret name in the Container App resource). If a future maintainer changes any of these constants in `trigger.sh` or `infra/main.bicep`, the corresponding gate string matches must be updated in lockstep across both `trigger.sh` and `verify.sh`.

## Clean Up

```bash
az group delete --name "$RG" --yes --no-wait
```

| Command | Why it is used |
|---|---|
| `az group delete ...` | Removes the lab resource group and its contained resources. |

## Related Playbook

- [Secret and Key Vault Reference Failure](../playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)

## See Also

- [Monitoring Operations](../../operations/monitoring/index.md)
- [KQL Query Catalog](../kql/index.md)

## Sources

- [Application Insights for Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents)
- [Observability in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/observability)
- [Enable Azure Monitor OpenTelemetry](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-enable)
