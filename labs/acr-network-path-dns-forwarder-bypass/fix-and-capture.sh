#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:-$(az account show --query 'id' --output tsv)}"
RG="${RG:-rg-lab-dns-forwarder-bypass-$(date +%Y%m%d%H%M)}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-acrdnsfwdbyp}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-dns-forwarder-bypass}"
IMAGE_REPO="${IMAGE_REPO:-dns-forwarder-bypass-lab}"
BUILD_TAG="${BUILD_TAG:-v1}"
VM_ADMIN_PASSWORD="${VM_ADMIN_PASSWORD:-$(python3 - <<'PY2'
import secrets
print(secrets.token_urlsafe(18) + 'Aa1!')
PY2
)}"

export AZ_SUBSCRIPTION RG LOCATION BASE_NAME DEPLOYMENT_NAME IMAGE_REPO BUILD_TAG EVIDENCE_DIR VM_ADMIN_PASSWORD

rm -f "${EVIDENCE_DIR}/"{01,02,03,04,05,06,07,08,09,10,11,12,14,15,16,17}-* "${EVIDENCE_DIR}/README.md"

SCRATCH_DIR="$(mktemp -d -t acr-dns-forwarder-bypass-phaseb-XXXXXX)"
trap 'rm -rf "${SCRATCH_DIR}"' EXIT
export SCRATCH_DIR

sanitize_pii() {
    python3 - "$1" <<'PY2'
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
    (re.compile(r'https://ms\.portal\.azure\.com/#@[^/]+/', re.I), 'https://ms.portal.azure.com/#@contoso.onmicrosoft.com/'),
    (re.compile(r'https://ms\.portal\.azure\.com[^\s"\']*', re.I), 'https://ms.portal.azure.com/#@contoso.onmicrosoft.com/'),
    (re.compile(r'\b[0-9A-F]{32,}\b'), 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
]
for path in sorted(base.glob('*')):
    if path.is_file():
        text = path.read_text(encoding='utf-8')
        for regex, repl in subs:
            text = regex.sub(repl, text)
        path.write_text(text, encoding='utf-8')
PY2
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
    local expected_first_class="$2"
    local output_file="$3"
    local captured_before_utc="$4"
    local captured_after_utc=""
    local raw_response=""
    local attempts_json="[]"

    for attempt in 1 2 3 4 5; do
        raw_response="$(curl -sS --max-time 30 "https://${app_fqdn}/probe" || true)"
        local valid_json=false
        local first_class=""
        if [ -n "${raw_response}" ] && first_class="$(printf '%s' "${raw_response}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("first_class", ""))' 2>/dev/null || true)" && [ -n "${first_class}" ]; then
            valid_json=true
        fi
        python3 - "${attempts_json}" "${attempt}" "${valid_json}" "${first_class}" "${raw_response}" > "${SCRATCH_DIR}/probe-attempts.json" <<'PY2'
import json
import sys
attempts = json.loads(sys.argv[1])
attempt = int(sys.argv[2])
valid = sys.argv[3] == 'true'
first_class = sys.argv[4]
raw = sys.argv[5]
item = {'attempt': attempt, 'valid_json': valid, 'raw_response': raw}
if valid:
    try:
        item['response'] = json.loads(raw)
    except json.JSONDecodeError:
        item['response'] = None
else:
    item['response'] = None
item['first_class'] = first_class or None
attempts.append(item)
print(json.dumps(attempts))
PY2
        attempts_json="$(cat "${SCRATCH_DIR}/probe-attempts.json")"
        if [ "${valid_json}" = true ] && [ "${first_class}" = "${expected_first_class}" ]; then
            captured_after_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            python3 - "${output_file}" "${expected_first_class}" "${captured_before_utc}" "${captured_after_utc}" "${attempts_json}" "${attempt}" "${raw_response}" <<'PY2'
