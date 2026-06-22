#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${ACR_NAME:?Set ACR_NAME before running}"
: "${ACR_LOGIN_SERVER:?Set ACR_LOGIN_SERVER before running}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "trigger.sh starting at ${UTC_NOW}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "ACR: ${ACR_NAME}"
echo "ACR login server: ${ACR_LOGIN_SERVER}"
echo ""
echo "Note: This lab's trigger is the Bicep deployment in Quick Start step 2, which is EXPECTED to fail"
echo "with MANIFEST_UNKNOWN because the Container App references labacr:does-not-exist (a tag that was"
echo "never pushed to ACR). This script captures the post-deployment failure state; it does NOT mutate"
echo "state."
echo ""

echo "=== Phase 1: capture deployment failure result (expect provisioningState=Failed + MANIFEST_UNKNOWN) ==="
az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "{name: name, provisioningState: properties.provisioningState, timestamp: properties.timestamp, error: properties.error, correlationId: properties.correlationId}" \
    --output json \
    > "$EVIDENCE_DIR/01-deployment-result.json"
cat "$EVIDENCE_DIR/01-deployment-result.json"
echo ""

echo "=== Phase 1b: capture failed deployment operations (this is where MANIFEST_UNKNOWN actually surfaces) ==="
# `az deployment group show --query "properties.error"` truncates the per-resource failure
# tree (the inner-most `details` is null in the group-show response). The per-operation
# detail with the MANIFEST_UNKNOWN smoking gun lives in `az deployment operation group list`
# under properties.statusMessage.error.message. We capture it as a separate evidence file so
# the classifier can grep both files for MANIFEST_UNKNOWN attribution.
az deployment operation group list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "[?properties.provisioningState=='Failed'].{operationId: operationId, resourceType: properties.targetResource.resourceType, resourceName: properties.targetResource.resourceName, statusMessage: properties.statusMessage}" \
    --output json \
    > "$EVIDENCE_DIR/01-deployment-operations-failed.json"
cat "$EVIDENCE_DIR/01-deployment-operations-failed.json"
echo ""

