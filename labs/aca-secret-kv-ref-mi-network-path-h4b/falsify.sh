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
    echo "ERROR: H0 baseline in evidence/04-h0-secret-set-outcome.json did NOT succeed (exit=$H0_EXIT)."
    exit 1
fi

APP_NAME="$(jq -r .app_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_NAME="$(jq -r .key_vault_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_URI="$(jq -r .key_vault_uri "$EVIDENCE_DIR/01-deployment-outputs.json")"
FIREWALL_RESOURCE_ID="$(jq -r .firewall_resource_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
FIREWALL_POLICY_NAME="$(jq -r .firewall_policy_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
LAW_CUSTOMER_ID="$(jq -r .log_analytics_customer_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
ENTRA_RULE_COLLECTION_NAME="$(jq -r .entra_rule_collection_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
ENTRA_RULE_NAME="$(jq -r .entra_rule_name "$EVIDENCE_DIR/01-deployment-outputs.json")"

RULE_COLLECTION_GROUP_NAME="aca-kv-entra-application"
ENTRA_COLLECTION_PRIORITY=220
ACA_SUBNET_PREFIX="$(az deployment group show --resource-group "$RG" --name aca-secret-kv-ref-mi-network-path-h4b --query properties.outputs.acaSubnetPrefix.value --output tsv 2>/dev/null || echo "10.90.0.0/23")"
ENTRA_FQDN_PRIMARY="login.microsoftonline.com"
ENTRA_FQDN_SECONDARY="login.microsoft.com"
DIAG_SETTING_NAME="diag-to-law"
DIAG_LOGS_DISABLED='[{"category":"AzureFirewallApplicationRule","enabled":false},{"category":"AzureFirewallNetworkRule","enabled":true}]'
DIAG_LOGS_ENABLED='[{"category":"AzureFirewallApplicationRule","enabled":true},{"category":"AzureFirewallNetworkRule","enabled":true}]'
DIAG_METRICS='[{"category":"AllMetrics","enabled":true}]'

LATEST_REV_BASELINE="$(jq -r .latest_ready_revision_name "$EVIDENCE_DIR/05-h0-app-state-after.json")"
APP_FQDN="$(jq -r .ingress_fqdn "$EVIDENCE_DIR/02-h0-app-state-before.json")"

START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "falsify.sh started at $START_ISO"
echo "  RG                           = $RG"
echo "  APP_NAME                     = $APP_NAME"
echo "  KV_NAME                      = $KV_NAME"
echo "  FIREWALL_POLICY_NAME         = $FIREWALL_POLICY_NAME"
echo "  FIREWALL_RESOURCE_ID         = $FIREWALL_RESOURCE_ID"
echo "  ENTRA_RULE_COLLECTION_NAME   = $ENTRA_RULE_COLLECTION_NAME"
echo "  ENTRA_RULE_NAME              = $ENTRA_RULE_NAME"
echo "  ENTRA_COLLECTION_PRIORITY    = $ENTRA_COLLECTION_PRIORITY"
echo "  ACA_SUBNET_PREFIX            = $ACA_SUBNET_PREFIX"
echo "  LATEST_REV_BASELINE          = $LATEST_REV_BASELINE"
echo "  APP_FQDN                     = $APP_FQDN"
echo "  LAW_CUSTOMER_ID              = $LAW_CUSTOMER_ID"
echo ""

build_azfw_entra_kql() {
    local since_iso="$1"
    local action_filter="$2"
    local until_iso="${3:-}"
    local upper_bound_app=''
    local upper_bound_diag=''
    if [[ -n "$until_iso" ]]; then
        upper_bound_app="| where TimeGenerated < datetime('${until_iso}')"
        upper_bound_diag="| where TimeGenerated < datetime('${until_iso}')"
    fi
    cat <<EOF
union isfuzzy=true
(AZFWApplicationRule
    | where TimeGenerated >= datetime('${since_iso}')
    ${upper_bound_app}
    | where Fqdn has '${ENTRA_FQDN_PRIMARY}' or Fqdn has '${ENTRA_FQDN_SECONDARY}'
    | where Action == '${action_filter}'
    | project TimeGenerated, Fqdn, SourceIp, Action, Policy, RuleCollectionGroup, RuleCollection, Rule, Source='AZFWApplicationRule'),
(AzureDiagnostics
    | where TimeGenerated >= datetime('${since_iso}')
    ${upper_bound_diag}
    | where Category == 'AzureFirewallApplicationRule'
    | where msg_s contains '${ENTRA_FQDN_PRIMARY}' or msg_s contains '${ENTRA_FQDN_SECONDARY}'
    | where msg_s contains '${action_filter}'
    | project TimeGenerated, Fqdn=extract(@'to (\\S+):443', 1, msg_s), SourceIp=extract(@'from (\\d+\\.\\d+\\.\\d+\\.\\d+)', 1, msg_s), Action='${action_filter}', Policy='', RuleCollectionGroup='', RuleCollection='', Rule='', Source='AzureDiagnostics')
| order by TimeGenerated desc
| take 20
EOF
}

count_azfw_entra_rows_window() {
    local since_iso="$1"
    local action_filter="$2"
    local until_iso="${3:-}"
    local kql
    kql="$(build_azfw_entra_kql "$since_iso" "$action_filter" "$until_iso")"
    local rows
    rows="$(az monitor log-analytics query --workspace "$LAW_CUSTOMER_ID" --analytics-query "$kql" --output tsv 2>/dev/null || true)"
    if [[ -n "$rows" ]]; then
        printf '%s\n' "$rows" | python3 -c 'import sys; print("\n".join(sys.stdin.read().splitlines()[:5]))' >&2
        printf '%s\n' "$rows" | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

query_azfw_entra_rows_json() {
    local since_iso="$1"
    local action_filter="$2"
    local until_iso="${3:-}"
    local kql
    kql="$(build_azfw_entra_kql "$since_iso" "$action_filter" "$until_iso")"
    az monitor log-analytics query --workspace "$LAW_CUSTOMER_ID" --analytics-query "$kql" --output json 2>/dev/null || echo '[]'
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
        for attempt in 1 2 3; do
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

echo "[H1] step 1: capturing H1 start timestamp"
H1_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "[H1] step 2: removing rule collection '$ENTRA_RULE_COLLECTION_NAME'"
REMOVE_STDOUT_FILE="$(mktemp)"
REMOVE_STDERR_FILE="$(mktemp)"
REMOVE_EXIT=0
az network firewall policy rule-collection-group collection remove \
    --resource-group "$RG" \
    --policy-name "$FIREWALL_POLICY_NAME" \
    --rule-collection-group-name "$RULE_COLLECTION_GROUP_NAME" \
    --name "$ENTRA_RULE_COLLECTION_NAME" \
    --output json >"$REMOVE_STDOUT_FILE" 2>"$REMOVE_STDERR_FILE" || REMOVE_EXIT=$?
REMOVE_STDOUT="$(cat "$REMOVE_STDOUT_FILE")"
REMOVE_STDERR="$(cat "$REMOVE_STDERR_FILE")"
rm -f "$REMOVE_STDOUT_FILE" "$REMOVE_STDERR_FILE"
if [[ $REMOVE_EXIT -ne 0 ]]; then
    echo "ERROR: failed to remove rule collection '$ENTRA_RULE_COLLECTION_NAME'."
    echo "  stderr: $REMOVE_STDERR"
    exit 1
fi

POST_REMOVE_GROUP_JSON="$(az network firewall policy rule-collection-group show --resource-group "$RG" --policy-name "$FIREWALL_POLICY_NAME" --name "$RULE_COLLECTION_GROUP_NAME" --output json)"
POST_REMOVE_COLLECTION_NAMES="$(echo "$POST_REMOVE_GROUP_JSON" | jq -r '.ruleCollections[].name')"
if echo "$POST_REMOVE_COLLECTION_NAMES" | grep -q "^${ENTRA_RULE_COLLECTION_NAME}$"; then
    echo "ERROR: rule collection '$ENTRA_RULE_COLLECTION_NAME' still present after remove call."
    exit 1
fi

echo "[H1] step 3: disabling AzureFirewallApplicationRule diagnostic category"
H1_DIAG_DISABLE_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DIAG_DISABLE_STDOUT_FILE="$(mktemp)"
DIAG_DISABLE_STDERR_FILE="$(mktemp)"
DIAG_DISABLE_EXIT=0
az monitor diagnostic-settings update \
    --name "$DIAG_SETTING_NAME" \
    --resource "$FIREWALL_RESOURCE_ID" \
    --logs "$DIAG_LOGS_DISABLED" \
    --metrics "$DIAG_METRICS" \
    --output json >"$DIAG_DISABLE_STDOUT_FILE" 2>"$DIAG_DISABLE_STDERR_FILE" || DIAG_DISABLE_EXIT=$?
DIAG_DISABLE_STDOUT="$(cat "$DIAG_DISABLE_STDOUT_FILE")"
DIAG_DISABLE_STDERR="$(cat "$DIAG_DISABLE_STDERR_FILE")"
rm -f "$DIAG_DISABLE_STDOUT_FILE" "$DIAG_DISABLE_STDERR_FILE"
if [[ $DIAG_DISABLE_EXIT -ne 0 ]]; then
    echo "ERROR: failed to disable AzureFirewallApplicationRule diagnostics."
    echo "  stderr: $DIAG_DISABLE_STDERR"
    exit 1
fi

POST_H1_DIAG_JSON="$(az monitor diagnostic-settings show --name "$DIAG_SETTING_NAME" --resource "$FIREWALL_RESOURCE_ID" --output json)"
H1_APP_RULE_DIAG_ENABLED="$(echo "$POST_H1_DIAG_JSON" | jq -r '.logs[] | select(.category == "AzureFirewallApplicationRule") | .enabled')"
H1_NETWORK_RULE_DIAG_ENABLED="$(echo "$POST_H1_DIAG_JSON" | jq -r '.logs[] | select(.category == "AzureFirewallNetworkRule") | .enabled')"
if [[ "$H1_APP_RULE_DIAG_ENABLED" != "false" ]]; then
    echo "ERROR: AzureFirewallApplicationRule diagnostic category is still enabled after H1 update."
    exit 1
fi

cat > "$EVIDENCE_DIR/06-h1-firewall-rule-removed.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "action": "remove-rule-collection-and-disable-applicationrule-diagnostics",
  "h1_start_iso": "$H1_START_ISO",
  "h1_diag_disable_iso": "$H1_DIAG_DISABLE_ISO",
  "firewall_policy_name": "$FIREWALL_POLICY_NAME",
  "firewall_resource_id": "$FIREWALL_RESOURCE_ID",
  "diagnostic_setting_name": "$DIAG_SETTING_NAME",
  "rule_collection_group_name": "$RULE_COLLECTION_GROUP_NAME",
  "rule_collection_name": "$ENTRA_RULE_COLLECTION_NAME",
  "rule_name": "$ENTRA_RULE_NAME",
  "collection_priority": $ENTRA_COLLECTION_PRIORITY,
  "aca_subnet_prefix": "$ACA_SUBNET_PREFIX",
  "remove_exit_code": $REMOVE_EXIT,
  "diagnostic_update_exit_code": $DIAG_DISABLE_EXIT,
  "post_remove_collections_in_group": $(echo "$POST_REMOVE_COLLECTION_NAMES" | jq -R -s -c 'split("\n") | map(select(length > 0))'),
  "post_h1_diagnostic_logs": $(echo "$POST_H1_DIAG_JSON" | jq '.logs'),
  "azure_firewall_application_rule_logging_enabled": false,
  "azure_firewall_network_rule_logging_enabled": $H1_NETWORK_RULE_DIAG_ENABLED,
  "controlled_variable_absent_after_remove": true,
  "controlled_variable_observability_disabled": true,
  "remove_stdout": $(printf '%s' "$REMOVE_STDOUT" | jq -Rs .),
  "remove_stderr": $(printf '%s' "$REMOVE_STDERR" | jq -Rs .),
  "diagnostic_update_stdout": $(printf '%s' "$DIAG_DISABLE_STDOUT" | jq -Rs .),
  "diagnostic_update_stderr": $(printf '%s' "$DIAG_DISABLE_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/06-h1-firewall-rule-removed.json"

echo "[H1] step 4: waiting 60s for firewall rule + diagnostic convergence"
sleep 60

SECRET_NAME_H1="kvref-h1-value"
SECRET_VALUE_H1="h1-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H1] step 5: creating KV secret '$SECRET_NAME_H1'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H1" --value "$SECRET_VALUE_H1" --output none
KV_SECRET_URL_H1="${KV_URI}secrets/${SECRET_NAME_H1}"

H1_SECRET_REF_NAME="kvref-h1"
echo "[H1] step 6: attempting 'az containerapp secret set --identity system' (MUST FAIL)"
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
STDERR_MATCH_OPENID_EOF="false"
STDERR_MATCH_LOGIN_HOST="false"
if grep -q -i "Failed to update secrets" <<<"$SET_STDERR"; then STDERR_MATCH_FAILED_UPDATE="true"; fi
if grep -q -i "Unable to get value using Managed identity" <<<"$SET_STDERR"; then STDERR_MATCH_UNABLE_MI="true"; fi
if grep -q -i "openid-configuration" <<<"$SET_STDERR"; then STDERR_MATCH_OPENID_EOF="true"; fi
if grep -q -i "login\.microsoft" <<<"$SET_STDERR"; then STDERR_MATCH_LOGIN_HOST="true"; fi

cat > "$EVIDENCE_DIR/07-h1-secret-set-outcome.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "hypothesis": "H1: Entra rule REMOVED + AzureFirewallApplicationRule logging DISABLED -> secret set FAILS while firewall denial stays invisible",
  "h1_start_iso": "$H1_START_ISO",
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${H1_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H1},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code_nonzero": true,
  "outcome": $([ $SET_EXIT -ne 0 ] && echo '"failure"' || echo '"success"'),
  "stderr_substring_matches": {
    "failed_to_update_secrets": $STDERR_MATCH_FAILED_UPDATE,
    "unable_to_get_value_using_managed_identity": $STDERR_MATCH_UNABLE_MI,
    "openid_configuration_reference": $STDERR_MATCH_OPENID_EOF,
    "login_microsoft_host_reference": $STDERR_MATCH_LOGIN_HOST
  },
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/07-h1-secret-set-outcome.json  [exit=$SET_EXIT]"
if [[ $SET_EXIT -eq 0 ]]; then
    echo "FAIL (H1): secret set unexpectedly succeeded after removing the Entra rule."
    exit 1
fi

echo "[H1] step 7: silence gate (revision unchanged + ingress 200 + kvref-h1 absent)"
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

echo "[H1] step 8: proving the logging gap (H1 Deny row count MUST stay 0)"
H1_DENY_ROW_COUNT="0"
H1_DENY_ATTEMPT_LOG='[]'
for attempt in 1 2 3; do
    echo "  attempt ${attempt}/3: querying H1 Deny rows since $H1_START_ISO"
    H1_DENY_ROW_COUNT="$(count_azfw_entra_rows_window "$H1_START_ISO" "Deny")"
    H1_DENY_ATTEMPT_LOG="$(echo "$H1_DENY_ATTEMPT_LOG" | jq --arg n "$attempt" --arg c "$H1_DENY_ROW_COUNT" '. + [{attempt: ($n|tonumber), row_count: ($c|tonumber)}]')"
    if [[ "$H1_DENY_ROW_COUNT" -ne 0 ]]; then
        break
    fi
    if [[ $attempt -lt 3 ]]; then
        sleep 30
    fi
done
H1_DENY_ROWS_JSON="$(query_azfw_entra_rows_json "$H1_START_ISO" "Deny")"

cat > "$EVIDENCE_DIR/09-h1-firewall-deny-log-absent.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "log_analytics_customer_id": "$LAW_CUSTOMER_ID",
  "kql_window_start_iso": "$H1_START_ISO",
  "kql_query": $(printf '%s' "$(build_azfw_entra_kql "$H1_START_ISO" "Deny")" | jq -Rs .),
  "final_deny_row_count": $H1_DENY_ROW_COUNT,
  "attempts": $H1_DENY_ATTEMPT_LOG,
  "denied_fqdn_primary": "$ENTRA_FQDN_PRIMARY",
  "denied_fqdn_secondary": "$ENTRA_FQDN_SECONDARY",
  "deny_rows": $H1_DENY_ROWS_JSON,
  "logging_gap_expected": true
}
EOF
echo "  wrote evidence/09-h1-firewall-deny-log-absent.json  [deny_row_count=$H1_DENY_ROW_COUNT]"
if [[ "$H1_DENY_ROW_COUNT" -ne 0 ]]; then
    echo "FAIL (H1 logging gap): Deny rows were logged even though AzureFirewallApplicationRule diagnostics were disabled."
    exit 1
fi

echo ""
echo "[H2] step 9: re-enabling AzureFirewallApplicationRule diagnostic category"
H2_DIAG_ENABLE_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DIAG_ENABLE_STDOUT_FILE="$(mktemp)"
DIAG_ENABLE_STDERR_FILE="$(mktemp)"
DIAG_ENABLE_EXIT=0
az monitor diagnostic-settings update \
    --name "$DIAG_SETTING_NAME" \
    --resource "$FIREWALL_RESOURCE_ID" \
    --logs "$DIAG_LOGS_ENABLED" \
    --metrics "$DIAG_METRICS" \
    --output json >"$DIAG_ENABLE_STDOUT_FILE" 2>"$DIAG_ENABLE_STDERR_FILE" || DIAG_ENABLE_EXIT=$?
DIAG_ENABLE_STDOUT="$(cat "$DIAG_ENABLE_STDOUT_FILE")"
DIAG_ENABLE_STDERR="$(cat "$DIAG_ENABLE_STDERR_FILE")"
rm -f "$DIAG_ENABLE_STDOUT_FILE" "$DIAG_ENABLE_STDERR_FILE"
if [[ $DIAG_ENABLE_EXIT -ne 0 ]]; then
    echo "ERROR: failed to re-enable AzureFirewallApplicationRule diagnostics."
    echo "  stderr: $DIAG_ENABLE_STDERR"
    exit 1
fi

POST_H2_DIAG_JSON="$(az monitor diagnostic-settings show --name "$DIAG_SETTING_NAME" --resource "$FIREWALL_RESOURCE_ID" --output json)"
H2_APP_RULE_DIAG_ENABLED="$(echo "$POST_H2_DIAG_JSON" | jq -r '.logs[] | select(.category == "AzureFirewallApplicationRule") | .enabled')"
if [[ "$H2_APP_RULE_DIAG_ENABLED" != "true" ]]; then
    echo "ERROR: AzureFirewallApplicationRule diagnostic category is not enabled after H2 update."
    exit 1
fi

POST_H2_RULE_GROUP_JSON="$(az network firewall policy rule-collection-group show --resource-group "$RG" --policy-name "$FIREWALL_POLICY_NAME" --name "$RULE_COLLECTION_GROUP_NAME" --output json)"
POST_H2_COLLECTION_NAMES="$(echo "$POST_H2_RULE_GROUP_JSON" | jq -r '.ruleCollections[].name')"
if echo "$POST_H2_COLLECTION_NAMES" | grep -q "^${ENTRA_RULE_COLLECTION_NAME}$"; then
    echo "ERROR: H2 must NOT restore the Entra rule collection, but '$ENTRA_RULE_COLLECTION_NAME' is present."
    exit 1
fi

echo "[H2] step 10: waiting 60s for diagnostic-setting convergence"
sleep 60

SECRET_NAME_H2="kvref-h2-value"
SECRET_VALUE_H2="h2-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H2] step 11: creating KV secret '$SECRET_NAME_H2'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H2" --value "$SECRET_VALUE_H2" --output none
KV_SECRET_URL_H2="${KV_URI}secrets/${SECRET_NAME_H2}"

H2_SECRET_REF_NAME="kvref-h2"
echo "[H2] step 12: attempting NEW 'az containerapp secret set --identity system' (MUST STILL FAIL)"
# Capture the H2 attempt-start timestamp immediately before the attempt so the pre-H2
# non-retroactivity guard window [enable -> start] and the H2 Deny window [start -> now]
# partition exactly at the attempt boundary, leaving no wall-clock gap in which a late H1
# retry Deny row (ingested after the diagnostic re-enable) could be misattributed to the
# H2 attempt. The guard query below is evaluated AFTER the attempt, but it is bounded by
# this true attempt-start timestamp, so its window remains correct.
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

echo "[H2] step 13: pre-H2 non-retroactivity guard (enable -> start window MUST have 0 Deny rows; bounded by the true attempt-start timestamp captured immediately before the H2 attempt)"
PRE_H2_GUARD_ROW_COUNT="$(count_azfw_entra_rows_window "$H2_DIAG_ENABLE_ISO" "Deny" "$H2_SECRET_SET_START_ISO")"
PRE_H2_GUARD_ROWS_JSON="$(query_azfw_entra_rows_json "$H2_DIAG_ENABLE_ISO" "Deny" "$H2_SECRET_SET_START_ISO")"

cat > "$EVIDENCE_DIR/10-h2-firewall-diagnostics-enabled.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "action": "enable-applicationrule-diagnostics-only",
  "h2_diag_enable_iso": "$H2_DIAG_ENABLE_ISO",
  "h2_secret_set_start_iso": "$H2_SECRET_SET_START_ISO",
  "firewall_policy_name": "$FIREWALL_POLICY_NAME",
  "firewall_resource_id": "$FIREWALL_RESOURCE_ID",
  "diagnostic_setting_name": "$DIAG_SETTING_NAME",
  "rule_collection_group_name": "$RULE_COLLECTION_GROUP_NAME",
  "rule_collection_name": "$ENTRA_RULE_COLLECTION_NAME",
  "rule_name": "$ENTRA_RULE_NAME",
  "collection_priority": $ENTRA_COLLECTION_PRIORITY,
  "aca_subnet_prefix": "$ACA_SUBNET_PREFIX",
  "diagnostic_update_exit_code": $DIAG_ENABLE_EXIT,
  "post_enable_collections_in_group": $(echo "$POST_H2_COLLECTION_NAMES" | jq -R -s -c 'split("\n") | map(select(length > 0))'),
  "post_h2_diagnostic_logs": $(echo "$POST_H2_DIAG_JSON" | jq '.logs'),
  "azure_firewall_application_rule_logging_enabled": true,
  "controlled_variable_absent_after_h2_observability_fix": true,
  "pre_h2_guard_window_start_iso": "$H2_DIAG_ENABLE_ISO",
  "pre_h2_guard_window_end_iso": "$H2_SECRET_SET_START_ISO",
  "pre_h2_guard_deny_row_count": $PRE_H2_GUARD_ROW_COUNT,
  "pre_h2_guard_query": $(printf '%s' "$(build_azfw_entra_kql "$H2_DIAG_ENABLE_ISO" "Deny" "$H2_SECRET_SET_START_ISO")" | jq -Rs .),
  "pre_h2_guard_deny_rows": $PRE_H2_GUARD_ROWS_JSON,
  "diagnostic_update_stdout": $(printf '%s' "$DIAG_ENABLE_STDOUT" | jq -Rs .),
  "diagnostic_update_stderr": $(printf '%s' "$DIAG_ENABLE_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/10-h2-firewall-diagnostics-enabled.json"
if [[ "$PRE_H2_GUARD_ROW_COUNT" -ne 0 ]]; then
    echo "FAIL (H2 pre-guard): found Deny rows between diagnostic re-enable and the NEW H2 attempt start."
    exit 1
fi

cat > "$EVIDENCE_DIR/11-h2-secret-set-outcome.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "hypothesis": "H2: AzureFirewallApplicationRule logging RE-ENABLED while Entra rule stays ABSENT -> NEW secret set still FAILS but denial becomes visible",
  "h2_diag_enable_iso": "$H2_DIAG_ENABLE_ISO",
  "h2_secret_set_start_iso": "$H2_SECRET_SET_START_ISO",
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${H2_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H2},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code_nonzero": true,
  "outcome": $([ $SET_EXIT -ne 0 ] && echo '"failure"' || echo '"success"'),
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/11-h2-secret-set-outcome.json  [exit=$SET_EXIT]"
if [[ $SET_EXIT -eq 0 ]]; then
    echo "FAIL (H2): connectivity unexpectedly recovered. H4b must NOT restore the Entra rule in H2."
    exit 1
fi

echo "[H2] step 14: silence gate (revision unchanged + ingress 200 + kvref-h2 absent)"
H2_APP_STATE_JSON="$(capture_app_state_snapshot "$H2_SECRET_REF_NAME" "false")"
echo "$H2_APP_STATE_JSON" > "$EVIDENCE_DIR/12-h2-app-state.json"
echo "  wrote evidence/12-h2-app-state.json"

H2_REV_UNCHANGED="$(echo "$H2_APP_STATE_JSON" | jq -r .latest_revision_unchanged_vs_baseline)"
H2_HTTP="$(echo "$H2_APP_STATE_JSON" | jq -r .ingress_probe_http_code)"
H2_EXPECTATION_MET="$(echo "$H2_APP_STATE_JSON" | jq -r .secret_presence_expectation_met)"
if [[ "$H2_REV_UNCHANGED" != "true" || "$H2_HTTP" != "200" || "$H2_EXPECTATION_MET" != "true" ]]; then
    echo "FAIL (H2 silence gate): revision/ingress/secret absence invariant broken."
    exit 1
fi

echo "[H2] step 15: waiting for H2 firewall Deny log after NEW attempt"
H2_DENY_ROW_COUNT="0"
H2_DENY_ATTEMPT_LOG='[]'
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    echo "  attempt ${attempt}/10: querying H2 Deny rows since $H2_SECRET_SET_START_ISO"
    H2_DENY_ROW_COUNT="$(count_azfw_entra_rows_window "$H2_SECRET_SET_START_ISO" "Deny")"
    H2_DENY_ATTEMPT_LOG="$(echo "$H2_DENY_ATTEMPT_LOG" | jq --arg n "$attempt" --arg c "$H2_DENY_ROW_COUNT" '. + [{attempt: ($n|tonumber), row_count: ($c|tonumber)}]')"
    if [[ "$H2_DENY_ROW_COUNT" -gt 0 ]]; then
        break
    fi
    sleep 60
done
H2_DENY_ROWS_JSON="$(query_azfw_entra_rows_json "$H2_SECRET_SET_START_ISO" "Deny")"

cat > "$EVIDENCE_DIR/13-h2-firewall-deny-log.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "log_analytics_customer_id": "$LAW_CUSTOMER_ID",
  "h2_diag_enable_iso": "$H2_DIAG_ENABLE_ISO",
  "h2_secret_set_start_iso": "$H2_SECRET_SET_START_ISO",
  "kql_window_start_iso": "$H2_SECRET_SET_START_ISO",
  "kql_query": $(printf '%s' "$(build_azfw_entra_kql "$H2_SECRET_SET_START_ISO" "Deny")" | jq -Rs .),
  "final_deny_row_count": $H2_DENY_ROW_COUNT,
  "attempts": $H2_DENY_ATTEMPT_LOG,
  "denied_fqdn_primary": "$ENTRA_FQDN_PRIMARY",
  "denied_fqdn_secondary": "$ENTRA_FQDN_SECONDARY",
  "deny_rows": $H2_DENY_ROWS_JSON
}
EOF
echo "  wrote evidence/13-h2-firewall-deny-log.json  [deny_row_count=$H2_DENY_ROW_COUNT]"
if [[ "$H2_DENY_ROW_COUNT" -lt 1 ]]; then
    echo "FAIL (H2 observability): no Deny row appeared after re-enabling diagnostics and making a NEW attempt."
    exit 1
fi

echo ""
echo "=== falsify.sh complete ==="
echo "Evidence directory: $EVIDENCE_DIR"
echo "  06-h1-firewall-rule-removed.json         [rule absent, AzureFirewallApplicationRule logging disabled]"
echo "  07-h1-secret-set-outcome.json            [exit=nonzero as expected]"
echo "  08-h1-app-state.json                     [silence gate: revision unchanged, ingress 200, kvref-h1 absent]"
echo "  09-h1-firewall-deny-log-absent.json      [deny rows since $H1_START_ISO = $H1_DENY_ROW_COUNT]"
echo "  10-h2-firewall-diagnostics-enabled.json  [logging re-enabled, rule still absent, pre-guard rows=$PRE_H2_GUARD_ROW_COUNT]"
echo "  11-h2-secret-set-outcome.json            [exit=nonzero as expected]"
echo "  12-h2-app-state.json                     [silence gate: revision unchanged, ingress 200, kvref-h2 absent]"
echo "  13-h2-firewall-deny-log.json             [deny rows since $H2_SECRET_SET_START_ISO = $H2_DENY_ROW_COUNT]"
echo ""
echo "H1 verified: connectivity broke and logging gap hid the firewall denial."
echo "H2 verified: connectivity is STILL broken; enabling diagnostics restored observability only."
echo ""
echo "Next: bash verify.sh"