import json
import sys
from pathlib import Path
payload = {
    'expected_first_class': sys.argv[2],
    'captured_before_utc': sys.argv[3],
    'captured_after_utc': sys.argv[4],
    'attempts': json.loads(sys.argv[5]),
    'selected_attempt': int(sys.argv[6]),
    'response': json.loads(sys.argv[7]),
}
Path(sys.argv[1]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY2
            return 0
        fi
        sleep 20
    done

    captured_after_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    python3 - "${output_file}" "${expected_first_class}" "${captured_before_utc}" "${captured_after_utc}" "${attempts_json}" "${raw_response}" <<'PY2'
import json
import sys
from pathlib import Path
payload = {
    'expected_first_class': sys.argv[2],
    'captured_before_utc': sys.argv[3],
    'captured_after_utc': sys.argv[4],
    'attempts': json.loads(sys.argv[5]),
    'selected_attempt': 0,
    'response': json.loads(sys.argv[6]) if sys.argv[6] else {},
}
Path(sys.argv[1]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY2
    return 1
}

run_on_vm_json() {
    local guest_script="$1"
    local output_file="$2"
    az vm run-command invoke \
        --subscription "${AZ_SUBSCRIPTION}" \
        --resource-group "${RG}" \
        --name "${DNS_VM_NAME}" \
        --command-id RunShellScript \
        --scripts "${guest_script}" \
        --output json > "${output_file}"
}

capture_dnsmasq_state() {
    local output_file="$1"
    local phase="$2"
    local command_output="${SCRATCH_DIR}/dnsmasq-${phase}-raw.json"
    local guest_script="set -eu; printf 'config_path=/etc/dnsmasq.d/acr-lab.conf\n'; grep -nE '^server=' /etc/dnsmasq.d/acr-lab.conf; printf 'resolved_upstream='; sed -n 's/^server=//p' /etc/dnsmasq.d/acr-lab.conf | head -n 1; printf 'service_state='; systemctl is-active dnsmasq; printf 'listen_address='; sed -n 's/^listen-address=//p' /etc/dnsmasq.d/acr-lab.conf | head -n 1"
    run_on_vm_json "${guest_script}" "${command_output}"
    python3 - "${command_output}" "${output_file}" "${phase}" "${DNS_VM_NAME}" <<'PY2'
import json
import re
import sys
from pathlib import Path
raw = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
message = (((raw.get('value') or [{}])[0]).get('message')) or ''
lines = [line.strip() for line in message.splitlines() if line.strip()]
def extract(prefix):
    for line in lines:
        if line.startswith(prefix):
            return line.split('=', 1)[1]
    return None
payload = {
    'phase': sys.argv[3],
    'vm_name': sys.argv[4],
    'resolved_upstream': extract('resolved_upstream='),
    'service_state': extract('service_state='),
    'listen_address': extract('listen_address='),
    'config_path': extract('config_path='),
    'server_lines': [line for line in lines if re.match(r'^\d+:server=', line)],
    'run_command': raw,
}
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY2
}

normalize_la_query() {
    local input_file="$1"
    local output_file="$2"
    local query_text="$3"
    local window_start_utc="$4"
    local window_end_utc="$5"
    python3 - "${input_file}" "${output_file}" "${query_text}" "${window_start_utc}" "${window_end_utc}" <<'PY2'
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
    'window_end_utc': sys.argv[5],
    'rows': normalized,
}
Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY2
}

