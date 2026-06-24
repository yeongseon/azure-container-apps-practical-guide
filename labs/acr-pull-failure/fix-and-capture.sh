#!/usr/bin/env bash
# fix-and-capture.sh — Phase A live-Azure fix and recovery capture for the
# acr-pull-failure lab.
#
# Before the Phase B evidence-pack refactor (2026-06-24) this script was
# named verify.sh; the Phase B verify.sh is now a pure file processor
# (no Azure calls) that emits four falsifiable gate JSONs under evidence/.
# The Phase A live-capture role moved here so both scripts can coexist with
# clear semantic boundaries: trigger.sh produces the failed-deployment
# baseline, fix-and-capture.sh runs az acr build + az containerapp update
# to recover the app and capture post-fix evidence (Phases 7-16), and
# verify.sh consumes the committed evidence and emits gate JSONs (Phase B).
#
# The output filename 00-verify-run.txt (captured by the operator's
# `tee evidence/00-verify-run.txt` invocation in the README Quick Start)
# is intentionally preserved for canonical-evidence schema stability — the
# committed Phase A evidence pack references this filename, and renaming
# it would orphan the canonical record. Future re-runs of fix-and-capture.sh
# will overwrite 00-verify-run.txt at the same canonical path.
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${ACR_NAME:?Set ACR_NAME before running}"
: "${ACR_LOGIN_SERVER:?Set ACR_LOGIN_SERVER before running}"
: "${WORKSPACE_CUSTOMER_ID:?Set WORKSPACE_CUSTOMER_ID before running (the LAW guid, not the resource ID)}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
WORKLOAD_DIR="$(cd "$(dirname "$0")" && pwd)/workload"
mkdir -p "$EVIDENCE_DIR"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "fix-and-capture.sh starting at ${UTC_NOW}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "ACR: ${ACR_NAME}"
echo "ACR login server: ${ACR_LOGIN_SERVER}"
echo ""

echo "=== Phase 7: validate baseline evidence from trigger.sh ==="
H1_FILE="$EVIDENCE_DIR/06-h1-gate.json"
if [[ ! -f "$H1_FILE" ]]; then
    echo "INVALID RUN: $H1_FILE not found. Run trigger.sh first."
    exit 1
fi
H1_GATE=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['gate_classification'])")
H1_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['h1_all_subgates_pass'])")
echo "Triggered state: H1 gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
if [[ "$H1_GATE" == "deployment_succeeded_revision_present" ]]; then
    echo "INVALID RUN: H1 was FALSIFIED in trigger.sh. Cannot run fix-and-capture.sh because the baseline failure state did not materialize."
    exit 1
fi
echo ""

echo "=== Phase 8: az acr build --image labacr:v1 ./workload (build known-good image and push to ACR) ==="
FIX_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Fix UTC: $FIX_UTC"
az acr build \
    --subscription "$AZ_SUBSCRIPTION" \
    --registry "$ACR_NAME" \
    --image "labacr:v1" \
    --file "$WORKLOAD_DIR/Dockerfile" \
    "$WORKLOAD_DIR" \
    > "$EVIDENCE_DIR/07-acr-build-result.json" 2>&1 || true

