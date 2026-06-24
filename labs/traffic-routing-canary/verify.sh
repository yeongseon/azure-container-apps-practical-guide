#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "verify.sh starting at ${UTC_NOW}"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo ""

echo "=== Phase 12: validate H1 evidence from trigger.sh ==="
H1_FILE="$EVIDENCE_DIR/12-h1-gate.json"
GOOD_CAPTURE_FILE="$EVIDENCE_DIR/04-good-revision-captured.json"
if [[ ! -f "$H1_FILE" ]]; then
    echo "INVALID RUN: $H1_FILE not found. Run trigger.sh first."
    exit 1
fi
if [[ ! -f "$GOOD_CAPTURE_FILE" ]]; then
    echo "INVALID RUN: $GOOD_CAPTURE_FILE not found. Run trigger.sh first."
    exit 1
fi
H1_GATE=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['gate_classification'])")
H1_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['h1_all_subgates_pass'])")
BAD_REVISION_NAME=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['trigger_window']['bad_revision_name'])")
GOOD_REVISION_NAME=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['trigger_window']['good_revision_name'])")
APP_FQDN=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['app_fqdn'])")
TRIGGER_GOOD_CREATED=$(python3 -c "import json; print(json.load(open('$GOOD_CAPTURE_FILE'))['good_revision_created_time'])")
TRIGGER_GOOD_IMAGE=$(python3 -c "import json; print(json.load(open('$GOOD_CAPTURE_FILE'))['good_revision_image'])")
TRIGGER_BAD_RUNNING=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['trigger_window']['bad_revision_running_state'])")
TRIGGER_BAD_RUNNING_DETAILS=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['trigger_window']['bad_revision_running_state_details'])")
echo "H1 state: gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
echo "Bad revision (from H1): ${BAD_REVISION_NAME}"
echo "Good revision (from H1): ${GOOD_REVISION_NAME}"
echo "Trigger-time GOOD createdTime (from 04): ${TRIGGER_GOOD_CREATED}"
echo "Trigger-time GOOD image (from 04): ${TRIGGER_GOOD_IMAGE}"
echo "Trigger-time BAD runningState (from H1): ${TRIGGER_BAD_RUNNING}"
echo "FQDN: ${APP_FQDN}"
if [[ "$H1_GATE" == "canary_failure_did_not_materialize" ]]; then
    echo "INVALID RUN: H1 was FALSIFIED in trigger.sh. The canary-failure scenario did not reproduce, so the rollback experiment cannot proceed."
    exit 1
fi
if [[ -z "$BAD_REVISION_NAME" ]] || [[ -z "$GOOD_REVISION_NAME" ]]; then
    echo "INVALID RUN: required revision names missing from H1 gate JSON."
    exit 1
fi
echo ""

echo "=== Phase 13: re-confirm BAD revision is still in failure state (expected: same name still showing port-mismatch evidence) ==="
az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision "$BAD_REVISION_NAME" \
    --query "{name: name, healthState: properties.healthState, runningState: properties.runningState, provisioningState: properties.provisioningState, replicas: properties.replicas, runningStateDetails: properties.runningStateDetails, image: properties.template.containers[0].image, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/13-revision-pre-fix-bad.json"
cat "$EVIDENCE_DIR/13-revision-pre-fix-bad.json"
PRE_FIX_BAD_NAME=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/13-revision-pre-fix-bad.json')).get('name') or '')")
PRE_FIX_BAD_RUNNING=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/13-revision-pre-fix-bad.json')).get('runningState') or 'Unknown')")
PRE_FIX_BAD_HEALTH=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/13-revision-pre-fix-bad.json')).get('healthState') or 'Unknown')")
PRE_FIX_BAD_RUNNING_DETAILS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/13-revision-pre-fix-bad.json')).get('runningStateDetails') or '')")
PRE_FIX_BAD_IMAGE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/13-revision-pre-fix-bad.json')).get('image') or '')")
echo "Pre-fix BAD runningState: ${PRE_FIX_BAD_RUNNING}"
echo "Pre-fix BAD runningStateDetails: ${PRE_FIX_BAD_RUNNING_DETAILS}"
echo "Pre-fix BAD image: ${PRE_FIX_BAD_IMAGE}"
echo ""