DEPLOYMENT_STATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/01-deployment-result.json'))['provisioningState'])")
DEPLOYMENT_ERROR_MESSAGE=$(python3 -c "
import json
# Recursively walk both the deployment error tree AND the per-operation statusMessage tree.
# Azure Resource Manager places the MANIFEST_UNKNOWN smoking gun in the per-operation
# response (01-deployment-operations-failed.json -> statusMessage.error.message) but truncates
# it in the group-show response (01-deployment-result.json -> error.details[*].details is null).
# By concatenating all .message strings found across both files we get an aggregate that the
# classifier can grep for MANIFEST_UNKNOWN regardless of where the platform put it.

def walk(node, parts):
    if isinstance(node, dict):
        msg = node.get('message')
        if isinstance(msg, str) and msg:
            parts.append(msg)
        for v in node.values():
            if isinstance(v, (dict, list)):
                walk(v, parts)
    elif isinstance(node, list):
        for item in node:
            walk(item, parts)

parts = []
walk(json.load(open('$EVIDENCE_DIR/01-deployment-result.json')).get('error') or {}, parts)
ops = json.load(open('$EVIDENCE_DIR/01-deployment-operations-failed.json'))
for op in ops:
    walk(op.get('statusMessage') or {}, parts)
print(' || '.join(parts))
")
echo "Deployment provisioningState: $DEPLOYMENT_STATE"
echo "Deployment error.message (truncated 500 chars): ${DEPLOYMENT_ERROR_MESSAGE:0:500}"
echo ""

echo "=== Phase 2: capture container app baseline state (expect provisioningState=Failed, latestRevisionName=null) ==="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{name: name, provisioningState: properties.provisioningState, latestRevisionName: properties.latestRevisionName, latestRevisionFqdn: properties.latestRevisionFqdn, ingress: properties.configuration.ingress, image: properties.template.containers[0].image}" \
    --output json \
    > "$EVIDENCE_DIR/02-containerapp-show-baseline.json"
cat "$EVIDENCE_DIR/02-containerapp-show-baseline.json"
echo ""

APP_PROVISIONING_STATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/02-containerapp-show-baseline.json'))['provisioningState'])")
APP_LATEST_REVISION=$(python3 -c "
import json
d = json.load(open('$EVIDENCE_DIR/02-containerapp-show-baseline.json'))
v = d.get('latestRevisionName')
print('' if v is None else v)
")
APP_IMAGE_REFERENCE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/02-containerapp-show-baseline.json'))['image'])")
echo "Container App provisioningState: $APP_PROVISIONING_STATE"
echo "Container App latestRevisionName: '$APP_LATEST_REVISION' (empty string = null)"
echo "Container App image reference: $APP_IMAGE_REFERENCE"
echo ""

echo "=== Phase 3: capture revision list (expect [] empty) ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --output json \
    > "$EVIDENCE_DIR/03-revisions-list-baseline.json"
cat "$EVIDENCE_DIR/03-revisions-list-baseline.json"
echo ""

REVISION_COUNT=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/03-revisions-list-baseline.json'))))")
echo "Revision count: $REVISION_COUNT"
echo ""

echo "=== Phase 4: capture ACR repository list (expect labacr repository absent) ==="
az acr repository list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$ACR_NAME" \
    --output json \
    > "$EVIDENCE_DIR/04-acr-repository-list-baseline.json"
cat "$EVIDENCE_DIR/04-acr-repository-list-baseline.json"
echo ""

LABACR_PRESENT=$(python3 -c "
import json
repos = json.load(open('$EVIDENCE_DIR/04-acr-repository-list-baseline.json'))
print('true' if 'labacr' in repos else 'false')
")
echo "labacr repository present in ACR: $LABACR_PRESENT"
echo ""

echo "=== Phase 5: attempt system log capture (expect KeyError: 'eventStreamEndpoint' because no revision exists) ==="
set +e
az containerapp logs show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --type system \
    --tail 20 \
    > "$EVIDENCE_DIR/05-system-logs-show-error.txt" 2>&1
SYSTEM_LOGS_EXIT=$?
set -e
echo "az containerapp logs show --type system exit code: $SYSTEM_LOGS_EXIT"
echo "Captured output (truncated to first 500 chars):"
head -c 500 "$EVIDENCE_DIR/05-system-logs-show-error.txt" || true
echo ""
echo ""

SYSTEM_LOGS_KEYERROR=$(python3 -c "
with open('$EVIDENCE_DIR/05-system-logs-show-error.txt') as f:
    t = f.read()
print('true' if 'eventStreamEndpoint' in t or 'KeyError' in t else 'false')
")
echo "system log capture surfaced eventStreamEndpoint / KeyError signature: $SYSTEM_LOGS_KEYERROR"
echo ""

echo "=== Phase 6: capture Activity Log entries (Failed Create or Update Container App, last 1 hour) ==="
START_TIME="$(python3 -c "
import datetime as d
print((d.datetime.utcnow() - d.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))
")"
az monitor activity-log list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --start-time "$START_TIME" \
    --query "[?status.value=='Failed' && contains(resourceType.value, 'Microsoft.App')].{timestamp: eventTimestamp, operationName: operationName.localizedValue, status: status.value, subStatus: subStatus.value, resourceId: resourceId, correlationId: correlationId, statusMessage: properties.statusMessage}" \
    --output json \
    > "$EVIDENCE_DIR/06-activity-log-failed.json"
cat "$EVIDENCE_DIR/06-activity-log-failed.json"
echo ""

ACTIVITY_LOG_FAILED_COUNT=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/06-activity-log-failed.json'))))")
echo "Failed Microsoft.App activity log entries in last 1 hour: $ACTIVITY_LOG_FAILED_COUNT"
echo ""

export EVIDENCE_DIR DEPLOYMENT_STATE DEPLOYMENT_ERROR_MESSAGE APP_PROVISIONING_STATE APP_LATEST_REVISION REVISION_COUNT LABACR_PRESENT SYSTEM_LOGS_KEYERROR ACTIVITY_LOG_FAILED_COUNT

python3 <<'PYEOF'
import json, os

# Deployment-level H1 gate taxonomy for ACR pull failure (no KQL gate at H1 because no container
# ever starts, no revision is created, and ContainerAppSystemLogs_CL is never materialized):
#
#   deployment_failed_manifest_unknown    - provisioningState=Failed AND error.message contains MANIFEST_UNKNOWN
#                                           (expected H1 outcome — the bad tag produced the documented failure)
#   deployment_failed_other               - provisioningState=Failed AND error.message does NOT contain MANIFEST_UNKNOWN
#                                           (a different failure mode was produced; investigate before proceeding)
#   deployment_succeeded_no_revision      - provisioningState=Succeeded AND latestRevisionName is empty
#                                           (unusual; deployment somehow succeeded without creating a revision)
#   deployment_succeeded_revision_present - H1 FALSIFIED — provisioningState=Succeeded AND latestRevisionName is populated
#                                           (the bad tag did not produce the documented failure mode)

deployment_state = os.environ['DEPLOYMENT_STATE']
deployment_error_message = os.environ['DEPLOYMENT_ERROR_MESSAGE']
app_provisioning_state = os.environ['APP_PROVISIONING_STATE']
app_latest_revision = os.environ['APP_LATEST_REVISION']
revision_count = int(os.environ['REVISION_COUNT'])
labacr_present = os.environ['LABACR_PRESENT'] == 'true'
system_logs_keyerror = os.environ['SYSTEM_LOGS_KEYERROR'] == 'true'
activity_log_failed_count = int(os.environ['ACTIVITY_LOG_FAILED_COUNT'])

manifest_unknown_in_error = 'MANIFEST_UNKNOWN' in deployment_error_message or 'manifest unknown' in deployment_error_message.lower() or 'manifest tagged' in deployment_error_message.lower()

if deployment_state == 'Failed':
    if manifest_unknown_in_error:
        gate_classification = 'deployment_failed_manifest_unknown'
    else:
        gate_classification = 'deployment_failed_other'
elif deployment_state == 'Succeeded':
    if not app_latest_revision:
        gate_classification = 'deployment_succeeded_no_revision'
    else:
        gate_classification = 'deployment_succeeded_revision_present'
else:
    gate_classification = 'deployment_in_unknown_state'

# H1 sub-gates:
#   A. deployment must be Failed with MANIFEST_UNKNOWN attribution
#   B. Container App resource must exist with provisioningState=Failed
#   C. latestRevisionName must be null (empty string here, normalized from null)
#   D. revision list must be empty
#   E. labacr repository must be absent from ACR (since v1 was never built/pushed)
h1_sub_gates = {
    'a_deployment_failed_with_manifest_unknown': deployment_state == 'Failed' and manifest_unknown_in_error,
    'b_app_provisioning_state_failed': app_provisioning_state == 'Failed',
    'c_latest_revision_name_null': not app_latest_revision,
    'd_revision_list_empty': revision_count == 0,
    'e_labacr_repository_absent': not labacr_present,
}
h1_all_subgates_pass = all(h1_sub_gates.values())

out = {
    'utc_captured': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'app_name': os.environ.get('APP_NAME', ''),
    'rg': os.environ.get('RG', ''),
    'deployment_state': deployment_state,
    'deployment_error_message_first_500_chars': deployment_error_message[:500],
    'manifest_unknown_in_error': manifest_unknown_in_error,
    'app_provisioning_state': app_provisioning_state,
    'app_latest_revision_name': app_latest_revision,
    'revision_count': revision_count,
    'labacr_repository_present_in_acr': labacr_present,
    'system_logs_show_surfaced_keyerror': system_logs_keyerror,
    'activity_log_failed_count_last_1h': activity_log_failed_count,
    'gate_classification': gate_classification,
    'h1_sub_gates': h1_sub_gates,
    'h1_all_subgates_pass': h1_all_subgates_pass,
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '06-h1-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'gate_classification': out['gate_classification'],
    'h1_all_subgates_pass': out['h1_all_subgates_pass'],
    'h1_sub_gates': out['h1_sub_gates'],
}, indent=2))
PYEOF

H1_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/06-h1-gate.json'))['gate_classification'])")
H1_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/06-h1-gate.json'))['h1_all_subgates_pass'])")

echo ""
echo "=== H1 summary ==="
echo "Deployment state: $DEPLOYMENT_STATE"
echo "App provisioningState: $APP_PROVISIONING_STATE"
echo "App latestRevisionName: '$APP_LATEST_REVISION' (empty = null)"
echo "Revision count: $REVISION_COUNT (expect 0)"
echo "labacr present in ACR: $LABACR_PRESENT (expect false)"
echo "system logs surfaced KeyError: $SYSTEM_LOGS_KEYERROR (expect true)"
echo "Gate classification: $H1_GATE"
echo "All H1 sub-gates pass: $H1_ALL_SUBGATES_PASS"
echo ""

if [[ "$H1_GATE" == "deployment_failed_manifest_unknown" && "$H1_ALL_SUBGATES_PASS" == "True" ]]; then
    echo "H1 PASS: trigger (the Bicep deployment with image labacr:does-not-exist) produced the documented failure signature (deployment Failed + MANIFEST_UNKNOWN + empty revision list + no labacr repo in ACR). Proceed to verify.sh."
    exit 0
fi

if [[ "$H1_GATE" == "deployment_succeeded_revision_present" ]]; then
    echo "H1 FALSIFIED: the Bicep deployment succeeded and a revision exists despite the bad image tag (gate_classification=${H1_GATE}). The lab cannot proceed because the failure state did not materialize."
    exit 2
fi

if [[ "$H1_GATE" == "deployment_failed_other" ]]; then
    echo "H1 PASS WITH NOTE: deployment failed but the error message does not contain MANIFEST_UNKNOWN (gate_classification=${H1_GATE}). A different failure mode was produced. Inspect 01-deployment-result.json for the actual error before proceeding."
    exit 0
fi

if [[ "$H1_GATE" == "deployment_succeeded_no_revision" ]]; then
    echo "H1 PASS WITH NOTE: deployment succeeded but no revision was created (gate_classification=${H1_GATE}). Unusual outcome. Inspect 02-containerapp-show-baseline.json before proceeding."
    exit 0
fi

echo "H1 INVALID RUN: unexpected gate classification ${H1_GATE}. Inspect evidence files before proceeding."
exit 1
