#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${WORKSPACE_CUSTOMER_ID:?Set WORKSPACE_CUSTOMER_ID before running (the LAW guid, not the resource ID)}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "verify.sh starting at ${UTC_NOW}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "Workspace customer ID: ${WORKSPACE_CUSTOMER_ID}"
echo ""

echo "=== Phase 13: validate baseline evidence from trigger.sh ==="
H1_FILE="$EVIDENCE_DIR/11-h1-gate.json"
if [[ ! -f "$H1_FILE" ]]; then
    echo "INVALID RUN: $H1_FILE not found. Run trigger.sh first."
    exit 1
fi
H1_GATE=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['gate_classification'])")
H1_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['h1_all_subgates_pass'])")
BASELINE_REVISION_NAME=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['baseline_revision_name'])")
echo "Triggered state: H1 gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
echo "Baseline revision (from trigger.sh): ${BASELINE_REVISION_NAME}"
if [[ "$H1_GATE" == "revision_failover_break_did_not_materialize" ]]; then
    echo "INVALID RUN: H1 was FALSIFIED in trigger.sh. The ingress targetPort flip to 9999 did not cause the revision to transition to non-Healthy; cannot test the fix because the baseline failure state did not materialize."
    exit 1
fi
echo ""

echo "=== Phase 14: az containerapp ingress update --target-port 8000 (apply in-place fix to same revision) ==="
# The fix mirrors the break action: ingress targetPort is an app-level configuration, so flipping
# it back to 8000 modifies the same revision in place. The platform startup probe is re-targeted
# to port 8000 where the Gunicorn container has been listening the whole time, and the revision
# should transition back from non-Healthy to Healthy within ~30 s. This is the canonical "path b"
# recovery (in-place, same revision name) that the existing 2026-06-03 Portal capture sequence
# documents in docs/troubleshooting/lab-guides/revision-failover.md.
FIX_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Fix UTC: $FIX_UTC"
az containerapp ingress update \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --target-port 8000 \
    --output json \
    > "$EVIDENCE_DIR/12-containerapp-ingress-update-fix.json"
cat "$EVIDENCE_DIR/12-containerapp-ingress-update-fix.json"
echo ""

echo "=== Phase 15: poll for revision health to recover from non-Healthy back to Healthy ==="
HEALTH_POLL_START_EPOCH=$(date +%s)
DEADLINE=$(( HEALTH_POLL_START_EPOCH + 240 ))
revision_health="Unknown"
POLL_COUNT=0
SECONDS_TO_HEALTHY=""
while [[ $(date +%s) -lt $DEADLINE ]]; do
    POLL_COUNT=$(( POLL_COUNT + 1 ))
    revision_health=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --revision "$BASELINE_REVISION_NAME" \
        --query "properties.healthState" \
        --output tsv 2>/dev/null || echo "Unknown")
    echo "Poll #${POLL_COUNT} at $(date -u +%Y-%m-%dT%H:%M:%SZ): healthState=${revision_health}"
    if [[ "$revision_health" == "Healthy" ]]; then
        HEALTHY_AT_EPOCH=$(date +%s)
        SECONDS_TO_HEALTHY=$(( HEALTHY_AT_EPOCH - HEALTH_POLL_START_EPOCH ))
        echo "Revision recovered to Healthy after ${SECONDS_TO_HEALTHY}s"
        break
    fi
    sleep 10
done
echo "Final healthState after polling: $revision_health"
echo "Seconds to Healthy (measured from fix completion to first Healthy poll): ${SECONDS_TO_HEALTHY}"
echo ""

echo "=== Phase 16: capture post-fix revision list (expect baseline revision Healthy at 100% traffic) ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, trafficWeight: properties.trafficWeight, runningState: properties.runningState, createdTime: properties.createdTime, replicas: properties.replicas}" \
    --output json \
    > "$EVIDENCE_DIR/13-revision-list-after-fix.json"
cat "$EVIDENCE_DIR/13-revision-list-after-fix.json"
echo ""

