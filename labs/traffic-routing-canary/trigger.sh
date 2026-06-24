#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

# The bad image's listening port is :8080; ingress targetPort stays at :80.
# Both are stable parts of the lab; if either is changed, the H1 c sub-gate
# port-text matcher and the e sub-gate image matcher must be updated in lockstep.
BAD_IMAGE="mcr.microsoft.com/dotnet/samples:aspnetapp"
BAD_REVISION_SUFFIX="badv2"
GOOD_IMAGE="mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
BAD_IMAGE_LISTENING_PORT="8080"
EXPECTED_INGRESS_TARGET_PORT="80"
TRAFFIC_PROBE_COUNT=30
TRAFFIC_PROBE_MAX_TIME=10
# H1 sub-gate d tolerance: out of 30 requests split 50/50, ProbeFailed-induced
# timeouts (curl 000) should land in [8, 22] — that is, 50% ± 25 percentage
# points. The tolerance accounts for ingress routing being a per-request
# weighted-random selection rather than a strict round-robin.
TIMEOUT_COUNT_LOWER_BOUND=8
TIMEOUT_COUNT_UPPER_BOUND=22

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "trigger.sh starting at ${UTC_NOW}"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo ""
echo "Note: This lab reproduces a canary-failure scenario where 50/50 traffic split between a"
echo "healthy revision (image listens on :${EXPECTED_INGRESS_TARGET_PORT}) and a port-mismatched"
echo "revision (image listens on :${BAD_IMAGE_LISTENING_PORT} while ingress targetPort stays at"
echo ":${EXPECTED_INGRESS_TARGET_PORT}) produces ~50% client failure. The image-swap workaround"
echo "documented in the lab guide is the minimal way to isolate per-revision failure (the original"
echo "trigger.sh used '--target-port 9999' which is architecturally unable to reproduce this:"
echo "ingress targetPort is shared across all revisions). H1 captures the reproduced failure state."
echo "H2 in verify.sh proves that the standard 'az containerapp ingress traffic set --revision-weight"
echo "GOOD=100' rollback restores 100% success WITHOUT modifying the good revision (same name,"
echo "createdTime, image) — falsifying any theory that rollback would require a new revision."
echo ""

echo "=== Phase 1: resolve infrastructure (FQDN, ingress targetPort) ==="
APP_FQDN=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv | tr -d '\r')
BASELINE_TARGET_PORT=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.ingress.targetPort" \
    --output tsv | tr -d '\r')
ACTIVE_REVISIONS_MODE=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.activeRevisionsMode" \
    --output tsv | tr -d '\r')
echo "App FQDN: ${APP_FQDN}"
echo "Baseline ingress targetPort: ${BASELINE_TARGET_PORT} (expected: ${EXPECTED_INGRESS_TARGET_PORT})"
echo "activeRevisionsMode: ${ACTIVE_REVISIONS_MODE} (expected: Multiple)"
echo ""

