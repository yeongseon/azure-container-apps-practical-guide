#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${APP_FQDN:?Set APP_FQDN before running}"
: "${WORKSPACE_CUSTOMER_ID:?Set WORKSPACE_CUSTOMER_ID before running (the LAW guid, not the resource ID)}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "verify.sh starting at ${UTC_NOW}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "FQDN: ${APP_FQDN}"
echo ""

TRIGGER_FILE="$EVIDENCE_DIR/09-kql-after-trigger.json"
if [[ ! -f "$TRIGGER_FILE" ]]; then
    echo "INVALID RUN: $TRIGGER_FILE not found. Run trigger.sh first."
    exit 1
fi
PORTMISMATCH_ROWS_TRIGGER=$(python3 -c "import json; print(json.load(open('$TRIGGER_FILE'))['portmismatch_rows'])")
GATE_TRIGGER=$(python3 -c "import json; print(json.load(open('$TRIGGER_FILE'))['gate_classification'])")
CURL_BEFORE_OK=$(python3 -c "import json; print(json.load(open('$TRIGGER_FILE'))['curl_before_ok'])")
CURL_AFTER_TRIGGER_OK=$(python3 -c "import json; print(json.load(open('$TRIGGER_FILE'))['curl_after_trigger_ok'])")
TRIGGERED_REVISION=$(python3 -c "import json; print(json.load(open('$TRIGGER_FILE'))['triggered_revision'])")
echo "Triggered state: PortMismatch rows=${PORTMISMATCH_ROWS_TRIGGER}, gate=${GATE_TRIGGER}, curl pre/post=${CURL_BEFORE_OK}/${CURL_AFTER_TRIGGER_OK}"
echo "Triggered revision: ${TRIGGERED_REVISION}"
echo ""

echo "=== Phase 11: apply fix (az containerapp ingress update --target-port 80) ==="
FIX_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Fix UTC: $FIX_UTC"
az containerapp ingress update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --target-port 80 \
    --query "{external: external, targetPort: targetPort, transport: transport, fqdn: fqdn}" \
    --output json \
    > "$EVIDENCE_DIR/10-ingress-update-fix-result.json"
cat "$EVIDENCE_DIR/10-ingress-update-fix-result.json"
echo ""

echo "=== Phase 12: post-fix ingress configuration (expect targetPort=80) ==="
sleep 5
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{name: name, latestRevisionName: properties.latestRevisionName, ingress: properties.configuration.ingress}" \
    --output json \
    > "$EVIDENCE_DIR/11-ingress-config-after-fix.json"
cat "$EVIDENCE_DIR/11-ingress-config-after-fix.json"
echo ""

TARGET_PORT_AFTER_FIX=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/11-ingress-config-after-fix.json'))['ingress']['targetPort'])")
REVISION_AFTER_FIX=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/11-ingress-config-after-fix.json'))['latestRevisionName'])")

if [[ "$TARGET_PORT_AFTER_FIX" != "80" ]]; then
    echo "INVALID RUN: post-fix expected targetPort=80, got ${TARGET_PORT_AFTER_FIX}."
    exit 1
fi

if [[ "$REVISION_AFTER_FIX" != "$TRIGGERED_REVISION" ]]; then
    echo "NOTE: revision name changed across the fix (${TRIGGERED_REVISION} -> ${REVISION_AFTER_FIX}). This is unexpected because ingress is documented as application-scope (does not create new revisions). Continuing, but this is worth investigating."
fi

echo "=== Phase 13: wait 30s for ingress propagation ==="
sleep 30
echo "Wait complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

echo "=== Phase 14: post-fix replica list + revision status (expect Running) ==="
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, runningState: properties.runningState, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/12-replicas-after-fix.json"
cat "$EVIDENCE_DIR/12-replicas-after-fix.json"
echo ""

az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision "$REVISION_AFTER_FIX" \
    --query "{name: name, runningState: properties.runningState, healthState: properties.healthState, replicas: properties.replicas, trafficWeight: properties.trafficWeight}" \
    --output json \
    > "$EVIDENCE_DIR/13-revision-status-after-fix.json"
