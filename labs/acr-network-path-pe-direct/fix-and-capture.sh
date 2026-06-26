#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:-$(az account show --query 'id' --output tsv)}"
RG="${RG:-rg-acr-pe-direct-lab}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-acrpedir}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-pe-direct}"

export AZ_SUBSCRIPTION RG LOCATION BASE_NAME DEPLOYMENT_NAME

echo "fix-and-capture.sh starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "Resource group: ${RG}"
echo "Location: ${LOCATION}"
echo

rm -f "${EVIDENCE_DIR}/"{01,02,03,04,05,06,07,08,09,10,11,12,14,15,16,17}-*

SCRATCH_DIR="$(mktemp -d -t acr-pe-direct-phaseb-XXXXXX)"
trap 'rm -rf "${SCRATCH_DIR}"' EXIT
export SCRATCH_DIR

sanitize_pii() {
    python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

base = Path(sys.argv[1])
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
}

wait_for_revision_state() {
    local app_name="$1"
    local revision_name="$2"
    local expected_health="$3"
    local timeout_seconds="$4"
    local started_at
    started_at="$(date +%s)"
    while true; do
        local health_state running_state provisioning_state
        health_state="$(az containerapp revision list \
            --subscription "${AZ_SUBSCRIPTION}" \
            --name "${app_name}" \
            --resource-group "${RG}" \
            --query "[?name=='${revision_name}'] | [0].properties.healthState" \
            --output tsv 2>/dev/null)"
        running_state="$(az containerapp revision list \
            --subscription "${AZ_SUBSCRIPTION}" \
            --name "${app_name}" \
            --resource-group "${RG}" \
            --query "[?name=='${revision_name}'] | [0].properties.runningState" \
            --output tsv 2>/dev/null)"
        provisioning_state="$(az containerapp revision list \
            --subscription "${AZ_SUBSCRIPTION}" \
            --name "${app_name}" \
            --resource-group "${RG}" \
            --query "[?name=='${revision_name}'] | [0].properties.provisioningState" \
            --output tsv 2>/dev/null)"
        echo "wait_for_revision_state: ${revision_name} health=${health_state} running=${running_state} provisioning=${provisioning_state}"
        if [ "${health_state}" = "${expected_health}" ]; then
            return 0
        fi
        if [ $(( $(date +%s) - started_at )) -ge "${timeout_seconds}" ]; then
            return 1
        fi
        sleep 15
    done
}

wait_for_kql_rows() {
    local workspace_id="$1"
    local query="$2"
    local output_file="$3"
    local timeout_seconds="$4"
    local started_at
    started_at="$(date +%s)"
    while true; do
        az monitor log-analytics query \
            --subscription "${AZ_SUBSCRIPTION}" \
            --workspace "${workspace_id}" \
            --analytics-query "${query}" \
            --output json \
            > "${output_file}"
        if python3 - "$output_file" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
rows = payload if isinstance(payload, list) else payload.get('tables', [{}])[0].get('rows', payload.get('rows', []))
raise SystemExit(0 if rows else 1)
PY
        then
            return 0
        fi
        if [ $(( $(date +%s) - started_at )) -ge "${timeout_seconds}" ]; then
            return 1
        fi
        sleep 20
    done
}

build_image_tag() {
    local acr_name="$1"
    local image_repo="$2"
    local image_tag="$3"
    local previous_public
    previous_public="$(az acr show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --name "${acr_name}" \
        --resource-group "${RG}" \
        --query 'publicNetworkAccess' \
        --output tsv)"
    if [ "${previous_public}" = "Disabled" ]; then
        az acr update \
            --subscription "${AZ_SUBSCRIPTION}" \
            --name "${acr_name}" \
            --resource-group "${RG}" \
            --public-network-enabled true \
            --default-action Allow \
            --output none
        sleep 60
    fi
    az acr build \
        --subscription "${AZ_SUBSCRIPTION}" \
        --registry "${acr_name}" \
        --image "${image_repo}:${image_tag}" \
        --file "${SCRIPT_DIR}/workload/Dockerfile" \
        "${SCRIPT_DIR}/workload" \
        --output none
    if [ "${previous_public}" = "Disabled" ]; then
        az acr update \
            --subscription "${AZ_SUBSCRIPTION}" \
            --name "${acr_name}" \
            --resource-group "${RG}" \
            --public-network-enabled false \
            --output none
        sleep 30
    fi
}

echo "=== Phase 1: ensure resource group exists ==="
if ! az group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${RG}" \
    --output none >/dev/null 2>&1; then
    az group create \
        --subscription "${AZ_SUBSCRIPTION}" \
        --name "${RG}" \
        --location "${LOCATION}" \
        --output json
fi

echo
echo "=== Phase 2: deploy baseline infra ==="
az deployment group create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --template-file "${SCRIPT_DIR}/infra/main.bicep" \
    --parameters baseName="${BASE_NAME}" location="${LOCATION}" \
    --output json \
    > "${SCRATCH_DIR}/deployment.json"

