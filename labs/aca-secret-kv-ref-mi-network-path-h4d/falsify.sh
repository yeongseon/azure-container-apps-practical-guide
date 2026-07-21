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
VNET_RESOURCE_ID="$(jq -r .vnet_resource_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
ACA_SUBNET_PREFIX="$(jq -r .aca_subnet_prefix "$EVIDENCE_DIR/01-deployment-outputs.json")"
VHUB_RESOURCE_ID="$(jq -r .virtual_hub_resource_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
AZFW_RESOURCE_ID="$(jq -r .azure_firewall_resource_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
FIREWALL_POLICY_RESOURCE_ID="$(jq -r .firewall_policy_resource_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
FIREWALL_LAW_CUSTOMER_ID="$(jq -r '.firewall_log_analytics_customer_id // empty' "$EVIDENCE_DIR/01-deployment-outputs.json")"
ROUTING_INTENT_NAME="$(jq -r .routing_intent_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
CONNECTION_NAME_PREFIX="$(jq -r .vhub_connection_name_prefix "$EVIDENCE_DIR/01-deployment-outputs.json")"
LATEST_REV_BASELINE="$(jq -r .latest_ready_revision_name "$EVIDENCE_DIR/05-h0-app-state-after.json")"
APP_FQDN="$(jq -r .ingress_fqdn "$EVIDENCE_DIR/02-h0-app-state-before.json")"

if [[ -z "$VHUB_RESOURCE_ID" || -z "$AZFW_RESOURCE_ID" || -z "$FIREWALL_POLICY_RESOURCE_ID" ]]; then
    echo "ERROR: Virtual Hub / Azure Firewall / Firewall Policy anchors are missing from evidence/01-deployment-outputs.json."
    exit 1
fi

resource_group_from_id() {
    local resource_id="$1"
    printf '%s' "$resource_id" | awk -F/ '{for (i = 1; i <= NF; i++) if ($i == "resourceGroups") {print $(i + 1); exit}}'
}

resource_name_from_id() {
    local resource_id="$1"
    printf '%s' "$resource_id" | awk -F/ '{print $NF}'
}

VHUB_RG="$(resource_group_from_id "$VHUB_RESOURCE_ID")"
VHUB_NAME="$(resource_name_from_id "$VHUB_RESOURCE_ID")"
AZFW_NAME="$(resource_name_from_id "$AZFW_RESOURCE_ID")"
CONNECTION_NAME="${CONNECTION_NAME_PREFIX}-ri"

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

build_azfw_entra_kql() {
    local since_iso="$1"
    cat <<EOF
union isfuzzy=true
(AZFWApplicationRule
    | where TimeGenerated >= datetime('${since_iso}')
    | where Fqdn has 'login.microsoftonline.com' or Fqdn has 'login.microsoft.com'
    | project TimeGenerated, Fqdn, SourceIp, Action, Policy, RuleCollectionGroup, RuleCollection, Rule, Source='AZFWApplicationRule'),
(AzureDiagnostics
    | where TimeGenerated >= datetime('${since_iso}')
    | where Category == 'AzureFirewallApplicationRule'
    | where msg_s contains 'login.microsoftonline.com' or msg_s contains 'login.microsoft.com'
    | project TimeGenerated, Fqdn=extract(@'to (\\S+):443', 1, msg_s), SourceIp=extract(@'from (\\d+\\.\\d+\\.\\d+\\.\\d+)', 1, msg_s), Action=extract(@' Action: (\\w+)', 1, msg_s), Policy='', RuleCollectionGroup='', RuleCollection='', Rule='', Source='AzureDiagnostics')
| order by TimeGenerated desc
| take 20
EOF
}

query_azfw_clue_json() {
    local phase="$1"
    local since_iso="$2"
    local file_name="$3"
    if [[ -z "$FIREWALL_LAW_CUSTOMER_ID" || "$FIREWALL_LAW_CUSTOMER_ID" == "null" ]]; then
        cat > "$EVIDENCE_DIR/$file_name" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "available": false,
  "firewall_log_analytics_customer_id": null,
  "note": "Best-effort diagnostic clue not captured because no firewall Log Analytics customer ID was supplied for this cohort.",
  "deterministic_pass_condition": false
}
EOF
        return
    fi

    local kql
    kql="$(build_azfw_entra_kql "$since_iso")"
    local rows_json
    rows_json="$(az monitor log-analytics query --workspace "$FIREWALL_LAW_CUSTOMER_ID" --analytics-query "$kql" --output json 2>/dev/null || echo '[]')"
    local row_count
    row_count="$(echo "$rows_json" | jq 'length')"
    cat > "$EVIDENCE_DIR/$file_name" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "available": true,
  "firewall_log_analytics_customer_id": "$FIREWALL_LAW_CUSTOMER_ID",
  "kql_window_start_iso": "$since_iso",
  "kql_query": $(printf '%s' "$kql" | jq -Rs .),
  "row_count": $row_count,
  "rows": $rows_json,
  "note": "A zero-row result is a real-world H4d escalation clue, not the deterministic pass condition for this reproducer. If diagnostics are enabled and the packet reaches Azure Firewall, Deny rows may appear.",
  "deterministic_pass_condition": false
}
EOF
}

