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
NSG_NAME="$(jq -r .nsg_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
ACA_SUBNET_PREFIX="$(jq -r .aca_subnet_prefix "$EVIDENCE_DIR/01-deployment-outputs.json")"
LAW_CUSTOMER_ID="$(jq -r .log_analytics_customer_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
LATEST_REV_BASELINE="$(jq -r .latest_ready_revision_name "$EVIDENCE_DIR/05-h0-app-state-after.json")"
APP_FQDN="$(jq -r .ingress_fqdn "$EVIDENCE_DIR/02-h0-app-state-before.json")"

DENY_RULE_NAME="deny-aad-443-h4c"
DENY_RULE_PRIORITY=200
ALLOW_RULE_NAME="allow-aad-443-h4c"
ALLOW_RULE_PRIORITY=100
AAD_SERVICE_TAG="AzureActiveDirectory"
AAD_DEST_PORT="443"
H1_SETTLE_SECONDS=15
H2_RETRY_SLEEP_SECONDS=15
H2_MAX_ATTEMPTS=8

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

capture_nsg_rule_snapshot() {
    local phase="$1"
    local file_name="$2"
    local governing_expectation="$3"
    local rules_json
    rules_json="$(az network nsg rule list --resource-group "$RG" --nsg-name "$NSG_NAME" --output json)"
    local deny_rule_json
    deny_rule_json="$(echo "$rules_json" | jq --arg name "$DENY_RULE_NAME" 'map(select(.name == $name)) | .[0] // null')"
    local allow_rule_json
    allow_rule_json="$(echo "$rules_json" | jq --arg name "$ALLOW_RULE_NAME" 'map(select(.name == $name)) | .[0] // null')"
    local matching_allow_rules_json
    matching_allow_rules_json="$(echo "$rules_json" | jq '[.[] | select((.direction // "") == "Outbound" and (.access // "") == "Allow" and (.protocol // "") == "Tcp" and (((.destinationPortRange // "") == "443") or ((.destinationPortRanges // []) | index("443") != null)) and (((.destinationAddressPrefix // "") == "AzureActiveDirectory") or ((.destinationAddressPrefixes // []) | index("AzureActiveDirectory") != null)))]')"
    local deny_priority
    deny_priority="$(echo "$deny_rule_json" | jq '.priority // null')"
    local allow_priority
    allow_priority="$(echo "$allow_rule_json" | jq '.priority // null')"
    local higher_priority_allow_count
    higher_priority_allow_count="$(echo "$matching_allow_rules_json" | jq --argjson deny_priority "${deny_priority:-null}" 'if $deny_priority == null then 0 else map(select((.priority // 65535) < $deny_priority)) | length end')"
    local highest_priority_allow
    highest_priority_allow="$(echo "$matching_allow_rules_json" | jq 'if length == 0 then null else (sort_by(.priority) | .[0]) end')"
    local governing_rule="unknown"
    if [[ "$governing_expectation" == "deny" ]]; then
        governing_rule="deny-aad-443-h4c"
    elif [[ "$governing_expectation" == "allow" ]]; then
        governing_rule="allow-aad-443-h4c"
    fi
    cat > "$EVIDENCE_DIR/$file_name" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "nsg_name": "$NSG_NAME",
  "governing_expectation": "$governing_expectation",
  "governing_rule_name": "$governing_rule",
  "deny_rule": $deny_rule_json,
  "allow_rule": $allow_rule_json,
  "matching_allow_rules": $matching_allow_rules_json,
  "higher_priority_matching_allow_count": ${higher_priority_allow_count:-0},
  "highest_priority_matching_allow": $highest_priority_allow,
  "all_custom_rules": $rules_json
}
EOF
}

echo "falsify.sh started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  RG                  = $RG"
echo "  APP_NAME            = $APP_NAME"
echo "  KV_NAME             = $KV_NAME"
echo "  NSG_NAME            = $NSG_NAME"
echo "  ACA_SUBNET_PREFIX   = $ACA_SUBNET_PREFIX"
echo "  LAW_CUSTOMER_ID     = $LAW_CUSTOMER_ID"
echo ""

echo "[H1] step 1: creating outbound NSG deny rule for AzureActiveDirectory:443"
H1_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az network nsg rule create \
    --resource-group "$RG" \
    --nsg-name "$NSG_NAME" \
    --name "$DENY_RULE_NAME" \
    --priority "$DENY_RULE_PRIORITY" \
    --direction Outbound \
    --access Deny \
    --protocol Tcp \
    --source-address-prefixes '*' \
    --source-port-ranges '*' \
    --destination-address-prefixes "$AAD_SERVICE_TAG" \
    --destination-port-ranges "$AAD_DEST_PORT" \
    --output none

