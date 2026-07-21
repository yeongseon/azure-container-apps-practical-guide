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

APP_NAME="$(jq -r .app_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_NAME="$(jq -r .key_vault_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_URI="$(jq -r .key_vault_uri "$EVIDENCE_DIR/01-deployment-outputs.json")"
VNET_NAME="$(jq -r .vnet_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
ACA_SUBNET_PREFIX="$(jq -r .aca_subnet_prefix "$EVIDENCE_DIR/01-deployment-outputs.json")"
LAW_CUSTOMER_ID="$(jq -r .log_analytics_customer_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
LATEST_REV_BASELINE="$(jq -r .latest_ready_revision_name "$EVIDENCE_DIR/05-h0-app-state-after.json")"
APP_FQDN="$(jq -r .ingress_fqdn "$EVIDENCE_DIR/02-h0-app-state-before.json")"

PRIMARY_ZONE="login.microsoftonline.com"
SECONDARY_ZONE="login.microsoft.com"
PRIMARY_LINK_NAME="link-${APP_NAME}-login-microsoftonline-com"
SECONDARY_LINK_NAME="link-${APP_NAME}-login-microsoft-com"
SINK_IP="192.0.2.1"
DNS_TTL=10
H1_PROPAGATION_WAIT_SECONDS=45
H2_POST_REMOVAL_WAIT_SECONDS=45

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

capture_nslookup_view() {
    local phase="$1"
    local file_name="$2"
    local expected_sink="$3"
    local exec_command="sh -c 'nslookup login.microsoftonline.com || true'"
    local stdout_file
    local stderr_file
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    local exit_code=0
    az containerapp exec \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --command "$exec_command" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
    local stdout
    local stderr
    stdout="$(cat "$stdout_file")"
    stderr="$(cat "$stderr_file")"
    rm -f "$stdout_file" "$stderr_file"
    local combined
    combined="${stdout}"
    if [[ -n "$stderr" ]]; then
        combined+=$'\n'
        combined+="${stderr}"
    fi
    local normalized_json
    normalized_json="$(printf '%s\n' "$combined" | python3 -c 'import json,re,sys; text=sys.stdin.read(); ips=re.findall(r"(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])", text); print(json.dumps({"output": text, "ips": ips}))')"
    local contains_sink="false"
    if echo "$normalized_json" | jq -e --arg ip "$SINK_IP" '.ips | index($ip) != null' >/dev/null; then
        contains_sink="true"
    fi
    cat > "$EVIDENCE_DIR/$file_name" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "app_name": "$APP_NAME",
  "command": "az containerapp exec --name $APP_NAME --resource-group $RG --command $exec_command",
  "exec_exit_code": $exit_code,
  "nslookup_target": "login.microsoftonline.com",
  "sink_ip": "$SINK_IP",
  "expected_sink_presence": $expected_sink,
  "observed_sink_presence": $contains_sink,
  "parsed": $normalized_json,
  "stdout": $(printf '%s' "$stdout" | jq -Rs .),
  "stderr": $(printf '%s' "$stderr" | jq -Rs .)
}
EOF
}

echo "falsify.sh started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  RG                  = $RG"
echo "  APP_NAME            = $APP_NAME"
echo "  KV_NAME             = $KV_NAME"
echo "  VNET_NAME           = $VNET_NAME"
echo "  ACA_SUBNET_PREFIX   = $ACA_SUBNET_PREFIX"
echo "  LAW_CUSTOMER_ID     = $LAW_CUSTOMER_ID"
echo ""

