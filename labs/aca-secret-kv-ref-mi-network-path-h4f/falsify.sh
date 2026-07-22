#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set (same value used by trigger.sh)}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$LAB_DIR/evidence"

if [[ ! -f "$EVIDENCE_DIR/01-deployment-outputs.json" ]]; then
    echo "ERROR: evidence/01-deployment-outputs.json not found. Run trigger.sh first."
    exit 1
fi
if [[ ! -f "$EVIDENCE_DIR/04-h0-secret-set-outcome.json" ]]; then
    echo "ERROR: evidence/04-h0-secret-set-outcome.json not found. Run trigger.sh first."
    exit 1
fi

H0_EXIT="$(jq -r .exit_code "$EVIDENCE_DIR/04-h0-secret-set-outcome.json")"
if [[ "$H0_EXIT" != "0" ]]; then
    echo "ERROR: H0 baseline did NOT succeed (exit=$H0_EXIT)."
    exit 1
fi

extract_embedded_json() {
    python3 - <<'PY' "$1"
import sys
text = sys.argv[1]
start = text.find('{')
end = text.rfind('}')
if start == -1 or end == -1 or end < start:
    raise SystemExit('could not locate JSON payload in run-command output')
print(text[start:end + 1])
PY
}

run_on_nva_json() {
    local vm_name="$1"
    local guest_script="$2"
    local raw_message
    raw_message="$(az vm run-command invoke \
        --resource-group "$RG" \
        --name "$vm_name" \
        --command-id RunShellScript \
        --scripts "$guest_script" \
        --query 'value[0].message' \
        --output tsv)"
    extract_embedded_json "$raw_message"
}

capture_app_state_snapshot() {
    local expected_secret_name="$1"
    local expected_secret_present="$2"
    local app_json
    app_json="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --output json)"
    local latest_rev
    latest_rev="$(echo "$app_json" | jq -r .properties.latestReadyRevisionName)"
    local rev_unchanged="false"
    if [[ "$latest_rev" == "$LATEST_REV_BASELINE" ]]; then
        rev_unchanged="true"
    fi
    local http_code="000"
    if [[ -n "$APP_FQDN" && "$APP_FQDN" != "null" ]]; then
        for _ in 1 2 3; do
            : "$_"
            http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "https://$APP_FQDN/" 2>/dev/null || echo "000")"
            if [[ "$http_code" == "200" ]]; then
                break
            fi
            sleep 5
        done
    fi
    local secrets_json
    secrets_json="$(echo "$app_json" | jq '.properties.configuration.secrets // []')"
    local secret_present_count
    secret_present_count="$(echo "$secrets_json" | jq --arg n "$expected_secret_name" 'map(select(.name == $n)) | length')"
    local secret_present_bool="false"
    if [[ "${secret_present_count:-0}" -gt 0 ]]; then
        secret_present_bool="true"
    fi
    local expectation_met="false"
    if [[ "$secret_present_bool" == "$expected_secret_present" ]]; then
        expectation_met="true"
    fi
    cat <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "resource_group": "$RESOURCE_GROUP",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BASELINE",
  "app_name": "$APP_NAME",
  "latest_ready_revision_name": "$latest_rev",
  "latest_revision_unchanged_vs_baseline": $rev_unchanged,
  "ingress_probe_http_code": "$http_code",
  "expected_secret_name": "$expected_secret_name",
  "expected_secret_present": $expected_secret_present,
  "observed_secret_present": $secret_present_bool,
  "observed_secret_present_count": ${secret_present_count:-0},
  "secret_presence_expectation_met": $expectation_met,
  "secrets_snapshot": $secrets_json
}
EOF
}

