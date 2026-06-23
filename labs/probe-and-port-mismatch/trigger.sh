#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${ACR_NAME:?Set ACR_NAME before running}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKLOAD_DIR="${SCRIPT_DIR}/workload"
IMAGE_TAG="v1"

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "trigger.sh starting at ${UTC_NOW}"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "RG: ${RG}"
echo "App: ${APP_NAME}"
echo "ACR: ${ACR_NAME}"
echo "Workload dir: ${WORKLOAD_DIR}"
echo ""
echo "Note: This lab reproduces probe failure caused by a port mismatch between the container"
echo "workload's listening port and the Container Apps ingress targetPort. The Bicep baseline"
echo "deploys the placeholder helloworld image (listens on :80) with ingress targetPort=8000,"
echo "so the baseline revision is itself mismatched. Phase 4 builds a workload that explicitly"
echo "binds to :3000 and applies it via az containerapp update --image (mints --0000001), while"
echo "ingress remains at 8000 — producing a second, deliberately documented mismatch (3000 vs"
echo "8000) on the new revision. H1 captures that mismatched state. The fix in verify.sh is an"
echo "app-scope-only ingress edit (az containerapp ingress update --target-port 3000) that does"
echo "not mint a new revision; H2 falsifies image-broken / pull-failure / probe-config theories"
echo "by showing the SAME revision name and createdTime recover."
echo ""

