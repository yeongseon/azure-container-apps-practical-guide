#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

RG="${1:-${RG:-rg-aca-firewall-allowlist-lab33-$(date -u +%Y%m%d%H%M)}}"
LOCATION="${2:-${LOCATION:-koreacentral}}"
LAB_NAME="${3:-${LAB_NAME:-acr-network-path-firewall-allowlist}}"
BASE_NAME="${BASE_NAME:-acrfw33}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-firewall-allowlist}"
IMAGE_REPO="${IMAGE_REPO:-firewall-allowlist-lab}"
AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:-$(az account show --query 'id' --output tsv)}"

export RG LOCATION LAB_NAME BASE_NAME DEPLOYMENT_NAME IMAGE_REPO AZ_SUBSCRIPTION EVIDENCE_DIR

SCRATCH_DIR="$(mktemp -d -t acr-firewall-allowlist-phaseb-XXXXXX)"
trap 'rm -rf "${SCRATCH_DIR}"' EXIT
export SCRATCH_DIR

printf 'fix-and-capture.sh starting at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Subscription: %s\n' "${AZ_SUBSCRIPTION}"
printf 'Resource group: %s\n' "${RG}"
printf 'Location: %s\n' "${LOCATION}"
printf 'Lab: %s\n\n' "${LAB_NAME}"

rm -f "${EVIDENCE_DIR}/"{01,02,03,04,05,06,07,08,09,10,11,12,14,15,16,17}-*
rm -f "${EVIDENCE_DIR}/README.md"

cat <<'LIST'
Capture checklist (Phase B canonical order)
  01-app-spec-pre-fix.json
  02-revision-list-pre-fix.json
  03-acr-network-rules-pre-fix.json
  04-firewall-metadata-pre-fix.json
  05-baseline-success-window.json
  06-system-logs-pre-fix.json
  07-containerapp-spec-pre-fix.yaml
  08-h1-failure-window.json
  09-acr-network-rules-post-fix.json
  10-revision-list-post-fix.json
  11-app-spec-post-fix.json
  12-h2-recovery-window.json
LIST

discover_outputs() {
    APP_NAME="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.appName.value' \
        --output tsv)"
    ACR_NAME="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.registryName.value' \
        --output tsv)"
    ACR_LOGIN_SERVER="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.registryLoginServer.value' \
        --output tsv)"
    ACR_DATA_ENDPOINT="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.registryDataEndpoint.value' \
        --output tsv)"
    FIREWALL_NAME="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.firewallName.value' \
        --output tsv)"
    FIREWALL_POLICY_NAME="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.firewallPolicyName.value' \
        --output tsv)"
    FIREWALL_PUBLIC_IP_NAME="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.firewallPublicIpName.value' \
        --output tsv)"
    FIREWALL_PUBLIC_IP="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.firewallPublicIpAddress.value' \
        --output tsv)"
    VNET_NAME="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.vnetName.value' \
        --output tsv)"
    ACA_SUBNET_NAME="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.acaSubnetName.value' \
        --output tsv)"
    LAW_NAME="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.logAnalyticsName.value' \
        --output tsv)"
    LAW_CUSTOMER_ID="$(az deployment group show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DEPLOYMENT_NAME}" \
        --query 'properties.outputs.logAnalyticsCustomerId.value' \
        --output tsv)"
    APP_FQDN="$(az containerapp show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --name "${APP_NAME}" \
        --resource-group "${RG}" \
        --query 'properties.configuration.ingress.fqdn' \
        --output tsv)"
    VNET_ID="$(az network vnet show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${VNET_NAME}" \
        --query 'id' \
        --output tsv)"
    ACA_SUBNET_ID="$(az network vnet subnet show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --vnet-name "${VNET_NAME}" \
        --name "${ACA_SUBNET_NAME}" \
        --query 'id' \
        --output tsv)"
    FIREWALL_PRIVATE_IP="$(az network firewall show \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${FIREWALL_NAME}" \
        --query 'ipConfigurations[0].privateIPAddress' \
        --output tsv)"
    export APP_NAME ACR_NAME ACR_LOGIN_SERVER ACR_DATA_ENDPOINT FIREWALL_NAME FIREWALL_POLICY_NAME FIREWALL_PUBLIC_IP_NAME FIREWALL_PUBLIC_IP VNET_NAME VNET_ID ACA_SUBNET_ID LAW_NAME LAW_CUSTOMER_ID APP_FQDN FIREWALL_PRIVATE_IP
}

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

