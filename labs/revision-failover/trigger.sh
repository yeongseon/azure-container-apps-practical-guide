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
echo "Note: This lab reproduces an ingress targetPort misconfiguration failure. The Bicep deploys"
echo "the app with ingress.targetPort=8000 and a placeholder image. Phase 1-2 build and deploy the"
echo "custom Flask + Gunicorn workload (listening on 0.0.0.0:8000) so the baseline revision is"
echo "Healthy and serving HTTP 200. Phase 7 flips ingress.targetPort to 9999 via az containerapp"
echo "ingress update (which does NOT create a new revision; ingress is an app-level configuration"
echo "shared across all revisions). The platform startup probe then targets port 9999 where nothing"
echo "is listening, so the same revision transitions from Healthy to Degraded within ~60-90 s. HTTP"
echo "requests to the FQDN start failing because the platform deems the revision non-Healthy."
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
    --image "labrevision:v1" \
    ./workload \
    > "$EVIDENCE_DIR/01-acr-build-result.txt" 2>&1
echo "Built and pushed ${ACR_LOGIN_SERVER}/labrevision:v1"
echo ""

echo "=== Phase 2: set registry credentials + update container app to custom image (baseline Healthy) ==="
# Azure CLI 2.71.0+ rejects combined `az containerapp update --target-port --registry-server ...`
# in a single call (argument conflict), so the registry attachment and the image swap are split
# into two calls. The Bicep already provisions ingress with targetPort=8000, so no ingress change
# is needed in trigger.sh; the baseline state inherits the correct port from the deployment.
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
    --image "${ACR_LOGIN_SERVER}/labrevision:v1" \
    --output json \
    > "$EVIDENCE_DIR/02-containerapp-update-baseline.json"
echo "Updated container app to image labrevision:v1 (baseline state)"
echo ""

echo "=== Phase 3: wait for baseline LATEST revision to become Healthy ==="
HEALTHY_TIMEOUT=300
HEALTHY_INTERVAL=10
elapsed=0
revision_health=""
LATEST_REV_NAME=""
while [ $elapsed -lt $HEALTHY_TIMEOUT ]; do
    LATEST_REV_NAME=$(az containerapp show \
        --subscription "$AZ_SUBSCRIPTION" \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --query "properties.latestRevisionName" \
        --output tsv 2>/dev/null || echo "")
    if [ -n "$LATEST_REV_NAME" ]; then
        revision_health=$(az containerapp revision show \
            --subscription "$AZ_SUBSCRIPTION" \
            --name "$APP_NAME" \
            --resource-group "$RG" \
            --revision "$LATEST_REV_NAME" \
            --query "properties.healthState" \
            --output tsv 2>/dev/null || echo "")
        echo "Poll at +${elapsed}s: latestRevisionName=${LATEST_REV_NAME}, healthState=${revision_health}"
    else
        echo "Poll at +${elapsed}s: latestRevisionName not yet available"
    fi
    if [ "$revision_health" = "Healthy" ]; then
        echo "Baseline latest revision ${LATEST_REV_NAME} is Healthy after ${elapsed}s"
        break
    fi
    sleep $HEALTHY_INTERVAL
    elapsed=$((elapsed + HEALTHY_INTERVAL))
done
if [ "$revision_health" != "Healthy" ]; then
    echo "ERROR: baseline latest revision did not become Healthy within ${HEALTHY_TIMEOUT}s"
    exit 1
fi
echo ""

echo "=== Phase 4: capture container app baseline state (expect targetPort=8000, healthState=Healthy) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "{name: name, provisioningState: properties.provisioningState, latestRevisionName: properties.latestRevisionName, fqdn: properties.configuration.ingress.fqdn, targetPort: properties.configuration.ingress.targetPort, activeRevisionsMode: properties.configuration.activeRevisionsMode}" \
    --output json \
    > "$EVIDENCE_DIR/03-containerapp-show-baseline.json"
cat "$EVIDENCE_DIR/03-containerapp-show-baseline.json"
echo ""

