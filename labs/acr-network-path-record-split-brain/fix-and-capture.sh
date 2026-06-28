#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:-$(az account show --query 'id' --output tsv)}"
RG="${RG:-rg-acr-record-split-brain-lab}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-acrrecsplitbrain}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-record-split-brain}"
IMAGE_REPO="${IMAGE_REPO:-record-split-brain-lab}"
BUILD_TAG="${BUILD_TAG:-v1}"

export AZ_SUBSCRIPTION RG LOCATION BASE_NAME DEPLOYMENT_NAME IMAGE_REPO BUILD_TAG EVIDENCE_DIR

rm -f "${EVIDENCE_DIR}/"{01,02,03,04,05,06,07,08,09,10,11,12,14,15,16,17}-* "${EVIDENCE_DIR}/README.md"

SCRATCH_DIR="$(mktemp -d -t acr-record-split-brain-phaseb-XXXXXX)"
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

wait_for_revision_healthy() {
    local app_name="$1"
    local timeout_seconds="$2"
    local started_at
    started_at="$(date +%s)"
    while true; do
        local revision_name health_state active_state
        revision_name="$(az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${app_name}" --resource-group "${RG}" --query 'properties.latestReadyRevisionName' --output tsv 2>/dev/null || true)"
        health_state="$(az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${app_name}" --resource-group "${RG}" --query "[?name=='${revision_name}'] | [0].properties.healthState" --output tsv 2>/dev/null || true)"
        active_state="$(az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${app_name}" --resource-group "${RG}" --query "[?name=='${revision_name}'] | [0].properties.active" --output tsv 2>/dev/null || true)"
        echo "wait_for_revision_healthy: revision=${revision_name} health=${health_state} active=${active_state}"
        if [ -n "${revision_name}" ] && [ "${health_state}" = "Healthy" ]; then
            return 0
        fi
        if [ $(( $(date +%s) - started_at )) -ge "${timeout_seconds}" ]; then
            return 1
        fi
        sleep 15
    done
}

capture_probe_payload() {
    local app_fqdn="$1"
    local expected_topology="$2"
    local output_file="$3"
    local captured_before_utc="$4"
    local captured_after_utc=""
    local raw_response=""
    local attempts_json="[]"

    for attempt in 1 2 3 4 5; do
        raw_response="$(curl -sS --max-time 30 "https://${app_fqdn}/probe" || true)"
        local valid_json=false
        local topology=""
        if [ -n "${raw_response}" ] && topology="$(printf '%s' "${raw_response}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("topology_class", ""))' 2>/dev/null || true)" && [ -n "${topology}" ]; then
            valid_json=true
        fi
        python3 - "${attempts_json}" "${attempt}" "${valid_json}" "${topology}" "${raw_response}" > "${SCRATCH_DIR}/probe-attempts.json" <<'PY'
import json
import sys
attempts = json.loads(sys.argv[1])
attempt = int(sys.argv[2])
valid = sys.argv[3] == 'true'
topology = sys.argv[4]
raw = sys.argv[5]
item = {"attempt": attempt, "valid_json": valid, "raw_response": raw}
if valid:
    try:
        item["response"] = json.loads(raw)
    except json.JSONDecodeError:
        item["response"] = None
else:
    item["response"] = None
item["topology_class"] = topology or None
attempts.append(item)
print(json.dumps(attempts))
PY
        attempts_json="$(cat "${SCRATCH_DIR}/probe-attempts.json")"
        if [ "${valid_json}" = true ] && [ "${topology}" = "${expected_topology}" ]; then
            captured_after_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            python3 - "${output_file}" "${expected_topology}" "${captured_before_utc}" "${captured_after_utc}" "${attempts_json}" "${attempt}" "${raw_response}" <<'PY'
