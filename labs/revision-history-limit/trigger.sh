#!/usr/bin/env bash
set -euo pipefail

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:?AZ_SUBSCRIPTION must be set (the lab subscription GUID)}"
RG="${RG:?RG must be set (the lab resource group)}"
APP_NAME="${APP_NAME:?APP_NAME must be set (Container App name from the Bicep output)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "$EVIDENCE_DIR"

LOG_FILE="${EVIDENCE_DIR}/00-trigger-run.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== trigger.sh started $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
echo "Resource group: $RG"
echo "Container app: $APP_NAME"
echo

echo "===== Phase 1: capture initial app configuration ====="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{maxInactiveRevisions: properties.configuration.maxInactiveRevisions, activeRevisionsMode: properties.configuration.activeRevisionsMode}" \
    --output json \
    > "${EVIDENCE_DIR}/01-app-config-before.json"
cat "${EVIDENCE_DIR}/01-app-config-before.json"

INIT_LIMIT=$(python3 -c "import json; print(json.load(open('${EVIDENCE_DIR}/01-app-config-before.json'))['maxInactiveRevisions'])")
echo "Read maxInactiveRevisions = ${INIT_LIMIT}"
if [ "${INIT_LIMIT}" != "2" ]; then
    echo "[INVALID RUN] Bicep was supposed to set maxInactiveRevisions=2. Saw '${INIT_LIMIT}'."
    echo "              Redeploy with the canonical Bicep before running this script."
    exit 1
fi
echo

echo "===== Phase 2: capture initial revision list ====="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --all \
    --query "[].{name:name, active:properties.active, createdTime:properties.createdTime, trafficWeight:properties.trafficWeight, provisioningState:properties.provisioningState, runningState:properties.runningState}" \
    --output json \
    > "${EVIDENCE_DIR}/02-revisions-initial.json"
cat "${EVIDENCE_DIR}/02-revisions-initial.json"
INITIAL_COUNT=$(python3 -c "import json; print(len(json.load(open('${EVIDENCE_DIR}/02-revisions-initial.json'))))")
echo "Initial revision count: ${INITIAL_COUNT}"
echo

echo "===== Phase 3: burst 10 env-var-only updates with unique nonce ====="
BURST_NONCE="$(date -u +%Y%m%d%H%M%S)"
echo "Burst nonce: ${BURST_NONCE}"
for N in 1 2 3 4 5 6 7 8 9 10; do
    echo "  -> Update ${N}/10 (REV=${BURST_NONCE}-${N})"
    az containerapp update \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --set-env-vars "REV=${BURST_NONCE}-${N}" \
        --query "{name:name, latestRevisionName:properties.latestRevisionName, provisioningState:properties.provisioningState}" \
        --output json
done
echo

BURST_END_EPOCH="$(date -u +%s)"
BURST_END_ISO="$(date -u -r "${BURST_END_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)"
echo "${BURST_END_EPOCH}" > "${EVIDENCE_DIR}/burst-completed-epoch.txt"
echo "${BURST_END_ISO}" > "${EVIDENCE_DIR}/burst-completed-iso.txt"
echo "Burst completed at ${BURST_END_ISO} (epoch ${BURST_END_EPOCH})"
echo

echo "===== Phase 4: capture revisions at t+0 (immediately after burst) ====="
az containerapp revision list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --all \
    --query "[].{name:name, active:properties.active, createdTime:properties.createdTime, trafficWeight:properties.trafficWeight, provisioningState:properties.provisioningState, runningState:properties.runningState}" \
    --output json \
    > "${EVIDENCE_DIR}/03-revisions-t0.json"
T0_COUNT=$(python3 -c "import json; print(len(json.load(open('${EVIDENCE_DIR}/03-revisions-t0.json'))))")
echo "t+0 revision count: ${T0_COUNT}"
echo

echo "===== trigger.sh evaluation ====="
if [ "${T0_COUNT}" -lt 8 ]; then
    echo "[INVALID RUN] Expected the burst to leave >=8 revisions visible at t+0 (1 initial + 10 burst minus eager prune)."
    echo "              Saw ${T0_COUNT}. The burst likely did not create distinct revisions (template-hash collision?)."
    echo "              Inspect ${EVIDENCE_DIR}/03-revisions-t0.json before running verify.sh."
    exit 1
fi
if [ "${T0_COUNT}" -le 2 ]; then
    echo "[FALSIFIED AT t+0] Inactive-revision retention limit pruned aggressively before t+5m sample window."
    echo "                   This contradicts the lab's bounded-observation hypothesis. Capture and stop."
    exit 2
fi
echo "[OK] Burst produced ${T0_COUNT} revisions at t+0."
echo "     burst-completed-epoch.txt is written; verify.sh will sample at t+5m and t+15m."
echo "     Run ./verify.sh next."
exit 0
