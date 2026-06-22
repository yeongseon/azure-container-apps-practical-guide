#!/usr/bin/env bash
set -euo pipefail

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${APP_FQDN:?Set APP_FQDN before running}"
: "${ENV_NAME:?Set ENV_NAME before running}"
: "${WORKSPACE_CUSTOMER_ID:?Set WORKSPACE_CUSTOMER_ID before running (the LAW guid, not the resource ID)}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "trigger.sh starting at ${UTC_NOW}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "Env: ${ENV_NAME}"
echo "FQDN: ${APP_FQDN}"
echo "Workspace customer id: ${WORKSPACE_CUSTOMER_ID}"
echo ""

echo "=== Phase 1: env appLogsConfiguration (expect destination=null) ==="
az containerapp env show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$ENV_NAME" \
    --query "properties.appLogsConfiguration" \
    --output json \
    > "$EVIDENCE_DIR/01-env-config-before.json"
cat "$EVIDENCE_DIR/01-env-config-before.json"
echo ""

DEST_BEFORE=$(python3 -c "import json,sys; d=json.load(open('$EVIDENCE_DIR/01-env-config-before.json')); print(d.get('destination') if d else 'null')")
if [[ "$DEST_BEFORE" != "null" && "$DEST_BEFORE" != "None" ]]; then
    echo "INVALID RUN: env destination is '$DEST_BEFORE' but lab expects null. The Bicep deploy did not produce the documented baseline state."
    exit 1
fi

echo "=== Phase 2: app configuration + active revision ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{name: name, latestRevisionName: properties.latestRevisionName, fqdn: properties.configuration.ingress.fqdn, minReplicas: properties.template.scale.minReplicas, maxReplicas: properties.template.scale.maxReplicas}" \
    --output json \
    > "$EVIDENCE_DIR/02-app-config-before.json"
cat "$EVIDENCE_DIR/02-app-config-before.json"
echo ""

REVISION_BEFORE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/02-app-config-before.json'))['latestRevisionName'])")
echo "Baseline revision: $REVISION_BEFORE"
echo ""

echo "=== Phase 3: send 10 HTTP requests to baseline revision ==="
python3 -c "
import json, sys, urllib.request, time
fqdn = '$APP_FQDN'
results = []
for i in range(10):
    t0 = time.time()
    try:
        with urllib.request.urlopen(f'https://{fqdn}/', timeout=10) as r:
            results.append({'i': i, 'status': r.status, 'elapsed_ms': round((time.time()-t0)*1000, 1)})
    except Exception as e:
        results.append({'i': i, 'status': 'error', 'error': str(e), 'elapsed_ms': round((time.time()-t0)*1000, 1)})
    time.sleep(0.5)
ok = sum(1 for r in results if r.get('status') == 200)
out = {'baseline_revision': '$REVISION_BEFORE', 'requests_sent': 10, 'requests_ok': ok, 'utc_completed': '$(date -u +%Y-%m-%dT%H:%M:%SZ)', 'samples': results}
json.dump(out, open('$EVIDENCE_DIR/03-curl-before.json', 'w'), indent=2)
print(f'Sent 10 requests, {ok}/10 ok')
"
echo ""

WAIT_SECONDS=300
echo "=== Phase 4: wait ${WAIT_SECONDS}s for any potential log ingestion lag ==="
sleep "$WAIT_SECONDS"
echo "Wait complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

echo "=== Phase 5: KQL ContainerAppConsoleLogs_CL + ContainerAppSystemLogs_CL (expect 0 rows or BadArgumentError if tables not yet materialized) ==="

KQL_CONSOLE="ContainerAppConsoleLogs_CL | where ContainerAppName_s == '${APP_NAME}' | summarize rows=count(), distinct_revisions=dcount(RevisionName_s)"
KQL_SYSTEM="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | summarize rows=count(), distinct_revisions=dcount(RevisionName_s)"

set +e
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_CONSOLE" \
    --output json \
    > "$EVIDENCE_DIR/04-kql-before-console-raw.txt" 2>&1
CONSOLE_EXIT=$?
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_SYSTEM" \
    --output json \
    > "$EVIDENCE_DIR/04-kql-before-system-raw.txt" 2>&1
SYSTEM_EXIT=$?
set -e

CONSOLE_OUT_FILE="$EVIDENCE_DIR/04-kql-before-console-raw.txt"
SYSTEM_OUT_FILE="$EVIDENCE_DIR/04-kql-before-system-raw.txt"