cat "$EVIDENCE_DIR/13-revision-status-after-fix.json"
echo ""

echo "=== Phase 15: send 10 HTTP requests post-fix (expect all 200) ==="
python3 -c "
import json, urllib.request, time
fqdn = '$APP_FQDN'
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
out = {'post_fix_revision': '$REVISION_AFTER_FIX', 'requests_sent': 10, 'requests_ok': ok, 'utc_completed': '$(date -u +%Y-%m-%dT%H:%M:%SZ)', 'samples': results}
json.dump(out, open('$EVIDENCE_DIR/14-curl-after-fix.json', 'w'), indent=2)
print(f'Sent 10 requests, {ok}/10 ok')
"
echo ""

CURL_AFTER_FIX_OK=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/14-curl-after-fix.json'))['requests_ok'])")

WAIT_SECONDS=300
echo "=== Phase 16: wait ${WAIT_SECONDS}s for any final probe-failure events to land ==="
sleep "$WAIT_SECONDS"
echo "Wait complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

echo "=== Phase 17: KQL ContainerAppSystemLogs_CL port-mismatch detection in post-fix window (expect 0 PortMismatch rows) ==="
KQL_POST_FIX="ContainerAppSystemLogs_CL | where TimeGenerated > datetime(${FIX_UTC}) | where ContainerAppName_s == '${APP_NAME}' | where Reason_s == 'Pending:PortMismatch' or Reason_s contains 'TargetPort' or Log_s contains 'TargetPort' or Reason_s == 'ProbeFailed' | summarize rows=count(), portmismatch_rows=countif(Reason_s == 'Pending:PortMismatch' or Log_s contains 'TargetPort'), probefailed_rows=countif(Reason_s == 'ProbeFailed'), distinct_revisions=dcount(RevisionName_s)"
KQL_POST_FIX_SAMPLE="ContainerAppSystemLogs_CL | where TimeGenerated > datetime(${FIX_UTC}) | where ContainerAppName_s == '${APP_NAME}' | where Reason_s == 'Pending:PortMismatch' or Log_s contains 'TargetPort' | project TimeGenerated, RevisionName_s, ReplicaName_s, Reason_s, Type_s, Log_s | order by TimeGenerated desc | take 5"

set +e
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_POST_FIX" \
    --output json \
    > "$EVIDENCE_DIR/15-kql-after-fix-portmismatch-raw.txt" 2>&1
POST_FIX_EXIT=$?

az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_POST_FIX_SAMPLE" \
    --output json \
    > "$EVIDENCE_DIR/15-kql-after-fix-portmismatch-sample-raw.txt" 2>&1
POST_FIX_SAMPLE_EXIT=$?
set -e

UTC_QUERY="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR UTC_QUERY APP_NAME REVISION_AFTER_FIX FIX_UTC KQL_POST_FIX KQL_POST_FIX_SAMPLE POST_FIX_EXIT POST_FIX_SAMPLE_EXIT CURL_AFTER_FIX_OK TRIGGER_FILE

python3 <<'PYEOF'
import json, os

# Phase-aware 3-state gate taxonomy (kept in sync with trigger.sh):
#   populated_table        - >=1 PortMismatch row attributed by the platform (means the fix did NOT hold if seen here)
#   silent_valid_baseline  - 0 PortMismatch rows AND we are in the post-fix phase (silence is expected and means the fix held)
#   silent_failure         - 0 PortMismatch rows AND we are in the post-trigger phase (not used by this script; trigger.sh uses it)
#   query_error_invalid_run- KQL CLI returned an unexpected error signature that cannot be parsed as either "no rows" or "with rows"
#
# This script runs the post-FIX query, so zero rows here is silent_valid_baseline.

