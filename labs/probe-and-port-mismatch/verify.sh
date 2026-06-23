#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${ACR_NAME:?Set ACR_NAME before running}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "verify.sh starting at ${UTC_NOW}"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "ACR: ${ACR_NAME}"
echo ""

echo "=== Phase 10: validate H1 evidence from trigger.sh ==="
H1_FILE="$EVIDENCE_DIR/11-h1-gate.json"
if [[ ! -f "$H1_FILE" ]]; then
    echo "INVALID RUN: $H1_FILE not found. Run trigger.sh first."
    exit 1
fi
H1_GATE=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['gate_classification'])")
H1_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['h1_all_subgates_pass'])")
TRIGGER_REVISION_NAME=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['trigger_window']['revision_name'])")
TRIGGER_IMAGE=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['trigger_window']['image'])")
TRIGGER_CREATED=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['trigger_window']['created_time'])")
APP_FQDN=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['app_fqdn'])")
echo "H1 state: gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
echo "Trigger revision (from H1): ${TRIGGER_REVISION_NAME}"
echo "Trigger image (from H1): ${TRIGGER_IMAGE}"
echo "Trigger createdTime (from H1): ${TRIGGER_CREATED}"
echo "FQDN: ${APP_FQDN}"
if [[ "$H1_GATE" == "probe_failure_did_not_materialize" ]]; then
    echo "INVALID RUN: H1 was FALSIFIED in trigger.sh. Probe failure did not reproduce so the recovery experiment cannot proceed."
    exit 1
fi
if [[ -z "$TRIGGER_REVISION_NAME" ]]; then
    echo "INVALID RUN: trigger revision name missing from H1 gate JSON."
    exit 1
fi
echo ""

echo "=== Phase 11: re-confirm failure state at start of verify (expected: same revision still showing probe failure) ==="
az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision "$TRIGGER_REVISION_NAME" \
    --query "{name: name, healthState: properties.healthState, runningState: properties.runningState, provisioningState: properties.provisioningState, replicas: properties.replicas, runningStateDetails: properties.runningStateDetails, image: properties.template.containers[0].image, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/12-revision-pre-fix.json"
cat "$EVIDENCE_DIR/12-revision-pre-fix.json"
PRE_FIX_NAME=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/12-revision-pre-fix.json')).get('name') or '')")
PRE_FIX_RUNNING=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/12-revision-pre-fix.json')).get('runningState') or 'Unknown')")
PRE_FIX_CREATED=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/12-revision-pre-fix.json')).get('createdTime') or '')")
PRE_FIX_IMAGE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/12-revision-pre-fix.json')).get('image') or '')")
PRE_FIX_RUNNING_DETAILS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/12-revision-pre-fix.json')).get('runningStateDetails') or '')")
echo "Pre-fix runningState: ${PRE_FIX_RUNNING}"
echo "Pre-fix runningStateDetails: ${PRE_FIX_RUNNING_DETAILS}"
echo "Pre-fix createdTime: ${PRE_FIX_CREATED} (expected: matches H1 trigger createdTime)"
echo "Pre-fix image: ${PRE_FIX_IMAGE}"
echo ""

# createdTime drift between H1 capture and verify.sh start would indicate something
# re-minted the revision between phases (external operator, redeploy, etc.) — fail loudly.
if [[ "$PRE_FIX_CREATED" != "$TRIGGER_CREATED" ]]; then
    echo "INVALID RUN: pre-fix createdTime (${PRE_FIX_CREATED}) does not match H1 trigger createdTime (${TRIGGER_CREATED}). External actor may have re-minted the revision."
    exit 1
fi

echo "=== Phase 12: client HTTP probe pre-fix (expected: 5/5 non-200) ==="
PRE_FIX_CURL_RESULTS=()
PRE_FIX_CURL_SUCCESS_COUNT=0
for i in 1 2 3 4 5; do
    CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "https://${APP_FQDN}/" 2>/dev/null || echo "000")
    PRE_FIX_CURL_RESULTS+=("$CODE")
    if [ "$CODE" = "200" ]; then
        PRE_FIX_CURL_SUCCESS_COUNT=$((PRE_FIX_CURL_SUCCESS_COUNT + 1))
    fi
    echo "Pre-fix probe $i: HTTP ${CODE}"
    sleep 2