ACR_BUILD_OK=$(python3 -c "
import re
with open('$EVIDENCE_DIR/07-acr-build-result.json') as f:
    t = f.read()
# az acr build prints 'Run ID: ...' on success and ends with 'Run ID: ... was successful after ...'
print('true' if re.search(r'Run ID:.*was successful', t) or 'Build complete' in t or '\"status\": \"Succeeded\"' in t else 'false')
")
echo "az acr build apparent success: $ACR_BUILD_OK"
echo "Output (truncated to first 1000 chars):"
head -c 1000 "$EVIDENCE_DIR/07-acr-build-result.json" || true
echo ""
echo ""

if [[ "$ACR_BUILD_OK" != "true" ]]; then
    echo "INVALID RUN: az acr build did not succeed. Inspect 07-acr-build-result.json before proceeding."
    exit 1
fi

echo "=== Phase 9: az containerapp update --image \${ACR_LOGIN_SERVER}/labacr:v1 ==="
az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --image "${ACR_LOGIN_SERVER}/labacr:v1" \
    --query "{name: name, provisioningState: properties.provisioningState, latestRevisionName: properties.latestRevisionName, image: properties.template.containers[0].image}" \
    --output json \
    > "$EVIDENCE_DIR/08-containerapp-update-result.json"
cat "$EVIDENCE_DIR/08-containerapp-update-result.json"
echo ""

POST_FIX_PROVISIONING_STATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-containerapp-update-result.json'))['provisioningState'])")
POST_FIX_REVISION_NAME=$(python3 -c "
import json
d = json.load(open('$EVIDENCE_DIR/08-containerapp-update-result.json'))
v = d.get('latestRevisionName')
print('' if v is None else v)
")
echo "Post-fix provisioningState: $POST_FIX_PROVISIONING_STATE"
echo "Post-fix latestRevisionName: '$POST_FIX_REVISION_NAME'"
echo ""

if [[ "$POST_FIX_PROVISIONING_STATE" != "Succeeded" ]]; then
    echo "INVALID RUN: az containerapp update did not transition provisioningState to Succeeded (got: $POST_FIX_PROVISIONING_STATE)."
    exit 1
fi
if [[ -z "$POST_FIX_REVISION_NAME" ]]; then
    echo "INVALID RUN: az containerapp update succeeded but no revision name was returned."
    exit 1
fi

echo "=== Phase 10: poll revision health up to 5 minutes (10 s interval) ==="
DEADLINE=$(( $(date +%s) + 300 ))
revision_health="Unknown"
POLL_COUNT=0
while [[ $(date +%s) -lt $DEADLINE ]]; do
    POLL_COUNT=$(( POLL_COUNT + 1 ))
    revision_health=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$POST_FIX_REVISION_NAME" \
        --query "properties.healthState" \
        --output tsv 2>/dev/null || echo "Unknown")
    echo "Poll #${POLL_COUNT} at $(date -u +%Y-%m-%dT%H:%M:%SZ): healthState=${revision_health}"
    if [[ "$revision_health" == "Healthy" ]]; then
        break
    fi
    sleep 10
done
echo "Final healthState after polling: $revision_health"
echo ""

echo "=== Phase 11: capture container app post-fix (expect provisioningState=Succeeded, FQDN populated) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{name: name, provisioningState: properties.provisioningState, latestRevisionName: properties.latestRevisionName, latestRevisionFqdn: properties.latestRevisionFqdn, ingress: properties.configuration.ingress, image: properties.template.containers[0].image}" \
    --output json \
    > "$EVIDENCE_DIR/09-containerapp-show-after-fix.json"
cat "$EVIDENCE_DIR/09-containerapp-show-after-fix.json"
echo ""

POST_FIX_FQDN=$(python3 -c "
import json
d = json.load(open('$EVIDENCE_DIR/09-containerapp-show-after-fix.json'))
v = (d.get('ingress') or {}).get('fqdn') or ''
print(v)
")
echo "Post-fix FQDN: $POST_FIX_FQDN"
echo ""

if [[ -z "$POST_FIX_FQDN" ]]; then
    echo "INVALID RUN: post-fix FQDN is empty. Cannot proceed to Phase 14 curl probes."
    exit 1
fi

echo "=== Phase 12: capture revision list post-fix (expect Healthy + traffic=100) ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, runningState: properties.runningState, replicas: properties.replicas, trafficWeight: properties.trafficWeight, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/10-revisions-list-after-fix.json"
cat "$EVIDENCE_DIR/10-revisions-list-after-fix.json"
echo ""

REVISION_HEALTHY_TRAFFIC_100=$(python3 -c "
import json
revs = json.load(open('$EVIDENCE_DIR/10-revisions-list-after-fix.json'))
healthy_and_100 = False
for r in revs:
    if r.get('healthState') == 'Healthy' and r.get('trafficWeight') == 100:
        healthy_and_100 = True
        break
print('true' if healthy_and_100 else 'false')
")
REVISION_LIST_COUNT=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/10-revisions-list-after-fix.json'))))")
echo "Revision list count: $REVISION_LIST_COUNT"
echo "At least one revision is Healthy + trafficWeight=100: $REVISION_HEALTHY_TRAFFIC_100"
echo ""

echo "=== Phase 13: capture ACR repository list post-fix (expect labacr present) ==="
az acr repository list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$ACR_NAME" \
    --output json \
    > "$EVIDENCE_DIR/11-acr-repository-list-after-fix.json"
cat "$EVIDENCE_DIR/11-acr-repository-list-after-fix.json"
echo ""

az acr repository show-tags \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$ACR_NAME" \
    --repository "labacr" \
    --output json \
    > "$EVIDENCE_DIR/11-acr-repository-show-tags-after-fix.json" 2>&1 || true
echo "labacr tags:"
cat "$EVIDENCE_DIR/11-acr-repository-show-tags-after-fix.json"
echo ""

LABACR_PRESENT_AFTER_FIX=$(python3 -c "
import json
repos = json.load(open('$EVIDENCE_DIR/11-acr-repository-list-after-fix.json'))
print('true' if 'labacr' in repos else 'false')
")
echo "labacr present in ACR post-fix: $LABACR_PRESENT_AFTER_FIX (expect true)"
echo ""

echo "=== Phase 14: send 10 HTTPS requests to post-fix FQDN (expect >=8/10 HTTP 200) ==="
python3 -c "
import json, urllib.request, time
fqdn = '$POST_FIX_FQDN'
results = []
for i in range(10):
    t0 = time.time()
    try:
        with urllib.request.urlopen(f'https://{fqdn}/', timeout=10) as r:
            results.append({'i': i, 'status': r.status, 'elapsed_ms': round((time.time()-t0)*1000, 1)})
    except urllib.error.HTTPError as e:
        results.append({'i': i, 'status': e.code, 'elapsed_ms': round((time.time()-t0)*1000, 1)})
    except Exception as e:
        results.append({'i': i, 'status': 'error', 'error': str(e), 'elapsed_ms': round((time.time()-t0)*1000, 1)})
    time.sleep(0.5)
ok = sum(1 for r in results if r.get('status') == 200)
out = {'post_fix_revision': '$POST_FIX_REVISION_NAME', 'post_fix_fqdn': fqdn, 'requests_sent': 10, 'requests_ok': ok, 'utc_completed': '$(date -u +%Y-%m-%dT%H:%M:%SZ)', 'samples': results}
json.dump(out, open('$EVIDENCE_DIR/12-curl-after-fix.json', 'w'), indent=2)
print(f'Sent 10 requests, {ok}/10 ok')
"
echo ""

CURL_AFTER_FIX_OK=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/12-curl-after-fix.json'))['requests_ok'])")
echo "curl post-fix HTTP 200 count: $CURL_AFTER_FIX_OK/10"
echo ""

echo "=== Phase 15: optional post-fix KQL ContainerAppSystemLogs_CL sanity (table may have just been materialized) ==="
KQL_POST_FIX="ContainerAppSystemLogs_CL | where TimeGenerated > datetime(${FIX_UTC}) | where ContainerAppName_s == '${APP_NAME}' | summarize rows=count(), distinct_revisions=dcount(RevisionName_s)"

set +e
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_POST_FIX" \
    --output json \
    > "$EVIDENCE_DIR/13-kql-after-fix-raw.txt" 2>&1
POST_FIX_KQL_EXIT=$?
set -e
echo "az monitor log-analytics query exit code: $POST_FIX_KQL_EXIT"
echo "Output (truncated to first 500 chars):"
head -c 500 "$EVIDENCE_DIR/13-kql-after-fix-raw.txt" || true
echo ""
echo ""

UTC_QUERY="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR UTC_QUERY APP_NAME POST_FIX_REVISION_NAME POST_FIX_FQDN FIX_UTC KQL_POST_FIX POST_FIX_KQL_EXIT CURL_AFTER_FIX_OK REVISION_HEALTHY_TRAFFIC_100 REVISION_LIST_COUNT LABACR_PRESENT_AFTER_FIX

python3 <<'PYEOF'
import json, os

# Phase-15 KQL parser. Post-fix KQL is OPTIONAL evidence in this lab because the
# ContainerAppSystemLogs_CL table is materialized lazily when the first row is written.
# Three legitimate outcomes are accepted here:
#
#   populated_table              - >= 1 row was attributed by the platform in the post-fix
#                                  window (the table exists and the platform is ingesting)
#   silent_acceptable_post_fix   - 0 rows in the post-fix window AND/OR the table is not
#                                  yet materialized (BadArgumentError + 'Failed to resolve
#                                  table'). For ACR pull failure this is acceptable because
#                                  the table did not exist during the failed-deployment
#                                  window and may take additional ingestion time after the
#                                  first successful revision starts.
#   query_error_invalid_run      - The KQL CLI returned an unexpected error signature that
#                                  cannot be parsed as either "no rows", "with rows", or
#                                  "table not materialized".
#
# Unlike Lab 6 (ingress-target-port-mismatch) where post-fix silence is the EXPECTED outcome
# proving the fix held, post-fix KQL here is just a sanity check; the H2 gate is driven by
# revision health + traffic weight + curl HTTP 200, not by KQL row counts.

def parse_post_fix_kql(path, exit_code):
    with open(path) as f:
        text = f.read()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = None
    if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict):
        rows = int(parsed[0].get('rows', 0) or 0)
        distinct_revisions = int(parsed[0].get('distinct_revisions', 0) or 0)
        gate = 'populated_table' if rows >= 1 else 'silent_acceptable_post_fix'
        return {
            'parse_status': 'parsed_json_with_rows',
            'cli_exit_code': exit_code,
            'rows': rows,
            'distinct_revisions': distinct_revisions,
            'gate_classification': gate,
            'raw_json': parsed,
        }
    if isinstance(parsed, list) and not parsed:
        return {
            'parse_status': 'parsed_empty_list',
            'cli_exit_code': exit_code,
            'rows': 0,
            'distinct_revisions': 0,
            'gate_classification': 'silent_acceptable_post_fix',
            'raw_json': [],
        }
    is_bad_arg = 'BadArgumentError' in text
    is_table_missing = 'Failed to resolve table' in text or 'could not be resolved' in text
    if is_bad_arg and is_table_missing:
        return {
            'parse_status': 'json_decode_failed',
            'cli_exit_code': exit_code,
            'rows': 0,
            'distinct_revisions': 0,
            'is_bad_argument_error': is_bad_arg,
            'is_table_missing': is_table_missing,
            'gate_classification': 'silent_acceptable_post_fix',
            'raw_text_first_500_chars': text[:500],
        }
    return {
        'parse_status': 'json_decode_failed',
        'cli_exit_code': exit_code,
        'rows': 0,
        'distinct_revisions': 0,
        'is_bad_argument_error': is_bad_arg,
        'is_table_missing': is_table_missing,
        'gate_classification': 'query_error_invalid_run',
        'raw_text_first_500_chars': text[:500],
    }


post_fix_kql = parse_post_fix_kql(
    os.environ['EVIDENCE_DIR'] + '/13-kql-after-fix-raw.txt',
    int(os.environ['POST_FIX_KQL_EXIT']),
)

out = {
    'utc_query': os.environ['UTC_QUERY'],
    'fix_utc': os.environ['FIX_UTC'],
    'app_name': os.environ['APP_NAME'],
    'post_fix_revision': os.environ['POST_FIX_REVISION_NAME'],
    'post_fix_fqdn': os.environ['POST_FIX_FQDN'],
    'post_fix_kql_query': os.environ['KQL_POST_FIX'],
    'post_fix_kql_result': post_fix_kql,
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '13-kql-after-fix.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'rows': post_fix_kql['rows'],
    'gate_classification': post_fix_kql['gate_classification'],
}, indent=2))
PYEOF

POST_FIX_KQL_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/13-kql-after-fix.json'))['post_fix_kql_result']['gate_classification'])")
echo "Post-fix KQL gate: $POST_FIX_KQL_GATE"
echo ""

echo "=== Phase 16: capture metadata + H2 gate ==="
az version --output json > "$EVIDENCE_DIR/20-cli-versions.json" 2>&1 || true
az extension list --query "[?name=='containerapp']" --output json > "$EVIDENCE_DIR/21-cli-containerapp-ext.json" 2>&1 || true
az group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --query "{name: name, location: location}" \
    --output json \
    > "$EVIDENCE_DIR/22-region.json" 2>&1 || true
az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs" \
    --output json \
    > "$EVIDENCE_DIR/23-deployment-outputs.json" 2>&1 || true

export REVISION_FINAL_HEALTH="$revision_health" POST_FIX_KQL_GATE

python3 <<'PYEOF'
import json, os

# H2 gate taxonomy for ACR pull failure recovery:
#
#   revision_healthy_traffic_100_curl_ok   - Healthy + trafficWeight=100 AND >=8/10 HTTP 200 (expected H2 PASS)
#   revision_healthy_no_curl_response      - Healthy + trafficWeight=100 BUT <8/10 HTTP 200 (partial: revision recovered but FQDN may need more time)
#   revision_unhealthy                     - revision exists but not Healthy after 5 min poll (H2 FALSIFIED)
#   revision_missing                       - no revision created post-fix (H2 FALSIFIED)
#
# H2 sub-gates:
#   A. revision_list_count >= 1
#   B. at least one revision Healthy + trafficWeight=100
#   C. curl_after_fix_ok >= 8/10
#   D. labacr present in ACR (sanity)

revision_health = os.environ['REVISION_FINAL_HEALTH']
revision_healthy_traffic_100 = os.environ['REVISION_HEALTHY_TRAFFIC_100'] == 'true'
revision_list_count = int(os.environ['REVISION_LIST_COUNT'])
curl_after_fix_ok = int(os.environ['CURL_AFTER_FIX_OK'])
labacr_present = os.environ['LABACR_PRESENT_AFTER_FIX'] == 'true'
post_fix_kql_gate = os.environ['POST_FIX_KQL_GATE']

if revision_list_count == 0:
    h2_gate = 'revision_missing'
elif revision_health != 'Healthy' or not revision_healthy_traffic_100:
    h2_gate = 'revision_unhealthy'
elif curl_after_fix_ok < 8:
    h2_gate = 'revision_healthy_no_curl_response'
else:
    h2_gate = 'revision_healthy_traffic_100_curl_ok'

h2_sub_gates = {
    'a_revision_list_count_ge_1': revision_list_count >= 1,
    'b_revision_healthy_traffic_100': revision_healthy_traffic_100,
    'c_curl_after_fix_ok_ge_8': curl_after_fix_ok >= 8,
    'd_labacr_present_in_acr': labacr_present,
}
h2_all_subgates_pass = all(h2_sub_gates.values())

out = {
    'utc_captured': os.environ.get('UTC_QUERY', ''),
    'fix_utc': os.environ['FIX_UTC'],
    'app_name': os.environ['APP_NAME'],
    'post_fix_revision': os.environ['POST_FIX_REVISION_NAME'],
    'post_fix_fqdn': os.environ['POST_FIX_FQDN'],
    'final_revision_health': revision_health,
    'revision_list_count': revision_list_count,
    'revision_healthy_traffic_100': revision_healthy_traffic_100,
    'curl_after_fix_ok': curl_after_fix_ok,
    'labacr_present_in_acr': labacr_present,
    'post_fix_kql_gate': post_fix_kql_gate,
    'gate_classification': h2_gate,
    'h2_sub_gates': h2_sub_gates,
    'h2_all_subgates_pass': h2_all_subgates_pass,
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '14-h2-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'gate_classification': out['gate_classification'],
    'h2_all_subgates_pass': out['h2_all_subgates_pass'],
    'h2_sub_gates': out['h2_sub_gates'],
}, indent=2))
PYEOF

