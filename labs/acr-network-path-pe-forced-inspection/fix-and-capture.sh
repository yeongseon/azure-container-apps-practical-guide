#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:-$(az account show --query id --output tsv)}"
RG="${RG:-rg-lab-pe-forced-inspection-$(date +%Y%m%d%H%M)}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-acrpefci}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-pe-forced-inspection}"
IMAGE_REPO="${IMAGE_REPO:-pe-forced-inspection-lab}"

echo "fix-and-capture.sh starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "Resource group: ${RG}"
echo "Location: ${LOCATION}"
echo

rm -f "${EVIDENCE_DIR}/"{01,02,03,04,05,06,07,08,09,10,11,12,14,15,16,17}-* || true
rm -f "${EVIDENCE_DIR}/_"* || true

if ! az group show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${RG}" \
    --output none >/dev/null 2>&1; then
    echo "=== Phase 1: create resource group ==="
    az group create \
        --subscription "${AZ_SUBSCRIPTION}" \
        --name "${RG}" \
        --location "${LOCATION}" \
        --output json >/dev/null
    echo
fi

cleanup_rg() {
    az group delete --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --yes --no-wait >/dev/null 2>&1 || true
}
trap cleanup_rg EXIT

containerapp_update_image() {
    local image_ref="$1"
    local attempt
    for attempt in 1 2 3 4 5; do
        if az containerapp show \
            --subscription "${AZ_SUBSCRIPTION}" \
            --name "${APP_NAME}" \
            --resource-group "${RG}" \
            --output none >/dev/null 2>&1; then
            if az containerapp update \
                --subscription "${AZ_SUBSCRIPTION}" \
                --name "${APP_NAME}" \
                --resource-group "${RG}" \
                --image "${image_ref}" \
                --output none; then
                return 0
            fi
        fi
        echo "containerapp update retry ${attempt}/5 for ${image_ref}" >&2
        sleep 20
    done
    return 1
}

echo "=== Phase 2: deploy Scenario C infrastructure ==="
az deployment group create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --template-file "${SCRIPT_DIR}/infra/main.bicep" \
    --parameters baseName="${BASE_NAME}" location="${LOCATION}" \
    --output none

APP_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.appName.value' --output tsv)"
ACR_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.registryName.value' --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.registryLoginServer.value' --output tsv)"
ACR_DATA_FQDN="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.registryDataEndpoint.value' --output tsv)"
FW_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.firewallName.value' --output tsv)"
FW_PRIVATE_IP="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.firewallPrivateIp.value' --output tsv)"
ROUTE_TABLE_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.routeTableName.value' --output tsv)"
VNET_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.vnetName.value' --output tsv)"
PE_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.privateEndpointName.value' --output tsv)"
WORKSPACE_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.logAnalyticsName.value' --output tsv)"
WORKSPACE_ID="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.logAnalyticsCustomerId.value' --output tsv)"

APP_FQDN="$(az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --query 'properties.configuration.ingress.fqdn' --output tsv)"
VNET_ID="$(az network vnet show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${VNET_NAME}" --query id --output tsv)"

echo "=== Phase 3: establish baseline via trigger.sh ==="
RG="${RG}" DEPLOYMENT_NAME="${DEPLOYMENT_NAME}" IMAGE_REPO="${IMAGE_REPO}" bash "${SCRIPT_DIR}/trigger.sh"
sleep 30

NIC_IDS="$(az network private-endpoint show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${PE_NAME}" --query 'networkInterfaces[].id' --output tsv)"

export NIC_IDS
PE_IP_MAP_JSON="$(python3 <<'PY'
import json
import os
import subprocess

items = []
for nic_id in os.environ["NIC_IDS"].split():
    payload = json.loads(subprocess.check_output([
        "az", "network", "nic", "show", "--ids", nic_id, "--output", "json"
    ], text=True))
    for config in payload.get("ipConfigurations", []):
        items.append({
            "name": config.get("name"),
            "private_ip": config.get("privateIPAddress"),
            "fqdns": sorted(config.get("privateLinkConnectionProperties", {}).get("fqdns", []) or []),
        })