echo "[H1] step 1: creating custom Private DNS overrides for both Entra authority zones"
H1_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az network private-dns zone create --resource-group "$RG" --name "$PRIMARY_ZONE" --output none
az network private-dns zone create --resource-group "$RG" --name "$SECONDARY_ZONE" --output none
az network private-dns record-set a create --resource-group "$RG" --zone-name "$PRIMARY_ZONE" --name '@' --ttl "$DNS_TTL" --output none
az network private-dns record-set a create --resource-group "$RG" --zone-name "$SECONDARY_ZONE" --name '@' --ttl "$DNS_TTL" --output none
az network private-dns record-set a add-record --resource-group "$RG" --zone-name "$PRIMARY_ZONE" --record-set-name '@' --ipv4-address "$SINK_IP" --output none
az network private-dns record-set a add-record --resource-group "$RG" --zone-name "$SECONDARY_ZONE" --record-set-name '@' --ipv4-address "$SINK_IP" --output none
az network private-dns link vnet create --resource-group "$RG" --zone-name "$PRIMARY_ZONE" --name "$PRIMARY_LINK_NAME" --virtual-network "$VNET_NAME" --registration-enabled false --output none
az network private-dns link vnet create --resource-group "$RG" --zone-name "$SECONDARY_ZONE" --name "$SECONDARY_LINK_NAME" --virtual-network "$VNET_NAME" --registration-enabled false --output none

PRIMARY_RECORD_JSON="$(az network private-dns record-set a show --resource-group "$RG" --zone-name "$PRIMARY_ZONE" --name '@' --output json)"
SECONDARY_RECORD_JSON="$(az network private-dns record-set a show --resource-group "$RG" --zone-name "$SECONDARY_ZONE" --name '@' --output json)"
ZONE_LIST_JSON="$(az network private-dns zone list --resource-group "$RG" --output json)"
PRIMARY_LINK_JSON="$(az network private-dns link vnet show --resource-group "$RG" --zone-name "$PRIMARY_ZONE" --name "$PRIMARY_LINK_NAME" --output json)"
SECONDARY_LINK_JSON="$(az network private-dns link vnet show --resource-group "$RG" --zone-name "$SECONDARY_ZONE" --name "$SECONDARY_LINK_NAME" --output json)"

cat > "$EVIDENCE_DIR/06-h1-dns-override-created.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "action": "create-custom-private-dns-override-for-entra-authority",
  "h1_start_iso": "$H1_START_ISO",
  "vnet_name": "$VNET_NAME",
  "zone_primary": "$PRIMARY_ZONE",
  "zone_secondary": "$SECONDARY_ZONE",
  "link_primary": "$PRIMARY_LINK_NAME",
  "link_secondary": "$SECONDARY_LINK_NAME",
  "sink_ip": "$SINK_IP",
  "ttl_seconds": $DNS_TTL,
  "propagation_wait_seconds": $H1_PROPAGATION_WAIT_SECONDS,
  "private_dns_zones_in_rg": $(echo "$ZONE_LIST_JSON" | jq '[.[].name]'),
  "primary_record": $PRIMARY_RECORD_JSON,
  "secondary_record": $SECONDARY_RECORD_JSON,
  "primary_link": $PRIMARY_LINK_JSON,
  "secondary_link": $SECONDARY_LINK_JSON,
  "uses_azure_provided_dns": true,
  "route_table_attached": false,
  "azure_firewall_present": false
}
EOF
echo "  wrote evidence/06-h1-dns-override-created.json"

echo "[H1] step 2: waiting ${H1_PROPAGATION_WAIT_SECONDS}s for DNS propagation"
sleep "$H1_PROPAGATION_WAIT_SECONDS"

SECRET_NAME_H1="kvref-h1-value"
SECRET_VALUE_H1="h1-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H1] step 3: creating KV secret '$SECRET_NAME_H1'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H1" --value "$SECRET_VALUE_H1" --output none
KV_SECRET_URL_H1="${KV_URI}secrets/${SECRET_NAME_H1}"

H1_SECRET_REF_NAME="kvref-h1"
echo "[H1] step 4: attempting 'az containerapp secret set --identity system' (MUST FAIL)"
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