export EVIDENCE_DIR APP_FQDN APP_NAME RG AZ_SUBSCRIPTION
export BASELINE_TARGET_PORT ACTIVE_REVISIONS_MODE UTC_NOW
python3 <<'PYEOF'
import json, os
out = {
    'utc': os.environ.get('UTC_NOW', ''),
    'subscription': os.environ['AZ_SUBSCRIPTION'],
    'rg': os.environ['RG'],
    'app_name': os.environ['APP_NAME'],
    'app_fqdn': os.environ['APP_FQDN'],
    'baseline_ingress_target_port': os.environ['BASELINE_TARGET_PORT'],
    'active_revisions_mode': os.environ['ACTIVE_REVISIONS_MODE'],
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '01-infra-resolve.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 2: baseline revisions snapshot (single healthy revision before image swap) ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, runningState: properties.runningState, trafficWeight: properties.trafficWeight, createdTime: properties.createdTime, image: properties.template.containers[0].image}" \
    --output json \
    > "$EVIDENCE_DIR/02-baseline-revisions.json"
cat "$EVIDENCE_DIR/02-baseline-revisions.json"
echo ""

# Capture GOOD_REVISION name (the single existing revision before image swap).
GOOD_REVISION=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/02-baseline-revisions.json')); print(d[0]['name'] if d else '')")
GOOD_REVISION_IMAGE=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/02-baseline-revisions.json')); print(d[0]['image'] if d else '')")
GOOD_REVISION_CREATED=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/02-baseline-revisions.json')); print(d[0]['createdTime'] if d else '')")
echo "Captured GOOD revision: ${GOOD_REVISION}"
echo "Captured GOOD image: ${GOOD_REVISION_IMAGE} (expected: ${GOOD_IMAGE})"
echo "Captured GOOD createdTime: ${GOOD_REVISION_CREATED}"
echo ""

echo "=== Phase 3: baseline curl probes against single healthy revision (expect 5/5 HTTP 200) ==="
BASELINE_CURL_RESULTS=()
BASELINE_SUCCESS_COUNT=0
for i in 1 2 3 4 5; do
    # curl --write-out '%{http_code}' always outputs an http_code (even '000' on
    # timeout), so we capture stdout and gate set -e with '|| true'. Avoid the
    # common '|| echo 000' trap: that pattern double-emits when curl returns
    # exit 28 with stdout already containing '000', producing '000000'.
    CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "https://${APP_FQDN}/" 2>/dev/null || true)
    [ -z "$CODE" ] && CODE="000"
    BASELINE_CURL_RESULTS+=("$CODE")
    if [ "$CODE" = "200" ]; then
        BASELINE_SUCCESS_COUNT=$((BASELINE_SUCCESS_COUNT + 1))
    fi
    echo "Baseline probe $i: HTTP ${CODE}"
    sleep 1
done

