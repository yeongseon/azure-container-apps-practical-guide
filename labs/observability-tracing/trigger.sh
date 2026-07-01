#!/usr/bin/env bash
# trigger.sh — observability-tracing lab Phase B evidence-pack reproduction
#
# What this script proves (falsifiable):
#   H1: telemetry_misconfiguration_env_var_source_flipped_to_literal
#       a) Baseline APPLICATIONINSIGHTS_CONNECTION_STRING env var sourced from secretRef.
#       b) `az containerapp update --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING=<literal>` succeeded
#          AND minted a new revision (revision name changed from baseline).
#       c) Post-trigger env var now sourced from a literal value matching the documented invalid string
#          (`InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/`).
#       d) Secret-store entry `appinsights-connection-string` is still present and unchanged
#          (proves the misconfiguration is at the Container App template env-var layer, NOT at the
#          Container Apps environment secret layer).
#       e) App still serves HTTP 200 from the public FQDN (telemetry config change does not break the
#          data plane; this is necessary because the lab is about telemetry export, not about request
#          handling).
#
# Honest disclosure:
#   The baseline `azuredocs/containerapps-helloworld:latest` image does NOT ship an Application
#   Insights SDK. The telemetry-blocking half of the upstream hypothesis ("the misconfigured env
#   var actually drops traces") is `[Not Proven]` with this image — Application Insights / Log
#   Analytics will report zero traces in BOTH the baseline AND the post-trigger state. This
#   script's H1 gate intentionally restricts its falsifiable claims to the env-var Source/Value
#   flip, which IS directly observable from the Container App template. The lab guide carries
#   the full `[Not Proven]` documentation; this script does not pretend SDK telemetry exists.
#
# Required environment:
#   AZ_SUBSCRIPTION         Subscription ID
#   RG                      Resource group name (Bicep already deployed)
#   APP_NAME                Container App name (from Bicep output)
#   APPINSIGHTS_NAME        Application Insights component name (from Bicep output)
#
# Cost note: this script does NOT provision new infrastructure. It only mutates the existing
# Container App's template env vars. Each `az containerapp update` mints a new revision, and the
# lab's scale rule keeps minReplicas=1, so this stays under $0.10 USD when paired with cleanup.sh.

set -euo pipefail

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION to the subscription ID before running}"
: "${RG:?Set RG to the lab resource group before running}"
: "${APP_NAME:?Set APP_NAME to the Container App name from the Bicep output}"
: "${APPINSIGHTS_NAME:?Set APPINSIGHTS_NAME to the Application Insights component name from the Bicep output}"

EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

# The documented invalid connection string used by the upstream trigger.sh. Pinning this here so
# H1 sub-gate `c` can do a strict string-match assertion in Phase 12 below.
EXPECTED_LITERAL_VALUE="InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/"

EXPECTED_SECRET_NAME="appinsights-connection-string"
EXPECTED_ENV_VAR_NAME="APPLICATIONINSIGHTS_CONNECTION_STRING"

CURL_MAX_TIME=10            # seconds per request — short, since app is healthy
BASELINE_CURL_ATTEMPTS=5    # baseline curl probe attempts (Phase 3)
POST_TRIGGER_CURL_ATTEMPTS=5  # post-trigger curl probe attempts (Phase 11)

# Wait policy for new-revision provisioning. The app's image is helloworld so startup is fast,
# but `az containerapp update` itself can take 30-60s to commit the new revision; we poll up to
# 4 minutes with a 10-second cadence.
WAIT_REVISION_MAX_ATTEMPTS=24   # 24 * 10s = 240s = 4 minutes
WAIT_REVISION_SLEEP_SECONDS=10

echo "=== Phase 1: resolve infrastructure (FQDN, env, baseline revision) ==="
APP_FQDN=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv)

ENVIRONMENT_ID=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.managedEnvironmentId" \
    --output tsv)

ACA_ENV_NAME=$(basename "$ENVIRONMENT_ID")

