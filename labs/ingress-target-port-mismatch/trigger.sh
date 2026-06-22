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
echo "trigger.sh starting at ${UTC_NOW}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "FQDN: ${APP_FQDN}"
echo "Workspace customer id: ${WORKSPACE_CUSTOMER_ID}"
echo ""

echo "=== Phase 1: pre-trigger ingress configuration (expect targetPort=80, external=true) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{name: name, latestRevisionName: properties.latestRevisionName, ingress: properties.configuration.ingress}" \
    --output json \
    > "$EVIDENCE_DIR/01-ingress-config-before.json"
cat "$EVIDENCE_DIR/01-ingress-config-before.json"
echo ""

TARGET_PORT_BEFORE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/01-ingress-config-before.json'))['ingress']['targetPort'])")
REVISION_BEFORE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/01-ingress-config-before.json'))['latestRevisionName'])")
EXTERNAL_BEFORE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/01-ingress-config-before.json'))['ingress']['external'])")

if [[ "$TARGET_PORT_BEFORE" != "80" || "$EXTERNAL_BEFORE" != "True" ]]; then
    echo "INVALID RUN: baseline expected targetPort=80 external=true, got targetPort=${TARGET_PORT_BEFORE} external=${EXTERNAL_BEFORE}."
    exit 1
fi
echo "Baseline revision: $REVISION_BEFORE"
echo ""

echo "=== Phase 2: pre-trigger replica list (expect replicas Running) ==="
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, runningState: properties.runningState, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/02-replicas-before.json"
cat "$EVIDENCE_DIR/02-replicas-before.json"
echo ""

echo "=== Phase 3: send 10 HTTP requests to baseline (expect all 200) ==="
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
out = {'baseline_revision': '$REVISION_BEFORE', 'requests_sent': 10, 'requests_ok': ok, 'utc_completed': '$(date -u +%Y-%m-%dT%H:%M:%SZ)', 'samples': results}
json.dump(out, open('$EVIDENCE_DIR/03-curl-before.json', 'w'), indent=2)
print(f'Sent 10 requests, {ok}/10 ok')
"
echo ""

CURL_BEFORE_OK=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/03-curl-before.json'))['requests_ok'])")
if [[ "$CURL_BEFORE_OK" -lt 8 ]]; then
    echo "INVALID RUN: baseline expected at least 8/10 HTTP 200, got ${CURL_BEFORE_OK}/10. Baseline state did not hold."
    exit 1
fi

echo "=== Phase 4: apply trigger (az containerapp ingress update --target-port 8081) ==="
TRIGGER_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Trigger UTC: $TRIGGER_UTC"
az containerapp ingress update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --target-port 8081 \
    --query "{external: external, targetPort: targetPort, transport: transport, fqdn: fqdn}" \
    --output json \
    > "$EVIDENCE_DIR/04-ingress-update-result.json"
cat "$EVIDENCE_DIR/04-ingress-update-result.json"
echo ""

echo "=== Phase 5: post-trigger ingress configuration (expect targetPort=8081) ==="
sleep 5
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{name: name, latestRevisionName: properties.latestRevisionName, ingress: properties.configuration.ingress}" \
    --output json \
    > "$EVIDENCE_DIR/05-ingress-config-after-trigger.json"
cat "$EVIDENCE_DIR/05-ingress-config-after-trigger.json"
echo ""

TARGET_PORT_AFTER_TRIGGER=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/05-ingress-config-after-trigger.json'))['ingress']['targetPort'])")
REVISION_AFTER_TRIGGER=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/05-ingress-config-after-trigger.json'))['latestRevisionName'])")

if [[ "$TARGET_PORT_AFTER_TRIGGER" != "8081" ]]; then
    echo "INVALID RUN: post-trigger expected targetPort=8081, got ${TARGET_PORT_AFTER_TRIGGER}."
    exit 1
fi

if [[ "$REVISION_AFTER_TRIGGER" != "$REVISION_BEFORE" ]]; then
    echo "NOTE: revision name changed across the ingress update (${REVISION_BEFORE} -> ${REVISION_AFTER_TRIGGER}). This is unexpected because ingress is documented as application-scope (does not create new revisions). Continuing, but this is worth investigating."
fi

echo "=== Phase 6: wait 60s for ingress propagation + first probe failures to land ==="
sleep 60
echo "Wait complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