export BASELINE_CURL_RESULTS_STR="${BASELINE_CURL_RESULTS[*]}"
export BASELINE_SUCCESS_COUNT
python3 <<'PYEOF'
import json, os
results = os.environ['BASELINE_CURL_RESULTS_STR'].split()
out = {
    'fqdn': os.environ['APP_FQDN'],
    'attempts': len(results),
    'http_codes': results,
    'success_count_200': int(os.environ['BASELINE_SUCCESS_COUNT']),
    'expected_success_count': len(results),
    'note': 'Baseline probes against the single healthy revision before the bad revision is minted. All 5 should return HTTP 200.',
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '03-baseline-curl.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 4: snapshot the captured GOOD revision identity for later same-revision proof ==="
export GOOD_REVISION GOOD_REVISION_IMAGE GOOD_REVISION_CREATED
python3 <<'PYEOF'
import json, os
out = {
    'good_revision_name': os.environ['GOOD_REVISION'],
    'good_revision_image': os.environ['GOOD_REVISION_IMAGE'],
    'good_revision_created_time': os.environ['GOOD_REVISION_CREATED'],
    'note': "Captured at trigger.sh Phase 4, before any image swap. H2 e_good_revision_unchanged consumes these fields to compute (name_unchanged AND image_unchanged AND createdTime_unchanged) against post-fix revision metadata.",
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '04-good-revision-captured.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 5: trigger — image-swap workaround (mints --${BAD_REVISION_SUFFIX} with port-mismatched image) ==="
# We swap the container image to one that listens on a DIFFERENT port than the ingress
# targetPort. The image swap is a revision-template change and mints a new revision named
# ${APP_NAME}--${BAD_REVISION_SUFFIX}. Ingress targetPort stays at :${EXPECTED_INGRESS_TARGET_PORT};
# the new revision's image listens on :${BAD_IMAGE_LISTENING_PORT} — isolated per-revision failure.
TRIGGER_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Trigger UTC: ${TRIGGER_UTC}"

az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --image "$BAD_IMAGE" \
    --revision-suffix "$BAD_REVISION_SUFFIX" \
    --only-show-errors \
    --output json \
    > "$EVIDENCE_DIR/05-containerapp-update-image.json" 2> "$EVIDENCE_DIR/05-containerapp-update-image.stderr"
BAD_REVISION=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/05-containerapp-update-image.json')); print(d['properties']['latestRevisionName'])" 2>/dev/null || echo "")
echo "Bad revision name: ${BAD_REVISION} (expected: ${APP_NAME}--${BAD_REVISION_SUFFIX})"
echo ""

echo "=== Phase 6: wait for bad revision to settle (poll up to 5 minutes) ==="
# Container Apps revision provisioningState progresses Provisioning -> Provisioned. The
# runtime state then reports as runningState (Activating/Running/Failed/Degraded). A
# probe-failing revision can stay in Activating indefinitely while the platform retries
# probes; the diagnostic surfaces via runningStateDetails (e.g. "The TargetPort 80 does
# not match the listening port 8080."). Break either on terminal runningState OR when
# runningStateDetails becomes non-empty (platform recognized the failure cause), with
# a 5-minute ceiling.
WAIT_LOG="$EVIDENCE_DIR/06-wait-bad-revision.log"
: > "$WAIT_LOG"
ATTEMPTS=30
for i in $(seq 1 $ATTEMPTS); do
    STATE=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$BAD_REVISION" \
        --query "properties.provisioningState" \
        --output tsv 2>/dev/null | tr -d '\r' || echo "Unknown")
    RUN_STATE=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$BAD_REVISION" \
        --query "properties.runningState" \
        --output tsv 2>/dev/null | tr -d '\r' || echo "Unknown")
    RUN_DETAILS=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$BAD_REVISION" \
        --query "properties.runningStateDetails" \
        --output tsv 2>/dev/null | tr -d '\r' || echo "")
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "[$ts] attempt $i/$ATTEMPTS provisioningState=${STATE} runningState=${RUN_STATE} runningStateDetails=${RUN_DETAILS}" | tee -a "$WAIT_LOG"
    if [ "$RUN_STATE" = "Failed" ] || [ "$RUN_STATE" = "Running" ] || [ "$RUN_STATE" = "Degraded" ]; then
        break
    fi
    if [ -n "$RUN_DETAILS" ] && [ "$STATE" = "Provisioned" ] && [ "$i" -ge 3 ]; then
        break
    fi
    sleep 10
done
echo ""

echo "=== Phase 7: capture bad revision state details ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, runningState: properties.runningState, provisioningState: properties.provisioningState, trafficWeight: properties.trafficWeight, createdTime: properties.createdTime, replicas: properties.replicas, image: properties.template.containers[0].image}" \
    --output json \
    > "$EVIDENCE_DIR/07-revision-list-bad.json"
cat "$EVIDENCE_DIR/07-revision-list-bad.json"
echo ""

az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision "$BAD_REVISION" \
    --query "{name: name, healthState: properties.healthState, runningState: properties.runningState, provisioningState: properties.provisioningState, replicas: properties.replicas, runningStateDetails: properties.runningStateDetails, image: properties.template.containers[0].image, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/08-revision-show-bad.json"
cat "$EVIDENCE_DIR/08-revision-show-bad.json"
echo ""

BAD_HEALTH=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-bad.json')).get('healthState') or 'Unknown')")
BAD_RUNNING=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-bad.json')).get('runningState') or 'Unknown')")
BAD_PROVISIONING=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-bad.json')).get('provisioningState') or 'Unknown')")
BAD_IMAGE_OBSERVED=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-bad.json')).get('image') or '')")
BAD_CREATED=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-bad.json')).get('createdTime') or '')")
BAD_RUNNING_DETAILS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-bad.json')).get('runningStateDetails') or '')")
echo "Bad revision healthState: ${BAD_HEALTH}"
echo "Bad revision runningState: ${BAD_RUNNING}"
echo "Bad revision provisioningState: ${BAD_PROVISIONING}"
echo "Bad revision image: ${BAD_IMAGE_OBSERVED}"
echo "Bad revision createdTime: ${BAD_CREATED}"
echo "Bad revision runningStateDetails: ${BAD_RUNNING_DETAILS}"
echo ""

# Capture good revision state at trigger-time too (it should still be Healthy/Running
# even after the bad revision is minted — H1 sub-gate e verifies this isolation).
az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision "$GOOD_REVISION" \
    --query "{name: name, healthState: properties.healthState, runningState: properties.runningState, image: properties.template.containers[0].image, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/08-revision-show-good.json"
cat "$EVIDENCE_DIR/08-revision-show-good.json"
GOOD_HEALTH_AT_TRIGGER=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-good.json')).get('healthState') or 'Unknown')")
GOOD_RUNNING_AT_TRIGGER=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-good.json')).get('runningState') or 'Unknown')")
echo "Good revision healthState at trigger time: ${GOOD_HEALTH_AT_TRIGGER}"
echo "Good revision runningState at trigger time: ${GOOD_RUNNING_AT_TRIGGER}"
echo ""

echo "=== Phase 8: apply 50/50 traffic split between good and bad revisions ==="
az containerapp ingress traffic set \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision-weight "${GOOD_REVISION}=50" "${BAD_REVISION}=50" \
    --only-show-errors \
    --output json \
    > "$EVIDENCE_DIR/09-traffic-set-50-50.json" 2> "$EVIDENCE_DIR/09-traffic-set-50-50.stderr"
echo "Traffic set response:"
cat "$EVIDENCE_DIR/09-traffic-set-50-50.json"
echo ""

# Brief settle window before probe loop — the traffic update is config-plane only
# (no replica restart), but Front Door / ingress route refresh can take ~10s.
sleep 15

echo "=== Phase 9: 30-request curl loop (--max-time ${TRAFFIC_PROBE_MAX_TIME}s) to measure 50/50 failure rate ==="
TRAFFIC_CURL_RESULTS=()
TRAFFIC_SUCCESS_COUNT=0
TRAFFIC_TIMEOUT_COUNT=0
for i in $(seq 1 $TRAFFIC_PROBE_COUNT); do
    CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time $TRAFFIC_PROBE_MAX_TIME "https://${APP_FQDN}/" 2>/dev/null || true)
    [ -z "$CODE" ] && CODE="000"
    TRAFFIC_CURL_RESULTS+=("$CODE")
    if [ "$CODE" = "200" ]; then
        TRAFFIC_SUCCESS_COUNT=$((TRAFFIC_SUCCESS_COUNT + 1))
    fi
    if [ "$CODE" = "000" ]; then
        TRAFFIC_TIMEOUT_COUNT=$((TRAFFIC_TIMEOUT_COUNT + 1))
    fi
    echo "Probe $i: HTTP ${CODE}"
done

export TRAFFIC_CURL_RESULTS_STR="${TRAFFIC_CURL_RESULTS[*]}"
export TRAFFIC_SUCCESS_COUNT TRAFFIC_TIMEOUT_COUNT TRAFFIC_PROBE_COUNT TRAFFIC_PROBE_MAX_TIME
export TIMEOUT_COUNT_LOWER_BOUND TIMEOUT_COUNT_UPPER_BOUND
python3 <<'PYEOF'
import json, os
results = os.environ['TRAFFIC_CURL_RESULTS_STR'].split()
out = {
    'fqdn': os.environ['APP_FQDN'],
    'attempts': len(results),
    'max_time_seconds': int(os.environ['TRAFFIC_PROBE_MAX_TIME']),
    'http_codes': results,
    'success_count_200': int(os.environ['TRAFFIC_SUCCESS_COUNT']),
    'timeout_count_000': int(os.environ['TRAFFIC_TIMEOUT_COUNT']),
    'expected_split': '~50/50 success/timeout under 50/50 traffic-weight (tolerated band: timeouts in [{}-{}] out of {}).'.format(
        os.environ['TIMEOUT_COUNT_LOWER_BOUND'],
        os.environ['TIMEOUT_COUNT_UPPER_BOUND'],
        os.environ['TRAFFIC_PROBE_COUNT'],
    ),
    'note': 'HTTP 000 indicates the upstream replica did not respond within --max-time (probe-failed bad revision accepts no traffic). Per-request routing is weighted-random so an exact 15/15 split is not guaranteed.',
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '10-curl-loop-30-requests.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 10: best-effort system log capture (Log Analytics ingestion lag is 5-10 minutes) ==="
set +e
az containerapp logs show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --type system \
    --tail 50 \
    > "$EVIDENCE_DIR/11-system-logs-tail.log" 2>&1
SYSLOG_EXIT_CODE=$?
set -e
echo "System log capture exit code: ${SYSLOG_EXIT_CODE} (0=available, non-zero=ingestion lag or transient API)"
SYSLOG_PROBE_FAILED_COUNT=$(grep -c "ProbeFailed\|Probe of" "$EVIDENCE_DIR/11-system-logs-tail.log" 2>/dev/null || echo "0")
SYSLOG_PROBE_FAILED_COUNT=$(echo "$SYSLOG_PROBE_FAILED_COUNT" | tr -d '\r\n ')
echo "ProbeFailed event lines captured in tail: ${SYSLOG_PROBE_FAILED_COUNT} (best-effort; consumed by H1 c fallback predicate)"
echo ""

echo "=== Phase 11: emit H1 gate JSON ==="
UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR AZ_SUBSCRIPTION RG APP_NAME APP_FQDN
export TRIGGER_UTC BAD_REVISION GOOD_REVISION
export BAD_HEALTH BAD_RUNNING BAD_PROVISIONING BAD_IMAGE_OBSERVED BAD_CREATED BAD_RUNNING_DETAILS
export GOOD_HEALTH_AT_TRIGGER GOOD_RUNNING_AT_TRIGGER
export BASELINE_TARGET_PORT BAD_IMAGE_LISTENING_PORT EXPECTED_INGRESS_TARGET_PORT BAD_IMAGE BAD_REVISION_SUFFIX
export TRAFFIC_SUCCESS_COUNT TRAFFIC_TIMEOUT_COUNT TRAFFIC_PROBE_COUNT
export TIMEOUT_COUNT_LOWER_BOUND TIMEOUT_COUNT_UPPER_BOUND
export SYSLOG_EXIT_CODE SYSLOG_PROBE_FAILED_COUNT UTC_CAPTURED

python3 <<'PYEOF'
import json, os

bad_revision = os.environ['BAD_REVISION']
good_revision = os.environ['GOOD_REVISION']
bad_running = os.environ['BAD_RUNNING']
bad_health = os.environ['BAD_HEALTH']
bad_image = os.environ['BAD_IMAGE_OBSERVED']
bad_running_details = os.environ.get('BAD_RUNNING_DETAILS', '')
good_health_at_trigger = os.environ['GOOD_HEALTH_AT_TRIGGER']
good_running_at_trigger = os.environ['GOOD_RUNNING_AT_TRIGGER']
baseline_target_port = os.environ['BASELINE_TARGET_PORT']
expected_target_port = os.environ['EXPECTED_INGRESS_TARGET_PORT']
expected_bad_image = os.environ['BAD_IMAGE']
expected_suffix = os.environ['BAD_REVISION_SUFFIX']
traffic_success = int(os.environ['TRAFFIC_SUCCESS_COUNT'])
traffic_timeout = int(os.environ['TRAFFIC_TIMEOUT_COUNT'])
traffic_count = int(os.environ['TRAFFIC_PROBE_COUNT'])
lower = int(os.environ['TIMEOUT_COUNT_LOWER_BOUND'])
upper = int(os.environ['TIMEOUT_COUNT_UPPER_BOUND'])
syslog_probe_failed_count = int(os.environ.get('SYSLOG_PROBE_FAILED_COUNT', '0'))

# Load 09 to compute b sub-gate (traffic split shape) from the actual ingress
# response, not from local environment. `az containerapp ingress traffic set`
# returns the traffic array directly as the top-level JSON (a list of
# {revisionName, weight} entries) — NOT the full Container App resource. Earlier
# observed CLI shapes wrapped this in properties.configuration.ingress.traffic,
# so we accept either shape defensively.
with open(os.path.join(os.environ['EVIDENCE_DIR'], '09-traffic-set-50-50.json')) as f:
    traffic_set_response = json.load(f)
if isinstance(traffic_set_response, list):
    ingress_traffic = traffic_set_response
else:
    ingress_traffic = (
        traffic_set_response.get('properties', {})
        .get('configuration', {})
        .get('ingress', {})
        .get('traffic', [])
    )
weights = sorted([t.get('weight') for t in ingress_traffic])

# Sub-gate a: bad revision was minted with the expected suffix and image.
a_bad_revision_minted = (
    bool(bad_revision)
    and bad_revision.endswith('--' + expected_suffix)
    and bool(bad_image)
    and bad_image == expected_bad_image
)

# Sub-gate b: ingress traffic is split 50/50 between exactly two revisions.
b_traffic_split_50_50 = (
    len(ingress_traffic) == 2
    and weights == [50, 50]
)

# Sub-gate c: PORT-SPECIFIC evidence of probe failure on the bad revision.
# Two acceptance paths:
#   Strong  : runningStateDetails contains port-mismatch text emitted by the
#             platform ("TargetPort N does not match the listening port M",
#             "ProbeFailed", or "listening port"). Authoritative signal.
#   Fallback: non-healthy state (Failed/Degraded) PAIRED with a non-zero
#             ProbeFailed count from the system log capture (11-system-logs-tail.log).
#             The fallback exists because runningStateDetails text formatting
#             is platform-controlled and has varied across captures, so a
#             corroborating syslog signal is required when runningStateDetails
#             is empty.
# A bare 'Failed'/'Degraded' label with NO port-specific corroboration is
# explicitly insufficient — it could be caused by image pull, OOMKilled,
# crash loop, or other non-port failure modes.
c_bad_revision_probe_failure_evidence = (
    (
        bad_running_details
        and (
            'TargetPort' in bad_running_details
            or 'listening port' in bad_running_details
            or 'ProbeFailed' in bad_running_details
        )
    )
    or (
        bad_running in ('Failed', 'Degraded')
        and syslog_probe_failed_count > 0
    )
)

# Sub-gate d: 30-request curl loop produces an intermittent-failure ratio
# consistent with 50/50 traffic split. Per-request routing is weighted-random,
# not strict round-robin, so we tolerate [lower, upper] timeouts out of N
# (default 8-22 out of 30 = 50% +/- 25 percentage points).
d_curl_loop_shows_intermittent_failure = (
    lower <= traffic_timeout <= upper
    and traffic_success + traffic_timeout >= traffic_count - 2  # at most 2 other codes (502/504/etc.)
)

# Sub-gate e: good revision was NOT affected by the bad revision being minted.
e_good_revision_still_healthy = (
    good_health_at_trigger == 'Healthy'
    and good_running_at_trigger == 'Running'
    and baseline_target_port == expected_target_port
)

h1_sub_gates = {
    'a_bad_revision_minted_with_port_mismatched_image': a_bad_revision_minted,
    'b_ingress_traffic_split_50_50': b_traffic_split_50_50,
    'c_bad_revision_probe_failure_evidence': c_bad_revision_probe_failure_evidence,
    'd_curl_loop_shows_intermittent_failure': d_curl_loop_shows_intermittent_failure,
    'e_good_revision_still_healthy': e_good_revision_still_healthy,
}
h1_all_subgates_pass = all(h1_sub_gates.values())

if h1_all_subgates_pass:
    gate_classification = 'canary_failure_reproduced_50_50_traffic_split'
elif (
    a_bad_revision_minted and b_traffic_split_50_50
    and traffic_success >= traffic_count - 2
):
    # Bad revision minted and traffic split applied, but no per-request failures
    # observed — this contradicts the canary-failure hypothesis.
    gate_classification = 'canary_failure_did_not_materialize'
else:
    gate_classification = 'partial_observation_some_subgates_failed'

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'subscription': os.environ['AZ_SUBSCRIPTION'],
    'rg': os.environ['RG'],
    'app_name': os.environ['APP_NAME'],
    'app_fqdn': os.environ['APP_FQDN'],
    'trigger_window': {
        'start_utc': os.environ['TRIGGER_UTC'],
        'bad_revision_name': bad_revision,
        'bad_revision_image': bad_image,
        'bad_revision_created_time': os.environ['BAD_CREATED'],
        'bad_revision_health_state': bad_health,
        'bad_revision_running_state': bad_running,
        'bad_revision_running_state_details': bad_running_details,
        'bad_revision_provisioning_state': os.environ['BAD_PROVISIONING'],
        'good_revision_name': good_revision,
        'good_revision_health_state_at_trigger': good_health_at_trigger,
        'good_revision_running_state_at_trigger': good_running_at_trigger,
        'ingress_target_port': baseline_target_port,
        'bad_image_listening_port_documented': int(os.environ['BAD_IMAGE_LISTENING_PORT']),
    },
    'traffic_split': {
        'ingress_traffic_array': ingress_traffic,
        'weights_sorted': weights,
    },
    'client_probe_results': {
        'attempts': traffic_count,
        'success_count_200': traffic_success,
        'timeout_count_000': traffic_timeout,
        'tolerance_band_for_timeouts': [lower, upper],
    },
    'system_log_capture': {
        'exit_code': int(os.environ['SYSLOG_EXIT_CODE']),
        'probe_failed_lines_in_tail': syslog_probe_failed_count,
        'note': 'Log Analytics ingestion lag is 5-10 minutes; tail count is best-effort. Consumed by the H1 c_bad_revision_probe_failure_evidence fallback predicate (bad revision non-healthy state + count > 0) when runningStateDetails lacks port-specific text; also re-used by the H2 a_pre_fix_failure_re_confirmed fallback predicate in verify.sh.',
    },
    'h1_sub_gates': h1_sub_gates,
    'h1_all_subgates_pass': h1_all_subgates_pass,
    'gate_classification': gate_classification,
}

with open(os.path.join(os.environ['EVIDENCE_DIR'], '12-h1-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== H1 summary ==="
echo "Bad revision: ${BAD_REVISION}"
echo "Bad revision runningState: ${BAD_RUNNING}"
echo "Bad revision runningStateDetails: ${BAD_RUNNING_DETAILS}"
echo "Good revision still healthy at trigger time: ${GOOD_HEALTH_AT_TRIGGER}/${GOOD_RUNNING_AT_TRIGGER}"
echo "Traffic loop: ${TRAFFIC_SUCCESS_COUNT}/${TRAFFIC_PROBE_COUNT} HTTP 200, ${TRAFFIC_TIMEOUT_COUNT}/${TRAFFIC_PROBE_COUNT} curl 000 timeout"
echo "Tolerance band for timeouts: [${TIMEOUT_COUNT_LOWER_BOUND}, ${TIMEOUT_COUNT_UPPER_BOUND}] out of ${TRAFFIC_PROBE_COUNT}"
GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/12-h1-gate.json'))['gate_classification'])")
echo "Gate classification: ${GATE}"

if [ "$GATE" = "canary_failure_reproduced_50_50_traffic_split" ]; then
    echo ""
    echo "H1 PASS: 50/50 traffic split between good and port-mismatched bad revision produced"
    echo "intermittent client failures within tolerance band. Proceed to verify.sh for the"
    echo "rollback experiment (traffic 100% to good revision)."
    exit 0
elif [ "$GATE" = "canary_failure_did_not_materialize" ]; then
    echo ""
    echo "H1 FALSIFIED: bad revision was minted and traffic split applied, but the curl loop"
    echo "did not show per-request failures. This contradicts the canary-failure hypothesis."
    echo "Investigate the bad image (does it actually listen on a different port?) before"
    echo "proceeding (verify.sh will exit 1 if this state)."
    exit 2
else
    echo ""
    echo "H1 PARTIAL: some sub-gates failed. Inspect 12-h1-gate.json for details."
    exit 2
fi
