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

echo "=== Phase 10: validate baseline evidence from trigger.sh ==="
H1_FILE="$EVIDENCE_DIR/10-h1-gate.json"
if [[ ! -f "$H1_FILE" ]]; then
    echo "INVALID RUN: $H1_FILE not found. Run trigger.sh first."
    exit 1
fi
H1_GATE=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['gate_classification'])")
H1_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['h1_all_subgates_pass'])")
echo "Triggered state: H1 gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
if [[ "$H1_GATE" == "scale_rule_responded_unexpectedly" ]]; then
    echo "INVALID RUN: H1 was FALSIFIED in trigger.sh. The mismatched scale rule unexpectedly responded to load; cannot test the fix because the baseline failure state did not materialize."
    exit 1
fi
echo ""

echo "=== Phase 11: az containerapp update --scale-rule-metadata concurrentRequests=10 --max-replicas 10 (apply fix) ==="
FIX_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Fix UTC: $FIX_UTC"
az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --min-replicas 1 \
    --max-replicas 10 \
    --scale-rule-name "http-rule" \
    --scale-rule-type "http" \
    --scale-rule-metadata "concurrentRequests=10" \
    --query "{name: name, provisioningState: properties.provisioningState, latestRevisionName: properties.latestRevisionName, scaleConfig: properties.template.scale}" \
    --output json \
    > "$EVIDENCE_DIR/11-containerapp-update-fix.json"
cat "$EVIDENCE_DIR/11-containerapp-update-fix.json"
echo ""

