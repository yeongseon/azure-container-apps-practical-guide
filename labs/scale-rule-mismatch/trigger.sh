#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${ACR_NAME:?Set ACR_NAME before running}"
: "${ACR_LOGIN_SERVER:?Set ACR_LOGIN_SERVER before running}"
: "${WORKSPACE_CUSTOMER_ID:?Set WORKSPACE_CUSTOMER_ID before running}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "trigger.sh starting at ${UTC_NOW}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "ACR: ${ACR_NAME}"
echo "ACR login server: ${ACR_LOGIN_SERVER}"
echo "Workspace customer ID: ${WORKSPACE_CUSTOMER_ID}"
echo ""
echo "Note: This lab triggers a scale rule mismatch by deploying a workload with"
echo "scale rule concurrentRequests=500 and maxReplicas=2. Under realistic concurrent"
echo "load (60 concurrent requests over 90 s), the threshold is never reached, so KEDA"
echo "does not request additional replicas. The replica count stays at 1 (= minReplicas)"
echo "and the platform appears to ignore the load. This is the documented behavior, not"
echo "a bug; the scale rule was configured with an unrealistic threshold."
echo ""

echo "=== Phase 1: build and push custom image to ACR ==="
ACR_USERNAME=$(az acr credential show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$ACR_NAME" \
    --query "username" \
    --output tsv)
ACR_PASSWORD=$(az acr credential show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$ACR_NAME" \
    --query "passwords[0].value" \
    --output tsv)

az acr build \
    --subscription "$AZ_SUBSCRIPTION" \
    --registry "$ACR_NAME" \
    --image "labscale:v1" \
    ./workload \
    > "$EVIDENCE_DIR/01-acr-build-result.txt" 2>&1
echo "Built and pushed ${ACR_LOGIN_SERVER}/labscale:v1"
echo ""

echo "=== Phase 2: set registry credentials + update container app to custom image with MISMATCHED scale rule ==="
az containerapp registry set \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --server "$ACR_LOGIN_SERVER" \
    --username "$ACR_USERNAME" \
    --password "$ACR_PASSWORD" \
    --output none

az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --image "${ACR_LOGIN_SERVER}/labscale:v1" \
    --min-replicas 1 \
    --max-replicas 2 \
    --scale-rule-name "http-rule" \
    --scale-rule-type "http" \
    --scale-rule-metadata "concurrentRequests=500" \
    --output json \
    > "$EVIDENCE_DIR/02-containerapp-update-baseline.json"
echo "Updated container app to image labscale:v1 with mismatched scale rule (concurrentRequests=500, maxReplicas=2)"
echo ""

echo "=== Phase 3: wait for new revision to become Healthy ==="
HEALTHY_TIMEOUT=300
HEALTHY_INTERVAL=10
elapsed=0
revision_health=""
while [ $elapsed -lt $HEALTHY_TIMEOUT ]; do
    revision_health=$(az containerapp revision list \
        --subscription "$AZ_SUBSCRIPTION" \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --query "[?properties.active==\`true\`] | [0].properties.healthState" \
        --output tsv 2>/dev/null || echo "")
    if [ "$revision_health" = "Healthy" ]; then
        echo "Latest active revision is Healthy after ${elapsed}s"
        break
    fi
    sleep $HEALTHY_INTERVAL
    elapsed=$((elapsed + HEALTHY_INTERVAL))
done
if [ "$revision_health" != "Healthy" ]; then
    echo "ERROR: revision did not become Healthy within ${HEALTHY_TIMEOUT}s"
    exit 1
fi
echo ""

echo "=== Phase 4: capture container app baseline state (expect maxReplicas=2, concurrentRequests=500) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "{name: name, provisioningState: properties.provisioningState, latestRevisionName: properties.latestRevisionName, scaleConfig: properties.template.scale, fqdn: properties.configuration.ingress.fqdn}" \
    --output json \
    > "$EVIDENCE_DIR/03-containerapp-show-baseline.json"
cat "$EVIDENCE_DIR/03-containerapp-show-baseline.json"
echo ""

FQDN=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/03-containerapp-show-baseline.json'))['fqdn'])")
ACTIVE_REVISION_NAME=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/03-containerapp-show-baseline.json'))['latestRevisionName'])")
URL="https://${FQDN}/load"
echo "Load URL: ${URL}"
echo "Active revision (pre-fix): ${ACTIVE_REVISION_NAME}"
echo ""

echo "=== Phase 5: capture pre-load replica baseline (expect 1 replica at idle) ==="
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --output json \
    > "$EVIDENCE_DIR/04-replicas-pre-load.json"
REPLICAS_PRE_LOAD=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/04-replicas-pre-load.json'))))")
echo "Pre-load replica count: ${REPLICAS_PRE_LOAD}"
echo ""

echo "=== Phase 6: generate sustained load (60 concurrent requests for 90s) ==="
LOAD_START_EPOCH=$(date -u +%s)
LOAD_START_UTC="$(date -u -r $LOAD_START_EPOCH +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Load start UTC: ${LOAD_START_UTC}"
LOAD_DURATION=90
LOAD_CONCURRENCY=60
LOAD_END_EPOCH=$((LOAD_START_EPOCH + LOAD_DURATION))
LOAD_END_UTC=$(LOAD_START_UTC="$LOAD_START_UTC" LOAD_DURATION="$LOAD_DURATION" python3 -c "
import datetime, os
start = datetime.datetime.strptime(os.environ['LOAD_START_UTC'], '%Y-%m-%dT%H:%M:%SZ')
print((start + datetime.timedelta(seconds=int(os.environ['LOAD_DURATION']))).strftime('%Y-%m-%dT%H:%M:%SZ'))
")
echo "Load end UTC (strict, +90s): ${LOAD_END_UTC}"
load_end_epoch=$LOAD_END_EPOCH
LOAD_PIDS=()
for _ in $(seq 1 $LOAD_CONCURRENCY); do
    (
        while [ "$(date -u +%s)" -lt "$load_end_epoch" ]; do
            curl --silent --max-time 5 "$URL" > /dev/null 2>&1 || true
        done
    ) &
    LOAD_PIDS+=($!)
done

echo "=== Phase 7: poll replica count during load at 15s, 30s, 60s, 90s ==="
sleep 15
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --output json \
    > "$EVIDENCE_DIR/05-replicas-load-15s.json"
REPLICAS_15S=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/05-replicas-load-15s.json'))))")
echo "Replicas at +15 s under load: ${REPLICAS_15S}"

sleep 15
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --output json \
    > "$EVIDENCE_DIR/06-replicas-load-30s.json"
REPLICAS_30S=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/06-replicas-load-30s.json'))))")
echo "Replicas at +30 s under load: ${REPLICAS_30S}"

sleep 30
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --output json \
    > "$EVIDENCE_DIR/07-replicas-load-60s.json"
REPLICAS_60S=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/07-replicas-load-60s.json'))))")
echo "Replicas at +60 s under load: ${REPLICAS_60S}"

sleep 30
az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --output json \
    > "$EVIDENCE_DIR/08-replicas-load-90s.json"
REPLICAS_90S=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/08-replicas-load-90s.json'))))")
echo "Replicas at +90 s under load: ${REPLICAS_90S}"

for pid in "${LOAD_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done
echo "Load generation processes joined (KQL window remains [${LOAD_START_UTC}, ${LOAD_END_UTC}] strict 90 s)"
echo ""

echo "=== Phase 8: query ContainerAppSystemLogs_CL for scale events during load window ==="
KQL_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where RevisionName_s == '${ACTIVE_REVISION_NAME}' | where TimeGenerated between (datetime(${LOAD_START_UTC}) .. datetime(${LOAD_END_UTC})) | where Reason_s startswith 'Scal' or Reason_s startswith 'KEDA' | project TimeGenerated, Reason_s, Log_s, RevisionName_s | sort by TimeGenerated asc | take 100"
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_QUERY" \
    --output json \
    > "$EVIDENCE_DIR/09-system-logs-scale-events-pre-fix.json" 2>&1 || echo "[]" > "$EVIDENCE_DIR/09-system-logs-scale-events-pre-fix.json"
SCALE_EVENTS_COUNT=$(python3 -c "
import json
data = json.load(open('$EVIDENCE_DIR/09-system-logs-scale-events-pre-fix.json'))
if isinstance(data, list):
    print(len(data))
elif isinstance(data, dict) and 'tables' in data:
    print(sum(len(t.get('rows', [])) for t in data['tables']))
else:
    print(0)
")
echo "Scale event rows in load window: ${SCALE_EVENTS_COUNT}"
echo ""

echo "=== Phase 9: emit H1 gate JSON ==="
UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR REPLICAS_PRE_LOAD REPLICAS_15S REPLICAS_30S REPLICAS_60S REPLICAS_90S SCALE_EVENTS_COUNT UTC_CAPTURED APP_NAME RG LOAD_START_UTC LOAD_END_UTC ACTIVE_REVISION_NAME

python3 <<'PYEOF'
import json, os

replicas_pre_load = int(os.environ['REPLICAS_PRE_LOAD'])
replicas_15s = int(os.environ['REPLICAS_15S'])
replicas_30s = int(os.environ['REPLICAS_30S'])
replicas_60s = int(os.environ['REPLICAS_60S'])
replicas_90s = int(os.environ['REPLICAS_90S'])
scale_events_count = int(os.environ['SCALE_EVENTS_COUNT'])

max_replicas_during_load = max(replicas_15s, replicas_30s, replicas_60s, replicas_90s)

# H1 sub-gates: scale rule mismatch reproduces when replicas stay capped at minReplicas
# (= 1) under sustained load that would normally trigger scaling. The threshold
# (concurrentRequests=500) is far above the actual concurrency (60 concurrent requests),
# so KEDA never requests additional replicas.
h1_sub_gates = {
    'a_baseline_one_replica': replicas_pre_load == 1,
    'b_replicas_did_not_scale_under_load': max_replicas_during_load <= 1,
    'c_no_scaleup_events_observed': scale_events_count == 0,
}
h1_all_subgates_pass = all(h1_sub_gates.values())

if h1_all_subgates_pass:
    gate_classification = 'scale_rule_mismatch_replicas_capped'
elif max_replicas_during_load >= 2:
    gate_classification = 'scale_rule_responded_unexpectedly'
else:
    gate_classification = 'partial_observation_some_subgates_failed'

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'app_name': os.environ['APP_NAME'],
    'rg': os.environ['RG'],
    'active_revision': os.environ['ACTIVE_REVISION_NAME'],
    'load_window': {
        'start_utc': os.environ['LOAD_START_UTC'],
        'end_utc': os.environ['LOAD_END_UTC'],
        'duration_seconds': 90,
        'concurrent_requests_generated': 60,
        'scale_rule_threshold_configured': 500,
    },
    'replicas_observed': {
        'pre_load': replicas_pre_load,
        'at_15s': replicas_15s,
        'at_30s': replicas_30s,
        'at_60s': replicas_60s,
        'at_90s': replicas_90s,
        'max_during_load': max_replicas_during_load,
    },
    'scale_events_count': scale_events_count,
    'h1_sub_gates': h1_sub_gates,
    'h1_all_subgates_pass': h1_all_subgates_pass,
    'gate_classification': gate_classification,
}

with open(os.path.join(os.environ['EVIDENCE_DIR'], '10-h1-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)

print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== H1 summary ==="
echo "Pre-load replicas: ${REPLICAS_PRE_LOAD} (expect 1)"
echo "Max replicas during 90 s load: $(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/10-h1-gate.json')); print(d['replicas_observed']['max_during_load'])") (expect 1 with mismatched threshold)"
echo "Scale events in load window: ${SCALE_EVENTS_COUNT} (expect 0)"
GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/10-h1-gate.json'))['gate_classification'])")
echo "Gate classification: ${GATE}"

if [ "$GATE" = "scale_rule_mismatch_replicas_capped" ]; then
    echo ""
    echo "H1 PASS: trigger (mismatched scale rule concurrentRequests=500 vs realistic load of 60 concurrent)"
    echo "produced the documented failure signature (replicas capped at 1 under sustained load, no KEDA"
    echo "scale events emitted). Proceed to verify.sh."
    exit 0
elif [ "$GATE" = "scale_rule_responded_unexpectedly" ]; then
    echo ""
    echo "H1 FALSIFIED: replicas scaled to $(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/10-h1-gate.json'))['replicas_observed']['max_during_load'])") under load that should not have crossed the threshold."
    echo "Investigate before proceeding."
    exit 2
else
    echo ""
    echo "H1 PARTIAL: some sub-gates failed. Inspect 10-h1-gate.json for details."
    exit 2
fi
