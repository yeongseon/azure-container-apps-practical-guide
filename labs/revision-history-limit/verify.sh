#!/usr/bin/env bash
set -euo pipefail

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:?AZ_SUBSCRIPTION must be set (the lab subscription GUID)}"
RG="${RG:?RG must be set (the lab resource group)}"
APP_NAME="${APP_NAME:?APP_NAME must be set (Container App name from the Bicep output)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "$EVIDENCE_DIR"

LOG_FILE="${EVIDENCE_DIR}/00-verify-run.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== verify.sh started $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
echo "Resource group: $RG"
echo "Container app: $APP_NAME"
echo

BURST_END_FILE="${EVIDENCE_DIR}/burst-completed-epoch.txt"
if [ ! -f "${BURST_END_FILE}" ]; then
    echo "[INVALID RUN] ${BURST_END_FILE} not found. Run ./trigger.sh first."
    exit 1
fi
BURST_END_EPOCH="$(cat "${BURST_END_FILE}")"
BURST_END_ISO="$(date -u -r "${BURST_END_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)"
echo "Burst end timestamp (from trigger.sh): ${BURST_END_ISO} (epoch ${BURST_END_EPOCH})"
echo

count_total() {
    python3 -c "import json; print(len(json.load(open('$1'))))"
}
count_inactive() {
    python3 -c "import json; d=json.load(open('$1')); print(sum(1 for r in d if not r['active']))"
}

wait_until() {
    local target_epoch="$1"
    local label="$2"
    local now
    now="$(date -u +%s)"
    if [ "${now}" -ge "${target_epoch}" ]; then
        echo "${label}: already past (now=${now}, target=${target_epoch})."
        return
    fi
    local wait_s=$((target_epoch - now))
    echo "${label}: sleeping ${wait_s}s until $(date -u -r "${target_epoch}" +%Y-%m-%dT%H:%M:%SZ)..."
    sleep "${wait_s}"
}

T5M_EPOCH=$((BURST_END_EPOCH + 300))
T15M_EPOCH=$((BURST_END_EPOCH + 900))

echo "===== Phase 5: wait until t+5m, then capture ====="
wait_until "${T5M_EPOCH}" "t+5m"
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --all \
    --query "[].{name:name, active:properties.active, createdTime:properties.createdTime, trafficWeight:properties.trafficWeight, provisioningState:properties.provisioningState, runningState:properties.runningState}" \
    --output json \
    > "${EVIDENCE_DIR}/04-revisions-t5m.json"
T5M_TOTAL=$(count_total "${EVIDENCE_DIR}/04-revisions-t5m.json")
T5M_INACTIVE=$(count_inactive "${EVIDENCE_DIR}/04-revisions-t5m.json")
echo "t+5m: total=${T5M_TOTAL}, inactive=${T5M_INACTIVE}"
echo

echo "===== Phase 6: wait until t+15m, then capture (primary hypothesis check) ====="
wait_until "${T15M_EPOCH}" "t+15m"
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --all \
    --query "[].{name:name, active:properties.active, createdTime:properties.createdTime, trafficWeight:properties.trafficWeight, provisioningState:properties.provisioningState, runningState:properties.runningState}" \
    --output json \
    > "${EVIDENCE_DIR}/05-revisions-t15m.json"
T15M_TOTAL=$(count_total "${EVIDENCE_DIR}/05-revisions-t15m.json")
T15M_INACTIVE=$(count_inactive "${EVIDENCE_DIR}/05-revisions-t15m.json")
echo "t+15m: total=${T15M_TOTAL}, inactive=${T15M_INACTIVE}"
echo

echo "===== Phase 7: capture app configuration at t+15m (prove setting persisted) ====="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{maxInactiveRevisions: properties.configuration.maxInactiveRevisions, activeRevisionsMode: properties.configuration.activeRevisionsMode}" \
    --output json \
    > "${EVIDENCE_DIR}/06-app-config-t15m.json"
cat "${EVIDENCE_DIR}/06-app-config-t15m.json"
T15M_LIMIT=$(python3 -c "import json; print(json.load(open('${EVIDENCE_DIR}/06-app-config-t15m.json'))['maxInactiveRevisions'])")
echo "Read maxInactiveRevisions at t+15m: ${T15M_LIMIT}"
echo

echo "===== verify.sh evaluation ====="
echo "Bounded-observation hypothesis:"
echo "  H1: At t+15m, maxInactiveRevisions config readback == 2 (setting persisted)."
echo "  H2: At t+15m, inactive revision count > 2 (pruning is NOT prompt within 15 min)."
echo "  If H1 AND H2 hold => hypothesis SUPPORTED (the preview setting is real, but pruning is asynchronous and not bounded by a short SLA)."
echo "  If H1 false => INVALID RUN (Bicep / CLI did not persist the value)."
echo "  If H1 true AND H2 false => FALSIFIED (pruning IS prompt within 15 min — update the lab claim)."
echo

if [ "${T15M_LIMIT}" != "2" ]; then
    echo "[INVALID RUN] maxInactiveRevisions at t+15m = '${T15M_LIMIT}' (expected 2)."
    echo "              Something mutated the config mid-run. Re-deploy and re-run."
    exit 1
fi
echo "[H1 PASS] maxInactiveRevisions persisted as 2 at t+15m."

if [ "${T15M_INACTIVE}" -le 2 ]; then
    echo "[H2 FALSIFIED] inactive revisions at t+15m = ${T15M_INACTIVE} (<= 2 limit)."
    echo "               Pruning happened within 15 min. Update the lab to reflect this."
    exit 2
fi
echo "[H2 PASS] inactive revisions at t+15m = ${T15M_INACTIVE} (> 2 limit) — pruning is NOT prompt within 15 min."
echo
echo "[BOUNDED-OBSERVATION HYPOTHESIS SUPPORTED]"
echo "  Operator takeaway: maxInactiveRevisions (preview) is honored as a target, NOT as a 15-min cleanup SLA."
echo "  For deterministic cleanup, use explicit lifecycle commands such as 'az containerapp revision deactivate'."
exit 0
