#!/usr/bin/env bash
# verify.sh — observability-tracing lab Phase B evidence-pack fix-path verification
#
# What this script proves (falsifiable):
#   H2: telemetry_configuration_restored_to_secretref_app_intact
#       a) Pre-fix env var is STILL the literal value (proves trigger.sh persisted across the gap
#          between trigger and fix — i.e. the fix is operating on the broken state, not a stale
#          snapshot).
#       b) `az containerapp update --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:...`
#          succeeded AND minted a new revision distinct from BOTH the baseline AND the post-trigger
#          revision.
#       c) Post-fix env var is back to secretRef sourcing (Source=secretRef, value empty).
#       d) Secret-store entry `appinsights-connection-string` STILL present and integrity preserved
#          (name + keyVaultUrl + identity + value_present unchanged across baseline → trigger → fix,
#          proving the fix touched ONLY the Container App template, NEVER the secret store).
#       e) App STILL serves HTTP 200 from the public FQDN post-fix.
#       f) Revision progression is documented: baseline_revision != post_trigger_revision !=
#          post_fix_revision, AND all three revisions are distinct (proves the lab produced three
#          observable state transitions, not two with a no-op fix).
#
# Honest disclosure (same as trigger.sh):
#   The baseline image (`azuredocs/containerapps-helloworld:latest`) ships no Application Insights
#   SDK. Application Insights / Log Analytics will report zero traces in ALL three states
#   (baseline / post-trigger / post-fix). H2 intentionally restricts its falsifiable claims to
#   the env-var Source/Value restoration and the revision progression; the telemetry-blocking half
#   of the upstream hypothesis remains `[Not Proven]` and is documented in the lab guide.
#
# Required environment:
#   AZ_SUBSCRIPTION         Subscription ID
#   RG                      Resource group name (Bicep already deployed, trigger.sh already run)
#   APP_NAME                Container App name (from Bicep output)
#
# Cost note: this script mutates the existing Container App template env vars only. Each
# `az containerapp update` mints a new revision; the lab's scale rule keeps minReplicas=1, so
# verify.sh + trigger.sh together stay under $0.20 USD when paired with cleanup.sh.

set -euo pipefail

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION to the subscription ID before running}"
: "${RG:?Set RG to the lab resource group before running}"
: "${APP_NAME:?Set APP_NAME to the Container App name from the Bicep output}"

EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

EXPECTED_LITERAL_VALUE="InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/"
EXPECTED_SECRET_NAME="appinsights-connection-string"
EXPECTED_ENV_VAR_NAME="APPLICATIONINSIGHTS_CONNECTION_STRING"

CURL_MAX_TIME=10
PRE_FIX_CURL_ATTEMPTS=5
POST_FIX_CURL_ATTEMPTS=5

WAIT_REVISION_MAX_ATTEMPTS=24   # 240s = 4 minutes
WAIT_REVISION_SLEEP_SECONDS=10

# Reload prior-phase context from H1 gate so verify.sh can cross-reference baseline and
# post-trigger revision names without re-querying the platform.
if [ ! -f "$EVIDENCE_DIR/12-h1-gate.json" ]; then
    echo "ERROR: $EVIDENCE_DIR/12-h1-gate.json not found. Run trigger.sh before verify.sh." >&2
    exit 1
fi
BASELINE_REVISION_NAME=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/12-h1-gate.json')); print(d['trigger_window']['baseline_revision_name'])")
POST_TRIGGER_REVISION_NAME=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/12-h1-gate.json')); print(d['trigger_window']['post_trigger_revision_name'])")
APP_FQDN=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/12-h1-gate.json')); print(d['app_fqdn'])")
echo "Reloaded from H1 gate: baseline=$BASELINE_REVISION_NAME post_trigger=$POST_TRIGGER_REVISION_NAME fqdn=$APP_FQDN"

echo "=== Phase 13: pre-fix env var snapshot (expect Source = literal value — trigger persisted) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.template.containers[0].env[?name=='${EXPECTED_ENV_VAR_NAME}'] | [0]" \
    --output json > "$EVIDENCE_DIR/13-pre-fix-env-var.json"

PRE_FIX_VALUE=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/13-pre-fix-env-var.json')); print(d.get('value') or '')")
PRE_FIX_SECRETREF=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/13-pre-fix-env-var.json')); print(d.get('secretRef') or '')")
echo "Pre-fix env var: secretRef='$PRE_FIX_SECRETREF' value='${PRE_FIX_VALUE:0:50}...'"