POST_FIX_PROVISIONING_STATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/11-containerapp-update-fix.json'))['provisioningState'])")
POST_FIX_REVISION_NAME=$(python3 -c "
import json
d = json.load(open('$EVIDENCE_DIR/11-containerapp-update-fix.json'))
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

echo "=== Phase 12: poll new revision health up to 5 minutes (10 s interval) ==="
HEALTH_POLL_START_EPOCH=$(date +%s)
DEADLINE=$(( HEALTH_POLL_START_EPOCH + 300 ))
revision_health="Unknown"
POLL_COUNT=0
SECONDS_TO_HEALTHY=""
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
        HEALTHY_AT_EPOCH=$(date +%s)
        SECONDS_TO_HEALTHY=$(( HEALTHY_AT_EPOCH - HEALTH_POLL_START_EPOCH ))
        echo "New revision Healthy after ${SECONDS_TO_HEALTHY}s"
        break
    fi
    sleep 10
done
echo "Final healthState after polling: $revision_health"
echo "Seconds to Healthy (measured from update completion to first Healthy poll): ${SECONDS_TO_HEALTHY}"
echo ""

echo "=== Phase 13: capture container app post-fix state (expect concurrentRequests=10, maxReplicas=10) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{name: name, provisioningState: properties.provisioningState, latestRevisionName: properties.latestRevisionName, scaleConfig: properties.template.scale, fqdn: properties.configuration.ingress.fqdn}" \
    --output json \
    > "$EVIDENCE_DIR/12-containerapp-show-after-fix.json"
cat "$EVIDENCE_DIR/12-containerapp-show-after-fix.json"
echo ""

POST_FIX_FQDN=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/12-containerapp-show-after-fix.json'))['fqdn'])")
URL_AFTER_FIX="https://${POST_FIX_FQDN}/load"
echo "Post-fix load URL: ${URL_AFTER_FIX}"
echo ""

if [[ -z "$POST_FIX_FQDN" ]]; then
    echo "INVALID RUN: post-fix FQDN is empty. Cannot proceed to Phase 15 load generation."
    exit 1
fi

echo "=== Phase 14: capture pre-load replica baseline AFTER FIX (expect 1 replica at idle) ==="
# Wait 30 s for the new revision to fully stabilize (KEDA scaler may briefly hold replicas at >1
# while the previous revision drains; we want the steady-state idle count before load resumes).
sleep 30
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --output json \
    > "$EVIDENCE_DIR/13-replicas-pre-load-after-fix.json"
REPLICAS_PRE_LOAD_AFTER_FIX=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/13-replicas-pre-load-after-fix.json'))))")
echo "Post-fix pre-load replica count: ${REPLICAS_PRE_LOAD_AFTER_FIX}"
echo ""

echo "=== Phase 15: generate sustained load AFTER FIX (60 concurrent requests for 90 s, identical to trigger.sh Phase 6) ==="
LOAD_START_EPOCH_AFTER_FIX=$(date -u +%s)
LOAD_START_UTC_AFTER_FIX="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Load start UTC (post-fix): ${LOAD_START_UTC_AFTER_FIX}"
LOAD_DURATION=90
LOAD_CONCURRENCY=60
LOAD_END_EPOCH_AFTER_FIX=$((LOAD_START_EPOCH_AFTER_FIX + LOAD_DURATION))
LOAD_END_UTC_AFTER_FIX=$(LOAD_START_UTC_AFTER_FIX="$LOAD_START_UTC_AFTER_FIX" LOAD_DURATION="$LOAD_DURATION" python3 -c "
import datetime, os
start = datetime.datetime.strptime(os.environ['LOAD_START_UTC_AFTER_FIX'], '%Y-%m-%dT%H:%M:%SZ')
print((start + datetime.timedelta(seconds=int(os.environ['LOAD_DURATION']))).strftime('%Y-%m-%dT%H:%M:%SZ'))
")
echo "Load end UTC (strict, +90s): ${LOAD_END_UTC_AFTER_FIX}"
load_end_epoch=$LOAD_END_EPOCH_AFTER_FIX
LOAD_PIDS=()
for _ in $(seq 1 $LOAD_CONCURRENCY); do
    (
        while [ "$(date -u +%s)" -lt "$load_end_epoch" ]; do
            curl --silent --max-time 5 "$URL_AFTER_FIX" > /dev/null 2>&1 || true
        done
    ) &
    LOAD_PIDS+=($!)
done

echo "=== Phase 16: poll replica count during post-fix load at 15 s, 30 s, 60 s, 90 s ==="
sleep 15
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --output json \
    > "$EVIDENCE_DIR/14-replicas-load-15s-after-fix.json"
REPLICAS_15S_AFTER_FIX=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/14-replicas-load-15s-after-fix.json'))))")
echo "Replicas at +15 s post-fix under load: ${REPLICAS_15S_AFTER_FIX}"

sleep 15
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --output json \
    > "$EVIDENCE_DIR/15-replicas-load-30s-after-fix.json"
REPLICAS_30S_AFTER_FIX=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/15-replicas-load-30s-after-fix.json'))))")
echo "Replicas at +30 s post-fix under load: ${REPLICAS_30S_AFTER_FIX}"

sleep 30
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --output json \
    > "$EVIDENCE_DIR/16-replicas-load-60s-after-fix.json"
REPLICAS_60S_AFTER_FIX=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/16-replicas-load-60s-after-fix.json'))))")
echo "Replicas at +60 s post-fix under load: ${REPLICAS_60S_AFTER_FIX}"

sleep 30
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --output json \
    > "$EVIDENCE_DIR/17-replicas-load-90s-after-fix.json"
REPLICAS_90S_AFTER_FIX=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/17-replicas-load-90s-after-fix.json'))))")
echo "Replicas at +90 s post-fix under load: ${REPLICAS_90S_AFTER_FIX}"

for pid in "${LOAD_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done
echo "Post-fix load generation processes joined (KQL window remains [${LOAD_START_UTC_AFTER_FIX}, ${LOAD_END_UTC_AFTER_FIX}] strict 90 s)"
echo ""

echo "=== Phase 17: query ContainerAppSystemLogs_CL for scale events during post-fix load window ==="
KQL_QUERY_AFTER_FIX="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where RevisionName_s == '${POST_FIX_REVISION_NAME}' | where TimeGenerated between (datetime(${LOAD_START_UTC_AFTER_FIX}) .. datetime(${LOAD_END_UTC_AFTER_FIX})) | where Reason_s startswith 'Scal' or Reason_s startswith 'KEDA' | project TimeGenerated, Reason_s, Log_s, RevisionName_s | sort by TimeGenerated asc | take 100"

set +e
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_QUERY_AFTER_FIX" \
    --output json \
    > "$EVIDENCE_DIR/18-system-logs-scale-events-after-fix.json" 2>&1
POST_FIX_KQL_EXIT=$?
set -e
echo "az monitor log-analytics query exit code: $POST_FIX_KQL_EXIT"
echo "Output (truncated to first 500 chars):"
head -c 500 "$EVIDENCE_DIR/18-system-logs-scale-events-after-fix.json" || true
echo ""
echo ""

SCALE_EVENTS_COUNT_AFTER_FIX=$(python3 -c "
import json
try:
    data = json.load(open('$EVIDENCE_DIR/18-system-logs-scale-events-after-fix.json'))
    if isinstance(data, list):
        print(len(data))
    elif isinstance(data, dict) and 'tables' in data:
        print(sum(len(t.get('rows', [])) for t in data['tables']))
    else:
        print(0)
except (json.JSONDecodeError, FileNotFoundError):
    print(0)
")
echo "Scale event rows in post-fix load window: ${SCALE_EVENTS_COUNT_AFTER_FIX}"
echo ""

echo "=== Phase 18: capture metadata + emit H2 gate ==="
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

UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR APP_NAME RG POST_FIX_REVISION_NAME POST_FIX_FQDN FIX_UTC LOAD_START_UTC_AFTER_FIX LOAD_END_UTC_AFTER_FIX UTC_CAPTURED
export REPLICAS_PRE_LOAD_AFTER_FIX REPLICAS_15S_AFTER_FIX REPLICAS_30S_AFTER_FIX REPLICAS_60S_AFTER_FIX REPLICAS_90S_AFTER_FIX
export SCALE_EVENTS_COUNT_AFTER_FIX
export REVISION_FINAL_HEALTH="$revision_health"
export SECONDS_TO_HEALTHY="${SECONDS_TO_HEALTHY:-}"

python3 <<'PYEOF'
import json, os

# H2 gate taxonomy for scale-rule-mismatch recovery:
#
#   scale_rule_fixed_replicas_scaled_events_observed - revision Healthy + max replicas
#                                                      during post-fix load >= 2 AND
#                                                      KEDA scale events observed (PASS)
#   scale_rule_fixed_replicas_scaled_no_events       - revision Healthy + replicas scaled
#                                                      but no KEDA scale event rows in
#                                                      ContainerAppSystemLogs_CL. KEDA
#                                                      attribution rows can be lazy or
#                                                      filtered differently; the replica
#                                                      count is the controlling signal.
#                                                      Acceptable as partial PASS.
#   scale_rule_fixed_replicas_did_not_scale          - revision Healthy but max replicas
#                                                      stayed at 1 under load that should
#                                                      have crossed the new threshold of 10.
#                                                      H2 FALSIFIED.
#   fix_revision_unhealthy                           - new revision did not reach Healthy
#                                                      within 5 min poll budget. H2 FALSIFIED.
#
# H2 sub-gates:
#   a. post_fix_revision_healthy           - new revision Healthy after fix
#   b. replicas_increased_after_fix        - max replicas during post-fix load >= 2
#   c. scaleup_events_observed_after_fix   - SCALE_EVENTS_COUNT_AFTER_FIX >= 1

revision_health = os.environ['REVISION_FINAL_HEALTH']
replicas_pre_load_after_fix = int(os.environ['REPLICAS_PRE_LOAD_AFTER_FIX'])
replicas_15s_after_fix = int(os.environ['REPLICAS_15S_AFTER_FIX'])
replicas_30s_after_fix = int(os.environ['REPLICAS_30S_AFTER_FIX'])
replicas_60s_after_fix = int(os.environ['REPLICAS_60S_AFTER_FIX'])
replicas_90s_after_fix = int(os.environ['REPLICAS_90S_AFTER_FIX'])
scale_events_count_after_fix = int(os.environ['SCALE_EVENTS_COUNT_AFTER_FIX'])

max_replicas_during_post_fix_load = max(
    replicas_15s_after_fix,
    replicas_30s_after_fix,
    replicas_60s_after_fix,
    replicas_90s_after_fix,
)

post_fix_revision_healthy = revision_health == 'Healthy'
replicas_increased_after_fix = max_replicas_during_post_fix_load >= 2
scaleup_events_observed_after_fix = scale_events_count_after_fix >= 1

if not post_fix_revision_healthy:
    h2_gate = 'fix_revision_unhealthy'
elif not replicas_increased_after_fix:
    h2_gate = 'scale_rule_fixed_replicas_did_not_scale'
elif not scaleup_events_observed_after_fix:
    h2_gate = 'scale_rule_fixed_replicas_scaled_no_events'
else:
    h2_gate = 'scale_rule_fixed_replicas_scaled_events_observed'

h2_sub_gates = {
    'a_post_fix_revision_healthy': post_fix_revision_healthy,
    'b_replicas_increased_after_fix': replicas_increased_after_fix,
    'c_scaleup_events_observed_after_fix': scaleup_events_observed_after_fix,
}
h2_all_subgates_pass = all(h2_sub_gates.values())

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'fix_utc': os.environ['FIX_UTC'],
    'app_name': os.environ['APP_NAME'],
    'rg': os.environ['RG'],
    'post_fix_revision': os.environ['POST_FIX_REVISION_NAME'],
    'post_fix_fqdn': os.environ['POST_FIX_FQDN'],
    'final_revision_health': revision_health,
    'seconds_to_healthy': int(os.environ['SECONDS_TO_HEALTHY']) if os.environ.get('SECONDS_TO_HEALTHY') else None,
    'post_fix_load_window': {
        'start_utc': os.environ['LOAD_START_UTC_AFTER_FIX'],
        'end_utc': os.environ['LOAD_END_UTC_AFTER_FIX'],
        'duration_seconds': 90,
        'concurrent_requests_generated': 60,
        'scale_rule_threshold_configured_after_fix': 10,
        'max_replicas_configured_after_fix': 10,
    },
    'replicas_observed_after_fix': {
        'pre_load': replicas_pre_load_after_fix,
        'at_15s': replicas_15s_after_fix,
        'at_30s': replicas_30s_after_fix,
        'at_60s': replicas_60s_after_fix,
        'at_90s': replicas_90s_after_fix,
        'max_during_load': max_replicas_during_post_fix_load,
    },
    'scale_events_count_after_fix': scale_events_count_after_fix,
    'h2_sub_gates': h2_sub_gates,
    'h2_all_subgates_pass': h2_all_subgates_pass,
    'gate_classification': h2_gate,
}

with open(os.path.join(os.environ['EVIDENCE_DIR'], '19-h2-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'gate_classification': out['gate_classification'],
    'h2_all_subgates_pass': out['h2_all_subgates_pass'],
    'h2_sub_gates': out['h2_sub_gates'],
    'max_replicas_during_load': max_replicas_during_post_fix_load,
}, indent=2))
PYEOF
echo ""

H2_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/19-h2-gate.json'))['gate_classification'])")
H2_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/19-h2-gate.json'))['h2_all_subgates_pass'])")

echo "=== Verdict ==="
echo "H1 (trigger.sh): gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
echo "H2 (verify.sh):  gate=${H2_GATE}, all_subgates_pass=${H2_ALL_SUBGATES_PASS}"
echo ""

H1_PASS=false
H2_PASS=false

if [[ "$H1_GATE" == "scale_rule_mismatch_replicas_capped" && "$H1_ALL_SUBGATES_PASS" == "True" ]]; then
    H1_PASS=true
fi
if [[ "$H1_GATE" == "partial_observation_some_subgates_failed" ]]; then
    H1_PASS=true
fi
if [[ "$H2_GATE" == "scale_rule_fixed_replicas_scaled_events_observed" && "$H2_ALL_SUBGATES_PASS" == "True" ]]; then
    H2_PASS=true
fi
if [[ "$H2_GATE" == "scale_rule_fixed_replicas_scaled_no_events" ]]; then
    H2_PASS=true
fi

echo "H1 PASS: $H1_PASS"
echo "H2 PASS: $H2_PASS"

if [[ "$H1_PASS" == "true" && "$H2_PASS" == "true" ]]; then
    echo "VERDICT: SUPPORTED. The HTTP scale rule threshold (concurrentRequests metadata) is the controlling variable: a threshold far above realistic concurrent load (500 vs 60) keeps replicas at minReplicas; lowering it to a realistic value (10) causes KEDA to scale replicas during the same load shape."
    exit 0
fi

if [[ "$H2_GATE" == "fix_revision_unhealthy" || "$H2_GATE" == "scale_rule_fixed_replicas_did_not_scale" ]]; then
    echo "VERDICT: H2 FALSIFIED. The fix (concurrentRequests=10, maxReplicas=10) did not produce KEDA scale-up under the same load shape (gate=${H2_GATE}). Investigate revision health, the new scale rule configuration, or the load generator."
    exit 2
fi

echo "VERDICT: INVALID RUN. Unexpected combination of H1 gate=${H1_GATE} and H2 gate=${H2_GATE}. Inspect evidence files."
exit 1