echo "=== Phase 7: post-trigger replica list (replicas should still be Running; revision health flipped) ==="
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, runningState: properties.runningState, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/06-replicas-after-trigger.json"
cat "$EVIDENCE_DIR/06-replicas-after-trigger.json"
echo ""

az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision "$REVISION_AFTER_TRIGGER" \
    --query "{name: name, runningState: properties.runningState, healthState: properties.healthState, replicas: properties.replicas, trafficWeight: properties.trafficWeight}" \
    --output json \
    > "$EVIDENCE_DIR/07-revision-status-after-trigger.json"
cat "$EVIDENCE_DIR/07-revision-status-after-trigger.json"
echo ""

echo "=== Phase 8: send 10 HTTP requests to triggered state (expect mostly non-200) ==="
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
err = sum(1 for r in results if r.get('status') != 200)
out = {'triggered_revision': '$REVISION_AFTER_TRIGGER', 'requests_sent': 10, 'requests_ok': ok, 'requests_non_200': err, 'utc_completed': '$(date -u +%Y-%m-%dT%H:%M:%SZ)', 'samples': results}
json.dump(out, open('$EVIDENCE_DIR/08-curl-after-trigger.json', 'w'), indent=2)
print(f'Sent 10 requests, {ok}/10 ok, {err}/10 non-200')
"
echo ""

CURL_AFTER_TRIGGER_OK=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-curl-after-trigger.json'))['requests_ok'])")

WAIT_SECONDS=300
echo "=== Phase 9: wait ${WAIT_SECONDS}s for system log ingestion ==="
sleep "$WAIT_SECONDS"
echo "Wait complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

echo "=== Phase 10: KQL ContainerAppSystemLogs_CL port-mismatch detection (expect >=1 PortMismatch row) ==="
KQL_SYSTEM_PORTMISMATCH="ContainerAppSystemLogs_CL | where TimeGenerated > datetime(${TRIGGER_UTC}) | where ContainerAppName_s == '${APP_NAME}' | where Reason_s == 'Pending:PortMismatch' or Reason_s contains 'TargetPort' or Log_s contains 'TargetPort' or Reason_s == 'ProbeFailed' | summarize rows=count(), portmismatch_rows=countif(Reason_s == 'Pending:PortMismatch' or Log_s contains 'TargetPort'), probefailed_rows=countif(Reason_s == 'ProbeFailed'), distinct_revisions=dcount(RevisionName_s)"
KQL_SYSTEM_SAMPLE="ContainerAppSystemLogs_CL | where TimeGenerated > datetime(${TRIGGER_UTC}) | where ContainerAppName_s == '${APP_NAME}' | where Reason_s == 'Pending:PortMismatch' or Log_s contains 'TargetPort' | project TimeGenerated, RevisionName_s, ReplicaName_s, Reason_s, Type_s, Log_s | order by TimeGenerated desc | take 5"

set +e
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_SYSTEM_PORTMISMATCH" \
    --output json \
    > "$EVIDENCE_DIR/09-kql-after-trigger-portmismatch-raw.txt" 2>&1
SYSTEM_EXIT=$?

az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_SYSTEM_SAMPLE" \
    --output json \
    > "$EVIDENCE_DIR/09-kql-after-trigger-portmismatch-sample-raw.txt" 2>&1
SAMPLE_EXIT=$?
set -e

UTC_QUERY="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR UTC_QUERY APP_NAME REVISION_AFTER_TRIGGER TRIGGER_UTC KQL_SYSTEM_PORTMISMATCH KQL_SYSTEM_SAMPLE SYSTEM_EXIT SAMPLE_EXIT CURL_BEFORE_OK CURL_AFTER_TRIGGER_OK

python3 <<'PYEOF'
import json, os

# Phase-aware 3-state gate taxonomy:
#   populated_table        - >=1 PortMismatch row attributed by the platform
#   silent_valid_baseline  - 0 PortMismatch rows AND we are in the post-fix phase (silence is expected and means the fix held)
#   silent_failure         - 0 PortMismatch rows AND we are in the post-trigger phase (silence is the wrong outcome — trigger did not produce attribution within the ingestion window)
#   query_error_invalid_run- KQL CLI returned an unexpected error signature that cannot be parsed as either "no rows" or "with rows"
#
# This script runs the post-TRIGGER query, so zero rows here is silent_failure, not silent_valid_baseline.

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