wait_for_revision_selector() {
    local image="$1"
    local timeout_seconds="$2"
    local started_at
    started_at="$(date +%s)"
    while true; do
        local revision
        revision="$(az containerapp revision list \
            --subscription "${AZ_SUBSCRIPTION}" \
            --name "${APP_NAME}" \
            --resource-group "${RG}" \
            --query "[?properties.template.containers[0].image=='${image}'] | sort_by(@, &properties.createdTime) | [-1].name" \
            --output tsv 2>/dev/null || true)"
        if [ -n "${revision}" ] && [ "${revision}" != "null" ]; then
            printf '%s' "${revision}"
            return 0
        fi
        if [ $(( $(date +%s) - started_at )) -ge "${timeout_seconds}" ]; then
            return 1
        fi
        sleep 10
    done
}

wait_for_revision_failed() {
    local revision="$1"
    local timeout_seconds="$2"
    local started_at
    started_at="$(date +%s)"
    while true; do
        local provision health running
        provision="$(az containerapp revision show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --revision "${revision}" --query 'properties.provisioningState' --output tsv 2>/dev/null || true)"
        health="$(az containerapp revision show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --revision "${revision}" --query 'properties.healthState' --output tsv 2>/dev/null || true)"
        running="$(az containerapp revision show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --revision "${revision}" --query 'properties.runningState' --output tsv 2>/dev/null || true)"
        printf 'wait_for_revision_failed: %s provisioning=%s health=%s running=%s\n' "${revision}" "${provision}" "${health}" "${running}"
        if [ "${provision}" = "Failed" ] || [ "${health}" = "Unhealthy" ] || [ "${running}" = "Failed" ] || [ "${running}" = "NotRunning" ]; then
            return 0
        fi
        if [ $(( $(date +%s) - started_at )) -ge "${timeout_seconds}" ]; then
            return 1
        fi
        sleep 15
    done
}

wait_for_revision_healthy() {
    local revision="$1"
    local timeout_seconds="$2"
    local started_at
    started_at="$(date +%s)"
    while true; do
        local health running provision
        health="$(az containerapp revision show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --revision "${revision}" --query 'properties.healthState' --output tsv 2>/dev/null || true)"
        running="$(az containerapp revision show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --revision "${revision}" --query 'properties.runningState' --output tsv 2>/dev/null || true)"
        provision="$(az containerapp revision show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --revision "${revision}" --query 'properties.provisioningState' --output tsv 2>/dev/null || true)"
        printf 'wait_for_revision_healthy: %s provisioning=%s health=%s running=%s\n' "${revision}" "${provision}" "${health}" "${running}"
        if [ "${health}" = "Healthy" ]; then
            return 0
        fi
        if [ $(( $(date +%s) - started_at )) -ge "${timeout_seconds}" ]; then
            return 1
        fi
        sleep 15
    done
}

query_to_json() {
    local query="$1"
    local output_file="$2"
    az monitor log-analytics query \
        --subscription "${AZ_SUBSCRIPTION}" \
        --workspace "${LAW_CUSTOMER_ID}" \
        --analytics-query "${query}" \
        --output json > "${output_file}"
}

normalize_query_json() {
    local input_file="$1"
    local output_file="$2"
    local query_text="$3"
    local start_utc="$4"
    python3 - "$input_file" "$output_file" "$query_text" "$start_utc" <<'PY'
import json
import sys
from pathlib import Path

raw = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
query_text = sys.argv[3]
start_utc = sys.argv[4]
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
    'query': query_text,
    'window_start_utc': start_utc,
    'window_end_utc': normalized[-1].get('TimeGenerated', start_utc) if normalized else start_utc,
    'row_count': len(normalized),
    'rows': normalized,
}
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY
}