def parse_summarize(path, exit_code, phase):
    silent_label = 'silent_valid_baseline' if phase == 'verify' else 'silent_failure'
    with open(path) as f:
        text = f.read()
    parsed = None
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        pass
    if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict):
        try:
            portmismatch_rows = int(parsed[0].get('portmismatch_rows', 0))
        except (TypeError, ValueError):
            portmismatch_rows = 0
        if portmismatch_rows >= 1:
            gate = 'populated_table'
        else:
            gate = silent_label
        return {
            'parse_status': 'parsed_json_with_rows',
            'cli_exit_code': exit_code,
            'rows': parsed[0].get('rows', 0),
            'portmismatch_rows': parsed[0].get('portmismatch_rows', 0),
            'probefailed_rows': parsed[0].get('probefailed_rows', 0),
            'distinct_revisions': parsed[0].get('distinct_revisions', 0),
            'gate_classification': gate,
            'raw_json': parsed,
        }
    if isinstance(parsed, list) and not parsed:
        return {
            'parse_status': 'parsed_empty_list',
            'cli_exit_code': exit_code,
            'rows': 0,
            'portmismatch_rows': 0,
            'probefailed_rows': 0,
            'distinct_revisions': 0,
            'gate_classification': silent_label,
            'raw_json': [],
        }
    is_bad_arg = 'BadArgumentError' in text
    is_table_missing = 'Failed to resolve table' in text or 'could not be resolved' in text
    if is_bad_arg and is_table_missing:
        gate_classification = silent_label
    else:
        gate_classification = 'query_error_invalid_run'
    return {
        'parse_status': 'json_decode_failed',
        'cli_exit_code': exit_code,
        'rows': 0,
        'portmismatch_rows': 0,
        'probefailed_rows': 0,
        'is_bad_argument_error': is_bad_arg,
        'is_table_missing': is_table_missing,
        'gate_classification': gate_classification,
        'raw_text_first_500_chars': text[:500],
    }
    if isinstance(parsed, list) and not parsed:
        return {
            'parse_status': 'parsed_empty_list',
            'cli_exit_code': exit_code,
            'rows': 0,
            'portmismatch_rows': 0,
            'probefailed_rows': 0,
            'distinct_revisions': 0,
            'gate_classification': 'silent_valid_baseline',
            'raw_json': [],
        }
    is_bad_arg = 'BadArgumentError' in text
    is_table_missing = 'Failed to resolve table' in text or 'could not be resolved' in text
    if is_bad_arg and is_table_missing:
        gate_classification = 'silent_valid_baseline'
    else:
        gate_classification = 'query_error_invalid_run'
    return {
        'parse_status': 'json_decode_failed',
        'cli_exit_code': exit_code,
        'rows': 0,
        'portmismatch_rows': 0,
        'probefailed_rows': 0,
        'distinct_revisions': 0,
        'is_bad_argument_error': is_bad_arg,
        'is_table_missing': is_table_missing,
        'gate_classification': gate_classification,
        'raw_text_first_500_chars': text[:500],
    }


def parse_sample(path, exit_code):
    with open(path) as f:
        text = f.read()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = None
    if isinstance(parsed, list):
        return {
            'parse_status': 'parsed_json_list',
            'cli_exit_code': exit_code,
            'sample_row_count': len(parsed),
            'samples': parsed[:5],
        }
    return {
        'parse_status': 'json_decode_failed',
        'cli_exit_code': exit_code,
        'sample_row_count': 0,
        'raw_text_first_500_chars': text[:500],
    }


post_fix_summarize = parse_summarize(os.environ['EVIDENCE_DIR'] + '/15-kql-after-fix-portmismatch-raw.txt', int(os.environ['POST_FIX_EXIT']), phase='verify')
post_fix_sample = parse_sample(os.environ['EVIDENCE_DIR'] + '/15-kql-after-fix-portmismatch-sample-raw.txt', int(os.environ['POST_FIX_SAMPLE_EXIT']))