FQDN=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/03-containerapp-show-baseline.json'))['fqdn'])")
BASELINE_REVISION_NAME=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/03-containerapp-show-baseline.json'))['latestRevisionName'])")
BASELINE_TARGET_PORT=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/03-containerapp-show-baseline.json'))['targetPort'])")
URL="https://${FQDN}/"
echo "Baseline FQDN: ${FQDN}"
echo "Baseline URL: ${URL}"
echo "Baseline revision: ${BASELINE_REVISION_NAME}"
echo "Baseline targetPort: ${BASELINE_TARGET_PORT}"
echo ""

if [ "$BASELINE_TARGET_PORT" != "8000" ]; then
    echo "ERROR: baseline targetPort is ${BASELINE_TARGET_PORT}, expected 8000. Aborting."
    exit 1
fi

echo "=== Phase 5: capture baseline revision list (expect 1 active revision Healthy at 100% traffic) ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, trafficWeight: properties.trafficWeight, runningState: properties.runningState, createdTime: properties.createdTime, replicas: properties.replicas}" \
    --output json \
    > "$EVIDENCE_DIR/04-revision-list-baseline.json"
cat "$EVIDENCE_DIR/04-revision-list-baseline.json"
echo ""

echo "=== Phase 6: baseline HTTP probe (expect HTTP 200) ==="
BASELINE_CURL_HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" --max-time 10 "$URL" || echo "000")
echo "Baseline HTTP code from ${URL}: ${BASELINE_CURL_HTTP_CODE}" > "$EVIDENCE_DIR/05-curl-baseline.txt"
cat "$EVIDENCE_DIR/05-curl-baseline.txt"
echo ""

echo "=== Phase 7: BREAK — flip ingress targetPort from 8000 to 9999 ==="
# Ingress targetPort is an app-level configuration (not a revision-level template setting), so
# this update modifies the same revision in place. The platform startup probe is re-targeted to
# port 9999 where nothing is listening (the Gunicorn container still binds to 8000), and the
# revision will transition from Healthy to Degraded within ~60-90 s as probe failures accumulate.
BREAK_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Break UTC: $BREAK_UTC"
az containerapp ingress update \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --target-port 9999 \
    --output json \
    > "$EVIDENCE_DIR/06-containerapp-ingress-update-broken.json"
cat "$EVIDENCE_DIR/06-containerapp-ingress-update-broken.json"
echo ""

echo "=== Phase 8: poll for revision health to transition from Healthy to non-Healthy ==="
# Budget tuned from the 2026-06-23 reproduction (measured 261 s wall clock from break command to
# healthState=Unhealthy). The platform startup probe applies a retry budget before reclassifying
# the revision, and the exact threshold varies with probe configuration and CLI / extension
# version. 420 s leaves headroom for slower runs.
BREAK_TIMEOUT=420
BREAK_INTERVAL=10
elapsed=0
break_revision_health="Healthy"
SECONDS_TO_DEGRADED=""
BREAK_POLL_START_EPOCH=$(date +%s)
while [ $elapsed -lt $BREAK_TIMEOUT ]; do
    break_revision_health=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --revision "$BASELINE_REVISION_NAME" \
        --query "properties.healthState" \
        --output tsv 2>/dev/null || echo "Unknown")
    echo "Poll at +${elapsed}s ($(date -u +%H:%M:%SZ)): healthState=${break_revision_health}"
    if [ "$break_revision_health" != "Healthy" ] && [ -n "$break_revision_health" ] && [ "$break_revision_health" != "Unknown" ]; then
        DEGRADED_AT_EPOCH=$(date +%s)
        SECONDS_TO_DEGRADED=$(( DEGRADED_AT_EPOCH - BREAK_POLL_START_EPOCH ))
        echo "Revision transitioned away from Healthy after ${SECONDS_TO_DEGRADED}s"
        break
    fi
    sleep $BREAK_INTERVAL
    elapsed=$((elapsed + BREAK_INTERVAL))
done
echo "Final post-break healthState: ${break_revision_health}"
echo ""

echo "=== Phase 9: capture post-break state ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, trafficWeight: properties.trafficWeight, runningState: properties.runningState, createdTime: properties.createdTime, replicas: properties.replicas}" \
    --output json \
    > "$EVIDENCE_DIR/07-revision-list-after-break.json"