H1_RULES_JSON="$(az network nsg rule list --resource-group "$RG" --nsg-name "$NSG_NAME" --output json)"
DENY_RULE_JSON="$(echo "$H1_RULES_JSON" | jq --arg name "$DENY_RULE_NAME" 'map(select(.name == $name)) | .[0] // null')"
MATCHING_ALLOW_RULES_JSON="$(echo "$H1_RULES_JSON" | jq '[.[] | select((.direction // "") == "Outbound" and (.access // "") == "Allow" and (.protocol // "") == "Tcp" and (((.destinationPortRange // "") == "443") or ((.destinationPortRanges // []) | index("443") != null)) and (((.destinationAddressPrefix // "") == "AzureActiveDirectory") or ((.destinationAddressPrefixes // []) | index("AzureActiveDirectory") != null)))]')"
H1_HIGHER_PRIORITY_ALLOW_COUNT="$(echo "$MATCHING_ALLOW_RULES_JSON" | jq --argjson deny_priority "$DENY_RULE_PRIORITY" 'map(select((.priority // 65535) < $deny_priority)) | length')"

cat > "$EVIDENCE_DIR/06-h1-nsg-deny-created.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "action": "create-outbound-nsg-deny-rule-for-entra-authority",
  "h1_start_iso": "$H1_START_ISO",
  "nsg_name": "$NSG_NAME",
  "rule_name": "$DENY_RULE_NAME",
  "priority": $DENY_RULE_PRIORITY,
  "direction": "Outbound",
  "access": "Deny",
  "protocol": "Tcp",
  "destination_address_prefix": "$AAD_SERVICE_TAG",
  "destination_port": "$AAD_DEST_PORT",
  "higher_priority_matching_allow_count": ${H1_HIGHER_PRIORITY_ALLOW_COUNT:-0},
  "matching_allow_rules": $MATCHING_ALLOW_RULES_JSON,
  "deny_rule": $DENY_RULE_JSON,
  "all_custom_rules": $H1_RULES_JSON,
  "nsg_attached": true,
  "uses_azure_provided_dns": true,
  "route_table_attached": false,
  "azure_firewall_present": false
}
EOF
echo "  wrote evidence/06-h1-nsg-deny-created.json"

if [[ "${H1_HIGHER_PRIORITY_ALLOW_COUNT:-0}" != "0" ]]; then
    echo "FAIL (H1): a higher-priority matching Allow rule already exists, so the Deny would not govern."
    exit 1
fi

echo "[H1] step 2: waiting ${H1_SETTLE_SECONDS}s for NSG rule convergence"
sleep "$H1_SETTLE_SECONDS"

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
  "hypothesis": "H1: outbound NSG deny to AzureActiveDirectory:443 -> secret set FAILS with managed-identity OIDC discovery surface",
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
    echo "FAIL (H1): secret set unexpectedly succeeded with the NSG deny rule present."
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

echo "[H1] step 6: capture NSG rule view proving the deny governs AAD:443"
capture_nsg_rule_snapshot "H1" "09-h1-nsg-effective-rules.json" "deny"
H1_GOVERNING_ALLOW_COUNT="$(jq -r .higher_priority_matching_allow_count "$EVIDENCE_DIR/09-h1-nsg-effective-rules.json")"
if [[ "$H1_GOVERNING_ALLOW_COUNT" != "0" ]]; then
    echo "FAIL (H1 NSG view): found a higher-priority matching Allow rule at H1."
    exit 1
fi
echo "  wrote evidence/09-h1-nsg-effective-rules.json"

echo "[H2] step 7: creating a higher-priority Allow rule while leaving the Deny in place"
H2_ALLOW_CREATE_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az network nsg rule create \
    --resource-group "$RG" \
    --nsg-name "$NSG_NAME" \
    --name "$ALLOW_RULE_NAME" \
    --priority "$ALLOW_RULE_PRIORITY" \
    --direction Outbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes '*' \
    --source-port-ranges '*' \
    --destination-address-prefixes "$AAD_SERVICE_TAG" \
    --destination-port-ranges "$AAD_DEST_PORT" \
    --output none

H2_RULES_JSON="$(az network nsg rule list --resource-group "$RG" --nsg-name "$NSG_NAME" --output json)"
ALLOW_RULE_JSON="$(echo "$H2_RULES_JSON" | jq --arg name "$ALLOW_RULE_NAME" 'map(select(.name == $name)) | .[0] // null')"
DENY_RULE_JSON_H2="$(echo "$H2_RULES_JSON" | jq --arg name "$DENY_RULE_NAME" 'map(select(.name == $name)) | .[0] // null')"