echo "=== Phase 14: pre-fix curl probes (expect ${PRE_FIX_CURL_ATTEMPTS}/${PRE_FIX_CURL_ATTEMPTS} HTTP 200) ==="
PRE_FIX_SUCCESS=0
PRE_FIX_TIMEOUT=0
PRE_FIX_RESULTS=()
for i in $(seq 1 "$PRE_FIX_CURL_ATTEMPTS"); do
    # Lab 12 lesson: never use `CODE=$(curl ... || echo "000")`. Use explicit if/then/else.
    if CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time "$CURL_MAX_TIME" "https://${APP_FQDN}/" 2>/dev/null); then
        :
    else
        CODE="000"
    fi
    PRE_FIX_RESULTS+=("\"req_${i}\": \"${CODE}\"")
    if [ "$CODE" = "200" ]; then PRE_FIX_SUCCESS=$((PRE_FIX_SUCCESS + 1)); fi
    if [ "$CODE" = "000" ]; then PRE_FIX_TIMEOUT=$((PRE_FIX_TIMEOUT + 1)); fi
done

PRE_FIX_RESULTS_JSON=$(IFS=,; echo "{${PRE_FIX_RESULTS[*]}}")
python3 - <<PY > "$EVIDENCE_DIR/14-curl-pre-fix.json"
import json
print(json.dumps({
    "utc_captured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "app_fqdn": "$APP_FQDN",
    "attempts": $PRE_FIX_CURL_ATTEMPTS,
    "max_time_seconds_per_request": $CURL_MAX_TIME,
    "success_count_200": $PRE_FIX_SUCCESS,
    "timeout_count_000": $PRE_FIX_TIMEOUT,
    "per_request_codes": $PRE_FIX_RESULTS_JSON
}, indent=2))
PY
echo "Pre-fix curl: $PRE_FIX_SUCCESS/$PRE_FIX_CURL_ATTEMPTS HTTP 200"

echo "=== Phase 15: fix — restore env var to secretRef sourcing ==="
FIX_EXIT_CODE=0
az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --set-env-vars "${EXPECTED_ENV_VAR_NAME}=secretref:${EXPECTED_SECRET_NAME}" \
    --output json \
    > "$EVIDENCE_DIR/15-fix-update.json" \
    2> "$EVIDENCE_DIR/15-fix-update.stderr" \
    || FIX_EXIT_CODE=$?

POST_FIX_REVISION_NAME=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/15-fix-update.json')); print(d.get('properties', {}).get('latestRevisionName', ''))")
echo "Post-fix latestRevisionName: $POST_FIX_REVISION_NAME (fix exit=$FIX_EXIT_CODE)"

echo "=== Phase 16: wait for fix revision to provision ==="
WAIT_LOG="$EVIDENCE_DIR/16-wait-fix-revision.log"
{
    echo "wait_started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "expected_revision=$POST_FIX_REVISION_NAME"
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
        --revision "$POST_FIX_REVISION_NAME" \
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

echo "=== Phase 17: post-fix env var snapshot (expect Source = secretRef, value empty) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.template.containers[0].env[?name=='${EXPECTED_ENV_VAR_NAME}'] | [0]" \
    --output json > "$EVIDENCE_DIR/17-post-fix-env-var.json"

POST_FIX_VALUE=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/17-post-fix-env-var.json')); print(d.get('value') or '')")
POST_FIX_SECRETREF=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/17-post-fix-env-var.json')); print(d.get('secretRef') or '')")
echo "Post-fix env var: secretRef='$POST_FIX_SECRETREF' value='${POST_FIX_VALUE:0:40}'"

echo "=== Phase 18: post-fix revisions snapshot (expect three revisions) ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name:name, active:properties.active, createdTime:properties.createdTime, healthState:properties.healthState, runningState:properties.runningState, trafficWeight:properties.trafficWeight}" \
    --output json > "$EVIDENCE_DIR/18-post-fix-revisions.json"

echo "=== Phase 19: post-fix secret store snapshot (expect ${EXPECTED_SECRET_NAME} still present) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.secrets" \
    --output json > "$EVIDENCE_DIR/19-post-fix-secrets-raw.json"

python3 - <<PY > "$EVIDENCE_DIR/19-post-fix-secrets.json"
import json
src = json.load(open("$EVIDENCE_DIR/19-post-fix-secrets-raw.json"))
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
rm -f "$EVIDENCE_DIR/19-post-fix-secrets-raw.json"

POST_FIX_SECRETS_COUNT=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/19-post-fix-secrets.json')); print(d['secrets_count'])")
echo "Post-fix secret store: $POST_FIX_SECRETS_COUNT secret(s) present (values redacted)"

echo "=== Phase 20: post-fix curl probes (expect ${POST_FIX_CURL_ATTEMPTS}/${POST_FIX_CURL_ATTEMPTS} HTTP 200 — data plane unaffected) ==="
POST_FIX_SUCCESS=0
POST_FIX_TIMEOUT=0
POST_FIX_RESULTS=()
for i in $(seq 1 "$POST_FIX_CURL_ATTEMPTS"); do
    if CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time "$CURL_MAX_TIME" "https://${APP_FQDN}/" 2>/dev/null); then
        :
    else
        CODE="000"
    fi
    POST_FIX_RESULTS+=("\"req_${i}\": \"${CODE}\"")
    if [ "$CODE" = "200" ]; then POST_FIX_SUCCESS=$((POST_FIX_SUCCESS + 1)); fi
    if [ "$CODE" = "000" ]; then POST_FIX_TIMEOUT=$((POST_FIX_TIMEOUT + 1)); fi