UTC_QUERY="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
APP_NAME_LITERAL="$APP_NAME"
export CONSOLE_OUT_FILE SYSTEM_OUT_FILE UTC_QUERY APP_NAME_LITERAL CONSOLE_EXIT SYSTEM_EXIT KQL_CONSOLE KQL_SYSTEM EVIDENCE_DIR

python3 <<'PYEOF'
import json, os
def parse(path, exit_code):
    with open(path) as f:
        text = f.read()
    parsed = None
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        pass
    if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict):
        try:
            rows_int = int(parsed[0].get('rows', 0))
        except (TypeError, ValueError):
            rows_int = 0
        return {
            'parse_status': 'parsed_json_with_rows',
            'cli_exit_code': exit_code,
            'rows': parsed[0].get('rows', 0),
            'distinct_revisions': parsed[0].get('distinct_revisions', 0),
            'gate_classification': 'silent_valid_baseline' if rows_int == 0 else 'populated_table',
            'raw_json': parsed,
        }
    if isinstance(parsed, list) and not parsed:
        return {
            'parse_status': 'parsed_empty_list',
            'cli_exit_code': exit_code,
            'rows': 0,
            'distinct_revisions': 0,
            'gate_classification': 'silent_valid_baseline',
            'raw_json': [],
        }
    is_bad_arg = 'BadArgumentError' in text
    is_table_missing = "Failed to resolve table" in text or "could not be resolved" in text
    if is_bad_arg and is_table_missing:
        gate_classification = 'silent_valid_baseline'
    else:
        gate_classification = 'query_error_invalid_run'
    return {
        'parse_status': 'json_decode_failed',
        'cli_exit_code': exit_code,
        'rows': 0,
        'distinct_revisions': 0,
        'is_bad_argument_error': is_bad_arg,
        'is_table_missing': is_table_missing,
        'gate_classification': gate_classification,
        'raw_text_first_500_chars': text[:500],
    }

console = parse(os.environ['CONSOLE_OUT_FILE'], int(os.environ['CONSOLE_EXIT']))
system  = parse(os.environ['SYSTEM_OUT_FILE'], int(os.environ['SYSTEM_EXIT']))
out = {
    'utc_query': os.environ['UTC_QUERY'],
    'app_name': os.environ['APP_NAME_LITERAL'],
    'console_query': os.environ['KQL_CONSOLE'],
    'system_query': os.environ['KQL_SYSTEM'],
    'console_result': console,
    'system_result': system,
    'console_rows': console['rows'],
    'system_rows': system['rows'],
    'console_gate_classification': console['gate_classification'],
    'system_gate_classification': system['gate_classification'],
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '04-kql-before.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'console_rows': out['console_rows'],
    'system_rows': out['system_rows'],
    'console_parse_status': console['parse_status'],
    'system_parse_status': system['parse_status'],
    'console_gate_classification': console['gate_classification'],
    'system_gate_classification': system['gate_classification'],
}, indent=2))
PYEOF

CONSOLE_ROWS_BEFORE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/04-kql-before.json'))['console_rows'])")
SYSTEM_ROWS_BEFORE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/04-kql-before.json'))['system_rows'])")
CONSOLE_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/04-kql-before.json'))['console_gate_classification'])")
SYSTEM_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/04-kql-before.json'))['system_gate_classification'])")

echo ""
echo "=== Baseline summary ==="
echo "Env appLogsConfiguration.destination: $DEST_BEFORE"
echo "ContainerAppConsoleLogs_CL: rows=$CONSOLE_ROWS_BEFORE gate=$CONSOLE_GATE"
echo "ContainerAppSystemLogs_CL: rows=$SYSTEM_ROWS_BEFORE gate=$SYSTEM_GATE"

if [[ "$CONSOLE_GATE" == "query_error_invalid_run" || "$SYSTEM_GATE" == "query_error_invalid_run" ]]; then
    echo "INVALID RUN: KQL query produced an unexpected error (not valid JSON, and not the expected BadArgumentError + 'Failed to resolve table' signature)."
    echo "Inspect 04-kql-before-console-raw.txt and 04-kql-before-system-raw.txt for the actual error."
    exit 1
fi

if [[ "$CONSOLE_GATE" == "populated_table" || "$SYSTEM_GATE" == "populated_table" ]]; then
    echo "H1 FALSIFIED: rows present in Log Analytics despite env destination=null."
    echo "This contradicts the expected baseline. INVALID RUN."
    exit 1
fi

echo ""
echo "H1 PASS (baseline): both *_CL tables classified silent_valid_baseline with destination=null. Proceed to verify.sh."
exit 0
