#!/usr/bin/env bash
#
# fix-and-capture.sh — Phase A recovery script for the cpu-throttling lab.
#
# This script (originally named verify.sh in the Phase A evidence captured on
# 2026-06-22) applies the fix (cpu=0.25 -> 1.0, memory=0.5Gi -> 2.0Gi) and
# captures Phase 6-12 evidence (update result, post-fix config, post-fix
# revision list, post-fix load test, post-fix metrics). The Phase A trigger
# log file is therefore still named `00-verify-run.txt` and the literal string
# "verify.sh" appears throughout the captured stdout -- that is preserved
# as-is to match the historical evidence file on disk.
#
# Phase B (the falsification gate evaluation) is implemented in the SIBLING
# script `verify.sh`, which is purely deterministic over the JSON evidence
# files this script produces. The naming convention mirrors Lab 22
# (appinsights-connection-string-missing): fix-and-capture.sh writes the raw
# evidence, verify.sh evaluates the four-gate Phase B falsification structure
# without re-running Azure CLI calls.
#
set -euo pipefail

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:?AZ_SUBSCRIPTION must be set (the lab subscription GUID)}"
RG="${RG:?RG must be set (the lab resource group)}"
APP_NAME="${APP_NAME:?APP_NAME must be set (Container App name from the Bicep output)}"
APP_FQDN="${APP_FQDN:?APP_FQDN must be set (Container App ingress FQDN from the Bicep output)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "$EVIDENCE_DIR"

# NOTE: The log filename `00-verify-run.txt` reflects this script's original
# name (verify.sh) at the time the Phase A evidence was captured. The literal
# string is kept so the historical evidence file on disk is byte-identical to
# what fix-and-capture.sh writes today.
LOG_FILE="${EVIDENCE_DIR}/00-verify-run.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== verify.sh started $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
echo "Resource group: $RG"
echo "Container app:  $APP_NAME"
echo "Ingress FQDN:   $APP_FQDN"
echo

BASELINE_FILE="${EVIDENCE_DIR}/03-loadtest-cpu025.json"
if [ ! -f "${BASELINE_FILE}" ]; then
    echo "[INVALID RUN] ${BASELINE_FILE} not found. Run ./trigger.sh first."
    exit 1
fi
P95_CPU025=$(python3 -c "import json; print(int(round(json.load(open('${BASELINE_FILE}'))['latency_ms']['p95'])))")
N_OK_CPU025=$(python3 -c "import json; print(json.load(open('${BASELINE_FILE}'))['requests_ok'])")
echo "cpu=0.25 baseline (from trigger.sh): p95=${P95_CPU025}ms, requests_ok=${N_OK_CPU025}/100"
echo

echo "===== Phase 6: apply the fix (cpu 0.25 -> 1.0, memory 0.5Gi -> 2.0Gi) ====="
az containerapp update \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --cpu 1.0 \
    --memory 2.0Gi \
    --query "{name:name, latestRevisionName:properties.latestRevisionName, provisioningState:properties.provisioningState}" \
    --output json \
    > "${EVIDENCE_DIR}/05-update-result.json"
cat "${EVIDENCE_DIR}/05-update-result.json"
NEW_REV=$(python3 -c "import json; print(json.load(open('${EVIDENCE_DIR}/05-update-result.json'))['latestRevisionName'])")
echo "New revision created: ${NEW_REV}"
echo

echo "===== Phase 7: wait for the new revision to be Running (max 5 min) ====="
DEADLINE=$(( $(date -u +%s) + 300 ))
while true; do
    NOW=$(date -u +%s)
    if [ "${NOW}" -ge "${DEADLINE}" ]; then
        echo "[INVALID RUN] New revision ${NEW_REV} did not reach runningState=Running within 5 min."
        exit 1
    fi
    RUNNING_STATE=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "${NEW_REV}" \
        --query "properties.runningState" \
        --output tsv 2>/dev/null || echo "Unknown")
    PROVISIONING_STATE=$(az containerapp revision show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "${NEW_REV}" \
        --query "properties.provisioningState" \
        --output tsv 2>/dev/null || echo "Unknown")
    echo "  $(date -u +%H:%M:%SZ) runningState=${RUNNING_STATE} provisioningState=${PROVISIONING_STATE}"
    if [ "${RUNNING_STATE}" = "Running" ] || [ "${RUNNING_STATE}" = "RunningAtMaxScale" ]; then
        break
    fi
    sleep 10
done
echo "[OK] New revision ${NEW_REV} reached runningState=${RUNNING_STATE}"
echo

echo "===== Phase 8: capture post-fix app configuration ====="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{cpu: properties.template.containers[0].resources.cpu, memory: properties.template.containers[0].resources.memory, minReplicas: properties.template.scale.minReplicas, maxReplicas: properties.template.scale.maxReplicas, latestRevisionName: properties.latestRevisionName}" \
    --output json \
    > "${EVIDENCE_DIR}/06-app-config-after.json"