print(json.dumps(sorted(items, key=lambda item: (item.get("private_ip") or "", ",".join(item.get("fqdns", []))))) )
PY
)"
export PE_IP_MAP_JSON AZ_SUBSCRIPTION RG ROUTE_TABLE_NAME FW_PRIVATE_IP

BASELINE_WINDOW_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BASELINE_WINDOW_START="$(date -u -v-20M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(minutes=20)).strftime('%Y-%m-%dT%H:%M:%SZ'))
PY
)"

FIREWALL_QUERY_TEMPLATE=$(cat <<'EOF'
union isfuzzy=true
  (AZFWApplicationRule
    | where TimeGenerated between (datetime('{WINDOW_START}') .. datetime('{WINDOW_END}'))
    | where Fqdn endswith '.azurecr.io'
    | project TimeGenerated, Fqdn, SourceIp, Action, Policy, RuleCollectionGroup, RuleCollection, Rule, Source='AZFWApplicationRule'),
  (AzureDiagnostics
    | where TimeGenerated between (datetime('{WINDOW_START}') .. datetime('{WINDOW_END}'))
    | where Category == 'AzureFirewallApplicationRule'
    | where msg_s contains 'azurecr.io'
    | extend Fqdn=extract(@'to (\S+):443', 1, msg_s)
    | extend SourceIp=extract(@'from (\d+\.\d+\.\d+\.\d+)', 1, msg_s)
    | project TimeGenerated, Fqdn, SourceIp, Action=action_s, Policy=policy_s, RuleCollectionGroup=ruleCollectionGroup_s, RuleCollection=ruleCollection_s, Rule=rule_s, Source='AzureDiagnostics')
| where Fqdn endswith '.azurecr.io'
| order by TimeGenerated desc
EOF
)

baseline_query="${FIREWALL_QUERY_TEMPLATE//\{WINDOW_START\}/${BASELINE_WINDOW_START}}"
baseline_query="${baseline_query//\{WINDOW_END\}/${BASELINE_WINDOW_END}}"
BASELINE_ROWS_FILE="$(mktemp -t pe-fi-baseline-XXXXXX.json)"

echo "=== Phase 4: capture baseline raw evidence ==="
az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${baseline_query}" \
    --output json > "${BASELINE_ROWS_FILE}"

az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output json > "${EVIDENCE_DIR}/_app-baseline.json"

az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output json > "${EVIDENCE_DIR}/_revisions-baseline.json"

az network route-table route list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --route-table-name "${ROUTE_TABLE_NAME}" \
    --output json > "${EVIDENCE_DIR}/_routes-baseline.json"

for nic_id in ${NIC_IDS}; do
    az network nic show --ids "${nic_id}" --output json > "${EVIDENCE_DIR}/_$(basename "${nic_id}").json"
done

az acr show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${ACR_NAME}" \
    --output json > "${EVIDENCE_DIR}/_acr-baseline.json"

az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output yaml > "${EVIDENCE_DIR}/07-containerapp-spec-pre-fix.yaml"

echo "=== Phase 5: H1 trigger (remove PE /32 routes, deploy v-bypass) ==="
python3 <<'PY'
import json
import os
import subprocess

pe_map = json.loads(os.environ["PE_IP_MAP_JSON"])
for item in pe_map:
    ip = item.get("private_ip")
    if not ip:
        continue
    subprocess.check_call([
        "az", "network", "route-table", "route", "delete",
        "--subscription", os.environ["AZ_SUBSCRIPTION"],
        "--resource-group", os.environ["RG"],
        "--route-table-name", os.environ["ROUTE_TABLE_NAME"],
        "--name", f"pe-{ip.replace('.', '-')}",
        "--output", "none",
    ])
PY
sleep 90

H1_TRIGGER_TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az containerapp update \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --image "${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-bypass" \
    --output none >/dev/null 2>&1 || true
containerapp_update_image "${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-bypass"