import json
import sys
from pathlib import Path
payload = {
    "expected_topology": sys.argv[2],
    "captured_before_utc": sys.argv[3],
    "captured_after_utc": sys.argv[4],
    "attempts": json.loads(sys.argv[5]),
    "selected_attempt": int(sys.argv[6]),
    "response": json.loads(sys.argv[7]),
}
Path(sys.argv[1]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY
            return 0
        fi
        sleep 20
    done

    captured_after_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    python3 - "${output_file}" "${expected_topology}" "${captured_before_utc}" "${captured_after_utc}" "${attempts_json}" "${raw_response}" <<'PY'
import json
import sys
from pathlib import Path
payload = {
    "expected_topology": sys.argv[2],
    "captured_before_utc": sys.argv[3],
    "captured_after_utc": sys.argv[4],
    "attempts": json.loads(sys.argv[5]),
    "selected_attempt": 0,
    "response": json.loads(sys.argv[6]) if sys.argv[6] else {},
}
Path(sys.argv[1]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY
    return 1
}

normalize_la_query() {
    local input_file="$1"
    local output_file="$2"
    local query_text="$3"
    local window_start_utc="$4"
    python3 - "${input_file}" "${output_file}" "${query_text}" "${window_start_utc}" <<'PY'
import json
import sys
from pathlib import Path
raw = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
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
    'query': sys.argv[3],
    'window_start_utc': sys.argv[4],
    'window_end_utc': normalized[-1]['TimeGenerated'] if normalized and 'TimeGenerated' in normalized[-1] else sys.argv[4],
    'rows': normalized,
}
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY
}

create_evidence_readme() {
    python3 - <<'PY'
import json
from pathlib import Path

root = Path(__import__('os').environ['EVIDENCE_DIR'])
pre = json.loads(root.joinpath('01-app-spec-pre-fix.json').read_text(encoding='utf-8'))
probe_pre = json.loads(root.joinpath('08-probe-response-pre-fix.json').read_text(encoding='utf-8'))
probe_post = json.loads(root.joinpath('11-probe-response-post-fix.json').read_text(encoding='utf-8'))
post = json.loads(root.joinpath('12-pe-nic-config-post-fix.json').read_text(encoding='utf-8'))
meta = pre['capture_metadata']
post_meta = post['capture_metadata']
text = f'''# Evidence pack — `acr-network-path-record-split-brain` lab

This directory carries the live raw evidence cohort for the `acr-network-path-record-split-brain` lab plus the derived Phase B gate outputs emitted by `labs/acr-network-path-record-split-brain/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what a single live `koreacentral` reproduction can support about Path D with one ACR Private Endpoint NIC, one linked `privatelink.azurecr.io` zone, one deleted regional data A record, one restored regional data A record, and one already-running Container App revision that stayed `Healthy` throughout. It does **not** claim universal applicability across regions, tenants, DNS topologies, or platform versions.

## Reproduction parameters

| Parameter | Value |
|---|---|
| Resource group | `{meta['resource_group']}` |
| Base name | `{meta['base_name']}` |
| Suffix | `{meta['suffix']}` |
| Build tag | `{meta['build_tag']}` |
| Azure region | `{meta['location']}` |
| Registry login FQDN | `{meta['acr_login_server']}` |
| Data FQDN | `{meta['acr_data_fqdn']}` |
| Registry record name | `{meta['registry_record_name']}` |
| Data record name | `{meta['data_record_name']}` |
| Broken probe capture window | `{probe_pre['captured_before_utc']}` → `{probe_pre['captured_after_utc']}` |
| Recovered probe capture window | `{probe_post['captured_before_utc']}` → `{probe_post['captured_after_utc']}` |
| Post-fix composite capture anchor | `{post_meta['post_window_start_utc']}` |

## Capture timeline

1. **H1 failure surface.** `01-app-spec-pre-fix.json` through `08-probe-response-pre-fix.json` capture the broken window after the regional data A record is deleted and the `/probe` endpoint converges on `topology_class=data_nxdomain`.
2. **H2 recovery surface.** `09-private-dns-record-list-post-fix.json` through `12-pe-nic-config-post-fix.json` capture the restored data A record, the unchanged healthy revision, the recovered `/probe` response, and the unchanged PE NIC + ACR + app surface.
3. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, single-window UTC coherence, revision-lineage equality, unchanged PE NIC IP map, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves the data A record is absent, `/probe` returns `data_nxdomain`, the already-running revision stays `Healthy`, and the broken-window pull-failure query stays empty.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves the data A record is restored with the original PE data IP, `/probe` returns `both_private`, and the same revision stays `Healthy` without a new revision.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the full normalized overlapping H1↔H2 diff, isolates the regional data A record as the trigger field, and actively checks the workload-path silence invariant.

## Honest disclosure

- The pack captures one live Azure reproduction in `koreacentral`; it is not a statistical sample.
- `06-system-logs-pre-fix.json` is an explicit Log Analytics query payload whose `rows` list is intentionally empty in the broken window; emptiness is the evidence.
- `08-probe-response-pre-fix.json` and `11-probe-response-post-fix.json` preserve every retry attempt explicitly so the verifier never overclaims instantaneous convergence.
- Gate 14 uses file-system UTC anchors (`birthtime`, falling back to `mtime`) so reruns are byte-stable and explicit about the time source for each file.
- The pack does not prove exact DNS timing, exact retry counts, broken-window control-plane fresh pulls, byte-identical backend HTTP bodies, or TLS cipher-suite identity. Those ceilings are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Pre-fix container app surface plus capture metadata |
| `02-revision-list-pre-fix.json` | Full revision list in the broken window |
| `03-private-dns-record-list-pre-fix.json` | A-record inventory after the regional data A record is deleted |
| `04-pe-nic-config-pre-fix.json` | PE NIC configuration proving the registry/data private IP map |
| `05-acr-public-access-pre-fix.json` | ACR public access snapshot during H1 |
| `06-system-logs-pre-fix.json` | Broken-window pull-failure KQL payload (expected empty row set) |
| `07-containerapp-spec-pre-fix.yaml` | Full pre-fix container app YAML |
| `08-probe-response-pre-fix.json` | Retried `/probe` capture converging on `topology_class=data_nxdomain` |
| `09-private-dns-record-list-post-fix.json` | A-record inventory after the regional data A record is restored |
| `10-revision-list-post-fix.json` | Full revision list after recovery |
| `11-probe-response-post-fix.json` | Retried `/probe` capture converging on `topology_class=both_private` |
| `12-pe-nic-config-post-fix.json` | Composite post-fix app + ACR + PE NIC surface |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/acr-network-path-record-split-brain/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort without touching Azure. |

```bash
cd labs/acr-network-path-record-split-brain/
bash verify.sh
```

The verifier is hermetic: it reads only the committed files in this directory, rewrites the four gate JSONs deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
'''
root.joinpath('README.md').write_text(text, encoding='utf-8')
PY
}