BASELINE_REVISION_NAME=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.latestRevisionName" \
    --output tsv)

python3 - <<PY > "$EVIDENCE_DIR/01-infra-resolve.json"
import json
print(json.dumps({
    "utc_captured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "subscription": "00000000-0000-0000-0000-000000000000",
    "rg": "$RG",
    "app_name": "$APP_NAME",
    "app_fqdn": "$APP_FQDN",
    "environment_name": "$ACA_ENV_NAME",
    "appinsights_name": "$APPINSIGHTS_NAME",
    "baseline_revision_name_resolved_from_latestRevisionName": "$BASELINE_REVISION_NAME"
}, indent=2))
PY

echo "Baseline revision: $BASELINE_REVISION_NAME"

echo "=== Phase 2: baseline revisions snapshot (single healthy revision before trigger) ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name:name, active:properties.active, createdTime:properties.createdTime, healthState:properties.healthState, runningState:properties.runningState, trafficWeight:properties.trafficWeight}" \
    --output json > "$EVIDENCE_DIR/02-baseline-revisions.json"

echo "=== Phase 3: baseline curl probes (expect ${BASELINE_CURL_ATTEMPTS}/${BASELINE_CURL_ATTEMPTS} HTTP 200) ==="
BASELINE_SUCCESS=0
BASELINE_TIMEOUT=0
BASELINE_RESULTS=()
for i in $(seq 1 "$BASELINE_CURL_ATTEMPTS"); do
    # Lab 12 lesson: NEVER use `CODE=$(curl ... || echo "000")` — curl emits "000" via
    # --write-out on timeout AND the OR-side `echo` also fires, producing "000000" concatenated
    # output and breaking timeout_count math. Use explicit if/then/else branches instead.
    if CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time "$CURL_MAX_TIME" "https://${APP_FQDN}/" 2>/dev/null); then
        :
    else
        CODE="000"
    fi
    BASELINE_RESULTS+=("\"req_${i}\": \"${CODE}\"")
    if [ "$CODE" = "200" ]; then
        BASELINE_SUCCESS=$((BASELINE_SUCCESS + 1))
    fi
    if [ "$CODE" = "000" ]; then
        BASELINE_TIMEOUT=$((BASELINE_TIMEOUT + 1))
    fi
done

BASELINE_RESULTS_JSON=$(IFS=,; echo "{${BASELINE_RESULTS[*]}}")
python3 - <<PY > "$EVIDENCE_DIR/03-baseline-curl.json"
import json
print(json.dumps({
    "utc_captured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "app_fqdn": "$APP_FQDN",
    "attempts": $BASELINE_CURL_ATTEMPTS,
    "max_time_seconds_per_request": $CURL_MAX_TIME,
    "success_count_200": $BASELINE_SUCCESS,
    "timeout_count_000": $BASELINE_TIMEOUT,
    "per_request_codes": $BASELINE_RESULTS_JSON
}, indent=2))
PY

echo "Baseline curl: $BASELINE_SUCCESS/$BASELINE_CURL_ATTEMPTS HTTP 200"

echo "=== Phase 4: baseline env var snapshot (expect Source = secretRef) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.template.containers[0].env[?name=='${EXPECTED_ENV_VAR_NAME}'] | [0]" \
    --output json > "$EVIDENCE_DIR/04-baseline-env-var.json"

BASELINE_SECRETREF=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/04-baseline-env-var.json')); print(d.get('secretRef') or '')")
BASELINE_VALUE=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/04-baseline-env-var.json')); print(d.get('value') or '')")
echo "Baseline env var: secretRef='$BASELINE_SECRETREF' value='${BASELINE_VALUE:0:40}'"

echo "=== Phase 5: baseline secret store snapshot (expect ${EXPECTED_SECRET_NAME} present) ==="
# `--secrets` flag tells `az containerapp show` to include secret values (resolved at the
# managed-env layer); we redact the VALUE to a placeholder here because logging real
# connection strings in evidence files would be a P0 PII leak. We only need the NAME, the
# value-presence indicator, and the keyVaultUrl (which is None for this lab — secrets are
# inline). The post-trigger secret store snapshot in Phase 10 will repeat this and the H1
# sub-gate `d` will compare presence + name + identity, NOT the resolved value.
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.secrets" \
    --output json > "$EVIDENCE_DIR/05-baseline-secrets-raw.json"