probe_host_from_workload() {
    local host="$1"
    local expected_outcome="$2"
    local stdout_file
    local stderr_file
    local exit_code=0
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    az containerapp exec \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --command "sh -lc 'curl -4 -I -sS --connect-timeout 10 --max-time 15 https://${host}/'" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
    python3 - <<'PY' "$host" "$expected_outcome" "$exit_code" "$stdout_file" "$stderr_file"
import json
import pathlib
import sys
payload = {
    'host': sys.argv[1],
    'expected_outcome': sys.argv[2],
    'exit_code': int(sys.argv[3]),
    'stdout': pathlib.Path(sys.argv[4]).read_text(encoding='utf-8'),
    'stderr': pathlib.Path(sys.argv[5]).read_text(encoding='utf-8'),
}
payload['outcome'] = 'success' if payload['exit_code'] == 0 else 'failure'
print(json.dumps(payload))
PY
    rm -f "$stdout_file" "$stderr_file"
}

capture_nva_rule_and_workload_probe() {
    local phase="$1"
    local expected_rule_present="$2"
    local expected_probe_outcome="$3"
    local output_file="$4"
    local nva_rule_state_json
    local login_msonline_probe_json
    local login_ms_probe_json
    nva_rule_state_json="$(run_on_nva_json "$NVA_VM_NAME" "set -euo pipefail; python3 - <<'PY'
import json
import subprocess

def run(*cmd):
    return subprocess.check_output(cmd, text=True)

chain = json.loads(run('sudo', 'nft', '-j', 'list', 'chain', 'inet', 'h4f', 'forward'))
rules = chain.get('nftables', [])
target = None
for item in rules:
    rule = item.get('rule')
    if not rule:
        continue
    comment = rule.get('comment')
    if comment == 'h4f-drop-entra-443':
        target = rule
        break

payload = {
    'rule_present': target is not None,
    'rule_handle': target.get('handle') if target else None,
    'rule_comment': target.get('comment') if target else None,
    'rule_counter': target.get('counter') if target else None,
    'forward_chain': chain,
}
print(json.dumps(payload))
PY")"
    login_msonline_probe_json="$(probe_host_from_workload 'login.microsoftonline.com' "$expected_probe_outcome")"
    login_ms_probe_json="$(probe_host_from_workload 'login.microsoft.com' "$expected_probe_outcome")"
    cat > "$EVIDENCE_DIR/$output_file" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "resource_group": "$RESOURCE_GROUP",
  "app_name": "$APP_NAME",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BASELINE",
  "nva_vm_name": "$NVA_VM_NAME",
  "nva_private_ip": "$NVA_PRIVATE_IP",
  "route_table_default_route": $ROUTE_JSON,
  "expected_rule_present": $expected_rule_present,
  "expected_probe_outcome": "$expected_probe_outcome",
  "nva_rule_state": $nva_rule_state_json,
  "workload_probe": {
    "login.microsoftonline.com": $login_msonline_probe_json,
    "login.microsoft.com": $login_ms_probe_json
  }
}
EOF
}