done
export EVIDENCE_DIR APP_FQDN PRE_FIX_CURL_SUCCESS_COUNT
export PRE_FIX_CURL_RESULTS_STR="${PRE_FIX_CURL_RESULTS[*]}"
python3 <<'PYEOF'
import json, os
results = os.environ['PRE_FIX_CURL_RESULTS_STR'].split()
out = {
    'fqdn': os.environ['APP_FQDN'],
    'attempts': len(results),
    'http_codes': results,
    'success_count_200': int(os.environ['PRE_FIX_CURL_SUCCESS_COUNT']),
    'phase': 'pre-fix re-confirmation',
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '13-curl-probes-pre-fix.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 13: apply fix — az containerapp ingress update --target-port 3000 (APP-SCOPE, no new revision) ==="
# az containerapp ingress update is app-scope only and does NOT mint a new revision.
# This is the entire point of the H2 falsification: if recovery happens on the SAME
# revision (same name AND same createdTime), then alternative theories that require
# a new revision (broken image, ACR pull failure, probe-config bug, revision-template
# defect) are all falsified — the only remaining cause consistent with the recovery
# is the targetPort vs application listening port mismatch.
FIX_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Fix UTC: ${FIX_UTC}"

set +e
az containerapp ingress update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --target-port 3000 \
    --only-show-errors \
    --output json \
    > "$EVIDENCE_DIR/14-ingress-update-fix.json" \
    2> "$EVIDENCE_DIR/14-ingress-update-fix.stderr"
FIX_EXIT_CODE=$?
set -e
echo "Ingress update exit code: ${FIX_EXIT_CODE} (expected: 0)"
if [ "$FIX_EXIT_CODE" -ne 0 ]; then
    echo "Fix stderr:"
    cat "$EVIDENCE_DIR/14-ingress-update-fix.stderr" || true
fi
echo ""

echo "=== Phase 14: wait for revision to become healthy (poll up to 3 minutes) ==="
WAIT_LOG="$EVIDENCE_DIR/15-wait-recovery.log"
: > "$WAIT_LOG"
ATTEMPTS=18
for i in $(seq 1 $ATTEMPTS); do
    RUN_STATE=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$TRIGGER_REVISION_NAME" \
        --query "properties.runningState" \
        --output tsv 2>/dev/null | tr -d '\r' || echo "Unknown")
    HEALTH=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$TRIGGER_REVISION_NAME" \
        --query "properties.healthState" \
        --output tsv 2>/dev/null | tr -d '\r' || echo "Unknown")
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "[$ts] attempt $i/$ATTEMPTS runningState=${RUN_STATE} healthState=${HEALTH}" | tee -a "$WAIT_LOG"
    if [ "$RUN_STATE" = "Running" ] && [ "$HEALTH" = "Healthy" ]; then
        break
    fi
    sleep 10
done
echo ""

echo "=== Phase 15: capture post-fix revision state (expected: same name + same createdTime, now Running/Healthy) ==="
az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision "$TRIGGER_REVISION_NAME" \
    --query "{name: name, healthState: properties.healthState, runningState: properties.runningState, provisioningState: properties.provisioningState, replicas: properties.replicas, runningStateDetails: properties.runningStateDetails, image: properties.template.containers[0].image, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/16-revision-post-fix.json"
cat "$EVIDENCE_DIR/16-revision-post-fix.json"
POST_FIX_HEALTH=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/16-revision-post-fix.json')).get('healthState') or 'Unknown')")
POST_FIX_RUNNING=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/16-revision-post-fix.json')).get('runningState') or 'Unknown')")
POST_FIX_CREATED=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/16-revision-post-fix.json')).get('createdTime') or '')")
POST_FIX_IMAGE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/16-revision-post-fix.json')).get('image') or '')")
POST_FIX_NAME=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/16-revision-post-fix.json')).get('name') or '')")
echo "Post-fix healthState: ${POST_FIX_HEALTH} (expected: Healthy)"
echo "Post-fix runningState: ${POST_FIX_RUNNING} (expected: Running)"
echo "Post-fix createdTime: ${POST_FIX_CREATED} (expected: ${PRE_FIX_CREATED} — same revision proof)"
echo "Post-fix image: ${POST_FIX_IMAGE} (expected: ${PRE_FIX_IMAGE} — same image proof)"
echo ""

POST_FIX_TARGET_PORT=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.ingress.targetPort" \
    --output tsv | tr -d '\r')
echo "Post-fix ingress targetPort: ${POST_FIX_TARGET_PORT} (expected: 3000 — now matches workload)"
echo ""

echo "=== Phase 16: client HTTP probe post-fix (expected: 5/5 200) ==="
POST_FIX_CURL_RESULTS=()
POST_FIX_CURL_SUCCESS_COUNT=0
for i in 1 2 3 4 5; do
    CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "https://${APP_FQDN}/" 2>/dev/null || echo "000")
    POST_FIX_CURL_RESULTS+=("$CODE")
    if [ "$CODE" = "200" ]; then
        POST_FIX_CURL_SUCCESS_COUNT=$((POST_FIX_CURL_SUCCESS_COUNT + 1))
    fi
    echo "Post-fix probe $i: HTTP ${CODE}"
    sleep 2
