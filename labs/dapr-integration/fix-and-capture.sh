#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:-$(az account show --query 'id' --output tsv)}"
RG="${RG:-rg-aca-lab-dapr}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-labdapr}"

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

INFRA_DEPLOYMENT_FILE="$(mktemp -t dapr-integration-infra-XXXXXX.json)"
APP_DEPLOYMENT_FILE="$(mktemp -t dapr-integration-app-XXXXXX.json)"
PRE_BODY_FILE="$(mktemp -t dapr-integration-pre-body-XXXXXX.txt)"
PRE_HEADERS_FILE="$(mktemp -t dapr-integration-pre-headers-XXXXXX.txt)"
POST_BODY_FILE="$(mktemp -t dapr-integration-post-body-XXXXXX.txt)"
POST_HEADERS_FILE="$(mktemp -t dapr-integration-post-headers-XXXXXX.txt)"
EXEC_PRE_STDOUT_FILE="$(mktemp -t dapr-integration-exec-pre-out-XXXXXX.txt)"
EXEC_PRE_STDERR_FILE="$(mktemp -t dapr-integration-exec-pre-err-XXXXXX.txt)"
trap 'rm -f "${INFRA_DEPLOYMENT_FILE}" "${APP_DEPLOYMENT_FILE}" "${PRE_BODY_FILE}" "${PRE_HEADERS_FILE}" "${POST_BODY_FILE}" "${POST_HEADERS_FILE}" "${EXEC_PRE_STDOUT_FILE}" "${EXEC_PRE_STDERR_FILE}"' EXIT

echo "=== Phase 2: deploy shared infra (ACR + Log Analytics + ACA environment) ==="
az deployment group create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-dapr-infra \
    --template-file "${SCRIPT_DIR}/infra/main.bicep" \
    --parameters baseName="${BASE_NAME}" location="${LOCATION}" containerImage='' \
    --output json \
    > "${INFRA_DEPLOYMENT_FILE}"

APP_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-dapr-infra \
    --query 'properties.outputs.containerAppName.value' \
    --output tsv)"
ACR_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-dapr-infra \
    --query 'properties.outputs.containerRegistryName.value' \
    --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-dapr-infra \
    --query 'properties.outputs.containerRegistryLoginServer.value' \
    --output tsv)"
ACA_ENV_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-dapr-infra \
    --query 'properties.outputs.containerAppsEnvironmentName.value' \
    --output tsv)"
WORKSPACE_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-dapr-infra \
    --query 'properties.outputs.logAnalyticsWorkspaceName.value' \
    --output tsv)"
DAPR_APP_ID="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-dapr-infra \
    --query 'properties.outputs.daprAppId.value' \
    --output tsv)"
WORKSPACE_ID="$(az monitor log-analytics workspace show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --workspace-name "${WORKSPACE_NAME}" \
    --query 'customerId' \
    --output tsv)"

echo
echo "=== Phase 3: build and push the Flask-on-8000 workload ==="
az acr build \
    --subscription "${AZ_SUBSCRIPTION}" \
    --registry "${ACR_NAME}" \
    --image "${APP_NAME}:v1" \
    "${SCRIPT_DIR}/workload"

IMAGE_REF="${ACR_LOGIN_SERVER}/${APP_NAME}:v1"

echo
echo "=== Phase 4: deploy the container app using the ACR image ==="
az deployment group create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name lab-dapr-app \
    --template-file "${SCRIPT_DIR}/infra/main.bicep" \
    --parameters baseName="${BASE_NAME}" location="${LOCATION}" containerImage="${IMAGE_REF}" \
    --output json \
    > "${APP_DEPLOYMENT_FILE}"

sleep 90
FQDN="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.configuration.ingress.fqdn' \
    --output tsv)"
BASELINE_REVISION="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.latestReadyRevisionName' \
    --output tsv)"

echo
echo "=== Phase 5: apply H1 trigger via CLI 2.71.0-safe command ==="
az containerapp dapr enable \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --dapr-app-id "${DAPR_APP_ID}" \
    --dapr-app-port 8081 \
    --dapr-app-protocol http \
    --output none

sleep 90
PRE_REVISION="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.latestReadyRevisionName' \
    --output tsv)"
PRE_HTTP_CODE="$(curl --silent --show-error --output "${PRE_BODY_FILE}" --dump-header "${PRE_HEADERS_FILE}" --write-out '%{http_code}' "https://${FQDN}/" || true)"

set +e
script -q /dev/null az containerapp exec \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --command "curl --silent --show-error --fail http://127.0.0.1:3500/v1.0/invoke/${DAPR_APP_ID}/method/" \
    > "${EXEC_PRE_STDOUT_FILE}" 2> "${EXEC_PRE_STDERR_FILE}"
EXEC_PRE_EXIT_CODE="$?"
set -e

echo
echo "=== Phase 6: capture H1 raw evidence ==="
az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query '{name:name,resourceGroup:resourceGroup,location:location,properties:{latestRevisionName:properties.latestRevisionName,latestReadyRevisionName:properties.latestReadyRevisionName,configuration:{ingress:properties.configuration.ingress,dapr:properties.configuration.dapr}}}' \
    --output json \
    > "${EVIDENCE_DIR}/01-app-spec-pre-fix.json"