APP_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --query 'properties.outputs.containerAppName.value' \
    --output tsv)"
ACR_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --query 'properties.outputs.containerRegistryName.value' \
    --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --query 'properties.outputs.containerRegistryLoginServer.value' \
    --output tsv)"
WORKSPACE_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --query 'properties.outputs.logAnalyticsWorkspaceName.value' \
    --output tsv)"
PE_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --query 'properties.outputs.privateEndpointName.value' \
    --output tsv)"
VNET_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --query 'properties.outputs.vnetName.value' \
    --output tsv)"
ZONE_NAME="$(az deployment group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --query 'properties.outputs.privateDnsZoneName.value' \
    --output tsv)"
WORKSPACE_ID="$(az monitor log-analytics workspace show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --workspace-name "${WORKSPACE_NAME}" \
    --query 'customerId' \
    --output tsv)"
VNET_ID="$(az network vnet show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${VNET_NAME}" \
    --query 'id' \
    --output tsv)"
NIC_ID="$(az network private-endpoint show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${PE_NAME}" \
    --resource-group "${RG}" \
    --query 'networkInterfaces[0].id' \
    --output tsv)"
FQDN="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.configuration.ingress.fqdn' \
    --output tsv)"
LINK_NAME="${VNET_NAME}-link"
IMAGE_REPO="pe-lab"

echo
echo "=== Phase 3: baseline private-path trigger ==="
bash "${SCRIPT_DIR}/trigger.sh"
sleep 90
BASELINE_REVISION="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.latestReadyRevisionName' \
    --output tsv)"
wait_for_revision_state "${APP_NAME}" "${BASELINE_REVISION}" "Healthy" 600

echo
echo "=== Phase 4: H1 trigger (remove link, build v-broken, force fresh pull) ==="
az network private-dns link vnet delete \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --zone-name "${ZONE_NAME}" \
    --name "${LINK_NAME}" \
    --yes \
    --output none

build_image_tag "${ACR_NAME}" "${IMAGE_REPO}" "v-broken"

az containerapp update \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --image "${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-broken" \
    --set-env-vars "BUILD_TAG=v-broken" \
    --output none

sleep 45
BROKEN_REVISION="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.latestRevisionName' \
    --output tsv)"
az containerapp revision restart \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${BROKEN_REVISION}" \
    --resource-group "${RG}" \
    --output none

PRE_WINDOW_START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sleep 120

echo
echo "=== Phase 5: capture H1 evidence ==="
export EVIDENCE_DIR APP_NAME ACR_LOGIN_SERVER VNET_ID ZONE_NAME DEPLOYMENT_NAME RG PRE_WINDOW_START_UTC

az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output json \
    > "${SCRATCH_DIR}/app-pre.json"

python3 - <<'PY'
import json
import os
from pathlib import Path