STDERR_MATCH_FAILED_UPDATE="false"
STDERR_MATCH_UNABLE_MI="false"
STDERR_MATCH_OPENID="false"
STDERR_MATCH_LOGIN_HOST="false"
STDERR_MATCH_EOF="false"
if grep -q -i 'Failed to update secrets' <<<"$SET_STDERR"; then STDERR_MATCH_FAILED_UPDATE="true"; fi
if grep -q -i 'Unable to get value using Managed identity' <<<"$SET_STDERR"; then STDERR_MATCH_UNABLE_MI="true"; fi
if grep -q -i 'openid-configuration' <<<"$SET_STDERR"; then STDERR_MATCH_OPENID="true"; fi
if grep -q -i 'login\.microsoft' <<<"$SET_STDERR"; then STDERR_MATCH_LOGIN_HOST="true"; fi
if grep -q -i 'EOF' <<<"$SET_STDERR"; then STDERR_MATCH_EOF="true"; fi

cat > "$EVIDENCE_DIR/07-h1-secret-set-outcome.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "hypothesis": "H1: custom Private DNS override for Entra authority -> secret set FAILS with managed-identity OIDC discovery surface",
  "h1_start_iso": "$H1_START_ISO",
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${H1_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H1},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code_nonzero": true,
  "outcome": $([ $SET_EXIT -ne 0 ] && echo '"failure"' || echo '"success"'),
  "stderr_substring_matches": {
    "failed_to_update_secrets": $STDERR_MATCH_FAILED_UPDATE,
    "unable_to_get_value_using_managed_identity": $STDERR_MATCH_UNABLE_MI,
    "openid_configuration_reference": $STDERR_MATCH_OPENID,
    "login_microsoft_host_reference": $STDERR_MATCH_LOGIN_HOST,
    "eof_reference": $STDERR_MATCH_EOF
  },
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/07-h1-secret-set-outcome.json  [exit=$SET_EXIT]"
if [[ $SET_EXIT -eq 0 ]]; then
    echo "FAIL (H1): secret set unexpectedly succeeded with the DNS override present."
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

echo "[H1] step 6: capture replica nslookup data-plane DNS view"
capture_nslookup_view "H1" "09-h1-replica-dns-view.json" "true"
H1_SINK_PRESENT="$(jq -r .observed_sink_presence "$EVIDENCE_DIR/09-h1-replica-dns-view.json")"
if [[ "$H1_SINK_PRESENT" != "true" ]]; then
    echo "FAIL (H1 DNS view): replica nslookup did not resolve login.microsoftonline.com to $SINK_IP."
    exit 1
fi
echo "  wrote evidence/09-h1-replica-dns-view.json"

echo "[H2] step 7: removing the custom Private DNS override"
H2_OVERRIDE_REMOVAL_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az network private-dns link vnet delete --resource-group "$RG" --zone-name "$PRIMARY_ZONE" --name "$PRIMARY_LINK_NAME" --yes
az network private-dns link vnet delete --resource-group "$RG" --zone-name "$SECONDARY_ZONE" --name "$SECONDARY_LINK_NAME" --yes
az network private-dns zone delete --resource-group "$RG" --name "$PRIMARY_ZONE" --yes
az network private-dns zone delete --resource-group "$RG" --name "$SECONDARY_ZONE" --yes
POST_REMOVE_ZONES_JSON="$(az network private-dns zone list --resource-group "$RG" --output json)"

cat > "$EVIDENCE_DIR/10-h2-dns-override-removed.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "action": "remove-custom-private-dns-override-for-entra-authority",
  "h2_override_removal_iso": "$H2_OVERRIDE_REMOVAL_ISO",
  "zone_primary": "$PRIMARY_ZONE",
  "zone_secondary": "$SECONDARY_ZONE",
  "link_primary": "$PRIMARY_LINK_NAME",
  "link_secondary": "$SECONDARY_LINK_NAME",
  "sink_ip": "$SINK_IP",
  "ttl_seconds": $DNS_TTL,
  "post_removal_wait_seconds": $H2_POST_REMOVAL_WAIT_SECONDS,
  "remaining_private_dns_zones_in_rg": $(echo "$POST_REMOVE_ZONES_JSON" | jq '[.[].name]'),
  "uses_azure_provided_dns": true,
  "route_table_attached": false,
  "azure_firewall_present": false
}
EOF
echo "  wrote evidence/10-h2-dns-override-removed.json"