echo "=== Phase 1: ensure resource group exists ==="
if ! az group show --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --output none >/dev/null 2>&1; then
    az group create --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --location "${LOCATION}" --output json > "${SCRATCH_DIR}/rg.json"
fi

echo "=== Phase 2: deploy baseline infra ==="
az deployment group create \
    --subscription "${AZ_SUBSCRIPTION}" \
    --resource-group "${RG}" \
    --name "${DEPLOYMENT_NAME}" \
    --template-file "${SCRIPT_DIR}/infra/main.bicep" \
    --parameters baseName="${BASE_NAME}" location="${LOCATION}" \
    --output json > "${SCRATCH_DIR}/deployment.json"

APP_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.containerAppName.value' --output tsv)"
APP_FQDN="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.containerAppFqdn.value' --output tsv)"
ACR_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.containerRegistryName.value' --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.containerRegistryLoginServer.value' --output tsv)"
ACR_DATA_FQDN="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.containerRegistryDataFqdn.value' --output tsv)"
WORKSPACE_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.logAnalyticsWorkspaceName.value' --output tsv)"
PE_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.privateEndpointName.value' --output tsv)"
VNET_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.vnetName.value' --output tsv)"
ZONE_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.privateDnsZoneName.value' --output tsv)"
WORKSPACE_ID="$(az monitor log-analytics workspace show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --workspace-name "${WORKSPACE_NAME}" --query 'customerId' --output tsv)"
VNET_ID="$(az network vnet show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${VNET_NAME}" --query 'id' --output tsv)"
NIC_ID="$(az network private-endpoint show --subscription "${AZ_SUBSCRIPTION}" --name "${PE_NAME}" --resource-group "${RG}" --query 'networkInterfaces[0].id' --output tsv)"
SUFFIX="${APP_NAME##*-}"
DATA_RECORD_NAME="${ACR_DATA_FQDN%.azurecr.io}"
REGISTRY_RECORD_NAME="${ACR_LOGIN_SERVER%.azurecr.io}"