create_evidence_readme() {
    python3 - <<'PY2'
import json
from pathlib import Path
import os

root = Path(os.environ['EVIDENCE_DIR'])
pre = json.loads(root.joinpath('01-app-spec-pre-fix.json').read_text(encoding='utf-8'))
dns_pre = json.loads(root.joinpath('03-dnsmasq-config-pre-fix.json').read_text(encoding='utf-8'))
probe_pre = json.loads(root.joinpath('08-probe-response-pre-fix.json').read_text(encoding='utf-8'))
dns_post = json.loads(root.joinpath('09-dnsmasq-config-post-fix.json').read_text(encoding='utf-8'))
post = json.loads(root.joinpath('12-recovery-surface-post-fix.json').read_text(encoding='utf-8'))
probe_post = post['probe_capture']
meta = pre['capture_metadata']
post_meta = post['capture_metadata']
text = f'''# Evidence pack — `acr-network-path-dns-forwarder-bypass` lab

This directory carries the live raw evidence cohort for the `acr-network-path-dns-forwarder-bypass` lab plus the derived Phase B gate outputs emitted by `labs/acr-network-path-dns-forwarder-bypass/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what a single live `koreacentral` reproduction can support about Path E with one custom dnsmasq forwarder VM, one linked `privatelink.azurecr.io` zone, one ACR Private Endpoint NIC, one upstream swap from Azure DNS to public DNS, one recovery swap back to Azure DNS, and one already-running Container App revision that stayed `Healthy` throughout. It does **not** claim universal applicability across regions, tenants, DNS topologies, or platform versions.

## Reproduction parameters

| Parameter | Value |
|---|---|
| Resource group | `{meta['resource_group']}` |
| Base name | `{meta['base_name']}` |
| Suffix | `{meta['suffix']}` |
| Build tag | `{meta['build_tag']}` |
| Azure region | `{meta['location']}` |
| Registry login FQDN | `{meta['acr_login_server']}` |
| Private DNS zone | `{meta['zone_name']}` |
| dnsmasq VM | `{meta['dns_vm_name']}` |
| dnsmasq VM private IP | `{meta['dns_vm_private_ip']}` |
| Broken probe capture window | `{probe_pre['captured_before_utc']}` → `{probe_pre['captured_after_utc']}` |
| Recovered probe capture window | `{probe_post['captured_before_utc']}` → `{probe_post['captured_after_utc']}` |
| Broken upstream | `{dns_pre['resolved_upstream']}` |
| Restored upstream | `{dns_post['resolved_upstream']}` |
| Post-fix composite capture anchor | `{post_meta['post_window_start_utc']}` |

## Capture timeline

1. **Baseline sanity.** `fix-and-capture.sh` confirms `/probe` returns `first_class=private` before H1; this baseline is intentionally not committed because the canonical 12-file pack centers the H1/H2 contrast.
2. **H1 failure surface.** `01-app-spec-pre-fix.json` through `08-probe-response-pre-fix.json` capture the broken window after dnsmasq is switched to `server=8.8.8.8` and the workload `/probe` converges on `first_class=public`.
3. **H2 recovery surface.** `09-dnsmasq-config-post-fix.json` through `12-recovery-surface-post-fix.json` capture the restored dnsmasq upstream, unchanged DNS/PE/app surface, and the recovered `/probe` response returning `first_class=private`.
4. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, single-window UTC coherence, revision-lineage equality, unchanged PE NIC + Private DNS surfaces, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves dnsmasq really pointed at `8.8.8.8`, `/probe` returned `first_class=public`, the already-running revision stayed `Healthy`, and the H1+H2 failure-event query stayed empty.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves dnsmasq was restored to `168.63.129.16`, `/probe` returned `first_class=private` again, and the same revision stayed `Healthy` with no new revision created during the lab.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the full normalized overlapping H1↔H2 diff, isolates `dnsmasq_upstream` + `first_class` as the trigger fields, and actively checks the workload-path silence invariant.

## Honest disclosure

- The pack captures one live Azure reproduction in `koreacentral`; it is not a statistical sample.
- `07-system-logs-pre-fix.json` is an explicit Log Analytics query payload whose `rows` list is intentionally empty across the H1+H2 window; emptiness is the evidence.
- `08-probe-response-pre-fix.json` and `12-recovery-surface-post-fix.json.probe_capture` preserve every retry attempt explicitly so the verifier never overclaims instantaneous convergence.
- Gate 14 uses file-system UTC anchors (`birthtime`, falling back to `mtime`) so reruns are byte-stable and explicit about the time source for each file.
- The pack does not prove exact DNS timing, exact retry counts, broken-window control-plane fresh pulls, byte-identical backend HTTP bodies, or TLS cipher-suite identity. Those ceilings are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Pre-fix container app surface plus capture metadata |
| `02-revision-list-pre-fix.json` | Full revision list in the broken window |
| `03-dnsmasq-config-pre-fix.json` | Broken-window dnsmasq upstream capture from the VM |
| `04-private-dns-record-list-pre-fix.json` | Private DNS A-record inventory during H1 |
| `05-pe-nic-config-pre-fix.json` | PE NIC configuration proving the registry/data private IP map |
| `06-acr-public-access-pre-fix.json` | ACR public access snapshot during H1 |
| `07-system-logs-pre-fix.json` | H1+H2 failure-event KQL payload (expected empty row set) |
| `08-probe-response-pre-fix.json` | Retried `/probe` capture converging on `first_class=public` |
| `09-dnsmasq-config-post-fix.json` | Recovery-state dnsmasq upstream capture from the VM |
| `10-private-dns-record-list-post-fix.json` | Private DNS A-record inventory after recovery |
| `11-revision-list-post-fix.json` | Full revision list after recovery |
| `12-recovery-surface-post-fix.json` | Composite post-fix app + ACR + PE NIC + probe surface |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/acr-network-path-dns-forwarder-bypass/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort without touching Azure. |

```bash
cd labs/acr-network-path-dns-forwarder-bypass/
bash verify.sh
```

The verifier is hermetic: it reads only the committed files in this directory, rewrites the four gate JSONs deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
'''
root.joinpath('README.md').write_text(text, encoding='utf-8')
PY2
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
    --parameters baseName="${BASE_NAME}" location="${LOCATION}" vmAdminPassword="${VM_ADMIN_PASSWORD}" \
    --output json > "${SCRATCH_DIR}/deployment.json"

APP_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.containerAppName.value' --output tsv)"
APP_FQDN="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.containerAppFqdn.value' --output tsv)"
ACR_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.containerRegistryName.value' --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.containerRegistryLoginServer.value' --output tsv)"
WORKSPACE_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.logAnalyticsWorkspaceName.value' --output tsv)"
PE_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.privateEndpointName.value' --output tsv)"
VNET_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.vnetName.value' --output tsv)"
ZONE_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.privateDnsZoneName.value' --output tsv)"
DNS_VM_NAME="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.dnsVmName.value' --output tsv)"
DNS_VM_PRIVATE_IP="$(az deployment group show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${DEPLOYMENT_NAME}" --query 'properties.outputs.dnsVmPrivateIp.value' --output tsv)"
WORKSPACE_ID="$(az monitor log-analytics workspace show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --workspace-name "${WORKSPACE_NAME}" --query 'customerId' --output tsv)"
VNET_ID="$(az network vnet show --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --name "${VNET_NAME}" --query 'id' --output tsv)"
NIC_ID="$(az network private-endpoint show --subscription "${AZ_SUBSCRIPTION}" --name "${PE_NAME}" --resource-group "${RG}" --query 'networkInterfaces[0].id' --output tsv)"
SUFFIX="${APP_NAME##*-}"
REGISTRY_RECORD_NAME="${ACR_LOGIN_SERVER%.azurecr.io}"
DATA_RECORD_NAME="${ACR_LOGIN_SERVER%.azurecr.io}.${LOCATION}.data"