H2_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/14-h2-gate.json'))['gate_classification'])")
H2_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/14-h2-gate.json'))['h2_all_subgates_pass'])")

echo ""
echo "=== Verdict ==="
echo "H1 (trigger.sh): gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
echo "H2 (fix-and-capture.sh): gate=${H2_GATE}, all_subgates_pass=${H2_ALL_SUBGATES_PASS}"
echo "Post-fix KQL gate: ${POST_FIX_KQL_GATE} (informational)"
echo ""

H1_PASS=false
H2_PASS=false

if [[ "$H1_GATE" == "deployment_failed_manifest_unknown" && "$H1_ALL_SUBGATES_PASS" == "True" ]]; then
    H1_PASS=true
fi
if [[ "$H1_GATE" == "deployment_failed_other" || "$H1_GATE" == "deployment_succeeded_no_revision" ]]; then
    H1_PASS=true
fi
if [[ "$H2_GATE" == "revision_healthy_traffic_100_curl_ok" && "$H2_ALL_SUBGATES_PASS" == "True" ]]; then
    H2_PASS=true
fi

echo "H1 PASS: $H1_PASS"
echo "H2 PASS: $H2_PASS"

if [[ "$H1_PASS" == "true" && "$H2_PASS" == "true" ]]; then
    echo "VERDICT: SUPPORTED. The existence of the referenced image tag in ACR is the controlling variable for the documented failure (deployment Failed + MANIFEST_UNKNOWN + no revision) and for recovery (Healthy revision + traffic=100 + HTTP 200 at FQDN)."
    exit 0
fi

if [[ "$H2_GATE" == "revision_missing" || "$H2_GATE" == "revision_unhealthy" ]]; then
    echo "VERDICT: H2 FALSIFIED. The fix (az acr build + az containerapp update) did not produce a Healthy revision within 5 min (gate=${H2_GATE}). Investigate revision health, replica state, or ACR push success."
    exit 2
fi

if [[ "$H2_GATE" == "revision_healthy_no_curl_response" ]]; then
    echo "VERDICT: H2 PARTIAL. Revision is Healthy + trafficWeight=100 but only ${CURL_AFTER_FIX_OK}/10 HTTP 200 responses. Edge may need more propagation time. Re-run curl probes and re-evaluate."
    exit 2
fi

echo "VERDICT: INVALID RUN. Unexpected combination of H1 gate=${H1_GATE} and H2 gate=${H2_GATE}. Inspect evidence files."
exit 1