az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query "[?name=='${PRE_REVISION}']" \
    --output json \
    > "${EVIDENCE_DIR}/02-revision-list-pre-fix.json"

az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.configuration.dapr' \
    --output json \
    > "${EVIDENCE_DIR}/03-dapr-config-pre-fix.json"

export PRE_BODY_FILE PRE_HEADERS_FILE PRE_HTTP_CODE FQDN EVIDENCE_DIR
python3 <<'PY'
import json
import os
from pathlib import Path

payload = {
    "request_url": f"https://{os.environ['FQDN']}/",
    "status_code": int(os.environ["PRE_HTTP_CODE"]),
    "headers": Path(os.environ["PRE_HEADERS_FILE"]).read_text(encoding="utf-8").splitlines(),
    "body": Path(os.environ["PRE_BODY_FILE"]).read_text(encoding="utf-8"),
}
Path(os.environ["EVIDENCE_DIR"]).joinpath("04-http-response-pre-fix.json").write_text(
    json.dumps(payload, indent=2) + "\n",
    encoding="utf-8",
)
PY

export EXEC_PRE_STDOUT_FILE EXEC_PRE_STDERR_FILE EXEC_PRE_EXIT_CODE APP_NAME DAPR_APP_ID
python3 <<'PY'
import json
import os
from pathlib import Path

payload = {
    "command": f"curl --silent --show-error --fail http://127.0.0.1:3500/v1.0/invoke/{os.environ['DAPR_APP_ID']}/method/",
    "exit_code": int(os.environ["EXEC_PRE_EXIT_CODE"]),
    "stdout": Path(os.environ["EXEC_PRE_STDOUT_FILE"]).read_text(encoding="utf-8"),
    "stderr": Path(os.environ["EXEC_PRE_STDERR_FILE"]).read_text(encoding="utf-8"),
}
    
Path(os.environ["EVIDENCE_DIR"]).joinpath("05-dapr-invoke-pre-fix.json").write_text(
    json.dumps(payload, indent=2) + "\n",
    encoding="utf-8",
)
PY

az containerapp logs show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --type system \
    --tail 100 \
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
    --analytics-query "union isfuzzy=true (ContainerAppConsoleLogs_CL | where ContainerAppName_s == '${APP_NAME}' | project Table='Console', TimeGenerated, RevisionName_s, ContainerName_s, Message=tostring(Log_s)), (ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | project Table='System', TimeGenerated, RevisionName_s, ContainerName_s='', Message=coalesce(tostring(Log_s), tostring(Reason_s))) | order by TimeGenerated desc | take 50" \
    --output json \
    > "${EVIDENCE_DIR}/08-kql-console-logs-pre-fix.json"

echo
echo "=== Phase 7: apply H2 fix via CLI 2.71.0-safe command ==="
RESTORE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az containerapp dapr enable \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --dapr-app-id "${DAPR_APP_ID}" \
    --dapr-app-port 8000 \
    --dapr-app-protocol http \
    --output none

sleep 90
POST_REVISION="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.latestReadyRevisionName' \
    --output tsv)"
POST_HTTP_CODE="$(curl --silent --show-error --output "${POST_BODY_FILE}" --dump-header "${POST_HEADERS_FILE}" --write-out '%{http_code}' "https://${FQDN}/" || true)"

echo
echo "=== Phase 8: capture H2 raw evidence ==="
az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.configuration.dapr' \
    --output json \
    > "${EVIDENCE_DIR}/09-dapr-config-post-fix.json"

export POST_BODY_FILE POST_HEADERS_FILE POST_HTTP_CODE
python3 <<'PY'
import json
import os
from pathlib import Path

payload = {
    "request_url": f"https://{os.environ['FQDN']}/",
    "status_code": int(os.environ["POST_HTTP_CODE"]),
    "headers": Path(os.environ["POST_HEADERS_FILE"]).read_text(encoding="utf-8").splitlines(),
    "body": Path(os.environ["POST_BODY_FILE"]).read_text(encoding="utf-8"),
}
Path(os.environ["EVIDENCE_DIR"]).joinpath("10-http-response-post-fix.json").write_text(
    json.dumps(payload, indent=2) + "\n",
    encoding="utf-8",
)
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
    --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where TimeGenerated >= todatetime('${RESTORE_UTC}') | summarize EventCount=count() by RevisionName_s, Reason_s | order by RevisionName_s asc, Reason_s asc" \
    --output json \
    > "${EVIDENCE_DIR}/12-kql-recovery-summary-post-fix.json"

echo
echo "=== Phase 9: sanitize captures and run offline verifier ==="
export EVIDENCE_DIR
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
    (re.compile(r'https://ms\.portal\.azure\.com[^\s"\']*', re.I), 'https://ms.portal.azure.com/#@contoso.onmicrosoft.com/'),
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
echo "=== Phase 10: cleanup Azure resources ==="
az group delete --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --yes --no-wait
echo "Cleanup initiated. Evidence written to ${EVIDENCE_DIR}."