DEADLINE=$((SECONDS + 420))
while [ $SECONDS -lt $DEADLINE ]; do
    BYPASS_HEALTH="$(az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --query "[?properties.template.containers[0].image=='${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-bypass'] | sort_by(@, &properties.createdTime) | [-1].properties.healthState" --output tsv)"
    if [ "${BYPASS_HEALTH}" = "Healthy" ]; then
        break
    fi
    sleep 15
done

sleep 30
H1_BODY_FILE="$(mktemp -t pe-fi-h1-body-XXXXXX.txt)"
H1_HEADERS_FILE="$(mktemp -t pe-fi-h1-headers-XXXXXX.txt)"
H1_HTTP_CODE="$(curl --silent --show-error --output "${H1_BODY_FILE}" --dump-header "${H1_HEADERS_FILE}" --write-out '%{http_code}' "https://${APP_FQDN}/" || true)"

echo "=== Phase 6: wait for baseline / bypass firewall-log convergence ==="
sleep 300

H1_WINDOW_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
h1_query="${FIREWALL_QUERY_TEMPLATE//\{WINDOW_START\}/${H1_TRIGGER_TS_UTC}}"
h1_query="${h1_query//\{WINDOW_END\}/${H1_WINDOW_END}}"
H1_ROWS_FILE="$(mktemp -t pe-fi-h1-rows-XXXXXX.json)"
az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${h1_query}" \
    --output json > "${H1_ROWS_FILE}"

SYSTEM_QUERY_TEMPLATE=$(cat <<'EOF'
ContainerAppSystemLogs_CL
| where ContainerAppName_s == '{APP_NAME}'
| where TimeGenerated between (datetime('{WINDOW_START}') .. datetime('{WINDOW_END}'))
| summarize EventCount=count() by RevisionName=tostring(RevisionName_s), Reason=tostring(Reason_s)
| order by RevisionName asc, Reason asc
EOF
)
system_h1_query="${SYSTEM_QUERY_TEMPLATE//\{APP_NAME\}/${APP_NAME}}"
system_h1_query="${system_h1_query//\{WINDOW_START\}/${H1_TRIGGER_TS_UTC}}"
system_h1_query="${system_h1_query//\{WINDOW_END\}/${H1_WINDOW_END}}"
H1_SYSTEM_ROWS_FILE="$(mktemp -t pe-fi-h1-system-XXXXXX.json)"
az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${system_h1_query}" \
    --output json > "${H1_SYSTEM_ROWS_FILE}"

az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output json > "${EVIDENCE_DIR}/02-revision-list-pre-fix.json"

az network route-table route list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --route-table-name "${ROUTE_TABLE_NAME}" \
    --output json > "${EVIDENCE_DIR}/_routes-h1.json"

echo "=== Phase 7: H2 recovery (re-add PE /32 routes, deploy v-recover) ==="
python3 <<'PY'
import json
import os
import subprocess

pe_map = json.loads(os.environ["PE_IP_MAP_JSON"])
for item in pe_map:
    ip = item.get("private_ip")
    if not ip:
        continue
    subprocess.check_call([
        "az", "network", "route-table", "route", "create",
        "--subscription", os.environ["AZ_SUBSCRIPTION"],
        "--resource-group", os.environ["RG"],
        "--route-table-name", os.environ["ROUTE_TABLE_NAME"],
        "--name", f"pe-{ip.replace('.', '-')}",
        "--address-prefix", f"{ip}/32",
        "--next-hop-type", "VirtualAppliance",
        "--next-hop-ip-address", os.environ["FW_PRIVATE_IP"],
        "--output", "none",
    ])
PY
sleep 90

H2_RECOVERY_TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
containerapp_update_image "${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-recover"

DEADLINE=$((SECONDS + 420))
while [ $SECONDS -lt $DEADLINE ]; do
    RECOVER_HEALTH="$(az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --query "[?properties.template.containers[0].image=='${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-recover'] | sort_by(@, &properties.createdTime) | [-1].properties.healthState" --output tsv)"
    if [ "${RECOVER_HEALTH}" = "Healthy" ]; then
        break
    fi
    sleep 15