done

POST_FIX_RESULTS_JSON=$(IFS=,; echo "{${POST_FIX_RESULTS[*]}}")
python3 - <<PY > "$EVIDENCE_DIR/20-curl-post-fix.json"
import json
print(json.dumps({
    "utc_captured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "app_fqdn": "$APP_FQDN",
    "attempts": $POST_FIX_CURL_ATTEMPTS,
    "max_time_seconds_per_request": $CURL_MAX_TIME,
    "success_count_200": $POST_FIX_SUCCESS,
    "timeout_count_000": $POST_FIX_TIMEOUT,
    "per_request_codes": $POST_FIX_RESULTS_JSON
}, indent=2))
PY
echo "Post-fix curl: $POST_FIX_SUCCESS/$POST_FIX_CURL_ATTEMPTS HTTP 200"

echo "=== Phase 21: CLI versions (for reproducibility) ==="
az version --output json > "$EVIDENCE_DIR/21-cli-versions.json"

echo "=== Phase 22: containerapp extension version (lockstep with CLI behavior) ==="
az extension show --name containerapp --output json > "$EVIDENCE_DIR/22-cli-containerapp-ext.json" 2>/dev/null || echo "{}" > "$EVIDENCE_DIR/22-cli-containerapp-ext.json"

echo "=== Phase 23: region detection (for cross-region capacity attribution) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{location:location, resourceGroup:resourceGroup}" \
    --output json > "$EVIDENCE_DIR/23-region.json"

echo "=== Phase 24: emit H2 gate JSON ==="
# H2 sub-gate logic. Same Lab 11/12 strict 2-path predicate approach as H1:
#   Sub-gate `c` (env var back to secretRef) has Strong path (exact match against expected
#   secret name) + Fallback path (secretRef non-empty AND value empty).
#   Sub-gate `d` (secret-store integrity post-fix) triangulates name + keyVaultUrl + identity
#   + value_present across the THREE snapshots (baseline → trigger → fix) instead of just
#   comparing trigger vs fix.
#   Sub-gate `f` (revision progression) requires THREE distinct revision names AND that the
#   post-fix revision is strictly after both the baseline and the post-trigger revision in the
#   createdTime ordering recorded in 18-post-fix-revisions.json.
python3 - <<PY > "$EVIDENCE_DIR/24-h2-gate.json"
import json

# Reload all three states for triangulation. Container Apps in single-revision mode applies
# revision history pruning, so the baseline revision name may NOT appear in the post-fix
# revisions snapshot — by the time Phase 18 runs, the platform may have already removed the
# oldest deactivated revision from the list. To sidestep that, we look up createdTime from
# the snapshot taken when each revision was the latest: baseline from 02, post-trigger from 09,
# post-fix from 18. This is also more semantically accurate ("createdTime as recorded at the
# time of the snapshot") than relying on the post-fix snapshot to preserve all three.
h1_gate = json.load(open("$EVIDENCE_DIR/12-h1-gate.json"))
pre_fix_env = json.load(open("$EVIDENCE_DIR/13-pre-fix-env-var.json"))
post_fix_env = json.load(open("$EVIDENCE_DIR/17-post-fix-env-var.json"))
baseline_secrets = json.load(open("$EVIDENCE_DIR/05-baseline-secrets.json"))
post_trigger_secrets = json.load(open("$EVIDENCE_DIR/10-post-trigger-secrets.json"))
post_fix_secrets = json.load(open("$EVIDENCE_DIR/19-post-fix-secrets.json"))
baseline_revs = json.load(open("$EVIDENCE_DIR/02-baseline-revisions.json"))
post_trigger_revs = json.load(open("$EVIDENCE_DIR/09-post-trigger-revisions.json"))
post_fix_revs = json.load(open("$EVIDENCE_DIR/18-post-fix-revisions.json"))

