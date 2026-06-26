#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:-$(az account show --query 'id' --output tsv)}"
RG="${RG:-rg-aca-lab-kv}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-labkv}"

echo "fix-and-capture.sh starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "Resource group: ${RG}"
echo "Location: ${LOCATION}"
echo

rm -f "${EVIDENCE_DIR}/"{01,02,03,04,05,06,07,08,09,10,11,12,14,15,16,17}-* || true

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
DEPLOYMENT_RESULT_FILE="$(mktemp -t managed-identity-kv-deployment-XXXXXX.json)"
PRE_BODY_FILE="$(mktemp -t managed-identity-kv-pre-body-XXXXXX.txt)"
PRE_HEADERS_FILE="$(mktemp -t managed-identity-kv-pre-headers-XXXXXX.txt)"
POST_BODY_FILE="$(mktemp -t managed-identity-kv-post-body-XXXXXX.txt)"
POST_HEADERS_FILE="$(mktemp -t managed-identity-kv-post-headers-XXXXXX.txt)"
trap 'rm -f "${DEPLOYMENT_RESULT_FILE}" "${PRE_BODY_FILE}" "${PRE_HEADERS_FILE}" "${POST_BODY_FILE}" "${POST_HEADERS_FILE}"' EXIT

az deployment group create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-kv \
    --template-file "${SCRIPT_DIR}/infra/main.bicep" \
    --parameters baseName="${BASE_NAME}" location="${LOCATION}" \
    --output json \
    > "${DEPLOYMENT_RESULT_FILE}"
echo "Deployment result captured to ${DEPLOYMENT_RESULT_FILE} (kept outside evidence/ so Gate 14 sees no unexpected extras)"

APP_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-kv \
    --query 'properties.outputs.containerAppName.value' \
    --output tsv)"
ACR_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-kv \
    --query 'properties.outputs.containerRegistryName.value' \
    --output tsv)"
KV_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-kv \
    --query 'properties.outputs.keyVaultName.value' \
    --output tsv)"
WORKSPACE_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-kv \
    --query 'properties.outputs.logAnalyticsWorkspaceName.value' \
    --output tsv)"
WORKSPACE_ID="$(az monitor log-analytics workspace show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --workspace-name "${WORKSPACE_NAME}" \
    --query 'customerId' \
    --output tsv)"

echo
echo "=== Phase 3: build and push workload image ==="
az acr build \
    --subscription "${AZ_SUBSCRIPTION}" \
    --registry "${ACR_NAME}" \
    --image "${APP_NAME}:v1" \
    "${SCRIPT_DIR}/workload"

echo
echo "=== Phase 4: trigger H1 with missing Key Vault RBAC ==="
ACR_LOGIN_SERVER="$(az acr show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${ACR_NAME}" \
    --resource-group "${RG}" \
    --query 'loginServer' \
    --output tsv)"
ACR_USERNAME="$(az acr credential show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${ACR_NAME}" \
    --query 'username' \
    --output tsv)"
ACR_PASSWORD="$(az acr credential show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${ACR_NAME}" \
    --query 'passwords[0].value' \
    --output tsv)"

PRINCIPAL_ID="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'identity.principalId' \
    --output tsv)"
KV_ID="$(az keyvault show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${KV_NAME}" \
    --resource-group "${RG}" \
    --query 'id' \
    --output tsv)"

while IFS= read -r role_id; do
    if [ -n "${role_id}" ]; then
        az role assignment delete --subscription "${AZ_SUBSCRIPTION}" --ids "${role_id}" --output none
    fi
done < <(
    az role assignment list \
        --subscription "${AZ_SUBSCRIPTION}" \
        --assignee "${PRINCIPAL_ID}" \
        --scope "${KV_ID}" \
        --query "[?roleDefinitionName=='Key Vault Secrets User'].id" \
        --output tsv
)

az containerapp registry set \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --server "${ACR_LOGIN_SERVER}" \
    --username "${ACR_USERNAME}" \
    --password "${ACR_PASSWORD}" \
    --output none

az containerapp update \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --image "${ACR_LOGIN_SERVER}/${APP_NAME}:v1" \
    --output none

sleep 90
FQDN="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.configuration.ingress.fqdn' \
    --output tsv)"
PRE_REVISION="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.latestReadyRevisionName' \
    --output tsv)"

PRE_HTTP_CODE="$(curl --silent --show-error --output "${PRE_BODY_FILE}" --dump-header "${PRE_HEADERS_FILE}" --write-out '%{http_code}' "https://${FQDN}/health" || true)"

echo
echo "=== Phase 5: capture H1 raw evidence ==="
az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'identity' \
    --output json \
    > "${EVIDENCE_DIR}/01-app-identity-pre-fix.json"

az role assignment list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --assignee "${PRINCIPAL_ID}" \
    --output json \
    > "${EVIDENCE_DIR}/02-role-assignments-pre-fix.json"