echo "=== Phase 14: 5-request curl loop on the 50/50 split (expected: ~50% non-200 to corroborate H1 d sub-gate) ==="
PRE_FIX_CURL_RESULTS=()
PRE_FIX_CURL_SUCCESS_COUNT=0
PRE_FIX_CURL_TIMEOUT_COUNT=0
for i in 1 2 3 4 5; do
    CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "https://${APP_FQDN}/" 2>/dev/null || true)
    [ -z "$CODE" ] && CODE="000"
    PRE_FIX_CURL_RESULTS+=("$CODE")
    if [ "$CODE" = "200" ]; then
        PRE_FIX_CURL_SUCCESS_COUNT=$((PRE_FIX_CURL_SUCCESS_COUNT + 1))
    fi
    if [ "$CODE" = "000" ]; then
        PRE_FIX_CURL_TIMEOUT_COUNT=$((PRE_FIX_CURL_TIMEOUT_COUNT + 1))
    fi
    echo "Pre-fix probe $i: HTTP ${CODE}"
    sleep 2
done
export EVIDENCE_DIR APP_FQDN PRE_FIX_CURL_SUCCESS_COUNT PRE_FIX_CURL_TIMEOUT_COUNT
export PRE_FIX_CURL_RESULTS_STR="${PRE_FIX_CURL_RESULTS[*]}"
python3 <<'PYEOF'
import json, os
results = os.environ['PRE_FIX_CURL_RESULTS_STR'].split()
out = {
    'fqdn': os.environ['APP_FQDN'],
    'attempts': len(results),
    'http_codes': results,
    'success_count_200': int(os.environ['PRE_FIX_CURL_SUCCESS_COUNT']),
    'timeout_count_000': int(os.environ['PRE_FIX_CURL_TIMEOUT_COUNT']),
    'phase': 'pre-fix re-confirmation of 50/50 canary failure on small sample',
    'note': 'A 5-request sample on a 50/50 weighted-random split is noisy. The H2 a sub-gate uses Pre-fix BAD revision state (re-confirmed in 13-revision-pre-fix-bad.json) plus H1 syslog count as the authoritative failure signal; this curl sample is corroborating evidence, not the primary predicate.',
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '14-curl-pre-fix.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 15: apply fix — az containerapp ingress traffic set --revision-weight ${GOOD_REVISION_NAME}=100 (CONFIG-PLANE only, no new revision) ==="
# `az containerapp ingress traffic set` is config-plane only and does NOT mint a new
# revision. The H2 falsification: if recovery happens by re-routing traffic 100% to the
# pre-existing GOOD revision (verified via same name AND same createdTime AND same image
# triangulation), then any theory requiring a new revision (image-rebuild, ACR re-pull,
# template re-deploy, hidden state on the good revision) is falsified. The only remaining
# cause consistent with both the failure (50/50 split with port-mismatched bad revision)
# AND the recovery (100/0 split back to good revision) is the per-request weighted routing
# being the controlling variable.
FIX_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Fix UTC: ${FIX_UTC}"

set +e
az containerapp ingress traffic set \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision-weight "${GOOD_REVISION_NAME}=100" "${BAD_REVISION_NAME}=0" \
    --only-show-errors \
    --output json \
    > "$EVIDENCE_DIR/15-traffic-set-rollback.json" \
    2> "$EVIDENCE_DIR/15-traffic-set-rollback.stderr"
FIX_EXIT_CODE=$?
set -e
echo "Traffic set exit code: ${FIX_EXIT_CODE} (expected: 0)"
if [ "$FIX_EXIT_CODE" -ne 0 ]; then
    echo "Fix stderr:"
    cat "$EVIDENCE_DIR/15-traffic-set-rollback.stderr" || true
fi
echo ""

# Brief settle window before re-probing the ingress route. The traffic update is
# config-plane only (no replica restart) but Front Door / ingress route refresh
# can take ~10s before the new weights propagate to all edge locations.
echo "=== Phase 16: wait for traffic split to propagate (15s) ==="
sleep 15
date -u +%Y-%m-%dT%H:%M:%SZ > "$EVIDENCE_DIR/16-wait-recovery.log"
echo "Wait complete at $(cat "$EVIDENCE_DIR/16-wait-recovery.log")"
echo ""

echo "=== Phase 17: capture post-fix revision list + show GOOD revision (expected: GOOD unchanged, BAD still visible with weight=0) ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, runningState: properties.runningState, trafficWeight: properties.trafficWeight, createdTime: properties.createdTime, image: properties.template.containers[0].image}" \
    --output json \
    > "$EVIDENCE_DIR/17-revision-list-post-fix.json"
cat "$EVIDENCE_DIR/17-revision-list-post-fix.json"
echo ""

az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision "$GOOD_REVISION_NAME" \
    --query "{name: name, healthState: properties.healthState, runningState: properties.runningState, provisioningState: properties.provisioningState, replicas: properties.replicas, runningStateDetails: properties.runningStateDetails, image: properties.template.containers[0].image, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/17-revision-show-good-post-fix.json"
cat "$EVIDENCE_DIR/17-revision-show-good-post-fix.json"
POST_FIX_GOOD_NAME=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/17-revision-show-good-post-fix.json')).get('name') or '')")
POST_FIX_GOOD_HEALTH=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/17-revision-show-good-post-fix.json')).get('healthState') or 'Unknown')")
POST_FIX_GOOD_RUNNING=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/17-revision-show-good-post-fix.json')).get('runningState') or 'Unknown')")
POST_FIX_GOOD_CREATED=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/17-revision-show-good-post-fix.json')).get('createdTime') or '')")
POST_FIX_GOOD_IMAGE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/17-revision-show-good-post-fix.json')).get('image') or '')")
echo "Post-fix GOOD healthState: ${POST_FIX_GOOD_HEALTH} (expected: Healthy)"
echo "Post-fix GOOD runningState: ${POST_FIX_GOOD_RUNNING} (expected: Running)"
echo "Post-fix GOOD createdTime: ${POST_FIX_GOOD_CREATED} (expected: ${TRIGGER_GOOD_CREATED} — same revision proof)"
echo "Post-fix GOOD image: ${POST_FIX_GOOD_IMAGE} (expected: ${TRIGGER_GOOD_IMAGE} — same image proof)"
echo ""

echo "=== Phase 18: 5-request curl loop post-fix (expected: 5/5 HTTP 200 — recovery complete) ==="
POST_FIX_CURL_RESULTS=()
POST_FIX_CURL_SUCCESS_COUNT=0
for i in 1 2 3 4 5; do
    CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "https://${APP_FQDN}/" 2>/dev/null || true)
    [ -z "$CODE" ] && CODE="000"
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
with open(os.path.join(os.environ['EVIDENCE_DIR'], '18-curl-post-fix.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 19: capture metadata + emit H2 gate ==="
az version --output json > "$EVIDENCE_DIR/19-cli-versions.json" 2>&1 || true
az extension list --query "[?name=='containerapp']" --output json > "$EVIDENCE_DIR/20-cli-containerapp-ext.json" 2>&1 || true
az group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --query "{name: name, location: location}" \
    --output json \
    > "$EVIDENCE_DIR/21-region.json" 2>&1 || true

UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR AZ_SUBSCRIPTION RG APP_NAME APP_FQDN
export BAD_REVISION_NAME GOOD_REVISION_NAME TRIGGER_GOOD_CREATED TRIGGER_GOOD_IMAGE
export PRE_FIX_BAD_NAME PRE_FIX_BAD_RUNNING PRE_FIX_BAD_HEALTH PRE_FIX_BAD_RUNNING_DETAILS PRE_FIX_BAD_IMAGE
export PRE_FIX_CURL_SUCCESS_COUNT PRE_FIX_CURL_TIMEOUT_COUNT
export FIX_UTC FIX_EXIT_CODE
export POST_FIX_GOOD_NAME POST_FIX_GOOD_HEALTH POST_FIX_GOOD_RUNNING POST_FIX_GOOD_CREATED POST_FIX_GOOD_IMAGE
export POST_FIX_CURL_SUCCESS_COUNT UTC_CAPTURED

python3 <<'PYEOF'
import json, os

pre_fix_bad_name = os.environ.get('PRE_FIX_BAD_NAME', '')
pre_fix_bad_running = os.environ['PRE_FIX_BAD_RUNNING']
pre_fix_bad_health = os.environ['PRE_FIX_BAD_HEALTH']
pre_fix_bad_running_details = os.environ.get('PRE_FIX_BAD_RUNNING_DETAILS', '')
pre_fix_curl_success = int(os.environ['PRE_FIX_CURL_SUCCESS_COUNT'])
pre_fix_curl_timeout = int(os.environ['PRE_FIX_CURL_TIMEOUT_COUNT'])
fix_exit_code = int(os.environ['FIX_EXIT_CODE'])
post_fix_good_name = os.environ.get('POST_FIX_GOOD_NAME', '')
post_fix_good_health = os.environ['POST_FIX_GOOD_HEALTH']
post_fix_good_running = os.environ['POST_FIX_GOOD_RUNNING']
post_fix_good_created = os.environ['POST_FIX_GOOD_CREATED']
post_fix_good_image = os.environ['POST_FIX_GOOD_IMAGE']
post_fix_curl_success = int(os.environ['POST_FIX_CURL_SUCCESS_COUNT'])
trigger_good_created = os.environ['TRIGGER_GOOD_CREATED']
trigger_good_image = os.environ['TRIGGER_GOOD_IMAGE']
good_revision_name = os.environ['GOOD_REVISION_NAME']
bad_revision_name = os.environ['BAD_REVISION_NAME']

# Read H1 syslog evidence from the trigger.sh-emitted gate file. H2's failure-
# evidence predicate mirrors trigger.sh's H1 c-gate: port-specific corroboration
# is required, not a bare 'Failed'/'Degraded' label. verify.sh does not capture
# its own syslog stream (the cost is paid once during trigger.sh), so the H1
# ProbeFailed count is the authoritative fallback signal.
h1_path = os.path.join(os.environ['EVIDENCE_DIR'], '12-h1-gate.json')
with open(h1_path) as h1f:
    h1_data = json.load(h1f)
h1_syslog_probe_failed_count = h1_data.get(
    'system_log_capture', {}
).get('probe_failed_lines_in_tail', 0)

# Load 17 revision list to verify BAD revision is still visible with weight=0.
# This is the audit-trail sub-gate: the rollback should preserve the BAD
# revision in the platform's history (it is still inspectable) but with traffic
# routed away from it. Auto-deletion would invalidate the audit trail.
with open(os.path.join(os.environ['EVIDENCE_DIR'], '17-revision-list-post-fix.json')) as f:
    post_fix_revision_list = json.load(f)
bad_revision_entry = None
good_revision_entry = None
for rev in post_fix_revision_list:
    if rev.get('name') == bad_revision_name:
        bad_revision_entry = rev
    if rev.get('name') == good_revision_name:
        good_revision_entry = rev

# Load 15 traffic-set response to verify the rollback weight shape from the
# actual ingress response, not local environment. `az containerapp ingress
# traffic set` returns the traffic array directly as the top-level JSON (a list
# of {revisionName, weight} entries), NOT the full Container App resource.
# Accept either shape defensively (see trigger.sh phase 11 for the empirical
# observation that motivated this).
with open(os.path.join(os.environ['EVIDENCE_DIR'], '15-traffic-set-rollback.json')) as f:
    traffic_set_response = json.load(f)
if isinstance(traffic_set_response, list):
    post_fix_ingress_traffic = traffic_set_response
else:
    post_fix_ingress_traffic = (
        traffic_set_response.get('properties', {})
        .get('configuration', {})
        .get('ingress', {})
        .get('traffic', [])
    )

# H2 sub-gate a requires PORT-SPECIFIC evidence that the BAD revision failure
# persisted into verify.sh — same acceptance discipline as H1 sub-gate c. Two paths:
#   Strong  : pre_fix_bad runningStateDetails contains explicit port/probe text.
#   Fallback: pre_fix_bad non-healthy state PAIRED with H1's syslog ProbeFailed
#             count > 0 (same lab run, same revision, syslog snapshot applies).
# A bare 'Failed'/'Degraded' label with NO port-specific corroboration is
# explicitly insufficient — see trigger.sh phase 11 for the full rationale.
pre_fix_bad_failure_evidence = (
    (
        pre_fix_bad_running_details
        and (
            'TargetPort' in pre_fix_bad_running_details
            or 'listening port' in pre_fix_bad_running_details
            or 'ProbeFailed' in pre_fix_bad_running_details
        )
    )
    or (
        pre_fix_bad_running in ('Failed', 'Degraded')
        and h1_syslog_probe_failed_count > 0
    )
)
a_pre_fix_failure_re_confirmed = bool(pre_fix_bad_failure_evidence)

# Sub-gate b: traffic set CLI succeeded AND the response carries the new
# weights (GOOD=100, BAD=0). Platform behavior — empirically observed in this
# lab run, see 15-traffic-set-rollback.json: `az containerapp ingress traffic
# set --revision-weight rev=100` returns ONLY the entries it explicitly assigned
# (a single-element list `[{revisionName: <good>, weight: 100}]`); unmentioned
# revisions are implicitly weight=0 and DO NOT appear in the response. So we
# accept BAD as either "absent from the response" OR "explicitly weight=0".
# The revision-list snapshot (17-revision-list-post-fix.json) independently
# corroborates BAD at weight=0 via sub-gate f.
b_traffic_set_rollback_succeeded = False
if fix_exit_code == 0 and post_fix_ingress_traffic:
    good_weight = None
    bad_weight_present = False
    bad_weight_value = None
    for t in post_fix_ingress_traffic:
        if t.get('revisionName') == good_revision_name:
            good_weight = t.get('weight')
        if t.get('revisionName') == bad_revision_name:
            bad_weight_present = True
            bad_weight_value = t.get('weight')
    bad_implicit_zero_or_explicit_zero = (
        (not bad_weight_present)
        or bad_weight_value == 0
    )
    b_traffic_set_rollback_succeeded = (
        good_weight == 100
        and bad_implicit_zero_or_explicit_zero
    )

# Sub-gate c: traffic split shape — exactly one entry at weight=100 belonging
# to the GOOD revision, no other entry > 0.
non_zero_weights = [t for t in post_fix_ingress_traffic if (t.get('weight') or 0) > 0]
c_traffic_100_pct_good = (
    len(non_zero_weights) == 1
    and non_zero_weights[0].get('revisionName') == good_revision_name
    and non_zero_weights[0].get('weight') == 100
)

# Sub-gate d: client-side validation — all 5 post-fix curl probes returned HTTP 200.
d_post_fix_curl_all_success = post_fix_curl_success == 5

# Sub-gate e: GOOD revision identity is preserved across the rollback.
# Triangulated across three platform-emitted fields:
#   name        — revision identity assigned by the platform
#   createdTime — provisioning timestamp (immutable per revision instance)
#   image       — revision template's container image
# The traffic-set edit is config-plane only and MUST NOT mint a new revision
# for the GOOD path. If ANY of these three fields drift between trigger-time
# (04-good-revision-captured.json) and post-fix (17-revision-show-good-post-fix.json),
# the same-revision claim is falsified and an alternative theory (image rebuild,
# template re-render, hidden state on good revision) must be entertained.
name_unchanged = bool(good_revision_name) and bool(post_fix_good_name) and good_revision_name == post_fix_good_name
created_time_unchanged = bool(trigger_good_created) and bool(post_fix_good_created) and trigger_good_created == post_fix_good_created
image_unchanged = bool(trigger_good_image) and bool(post_fix_good_image) and trigger_good_image == post_fix_good_image
e_good_revision_unchanged = (
    name_unchanged
    and created_time_unchanged
    and image_unchanged
    and post_fix_good_health == 'Healthy'
    and post_fix_good_running == 'Running'
)

# Sub-gate f: audit trail — the BAD revision is still visible in the revision
# list with weight=0 (not auto-deleted by the rollback). This proves the rollback
# is reversible (operator can re-route traffic back) and preserves diagnostic
# history. NOTE: trafficWeight in the revision-list query can render as null when
# weight=0 in some CLI versions, so we accept either 0 or null/missing.
bad_weight_in_list = None
if bad_revision_entry:
    bad_weight_in_list = bad_revision_entry.get('trafficWeight')
f_bad_revision_still_visible_with_zero_traffic = (
    bad_revision_entry is not None
    and (bad_weight_in_list == 0 or bad_weight_in_list is None)
)

h2_sub_gates = {
    'a_pre_fix_failure_re_confirmed': a_pre_fix_failure_re_confirmed,
    'b_traffic_set_rollback_succeeded': b_traffic_set_rollback_succeeded,
    'c_traffic_100_pct_good': c_traffic_100_pct_good,
    'd_post_fix_curl_all_success': d_post_fix_curl_all_success,
    'e_good_revision_unchanged': e_good_revision_unchanged,
    'f_bad_revision_still_visible_with_zero_traffic': f_bad_revision_still_visible_with_zero_traffic,
}
h2_all_subgates_pass = all(h2_sub_gates.values())

if h2_all_subgates_pass:
    gate_classification = 'canary_rolled_back_to_good_revision_intact'
elif not c_traffic_100_pct_good or not d_post_fix_curl_all_success:
    gate_classification = 'canary_rollback_did_not_recover'
elif not e_good_revision_unchanged:
    gate_classification = 'rollback_required_new_good_revision'
else:
    gate_classification = 'partial_observation_some_subgates_failed'

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'subscription': os.environ['AZ_SUBSCRIPTION'],
    'rg': os.environ['RG'],
    'app_name': os.environ['APP_NAME'],
    'app_fqdn': os.environ['APP_FQDN'],
    'good_revision_name': good_revision_name,
    'bad_revision_name': bad_revision_name,
    'pre_fix_state': {
        'bad_revision_name': pre_fix_bad_name,
        'bad_revision_running_state': pre_fix_bad_running,
        'bad_revision_health_state': pre_fix_bad_health,
        'bad_revision_running_state_details': pre_fix_bad_running_details,
        'bad_revision_image': os.environ.get('PRE_FIX_BAD_IMAGE', ''),
        'curl_success_count_200_of_5': pre_fix_curl_success,
        'curl_timeout_count_000_of_5': pre_fix_curl_timeout,
        'h1_syslog_probe_failed_count_referenced': h1_syslog_probe_failed_count,
    },
    'fix_window': {
        'start_utc': os.environ['FIX_UTC'],
        'command': 'az containerapp ingress traffic set --revision-weight GOOD=100 BAD=0',
        'cli_exit_code': fix_exit_code,
    },
    'post_fix_state': {
        'good_revision_name': post_fix_good_name,
        'good_revision_health_state': post_fix_good_health,
        'good_revision_running_state': post_fix_good_running,
        'good_revision_created_time': post_fix_good_created,
        'good_revision_image': post_fix_good_image,
        'curl_success_count_200_of_5': post_fix_curl_success,
        'ingress_traffic_array': post_fix_ingress_traffic,
        'bad_revision_entry_in_revision_list': bad_revision_entry,
    },
    'same_revision_proof': {
        'pre_fix_good_name': good_revision_name,
        'post_fix_good_name': post_fix_good_name,
        'name_unchanged': name_unchanged,
        'trigger_time_good_created_time': trigger_good_created,
        'post_fix_good_created_time': post_fix_good_created,
        'created_time_unchanged': created_time_unchanged,
        'trigger_time_good_image': trigger_good_image,
        'post_fix_good_image': post_fix_good_image,
        'image_unchanged': image_unchanged,
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

if [[ "$H1_GATE" == "canary_failure_reproduced_50_50_traffic_split" && "$H1_ALL_SUBGATES_PASS" == "True" ]]; then
    H1_PASS=true
fi
if [[ "$H2_GATE" == "canary_rolled_back_to_good_revision_intact" && "$H2_ALL_SUBGATES_PASS" == "True" ]]; then
    H2_PASS=true
fi

echo "H1 PASS: $H1_PASS"
echo "H2 PASS: $H2_PASS"

if [[ "$H1_PASS" == "true" && "$H2_PASS" == "true" ]]; then
    echo "VERDICT: SUPPORTED. The 50/50 traffic split between the existing healthy revision (image listens on the ingress targetPort) and a newly-minted port-mismatched revision (image listens on a different port) is the controlling variable for canary failure: at split-time the bad revision reports a non-healthy state (Failed/Degraded) with platform-emitted port-mismatch evidence in runningStateDetails (containing 'TargetPort'/'listening port'/'ProbeFailed') or, when runningStateDetails is empty, a non-zero ProbeFailed count in the system log stream; and client probes show intermittent failure (~50% timeouts within tolerance band). The rollback command (az containerapp ingress traffic set --revision-weight GOOD=100 BAD=0) restores 100% HTTP 200 client success WITHOUT minting a new GOOD revision — same name, same createdTime, same image (triangulated proof) — and preserves the BAD revision in the revision list at weight=0 for audit trail. This falsifies the alternative theories that recovery requires a new revision (image rebuild, ACR re-pull, template re-deploy, hidden state on the good revision)."
    exit 0
fi

if [[ "$H2_GATE" == "canary_rollback_did_not_recover" ]]; then
    echo "VERDICT: H2 FALSIFIED. The traffic-set rollback did not restore 100% client success on the GOOD revision (gate=${H2_GATE}). Investigate CLI version, ingress route propagation, or platform changes."
    exit 2
fi

if [[ "$H2_GATE" == "rollback_required_new_good_revision" ]]; then
    echo "VERDICT: H2 PARTIALLY SUPPORTED but with caveat. Recovery happened but the GOOD revision identity changed (name/createdTime/image drift detected), which invalidates the strongest falsification argument. The canary-rollback theory still holds but the alternatives (template re-render, hidden mutation of good revision) are not falsified by this run."
    exit 2
fi

echo "VERDICT: INVALID RUN. Unexpected combination of H1 gate=${H1_GATE} and H2 gate=${H2_GATE}. Inspect evidence files."
exit 1