APP_NAME="$(jq -r .app_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
RESOURCE_GROUP="$(jq -r .resource_group "$EVIDENCE_DIR/01-deployment-outputs.json")"
ENVIRONMENT_NAME="$(jq -r .environment_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_NAME="$(jq -r .key_vault_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_URI="$(jq -r .key_vault_uri "$EVIDENCE_DIR/01-deployment-outputs.json")"
APP_PRINCIPAL_ID="$(jq -r .app_principal_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
TENANT_ID="$(jq -r .tenant_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
LOCATION="$(jq -r .location "$EVIDENCE_DIR/01-deployment-outputs.json")"
NVA_VM_NAME="$(jq -r .nva_vm_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
NVA_PRIVATE_IP="$(jq -r .nva_private_ip "$EVIDENCE_DIR/01-deployment-outputs.json")"
ROUTE_JSON="$(jq -c .route_table_default_route "$EVIDENCE_DIR/01-deployment-outputs.json")"
LATEST_REV_BASELINE="$(jq -r .latest_ready_revision_name "$EVIDENCE_DIR/05-h0-app-state-after.json")"
APP_FQDN="$(jq -r .ingress_fqdn "$EVIDENCE_DIR/02-h0-app-state-before.json")"

echo "falsify.sh started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  RG                = $RG"
echo "  APP_NAME          = $APP_NAME"
echo "  KV_NAME           = $KV_NAME"
echo "  NVA_VM_NAME       = $NVA_VM_NAME"
echo "  NVA_PRIVATE_IP    = $NVA_PRIVATE_IP"
echo ""

echo "[H1] step 1: resolving AzureActiveDirectory service-tag prefixes in $LOCATION"
SERVICE_TAGS_JSON="$(az network list-service-tags --location "$LOCATION" --output json)"
AAD_PREFIXES_JSON="$(echo "$SERVICE_TAGS_JSON" | jq '[.values[] | select(.name == "AzureActiveDirectory") | .properties.addressPrefixes[] | select(type == "string") | select(test(":") | not)] | unique')"
AAD_PREFIX_COUNT="$(echo "$AAD_PREFIXES_JSON" | jq 'length')"
if [[ "$AAD_PREFIX_COUNT" -lt 1 ]]; then
    echo "FAIL (H1): AzureActiveDirectory service tag did not return any IPv4 prefixes in $LOCATION."
    exit 1
fi
AAD_PREFIXES_B64="$(printf '%s' "$AAD_PREFIXES_JSON" | base64 | tr -d '\n')"

echo "[H1] step 2: installing the single nftables forwarding-plane DROP rule on the NVA surrogate"
H1_INSTALL_JSON="$(run_on_nva_json "$NVA_VM_NAME" "set -euo pipefail; PREFIXES_B64='$AAD_PREFIXES_B64' python3 - <<'PY'
import base64
import json
import os
import subprocess
import tempfile

prefixes = json.loads(base64.b64decode(os.environ['PREFIXES_B64']).decode())

def run(*cmd):
    return subprocess.check_output(cmd, text=True)

def run_ok(*cmd):
    subprocess.run(cmd, check=True)

chain = json.loads(run('sudo', 'nft', '-j', 'list', 'chain', 'inet', 'h4f', 'forward'))
for item in chain.get('nftables', []):
    rule = item.get('rule')
    if rule and rule.get('comment') == 'h4f-drop-entra-443':
        run_ok('sudo', 'nft', 'delete', 'rule', 'inet', 'h4f', 'forward', 'handle', str(rule['handle']))

subprocess.run(['sudo', 'nft', 'list', 'set', 'inet', 'h4f', 'aad_h4f_v4'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if subprocess.run(['sudo', 'nft', 'list', 'set', 'inet', 'h4f', 'aad_h4f_v4'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
    run_ok('sudo', 'nft', 'flush', 'set', 'inet', 'h4f', 'aad_h4f_v4')
else:
    run_ok('sudo', 'nft', 'add', 'set', 'inet', 'h4f', 'aad_h4f_v4', '{', 'type', 'ipv4_addr', ';', 'flags', 'interval', ';', '}')
if prefixes:
    run_ok('sudo', 'nft', 'add', 'element', 'inet', 'h4f', 'aad_h4f_v4', '{', ', '.join(prefixes), '}')
run_ok('sudo', 'nft', 'insert', 'rule', 'inet', 'h4f', 'forward', 'ip', 'daddr', '@aad_h4f_v4', 'tcp', 'dport', '443', 'counter', 'drop', 'comment', 'h4f-drop-entra-443')
chain_after = json.loads(run('sudo', 'nft', '-j', 'list', 'chain', 'inet', 'h4f', 'forward'))
target = None
for item in chain_after.get('nftables', []):
    rule = item.get('rule')
    if rule and rule.get('comment') == 'h4f-drop-entra-443':
        target = rule
        break
payload = {
    'action': 'install-drop-rule',
    'dest_prefix_count': len(prefixes),
    'dest_prefixes': prefixes,
    'rule_present': target is not None,
    'rule_handle': target.get('handle') if target else None,
    'rule_comment': target.get('comment') if target else None,
    'counter_before_probe': target.get('counter') if target else None,
    'forward_chain': chain_after,
}
print(json.dumps(payload))
PY")"

cat > "$EVIDENCE_DIR/06-h1-nva-drop-rule-installed.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "action": "install-nftables-drop-rule-for-entra-service-tag-prefixes",
  "resource_group": "$RESOURCE_GROUP",
  "app_name": "$APP_NAME",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BASELINE",
  "nva_vm_name": "$NVA_VM_NAME",
  "nva_private_ip": "$NVA_PRIVATE_IP",
  "route_table_default_route": $ROUTE_JSON,
  "azure_active_directory_service_tag": {
    "location": "$LOCATION",
    "targeting_mode": "service_tag_ipv4_prefixes",
    "prefix_count": $AAD_PREFIX_COUNT,
    "prefixes": $AAD_PREFIXES_JSON
  },
  "nva_rule_installation": $H1_INSTALL_JSON
}
EOF
echo "  wrote evidence/06-h1-nva-drop-rule-installed.json"

SECRET_NAME_H1="kvref-h1-value"
SECRET_VALUE_H1="h1-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H1] step 3: creating KV secret '$SECRET_NAME_H1'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H1" --value "$SECRET_VALUE_H1" --output none
KV_SECRET_URL_H1="${KV_URI}secrets/${SECRET_NAME_H1}"

H1_SECRET_REF_NAME="kvref-h1"
echo "[H1] step 4: attempting 'az containerapp secret set --secrets ...identityref:system' (MUST FAIL)"
SET_STDOUT_FILE="$(mktemp)"
SET_STDERR_FILE="$(mktemp)"
SET_EXIT=0
az containerapp secret set \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --secrets "${H1_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H1},identityref:system" \
    --output json >"$SET_STDOUT_FILE" 2>"$SET_STDERR_FILE" || SET_EXIT=$?
SET_STDOUT="$(cat "$SET_STDOUT_FILE")"
SET_STDERR="$(cat "$SET_STDERR_FILE")"
rm -f "$SET_STDOUT_FILE" "$SET_STDERR_FILE"

# NOTE: exact production stderr is PENDING a real deployment run and must not be
# asserted verbatim. H4f classifies (managed-identity clue OR OIDC clue) AND
# (network / timeout / connection clue) instead.
MI_OR_OIDC_CLUES_JSON="$(STDERR_TEXT="$SET_STDERR" python3 - <<'PY'
import json
import os
text = os.environ.get('STDERR_TEXT', '').lower()
clues = [
    'failed to update secrets',
    'unable to get value using managed identity',
    'openid-configuration',
    'openid connect',
    'login.microsoftonline.com',
]
print(json.dumps([c for c in clues if c in text]))
PY
)"
NETWORK_CLUES_JSON="$(STDERR_TEXT="$SET_STDERR" python3 - <<'PY'
import json
import os
text = os.environ.get('STDERR_TEXT', '').lower()
clues = [
    'timeout',
    'timed out',
    'connection reset',
    'connection refused',
    'eof',
    'no such host',
    'temporary failure in name resolution',
    'dial tcp',
    'i/o timeout',
]
print(json.dumps([c for c in clues if c in text]))
PY
)"

cat > "$EVIDENCE_DIR/07-h1-secret-set-outcome.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "app_name": "$APP_NAME",
  "resource_group": "$RESOURCE_GROUP",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BASELINE",
  "hypothesis": "H1: NVA surrogate forwarding-plane drop for AzureActiveDirectory service-tag destinations on tcp/443 -> secret set FAILS with a managed-identity / OIDC clue plus a connectivity / timeout clue",
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${H1_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H1},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code_nonzero": true,
  "outcome": $([ "$SET_EXIT" -ne 0 ] && echo '"failure"' || echo '"success"'),
  "stderr_classifier_inputs": {
    "managed_identity_or_oidc_clues_found": $MI_OR_OIDC_CLUES_JSON,
    "network_timeout_or_connection_clues_found": $NETWORK_CLUES_JSON
  },
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/07-h1-secret-set-outcome.json  [exit=$SET_EXIT]"
if [[ "$SET_EXIT" -eq 0 ]]; then
    echo "FAIL (H1): secret set unexpectedly succeeded with the NVA drop rule present."
    exit 1
fi

echo "[H1] step 5: silence gate (revision unchanged + ingress 200 + kvref-h1 absent)"
H1_APP_STATE_JSON="$(capture_app_state_snapshot "$H1_SECRET_REF_NAME" "false")"
echo "$H1_APP_STATE_JSON" > "$EVIDENCE_DIR/08-h1-app-state.json"
echo "  wrote evidence/08-h1-app-state.json"
H1_REV_UNCHANGED="$(echo "$H1_APP_STATE_JSON" | jq -r .latest_revision_unchanged_vs_baseline)"
H1_HTTP="$(echo "$H1_APP_STATE_JSON" | jq -r .ingress_probe_http_code)"
H1_EXPECTATION_MET="$(echo "$H1_APP_STATE_JSON" | jq -r .secret_presence_expectation_met)"
if [[ "$H1_REV_UNCHANGED" != "true" || "$H1_HTTP" != "200" || "$H1_EXPECTATION_MET" != "true" ]]; then
    echo "FAIL (H1 silence gate): revision/ingress/secret absence invariant broken."
    exit 1
fi

echo "[H1] step 6: capture NVA-local counters plus workload probes to both Entra hosts"
capture_nva_rule_and_workload_probe "H1" "true" "failure" "09-h1-nva-rule-state-and-workload-probe.json"
echo "  wrote evidence/09-h1-nva-rule-state-and-workload-probe.json"

echo "[H2] step 7: removing the same DROP rule from the NVA surrogate"
H2_REMOVE_JSON="$(run_on_nva_json "$NVA_VM_NAME" "set -euo pipefail; python3 - <<'PY'
import json
import subprocess

def run(*cmd):
    return subprocess.check_output(cmd, text=True)

chain = json.loads(run('sudo', 'nft', '-j', 'list', 'chain', 'inet', 'h4f', 'forward'))
removed = False
for item in chain.get('nftables', []):
    rule = item.get('rule')
    if rule and rule.get('comment') == 'h4f-drop-entra-443':
        subprocess.run(['sudo', 'nft', 'delete', 'rule', 'inet', 'h4f', 'forward', 'handle', str(rule['handle'])], check=True)
        removed = True
        break
subprocess.run(['sudo', 'nft', 'delete', 'set', 'inet', 'h4f', 'aad_h4f_v4'], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
chain_after = json.loads(run('sudo', 'nft', '-j', 'list', 'chain', 'inet', 'h4f', 'forward'))
target = None
for item in chain_after.get('nftables', []):
    rule = item.get('rule')
    if rule and rule.get('comment') == 'h4f-drop-entra-443':
        target = rule
        break
payload = {
    'action': 'remove-drop-rule',
    'rule_removed': removed,
    'rule_present_after_remove': target is not None,
    'forward_chain': chain_after,
}
print(json.dumps(payload))
PY")"

cat > "$EVIDENCE_DIR/10-h2-nva-drop-rule-removed.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "action": "remove-nftables-drop-rule-for-entra-service-tag-prefixes",
  "resource_group": "$RESOURCE_GROUP",
  "app_name": "$APP_NAME",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BASELINE",
  "nva_vm_name": "$NVA_VM_NAME",
  "nva_private_ip": "$NVA_PRIVATE_IP",
  "route_table_default_route": $ROUTE_JSON,
  "nva_rule_removal": $H2_REMOVE_JSON
}
EOF
echo "  wrote evidence/10-h2-nva-drop-rule-removed.json"

SECRET_NAME_H2="kvref-h2-value"
SECRET_VALUE_H2="h2-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H2] step 8: creating KV secret '$SECRET_NAME_H2'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H2" --value "$SECRET_VALUE_H2" --output none
KV_SECRET_URL_H2="${KV_URI}secrets/${SECRET_NAME_H2}"

H2_SECRET_REF_NAME="kvref-h2"
echo "[H2] step 9: attempting NEW 'az containerapp secret set --secrets ...identityref:system' (MUST SUCCEED)"
SET_STDOUT_FILE="$(mktemp)"
SET_STDERR_FILE="$(mktemp)"
SET_EXIT=0
az containerapp secret set \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --secrets "${H2_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H2},identityref:system" \
    --output json >"$SET_STDOUT_FILE" 2>"$SET_STDERR_FILE" || SET_EXIT=$?
SET_STDOUT="$(cat "$SET_STDOUT_FILE")"
SET_STDERR="$(cat "$SET_STDERR_FILE")"
rm -f "$SET_STDOUT_FILE" "$SET_STDERR_FILE"

cat > "$EVIDENCE_DIR/11-h2-secret-set-outcome.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "app_name": "$APP_NAME",
  "resource_group": "$RESOURCE_GROUP",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BASELINE",
  "hypothesis": "H2: removing the NVA-surrogate Entra drop rule restores a NEW secret set while route table, forwarding, NAT, Key Vault, identity, and ingress stay constant",
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${H2_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H2},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code": 0,
  "outcome": $([ "$SET_EXIT" -eq 0 ] && echo '"success"' || echo '"failure"'),
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/11-h2-secret-set-outcome.json  [exit=$SET_EXIT]"
if [[ "$SET_EXIT" -ne 0 ]]; then
    echo "FAIL (H2): secret set did not recover after removing the NVA drop rule."
    exit 1
fi

echo "[H2] step 10: success gate (revision unchanged + ingress 200 + kvref-h2 present)"
H2_APP_STATE_JSON="$(capture_app_state_snapshot "$H2_SECRET_REF_NAME" "true")"
echo "$H2_APP_STATE_JSON" > "$EVIDENCE_DIR/12-h2-app-state.json"
echo "  wrote evidence/12-h2-app-state.json"
H2_REV_UNCHANGED="$(echo "$H2_APP_STATE_JSON" | jq -r .latest_revision_unchanged_vs_baseline)"
H2_HTTP="$(echo "$H2_APP_STATE_JSON" | jq -r .ingress_probe_http_code)"
H2_EXPECTATION_MET="$(echo "$H2_APP_STATE_JSON" | jq -r .secret_presence_expectation_met)"
if [[ "$H2_REV_UNCHANGED" != "true" || "$H2_HTTP" != "200" || "$H2_EXPECTATION_MET" != "true" ]]; then
    echo "FAIL (H2 success gate): revision/ingress/secret presence invariant broken."
    exit 1
fi

echo "[H2] step 11: capture NVA-local counters plus workload probes to both Entra hosts"
capture_nva_rule_and_workload_probe "H2" "false" "success" "13-h2-nva-rule-state-and-workload-probe.json"
echo "  wrote evidence/13-h2-nva-rule-state-and-workload-probe.json"

cat <<EOF

=== falsify.sh complete ===
Evidence directory: $EVIDENCE_DIR
  06-h1-nva-drop-rule-installed.json          [service-tag prefixes captured, DROP rule present]
  07-h1-secret-set-outcome.json               [exit=nonzero as expected]
  08-h1-app-state.json                        [silence gate: revision unchanged, ingress 200, kvref-h1 absent]
  09-h1-nva-rule-state-and-workload-probe.json[rules present, counters recorded, workload probes fail]
  10-h2-nva-drop-rule-removed.json            [same DROP rule removed]
  11-h2-secret-set-outcome.json               [exit=0 as expected]
  12-h2-app-state.json                        [success gate: revision unchanged, ingress 200, kvref-h2 present]
  13-h2-nva-rule-state-and-workload-probe.json[rule absent, workload probes succeed]

H1 verified: the NVA-surrogate forwarding-plane DROP rule produced the failure while route table, forwarding, NAT, DNS, NSG, Key Vault, identity, RBAC, app, revision, and ingress stayed constant.
H2 verified: removing that same DROP rule restored success with the same cohort anchors.

Next: bash verify.sh
EOF