done
export EVIDENCE_DIR APP_FQDN POST_FIX_CURL_SUCCESS_COUNT
export POST_FIX_CURL_RESULTS_STR="${POST_FIX_CURL_RESULTS[*]}"
python3 <<'PYEOF'
import json, os
results = os.environ['POST_FIX_CURL_RESULTS_STR'].split()
out = {
    'fqdn': os.environ['APP_FQDN'],
    'attempts': len(results),
    'http_codes': results,
    'success_count_200': int(os.environ['POST_FIX_CURL_SUCCESS_COUNT']),
    'phase': 'post-fix recovery verification',
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '17-curl-probes-post-fix.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 17: full revision list post-fix (expected: same trigger revision Healthy/Running at 100% traffic) ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, runningState: properties.runningState, trafficWeight: properties.trafficWeight, createdTime: properties.createdTime, image: properties.template.containers[0].image}" \
    --output json \
    > "$EVIDENCE_DIR/18-revision-list-post-fix.json"
cat "$EVIDENCE_DIR/18-revision-list-post-fix.json"
echo ""

echo "=== Phase 18: capture metadata + emit H2 gate ==="
az version --output json > "$EVIDENCE_DIR/19-cli-versions.json" 2>&1 || true
az extension list --query "[?name=='containerapp']" --output json > "$EVIDENCE_DIR/20-cli-containerapp-ext.json" 2>&1 || true
az group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --query "{name: name, location: location}" \
    --output json \
    > "$EVIDENCE_DIR/21-region.json" 2>&1 || true

UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR AZ_SUBSCRIPTION RG APP_NAME ACR_NAME APP_FQDN
export TRIGGER_REVISION_NAME TRIGGER_CREATED TRIGGER_IMAGE
export PRE_FIX_RUNNING PRE_FIX_CREATED PRE_FIX_IMAGE PRE_FIX_CURL_SUCCESS_COUNT PRE_FIX_CURL_RESULTS_STR
export PRE_FIX_RUNNING_DETAILS PRE_FIX_NAME
export FIX_UTC FIX_EXIT_CODE
export POST_FIX_HEALTH POST_FIX_RUNNING POST_FIX_CREATED POST_FIX_IMAGE POST_FIX_TARGET_PORT POST_FIX_NAME
export POST_FIX_CURL_SUCCESS_COUNT POST_FIX_CURL_RESULTS_STR UTC_CAPTURED

python3 <<'PYEOF'
import json, os

pre_fix_running = os.environ['PRE_FIX_RUNNING']
pre_fix_created = os.environ['PRE_FIX_CREATED']
pre_fix_image = os.environ['PRE_FIX_IMAGE']
pre_fix_name = os.environ.get('PRE_FIX_NAME', '')
pre_fix_running_details = os.environ.get('PRE_FIX_RUNNING_DETAILS', '')
pre_fix_curl_success = int(os.environ['PRE_FIX_CURL_SUCCESS_COUNT'])
trigger_created = os.environ['TRIGGER_CREATED']
trigger_image = os.environ['TRIGGER_IMAGE']
fix_exit_code = int(os.environ['FIX_EXIT_CODE'])
post_fix_health = os.environ['POST_FIX_HEALTH']
post_fix_running = os.environ['POST_FIX_RUNNING']
post_fix_created = os.environ['POST_FIX_CREATED']
post_fix_image = os.environ['POST_FIX_IMAGE']
post_fix_name = os.environ.get('POST_FIX_NAME', '')
post_fix_target_port = os.environ['POST_FIX_TARGET_PORT']
post_fix_curl_success = int(os.environ['POST_FIX_CURL_SUCCESS_COUNT'])

# Read H1 syslog evidence from the trigger.sh-emitted gate file. H2's failure-
# evidence predicate mirrors trigger.sh's H1 c-gate: port-specific corroboration
# is required, not a bare 'Failed'/'Degraded' label. verify.sh does not capture
# its own syslog stream (the cost is paid once during trigger.sh), so the H1
# ProbeFailed count is the authoritative fallback signal.
h1_path = os.path.join(os.environ['EVIDENCE_DIR'], '11-h1-gate.json')
with open(h1_path) as h1f:
    h1_data = json.load(h1f)
h1_syslog_probe_failed_count = h1_data.get(
    'system_log_capture', {}
).get('probe_failed_lines_in_tail', 0)

# H2 sub-gate a requires PORT-SPECIFIC evidence that the failure state persists
# into verify.sh — same acceptance discipline as H1 sub-gate c. Two paths:
#   Strong  : pre_fix runningStateDetails contains explicit port/probe text.
#   Fallback: pre_fix non-healthy state PAIRED with H1's syslog ProbeFailed
#             count > 0 (same lab run, same revision, syslog snapshot applies).
# A bare 'Failed'/'Degraded' label with NO port-specific corroboration is
# explicitly insufficient — see trigger.sh phase 9 for the full rationale.
pre_fix_probe_failure_evidence = (
    (
        pre_fix_running_details
        and (
            'TargetPort' in pre_fix_running_details
            or 'listening port' in pre_fix_running_details
            or 'ProbeFailed' in pre_fix_running_details
        )
    )
    or (
        pre_fix_running in ('Failed', 'Degraded')
        and h1_syslog_probe_failed_count > 0
    )
)
a_failure_state_persisted_into_verify = (
    pre_fix_probe_failure_evidence
    and pre_fix_created == trigger_created
    and pre_fix_curl_success == 0
)
b_ingress_update_succeeded = fix_exit_code == 0
c_revision_became_healthy = (
    post_fix_running == 'Running'
    and post_fix_health == 'Healthy'
)
d_client_probes_succeed = post_fix_curl_success == 5
# Same-revision proof is triangulated across three platform-emitted fields:
# name (revision identity), createdTime (provisioning timestamp), image (template
# content). The ingress.targetPort edit is an app-scope-only mutation; if ANY of
# these three fields drift between pre_fix and post_fix, a new revision was
# minted and the same-revision claim is falsified.
name_unchanged = bool(pre_fix_name) and bool(post_fix_name) and pre_fix_name == post_fix_name
e_same_revision_preserved = (
    post_fix_created == pre_fix_created
    and post_fix_image == pre_fix_image
    and name_unchanged
)
f_target_port_now_matches = post_fix_target_port == '3000'

h2_sub_gates = {
    'a_failure_state_persisted_into_verify': a_failure_state_persisted_into_verify,
    'b_ingress_update_succeeded': b_ingress_update_succeeded,
    'c_revision_became_healthy': c_revision_became_healthy,
    'd_client_probes_succeed': d_client_probes_succeed,
    'e_same_revision_preserved': e_same_revision_preserved,
    'f_target_port_now_matches': f_target_port_now_matches,
}
h2_all_subgates_pass = all(h2_sub_gates.values())

if h2_all_subgates_pass:
    gate_classification = 'port_mismatch_recovered_on_same_revision'
elif not c_revision_became_healthy or not d_client_probes_succeed:
    gate_classification = 'port_mismatch_did_not_recover'
elif not e_same_revision_preserved:
    gate_classification = 'recovery_required_new_revision'
else:
    gate_classification = 'partial_observation_some_subgates_failed'

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'subscription': os.environ['AZ_SUBSCRIPTION'],
    'rg': os.environ['RG'],
    'app_name': os.environ['APP_NAME'],
    'app_fqdn': os.environ['APP_FQDN'],
    'trigger_revision_name': os.environ['TRIGGER_REVISION_NAME'],
    'pre_fix_state': {
        'running_state': pre_fix_running,
        'running_state_details': pre_fix_running_details,
        'created_time': pre_fix_created,
        'image': pre_fix_image,
        'curl_success_count_200_of_5': pre_fix_curl_success,
    },
    'fix_window': {
        'start_utc': os.environ['FIX_UTC'],
        'command': 'az containerapp ingress update --target-port 3000',
        'cli_exit_code': fix_exit_code,
    },
    'post_fix_state': {
        'health_state': post_fix_health,
        'running_state': post_fix_running,
        'created_time': post_fix_created,
        'image': post_fix_image,
        'ingress_target_port': post_fix_target_port,
        'curl_success_count_200_of_5': post_fix_curl_success,
    },
    'same_revision_proof': {
        'created_time_unchanged': post_fix_created == pre_fix_created,
        'image_unchanged': post_fix_image == pre_fix_image,
        'name_unchanged': name_unchanged,
        'pre_fix_name': pre_fix_name,
        'post_fix_name': post_fix_name,
    },
    'h2_sub_gates': h2_sub_gates,
    'h2_all_subgates_pass': h2_all_subgates_pass,
    'gate_classification': gate_classification,
}