az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "{name: name, provisioningState: properties.provisioningState, latestRevisionName: properties.latestRevisionName, fqdn: properties.configuration.ingress.fqdn, targetPort: properties.configuration.ingress.targetPort}" \
    --output json \
    > "$EVIDENCE_DIR/08-containerapp-show-after-break.json"
cat "$EVIDENCE_DIR/08-containerapp-show-after-break.json"
echo ""

POST_BREAK_REVISION_NAME=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-containerapp-show-after-break.json'))['latestRevisionName'])")
POST_BREAK_TARGET_PORT=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-containerapp-show-after-break.json'))['targetPort'])")
echo "Post-break latestRevisionName: ${POST_BREAK_REVISION_NAME} (expected: same as baseline ${BASELINE_REVISION_NAME})"
echo "Post-break targetPort: ${POST_BREAK_TARGET_PORT} (expected: 9999)"
echo ""

echo "=== Phase 10: query ContainerAppSystemLogs_CL for probe / deployment failures during break window ==="
BREAK_END_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# The strict filter targets probe + deployment failure event families. The Reason_s contains
# clauses are intentionally bounded by `or` (KQL operator precedence binds `and` tighter than
# `or`, so the parens around the OR group keep the filter scoped correctly).
KQL_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where RevisionName_s == '${BASELINE_REVISION_NAME}' | where TimeGenerated between (datetime(${BREAK_UTC}) .. datetime(${BREAK_END_UTC})) | where Reason_s contains 'Probe' or Reason_s contains 'Deployment' or Reason_s contains 'Unhealthy' or Reason_s contains 'TargetPort' or Reason_s contains 'Failed' | project TimeGenerated, Reason_s, Log_s, RevisionName_s | sort by TimeGenerated asc | take 100"
az monitor log-analytics query \
    --subscription "$AZ_SUBSCRIPTION" \
    --workspace "$WORKSPACE_CUSTOMER_ID" \
    --analytics-query "$KQL_QUERY" \
    --output json \
    > "$EVIDENCE_DIR/09-system-logs-probe-failures.json" 2>&1 || echo "[]" > "$EVIDENCE_DIR/09-system-logs-probe-failures.json"