done

sleep 30
H2_BODY_FILE="$(mktemp -t pe-fi-h2-body-XXXXXX.txt)"
H2_HEADERS_FILE="$(mktemp -t pe-fi-h2-headers-XXXXXX.txt)"
H2_HTTP_CODE="$(curl --silent --show-error --output "${H2_BODY_FILE}" --dump-header "${H2_HEADERS_FILE}" --write-out '%{http_code}' "https://${APP_FQDN}/" || true)"

echo "=== Phase 8: wait for recovery firewall-log convergence ==="
sleep 180

H2_WINDOW_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
h2_query="${FIREWALL_QUERY_TEMPLATE//\{WINDOW_START\}/${H2_RECOVERY_TS_UTC}}"
h2_query="${h2_query//\{WINDOW_END\}/${H2_WINDOW_END}}"
H2_ROWS_FILE="$(mktemp -t pe-fi-h2-rows-XXXXXX.json)"
az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${h2_query}" \
    --output json > "${H2_ROWS_FILE}"

system_h2_query="${SYSTEM_QUERY_TEMPLATE//\{APP_NAME\}/${APP_NAME}}"
system_h2_query="${system_h2_query//\{WINDOW_START\}/${H1_TRIGGER_TS_UTC}}"
system_h2_query="${system_h2_query//\{WINDOW_END\}/${H2_WINDOW_END}}"
H2_SYSTEM_ROWS_FILE="$(mktemp -t pe-fi-h2-system-XXXXXX.json)"
az monitor log-analytics query \
    --subscription "${AZ_SUBSCRIPTION}" \
    --workspace "${WORKSPACE_ID}" \
    --analytics-query "${system_h2_query}" \
    --output json > "${H2_SYSTEM_ROWS_FILE}"

az network route-table route list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --route-table-name "${ROUTE_TABLE_NAME}" \
    --output json > "${EVIDENCE_DIR}/_routes-h2.json"

az containerapp revision list \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output json > "${EVIDENCE_DIR}/10-revision-list-post-fix.json"

az containerapp show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${APP_NAME}" \
    --resource-group "${RG}" \
    --output json > "${EVIDENCE_DIR}/_app-post.json"

az acr show \
    --subscription "${AZ_SUBSCRIPTION}" \
    --name "${ACR_NAME}" \
    --output json > "${EVIDENCE_DIR}/_acr-post.json"

echo "=== Phase 9: materialize canonical raw files ==="
export RG LOCATION BASE_NAME AZ_SUBSCRIPTION APP_NAME ACR_NAME ACR_LOGIN_SERVER ACR_DATA_FQDN FW_NAME FW_PRIVATE_IP ROUTE_TABLE_NAME VNET_ID PE_NAME WORKSPACE_ID APP_FQDN PE_IP_MAP_JSON BASELINE_ROWS_FILE H1_ROWS_FILE H2_ROWS_FILE H1_SYSTEM_ROWS_FILE H2_SYSTEM_ROWS_FILE H1_BODY_FILE H1_HEADERS_FILE H1_HTTP_CODE H2_BODY_FILE H2_HEADERS_FILE H2_HTTP_CODE BASELINE_WINDOW_START BASELINE_WINDOW_END H1_TRIGGER_TS_UTC H2_RECOVERY_TS_UTC H2_WINDOW_END
export H1_WINDOW_END
export EVIDENCE_DIR
python3 <<'PY'
import json
import os
from pathlib import Path

evidence_dir = Path(os.environ["EVIDENCE_DIR"])

def read_json_file(path_env: str):
    return json.loads(Path(os.environ[path_env]).read_text(encoding="utf-8"))

def rows_from_query_payload(payload):
    if isinstance(payload, dict) and isinstance(payload.get("tables"), list) and payload["tables"]:
        table = payload["tables"][0]
        columns = [col.get("name") for col in table.get("columns", [])]
        return [dict(zip(columns, row)) for row in table.get("rows", [])]
    if isinstance(payload, dict) and isinstance(payload.get("rows"), list):
        return payload.get("rows", [])
    if isinstance(payload, list):
        return payload
    return []