export APP_NAME APP_FQDN ACR_NAME ACR_LOGIN_SERVER WORKSPACE_NAME PE_NAME VNET_NAME ZONE_NAME DNS_VM_NAME DNS_VM_PRIVATE_IP WORKSPACE_ID VNET_ID NIC_ID SUFFIX REGISTRY_RECORD_NAME DATA_RECORD_NAME

echo "=== Phase 3: build private image and switch app ==="
if ! IMAGE_TAG="${BUILD_TAG}" RG="${RG}" DEPLOYMENT_NAME="${DEPLOYMENT_NAME}" IMAGE_REPO="${IMAGE_REPO}" IMAGE_TAG="${IMAGE_TAG}" bash "${SCRIPT_DIR}/trigger.sh"; then
    echo "Initial trigger.sh attempt failed; retrying once after 30 seconds"
    sleep 30
    IMAGE_TAG="${BUILD_TAG}" RG="${RG}" DEPLOYMENT_NAME="${DEPLOYMENT_NAME}" IMAGE_REPO="${IMAGE_REPO}" IMAGE_TAG="${IMAGE_TAG}" bash "${SCRIPT_DIR}/trigger.sh"
fi
wait_for_revision_healthy "${APP_NAME}" 1200

echo "=== Phase 4: baseline sanity probe ==="
BASELINE_CAPTURE_BEFORE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BASELINE_FILE="${SCRATCH_DIR}/baseline-probe.json"
if ! capture_probe_payload "${APP_FQDN}" "private" "${BASELINE_FILE}" "${BASELINE_CAPTURE_BEFORE_UTC}"; then
    echo "Baseline probe did not converge to private"
    exit 1
fi