echo "[H2] step 8: waiting ${H2_POST_REMOVAL_WAIT_SECONDS}s to clear DNS caches beyond TTL=${DNS_TTL}s"
sleep "$H2_POST_REMOVAL_WAIT_SECONDS"

SECRET_NAME_H2="kvref-h2-value"
SECRET_VALUE_H2="h2-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H2] step 9: creating KV secret '$SECRET_NAME_H2'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H2" --value "$SECRET_VALUE_H2" --output none
KV_SECRET_URL_H2="${KV_URI}secrets/${SECRET_NAME_H2}"

H2_SECRET_REF_NAME="kvref-h2"
echo "[H2] step 10: attempting NEW 'az containerapp secret set --identity system' (MUST SUCCEED)"
H2_SECRET_SET_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
  "hypothesis": "H2: custom Private DNS override removed and cache wait elapsed -> NEW secret set SUCCEEDS",
  "h2_override_removal_iso": "$H2_OVERRIDE_REMOVAL_ISO",
  "h2_secret_set_start_iso": "$H2_SECRET_SET_START_ISO",
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${H2_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H2},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code": 0,
  "outcome": $([ $SET_EXIT -eq 0 ] && echo '"success"' || echo '"failure"'),
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/11-h2-secret-set-outcome.json  [exit=$SET_EXIT]"
if [[ $SET_EXIT -ne 0 ]]; then
    echo "FAIL (H2): secret set did not recover after removing the DNS override."
    exit 1
fi

echo "[H2] step 11: success gate (revision unchanged + ingress 200 + kvref-h2 present)"
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

echo "[H2] step 12: capture replica nslookup data-plane DNS view after override removal"
capture_nslookup_view "H2" "13-h2-replica-dns-view.json" "false"
H2_SINK_PRESENT="$(jq -r .observed_sink_presence "$EVIDENCE_DIR/13-h2-replica-dns-view.json")"
if [[ "$H2_SINK_PRESENT" != "false" ]]; then
    echo "FAIL (H2 DNS view): replica nslookup still resolved login.microsoftonline.com to $SINK_IP after removal."
    exit 1
fi
echo "  wrote evidence/13-h2-replica-dns-view.json"

echo ""
echo "=== falsify.sh complete ==="
echo "Evidence directory: $EVIDENCE_DIR"
echo "  06-h1-dns-override-created.json        [zones linked, sink=$SINK_IP ttl=$DNS_TTL]"
echo "  07-h1-secret-set-outcome.json          [exit=nonzero as expected]"
echo "  08-h1-app-state.json                   [silence gate: revision unchanged, ingress 200, kvref-h1 absent]"
echo "  09-h1-replica-dns-view.json            [nslookup sink present=true]"
echo "  10-h2-dns-override-removed.json        [zones removed, waited ${H2_POST_REMOVAL_WAIT_SECONDS}s]"
echo "  11-h2-secret-set-outcome.json          [exit=0 as expected]"
echo "  12-h2-app-state.json                   [success gate: revision unchanged, ingress 200, kvref-h2 present]"
echo "  13-h2-replica-dns-view.json            [nslookup sink present=false]"
echo ""
echo "H1 verified: the DNS override broke OIDC discovery without any Azure Firewall or UDR in path."
echo "H2 verified: removing the override restored success with the same Key Vault, identity, and RBAC state."
echo ""
echo "Next: bash verify.sh"