baseline_rows = rows_from_query_payload(read_json_file("BASELINE_ROWS_FILE"))
h1_fw_rows = rows_from_query_payload(read_json_file("H1_ROWS_FILE"))
h2_fw_rows = rows_from_query_payload(read_json_file("H2_ROWS_FILE"))
h1_system_rows = rows_from_query_payload(read_json_file("H1_SYSTEM_ROWS_FILE"))
h2_system_rows = rows_from_query_payload(read_json_file("H2_SYSTEM_ROWS_FILE"))

app_baseline = json.loads((evidence_dir / "_app-baseline.json").read_text(encoding="utf-8"))
app_post = json.loads((evidence_dir / "_app-post.json").read_text(encoding="utf-8"))
acr_baseline = json.loads((evidence_dir / "_acr-baseline.json").read_text(encoding="utf-8"))
acr_post = json.loads((evidence_dir / "_acr-post.json").read_text(encoding="utf-8"))
routes_baseline = json.loads((evidence_dir / "_routes-baseline.json").read_text(encoding="utf-8"))
routes_h1 = json.loads((evidence_dir / "_routes-h1.json").read_text(encoding="utf-8"))
routes_h2 = json.loads((evidence_dir / "_routes-h2.json").read_text(encoding="utf-8"))
revisions_baseline = json.loads((evidence_dir / "_revisions-baseline.json").read_text(encoding="utf-8"))
revisions_pre = json.loads((evidence_dir / "02-revision-list-pre-fix.json").read_text(encoding="utf-8"))
revisions_post = json.loads((evidence_dir / "10-revision-list-post-fix.json").read_text(encoding="utf-8"))

nic_paths = sorted(evidence_dir.glob("_*.json"))
nic_payloads = []
for path in nic_paths:
    if path.name.startswith("_nic-") or path.name.startswith("_") and "providers-Microsoft.Network-networkInterfaces" in path.name:
        nic_payloads.append(json.loads(path.read_text(encoding="utf-8")))
if not nic_payloads:
    for path in nic_paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and data.get("type") == "Microsoft.Network/networkInterfaces":
            nic_payloads.append(data)

combined_nic = nic_payloads[0] if len(nic_payloads) == 1 else {
    "id": nic_payloads[0].get("id") if nic_payloads else None,
    "name": nic_payloads[0].get("name") if nic_payloads else None,
    "ipConfigurations": [cfg for nic in nic_payloads for cfg in nic.get("ipConfigurations", [])],
}

capture_metadata = {
    "resource_group": os.environ["RG"],
    "base_name": os.environ["BASE_NAME"],
    "location": os.environ["LOCATION"],
    "app_name": os.environ["APP_NAME"],
    "acr_name": os.environ["ACR_NAME"],
    "acr_login_server": os.environ["ACR_LOGIN_SERVER"],
    "acr_data_fqdn": os.environ["ACR_DATA_FQDN"],
    "firewall_name": os.environ["FW_NAME"],
    "firewall_private_ip": os.environ["FW_PRIVATE_IP"],
    "route_table_name": os.environ["ROUTE_TABLE_NAME"],
    "vnet_id": os.environ["VNET_ID"],
    "private_endpoint_name": os.environ["PE_NAME"],
    "log_analytics_customer_id": os.environ["WORKSPACE_ID"],
    "app_fqdn": os.environ["APP_FQDN"],
    "pe_ip_map": json.loads(os.environ["PE_IP_MAP_JSON"]),
}

def route_payload(routes, capture_state):
    return {
        "capture_state": capture_state,
        "route_table_name": os.environ["ROUTE_TABLE_NAME"],
        "firewall_private_ip": os.environ["FW_PRIVATE_IP"],
        "routes": routes,
    }