baseline_revision_name = "$BASELINE_REVISION_NAME"
post_trigger_revision_name = "$POST_TRIGGER_REVISION_NAME"
post_fix_revision_name = "$POST_FIX_REVISION_NAME"
expected_literal_value = "$EXPECTED_LITERAL_VALUE"
expected_secret_name = "$EXPECTED_SECRET_NAME"
expected_env_var_name = "$EXPECTED_ENV_VAR_NAME"

# Sub-gate a: pre-fix env var was still the literal value (trigger persisted to the fix moment)
a_pre_fix_value = pre_fix_env.get("value") if pre_fix_env else None
a_pre_fix_secretref = pre_fix_env.get("secretRef") if pre_fix_env else None
a_pre_fix_env_var_still_literal = (
    pre_fix_env is not None
    and pre_fix_env.get("name") == expected_env_var_name
    and bool(a_pre_fix_value)
    and not a_pre_fix_secretref
    and a_pre_fix_value == expected_literal_value
)

# Sub-gate b: fix command succeeded AND minted a new revision distinct from BOTH prior revisions
b_fix_command_succeeded_and_revision_advanced = (
    $FIX_EXIT_CODE == 0
    and post_fix_revision_name
    and post_fix_revision_name != baseline_revision_name
    and post_fix_revision_name != post_trigger_revision_name
)

# Sub-gate c: env var back to secretRef (Strong path + Fallback path)
c_post_fix_value = post_fix_env.get("value") if post_fix_env else None
c_post_fix_secretref = post_fix_env.get("secretRef") if post_fix_env else None
c_strong_path = (c_post_fix_secretref == expected_secret_name)
c_fallback_path = (
    post_fix_env is not None
    and post_fix_env.get("name") == expected_env_var_name
    and bool(c_post_fix_secretref)
    and not c_post_fix_value
)
c_env_var_back_to_secretref = c_strong_path or c_fallback_path

# Sub-gate d: secret-store integrity across ALL THREE states (baseline → trigger → fix)
def find_secret(snapshot, name):
    for s in snapshot.get("secrets", []):
        if s.get("name") == name:
            return s
    return None

bs = find_secret(baseline_secrets, expected_secret_name)
ts = find_secret(post_trigger_secrets, expected_secret_name)
fs = find_secret(post_fix_secrets, expected_secret_name)
d_secret_store_value_unchanged_after_fix = (
    bs is not None
    and ts is not None
    and fs is not None
    and bs.get("keyVaultUrl") == ts.get("keyVaultUrl") == fs.get("keyVaultUrl")
    and bs.get("identity") == ts.get("identity") == fs.get("identity")
    and bs.get("value_present") == ts.get("value_present") == fs.get("value_present")
)

# Sub-gate e: app still serves 5/5 HTTP 200 post-fix
e_app_continues_serving_requests_post_fix = ($POST_FIX_SUCCESS == $POST_FIX_CURL_ATTEMPTS)

# Sub-gate f: revision progression documented — three distinct revisions AND post-fix
# createdTime > post-trigger createdTime > baseline createdTime. Per the platform-pruning
# comment at the top of this block, we lookup createdTime from the snapshot taken when each
# revision was the latest, not the post-fix snapshot (which may have lost the baseline).
def lookup_created_time(revs, name):
    for r in revs:
        if r.get("name") == name:
            return r.get("createdTime")
    return None