PE_REGISTRY_IP="$(az network nic show --subscription "${AZ_SUBSCRIPTION}" --ids "${NIC_ID}" --query "ipConfigurations[?contains(to_string(privateLinkConnectionProperties.fqdns), '${ACR_LOGIN_SERVER}')] | [0].privateIPAddress" --output tsv)"
PE_DATA_IP="$(az network nic show --subscription "${AZ_SUBSCRIPTION}" --ids "${NIC_ID}" --query "ipConfigurations[?contains(to_string(privateLinkConnectionProperties.fqdns), '${ACR_LOGIN_SERVER}.${LOCATION}.data.azurecr.io')] | [0].privateIPAddress" --output tsv)"
export PE_REGISTRY_IP PE_DATA_IP

capture_dnsmasq_state "${SCRATCH_DIR}/dnsmasq-baseline.json" "baseline"
H_WINDOW_START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{\n  "query": null,\n  "window_start_utc": "%s",\n  "window_end_utc": null,\n  "rows": []\n}\n' "${H_WINDOW_START_UTC}" > "${EVIDENCE_DIR}/07-system-logs-pre-fix.json"

echo "=== Phase 5: trigger H1 by swapping dnsmasq upstream to 8.8.8.8 ==="
run_on_vm_json "set -eu; sudo sed -i 's|^server=168.63.129.16$|server=8.8.8.8|' /etc/dnsmasq.d/acr-lab.conf; sudo systemctl restart dnsmasq; grep -E '^server=' /etc/dnsmasq.d/acr-lab.conf" "${SCRATCH_DIR}/dnsmasq-h1-swap.json"
sleep 90
capture_dnsmasq_state "${EVIDENCE_DIR}/03-dnsmasq-config-pre-fix.json" "broken"
PRE_PROBE_CAPTURE_BEFORE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if ! capture_probe_payload "${APP_FQDN}" "public" "${EVIDENCE_DIR}/08-probe-response-pre-fix.json" "${PRE_PROBE_CAPTURE_BEFORE_UTC}"; then
    echo "Broken probe did not converge to public"
    exit 1
fi