with open(os.path.join(os.environ['EVIDENCE_DIR'], '22-h2-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'gate_classification': out['gate_classification'],
    'h2_all_subgates_pass': out['h2_all_subgates_pass'],
    'h2_sub_gates': out['h2_sub_gates'],
    'same_revision_proof': out['same_revision_proof'],
}, indent=2))
PYEOF
echo ""

H2_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/22-h2-gate.json'))['gate_classification'])")
H2_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/22-h2-gate.json'))['h2_all_subgates_pass'])")

echo "=== Verdict ==="
echo "H1 (trigger.sh): gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
echo "H2 (verify.sh):  gate=${H2_GATE}, all_subgates_pass=${H2_ALL_SUBGATES_PASS}"
echo ""

H1_PASS=false
H2_PASS=false

if [[ "$H1_GATE" == "port_mismatch_probe_failure_reproduced" && "$H1_ALL_SUBGATES_PASS" == "True" ]]; then
    H1_PASS=true
fi
if [[ "$H2_GATE" == "port_mismatch_recovered_on_same_revision" && "$H2_ALL_SUBGATES_PASS" == "True" ]]; then
    H2_PASS=true
fi

echo "H1 PASS: $H1_PASS"
echo "H2 PASS: $H2_PASS"

if [[ "$H1_PASS" == "true" && "$H2_PASS" == "true" ]]; then
    echo "VERDICT: SUPPORTED. The ingress.targetPort vs. workload listening-port mismatch is the controlling variable: with workload bound to :3000 and ingress targeting :8000, the revision reports a non-healthy state (Failed or Degraded) with platform-emitted port-mismatch evidence in runningStateDetails (containing 'TargetPort'/'listening port'/'ProbeFailed') or, when runningStateDetails is empty, a non-zero ProbeFailed count in the system log stream — and admits zero HTTP 200s from a client. The app-scope ingress edit (az containerapp ingress update --target-port 3000) restores Running/Healthy state on the SAME revision (same name, same createdTime, same image — triangulated proof), and the client probes recover to 5/5 200. The same-revision proof falsifies the alternative theories (broken image, ACR pull failure, probe-config bug, revision-template defect)."
    exit 0
fi

if [[ "$H2_GATE" == "port_mismatch_did_not_recover" ]]; then
    echo "VERDICT: H2 FALSIFIED. The ingress-only fix (az containerapp ingress update --target-port 3000) did not restore Running/Healthy on the trigger revision (gate=${H2_GATE}). Investigate CLI version, workload binding port, or platform changes."
    exit 2
fi

if [[ "$H2_GATE" == "recovery_required_new_revision" ]]; then
    echo "VERDICT: H2 PARTIALLY SUPPORTED but with caveat. Recovery happened but a new revision was minted, which invalidates the strongest falsification argument. The mismatch theory still holds but the alternatives (broken image, pull failure, probe-config bug) are not falsified by this run."
    exit 2
fi

echo "VERDICT: INVALID RUN. Unexpected combination of H1 gate=${H1_GATE} and H2 gate=${H2_GATE}. Inspect evidence files."
exit 1
