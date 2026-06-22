#!/usr/bin/env bash
set -euo pipefail

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:?AZ_SUBSCRIPTION must be set (the lab subscription GUID)}"
RG="${RG:?RG must be set (the lab resource group)}"
APP_NAME="${APP_NAME:?APP_NAME must be set (Container App name from the Bicep output)}"
APP_FQDN="${APP_FQDN:?APP_FQDN must be set (Container App ingress FQDN from the Bicep output)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "$EVIDENCE_DIR"

LOG_FILE="${EVIDENCE_DIR}/00-trigger-run.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== trigger.sh started $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
echo "Resource group: $RG"
echo "Container app:  $APP_NAME"
echo "Ingress FQDN:   $APP_FQDN"
echo

echo "===== Phase 1: capture initial app configuration ====="
az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "$APP_NAME" \
    --query "{cpu: properties.template.containers[0].resources.cpu, memory: properties.template.containers[0].resources.memory, minReplicas: properties.template.scale.minReplicas, maxReplicas: properties.template.scale.maxReplicas, activeRevisionsMode: properties.configuration.activeRevisionsMode}" \
    --output json \
    > "${EVIDENCE_DIR}/01-app-config-before.json"
cat "${EVIDENCE_DIR}/01-app-config-before.json"

INIT_CPU=$(python3 -c "import json; print(json.load(open('${EVIDENCE_DIR}/01-app-config-before.json'))['cpu'])")
echo "Initial CPU allocation: ${INIT_CPU} vCPU"
if [ "${INIT_CPU}" != "0.25" ]; then
    echo "[INVALID RUN] Bicep was supposed to set cpu=0.25. Saw '${INIT_CPU}'."
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
    > "${EVIDENCE_DIR}/02-revisions-before.json"
cat "${EVIDENCE_DIR}/02-revisions-before.json"
INIT_REV_COUNT=$(python3 -c "import json; print(len(json.load(open('${EVIDENCE_DIR}/02-revisions-before.json'))))")
echo "Initial revision count: ${INIT_REV_COUNT}"
echo

echo "===== Phase 3: warm up the replica (5 discarded GETs) ====="
URL="https://${APP_FQDN}/"
for I in 1 2 3 4 5; do
    HTTP_CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 "${URL}" || echo "000")
    echo "  warm-up GET ${I}/5 -> HTTP ${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "200" ]; then
        sleep 5
    fi
done
echo

echo "===== Phase 4: load test against cpu=0.25 baseline (100 req, 20 concurrent) ====="
python3 "${SCRIPT_DIR}/load_test.py" "${URL}" 100 20 "${EVIDENCE_DIR}/03-loadtest-cpu025.json"
echo

P95_CPU025=$(python3 -c "import json; print(int(round(json.load(open('${EVIDENCE_DIR}/03-loadtest-cpu025.json'))['latency_ms']['p95'])))")
N_OK_CPU025=$(python3 -c "import json; print(json.load(open('${EVIDENCE_DIR}/03-loadtest-cpu025.json'))['requests_ok'])")
echo "cpu=0.25 baseline: p95=${P95_CPU025}ms, requests_ok=${N_OK_CPU025}/100"

echo
echo "===== Phase 5: capture UsageNanoCores metric for the last 5 min ====="
RESOURCE_ID="/subscriptions/${AZ_SUBSCRIPTION}/resourceGroups/${RG}/providers/Microsoft.App/containerApps/${APP_NAME}"
az monitor metrics list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource "$RESOURCE_ID" \
    --metric UsageNanoCores \
    --aggregation Average Maximum \
    --interval PT1M \
    --output json \
    > "${EVIDENCE_DIR}/04-metrics-cpu025.json"
echo "Metric snapshot written to 04-metrics-cpu025.json"
echo

echo "===== trigger.sh evaluation ====="
if [ "${N_OK_CPU025}" -lt 95 ]; then
    echo "[INVALID RUN] Expected >=95/100 successful requests at cpu=0.25. Saw ${N_OK_CPU025}/100."
    echo "              The lab cannot draw a clean conclusion if the baseline run had network or app errors."
    echo "              Inspect ${EVIDENCE_DIR}/03-loadtest-cpu025.json and re-run."
    exit 1
fi
if [ "${P95_CPU025}" -lt 100 ]; then
    echo "[INVALID RUN] cpu=0.25 baseline p95 (${P95_CPU025}ms) is below the 100ms minimum the lab needs to show a CPU-throttling effect."
    echo "              The workload may have been too light, the replica may have under-utilized, or the request may have completed in browser cache. Re-run."
    exit 1
fi
echo "[OK] cpu=0.25 baseline produced p95=${P95_CPU025}ms with ${N_OK_CPU025}/100 successful requests."
echo "     This is a clean baseline for the cpu=1.0 comparison in verify.sh."
echo "     Run ./verify.sh next."
exit 0