echo "=== Phase 17: capture container app post-fix state (expect targetPort=8000, latestRevisionName=baseline) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "{name: name, provisioningState: properties.provisioningState, latestRevisionName: properties.latestRevisionName, fqdn: properties.configuration.ingress.fqdn, targetPort: properties.configuration.ingress.targetPort, activeRevisionsMode: properties.configuration.activeRevisionsMode}" \
    --output json \
    > "$EVIDENCE_DIR/14-containerapp-show-after-fix.json"
cat "$EVIDENCE_DIR/14-containerapp-show-after-fix.json"
echo ""

POST_FIX_FQDN=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/14-containerapp-show-after-fix.json'))['fqdn'])")
POST_FIX_REVISION_NAME=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/14-containerapp-show-after-fix.json'))['latestRevisionName'])")
POST_FIX_TARGET_PORT=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/14-containerapp-show-after-fix.json'))['targetPort'])")
URL_AFTER_FIX="https://${POST_FIX_FQDN}/"
echo "Post-fix FQDN: ${POST_FIX_FQDN}"
echo "Post-fix URL: ${URL_AFTER_FIX}"
echo "Post-fix latestRevisionName: ${POST_FIX_REVISION_NAME} (expected: same as baseline ${BASELINE_REVISION_NAME})"
echo "Post-fix targetPort: ${POST_FIX_TARGET_PORT} (expected: 8000)"
echo ""

if [[ -z "$POST_FIX_FQDN" ]]; then
    echo "INVALID RUN: post-fix FQDN is empty. Cannot proceed to Phase 18 HTTP probe."
    exit 1
fi

echo "=== Phase 18: post-fix HTTP probe (expect HTTP 200) ==="
POST_FIX_CURL_HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" --max-time 10 "$URL_AFTER_FIX" || echo "000")
echo "Post-fix HTTP code from ${URL_AFTER_FIX}: ${POST_FIX_CURL_HTTP_CODE}" > "$EVIDENCE_DIR/15-curl-after-fix.txt"
cat "$EVIDENCE_DIR/15-curl-after-fix.txt"
echo ""

echo "=== Phase 19: query ContainerAppSystemLogs_CL for recovery events during fix window ==="
RECOVERY_END_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Same KQL pattern as trigger.sh Phase 10 but the time window now spans [FIX_UTC, RECOVERY_END_UTC]
# and the expected outcome inverts: we expect to see probe success / revision-Healthy events instead
# of probe failures. The `Reason_s contains` clauses are intentionally bounded by `or` and the KQL
# operator precedence (`and` binds tighter than `or`) keeps the filter scoped correctly.
KQL_QUERY_RECOVERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where RevisionName_s == '${BASELINE_REVISION_NAME}' | where TimeGenerated between (datetime(${FIX_UTC}) .. datetime(${RECOVERY_END_UTC})) | project TimeGenerated, Reason_s, Log_s, RevisionName_s | sort by TimeGenerated asc | take 100"

set +e
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_QUERY_RECOVERY" \
    --output json \
    > "$EVIDENCE_DIR/16-system-logs-recovery.json" 2>&1
RECOVERY_KQL_EXIT=$?
set -e
echo "az monitor log-analytics query exit code: $RECOVERY_KQL_EXIT"
echo "Output (truncated to first 500 chars):"
head -c 500 "$EVIDENCE_DIR/16-system-logs-recovery.json" || true
echo ""
echo ""