PROBE_FAILURE_COUNT=$(python3 -c "
import json
data = json.load(open('$EVIDENCE_DIR/09-system-logs-probe-failures.json'))
if isinstance(data, list):
    print(len(data))
elif isinstance(data, dict) and 'tables' in data:
    print(sum(len(t.get('rows', [])) for t in data['tables']))
else:
    print(0)
")
echo "Probe/deployment failure rows in break window: ${PROBE_FAILURE_COUNT}"
echo ""

echo "=== Phase 11: post-break HTTP probe (expect non-200 or timeout) ==="
POST_BREAK_CURL_HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" --max-time 10 "$URL" || echo "000")
echo "Post-break HTTP code from ${URL}: ${POST_BREAK_CURL_HTTP_CODE}" > "$EVIDENCE_DIR/10-curl-after-break.txt"
cat "$EVIDENCE_DIR/10-curl-after-break.txt"
echo ""

echo "=== Phase 12: emit H1 gate JSON ==="
UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR APP_NAME RG BASELINE_REVISION_NAME POST_BREAK_REVISION_NAME UTC_CAPTURED
export BASELINE_TARGET_PORT POST_BREAK_TARGET_PORT BREAK_UTC BREAK_END_UTC
export BASELINE_CURL_HTTP_CODE POST_BREAK_CURL_HTTP_CODE
export BREAK_REVISION_HEALTH="$break_revision_health"
export PROBE_FAILURE_COUNT SECONDS_TO_DEGRADED

python3 <<'PYEOF'
import json, os

baseline_curl_http_code = os.environ['BASELINE_CURL_HTTP_CODE']
post_break_curl_http_code = os.environ['POST_BREAK_CURL_HTTP_CODE']
break_revision_health = os.environ['BREAK_REVISION_HEALTH']
baseline_target_port = int(os.environ['BASELINE_TARGET_PORT'])
post_break_target_port = int(os.environ['POST_BREAK_TARGET_PORT'])
probe_failure_count = int(os.environ['PROBE_FAILURE_COUNT'])
seconds_to_degraded_env = os.environ.get('SECONDS_TO_DEGRADED', '')

# H1 sub-gates: revision-failover break reproduces when ingress targetPort flip from 8000
# to 9999 causes the same revision to transition from Healthy to non-Healthy AND HTTP
# requests to the FQDN start failing.
h1_sub_gates = {
    'a_baseline_curl_succeeded': baseline_curl_http_code == '200',
    'b_break_applied_target_port_is_9999': post_break_target_port == 9999,
    'c_revision_no_longer_healthy_after_break': break_revision_health != 'Healthy',
    'd_post_break_curl_failed': post_break_curl_http_code != '200',
}
h1_all_subgates_pass = all(h1_sub_gates.values())

# Note: revision name should stay the same across baseline -> post-break because ingress
# is an app-level configuration, not a revision-level template field. This is tracked as
# a separate observation (not a sub-gate) because Azure may occasionally emit a new revision
# name for the same in-place change depending on activeRevisionsMode and the CLI version.
revision_name_unchanged = os.environ['BASELINE_REVISION_NAME'] == os.environ['POST_BREAK_REVISION_NAME']

if h1_all_subgates_pass:
    gate_classification = 'revision_failover_broken_revision_unhealthy'
elif break_revision_health == 'Healthy' and post_break_curl_http_code == '200':
    gate_classification = 'revision_failover_break_did_not_materialize'
else:
    gate_classification = 'partial_observation_some_subgates_failed'

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'app_name': os.environ['APP_NAME'],
    'rg': os.environ['RG'],
    'baseline_revision_name': os.environ['BASELINE_REVISION_NAME'],
    'post_break_revision_name': os.environ['POST_BREAK_REVISION_NAME'],
    'revision_name_unchanged': revision_name_unchanged,
    'break_window': {
        'start_utc': os.environ['BREAK_UTC'],
        'end_utc': os.environ['BREAK_END_UTC'],
        'baseline_target_port': baseline_target_port,
        'post_break_target_port': post_break_target_port,
    },
    'curl_observations': {
        'baseline_http_code': baseline_curl_http_code,
        'post_break_http_code': post_break_curl_http_code,
    },
    'health_observations': {
        'post_break_health_state': break_revision_health,
        'seconds_to_non_healthy': int(seconds_to_degraded_env) if seconds_to_degraded_env else None,
    },
    'probe_failure_count': probe_failure_count,
    'h1_sub_gates': h1_sub_gates,
    'h1_all_subgates_pass': h1_all_subgates_pass,
    'gate_classification': gate_classification,
}

with open(os.path.join(os.environ['EVIDENCE_DIR'], '11-h1-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)

print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== H1 summary ==="
echo "Baseline curl HTTP code: ${BASELINE_CURL_HTTP_CODE} (expect 200)"
echo "Post-break targetPort: ${POST_BREAK_TARGET_PORT} (expect 9999)"
echo "Post-break healthState: ${break_revision_health} (expect non-Healthy)"
echo "Post-break curl HTTP code: ${POST_BREAK_CURL_HTTP_CODE} (expect non-200)"
echo "Probe/deployment failure rows: ${PROBE_FAILURE_COUNT}"
GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/11-h1-gate.json'))['gate_classification'])")
echo "Gate classification: ${GATE}"

if [ "$GATE" = "revision_failover_broken_revision_unhealthy" ]; then
    echo ""
    echo "H1 PASS: trigger (ingress targetPort flip 8000 -> 9999) produced the documented failure"
    echo "signature (same revision transitioned to non-Healthy AND HTTP requests started failing)."
    echo "Proceed to verify.sh."
    exit 0
elif [ "$GATE" = "revision_failover_break_did_not_materialize" ]; then
    echo ""
    echo "H1 FALSIFIED: revision remained Healthy and HTTP 200 after targetPort flip to 9999."
    echo "Investigate before proceeding (probe behavior may differ in this CLI / platform version)."
    exit 2
else
    echo ""
    echo "H1 PARTIAL: some sub-gates failed. Inspect 11-h1-gate.json for details."
    exit 2
fi
