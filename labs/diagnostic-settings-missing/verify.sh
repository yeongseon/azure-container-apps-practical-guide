#!/usr/bin/env bash
set -euo pipefail

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${APP_FQDN:?Set APP_FQDN before running}"
: "${ENV_NAME:?Set ENV_NAME before running}"
: "${WORKSPACE_RESOURCE_ID:?Set WORKSPACE_RESOURCE_ID before running (the full /subscriptions/.../workspaces/<name> id, used by az containerapp env update)}"
: "${WORKSPACE_CUSTOMER_ID:?Set WORKSPACE_CUSTOMER_ID before running (the LAW guid, used by az monitor log-analytics query)}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "verify.sh starting at ${UTC_NOW}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "Env: ${ENV_NAME}"
echo "FQDN: ${APP_FQDN}"
echo ""

BASELINE_FILE="$EVIDENCE_DIR/04-kql-before.json"
if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "INVALID RUN: $BASELINE_FILE not found. Run trigger.sh first."
    exit 1
fi
CONSOLE_ROWS_BEFORE=$(python3 -c "import json; print(json.load(open('$BASELINE_FILE'))['console_rows'])")
SYSTEM_ROWS_BEFORE=$(python3 -c "import json; print(json.load(open('$BASELINE_FILE'))['system_rows'])")
echo "Baseline console rows: $CONSOLE_ROWS_BEFORE"
echo "Baseline system rows:  $SYSTEM_ROWS_BEFORE"
echo ""

echo "=== Phase 6: az containerapp env update --logs-destination log-analytics ==="
WS_SHARED_KEY="$(az monitor log-analytics workspace get-shared-keys \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --workspace-name "$(basename "$WORKSPACE_RESOURCE_ID")" \
    --query "primarySharedKey" \
    --output tsv)"

az containerapp env update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$ENV_NAME" \
    --logs-destination log-analytics \
    --logs-workspace-id "$WORKSPACE_CUSTOMER_ID" \
    --logs-workspace-key "$WS_SHARED_KEY" \
    --query "{name: name, provisioningState: properties.provisioningState, destination: properties.appLogsConfiguration.destination}" \
    --output json \
    > "$EVIDENCE_DIR/05-env-update-result.json"
cat "$EVIDENCE_DIR/05-env-update-result.json"
echo ""

echo "=== Phase 7: env config readback (expect destination=log-analytics) ==="
sleep 10
az containerapp env show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$ENV_NAME" \
    --query "properties.appLogsConfiguration" \
    --output json \
    > "$EVIDENCE_DIR/06-env-config-after.json"
cat "$EVIDENCE_DIR/06-env-config-after.json"
echo ""

DEST_AFTER=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/06-env-config-after.json')); print(d.get('destination', 'null'))")
if [[ "$DEST_AFTER" != "log-analytics" ]]; then
    echo "INVALID RUN: env destination is '$DEST_AFTER' after update; expected 'log-analytics'."
    exit 1
fi

echo "=== Phase 8: force new revision via env-var update (FIXAPPLIED nonce) ==="
FIX_NONCE=$(date -u +%Y%m%dT%H%M%SZ)
az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --set-env-vars "FIXAPPLIED=${FIX_NONCE}" \
    --output none

sleep 5

echo "=== Phase 9: wait for new revision to reach Running ==="
NEW_REVISION=""
for attempt in $(seq 1 30); do
    REV_JSON=$(az containerapp revision list \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --query "sort_by([], &properties.createdTime)[-1]" \
        --output json)
    NEW_REVISION=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('name',''))" <<< "$REV_JSON")
    RUNNING_STATE=$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('properties',{}).get('runningState',''))" <<< "$REV_JSON")
    echo "attempt=$attempt revision=$NEW_REVISION runningState=$RUNNING_STATE"
    if [[ "$RUNNING_STATE" == "Running" || "$RUNNING_STATE" == "RunningAtMaxScale" ]]; then
        break
    fi
    sleep 10
done

az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, runningState: properties.runningState, trafficWeight: properties.trafficWeight, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/07-revisions-after.json"
cat "$EVIDENCE_DIR/07-revisions-after.json"
echo ""

if [[ -z "$NEW_REVISION" ]]; then
    echo "INVALID RUN: no new revision detected after env-var update."
    exit 1
fi

echo "=== Phase 10: send 10 HTTP requests to new revision ==="
sleep 5
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
out = {'post_fix_revision': '$NEW_REVISION', 'requests_sent': 10, 'requests_ok': ok, 'utc_completed': '$(date -u +%Y-%m-%dT%H:%M:%SZ)', 'samples': results}
json.dump(out, open('$EVIDENCE_DIR/08-curl-after.json','w'), indent=2)
print(f'Sent 10 requests, {ok}/10 ok')
"
echo ""

WAIT_SECONDS=300
echo "=== Phase 11: wait ${WAIT_SECONDS}s for log ingestion ==="
sleep "$WAIT_SECONDS"
echo "Wait complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