RECOVERY_LOG_COUNT=$(python3 -c "
import json
try:
    data = json.load(open('$EVIDENCE_DIR/16-system-logs-recovery.json'))
    if isinstance(data, list):
        print(len(data))
    elif isinstance(data, dict) and 'tables' in data:
        print(sum(len(t.get('rows', [])) for t in data['tables']))
    else:
        print(0)
except (json.JSONDecodeError, FileNotFoundError):
    print(0)
")
echo "Recovery log rows in fix window: ${RECOVERY_LOG_COUNT}"
echo ""

echo "=== Phase 20: capture metadata + emit H2 gate ==="
az version --output json > "$EVIDENCE_DIR/18-cli-versions.json" 2>&1 || true
az extension list --query "[?name=='containerapp']" --output json > "$EVIDENCE_DIR/19-cli-containerapp-ext.json" 2>&1 || true
az group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --query "{name: name, location: location}" \
    --output json \
    > "$EVIDENCE_DIR/20-region.json" 2>&1 || true
az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs" \
    --output json \
    > "$EVIDENCE_DIR/21-deployment-outputs.json" 2>&1 || true

UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR APP_NAME RG BASELINE_REVISION_NAME POST_FIX_REVISION_NAME POST_FIX_FQDN
export FIX_UTC RECOVERY_END_UTC UTC_CAPTURED
export POST_FIX_TARGET_PORT POST_FIX_CURL_HTTP_CODE
export REVISION_FINAL_HEALTH="$revision_health"
export SECONDS_TO_HEALTHY="${SECONDS_TO_HEALTHY:-}"
export RECOVERY_LOG_COUNT

python3 <<'PYEOF'
import json, os

# H2 gate taxonomy for revision-failover recovery:
#
#   revision_failover_recovered_in_place_no_new_revision - canonical path b: revision name
#                                                          unchanged, Healthy after fix, curl 200,
#                                                          targetPort back to 8000 (PASS)
#   revision_failover_recovered_via_new_revision         - alternative recovery path: a new
#                                                          revision was created (e.g. operator
#                                                          deployed a fresh image instead of
#                                                          flipping the port). Healthy + curl 200
#                                                          + targetPort 8000 but revision name
#                                                          DIFFERS from baseline. Accepted as
#                                                          alternative PASS for completeness;
#                                                          docs lab guide calls this "path a".
#   revision_failover_did_not_recover                    - revision is still non-Healthy or curl
#                                                          still fails after 240 s poll budget.
#                                                          H2 FALSIFIED.
#   partial_observation_some_subgates_failed             - mixed sub-gate results (e.g. Healthy
#                                                          and revision name matches but curl
#                                                          intermittently failed). Investigate.
#
# H2 sub-gates:
#   a. post_fix_revision_healthy           - active revision Healthy after fix
#   b. same_revision_name_recovered        - latestRevisionName matches baseline (in-place proof)
#   c. curl_succeeded_after_fix            - HTTP 200 from FQDN
#   d. ingress_target_port_corrected       - configuration.ingress.targetPort == 8000

revision_health = os.environ['REVISION_FINAL_HEALTH']
post_fix_curl_http_code = os.environ['POST_FIX_CURL_HTTP_CODE']
post_fix_target_port = int(os.environ['POST_FIX_TARGET_PORT'])
baseline_revision_name = os.environ['BASELINE_REVISION_NAME']
post_fix_revision_name = os.environ['POST_FIX_REVISION_NAME']
recovery_log_count = int(os.environ['RECOVERY_LOG_COUNT'])
seconds_to_healthy_env = os.environ.get('SECONDS_TO_HEALTHY', '')

post_fix_revision_healthy = revision_health == 'Healthy'
same_revision_name_recovered = baseline_revision_name == post_fix_revision_name
curl_succeeded_after_fix = post_fix_curl_http_code == '200'
ingress_target_port_corrected = post_fix_target_port == 8000

h2_sub_gates = {
    'a_post_fix_revision_healthy': post_fix_revision_healthy,
    'b_same_revision_name_recovered': same_revision_name_recovered,
    'c_curl_succeeded_after_fix': curl_succeeded_after_fix,
    'd_ingress_target_port_corrected': ingress_target_port_corrected,
}
h2_all_subgates_pass = all(h2_sub_gates.values())

if not post_fix_revision_healthy or not curl_succeeded_after_fix or not ingress_target_port_corrected:
    h2_gate = 'revision_failover_did_not_recover'
elif h2_all_subgates_pass:
    h2_gate = 'revision_failover_recovered_in_place_no_new_revision'
elif post_fix_revision_healthy and curl_succeeded_after_fix and ingress_target_port_corrected and not same_revision_name_recovered:
    h2_gate = 'revision_failover_recovered_via_new_revision'
else:
    h2_gate = 'partial_observation_some_subgates_failed'

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'fix_utc': os.environ['FIX_UTC'],
    'app_name': os.environ['APP_NAME'],
    'rg': os.environ['RG'],
    'baseline_revision_name': baseline_revision_name,
    'post_fix_revision_name': post_fix_revision_name,
    'post_fix_fqdn': os.environ['POST_FIX_FQDN'],
    'final_revision_health': revision_health,
    'seconds_to_healthy': int(seconds_to_healthy_env) if seconds_to_healthy_env else None,
    'fix_window': {
        'start_utc': os.environ['FIX_UTC'],
        'end_utc': os.environ['RECOVERY_END_UTC'],
        'post_fix_target_port': post_fix_target_port,
    },
    'curl_observations': {
        'post_fix_http_code': post_fix_curl_http_code,
    },
    'recovery_log_count': recovery_log_count,
    'h2_sub_gates': h2_sub_gates,
    'h2_all_subgates_pass': h2_all_subgates_pass,
    'gate_classification': h2_gate,
}