cat "${EVIDENCE_DIR}/06-app-config-after.json"
POST_CPU=$(python3 -c "import json; print(json.load(open('${EVIDENCE_DIR}/06-app-config-after.json'))['cpu'])")
echo "Post-fix CPU allocation: ${POST_CPU} vCPU"
echo

echo "===== Phase 9: capture revision list after fix ====="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --all \
    --query "[].{name:name, active:properties.active, createdTime:properties.createdTime, trafficWeight:properties.trafficWeight, provisioningState:properties.provisioningState, runningState:properties.runningState}" \
    --output json \
    > "${EVIDENCE_DIR}/07-revisions-after.json"
cat "${EVIDENCE_DIR}/07-revisions-after.json"
echo

echo "===== Phase 10: warm up the new replica (5 discarded GETs) ====="
URL="https://${APP_FQDN}/"
for I in 1 2 3 4 5; do
    HTTP_CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 "${URL}" || echo "000")
    echo "  warm-up GET ${I}/5 -> HTTP ${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "200" ]; then
        sleep 5
    fi
done
echo

echo "===== Phase 11: load test against cpu=1.0 post-fix (100 req, 20 concurrent) ====="
python3 "${SCRIPT_DIR}/load_test.py" "${URL}" 100 20 "${EVIDENCE_DIR}/08-loadtest-cpu1.json"
echo

P95_CPU1=$(python3 -c "import json; print(int(round(json.load(open('${EVIDENCE_DIR}/08-loadtest-cpu1.json'))['latency_ms']['p95'])))")
N_OK_CPU1=$(python3 -c "import json; print(json.load(open('${EVIDENCE_DIR}/08-loadtest-cpu1.json'))['requests_ok'])")
echo "cpu=1.0 post-fix: p95=${P95_CPU1}ms, requests_ok=${N_OK_CPU1}/100"
echo

echo "===== Phase 12: capture UsageNanoCores metric for the last 5 min (post-fix) ====="
RESOURCE_ID="/subscriptions/${AZ_SUBSCRIPTION}/resourceGroups/${RG}/providers/Microsoft.App/containerApps/${APP_NAME}"
az monitor metrics list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource "$RESOURCE_ID" \
    --metric UsageNanoCores \
    --aggregation Average Maximum \
    --interval PT1M \
    --output json \
    > "${EVIDENCE_DIR}/09-metrics-cpu1.json"
echo "Metric snapshot written to 09-metrics-cpu1.json"
echo

echo "===== verify.sh evaluation ====="
echo "CPU throttling hypothesis:"
echo "  H1: p95 at cpu=0.25 > 100ms (baseline confirms CPU pressure is observable)."
echo "  H2: p95 at cpu=1.0 < 0.5 * p95 at cpu=0.25 (at least 50% reduction)."
echo "  If H1 AND H2 hold => hypothesis SUPPORTED (per-replica CPU is the bottleneck)."
echo "  If H1 false => INVALID RUN (baseline too light; trigger.sh should have caught this)."
echo "  If H1 true AND H2 false => FALSIFIED (CPU is not the bottleneck; investigate concurrency, network, or other resources)."
echo
echo "Measured:"
echo "  cpu=0.25 p95: ${P95_CPU025}ms (${N_OK_CPU025}/100 ok)"
echo "  cpu=1.0  p95: ${P95_CPU1}ms (${N_OK_CPU1}/100 ok)"
echo

if [ "${N_OK_CPU1}" -lt 95 ]; then
    echo "[INVALID RUN] Post-fix run only had ${N_OK_CPU1}/100 successful requests."
    exit 1
fi

THRESHOLD=$(( P95_CPU025 / 2 ))
if [ "${P95_CPU1}" -ge "${THRESHOLD}" ]; then
    echo "[H2 FALSIFIED] cpu=1.0 p95 (${P95_CPU1}ms) is NOT below 50% of cpu=0.25 p95 (${THRESHOLD}ms)."
    echo "               CPU allocation is NOT the dominant bottleneck for this workload."
    echo "               Investigate: concurrency limits, network egress, dependency latency, or container memory pressure."
    exit 2
fi
echo "[H2 PASS] cpu=1.0 p95 (${P95_CPU1}ms) < 50% of cpu=0.25 p95 (${THRESHOLD}ms)."
echo
echo "[CPU-THROTTLING HYPOTHESIS SUPPORTED]"
echo "  Per-replica CPU was the dominant bottleneck. Increasing from 0.25 to 1.0 vCPU eliminated the throttling-induced tail latency."
echo "  Operator action: scale per-replica CPU when each request needs more compute, OR scale OUT replicas when total throughput is the constraint."
exit 0