wait_for_query_match() {
    local query="$1"
    local output_file="$2"
    local timeout_seconds="$3"
    local predicate_py="$4"
    local started_at
    started_at="$(date +%s)"
    while true; do
        query_to_json "${query}" "${output_file}"
        if python3 - "$output_file" "$predicate_py" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
rows = payload if isinstance(payload, list) else payload.get('tables', [{}])[0].get('rows', payload.get('rows', []))
ns = {'rows': rows, 'json': json}
raise SystemExit(0 if eval(sys.argv[2], ns, {}) else 1)
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

capture_http_response() {
    local output_file="$1"
    local expected_tag="$2"
    local timeout_seconds="$3"
    local started_at
    started_at="$(date +%s)"
    while true; do
        if curl -sS --max-time 30 -D "${SCRATCH_DIR}/headers.txt" "https://${APP_FQDN}/" > "${SCRATCH_DIR}/body.txt"; then
            if python3 - "${SCRATCH_DIR}/body.txt" "$expected_tag" <<'PY'
import json
import sys
from pathlib import Path
try:
    payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if payload.get('build_tag') == sys.argv[2] else 1)
PY
            then
                python3 - "$output_file" "${SCRATCH_DIR}/headers.txt" "${SCRATCH_DIR}/body.txt" "${APP_FQDN}" <<'PY'
import json
import sys
from pathlib import Path
headers = Path(sys.argv[2]).read_text(encoding='utf-8').splitlines()
body = Path(sys.argv[3]).read_text(encoding='utf-8')
payload = json.loads(body)
out = {
    'request_url': f"https://{sys.argv[4]}/",
    'status_code': int(headers[0].split()[1]) if headers else None,
    'headers': headers,
    'body': body,
    'body_json': payload,
}
Path(sys.argv[1]).write_text(json.dumps(out, indent=2) + '\n', encoding='utf-8')
PY
                return 0
            fi
        fi
        if [ $(( $(date +%s) - started_at )) -ge "${timeout_seconds}" ]; then
            return 1
        fi
        sleep 15
    done
}

echo '=== Phase 1: ensure resource group exists ==='
if ! az group show --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --output none >/dev/null 2>&1; then
    az group create --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --location "${LOCATION}" --output json > "${SCRATCH_DIR}/group.json"
fi

echo
echo '=== Phase 2: deploy baseline infrastructure ==='
az deployment group create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --template-file "${SCRIPT_DIR}/infra/main.bicep" \
    --parameters baseName="${BASE_NAME}" location="${LOCATION}" \
    --output json > "${SCRATCH_DIR}/deployment.json"

discover_outputs

echo
echo '=== Phase 3: establish v1 baseline ==='
RG="${RG}" DEPLOYMENT_NAME="${DEPLOYMENT_NAME}" IMAGE_REPO="${IMAGE_REPO}" bash "${SCRIPT_DIR}/trigger.sh"
discover_outputs
BASELINE_REVISION="$(az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --query 'properties.latestReadyRevisionName' --output tsv)"
BASELINE_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v1"
BROKEN_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-broken"
RECOVER_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-recover"
export BASELINE_REVISION BASELINE_IMAGE BROKEN_IMAGE RECOVER_IMAGE

BASELINE_WINDOW_START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export BASELINE_WINDOW_START_UTC
az containerapp revision restart --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --revision "${BASELINE_REVISION}" --output none
sleep 45
BASELINE_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where TimeGenerated >= todatetime('${BASELINE_WINDOW_START_UTC}') | where RevisionName_s == '${BASELINE_REVISION}' | where Reason_s in ('PullingImage','PulledImage','ImagePullUnauthorized','ImagePullFailed','BackOff','ContainerTerminated') | project TimeGenerated, ContainerAppName_s, RevisionName_s, ReplicaName_s, Reason_s, Log_s, Type_s | order by TimeGenerated asc"
wait_for_query_match "${BASELINE_QUERY}" "${SCRATCH_DIR}/baseline-raw.json" 900 "len(rows) >= 2"
wait_for_revision_healthy "${BASELINE_REVISION}" 300
normalize_query_json "${SCRATCH_DIR}/baseline-raw.json" "${EVIDENCE_DIR}/05-baseline-success-window.json" "${BASELINE_QUERY}" "${BASELINE_WINDOW_START_UTC}"
capture_http_response "${SCRATCH_DIR}/baseline-http.json" v1 300