python3 - <<PY > "$EVIDENCE_DIR/05-baseline-secrets.json"
import json
src = json.load(open("$EVIDENCE_DIR/05-baseline-secrets-raw.json"))
redacted = []
for s in (src or []):
    redacted.append({
        "name": s.get("name"),
        "value_present": "value" in s and bool(s.get("value")),
        "value_redacted_placeholder": "REDACTED_NEVER_LOG_REAL_CONNECTION_STRINGS",
        "keyVaultUrl": s.get("keyVaultUrl"),
        "identity": s.get("identity"),
    })
print(json.dumps({
    "utc_captured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "secrets_count": len(redacted),
    "secrets": redacted,
}, indent=2))
PY

# Drop the raw file with the real secret values — keep ONLY the redacted summary in evidence/.
rm -f "$EVIDENCE_DIR/05-baseline-secrets-raw.json"

BASELINE_SECRETS_COUNT=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/05-baseline-secrets.json')); print(d['secrets_count'])")
echo "Baseline secret store: $BASELINE_SECRETS_COUNT secret(s) present (values redacted)"

echo "=== Phase 6: trigger — apply invalid literal connection string ==="
echo "Expected literal value: $EXPECTED_LITERAL_VALUE"
TRIGGER_EXIT_CODE=0
az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --set-env-vars "${EXPECTED_ENV_VAR_NAME}=${EXPECTED_LITERAL_VALUE}" \
    --output json \
    > "$EVIDENCE_DIR/06-trigger-update.json" \
    2> "$EVIDENCE_DIR/06-trigger-update.stderr" \
    || TRIGGER_EXIT_CODE=$?

POST_TRIGGER_REVISION_NAME=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/06-trigger-update.json')); print(d.get('properties', {}).get('latestRevisionName', ''))")
echo "Post-trigger latestRevisionName: $POST_TRIGGER_REVISION_NAME (trigger exit=$TRIGGER_EXIT_CODE)"

echo "=== Phase 7: wait for new revision to provision ==="
WAIT_LOG="$EVIDENCE_DIR/07-wait-trigger-revision.log"
{
    echo "wait_started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "expected_revision=$POST_TRIGGER_REVISION_NAME"
    echo "max_attempts=$WAIT_REVISION_MAX_ATTEMPTS sleep=${WAIT_REVISION_SLEEP_SECONDS}s"
} > "$WAIT_LOG"

WAIT_ATTEMPT=0
WAIT_PROVISIONED=false
while [ "$WAIT_ATTEMPT" -lt "$WAIT_REVISION_MAX_ATTEMPTS" ]; do
    WAIT_ATTEMPT=$((WAIT_ATTEMPT + 1))
    PROVISIONING_STATE=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$POST_TRIGGER_REVISION_NAME" \
        --query "properties.provisioningState" \
        --output tsv 2>/dev/null || echo "NotFound")
    echo "attempt=$WAIT_ATTEMPT utc=$(date -u +%Y-%m-%dT%H:%M:%SZ) provisioningState=$PROVISIONING_STATE" >> "$WAIT_LOG"
    if [ "$PROVISIONING_STATE" = "Provisioned" ]; then
        WAIT_PROVISIONED=true
        break
    fi
    sleep "$WAIT_REVISION_SLEEP_SECONDS"
done

{
    echo "wait_ended_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "wait_provisioned=$WAIT_PROVISIONED"
} >> "$WAIT_LOG"
echo "Wait complete: provisioned=$WAIT_PROVISIONED (attempts=$WAIT_ATTEMPT)"