def response_payload(body_file_env, headers_file_env, code_env):
    body_text = Path(os.environ[body_file_env]).read_text(encoding="utf-8")
    try:
        body_json = json.loads(body_text)
    except json.JSONDecodeError:
        body_json = None
    return {
        "request_url": f"https://{os.environ['APP_FQDN']}/",
        "status_code": int(os.environ[code_env]),
        "headers": Path(os.environ[headers_file_env]).read_text(encoding="utf-8").splitlines(),
        "body": body_text,
        "body_json": body_json,
    }

def summarize_counts(rows):
    out = {}
    for row in rows:
        reason = row.get("Reason") or row.get("Reason_s") or row.get("ReasonName") or row.get("ReasonName_s") or ""
        if not reason:
            continue
        out[reason] = out.get(reason, 0) + int(row.get("EventCount", row.get("EventCount_d", 1)) or 1)
    return out

h1_counts = summarize_counts(h1_system_rows)
h2_counts = summarize_counts(h2_system_rows)

(evidence_dir / "01-app-spec-pre-fix.json").write_text(json.dumps({
    "capture_metadata": capture_metadata,
    "container_app": app_baseline,
}, indent=2) + "\n", encoding="utf-8")
(evidence_dir / "03-route-table-pre-fix.json").write_text(json.dumps(route_payload(routes_h1, "h1_pre_fix"), indent=2) + "\n", encoding="utf-8")
(evidence_dir / "04-pe-nic-config-pre-fix.json").write_text(json.dumps(combined_nic, indent=2) + "\n", encoding="utf-8")
(evidence_dir / "05-acr-public-access-pre-fix.json").write_text(json.dumps({
    "loginServer": acr_baseline.get("loginServer"),
    "publicNetworkAccess": acr_baseline.get("publicNetworkAccess"),
    "networkRuleBypassOptions": acr_baseline.get("networkRuleBypassOptions"),
    "dataEndpointEnabled": acr_baseline.get("dataEndpointEnabled"),
}, indent=2) + "\n", encoding="utf-8")
(evidence_dir / "06-firewall-log-baseline.json").write_text(json.dumps({
    "query": os.environ["BASELINE_WINDOW_START"] + " -> " + os.environ["BASELINE_WINDOW_END"],
    "window_start_utc": os.environ["BASELINE_WINDOW_START"],
    "window_end_utc": os.environ["BASELINE_WINDOW_END"],
    "row_count": len(baseline_rows),
    "rows": baseline_rows,
}, indent=2) + "\n", encoding="utf-8")
(evidence_dir / "08-h1-silence-window.json").write_text(json.dumps({
    "h1_trigger_ts_utc": os.environ["H1_TRIGGER_TS_UTC"],
    "firewall_query": os.environ["H1_TRIGGER_TS_UTC"] + " -> " + os.environ["H1_WINDOW_END"],
    "firewall_row_count": len(h1_fw_rows),
    "firewall_rows": h1_fw_rows,
    "system_query": "ContainerAppSystemLogs_CL summary for H1 window",
    "system_rows": h1_system_rows,
    "http_response": response_payload("H1_BODY_FILE", "H1_HEADERS_FILE", "H1_HTTP_CODE"),
    "all_revisions_healthy": all(row.get("properties", {}).get("healthState") == "Healthy" for row in revisions_pre),
    "imagepull_failed_count": int(h1_counts.get("ImagePullFailed", 0)),
    "revision_failed_count": int(h1_counts.get("RevisionFailed", 0)),
    "imagepull_unauthorized_count": int(h1_counts.get("ImagePullUnauthorized", 0)),
    "zero_imagepull_failures": int(h1_counts.get("ImagePullFailed", 0)) == 0,
    "zero_revision_failures": int(h1_counts.get("RevisionFailed", 0)) == 0,
}, indent=2) + "\n", encoding="utf-8")
(evidence_dir / "09-route-table-post-fix.json").write_text(json.dumps(route_payload(routes_h2, "h2_post_fix"), indent=2) + "\n", encoding="utf-8")
(evidence_dir / "11-app-spec-post-fix.json").write_text(json.dumps({
    "capture_metadata": capture_metadata,
    "container_app": app_post,
    "acr": {
        "loginServer": acr_post.get("loginServer"),
        "publicNetworkAccess": acr_post.get("publicNetworkAccess"),
        "networkRuleBypassOptions": acr_post.get("networkRuleBypassOptions"),
        "dataEndpointEnabled": acr_post.get("dataEndpointEnabled"),
    },
    "pe_nic": combined_nic,
}, indent=2) + "\n", encoding="utf-8")
(evidence_dir / "12-h2-recovery-window.json").write_text(json.dumps({
    "h2_recovery_ts_utc": os.environ["H2_RECOVERY_TS_UTC"],
    "firewall_query": os.environ["H2_RECOVERY_TS_UTC"] + " -> " + os.environ["H2_WINDOW_END"],
    "firewall_row_count": len(h2_fw_rows),
    "firewall_rows": h2_fw_rows,
    "system_query": "ContainerAppSystemLogs_CL summary for H1+H2 window",
    "system_rows": h2_system_rows,
    "http_response": response_payload("H2_BODY_FILE", "H2_HEADERS_FILE", "H2_HTTP_CODE"),
    "all_revisions_healthy": all(row.get("properties", {}).get("healthState") == "Healthy" for row in revisions_post),
    "imagepull_failed_count": int(h2_counts.get("ImagePullFailed", 0)),
    "revision_failed_count": int(h2_counts.get("RevisionFailed", 0)),
    "imagepull_unauthorized_count": int(h2_counts.get("ImagePullUnauthorized", 0)),
    "zero_imagepull_failures": int(h2_counts.get("ImagePullFailed", 0)) == 0,
    "zero_revision_failures": int(h2_counts.get("RevisionFailed", 0)) == 0,
}, indent=2) + "\n", encoding="utf-8")