container_app = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/app-pre.json").read_text(encoding='utf-8'))
payload = {
    "capture_metadata": {
        "acr_login_server": os.environ['ACR_LOGIN_SERVER'],
        "vnet_id": os.environ['VNET_ID'],
        "zone_name": os.environ['ZONE_NAME'],
        "pre_window_start_utc": os.environ['PRE_WINDOW_START_UTC'],
    },
    "container_app": container_app,
}
Path(os.environ['EVIDENCE_DIR']).joinpath('01-app-spec-pre-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output json \
    > "${EVIDENCE_DIR}/02-revision-list-pre-fix.json"

az network private-dns link vnet list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --zone-name "${ZONE_NAME}" \
    --output json \
    > "${EVIDENCE_DIR}/03-private-dns-link-list-pre-fix.json"

az network nic show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --ids "${NIC_ID}" \
    --output json \
    > "${EVIDENCE_DIR}/04-pe-nic-config-pre-fix.json"

az acr show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${ACR_NAME}" \
    --resource-group "${RG}" \
    --query '{publicNetworkAccess:publicNetworkAccess,networkRuleSet:networkRuleSet}' \
    --output json \
    > "${EVIDENCE_DIR}/05-acr-public-access-pre-fix.json"

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

PRE_KQL_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where TimeGenerated >= todatetime('${PRE_WINDOW_START_UTC}') | where Reason_s in ('PullingImage','ImagePullUnauthorized','ImagePullFailed','BackOff','PulledImage') | order by TimeGenerated asc | project TimeGenerated, RevisionName_s, ReplicaName_s, Reason_s, Log_s"
wait_for_kql_rows "${WORKSPACE_ID}" "${PRE_KQL_QUERY}" "${SCRATCH_DIR}/pre-kql.json" 900
export PRE_KQL_QUERY
python3 - <<'PY'
import json
import os
from pathlib import Path

raw = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/pre-kql.json").read_text(encoding='utf-8'))
rows = raw if isinstance(raw, list) else raw.get('tables', [{}])[0].get('rows', raw.get('rows', []))
columns = raw.get('tables', [{}])[0].get('columns', []) if isinstance(raw, dict) else []
normalized = []
if columns and rows and isinstance(rows[0], list):
    names = [col['name'] for col in columns]
    for row in rows:
        normalized.append(dict(zip(names, row)))
else:
    normalized = rows
payload = {
    "query": os.environ['PRE_KQL_QUERY'],
    "window_start_utc": os.environ['PRE_WINDOW_START_UTC'],
    "window_end_utc": normalized[-1]['TimeGenerated'] if normalized else os.environ['PRE_WINDOW_START_UTC'],
    "rows": normalized,
}
Path(os.environ['EVIDENCE_DIR']).joinpath('08-kql-imagepull-events-pre-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

echo
echo "=== Phase 6: H2 restore (recreate link, build v-recover, deploy) ==="
az network private-dns link vnet create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --zone-name "${ZONE_NAME}" \
    --name "${LINK_NAME}" \
    --virtual-network "${VNET_ID}" \
    --registration-enabled false \
    --output none

build_image_tag "${ACR_NAME}" "${IMAGE_REPO}" "v-recover"

az containerapp update \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --image "${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-recover" \
    --set-env-vars "BUILD_TAG=v-recover" \
    --output none

POST_WINDOW_START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sleep 90
POST_REVISION="$(az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --query 'properties.latestRevisionName' \
    --output tsv)"
wait_for_revision_state "${APP_NAME}" "${POST_REVISION}" "Healthy" 900

echo
echo "=== Phase 7: capture H2 evidence ==="
az network private-dns link vnet list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --zone-name "${ZONE_NAME}" \
    --output json \
    > "${EVIDENCE_DIR}/09-private-dns-link-list-post-fix.json"

az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output json \
    > "${EVIDENCE_DIR}/10-revision-list-post-fix.json"

az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output json \
    > "${SCRATCH_DIR}/app-post.json"
az acr show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${ACR_NAME}" \
    --resource-group "${RG}" \
    --query '{publicNetworkAccess:publicNetworkAccess,networkRuleSet:networkRuleSet}' \
    --output json \
    > "${SCRATCH_DIR}/acr-post.json"
az network nic show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --ids "${NIC_ID}" \
    --output json \
    > "${SCRATCH_DIR}/nic-post.json"

export POST_WINDOW_START_UTC
python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "capture_metadata": {
        "acr_login_server": os.environ['ACR_LOGIN_SERVER'],
        "vnet_id": os.environ['VNET_ID'],
        "zone_name": os.environ['ZONE_NAME'],
        "post_window_start_utc": os.environ['POST_WINDOW_START_UTC'],
    },
    "container_app": json.loads(Path(f"{os.environ['SCRATCH_DIR']}/app-post.json").read_text(encoding='utf-8')),
    "acr": json.loads(Path(f"{os.environ['SCRATCH_DIR']}/acr-post.json").read_text(encoding='utf-8')),
    "pe_nic": json.loads(Path(f"{os.environ['SCRATCH_DIR']}/nic-post.json").read_text(encoding='utf-8')),
}
Path(os.environ['EVIDENCE_DIR']).joinpath('11-app-spec-post-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

POST_KQL_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where TimeGenerated >= todatetime('${POST_WINDOW_START_UTC}') | where Reason_s in ('PullingImage','PulledImage','ImagePullUnauthorized','ImagePullFailed','BackOff') | order by TimeGenerated asc | project TimeGenerated, RevisionName_s, ReplicaName_s, Reason_s, Log_s"
wait_for_kql_rows "${WORKSPACE_ID}" "${POST_KQL_QUERY}" "${SCRATCH_DIR}/post-kql.json" 900
export POST_KQL_QUERY
python3 - <<'PY'
import json
import os
from pathlib import Path

raw = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/post-kql.json").read_text(encoding='utf-8'))
rows = raw if isinstance(raw, list) else raw.get('tables', [{}])[0].get('rows', raw.get('rows', []))
columns = raw.get('tables', [{}])[0].get('columns', []) if isinstance(raw, dict) else []
normalized = []
if columns and rows and isinstance(rows[0], list):
    names = [col['name'] for col in columns]
    for row in rows:
        normalized.append(dict(zip(names, row)))
else:
    normalized = rows
payload = {
    "query": os.environ['POST_KQL_QUERY'],
    "window_start_utc": os.environ['POST_WINDOW_START_UTC'],
    "window_end_utc": normalized[-1]['TimeGenerated'] if normalized else os.environ['POST_WINDOW_START_UTC'],
    "rows": normalized,
}
Path(os.environ['EVIDENCE_DIR']).joinpath('12-kql-imagepull-events-post-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

echo
echo "=== Phase 8: sanitize captures and run offline verifier ==="
export SCRATCH_DIR
sanitize_pii "${EVIDENCE_DIR}"
bash "${SCRIPT_DIR}/verify.sh"

echo
echo "=== Phase 9: cleanup Azure resources ==="
az group delete \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${RG}" \
    --yes \
    --no-wait
echo "Cleanup initiated. Evidence written to ${EVIDENCE_DIR}."