echo
echo '=== Phase 4: H1 trigger (remove FW PIP allowlist, deploy v-broken) ==='
H1_TRIGGER_TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az acr network-rule remove --subscription "${AZ_SUBSCRIPTION}" --name "${ACR_NAME}" --ip-address "${FIREWALL_PUBLIC_IP}" --output none
sleep 60
az containerapp update --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --image "${BROKEN_IMAGE}" --output none
BROKEN_REVISION="$(wait_for_revision_selector "${BROKEN_IMAGE}" 300)"
export H1_TRIGGER_TS_UTC BROKEN_REVISION
wait_for_revision_failed "${BROKEN_REVISION}" 600
sleep 45

H1_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where TimeGenerated >= todatetime('${H1_TRIGGER_TS_UTC}') | where RevisionName_s == '${BROKEN_REVISION}' or Log_s contains 'v-broken' or Log_s contains '${FIREWALL_PUBLIC_IP}' | project TimeGenerated, ContainerAppName_s, RevisionName_s, ReplicaName_s, Reason_s, Log_s, Type_s | order by TimeGenerated asc"
wait_for_query_match "${H1_QUERY}" "${SCRATCH_DIR}/h1-raw.json" 900 "any(('DENIED' in json.dumps(row)) or ('v-broken' in json.dumps(row)) for row in rows)"
normalize_query_json "${SCRATCH_DIR}/h1-raw.json" "${EVIDENCE_DIR}/06-system-logs-pre-fix.json" "${H1_QUERY}" "${H1_TRIGGER_TS_UTC}"
capture_http_response "${SCRATCH_DIR}/h1-http.json" v1 300

echo
echo '=== Phase 5: capture H1 raw evidence ==='
az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${SCRATCH_DIR}/app-pre.json"
az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --all --output json > "${EVIDENCE_DIR}/02-revision-list-pre-fix.json"
az acr show --subscription "${AZ_SUBSCRIPTION}" --name "${ACR_NAME}" --resource-group "${RG}" --query '{name:name,loginServer:loginServer,publicNetworkAccess:publicNetworkAccess,networkRuleBypassOptions:networkRuleBypassOptions,networkRuleSet:networkRuleSet}' --output json > "${EVIDENCE_DIR}/03-acr-network-rules-pre-fix.json"
az network firewall show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${FIREWALL_NAME}" --query '{name:name,id:id,privateIp:ipConfigurations[0].privateIPAddress,policyId:firewallPolicy.id,sku:sku.tier}' --output json > "${SCRATCH_DIR}/firewall-pre.json"
az network public-ip show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${FIREWALL_PUBLIC_IP_NAME}" --output json > "${SCRATCH_DIR}/firewall-pip-pre.json"
az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output yaml > "${EVIDENCE_DIR}/07-containerapp-spec-pre-fix.yaml"

python3 <<'PY'
import json
import os
from pathlib import Path

app = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/app-pre.json").read_text(encoding='utf-8'))
http_baseline = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/baseline-http.json").read_text(encoding='utf-8'))
payload = {
    'capture_metadata': {
        'resource_group': os.environ['RG'],
        'app_name': os.environ['APP_NAME'],
        'acr_name': os.environ['ACR_NAME'],
        'acr_login_server': os.environ['ACR_LOGIN_SERVER'],
        'acr_data_endpoint': os.environ['ACR_DATA_ENDPOINT'],
        'firewall_public_ip': os.environ['FIREWALL_PUBLIC_IP'],
        'firewall_private_ip': os.environ['FIREWALL_PRIVATE_IP'],
        'baseline_revision_name': os.environ['BASELINE_REVISION'],
        'broken_revision_name': os.environ['BROKEN_REVISION'],
        'baseline_image': os.environ['BASELINE_IMAGE'],
        'broken_image': os.environ['BROKEN_IMAGE'],
        'recover_image': os.environ['RECOVER_IMAGE'],
        'vnet_id': os.environ['VNET_ID'],
        'aca_subnet_id': os.environ['ACA_SUBNET_ID'],
        'law_customer_id': os.environ['LAW_CUSTOMER_ID'],
        'app_fqdn': os.environ['APP_FQDN'],
        'baseline_window_start_utc': os.environ['BASELINE_WINDOW_START_UTC'],
        'h1_trigger_ts_utc': os.environ['H1_TRIGGER_TS_UTC'],
        'baseline_http_response': http_baseline,
    },
    'container_app': app,
}
Path(os.environ['EVIDENCE_DIR']).joinpath('01-app-spec-pre-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

python3 <<'PY'
import json
import os
from pathlib import Path
payload = {
    'firewall': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/firewall-pre.json").read_text(encoding='utf-8')),
    'public_ip': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/firewall-pip-pre.json").read_text(encoding='utf-8')),
}
Path(os.environ['EVIDENCE_DIR']).joinpath('04-firewall-metadata-pre-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

FAILURE_COUNTS_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where TimeGenerated >= todatetime('${H1_TRIGGER_TS_UTC}') | where RevisionName_s == '${BROKEN_REVISION}' or Log_s contains 'v-broken' or Log_s contains '${FIREWALL_PUBLIC_IP}' | summarize denied_count=countif(Log_s contains 'DENIED'), imagepull_failed_count=countif(Log_s contains 'ImagePullFailure' or Reason_s == 'ImagePullFailed'), imagepull_unauthorized_count=countif(Reason_s == 'ImagePullUnauthorized' or Log_s contains 'ImagePullUnauthorized'), container_terminated_count=countif(Reason_s == 'ContainerTerminated')"
query_to_json "${FAILURE_COUNTS_QUERY}" "${SCRATCH_DIR}/h1-counts.json"
python3 <<'PY'
import json
import os
from pathlib import Path

h1_rows = json.loads(Path(os.path.join(os.environ['EVIDENCE_DIR'], '06-system-logs-pre-fix.json')).read_text(encoding='utf-8'))
counts_raw = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/h1-counts.json").read_text(encoding='utf-8'))
http_resp = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/h1-http.json").read_text(encoding='utf-8'))
rows = counts_raw.get('tables', [{}])[0].get('rows', []) if isinstance(counts_raw, dict) else counts_raw
cols = [c['name'] for c in counts_raw.get('tables', [{}])[0].get('columns', [])] if isinstance(counts_raw, dict) else []
counts = dict(zip(cols, rows[0])) if cols and rows else {}
payload = {
    'h1_trigger_ts_utc': os.environ['H1_TRIGGER_TS_UTC'],
    'broken_revision_name': os.environ['BROKEN_REVISION'],
    'baseline_revision_name': os.environ['BASELINE_REVISION'],
    'firewall_public_ip': os.environ['FIREWALL_PUBLIC_IP'],
    'http_response': http_resp,
    'row_count': h1_rows['row_count'],
    'rows': h1_rows['rows'],
    'counts': counts,
    'zero_successful_pulls_for_v_broken': not any(row.get('Reason_s') == 'PulledImage' and 'v-broken' in json.dumps(row) for row in h1_rows['rows']),
}
Path(os.environ['EVIDENCE_DIR']).joinpath('08-h1-failure-window.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

echo
echo '=== Phase 5b: Deactivate v-broken to lock in Failed state ==='
az containerapp revision deactivate --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --revision "${BROKEN_REVISION}" --output none
az containerapp revision show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --revision "${BROKEN_REVISION}" --output json > "${SCRATCH_DIR}/broken-post-deactivate.json"
sleep 15
echo
echo '=== Phase 6: H2 restore (re-add FW PIP, deploy v-recover) ==='
az acr network-rule add --subscription "${AZ_SUBSCRIPTION}" --name "${ACR_NAME}" --ip-address "${FIREWALL_PUBLIC_IP}" --output none
sleep 45
H2_RECOVERY_TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az containerapp update --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --image "${RECOVER_IMAGE}" --output none
RECOVER_REVISION="$(wait_for_revision_selector "${RECOVER_IMAGE}" 300)"
export H2_RECOVERY_TS_UTC RECOVER_REVISION
wait_for_revision_healthy "${RECOVER_REVISION}" 900
sleep 30

POST_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where TimeGenerated >= todatetime('${H2_RECOVERY_TS_UTC}') | where RevisionName_s == '${RECOVER_REVISION}' or Log_s contains 'v-recover' | project TimeGenerated, ContainerAppName_s, RevisionName_s, ReplicaName_s, Reason_s, Log_s, Type_s | order by TimeGenerated asc"
wait_for_query_match "${POST_QUERY}" "${SCRATCH_DIR}/h2-raw.json" 900 "any(row.get('Reason_s') == 'PulledImage' for row in rows)"
capture_http_response "${SCRATCH_DIR}/h2-http.json" v-recover 300

echo
echo '=== Phase 7: capture H2 raw evidence ==='
az acr show --subscription "${AZ_SUBSCRIPTION}" --name "${ACR_NAME}" --resource-group "${RG}" --query '{name:name,loginServer:loginServer,publicNetworkAccess:publicNetworkAccess,networkRuleBypassOptions:networkRuleBypassOptions,networkRuleSet:networkRuleSet}' --output json > "${EVIDENCE_DIR}/09-acr-network-rules-post-fix.json"
az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --all --output json > "${EVIDENCE_DIR}/10-revision-list-post-fix.json"
az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${SCRATCH_DIR}/app-post.json"
az network firewall show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${FIREWALL_NAME}" --query '{name:name,id:id,privateIp:ipConfigurations[0].privateIPAddress,policyId:firewallPolicy.id,sku:sku.tier}' --output json > "${SCRATCH_DIR}/firewall-post.json"
az network public-ip show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${FIREWALL_PUBLIC_IP_NAME}" --output json > "${SCRATCH_DIR}/firewall-pip-post.json"
normalize_query_json "${SCRATCH_DIR}/h2-raw.json" "${SCRATCH_DIR}/h2-normalized.json" "${POST_QUERY}" "${H2_RECOVERY_TS_UTC}"

python3 <<'PY'
import json
import os
from pathlib import Path
payload = {
    'capture_metadata': {
        'resource_group': os.environ['RG'],
        'app_name': os.environ['APP_NAME'],
        'acr_name': os.environ['ACR_NAME'],
        'acr_login_server': os.environ['ACR_LOGIN_SERVER'],
        'acr_data_endpoint': os.environ['ACR_DATA_ENDPOINT'],
        'firewall_public_ip': os.environ['FIREWALL_PUBLIC_IP'],
        'firewall_private_ip': os.environ['FIREWALL_PRIVATE_IP'],
        'baseline_revision_name': os.environ['BASELINE_REVISION'],
        'broken_revision_name': os.environ['BROKEN_REVISION'],
        'recover_revision_name': os.environ['RECOVER_REVISION'],
        'h2_recovery_ts_utc': os.environ['H2_RECOVERY_TS_UTC'],
        'app_fqdn': os.environ['APP_FQDN'],
        'broken_revision_post_deactivate': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/broken-post-deactivate.json").read_text(encoding='utf-8')),
    },
    'container_app': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/app-post.json").read_text(encoding='utf-8')),
    'acr': json.loads(Path(os.path.join(os.environ['EVIDENCE_DIR'], '09-acr-network-rules-post-fix.json')).read_text(encoding='utf-8')),
    'firewall': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/firewall-post.json").read_text(encoding='utf-8')),
    'public_ip': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/firewall-pip-post.json").read_text(encoding='utf-8')),
}
Path(os.environ['EVIDENCE_DIR']).joinpath('11-app-spec-post-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

python3 <<'PY'
import json
import os
from pathlib import Path
rows_payload = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/h2-normalized.json").read_text(encoding='utf-8'))
http_resp = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/h2-http.json").read_text(encoding='utf-8'))
payload = {
    'h2_recovery_ts_utc': os.environ['H2_RECOVERY_TS_UTC'],
    'recover_revision_name': os.environ['RECOVER_REVISION'],
    'broken_revision_name': os.environ['BROKEN_REVISION'],
    'baseline_revision_name': os.environ['BASELINE_REVISION'],
    'http_response': http_resp,
    'row_count': rows_payload['row_count'],
    'rows': rows_payload['rows'],
    'pulledimage_count': sum(1 for row in rows_payload['rows'] if row.get('Reason_s') == 'PulledImage'),
    'pullingimage_count': sum(1 for row in rows_payload['rows'] if row.get('Reason_s') == 'PullingImage'),
}
Path(os.environ['EVIDENCE_DIR']).joinpath('12-h2-recovery-window.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

echo
echo '=== Phase 8: write evidence README, sanitize, verify, cleanup ==='
cat > "${EVIDENCE_DIR}/README.md" <<'EOF2'
# Evidence pack — `acr-network-path-firewall-allowlist` lab

This directory carries the live raw evidence cohort for the `acr-network-path-firewall-allowlist` lab plus the derived Phase B gate outputs emitted by `labs/acr-network-path-firewall-allowlist/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what one live `koreacentral` reproduction can support about Path A with one Azure Firewall Basic instance, one ACR Premium registry exposed publicly, one firewall public IP allow-listed in `networkRuleSet.ipRules`, one broken `v-broken` fresh-pull window, one recovered `v-recover` fresh-pull window, and one already-cached `v1` revision that kept serving traffic throughout H1.

## Capture timeline

1. **Baseline-presence proof.** `05-baseline-success-window.json` proves the healthy `v1` pull emitted successful pull markers before the allowlist entry was removed.
2. **H1 failure surface.** `01` through `08` capture the broken window after the firewall public IP was removed from the ACR allowlist and `v-broken` failed with a DENIED/403 surface while the old `v1` revision kept serving.
3. **H2 recovery surface.** `09` through `12` capture the restored allowlist, healthy `v-recover` revision, and successful post-fix pull markers.
4. **Phase B overlay.** `verify.sh` re-parses the raw files and deterministically writes Gate 14 through Gate 17.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, bounded UTC coherence, pre/post lineage equality, anchor consistency (RG, app, ACR, firewall public IP), and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves baseline presence, confirms the allowlist entry was removed while ACR stayed locked down, proves the DENIED/403 failure named the firewall public IP for `v-broken`, proves the broken revision failed, and proves the old `v1` revision kept serving.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves the allowlist entry was restored, the latest `v-recover` revision is Healthy, the recovery window contains `PullingImage` + `PulledImage`, and the post-fix evidence shows `v-broken` was not retroactively repaired after explicit deactivation.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the bounded H1↔H2 diff and carries the non-vacuous silence-gate proof required for this final Path A pack.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Broken-window container app surface plus capture metadata |
| `02-revision-list-pre-fix.json` | Revision list during H1 showing `v1` plus the failed `v-broken` attempt |
| `03-acr-network-rules-pre-fix.json` | ACR rule set after the firewall public IP was removed |
| `04-firewall-metadata-pre-fix.json` | Firewall public/private IP metadata and policy anchor |
| `05-baseline-success-window.json` | Baseline successful pull window proving non-vacuous success markers |
| `06-system-logs-pre-fix.json` | Structured H1 system-log window containing the DENIED/403 evidence |
| `07-containerapp-spec-pre-fix.yaml` | Full pre-fix container app YAML |
| `08-h1-failure-window.json` | Composite H1 payload: broken-window `/` response, counts, and DENIED rows |
| `09-acr-network-rules-post-fix.json` | ACR rule set after the firewall public IP was restored |
| `10-revision-list-post-fix.json` | Revision list during H2 showing healthy `v-recover` |
| `11-app-spec-post-fix.json` | Composite post-fix app + ACR + firewall surface |
| `12-h2-recovery-window.json` | Composite H2 payload: `v-recover` response and successful pull markers |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

```bash
cd labs/acr-network-path-firewall-allowlist/
bash verify.sh
```

The verifier is hermetic: it reads only the committed raw cohort in this directory, rewrites the four Phase B gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
EOF2

sanitize_pii "${EVIDENCE_DIR}"
bash "${SCRIPT_DIR}/verify.sh"
az group delete --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --yes --no-wait
echo "Cleanup initiated for ${RG}."