echo "=== Phase 1: resolve infrastructure (FQDN, ACR loginServer, ACR creds) ==="
APP_FQDN=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv | tr -d '\r')
ACR_LOGIN_SERVER=$(az acr show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$ACR_NAME" \
    --resource-group "$RG" \
    --query "loginServer" \
    --output tsv | tr -d '\r')
ACR_USERNAME=$(az acr credential show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$ACR_NAME" \
    --query "username" \
    --output tsv | tr -d '\r')
# Password is captured for the registry-set call only; it is never written to evidence files.
ACR_PASSWORD=$(az acr credential show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$ACR_NAME" \
    --query "passwords[0].value" \
    --output tsv | tr -d '\r')
echo "App FQDN: ${APP_FQDN}"
echo "ACR login server: ${ACR_LOGIN_SERVER}"
echo "ACR admin username: ${ACR_USERNAME}"
echo ""

# Capture non-secret resolution to evidence; password explicitly excluded.
export EVIDENCE_DIR APP_FQDN ACR_LOGIN_SERVER ACR_USERNAME APP_NAME ACR_NAME RG AZ_SUBSCRIPTION
python3 <<'PYEOF'
import json, os
out = {
    'utc': os.environ.get('UTC_NOW', ''),
    'subscription': os.environ['AZ_SUBSCRIPTION'],
    'rg': os.environ['RG'],
    'app_name': os.environ['APP_NAME'],
    'app_fqdn': os.environ['APP_FQDN'],
    'acr_name': os.environ['ACR_NAME'],
    'acr_login_server': os.environ['ACR_LOGIN_SERVER'],
    'acr_username': os.environ['ACR_USERNAME'],
    'note': 'ACR admin password intentionally omitted; captured in-memory only for the registry-set call.',
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '01-infra-resolve.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 2: baseline revision snapshot (helloworld :80 vs targetPort :8000) ==="
# The Bicep baseline is intentionally mismatched: helloworld listens on :80 but ingress
# targets :8000. Capture this pre-trigger state so H1 can distinguish the *new* mismatch
# (:3000 vs :8000) from the pre-existing one and so the lab guide's same-revision
# falsification argument has a documented starting point.
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, runningState: properties.runningState, trafficWeight: properties.trafficWeight, createdTime: properties.createdTime, image: properties.template.containers[0].image}" \
    --output json \
    > "$EVIDENCE_DIR/02-baseline-revisions.json"
cat "$EVIDENCE_DIR/02-baseline-revisions.json"
BASELINE_TARGET_PORT=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.ingress.targetPort" \
    --output tsv | tr -d '\r')
echo "Baseline ingress targetPort: ${BASELINE_TARGET_PORT} (expected: 8000 from Bicep)"
echo ""

echo "=== Phase 3: ACR build workload (Flask + Gunicorn listening on :3000) ==="
BUILD_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "ACR build UTC: ${BUILD_UTC}"
# --only-show-errors silences the bicep-style WARNING noise on stderr; the build log itself
# still goes to stdout. The build can take 3-7 minutes depending on registry warm state.
set +e
az acr build \
    --subscription "$AZ_SUBSCRIPTION" \
    --registry "$ACR_NAME" \
    --image "${APP_NAME}:${IMAGE_TAG}" \
    --only-show-errors \
    "$WORKLOAD_DIR" \
    > "$EVIDENCE_DIR/03-acr-build.log" 2>&1
ACR_BUILD_EXIT_CODE=$?
set -e
echo "ACR build exit code: ${ACR_BUILD_EXIT_CODE} (expected: 0)"
echo "Last 30 lines of build log:"
tail -n 30 "$EVIDENCE_DIR/03-acr-build.log" || true
echo ""

if [ "$ACR_BUILD_EXIT_CODE" -ne 0 ]; then
    echo "ERROR: ACR build failed. Cannot proceed with trigger."
    exit 1
fi

echo "=== Phase 4: trigger — set registry creds + update --image (mints --0000001 with :3000 workload) ==="
# Split into three commands matching the documented capture-day sequence in the lab guide.
# az containerapp update --image is a revision-template change and mints a new revision.
# We do NOT pass --target-port here so ingress remains at 8000 from the Bicep baseline,
# producing the documented :3000 vs :8000 mismatch on the new revision.
TRIGGER_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Trigger UTC: ${TRIGGER_UTC}"

az containerapp registry set \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --server "$ACR_LOGIN_SERVER" \
    --username "$ACR_USERNAME" \
    --password "$ACR_PASSWORD" \
    --only-show-errors \
    --output json \
    > "$EVIDENCE_DIR/04-registry-set.json" 2> "$EVIDENCE_DIR/04-registry-set.stderr"
echo "Registry credentials configured on app."
echo ""

az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --image "${ACR_LOGIN_SERVER}/${APP_NAME}:${IMAGE_TAG}" \
    --only-show-errors \
    --output json \
    > "$EVIDENCE_DIR/05-containerapp-update-image.json" 2> "$EVIDENCE_DIR/05-containerapp-update-image.stderr"
TRIGGER_REVISION_NAME=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/05-containerapp-update-image.json')); print(d['properties']['latestRevisionName'])" 2>/dev/null || echo "")
echo "Trigger revision name: ${TRIGGER_REVISION_NAME} (expected: ${APP_NAME}--XXXXXXX)"
echo ""

echo "=== Phase 5: wait for revision provisioning to settle (poll up to 5 minutes) ==="
# Container Apps revision provisioningState progresses Provisioning -> Provisioned. The
# runtime state then reports as runningState ('Activating', 'Running', 'Failed', 'Degraded').
# In current Container Apps platform behavior, a probe-failing revision can stay in
# 'Activating' indefinitely while the platform retries probes; the platform surfaces the
# diagnostic via runningStateDetails (e.g. "The TargetPort 8000 does not match the
# listening port 3000."). We poll until either a terminal runningState (Failed/Running/
# Degraded) is reached, OR runningStateDetails becomes non-empty (platform recognized
# the failure cause), with a 5-minute ceiling.
WAIT_LOG="$EVIDENCE_DIR/06-wait-provisioning.log"
: > "$WAIT_LOG"
ATTEMPTS=30  # 30 * 10s = 300s
for i in $(seq 1 $ATTEMPTS); do
    STATE=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$TRIGGER_REVISION_NAME" \
        --query "properties.provisioningState" \
        --output tsv 2>/dev/null | tr -d '\r' || echo "Unknown")
    RUN_STATE=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$TRIGGER_REVISION_NAME" \
        --query "properties.runningState" \
        --output tsv 2>/dev/null | tr -d '\r' || echo "Unknown")
    RUN_DETAILS=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$TRIGGER_REVISION_NAME" \
        --query "properties.runningStateDetails" \
        --output tsv 2>/dev/null | tr -d '\r' || echo "")
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "[$ts] attempt $i/$ATTEMPTS provisioningState=${STATE} runningState=${RUN_STATE} runningStateDetails=${RUN_DETAILS}" | tee -a "$WAIT_LOG"
    # Break on either a terminal runningState (Failed/Running/Degraded) OR when the
    # platform has recognized the failure mode and populated runningStateDetails. The
    # runningStateDetails text is platform-emitted evidence of the probe failure even
    # if the revision is still in 'Activating' state.
    if [ "$RUN_STATE" = "Failed" ] || [ "$RUN_STATE" = "Running" ] || [ "$RUN_STATE" = "Degraded" ]; then
        break
    fi
    if [ -n "$RUN_DETAILS" ] && [ "$STATE" = "Provisioned" ] && [ "$i" -ge 3 ]; then
        # Wait at least 30s after provisioning to let the platform emit detail text.
        break
    fi
    sleep 10
done
echo ""

echo "=== Phase 6: capture failure-state revision details ==="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "[].{name: name, active: properties.active, healthState: properties.healthState, runningState: properties.runningState, provisioningState: properties.provisioningState, trafficWeight: properties.trafficWeight, createdTime: properties.createdTime, replicas: properties.replicas, image: properties.template.containers[0].image}" \
    --output json \
    > "$EVIDENCE_DIR/07-revision-list-failed.json"
cat "$EVIDENCE_DIR/07-revision-list-failed.json"
echo ""

az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --revision "$TRIGGER_REVISION_NAME" \
    --query "{name: name, healthState: properties.healthState, runningState: properties.runningState, provisioningState: properties.provisioningState, replicas: properties.replicas, runningStateDetails: properties.runningStateDetails, image: properties.template.containers[0].image, createdTime: properties.createdTime}" \
    --output json \
    > "$EVIDENCE_DIR/08-revision-show-failed.json"
cat "$EVIDENCE_DIR/08-revision-show-failed.json"
echo ""

# Capture the current targetPort from the app config to document that ingress is still 8000.
TRIGGER_TARGET_PORT=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "properties.configuration.ingress.targetPort" \
    --output tsv | tr -d '\r')
echo "Trigger-state ingress targetPort: ${TRIGGER_TARGET_PORT} (expected: 8000 — unchanged from baseline; mismatch is workload :3000 vs ingress :8000)"
echo ""

TRIGGER_HEALTH=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-failed.json')).get('healthState') or 'Unknown')")
TRIGGER_RUNNING=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-failed.json')).get('runningState') or 'Unknown')")
TRIGGER_PROVISIONING=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-failed.json')).get('provisioningState') or 'Unknown')")
TRIGGER_IMAGE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-failed.json')).get('image') or '')")
TRIGGER_CREATED=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-failed.json')).get('createdTime') or '')")
TRIGGER_RUNNING_DETAILS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/08-revision-show-failed.json')).get('runningStateDetails') or '')")
echo "Trigger revision healthState: ${TRIGGER_HEALTH} (expected: Unhealthy or None with details)"
echo "Trigger revision runningState: ${TRIGGER_RUNNING} (expected: Failed, Degraded, or Activating with port-mismatch details)"
echo "Trigger revision provisioningState: ${TRIGGER_PROVISIONING}"
echo "Trigger revision image: ${TRIGGER_IMAGE}"
echo "Trigger revision createdTime: ${TRIGGER_CREATED}"
echo ""

echo "=== Phase 7: HTTP probe from client (expected: 5/5 non-200 / connection failure) ==="
# curl with --max-time 10 caps each request so a hung connection cannot stall the script.
# --write-out '%{http_code}' returns the actual HTTP status (000 means no response).
PROBE_LOG="$EVIDENCE_DIR/09-curl-probes-failed.json"
: > "$PROBE_LOG"
CURL_SUCCESS_COUNT=0
CURL_RESULTS=()
for i in 1 2 3 4 5; do
    CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "https://${APP_FQDN}/" 2>/dev/null || echo "000")
    CURL_RESULTS+=("$CODE")
    if [ "$CODE" = "200" ]; then
        CURL_SUCCESS_COUNT=$((CURL_SUCCESS_COUNT + 1))
    fi
    echo "Probe $i: HTTP ${CODE}"
    sleep 2
done

export CURL_RESULTS_STR="${CURL_RESULTS[*]}"
export CURL_SUCCESS_COUNT APP_FQDN
python3 <<'PYEOF'
import json, os
results = os.environ['CURL_RESULTS_STR'].split()
out = {
    'fqdn': os.environ['APP_FQDN'],
    'attempts': len(results),
    'http_codes': results,
    'success_count_200': int(os.environ['CURL_SUCCESS_COUNT']),
    'expected_success_count': 0,
    'note': 'HTTP 000 indicates the TCP connection was not established within --max-time 10s (probe-failed revisions accept no traffic).',
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], '09-curl-probes-failed.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 8: best-effort system log capture (LAW ingestion may not have caught up yet) ==="
# az containerapp logs show --type system queries Log Analytics, which has ingestion lag
# of 5-10 minutes. We capture what's available with --tail 50; the lab guide separately
# documents richer KQL queries the operator can run later.
set +e
az containerapp logs show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --type system \
    --tail 50 \
    > "$EVIDENCE_DIR/10-system-logs-tail.log" 2>&1
SYSLOG_EXIT_CODE=$?
set -e
echo "System log capture exit code: ${SYSLOG_EXIT_CODE} (0=available, non-zero=ingestion lag or transient API)"
SYSLOG_PROBE_FAILED_COUNT=$(grep -c "ProbeFailed\|Probe of" "$EVIDENCE_DIR/10-system-logs-tail.log" 2>/dev/null || echo "0")
SYSLOG_PROBE_FAILED_COUNT=$(echo "$SYSLOG_PROBE_FAILED_COUNT" | tr -d '\r\n ')
echo "ProbeFailed event lines captured in tail: ${SYSLOG_PROBE_FAILED_COUNT} (expected: best-effort; richer KQL pack runs later)"
echo ""

echo "=== Phase 9: emit H1 gate JSON ==="
UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR AZ_SUBSCRIPTION RG APP_NAME ACR_NAME APP_FQDN
export BUILD_UTC TRIGGER_UTC ACR_BUILD_EXIT_CODE TRIGGER_REVISION_NAME
export TRIGGER_HEALTH TRIGGER_RUNNING TRIGGER_PROVISIONING TRIGGER_IMAGE TRIGGER_CREATED
export TRIGGER_RUNNING_DETAILS
export TRIGGER_TARGET_PORT BASELINE_TARGET_PORT CURL_SUCCESS_COUNT CURL_RESULTS_STR
export SYSLOG_EXIT_CODE SYSLOG_PROBE_FAILED_COUNT UTC_CAPTURED

python3 <<'PYEOF'
import json, os

acr_build_exit_code = int(os.environ['ACR_BUILD_EXIT_CODE'])
trigger_revision_name = os.environ['TRIGGER_REVISION_NAME']
trigger_running = os.environ['TRIGGER_RUNNING']
trigger_health = os.environ['TRIGGER_HEALTH']
trigger_target_port = os.environ['TRIGGER_TARGET_PORT']
trigger_image = os.environ['TRIGGER_IMAGE']
trigger_running_details = os.environ.get('TRIGGER_RUNNING_DETAILS', '')
curl_success_count = int(os.environ['CURL_SUCCESS_COUNT'])
curl_results = os.environ['CURL_RESULTS_STR'].split()
syslog_probe_failed_count = int(os.environ.get('SYSLOG_PROBE_FAILED_COUNT', '0'))

a_acr_build_succeeded = acr_build_exit_code == 0
b_trigger_revision_minted = bool(trigger_revision_name)
# H1 sub-gate c requires PORT-SPECIFIC evidence of probe failure, not just a
# bare non-healthy label. Two acceptance paths:
#   Strong  : runningStateDetails contains explicit port/probe text emitted by
#             the platform ("TargetPort N does not match the listening port M",
#             "ProbeFailed", etc.). This is the authoritative signal.
#   Fallback: non-healthy state (Failed/Degraded) PAIRED with a non-zero
#             ProbeFailed count from the system log capture. The fallback
#             exists because runningStateDetails text formatting is platform-
#             controlled and has varied across captures, so a probe-failure
#             corroboration from the syslog stream is required when the
#             runningStateDetails text is empty/missing.
# A bare 'Failed'/'Degraded' label with NO port-specific corroboration is
# explicitly insufficient — it could be caused by image pull, OOMKilled,
# crash loop, or other non-port failure modes.
c_probe_failure_evidence_present = (
    (
        trigger_running_details
        and (
            'TargetPort' in trigger_running_details
            or 'listening port' in trigger_running_details
            or 'ProbeFailed' in trigger_running_details
        )
    )
    or (
        trigger_running in ('Failed', 'Degraded')
        and syslog_probe_failed_count > 0
    )
)
d_zero_client_200s_out_of_five = curl_success_count == 0 and len(curl_results) == 5
e_target_port_still_mismatched = (
    trigger_target_port == '8000'
    and bool(trigger_image)
    and ':v1' in trigger_image
)

h1_sub_gates = {
    'a_acr_build_succeeded': a_acr_build_succeeded,
    'b_trigger_revision_minted': b_trigger_revision_minted,
    'c_probe_failure_evidence_present': c_probe_failure_evidence_present,
    'd_zero_client_200s_out_of_five': d_zero_client_200s_out_of_five,
    'e_target_port_still_mismatched': e_target_port_still_mismatched,
}
h1_all_subgates_pass = all(h1_sub_gates.values())

if h1_all_subgates_pass:
    gate_classification = 'port_mismatch_probe_failure_reproduced'
elif (trigger_running == 'Running' and trigger_health == 'Healthy'
      and curl_success_count == 5
      and a_acr_build_succeeded and b_trigger_revision_minted):
    gate_classification = 'probe_failure_did_not_materialize'
else:
    gate_classification = 'partial_observation_some_subgates_failed'

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'subscription': os.environ['AZ_SUBSCRIPTION'],
    'rg': os.environ['RG'],
    'app_name': os.environ['APP_NAME'],
    'acr_name': os.environ['ACR_NAME'],
    'app_fqdn': os.environ['APP_FQDN'],
    'build_window': {
        'start_utc': os.environ['BUILD_UTC'],
        'exit_code': acr_build_exit_code,
    },
    'trigger_window': {
        'start_utc': os.environ['TRIGGER_UTC'],
        'revision_name': trigger_revision_name,
        'image': trigger_image,
        'created_time': os.environ['TRIGGER_CREATED'],
        'health_state': trigger_health,
        'running_state': trigger_running,
        'running_state_details': trigger_running_details,
        'provisioning_state': os.environ['TRIGGER_PROVISIONING'],
        'ingress_target_port': trigger_target_port,
        'baseline_ingress_target_port': os.environ['BASELINE_TARGET_PORT'],
    },
    'client_probe_results': {
        'attempts': len(curl_results),
        'http_codes': curl_results,
        'success_count_200': curl_success_count,
    },
    'system_log_capture': {
        'exit_code': int(os.environ['SYSLOG_EXIT_CODE']),
        'probe_failed_lines_in_tail': int(os.environ['SYSLOG_PROBE_FAILED_COUNT']),
        'note': 'Log Analytics ingestion lag is 5-10 minutes; tail count is best-effort. Consumed by the H1 c_probe_failure_evidence_present fallback predicate (non-healthy state + count > 0) when runningStateDetails lacks port-specific text; also re-used by the H2 a_pre_fix_probe_failure_evidence fallback predicate in verify.sh.',
    },
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
echo "ACR build exit code: ${ACR_BUILD_EXIT_CODE} (expected: 0)"
echo "Trigger revision name: ${TRIGGER_REVISION_NAME}"
echo "Trigger revision runningState: ${TRIGGER_RUNNING}"
echo "Trigger revision runningStateDetails: ${TRIGGER_RUNNING_DETAILS}"
echo "Trigger revision healthState: ${TRIGGER_HEALTH}"
echo "Trigger ingress targetPort: ${TRIGGER_TARGET_PORT} (expected: 8000, still mismatched vs workload :3000)"
echo "Client HTTP 200 count: ${CURL_SUCCESS_COUNT}/5 (expected: 0/5)"
GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/11-h1-gate.json'))['gate_classification'])")
echo "Gate classification: ${GATE}"

if [ "$GATE" = "port_mismatch_probe_failure_reproduced" ]; then
    echo ""
    echo "H1 PASS: probe failure reproduces with workload :3000 vs ingress :8000. Proceed to"
    echo "verify.sh for the recovery experiment (ingress-only edit to targetPort 3000)."
    exit 0
elif [ "$GATE" = "probe_failure_did_not_materialize" ]; then
    echo ""
    echo "H1 FALSIFIED: trigger revision became healthy despite the port mismatch, which"
    echo "contradicts documented probe behavior. Investigate workload Dockerfile, image"
    echo "build, or platform changes before proceeding (verify.sh will exit 1 if this state)."
    exit 2
else
    echo ""
    echo "H1 PARTIAL: some sub-gates failed. Inspect 11-h1-gate.json for details."
    exit 2
fi