get_effective_routes_json() {
    az network vhub get-effective-routes \
        --resource-type HubVirtualNetworkConnection \
        --resource-id "$1" \
        --name "$VHUB_NAME" \
        --resource-group "$VHUB_RG" \
        --output json
}

extract_default_route_targets_json() {
    jq '[.value[]? | select(((.addressPrefixes // []) | index("0.0.0.0/0")) != null) | {addressPrefixes: (.addressPrefixes // []), nextHopType: .nextHopType, nextHops: (.nextHops // []), routeOrigin: .routeOrigin}]'
}

default_route_targets_firewall() {
    local routes_json="$1"
    echo "$routes_json" | jq -e --arg fw "$AZFW_RESOURCE_ID" --arg fwname "$AZFW_NAME" '
      [.value[]? | select(((.addressPrefixes // []) | index("0.0.0.0/0")) != null)]
      | any(
          ((.nextHops // [])[]? | tostring);
          . == $fw or . == $fwname or (. | contains($fwname)) or (. | contains($fw))
        )
    ' >/dev/null
}

echo "falsify.sh started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  RG                        = $RG"
echo "  APP_NAME                  = $APP_NAME"
echo "  KV_NAME                   = $KV_NAME"
echo "  VNET_NAME                 = $VNET_NAME"
echo "  VHUB_NAME                 = $VHUB_NAME"
echo "  AZFW_NAME                 = $AZFW_NAME"
echo "  ACA_SUBNET_PREFIX         = $ACA_SUBNET_PREFIX"
echo "  LATEST_REV_BASELINE       = $LATEST_REV_BASELINE"
echo ""

echo "[H1] step 1: connecting the ACTUAL ACA infrastructure VNet to the Virtual Hub"
H1_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if az network vhub routing-intent show --name "$ROUTING_INTENT_NAME" --resource-group "$VHUB_RG" --vhub "$VHUB_NAME" --output none 2>/dev/null; then
    echo "ERROR: Routing Intent '$ROUTING_INTENT_NAME' already exists on the target Virtual Hub."
    echo "This lab requires H0 to start without an active Routing Intent path through the secured hub. Use a dedicated hub or remove the existing intent before running the lab."
    exit 1
fi
if az network vhub connection show --name "$CONNECTION_NAME" --resource-group "$VHUB_RG" --vhub-name "$VHUB_NAME" --output none 2>/dev/null; then
    echo "ERROR: HubVirtualNetworkConnection '$CONNECTION_NAME' already exists on the target Virtual Hub."
    echo "Run cleanup.sh or remove the stale lab connection before re-running falsify.sh."
    exit 1
fi
CONNECTION_JSON="$(az network vhub connection create \
    --name "$CONNECTION_NAME" \
    --remote-vnet "$VNET_RESOURCE_ID" \
    --resource-group "$VHUB_RG" \
    --vhub-name "$VHUB_NAME" \
    --internet-security true \
    --output json)"
ACA_VNET_CONNECTION_ID="$(echo "$CONNECTION_JSON" | jq -r .id)"

echo "[H1] step 2: enabling Routing Intent to the hub Azure Firewall"
ROUTING_POLICIES_JSON="$(jq -nc --arg fw "$AZFW_RESOURCE_ID" '[
  {name:"InternetTraffic", destinations:["Internet"], nextHop:$fw},
  {name:"PrivateTraffic", destinations:["PrivateTraffic"], nextHop:$fw}
]')"
if az network vhub routing-intent show --name "$ROUTING_INTENT_NAME" --resource-group "$VHUB_RG" --vhub "$VHUB_NAME" --output none 2>/dev/null; then
    az network vhub routing-intent update \
        --name "$ROUTING_INTENT_NAME" \
        --resource-group "$VHUB_RG" \
        --vhub "$VHUB_NAME" \
        --routing-policies "$ROUTING_POLICIES_JSON" \
        --output none
else
    az network vhub routing-intent create \
        --name "$ROUTING_INTENT_NAME" \
        --resource-group "$VHUB_RG" \
        --vhub "$VHUB_NAME" \
        --routing-policies "$ROUTING_POLICIES_JSON" \
        --output none
fi

echo "[H1] step 3: polling until Routing Intent is Succeeded and effective routes show 0.0.0.0/0 -> hub firewall"
RI_READY="false"
ROUTING_INTENT_JSON='{}'
EFFECTIVE_ROUTES_JSON='{"value":[]}'
DEFAULT_ROUTE_TARGETS_JSON='[]'
CONNECTION_STATE_JSON='{}'
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    CONNECTION_STATE_JSON="$(az network vhub connection show --name "$CONNECTION_NAME" --resource-group "$VHUB_RG" --vhub-name "$VHUB_NAME" --output json)"
    ROUTING_INTENT_JSON="$(az network vhub routing-intent show --name "$ROUTING_INTENT_NAME" --resource-group "$VHUB_RG" --vhub "$VHUB_NAME" --output json 2>/dev/null || echo '{}')"
    EFFECTIVE_ROUTES_JSON="$(get_effective_routes_json "$ACA_VNET_CONNECTION_ID")"
    DEFAULT_ROUTE_TARGETS_JSON="$(echo "$EFFECTIVE_ROUTES_JSON" | extract_default_route_targets_json)"
    RI_STATE="$(echo "$ROUTING_INTENT_JSON" | jq -r '.provisioningState // .properties.provisioningState // "Unknown"')"
    CONN_STATE="$(echo "$CONNECTION_STATE_JSON" | jq -r '.provisioningState // .properties.provisioningState // "Unknown"')"
    if [[ "$RI_STATE" == "Succeeded" && "$CONN_STATE" == "Succeeded" ]] && default_route_targets_firewall "$EFFECTIVE_ROUTES_JSON"; then
        RI_READY="true"
        break
    fi
    echo "  attempt $attempt: connection=$CONN_STATE routing_intent=$RI_STATE default_route_to_firewall=$(default_route_targets_firewall "$EFFECTIVE_ROUTES_JSON" && echo true || echo false)"
    sleep 30
done
if [[ "$RI_READY" != "true" ]]; then
    echo "FAIL (H1 convergence): Routing Intent never reached Succeeded with 0.0.0.0/0 targeting the hub firewall."
    exit 1
fi

cat > "$EVIDENCE_DIR/06-h1-routing-intent-enabled.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "action": "connect-aca-vnet-to-vhub-and-enable-routing-intent",
  "h1_start_iso": "$H1_START_ISO",
  "virtual_hub_resource_id": "$VHUB_RESOURCE_ID",
  "virtual_hub_name": "$VHUB_NAME",
  "virtual_hub_resource_group": "$VHUB_RG",
  "azure_firewall_resource_id": "$AZFW_RESOURCE_ID",
  "firewall_policy_resource_id": "$FIREWALL_POLICY_RESOURCE_ID",
  "routing_intent_name": "$ROUTING_INTENT_NAME",
  "aca_vnet_connection_id": "$ACA_VNET_CONNECTION_ID",
  "aca_vnet_connection_name": "$CONNECTION_NAME",
  "remote_vnet_resource_id": $(echo "$CONNECTION_STATE_JSON" | jq '.remoteVirtualNetwork.id // .properties.remoteVirtualNetwork.id // null'),
  "expected_default_route_prefix": "0.0.0.0/0",
  "expected_next_hop_resource_id": "$AZFW_RESOURCE_ID",
  "routing_intent_show": $ROUTING_INTENT_JSON,
  "connection_show": $CONNECTION_STATE_JSON,
  "effective_routes": $EFFECTIVE_ROUTES_JSON,
  "default_route_targets": $DEFAULT_ROUTE_TARGETS_JSON,
  "routing_intent_provisioning_succeeded": true,
  "connection_provisioning_succeeded": true,
  "default_route_targets_expected_firewall": true
}
EOF
echo "  wrote evidence/06-h1-routing-intent-enabled.json"

SECRET_NAME_H1="kvref-h1-value"
SECRET_VALUE_H1="h1-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H1] step 4: creating KV secret '$SECRET_NAME_H1'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H1" --value "$SECRET_VALUE_H1" --output none
KV_SECRET_URL_H1="${KV_URI}secrets/${SECRET_NAME_H1}"

H1_SECRET_REF_NAME="kvref-h1"
echo "[H1] step 5: attempting 'az containerapp secret set --identity system' (MUST FAIL)"
SET_STDOUT_FILE="$(mktemp)"
SET_STDERR_FILE="$(mktemp)"
SET_EXIT=0
az containerapp secret set \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --secrets "${H1_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H1},identityref:system" \
    --output json >"$SET_STDOUT_FILE" 2>"$SET_STDERR_FILE" || SET_EXIT=$?
SET_STDOUT="$(<"$SET_STDOUT_FILE")"
SET_STDERR="$(<"$SET_STDERR_FILE")"
rm -f "$SET_STDOUT_FILE" "$SET_STDERR_FILE"

STDERR_MATCH_FAILED_UPDATE=false
STDERR_MATCH_UNABLE_MI=false
STDERR_MATCH_OPENID=false
STDERR_MATCH_LOGIN_HOST=false
if [[ "$SET_STDERR" == *"Failed to update secrets"* ]]; then STDERR_MATCH_FAILED_UPDATE=true; fi
if [[ "$SET_STDERR" == *"Unable to get value using Managed identity"* ]]; then STDERR_MATCH_UNABLE_MI=true; fi
if [[ "$SET_STDERR" == *"openid-configuration"* ]]; then STDERR_MATCH_OPENID=true; fi
if [[ "$SET_STDERR" == *"login.microsoft"* ]]; then STDERR_MATCH_LOGIN_HOST=true; fi

cat > "$EVIDENCE_DIR/07-h1-secret-set-outcome.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "hypothesis": "H1: Routing Intent forces egress through the secured hub firewall, Key Vault public FQDNs stay allowed, Entra authority remains blocked -> secret set FAILS at managed-identity OIDC discovery",
  "h1_start_iso": "$H1_START_ISO",
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${H1_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H1},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code_nonzero": true,
  "outcome": $([ $SET_EXIT -ne 0 ] && echo '"failure"' || echo '"success"'),
  "stderr_substring_matches": {
    "failed_to_update_secrets": $STDERR_MATCH_FAILED_UPDATE,
    "unable_to_get_value_using_managed_identity": $STDERR_MATCH_UNABLE_MI,
    "openid_configuration_reference": $STDERR_MATCH_OPENID,
    "login_microsoft_host_reference": $STDERR_MATCH_LOGIN_HOST
  },
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/07-h1-secret-set-outcome.json  [exit=$SET_EXIT]"
if [[ $SET_EXIT -eq 0 ]]; then
    echo "FAIL (H1): secret set unexpectedly succeeded with Routing Intent ON."
    exit 1
fi

echo "[H1] step 6: silence gate (revision unchanged + ingress 200 + kvref-h1 absent)"
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

echo "[H1] step 7: capturing best-effort Azure Firewall diagnostic clue (not a deterministic pass condition)"
query_azfw_clue_json "H1" "$H1_START_ISO" "09-h1-azfw-diagnostic-clue.json"
echo "  wrote evidence/09-h1-azfw-diagnostic-clue.json"

echo "[H2] step 8: disabling/removing Routing Intent while leaving firewall policy unchanged"
H2_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az network vhub routing-intent delete \
    --name "$ROUTING_INTENT_NAME" \
    --resource-group "$VHUB_RG" \
    --vhub "$VHUB_NAME" \
    --yes \
    --output none

echo "[H2] step 9: polling until effective routes no longer show 0.0.0.0/0 targeting the hub firewall"
RI_REMOVED="false"
ROUTING_INTENT_SHOW_AFTER='{}'
EFFECTIVE_ROUTES_AFTER='{"value":[]}'
DEFAULT_ROUTE_TARGETS_AFTER='[]'
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    ROUTING_INTENT_SHOW_AFTER="$(az network vhub routing-intent show --name "$ROUTING_INTENT_NAME" --resource-group "$VHUB_RG" --vhub "$VHUB_NAME" --output json 2>/dev/null || echo '{}')"
    EFFECTIVE_ROUTES_AFTER="$(get_effective_routes_json "$ACA_VNET_CONNECTION_ID")"
    DEFAULT_ROUTE_TARGETS_AFTER="$(echo "$EFFECTIVE_ROUTES_AFTER" | extract_default_route_targets_json)"
    if ! default_route_targets_firewall "$EFFECTIVE_ROUTES_AFTER"; then
        RI_REMOVED="true"
        break
    fi
    echo "  attempt $attempt: routing intent still steering default route to firewall, retrying in 30s..."
    sleep 30
done
if [[ "$RI_REMOVED" != "true" ]]; then
    echo "FAIL (H2 convergence): effective routes still show 0.0.0.0/0 targeting the hub firewall after Routing Intent removal."
    exit 1
fi

cat > "$EVIDENCE_DIR/10-h2-routing-intent-removed.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "action": "remove-routing-intent-leave-firewall-policy-unchanged",
  "h2_start_iso": "$H2_START_ISO",
  "virtual_hub_resource_id": "$VHUB_RESOURCE_ID",
  "virtual_hub_name": "$VHUB_NAME",
  "virtual_hub_resource_group": "$VHUB_RG",
  "azure_firewall_resource_id": "$AZFW_RESOURCE_ID",
  "routing_intent_name": "$ROUTING_INTENT_NAME",
  "aca_vnet_connection_id": "$ACA_VNET_CONNECTION_ID",
  "routing_intent_show_after_delete": $ROUTING_INTENT_SHOW_AFTER,
  "effective_routes_after_delete": $EFFECTIVE_ROUTES_AFTER,
  "default_route_targets_after_delete": $DEFAULT_ROUTE_TARGETS_AFTER,
  "default_route_targets_expected_firewall": false,
  "firewall_policy_resource_id": "$FIREWALL_POLICY_RESOURCE_ID"
}
EOF
echo "  wrote evidence/10-h2-routing-intent-removed.json"

SECRET_NAME_H2="kvref-h2-value"
SECRET_VALUE_H2="h2-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H2] step 10: creating KV secret '$SECRET_NAME_H2'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H2" --value "$SECRET_VALUE_H2" --output none
KV_SECRET_URL_H2="${KV_URI}secrets/${SECRET_NAME_H2}"

H2_SECRET_REF_NAME="kvref-h2"
echo "[H2] step 11: attempting NEW 'az containerapp secret set --identity system' (MUST SUCCEED)"
SET_STDOUT_FILE="$(mktemp)"
SET_STDERR_FILE="$(mktemp)"
SET_EXIT=0
az containerapp secret set \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --secrets "${H2_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H2},identityref:system" \
    --output json >"$SET_STDOUT_FILE" 2>"$SET_STDERR_FILE" || SET_EXIT=$?
SET_STDOUT="$(<"$SET_STDOUT_FILE")"
SET_STDERR="$(<"$SET_STDERR_FILE")"
rm -f "$SET_STDOUT_FILE" "$SET_STDERR_FILE"

cat > "$EVIDENCE_DIR/11-h2-secret-set-outcome.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "hypothesis": "H2: Routing Intent removed while firewall policy stays unchanged -> NEW secret set SUCCEEDS again",
  "h2_start_iso": "$H2_START_ISO",
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
    echo "FAIL (H2): secret set did not recover after Routing Intent removal."
    exit 1
fi

echo "[H2] step 12: success gate (revision unchanged + ingress 200 + kvref-h2 present)"
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

echo "[H2] step 13: capturing best-effort Azure Firewall diagnostic clue after Routing Intent removal"
query_azfw_clue_json "H2" "$H2_START_ISO" "13-h2-azfw-diagnostic-clue.json"
echo "  wrote evidence/13-h2-azfw-diagnostic-clue.json"

echo ""
echo "=== falsify.sh complete ==="
echo "Evidence directory: $EVIDENCE_DIR"
echo "  06-h1-routing-intent-enabled.json      [routing intent converged, default route targets hub firewall]"
echo "  07-h1-secret-set-outcome.json          [exit=nonzero as expected]"
echo "  08-h1-app-state.json                   [silence gate: revision unchanged, ingress 200, kvref-h1 absent]"
echo "  09-h1-azfw-diagnostic-clue.json        [best-effort clue only; not a deterministic pass condition]"
echo "  10-h2-routing-intent-removed.json      [routing intent removed, default route no longer targets hub firewall]"
echo "  11-h2-secret-set-outcome.json          [exit=0 as expected]"
echo "  12-h2-app-state.json                   [success gate: revision unchanged, ingress 200, kvref-h2 present]"
echo "  13-h2-azfw-diagnostic-clue.json        [best-effort clue only; not a deterministic pass condition]"
echo ""
echo "H1 verified: Routing Intent ON forced the failure with the firewall policy unchanged."
echo "H2 verified: Routing Intent OFF restored success with the same Key Vault, identity, app, and firewall policy."
echo ""
echo "Next: bash verify.sh"
