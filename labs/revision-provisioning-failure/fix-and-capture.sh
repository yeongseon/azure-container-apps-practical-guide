#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:-$(az account show --query 'id' --output tsv)}"
RG="${RG:-rg-aca-lab-revprov}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-labrevprov}"

echo "fix-and-capture.sh starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "Resource group: ${RG}"
echo "Location: ${LOCATION}"
echo

if ! az group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${RG}" \
    --output none >/dev/null 2>&1; then
    echo "=== Phase 1: create resource group ==="
    az group create \
        --subscription "${AZ_SUBSCRIPTION}" \
        --name "${RG}" \
        --location "${LOCATION}" \
        --output json
    echo
fi

echo "=== Phase 2: deploy or redeploy baseline infra ==="
az deployment group create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name main \
    --template-file "${SCRIPT_DIR}/infra/main.bicep" \
    --parameters baseName="${BASE_NAME}" location="${LOCATION}" \
    --output json \
    > "${EVIDENCE_DIR}/00-deployment-result.json"
echo "Deployment result captured to evidence/00-deployment-result.json"
echo

APP_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name main \
    --query 'properties.outputs.containerAppName.value' \
    --output tsv)"

echo "=== Phase 3: capture baseline revision list ==="
az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --output json \
    > "${EVIDENCE_DIR}/01-revision-list.json"
echo

echo "=== Phase 4: trigger H1 with bad-path startup probe ==="
TRIGGER_PATCH="$(mktemp -t revprov-trigger-XXXXXX.yaml)"
trap 'rm -f "${TRIGGER_PATCH}" "${FIX_PATCH:-}"' EXIT
cat > "${TRIGGER_PATCH}" <<'EOF'
properties:
  template:
    revisionSuffix: badpath2
    containers:
      - name: app
        image: nginx:alpine
        resources:
          cpu: 0.5
          memory: 1Gi
        probes:
          - type: Startup
            httpGet:
              path: /nonexistent-health-endpoint
              port: 80
            periodSeconds: 5
            failureThreshold: 3
            successThreshold: 1
            timeoutSeconds: 1
EOF

az containerapp update \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --yaml "${TRIGGER_PATCH}" \
    --output none
sleep 60
echo

echo "=== Phase 5: capture H1 raw evidence surfaces ==="
FAILED_REVISION="$(az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --query 'sort_by([].{name:name,created:properties.createdTime}, &created)[-1].name' \
    --output tsv)"

az containerapp revision show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --revision "${FAILED_REVISION}" \
    --output json \
    > "${EVIDENCE_DIR}/02-failed-revision-detail.json"

az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --output yaml \
    > "${EVIDENCE_DIR}/03-containerapp-spec.yaml"

az containerapp logs show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --type system \
    --tail 200 \
    > "${EVIDENCE_DIR}/04-system-logs.json"

az containerapp replica list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --query "[?contains(name, '${FAILED_REVISION}') ]" \
    --output json \
    > "${EVIDENCE_DIR}/05-replicas-failed.json"

az containerapp logs show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --tail 200 \
    > "${EVIDENCE_DIR}/06-console-logs.json"

WORKSPACE_ID="$(az monitor log-analytics workspace list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --query '[0].customerId' \
    --output tsv)"

KQL_PROBE="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where RevisionName_s == '${FAILED_REVISION}' | where Reason_s == 'ProbeFailed' | order by TimeGenerated desc"
KQL_CORR="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where RevisionName_s == '${FAILED_REVISION}' | where Reason_s in ('ContainerCreated','ContainerStarted','ProbeFailed','ContainerTerminated') | order by TimeGenerated desc"
KQL_REASON="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | summarize EventCount=count() by RevisionName_s, Reason_s, Type_s | order by toint(EventCount) desc"
KQL_CONSOLE="ContainerAppConsoleLogs_CL | where ContainerName_s == 'app' | where RevisionName_s == '${FAILED_REVISION}' | order by TimeGenerated desc"

az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${KQL_PROBE}" \
    --output json \
    > "${EVIDENCE_DIR}/07-kql-probefailed-rows.json"

az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${KQL_CORR}" \
    --output json \
    > "${EVIDENCE_DIR}/08-kql-event-correlation.json"

az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${KQL_REASON}" \
    --output json \
    > "${EVIDENCE_DIR}/09-kql-summary-by-reason.json"

az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${KQL_CONSOLE}" \
    --output json \
    > "${EVIDENCE_DIR}/10-kql-console-logs.json"
echo

echo "=== Phase 6: apply H2 fix with path=/ ==="
FIX_PATCH="$(mktemp -t revprov-fix-XXXXXX.yaml)"
cat > "${FIX_PATCH}" <<'EOF'
properties:
  template:
    revisionSuffix: badpath3
    containers:
      - name: app
        image: nginx:alpine
        resources:
          cpu: 0.5
          memory: 1Gi
        probes:
          - type: Startup
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
            timeoutSeconds: 2
EOF

az containerapp update \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --yaml "${FIX_PATCH}" \
    --output none
sleep 60
echo

echo "=== Phase 7: capture H2 evidence ==="
az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${KQL_REASON}" \
    --output json \
    > "${EVIDENCE_DIR}/11-kql-postfix-verification.json"

az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${APP_NAME}" \
    --query "[?name=='ca-labrevprov-e2upm2--badpath3']" \
    --output json \
    > "${EVIDENCE_DIR}/12-revision-list-recovered.json"

echo "=== Phase 8: run offline verifier ==="
bash "${SCRIPT_DIR}/verify.sh"

echo
echo "Live capture complete. Raw evidence written to ${EVIDENCE_DIR}."
echo "Optional cleanup command: az group delete --subscription \"${AZ_SUBSCRIPTION}\" --name \"${RG}\" --yes --no-wait"