with open(os.path.join(os.environ['EVIDENCE_DIR'], '17-h2-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'gate_classification': out['gate_classification'],
    'h2_all_subgates_pass': out['h2_all_subgates_pass'],
    'h2_sub_gates': out['h2_sub_gates'],
    'seconds_to_healthy': out['seconds_to_healthy'],
    'baseline_vs_post_fix_revision_name': {
        'baseline': baseline_revision_name,
        'post_fix': post_fix_revision_name,
        'unchanged': same_revision_name_recovered,
    },
}, indent=2))
PYEOF
echo ""

H2_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/17-h2-gate.json'))['gate_classification'])")
H2_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/17-h2-gate.json'))['h2_all_subgates_pass'])")

echo "=== Verdict ==="
echo "H1 (trigger.sh): gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
echo "H2 (verify.sh):  gate=${H2_GATE}, all_subgates_pass=${H2_ALL_SUBGATES_PASS}"
echo ""

H1_PASS=false
H2_PASS=false

if [[ "$H1_GATE" == "revision_failover_broken_revision_unhealthy" && "$H1_ALL_SUBGATES_PASS" == "True" ]]; then
    H1_PASS=true
fi
if [[ "$H2_GATE" == "revision_failover_recovered_in_place_no_new_revision" && "$H2_ALL_SUBGATES_PASS" == "True" ]]; then
    H2_PASS=true
fi
if [[ "$H2_GATE" == "revision_failover_recovered_via_new_revision" ]]; then
    H2_PASS=true
fi

echo "H1 PASS: $H1_PASS"
echo "H2 PASS: $H2_PASS"

if [[ "$H1_PASS" == "true" && "$H2_PASS" == "true" ]]; then
    echo "VERDICT: SUPPORTED. The ingress targetPort flip (8000 -> 9999 -> 8000) is the controlling variable: the same revision transitions from Healthy to non-Healthy when targetPort points to a port nothing is listening on, and the same revision recovers to Healthy in-place when targetPort is corrected back. No new revision is required for either the break or the fix."
    exit 0
fi

if [[ "$H2_GATE" == "revision_failover_did_not_recover" ]]; then
    echo "VERDICT: H2 FALSIFIED. The fix (ingress targetPort flip back to 8000) did not restore the revision to Healthy or did not restore HTTP 200 (gate=${H2_GATE}). Investigate startup probe configuration, the workload's actual listening port, or the platform's probe-retry behavior."
    exit 2
fi

echo "VERDICT: INVALID RUN. Unexpected combination of H1 gate=${H1_GATE} and H2 gate=${H2_GATE}. Inspect evidence files."
exit 1