baseline_ct = lookup_created_time(baseline_revs, baseline_revision_name)
post_trigger_ct = lookup_created_time(post_trigger_revs, post_trigger_revision_name)
post_fix_ct = lookup_created_time(post_fix_revs, post_fix_revision_name)
three_distinct = (
    baseline_revision_name
    and post_trigger_revision_name
    and post_fix_revision_name
    and baseline_revision_name != post_trigger_revision_name
    and post_trigger_revision_name != post_fix_revision_name
    and baseline_revision_name != post_fix_revision_name
)
created_time_ordering_ok = (
    baseline_ct is not None
    and post_trigger_ct is not None
    and post_fix_ct is not None
    and baseline_ct < post_trigger_ct < post_fix_ct
)
f_revision_progression_documented = three_distinct and created_time_ordering_ok

h2_sub_gates = {
    "a_pre_fix_env_var_still_literal": a_pre_fix_env_var_still_literal,
    "b_fix_command_succeeded_and_revision_advanced": b_fix_command_succeeded_and_revision_advanced,
    "c_env_var_back_to_secretref": c_env_var_back_to_secretref,
    "d_secret_store_value_unchanged_after_fix": d_secret_store_value_unchanged_after_fix,
    "e_app_continues_serving_requests_post_fix": e_app_continues_serving_requests_post_fix,
    "f_revision_progression_documented": f_revision_progression_documented,
}
h2_all_pass = all(h2_sub_gates.values())

print(json.dumps({
    "utc_captured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "subscription": "00000000-0000-0000-0000-000000000000",
    "rg": "$RG",
    "app_name": "$APP_NAME",
    "app_fqdn": "$APP_FQDN",
    "fix_window": {
        "baseline_revision_name": baseline_revision_name,
        "post_trigger_revision_name": post_trigger_revision_name,
        "post_fix_revision_name": post_fix_revision_name,
        "three_distinct_revisions": three_distinct,
        "expected_env_var_name": expected_env_var_name,
        "expected_secret_name": expected_secret_name,
        "fix_cli_exit_code": $FIX_EXIT_CODE,
        "wait_provisioned": "$WAIT_PROVISIONED" == "true",
    },
    "env_var_state": {
        "pre_fix_value": a_pre_fix_value,
        "pre_fix_secretRef": a_pre_fix_secretref,
        "pre_fix_matches_expected_literal": (a_pre_fix_value == expected_literal_value),
        "post_fix_value": c_post_fix_value,
        "post_fix_secretRef": c_post_fix_secretref,
        "c_strong_path_secretref_exact_match": c_strong_path,
        "c_fallback_path_non_empty_secretref_no_value": c_fallback_path,
    },
    "secret_store_integrity_across_three_states": {
        "expected_secret_name": expected_secret_name,
        "baseline_match": bs,
        "post_trigger_match": ts,
        "post_fix_match": fs,
        "comparison_excludes_resolved_value_for_pii_safety": True,
    },
    "revision_progression": {
        "baseline_createdTime": baseline_ct,
        "post_trigger_createdTime": post_trigger_ct,
        "post_fix_createdTime": post_fix_ct,
        "three_distinct_names": three_distinct,
        "createdTime_strictly_increasing": created_time_ordering_ok,
    },
    "client_probe_results": {
        "pre_fix_success_count_200": $PRE_FIX_SUCCESS,
        "pre_fix_attempts": $PRE_FIX_CURL_ATTEMPTS,
        "post_fix_success_count_200": $POST_FIX_SUCCESS,
        "post_fix_attempts": $POST_FIX_CURL_ATTEMPTS,
        "note": "Both pre-fix and post-fix curl probes are expected to be 5/5 HTTP 200. The fix changes telemetry export configuration ONLY, not request handling.",
    },
    "telemetry_caveat": {
        "image": "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest",
        "ships_application_insights_sdk": False,
        "trace_count_expected_in_all_three_states": 0,
        "telemetry_blocking_hypothesis_status": "[Not Proven] — see lab guide Hypothesis caveat",
        "h2_intentionally_restricted_to": "env-var Source/Value restoration + revision progression (directly observable from Container App template and revision list)",
    },
    "h2_sub_gates": h2_sub_gates,
    "h2_all_subgates_pass": h2_all_pass,
    "gate_classification": "telemetry_configuration_restored_to_secretref_app_intact" if h2_all_pass else "h2_failed_check_sub_gates",
}, indent=2))
PY

echo "=== H2 gate emitted to $EVIDENCE_DIR/24-h2-gate.json ==="
python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/24-h2-gate.json')); print('Classification:', d['gate_classification']); print('All sub-gates pass:', d['h2_all_subgates_pass']); [print(f'  {k}: {v}') for k,v in d['h2_sub_gates'].items()]"