out = {
    'utc_query': os.environ['UTC_QUERY'],
    'fix_utc': os.environ['FIX_UTC'],
    'app_name': os.environ['APP_NAME'],
    'post_fix_revision': os.environ['REVISION_AFTER_FIX'],
    'system_portmismatch_query': os.environ['KQL_POST_FIX'],
    'system_portmismatch_sample_query': os.environ['KQL_POST_FIX_SAMPLE'],
    'system_portmismatch_result': post_fix_summarize,
    'system_portmismatch_sample': post_fix_sample,
    'portmismatch_rows': post_fix_summarize['portmismatch_rows'],
    'probefailed_rows': post_fix_summarize['probefailed_rows'],
    'gate_classification': post_fix_summarize['gate_classification'],
    'curl_after_fix_ok': int(os.environ['CURL_AFTER_FIX_OK']),
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '15-kql-after-fix.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'portmismatch_rows': out['portmismatch_rows'],
    'probefailed_rows': out['probefailed_rows'],
    'gate_classification': out['gate_classification'],
    'sample_row_count': post_fix_sample.get('sample_row_count', 0),
}, indent=2))
PYEOF

PORTMISMATCH_ROWS_AFTER_FIX=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/15-kql-after-fix.json'))['portmismatch_rows'])")
POST_FIX_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/15-kql-after-fix.json'))['gate_classification'])")

echo ""
echo "=== Verdict ==="
echo "BEFORE TRIGGER:   curl ${CURL_BEFORE_OK}/10 HTTP 200, KQL PortMismatch rows in post-trigger window=${PORTMISMATCH_ROWS_TRIGGER}, gate=${GATE_TRIGGER}"
echo "AFTER TRIGGER:    curl ${CURL_AFTER_TRIGGER_OK}/10 HTTP 200"
echo "AFTER FIX:        curl ${CURL_AFTER_FIX_OK}/10 HTTP 200, KQL PortMismatch rows in post-fix window=${PORTMISMATCH_ROWS_AFTER_FIX}, gate=${POST_FIX_GATE}"
echo ""

if [[ "$POST_FIX_GATE" == "query_error_invalid_run" ]]; then
    echo "VERDICT: INVALID RUN. Post-fix KQL produced an unexpected error (not valid JSON, and not the expected BadArgumentError + 'Failed to resolve table' signature)."
    echo "Inspect 15-kql-after-fix-portmismatch-raw.txt for the actual error."
    exit 1
fi

H1_PASS=false
H2_PASS=false

if [[ "$GATE_TRIGGER" == "populated_table" && "$CURL_AFTER_TRIGGER_OK" -le 1 ]]; then
    H1_PASS=true
fi
if [[ "$POST_FIX_GATE" == "silent_valid_baseline" && "$CURL_AFTER_FIX_OK" -ge 8 ]]; then
    H2_PASS=true
fi

echo "H1 (trigger produces failure: PortMismatch row populated_table + curl <=1/10 200): $H1_PASS"
echo "H2 (fix restores recovery: post-fix PortMismatch silent_valid_baseline + curl >=8/10 200): $H2_PASS"

if [[ "$H1_PASS" == "true" && "$H2_PASS" == "true" ]]; then
    echo "VERDICT: SUPPORTED. Ingress targetPort vs. container listening port is the controlling variable for the documented failure (HTTP 503 at the edge + PortMismatch row in ContainerAppSystemLogs_CL) and for recovery (HTTP 200 + post-fix window silent for PortMismatch)."
    exit 0
fi

if [[ "$H2_PASS" == "false" && "$CURL_AFTER_FIX_OK" -lt 8 ]]; then
    echo "VERDICT: H2 FALSIFIED. Edge did not recover to HTTP 200 within the post-fix window despite targetPort=80. Investigate ingress propagation or replica state."
    exit 2
fi

if [[ "$H2_PASS" == "false" && "$POST_FIX_GATE" == "populated_table" ]]; then
    echo "VERDICT: H2 FALSIFIED. PortMismatch rows continued to appear in ContainerAppSystemLogs_CL AFTER the fix UTC. The fix did not stop the platform mismatch attribution. Investigate."
    exit 2
fi

echo "VERDICT: INVALID RUN. Re-deploy and re-run."
exit 1