az keyvault show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${KV_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.{enableRbacAuthorization:enableRbacAuthorization,publicNetworkAccess:publicNetworkAccess,uri:vaultUri}' \
    --output json \
    > "${EVIDENCE_DIR}/03-kv-rbac-config.json"

az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query "[?name=='${PRE_REVISION}']" \
    --output json \
    > "${EVIDENCE_DIR}/04-revision-list-pre-fix.json"

export PRE_BODY_FILE PRE_HEADERS_FILE PRE_HTTP_CODE FQDN EVIDENCE_DIR
python3 <<'PY'
import json
import os
from pathlib import Path

body = Path(os.environ["PRE_BODY_FILE"]).read_text(encoding="utf-8")
headers = Path(os.environ["PRE_HEADERS_FILE"]).read_text(encoding="utf-8").splitlines()
payload = {
    "request_url": f"https://{os.environ['FQDN']}/health",
    "status_code": int(os.environ["PRE_HTTP_CODE"]),
    "headers": headers,
    "body": body,
}
Path(os.environ["EVIDENCE_DIR"]).joinpath("05-http-response-pre-fix.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

az containerapp logs show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --type system \
    --tail 50 \
    > "${EVIDENCE_DIR}/06-system-logs-pre-fix.json"

az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output yaml \
    > "${EVIDENCE_DIR}/07-containerapp-spec-pre-fix.yaml"

az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "ContainerAppConsoleLogs_CL | where ContainerName_s == 'app' | where RevisionName_s startswith '${APP_NAME}--' | order by TimeGenerated desc | take 50" \
    --output json \
    > "${EVIDENCE_DIR}/08-kql-console-logs-pre-fix.json"

echo
echo "=== Phase 6: apply H2 fix ==="
az role assignment create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --assignee-object-id "${PRINCIPAL_ID}" \
    --assignee-principal-type ServicePrincipal \
    --role "Key Vault Secrets User" \
    --scope "${KV_ID}" \
    --output none
sleep 60

az containerapp update \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --set-env-vars "RESTART_TOKEN=$(date +%s)" \
    --output none
sleep 90
POST_REVISION="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.latestReadyRevisionName' \
    --output tsv)"

POST_HTTP_CODE="$(curl --silent --show-error --output "${POST_BODY_FILE}" --dump-header "${POST_HEADERS_FILE}" --write-out '%{http_code}' "https://${FQDN}/health" || true)"

echo
echo "=== Phase 7: capture H2 raw evidence ==="
az role assignment list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --assignee "${PRINCIPAL_ID}" \
    --scope "${KV_ID}" \
    --output json \
    > "${EVIDENCE_DIR}/09-role-assignment-post-fix.json"

export POST_BODY_FILE POST_HEADERS_FILE POST_HTTP_CODE
python3 <<'PY'
import json
import os
from pathlib import Path

body = Path(os.environ["POST_BODY_FILE"]).read_text(encoding="utf-8")
headers = Path(os.environ["POST_HEADERS_FILE"]).read_text(encoding="utf-8").splitlines()
payload = {
    "request_url": f"https://{os.environ['FQDN']}/health",
    "status_code": int(os.environ["POST_HTTP_CODE"]),
    "headers": headers,
    "body": body,
}
Path(os.environ["EVIDENCE_DIR"]).joinpath("10-http-response-post-fix.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query "[?name=='${POST_REVISION}']" \
    --output json \
    > "${EVIDENCE_DIR}/11-revision-list-post-fix.json"

az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | summarize EventCount=count() by RevisionName_s, Reason_s | order by RevisionName_s asc, Reason_s asc" \
    --output json \
    > "${EVIDENCE_DIR}/12-kql-recovery-summary-post-fix.json"

echo
echo "=== Phase 8: sanitize captures and run offline verifier ==="
export EVIDENCE_DIR PRE_BODY_FILE PRE_HEADERS_FILE POST_BODY_FILE POST_HEADERS_FILE PRE_HTTP_CODE POST_HTTP_CODE FQDN
python3 <<'PY'
import re
from pathlib import Path

base = Path(__import__('os').environ['EVIDENCE_DIR'])
subs = [
    (re.compile(r'(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])', re.I), '00000000-0000-0000-0000-000000000000'),
    (re.compile(r'\bMCAPS[-A-Za-z0-9_]*\b'), 'Visual Studio Enterprise Subscription'),
    (re.compile(r'Microsoft\s+Non-Production', re.I), 'Contoso'),
    (re.compile(r'\b[A-Za-z0-9._%+-]+@microsoft\.com(?![A-Za-z0-9.-])', re.I), 'user@example.com'),
    (re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.onmicrosoft\.com(?![A-Za-z0-9.-])', re.I), 'user@example.com'),
    (re.compile(r'\b[A-Za-z0-9._%+-]+@gmail\.com(?![A-Za-z0-9.-])', re.I), 'user@example.com'),
    (re.compile(r'\b[A-Za-z0-9-]+\.onmicrosoft\.com(?![A-Za-z0-9.-])', re.I), 'contoso.onmicrosoft.com'),
    (re.compile(r'\bychoe\b', re.I), 'demouser'),
    (re.compile(r'Yeongseon\s+Choe', re.I), 'Demo User'),
    (re.compile(r'\byeongseon\b', re.I), 'demouser'),
    (re.compile(r'\b[0-9A-F]{32,}\b'), 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
]
for path in sorted(base.glob('*')):
    if path.is_file():
        text = path.read_text(encoding='utf-8')
        for regex, repl in subs:
            text = regex.sub(repl, text)
        path.write_text(text, encoding='utf-8')
PY

bash "${SCRIPT_DIR}/verify.sh"

echo
echo "=== Phase 9: cleanup Azure resources ==="
az group delete --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --yes --no-wait
echo "Cleanup initiated. Evidence written to ${EVIDENCE_DIR}."