echo "=== Phase 12: KQL ContainerAppConsoleLogs_CL + ContainerAppSystemLogs_CL (expect >=1 row) ==="
KQL_CONSOLE="ContainerAppConsoleLogs_CL | where ContainerAppName_s == '${APP_NAME}' | summarize rows=count(), distinct_revisions=dcount(RevisionName_s)"
KQL_SYSTEM="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | summarize rows=count(), distinct_revisions=dcount(RevisionName_s)"

set +e
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_CONSOLE" \
    --output json \
    > "$EVIDENCE_DIR/09-kql-after-console-raw.txt" 2>&1
CONSOLE_EXIT=$?
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_SYSTEM" \
    --output json \
    > "$EVIDENCE_DIR/09-kql-after-system-raw.txt" 2>&1
SYSTEM_EXIT=$?
set -e

UTC_QUERY="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
APP_NAME_LITERAL="$APP_NAME"
POST_FIX_REVISION="$NEW_REVISION"
export UTC_QUERY APP_NAME_LITERAL POST_FIX_REVISION CONSOLE_EXIT SYSTEM_EXIT KQL_CONSOLE KQL_SYSTEM EVIDENCE_DIR
export CONSOLE_OUT_FILE="$EVIDENCE_DIR/09-kql-after-console-raw.txt"
export SYSTEM_OUT_FILE="$EVIDENCE_DIR/09-kql-after-system-raw.txt"

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
    'post_fix_revision': os.environ['POST_FIX_REVISION'],
    'console_query': os.environ['KQL_CONSOLE'],
    'system_query': os.environ['KQL_SYSTEM'],
    'console_result': console,
    'system_result': system,
    'console_rows': console['rows'],
    'system_rows': system['rows'],
    'console_gate_classification': console['gate_classification'],
    'system_gate_classification': system['gate_classification'],
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '09-kql-after.json'), 'w') as f:
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

CONSOLE_ROWS_AFTER=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/09-kql-after.json'))['console_rows'])")
SYSTEM_ROWS_AFTER=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/09-kql-after.json'))['system_rows'])")
CONSOLE_GATE_AFTER=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/09-kql-after.json'))['console_gate_classification'])")
SYSTEM_GATE_AFTER=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/09-kql-after.json'))['system_gate_classification'])")
CONSOLE_GATE_BEFORE=$(python3 -c "import json,sys; d=json.load(open('$BASELINE_FILE')); print(d.get('console_gate_classification') or d['console_result'].get('gate_classification','unknown'))")
SYSTEM_GATE_BEFORE=$(python3 -c "import json,sys; d=json.load(open('$BASELINE_FILE')); print(d.get('system_gate_classification') or d['system_result'].get('gate_classification','unknown'))")

echo ""
echo "=== Summary ==="
echo "BEFORE: console rows=$CONSOLE_ROWS_BEFORE gate=$CONSOLE_GATE_BEFORE | system rows=$SYSTEM_ROWS_BEFORE gate=$SYSTEM_GATE_BEFORE"
echo "AFTER:  console rows=$CONSOLE_ROWS_AFTER gate=$CONSOLE_GATE_AFTER | system rows=$SYSTEM_ROWS_AFTER gate=$SYSTEM_GATE_AFTER"
echo ""

if [[ "$CONSOLE_GATE_AFTER" == "query_error_invalid_run" || "$SYSTEM_GATE_AFTER" == "query_error_invalid_run" ]]; then
    echo "VERDICT: INVALID RUN. Post-fix KQL produced an unexpected error (not valid JSON, and not the expected BadArgumentError + 'Failed to resolve table' signature)."
    echo "Inspect 09-kql-after-console-raw.txt and 09-kql-after-system-raw.txt for the actual error."
    exit 1
fi

H1_PASS=false
H2_PASS=false

if [[ "$CONSOLE_GATE_BEFORE" == "silent_valid_baseline" && "$SYSTEM_GATE_BEFORE" == "silent_valid_baseline" ]]; then
    H1_PASS=true
fi
if [[ "$CONSOLE_GATE_AFTER" == "populated_table" && "$SYSTEM_GATE_AFTER" == "populated_table" ]]; then
    H2_PASS=true
fi

echo "H1 (baseline = silent_valid_baseline for both tables): $H1_PASS"
echo "H2 (post-fix = populated_table for both tables): $H2_PASS"

if [[ "$H1_PASS" == "true" && "$H2_PASS" == "true" ]]; then
    echo "VERDICT: SUPPORTED. Environment-level appLogsConfiguration is the controlling variable for Log Analytics ingestion in this reproduction."
    exit 0
fi

if [[ "$H2_PASS" == "false" ]]; then
    echo "VERDICT: H2 FALSIFIED. Logs did not appear after appLogsConfiguration was set. Investigate ingestion path."
    exit 2
fi

echo "VERDICT: INVALID RUN. Re-deploy and re-run."
exit 1