export APP_NAME APP_FQDN ACR_NAME ACR_LOGIN_SERVER ACR_DATA_FQDN WORKSPACE_NAME PE_NAME VNET_NAME ZONE_NAME WORKSPACE_ID VNET_ID NIC_ID SUFFIX DATA_RECORD_NAME REGISTRY_RECORD_NAME

echo "=== Phase 3: build private image and switch app ==="
IMAGE_TAG="${BUILD_TAG}" RG="${RG}" DEPLOYMENT_NAME="${DEPLOYMENT_NAME}" IMAGE_REPO="${IMAGE_REPO}" IMAGE_TAG="${IMAGE_TAG}" bash "${SCRIPT_DIR}/trigger.sh"
wait_for_revision_healthy "${APP_NAME}" 1200

echo "=== Phase 4: baseline sanity probe ==="
BASELINE_CAPTURE_BEFORE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BASELINE_FILE="${SCRATCH_DIR}/baseline-probe.json"
if ! capture_probe_payload "${APP_FQDN}" "both_private" "${BASELINE_FILE}" "${BASELINE_CAPTURE_BEFORE_UTC}"; then
    echo "Baseline probe did not converge to both_private"
    exit 1
fi

echo "=== Phase 5: break the regional data A record ==="
BASELINE_DATA_IP="$(az network private-dns record-set a show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --zone-name "${ZONE_NAME}" --name "${DATA_RECORD_NAME}" --query 'aRecords[0].ipv4Address' --output tsv)"
az network private-dns record-set a delete --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --zone-name "${ZONE_NAME}" --name "${DATA_RECORD_NAME}" --yes --output none
sleep 90

PRE_KQL_WINDOW_START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRE_PROBE_CAPTURE_BEFORE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if ! capture_probe_payload "${APP_FQDN}" "data_nxdomain" "${EVIDENCE_DIR}/08-probe-response-pre-fix.json" "${PRE_PROBE_CAPTURE_BEFORE_UTC}"; then
    echo "Broken probe did not converge to data_nxdomain"
    exit 1
fi