readme = f'''# Evidence pack — `acr-network-path-pe-forced-inspection` lab

This directory carries the live raw evidence cohort for the `acr-network-path-pe-forced-inspection` lab plus the derived Phase B gate outputs emitted by `labs/acr-network-path-pe-forced-inspection/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what a single live `koreacentral` reproduction can support about Path C with one ACR Private Endpoint, one Azure Firewall Basic instance, one default route to the firewall, two PE NIC IPs, one bypass window created by removing the two customer `/32` PE routes, and one recovery window created by restoring those routes. It does **not** claim universal applicability across regions, tenants, firewall policies, or platform versions.

## Reproduction parameters

| Parameter | Value |
|---|---|
| Resource group | `{os.environ['RG']}` |
| Base name | `{os.environ['BASE_NAME']}` |
| Azure region | `{os.environ['LOCATION']}` |
| Registry login FQDN | `{os.environ['ACR_LOGIN_SERVER']}` |
| Data FQDN | `{os.environ['ACR_DATA_FQDN']}` |
| Firewall private IP | `{os.environ['FW_PRIVATE_IP']}` |
| Baseline pull window | `{os.environ['BASELINE_WINDOW_START']}` → `{os.environ['BASELINE_WINDOW_END']}` |
| H1 trigger timestamp | `{os.environ['H1_TRIGGER_TS_UTC']}` |
| H2 recovery timestamp | `{os.environ['H2_RECOVERY_TS_UTC']}` |

## Capture timeline

1. **Baseline-presence proof.** `01-app-spec-pre-fix.json` through `07-containerapp-spec-pre-fix.yaml` capture the PE-only baseline and the firewall log window proving Azure Firewall did see ACR traffic before the bypass.
2. **H1 silence window.** `02-revision-list-pre-fix.json`, `03-route-table-pre-fix.json`, and `08-h1-silence-window.json` capture the broken window after the two customer `/32` PE routes are removed, where pulls still succeed but the firewall sees zero new ACR rows.
3. **H2 recovery window.** `09-route-table-post-fix.json` through `12-h2-recovery-window.json` capture the restored `/32` routes, healthy `v-recover` revision, and the return of ACR rows in the firewall log.
4. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, single-window UTC coherence, revision-lineage equality, unchanged PE NIC IP map, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves the baseline-presence subgate, the `/32` routes were removed while the default route stayed, the v-bypass pull still succeeded under PE-only ACR, the H1 firewall query returned zero rows, and the workload-silence invariant held.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves the exact `/32` routes were restored, the latest active `v-recover` revision is Healthy, the H2 firewall query returned rows again, and the workload-silence invariant still held.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the full silence-gate bounded-falsification check: baseline-presence, bypass-absence, recovery-presence, workload-silence, held constants, and explicit claim ceiling.

## Honest disclosure

- The pack captures one live Azure reproduction in `koreacentral`; it is not a statistical sample.
- `06-firewall-log-baseline.json`, `08-h1-silence-window.json`, and `12-h2-recovery-window.json` preserve explicit firewall-query windows because the silence-gate claim depends on time-bounded absence versus presence.
- Gate 14 uses file-system UTC anchors (`birthtime`, falling back to `mtime`) so reruns are byte-stable and explicit about the time source for each file.
- The pack does not prove exact Azure Firewall ingestion latency, exact pull durations, OCI layer digests, route-propagation subsecond timing, pod continuity, or the specific internal ACA component identity behind the observed workload-subnet source IP. Those ceilings are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Baseline app surface plus capture metadata |
| `02-revision-list-pre-fix.json` | H1 revision list after `v-bypass` reaches Healthy |
| `03-route-table-pre-fix.json` | Route-table inventory after the PE `/32` routes are removed |
| `04-pe-nic-config-pre-fix.json` | PE NIC configuration proving the two ACR private IPs |
| `05-acr-public-access-pre-fix.json` | ACR public-access snapshot during H1 |
| `06-firewall-log-baseline.json` | Baseline firewall-log window proving ACR visibility before the bypass |
| `07-containerapp-spec-pre-fix.yaml` | Full baseline container app YAML |
| `08-h1-silence-window.json` | H1 composite payload: zero firewall rows, v-bypass response, system-log summary |
| `09-route-table-post-fix.json` | Route-table inventory after the PE `/32` routes are restored |
| `10-revision-list-post-fix.json` | H2 revision list after `v-recover` reaches Healthy |
| `11-app-spec-post-fix.json` | Composite post-fix app + ACR + PE NIC surface |
| `12-h2-recovery-window.json` | H2 composite payload: firewall rows restored, v-recover response, system-log summary |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/acr-network-path-pe-forced-inspection/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort without touching Azure. |

```bash
cd labs/acr-network-path-pe-forced-inspection/
bash verify.sh
```

The verifier is hermetic: it reads only the committed files in this directory, rewrites the four Phase B gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
'''
(evidence_dir / 'README.md').write_text(readme, encoding='utf-8')