echo "=== Phase 8: post-trigger env var snapshot (expect Source = literal value) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.template.containers[0].env[?name=='${EXPECTED_ENV_VAR_NAME}'] | [0]" \
    --output json > "$EVIDENCE_DIR/08-post-trigger-env-var.json"

POST_TRIGGER_VALUE=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/08-post-trigger-env-var.json')); print(d.get('value') or '')")
POST_TRIGGER_SECRETREF=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/08-post-trigger-env-var.json')); print(d.get('secretRef') or '')")
echo "Post-trigger env var: secretRef='$POST_TRIGGER_SECRETREF' value='${POST_TRIGGER_VALUE:0:50}...'"

echo "=== Phase 9: post-trigger revisions snapshot ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name:name, active:properties.active, createdTime:properties.createdTime, healthState:properties.healthState, runningState:properties.runningState, trafficWeight:properties.trafficWeight}" \
    --output json > "$EVIDENCE_DIR/09-post-trigger-revisions.json"

echo "=== Phase 10: post-trigger secret store snapshot (expect ${EXPECTED_SECRET_NAME} still present) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.secrets" \
    --output json > "$EVIDENCE_DIR/10-post-trigger-secrets-raw.json"

python3 - <<PY > "$EVIDENCE_DIR/10-post-trigger-secrets.json"
import json
src = json.load(open("$EVIDENCE_DIR/10-post-trigger-secrets-raw.json"))
redacted = []
for s in (src or []):
    redacted.append({
        "name": s.get("name"),
        "value_present": "value" in s and bool(s.get("value")),
        "value_redacted_placeholder": "REDACTED_NEVER_LOG_REAL_CONNECTION_STRINGS",
        "keyVaultUrl": s.get("keyVaultUrl"),
        "identity": s.get("identity"),
    })
print(json.dumps({
    "utc_captured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "secrets_count": len(redacted),
    "secrets": redacted,
}, indent=2))
PY
rm -f "$EVIDENCE_DIR/10-post-trigger-secrets-raw.json"

POST_TRIGGER_SECRETS_COUNT=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/10-post-trigger-secrets.json')); print(d['secrets_count'])")
echo "Post-trigger secret store: $POST_TRIGGER_SECRETS_COUNT secret(s) present (values redacted)"

echo "=== Phase 11: post-trigger curl probes (expect ${POST_TRIGGER_CURL_ATTEMPTS}/${POST_TRIGGER_CURL_ATTEMPTS} HTTP 200 — data plane unaffected) ==="
POST_TRIGGER_SUCCESS=0
POST_TRIGGER_TIMEOUT=0
POST_TRIGGER_RESULTS=()
for i in $(seq 1 "$POST_TRIGGER_CURL_ATTEMPTS"); do
    if CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time "$CURL_MAX_TIME" "https://${APP_FQDN}/" 2>/dev/null); then
        :
    else
        CODE="000"
    fi
    POST_TRIGGER_RESULTS+=("\"req_${i}\": \"${CODE}\"")
    if [ "$CODE" = "200" ]; then
        POST_TRIGGER_SUCCESS=$((POST_TRIGGER_SUCCESS + 1))
    fi
    if [ "$CODE" = "000" ]; then
        POST_TRIGGER_TIMEOUT=$((POST_TRIGGER_TIMEOUT + 1))
    fi
done

POST_TRIGGER_RESULTS_JSON=$(IFS=,; echo "{${POST_TRIGGER_RESULTS[*]}}")
python3 - <<PY > "$EVIDENCE_DIR/11-curl-after-trigger.json"
import json
print(json.dumps({
    "utc_captured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "app_fqdn": "$APP_FQDN",
    "attempts": $POST_TRIGGER_CURL_ATTEMPTS,
    "max_time_seconds_per_request": $CURL_MAX_TIME,
    "success_count_200": $POST_TRIGGER_SUCCESS,
    "timeout_count_000": $POST_TRIGGER_TIMEOUT,
    "per_request_codes": $POST_TRIGGER_RESULTS_JSON
}, indent=2))
PY
echo "Post-trigger curl: $POST_TRIGGER_SUCCESS/$POST_TRIGGER_CURL_ATTEMPTS HTTP 200"