echo "=== Phase 6: capture H1 evidence ==="
az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${SCRATCH_DIR}/app-pre.json"
python3 - <<'PY2'
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
        'zone_name': os.environ['ZONE_NAME'],
        'vnet_id': os.environ['VNET_ID'],
        'registry_record_name': os.environ['REGISTRY_RECORD_NAME'],
        'data_record_name': os.environ['DATA_RECORD_NAME'],
        'dns_vm_name': os.environ['DNS_VM_NAME'],
        'dns_vm_private_ip': os.environ['DNS_VM_PRIVATE_IP'],
        'pe_registry_ip': os.environ['PE_REGISTRY_IP'],
        'pe_data_ip': os.environ['PE_DATA_IP'],
    },
    'container_app': app,
}
Path(os.environ['EVIDENCE_DIR']).joinpath('01-app-spec-pre-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY2
az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${EVIDENCE_DIR}/02-revision-list-pre-fix.json"
az network private-dns record-set a list --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --zone-name "${ZONE_NAME}" --output json > "${EVIDENCE_DIR}/04-private-dns-record-list-pre-fix.json"
az network nic show --subscription "${AZ_SUBSCRIPTION}" --ids "${NIC_ID}" --output json > "${EVIDENCE_DIR}/05-pe-nic-config-pre-fix.json"
az acr show --subscription "${AZ_SUBSCRIPTION}" --name "${ACR_NAME}" --resource-group "${RG}" --query '{publicNetworkAccess:publicNetworkAccess,networkRuleSet:networkRuleSet}' --output json > "${EVIDENCE_DIR}/06-acr-public-access-pre-fix.json"

echo "=== Phase 7: trigger H2 by restoring dnsmasq upstream to 168.63.129.16 ==="
run_on_vm_json "set -eu; sudo sed -i 's|^server=8.8.8.8$|server=168.63.129.16|' /etc/dnsmasq.d/acr-lab.conf; sudo systemctl restart dnsmasq; grep -E '^server=' /etc/dnsmasq.d/acr-lab.conf" "${SCRATCH_DIR}/dnsmasq-h2-restore.json"
sleep 90
capture_dnsmasq_state "${EVIDENCE_DIR}/09-dnsmasq-config-post-fix.json" "recovered"
POST_PROBE_CAPTURE_BEFORE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
POST_PROBE_FILE="${SCRATCH_DIR}/probe-post.json"
if ! capture_probe_payload "${APP_FQDN}" "private" "${POST_PROBE_FILE}" "${POST_PROBE_CAPTURE_BEFORE_UTC}"; then
    echo "Recovered probe did not converge to private"
    exit 1
fi
wait_for_revision_healthy "${APP_NAME}" 600
H_WINDOW_END_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "=== Phase 8: capture H2 evidence ==="
az network private-dns record-set a list --subscription "${AZ_SUBSCRIPTION}" --resource-group "${RG}" --zone-name "${ZONE_NAME}" --output json > "${EVIDENCE_DIR}/10-private-dns-record-list-post-fix.json"
az containerapp revision list --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${EVIDENCE_DIR}/11-revision-list-post-fix.json"
az containerapp show --subscription "${AZ_SUBSCRIPTION}" --name "${APP_NAME}" --resource-group "${RG}" --output json > "${SCRATCH_DIR}/app-post.json"
az acr show --subscription "${AZ_SUBSCRIPTION}" --name "${ACR_NAME}" --resource-group "${RG}" --query '{publicNetworkAccess:publicNetworkAccess,networkRuleSet:networkRuleSet}' --output json > "${SCRATCH_DIR}/acr-post.json"
az network nic show --subscription "${AZ_SUBSCRIPTION}" --ids "${NIC_ID}" --output json > "${SCRATCH_DIR}/nic-post.json"
POST_WINDOW_START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export POST_WINDOW_START_UTC H_WINDOW_START_UTC H_WINDOW_END_UTC PE_REGISTRY_IP PE_DATA_IP
PRE_KQL_QUERY="ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where TimeGenerated between (todatetime('${H_WINDOW_START_UTC}') .. todatetime('${H_WINDOW_END_UTC}')) | where Reason_s in ('ImagePullFailed','ImagePullUnauthorized','BackOff','RevisionFailed','ReplicaFailed') | order by TimeGenerated asc | project TimeGenerated, RevisionName_s, ReplicaName_s, Reason_s, Log_s"
az monitor log-analytics query --subscription "${AZ_SUBSCRIPTION}" --workspace "${WORKSPACE_ID}" --analytics-query "${PRE_KQL_QUERY}" --output json > "${SCRATCH_DIR}/pre-kql.json"
normalize_la_query "${SCRATCH_DIR}/pre-kql.json" "${EVIDENCE_DIR}/07-system-logs-pre-fix.json" "${PRE_KQL_QUERY}" "${H_WINDOW_START_UTC}" "${H_WINDOW_END_UTC}"
python3 - <<'PY2'
import json
import os
from pathlib import Path
payload = {
    'capture_metadata': {
        'post_window_start_utc': os.environ['POST_WINDOW_START_UTC'],
        'h_window_start_utc': os.environ['H_WINDOW_START_UTC'],
        'h_window_end_utc': os.environ['H_WINDOW_END_UTC'],
        'resource_group': os.environ['RG'],
        'base_name': os.environ['BASE_NAME'],
        'suffix': os.environ['SUFFIX'],
        'build_tag': os.environ['BUILD_TAG'],
        'location': os.environ['LOCATION'],
        'pe_registry_ip': os.environ['PE_REGISTRY_IP'],
        'pe_data_ip': os.environ['PE_DATA_IP'],
    },
    'container_app': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/app-post.json").read_text(encoding='utf-8')),
    'acr': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/acr-post.json").read_text(encoding='utf-8')),
    'pe_nic': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/nic-post.json").read_text(encoding='utf-8')),
    'dnsmasq_post': json.loads(Path(os.environ['EVIDENCE_DIR']).joinpath('09-dnsmasq-config-post-fix.json').read_text(encoding='utf-8')),
    'probe_capture': json.loads(Path(f"{os.environ['SCRATCH_DIR']}/probe-post.json").read_text(encoding='utf-8')),
}
Path(os.environ['EVIDENCE_DIR']).joinpath('12-recovery-surface-post-fix.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
PY2

create_evidence_readme
sanitize_pii "${EVIDENCE_DIR}"

echo "=== Phase 9: cleanup Azure resources immediately after capture ==="
az group delete --subscription "${AZ_SUBSCRIPTION}" --name "${RG}" --yes --no-wait

echo "=== Phase 10: offline verifier ==="
bash "${SCRIPT_DIR}/verify.sh"

echo "Evidence pack captured to ${EVIDENCE_DIR}"