for helper in evidence_dir.glob('_*.json'):
    helper.unlink()
PY

echo "=== Phase 10: sanitize evidence, run hermetic verifier, delete RG immediately ==="
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
    (re.compile(r'\b[A-Za-z0-9-]+\.onmicrosoft\.com(?![A-Za-z0-9.-])', re.I), 'contoso.onmicrosoft.com'),
    (re.compile(r'\bychoe\b', re.I), 'demouser'),
    (re.compile(r'Yeongseon\s+Choe', re.I), 'Demo User'),
    (re.compile(r'\byeongseon\b', re.I), 'demouser'),
    (re.compile(r'\b[0-9A-F]{32,}\b'), 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
    (re.compile(r'https://ms\.portal\.azure\.com[^\s"\']*', re.I), 'https://ms.portal.azure.com/#@contoso.onmicrosoft.com/'),
]
for path in sorted(base.glob('*')):
    if not path.is_file():
        continue
    text = path.read_text(encoding='utf-8')
    for regex, repl in subs:
        text = regex.sub(repl, text)
    path.write_text(text, encoding='utf-8')
PY

az group delete --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --yes --no-wait
trap - EXIT

bash "${SCRIPT_DIR}/verify.sh"
echo "Cleanup initiated for ${RG}. Evidence written to ${EVIDENCE_DIR}."