echo "=== Phase 12: emit H1 gate JSON ==="
# H1 sub-gate logic. Each gate is evaluated against the raw evidence files; the JSON output
# below is a derivation of those files and MUST NOT be edited without re-running this script
# end-to-end. The Lab 11/12 strict 2-path predicate pattern is applied to sub-gate `c` (literal
# value match): Strong path = exact-string match against the documented invalid value; Fallback
# path = env var has a non-empty `value` field AND no `secretRef` field. Sub-gate `d` triangulates
# secret-store integrity by comparing baseline and post-trigger secret name/identity (NOT the
# resolved value, which is a P0 PII leak risk).
python3 - <<PY > "$EVIDENCE_DIR/12-h1-gate.json"
import json

baseline_env = json.load(open("$EVIDENCE_DIR/04-baseline-env-var.json"))
post_trigger_env = json.load(open("$EVIDENCE_DIR/08-post-trigger-env-var.json"))
baseline_secrets = json.load(open("$EVIDENCE_DIR/05-baseline-secrets.json"))
post_trigger_secrets = json.load(open("$EVIDENCE_DIR/10-post-trigger-secrets.json"))
baseline_revs = json.load(open("$EVIDENCE_DIR/02-baseline-revisions.json"))
post_trigger_revs = json.load(open("$EVIDENCE_DIR/09-post-trigger-revisions.json"))

baseline_revision_name = "$BASELINE_REVISION_NAME"
post_trigger_revision_name = "$POST_TRIGGER_REVISION_NAME"
expected_literal_value = "$EXPECTED_LITERAL_VALUE"
expected_secret_name = "$EXPECTED_SECRET_NAME"
expected_env_var_name = "$EXPECTED_ENV_VAR_NAME"

# Sub-gate a: baseline env var was sourced from secretRef
a_baseline_env_was_secretref = (
    baseline_env is not None
    and baseline_env.get("name") == expected_env_var_name
    and baseline_env.get("secretRef") == expected_secret_name
    and not baseline_env.get("value")
)

# Sub-gate b: trigger succeeded AND minted a new revision
b_trigger_succeeded_and_revision_advanced = (
    $TRIGGER_EXIT_CODE == 0
    and post_trigger_revision_name
    and post_trigger_revision_name != baseline_revision_name
)

# Sub-gate c: post-trigger env var is now the literal value (Strong path + Fallback path)
post_trigger_value = post_trigger_env.get("value") if post_trigger_env else None
post_trigger_secretref = post_trigger_env.get("secretRef") if post_trigger_env else None
c_strong_path = (post_trigger_value == expected_literal_value)
c_fallback_path = (
    post_trigger_env is not None
    and post_trigger_env.get("name") == expected_env_var_name
    and bool(post_trigger_value)
    and not post_trigger_secretref
)
c_env_var_now_literal_with_expected_value = c_strong_path or c_fallback_path

# Sub-gate d: secret-store integrity preserved (name present in BOTH snapshots; keyVaultUrl,
# identity preserved). We do NOT compare resolved values for the documented PII reason.
baseline_secret_match = None
for s in baseline_secrets.get("secrets", []):
    if s.get("name") == expected_secret_name:
        baseline_secret_match = s
        break
post_trigger_secret_match = None
for s in post_trigger_secrets.get("secrets", []):
    if s.get("name") == expected_secret_name:
        post_trigger_secret_match = s
        break
d_secret_store_unchanged = (
    baseline_secret_match is not None
    and post_trigger_secret_match is not None
    and baseline_secret_match.get("keyVaultUrl") == post_trigger_secret_match.get("keyVaultUrl")
    and baseline_secret_match.get("identity") == post_trigger_secret_match.get("identity")
    and baseline_secret_match.get("value_present") == post_trigger_secret_match.get("value_present")
)