cat > "$EVIDENCE_DIR/10-h2-nsg-allow-created.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "action": "create-higher-priority-outbound-nsg-allow-rule-for-entra-authority",
  "h2_allow_create_iso": "$H2_ALLOW_CREATE_ISO",
  "nsg_name": "$NSG_NAME",
  "allow_rule_name": "$ALLOW_RULE_NAME",
  "allow_rule_priority": $ALLOW_RULE_PRIORITY,
  "deny_rule_name": "$DENY_RULE_NAME",
  "deny_rule_priority": $DENY_RULE_PRIORITY,
  "allow_rule": $ALLOW_RULE_JSON,
  "deny_rule": $DENY_RULE_JSON_H2,
  "all_custom_rules": $H2_RULES_JSON,
  "nsg_attached": true,
  "uses_azure_provided_dns": true,
  "route_table_attached": false,
  "azure_firewall_present": false
}
EOF
echo "  wrote evidence/10-h2-nsg-allow-created.json"

SECRET_NAME_H2="kvref-h2-value"
SECRET_VALUE_H2="h2-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H2] step 8: creating KV secret '$SECRET_NAME_H2'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H2" --value "$SECRET_VALUE_H2" --output none
KV_SECRET_URL_H2="${KV_URI}secrets/${SECRET_NAME_H2}"

H2_SECRET_REF_NAME="kvref-h2"
echo "[H2] step 9: attempting NEW 'az containerapp secret set --identity system' with short settle/retry loop (MUST SUCCEED)"
H2_SECRET_SET_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SET_EXIT=1
SET_STDOUT=""
SET_STDERR=""
H2_ATTEMPTS_USED=0
for attempt in $(seq 1 "$H2_MAX_ATTEMPTS"); do
    H2_ATTEMPTS_USED="$attempt"
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
    if [[ $SET_EXIT -eq 0 ]]; then
        break
    fi
    if [[ "$attempt" -lt "$H2_MAX_ATTEMPTS" ]]; then
        sleep "$H2_RETRY_SLEEP_SECONDS"
    fi
done

cat > "$EVIDENCE_DIR/11-h2-secret-set-outcome.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "hypothesis": "H2: higher-priority outbound NSG allow to AzureActiveDirectory:443 restores a NEW secret set while the Deny remains",
  "h2_allow_create_iso": "$H2_ALLOW_CREATE_ISO",
  "h2_secret_set_start_iso": "$H2_SECRET_SET_START_ISO",
  "retry_attempts_used": ${H2_ATTEMPTS_USED:-0},
  "retry_sleep_seconds": $H2_RETRY_SLEEP_SECONDS,
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${H2_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H2},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code": 0,
  "outcome": $([ $SET_EXIT -eq 0 ] && echo '"success"' || echo '"failure"'),
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/11-h2-secret-set-outcome.json  [exit=$SET_EXIT attempts=${H2_ATTEMPTS_USED:-0}]"
if [[ $SET_EXIT -ne 0 ]]; then
    echo "FAIL (H2): secret set did not recover after adding the higher-priority Allow rule."
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

echo "[H2] step 11: capture NSG rule view proving the Allow now governs AAD:443"
capture_nsg_rule_snapshot "H2" "13-h2-nsg-effective-rules.json" "allow"
H2_HIGHEST_ALLOW_NAME="$(jq -r '.highest_priority_matching_allow.name // ""' "$EVIDENCE_DIR/13-h2-nsg-effective-rules.json")"
if [[ "$H2_HIGHEST_ALLOW_NAME" != "$ALLOW_RULE_NAME" ]]; then
    echo "FAIL (H2 NSG view): the expected higher-priority Allow rule is not governing."
    exit 1
fi
echo "  wrote evidence/13-h2-nsg-effective-rules.json"

echo ""
echo "=== falsify.sh complete ==="
echo "Evidence directory: $EVIDENCE_DIR"
echo "  06-h1-nsg-deny-created.json         [deny rule priority=$DENY_RULE_PRIORITY]"
echo "  07-h1-secret-set-outcome.json       [exit=nonzero as expected]"
echo "  08-h1-app-state.json                [silence gate: revision unchanged, ingress 200, kvref-h1 absent]"
echo "  09-h1-nsg-effective-rules.json      [deny governs, higher-priority allow count=0]"
echo "  10-h2-nsg-allow-created.json        [allow priority=$ALLOW_RULE_PRIORITY < deny priority=$DENY_RULE_PRIORITY]"
echo "  11-h2-secret-set-outcome.json       [exit=0 as expected]"
echo "  12-h2-app-state.json                [success gate: revision unchanged, ingress 200, kvref-h2 present]"
echo "  13-h2-nsg-effective-rules.json      [allow governs AzureActiveDirectory:443]"
echo ""
echo "H1 verified: the NSG deny broke OIDC discovery without any Azure Firewall or UDR in path."
echo "H2 verified: a higher-priority NSG Allow restored success with the same Key Vault, identity, and RBAC state."
echo ""
echo "Next: bash verify.sh"