system_summarize = parse_summarize(os.environ['EVIDENCE_DIR'] + '/09-kql-after-trigger-portmismatch-raw.txt', int(os.environ['SYSTEM_EXIT']), phase='trigger')
system_sample = parse_sample(os.environ['EVIDENCE_DIR'] + '/09-kql-after-trigger-portmismatch-sample-raw.txt', int(os.environ['SAMPLE_EXIT']))

out = {
    'utc_query': os.environ['UTC_QUERY'],
    'trigger_utc': os.environ['TRIGGER_UTC'],
    'app_name': os.environ['APP_NAME'],
    'triggered_revision': os.environ['REVISION_AFTER_TRIGGER'],
    'system_portmismatch_query': os.environ['KQL_SYSTEM_PORTMISMATCH'],
    'system_portmismatch_sample_query': os.environ['KQL_SYSTEM_SAMPLE'],
    'system_portmismatch_result': system_summarize,
    'system_portmismatch_sample': system_sample,
    'portmismatch_rows': system_summarize['portmismatch_rows'],
    'probefailed_rows': system_summarize['probefailed_rows'],
    'gate_classification': system_summarize['gate_classification'],
    'curl_before_ok': int(os.environ['CURL_BEFORE_OK']),
    'curl_after_trigger_ok': int(os.environ['CURL_AFTER_TRIGGER_OK']),
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '09-kql-after-trigger.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'portmismatch_rows': out['portmismatch_rows'],
    'probefailed_rows': out['probefailed_rows'],
    'gate_classification': out['gate_classification'],
    'sample_row_count': system_sample.get('sample_row_count', 0),
}, indent=2))
PYEOF

PORTMISMATCH_ROWS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/09-kql-after-trigger.json'))['portmismatch_rows'])")
PROBE_ROWS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/09-kql-after-trigger.json'))['probefailed_rows'])")
SYSTEM_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/09-kql-after-trigger.json'))['gate_classification'])")

echo ""
echo "=== H1 summary ==="
echo "Baseline curl (pre-trigger): ${CURL_BEFORE_OK}/10 HTTP 200"
echo "Triggered curl (post-trigger, targetPort=8081): ${CURL_AFTER_TRIGGER_OK}/10 HTTP 200"
echo "ContainerAppSystemLogs_CL PortMismatch rows in post-trigger window: $PORTMISMATCH_ROWS"
echo "ContainerAppSystemLogs_CL ProbeFailed rows in post-trigger window: $PROBE_ROWS"
echo "Gate classification: $SYSTEM_GATE"
echo ""

if [[ "$SYSTEM_GATE" == "query_error_invalid_run" ]]; then
    echo "INVALID RUN: KQL query produced an unexpected error (not valid JSON, and not the expected BadArgumentError + 'Failed to resolve table' signature)."
    echo "Inspect 09-kql-after-trigger-portmismatch-raw.txt for the actual error."
    exit 1
fi

H1_CURL_PASS=false
H1_KQL_PASS=false

if [[ "$CURL_AFTER_TRIGGER_OK" -le 1 ]]; then
    H1_CURL_PASS=true
fi
if [[ "$PORTMISMATCH_ROWS" -ge 1 ]]; then
    H1_KQL_PASS=true
fi

echo "H1 sub-gate A (post-trigger curl <=1/10 HTTP 200): $H1_CURL_PASS"
echo "H1 sub-gate B (>=1 PortMismatch row in post-trigger window): $H1_KQL_PASS"

if [[ "$H1_CURL_PASS" == "true" && "$H1_KQL_PASS" == "true" ]]; then
    echo "H1 PASS: trigger produced the documented failure signature (edge non-200 + PortMismatch row in system logs). Proceed to verify.sh."
    exit 0
fi

if [[ "$H1_CURL_PASS" == "false" ]]; then
    echo "H1 FALSIFIED (sub-gate A): post-trigger curl still returned ${CURL_AFTER_TRIGGER_OK}/10 HTTP 200 despite targetPort=8081. The lab cannot proceed because the failure state did not materialize."
    exit 2
fi

echo "H1 FALSIFIED (sub-gate B): post-trigger curl is non-200 as expected, but no PortMismatch row appeared in ContainerAppSystemLogs_CL within the 300s ingestion window (gate_classification=${SYSTEM_GATE}, expected populated_table). The platform may have suppressed the system log or ingestion is delayed beyond 300s; re-run with a longer wait or investigate."
exit 2