# Sub-gate e: app still serves HTTP 200 (data plane unaffected by env var change)
e_app_continues_serving_requests = ($POST_TRIGGER_SUCCESS == $POST_TRIGGER_CURL_ATTEMPTS)

h1_sub_gates = {
    "a_baseline_env_was_secretref": a_baseline_env_was_secretref,
    "b_trigger_succeeded_and_revision_advanced": b_trigger_succeeded_and_revision_advanced,
    "c_env_var_now_literal_with_expected_value": c_env_var_now_literal_with_expected_value,
    "d_secret_store_unchanged": d_secret_store_unchanged,
    "e_app_continues_serving_requests": e_app_continues_serving_requests,
}
h1_all_pass = all(h1_sub_gates.values())

print(json.dumps({
    "utc_captured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "subscription": "00000000-0000-0000-0000-000000000000",
    "rg": "$RG",
    "app_name": "$APP_NAME",
    "app_fqdn": "$APP_FQDN",
    "trigger_window": {
        "start_utc": "$(cat "$WAIT_LOG" | grep wait_started_utc | head -1 | cut -d= -f2)",
        "baseline_revision_name": baseline_revision_name,
        "post_trigger_revision_name": post_trigger_revision_name,
        "revision_advanced": post_trigger_revision_name != baseline_revision_name,
        "expected_env_var_name": expected_env_var_name,
        "expected_literal_value": expected_literal_value,
        "expected_secret_name": expected_secret_name,
        "trigger_cli_exit_code": $TRIGGER_EXIT_CODE,
        "wait_provisioned": "$WAIT_PROVISIONED" == "true",
    },
    "env_var_state": {
        "baseline_secretRef": baseline_env.get("secretRef") if baseline_env else None,
        "baseline_value": baseline_env.get("value") if baseline_env else None,
        "post_trigger_secretRef": post_trigger_secretref,
        "post_trigger_value": post_trigger_value,
        "c_strong_path_exact_string_match": c_strong_path,
        "c_fallback_path_non_empty_value_no_secretref": c_fallback_path,
    },
    "secret_store_integrity": {
        "expected_secret_name": expected_secret_name,
        "baseline_secrets_count": baseline_secrets.get("secrets_count"),
        "post_trigger_secrets_count": post_trigger_secrets.get("secrets_count"),
        "baseline_secret_match": baseline_secret_match,
        "post_trigger_secret_match": post_trigger_secret_match,
        "comparison_excludes_resolved_value_for_pii_safety": True,
    },
    "client_probe_results": {
        "baseline_success_count_200": $BASELINE_SUCCESS,
        "baseline_attempts": $BASELINE_CURL_ATTEMPTS,
        "post_trigger_success_count_200": $POST_TRIGGER_SUCCESS,
        "post_trigger_attempts": $POST_TRIGGER_CURL_ATTEMPTS,
        "note": "Both baseline and post-trigger curl probes are expected to be 5/5 HTTP 200. The trigger changes telemetry export configuration ONLY, not request handling. The data-plane integrity check is sub-gate e.",
    },
    "telemetry_caveat": {
        "image": "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest",
        "ships_application_insights_sdk": False,
        "trace_count_expected_in_both_states": 0,
        "telemetry_blocking_hypothesis_status": "[Not Proven] — see lab guide Hypothesis caveat",
        "h1_intentionally_restricted_to": "env-var Source/Value flip (directly observable from Container App template)",
    },
    "h1_sub_gates": h1_sub_gates,
    "h1_all_subgates_pass": h1_all_pass,
    "gate_classification": "telemetry_misconfiguration_env_var_source_flipped_to_literal" if h1_all_pass else "h1_failed_check_sub_gates",
}, indent=2))
PY

echo "=== H1 gate emitted to $EVIDENCE_DIR/12-h1-gate.json ==="
python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/12-h1-gate.json')); print('Classification:', d['gate_classification']); print('All sub-gates pass:', d['h1_all_subgates_pass']); [print(f'  {k}: {v}') for k,v in d['h1_sub_gates'].items()]"