echo "=== Phase 6: capture H1 evidence ==="
az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${SCRATCH_DIR}/app-pre.json"
python3 - <<'PY'
import json
import os
from pathlib import Path
app = json.loads(Path(f"{os.environ['SCRATCH_DIR']}/app-pre.json").read_text(encoding='utf-8'))
payload = {
    'capture_metadata': {
        'subscription_id': os.environ['AZ_SUBSCRIPTION'],
        'resource_group': os.environ['RG'],
        'base_name': os.environ['BASE_NAME'],
        'suffix': os.environ['SUFFIX'],
        'build_tag': os.environ['BUILD_TAG'],
        'location': os.environ['LOCATION'],
        'acr_login_server': os.environ['ACR_LOGIN_SERVER'],
        'acr_data_fqdn': os.environ['ACR_DATA_FQDN'],
        'zone_name': os.environ['ZONE_NAME'],
        'vnet_id': os.environ['VNET_ID'],
        'registry_record_name': os.environ['REGISTRY_RECORD_NAME'],
        'data_record_name': os.environ['DATA_RECORD_NAME'],
    },
    'container_app': app,
}
Path(os.environ['EVIDENCE_DIR']).joinpath('01-app-spec-pre-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY
az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${EVIDENCE_DIR}/02-revision-list-pre-fix.json"
az network private-dns record-set a list --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --zone-name "${ZONE_NAME}" --output json > "${EVIDENCE_DIR}/03-private-dns-record-list-pre-fix.json"
az network nic show --subscription "${AZ_SUBSCRIPTION}" --ids "${NIC_ID}" --output json > "${EVIDENCE_DIR}/04-pe-nic-config-pre-fix.json"
az acr show --subscription "${AZ_SUBSCRIPTION}" --name "${ACR_NAME}" --resource-group "${RG}" --query '{publicNetworkAccess:publicNetworkAccess,networkRuleSet:networkRuleSet}' --output json > "${EVIDENCE_DIR}/05-acr-public-access-pre-fix.json"
az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output yaml > "${EVIDENCE_DIR}/07-containerapp-spec-pre-fix.yaml"
PRE_KQL_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where TimeGenerated >= todatetime('${PRE_KQL_WINDOW_START_UTC}') | where Reason_s in ('PullingImage','PulledImage','ImagePullUnauthorized','ImagePullFailed','BackOff') | order by TimeGenerated asc | project TimeGenerated, RevisionName_s, ReplicaName_s, Reason_s, Log_s"
az monitor log-analytics query --subscription "${AZ_SUBSCRIPTION}" --workspace "${WORKSPACE_ID}" --analytics-query "${PRE_KQL_QUERY}" --output json > "${SCRATCH_DIR}/pre-kql.json"
normalize_la_query "${SCRATCH_DIR}/pre-kql.json" "${EVIDENCE_DIR}/06-system-logs-pre-fix.json" "${PRE_KQL_QUERY}" "${PRE_KQL_WINDOW_START_UTC}"

echo "=== Phase 7: restore the regional data A record ==="
az network private-dns record-set a create --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --zone-name "${ZONE_NAME}" --name "${DATA_RECORD_NAME}" --output none
az network private-dns record-set a add-record --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --zone-name "${ZONE_NAME}" --record-set-name "${DATA_RECORD_NAME}" --ipv4-address "${BASELINE_DATA_IP}" --output none
sleep 90

POST_PROBE_CAPTURE_BEFORE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if ! capture_probe_payload "${APP_FQDN}" "both_private" "${EVIDENCE_DIR}/11-probe-response-post-fix.json" "${POST_PROBE_CAPTURE_BEFORE_UTC}"; then
    echo "Recovered probe did not converge to both_private"
    exit 1
fi
wait_for_revision_healthy "${APP_NAME}" 600

echo "=== Phase 8: capture H2 evidence ==="
az network private-dns record-set a list --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --zone-name "${ZONE_NAME}" --output json > "${EVIDENCE_DIR}/09-private-dns-record-list-post-fix.json"
az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${EVIDENCE_DIR}/10-revision-list-post-fix.json"
az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${SCRATCH_DIR}/app-post.json"
az acr show --subscription "${AZ_SUBSCRIPTION}" --name "${ACR_NAME}" --resource-group "${RG}" --query '{publicNetworkAccess:publicNetworkAccess,networkRuleSet:networkRuleSet}' --output json > "${SCRATCH_DIR}/acr-post.json"
az network nic show --subscription "${AZ_SUBSCRIPTION}" --ids "${NIC_ID}" --output json > "${SCRATCH_DIR}/nic-post.json"
POST_WINDOW_START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export POST_WINDOW_START_UTC BASELINE_DATA_IP
python3 - <<'PY'
import json
import os
from pathlib import Path
payload = {
    'capture_metadata': {
        'post_window_start_utc': os.environ['POST_WINDOW_START_UTC'],
        'resource_group': os.environ['RG'],
        'base_name': os.environ['BASE_NAME'],
        'suffix': os.environ['SUFFIX'],
        'build_tag': os.environ['BUILD_TAG'],
        'location': os.environ['LOCATION'],
        'baseline_data_ip': os.environ['BASELINE_DATA_IP'],
    },
    'container_app': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/app-post.json").read_text(encoding='utf-8')),
    'acr': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/acr-post.json").read_text(encoding='utf-8')),
    'pe_nic': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/nic-post.json").read_text(encoding='utf-8')),
}
Path(os.environ['EVIDENCE_DIR']).joinpath('12-pe-nic-config-post-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY

create_evidence_readme
sanitize_pii "${EVIDENCE_DIR}"

echo "=== Phase 9: offline verifier ==="
bash "${SCRIPT_DIR}/verify.sh"

echo "=== Phase 10: cleanup Azure resources ==="
az group delete --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --yes --no-wait

echo "Evidence pack captured to ${EVIDENCE_DIR}"
