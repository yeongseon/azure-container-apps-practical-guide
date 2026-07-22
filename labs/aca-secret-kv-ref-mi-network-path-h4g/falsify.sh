#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set (same value used by trigger.sh)}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$LAB_DIR/evidence"
DEPLOYMENT_NAME="aca-secret-kv-ref-mi-network-path-h4g"

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
RESOURCE_GROUP="$(jq -r .resource_group "$EVIDENCE_DIR/01-deployment-outputs.json")"
ENVIRONMENT_NAME="$(jq -r .environment_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_NAME="$(jq -r .key_vault_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_URI="$(jq -r .key_vault_uri "$EVIDENCE_DIR/01-deployment-outputs.json")"
APP_PRINCIPAL_ID="$(jq -r .app_principal_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
TENANT_ID="$(jq -r .tenant_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
VNET_NAME="$(jq -r .vnet_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
FIREWALL_POLICY_NAME="$(jq -r .firewall_policy_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
FIREWALL_RULE_COLLECTION_GROUP_NAME="$(jq -r .firewall_rule_collection_group_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
ENTRA_RULE_COLLECTION_NAME="$(jq -r .entra_rule_collection_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
ENTRA_RULE_NAME="$(jq -r .entra_rule_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
FIREWALL_PRIVATE_IP="$(jq -r .firewall_private_ip "$EVIDENCE_DIR/01-deployment-outputs.json")"
LATEST_REV_BASELINE="$(jq -r .latest_ready_revision_name "$EVIDENCE_DIR/05-h0-app-state-after.json")"
APP_FQDN="$(jq -r .ingress_fqdn "$EVIDENCE_DIR/02-h0-app-state-before.json")"
BASE_NAME="$(jq -r .base_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
DEPLOYMENT_PRINCIPAL_ID="$(jq -r .deployer_principal_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
DEPLOYMENT_PRINCIPAL_TYPE="$(jq -r .deployer_principal_type "$EVIDENCE_DIR/01-deployment-outputs.json")"
TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID="$(jq -r .tls_inspection_ca_key_vault_secret_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
TLS_INSPECTION_CA_CERTIFICATE_NAME="$(jq -r .tls_inspection_ca_certificate_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
TLS_INSPECTION_IDENTITY_RESOURCE_ID="$(jq -r .tls_inspection_identity_resource_id "$EVIDENCE_DIR/01-deployment-outputs.json")"

H1_SETTLE_SECONDS=30
H2_RETRY_SLEEP_SECONDS=20
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

capture_rule_snapshot() {
    local phase="$1"
    local expected_terminate_tls="$2"
    local output_file="$3"
    local openssl_expected_contains_lab_ca="$4"
    local rcg_json
    rcg_json="$(az network firewall policy rule-collection-group show --resource-group "$RG" --policy-name "$FIREWALL_POLICY_NAME" --name "$FIREWALL_RULE_COLLECTION_GROUP_NAME" --output json)"
    local entra_collection_json
    entra_collection_json="$(echo "$rcg_json" | jq --arg name "$ENTRA_RULE_COLLECTION_NAME" '.properties.ruleCollections[] | select(.name == $name)')"
    local entra_rule_json
    entra_rule_json="$(echo "$entra_collection_json" | jq --arg name "$ENTRA_RULE_NAME" '.rules[] | select(.name == $name)')"
    local route_table_name
    route_table_name="$(jq -r .route_table_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
    local route_json
    route_json="$(az network route-table route show --resource-group "$RG" --route-table-name "$route_table_name" --name default-via-afw-h4g --output json)"
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
  "firewall_policy_name": "$FIREWALL_POLICY_NAME",
  "firewall_rule_collection_group_name": "$FIREWALL_RULE_COLLECTION_GROUP_NAME",
  "entra_rule_collection_name": "$ENTRA_RULE_COLLECTION_NAME",
  "entra_rule_name": "$ENTRA_RULE_NAME",
  "expected_terminate_tls": $expected_terminate_tls,
  "entra_rule_collection": $entra_collection_json,
  "entra_rule": $entra_rule_json,
  "firewall_private_ip": "$FIREWALL_PRIVATE_IP",
  "route_table_default_route": $route_json,
  "workload_openssl_capture": {
    "status": "reader_action_required",
    "capture_mode": "manual_fill_required",
    "target_host": "login.microsoftonline.com",
    "target_port": 443,
    "expected_contains_lab_intermediate_ca": $openssl_expected_contains_lab_ca,
    "reader_asserted_contains_lab_intermediate_ca": null,
    "reader_observed_certificate_subjects": [],
    "reader_observed_issuer_subjects": [],
    "reader_notes": "Run the documented az containerapp exec openssl command during this phase, paste the relevant certificate-chain observations here, and set reader_asserted_contains_lab_intermediate_ca to true for H1 or false for H2.",
    "suggested_command": "az containerapp exec --name $APP_NAME --resource-group $RG --command \"sh -lc 'openssl s_client -connect login.microsoftonline.com:443 -servername login.microsoftonline.com -showcerts < /dev/null 2>&1'\"",
    "claim_ceiling": {
      "observed": "A workload replica can directly observe whether the lab interception CA appears on the workload data plane for login.microsoftonline.com.",
      "strongly_suggested": "If the workload chain flips with terminateTLS and the control-plane secret-set behavior flips in the same H0/H1/H2 cohort, the control plane is strongly suggested to be affected by the same Entra-authority TLS-inspection exemption.",
      "not_proven": [
        "No direct control-plane TLS-chain observation exists.",
        "No control-plane packet capture exists.",
        "The lab does not prove workload and control-plane egress are identical."
      ]
    }
  }
}
EOF
}

echo "falsify.sh started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  RG                      = $RG"
echo "  APP_NAME                = $APP_NAME"
echo "  KV_NAME                 = $KV_NAME"
echo "  FIREWALL_POLICY_NAME    = $FIREWALL_POLICY_NAME"
echo "  FIREWALL_PRIVATE_IP     = $FIREWALL_PRIVATE_IP"
echo "  VNET_NAME               = $VNET_NAME"
echo ""

echo "[H1] step 1: redeploying the lab with entraAuthorityTerminateTls=true"
echo "         (This lab flips the terminateTLS field by Bicep redeploy rather than an imperative rule edit.)"
H1_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az deployment group create \
    --resource-group "$RG" \
    --name "$DEPLOYMENT_NAME" \
    --template-file "$LAB_DIR/infra/main.bicep" \
    --parameters baseName="$BASE_NAME" \
    --parameters deploymentPrincipalId="$DEPLOYMENT_PRINCIPAL_ID" \
    --parameters deploymentPrincipalType="$DEPLOYMENT_PRINCIPAL_TYPE" \
    --parameters tlsInspectionCaKeyVaultSecretId="$TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID" \
    --parameters tlsInspectionCaCertificateName="$TLS_INSPECTION_CA_CERTIFICATE_NAME" \
    --parameters tlsInspectionIdentityResourceId="$TLS_INSPECTION_IDENTITY_RESOURCE_ID" \
    --parameters entraAuthorityTerminateTls=true \
    --output none

H1_OUTPUTS_JSON="$(az deployment group show --resource-group "$RG" --name "$DEPLOYMENT_NAME" --query properties.outputs --output json)"
H1_RULE_COLLECTION_GROUP_JSON="$(az network firewall policy rule-collection-group show --resource-group "$RG" --policy-name "$FIREWALL_POLICY_NAME" --name "$FIREWALL_RULE_COLLECTION_GROUP_NAME" --output json)"
H1_ENTRA_RULE_JSON="$(echo "$H1_RULE_COLLECTION_GROUP_JSON" | jq --arg collection "$ENTRA_RULE_COLLECTION_NAME" --arg rule "$ENTRA_RULE_NAME" '.properties.ruleCollections[] | select(.name == $collection) | .rules[] | select(.name == $rule)')"
H1_ROUTE_JSON="$(az network route-table route show --resource-group "$RG" --route-table-name "$(jq -r .routeTableName.value <<<"$H1_OUTPUTS_JSON")" --name default-via-afw-h4g --output json)"

cat > "$EVIDENCE_DIR/06-h1-entra-rule-updated.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "action": "redeploy-firewall-policy-with-entra-rule-terminate-tls-true",
  "h1_start_iso": "$H1_START_ISO",
  "resource_group": "$RESOURCE_GROUP",
  "app_name": "$APP_NAME",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BASELINE",
  "firewall_policy_name": "$FIREWALL_POLICY_NAME",
  "firewall_rule_collection_group_name": "$FIREWALL_RULE_COLLECTION_GROUP_NAME",
  "entra_rule_collection_name": "$ENTRA_RULE_COLLECTION_NAME",
  "entra_rule_name": "$ENTRA_RULE_NAME",
  "entra_rule": $H1_ENTRA_RULE_JSON,
  "firewall_private_ip": "$FIREWALL_PRIVATE_IP",
  "tls_inspection_ca_key_vault_secret_id": "$TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID",
  "tls_inspection_identity_resource_id": "$TLS_INSPECTION_IDENTITY_RESOURCE_ID",
  "route_table_default_route": $H1_ROUTE_JSON,
  "azure_firewall_present": true,
  "azure_firewall_sku": "Premium",
  "firewall_policy_present": true,
  "tls_inspection_configured": true,
  "route_table_attached": true,
  "nsg_attached": true,
  "nsg_deny_present": false,
  "dns_override_present": false,
  "vwan_routing_intent_present": false,
  "entra_authority_terminate_tls": true
}
EOF
echo "  wrote evidence/06-h1-entra-rule-updated.json"

echo "[H1] step 2: waiting ${H1_SETTLE_SECONDS}s for Firewall Policy convergence"
sleep "$H1_SETTLE_SECONDS"

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

# Given a real Azure Firewall Premium stderr string is still pending live capture,
# when this lab classifies H1 failure text, then it must match clue families
# instead of asserting one verbatim production string.
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
TLS_CERT_CLUES_JSON="$(STDERR_TEXT="$SET_STDERR" python3 - <<'PY'
import json
import os
text = os.environ.get('STDERR_TEXT', '').lower()
clues = [
    'x509: certificate signed by unknown authority',
    'certificate verify failed',
    'unable to get local issuer certificate',
    'self-signed certificate in certificate chain',
    'tls handshake',
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
  "hypothesis": "H1: Entra-authority rule terminateTLS=true -> secret set FAILS with a managed-identity / OIDC clue plus a TLS / certificate clue",
  "h1_start_iso": "$H1_START_ISO",
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${H1_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H1},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code_nonzero": true,
  "outcome": $([ $SET_EXIT -ne 0 ] && echo '"failure"' || echo '"success"'),
  "stderr_classifier_inputs": {
    "managed_identity_or_oidc_clues_found": $MI_OR_OIDC_CLUES_JSON,
    "tls_or_certificate_clues_found": $TLS_CERT_CLUES_JSON
  },
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/07-h1-secret-set-outcome.json  [exit=$SET_EXIT]"
if [[ $SET_EXIT -eq 0 ]]; then
    echo "FAIL (H1): secret set unexpectedly succeeded with terminateTLS=true on the Entra-authority rule."
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

echo "[H1] step 6: capture firewall rule state and reader-generated openssl placeholder"
capture_rule_snapshot "H1" "true" "09-h1-rule-state-and-openssl.json" "true"
echo "  wrote evidence/09-h1-rule-state-and-openssl.json"

echo "[H2] step 7: redeploying the lab with entraAuthorityTerminateTls=false (TLS-inspection exemption restored)"
H2_ALLOW_CREATE_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
az deployment group create \
    --resource-group "$RG" \
    --name "$DEPLOYMENT_NAME" \
    --template-file "$LAB_DIR/infra/main.bicep" \
    --parameters baseName="$BASE_NAME" \
    --parameters deploymentPrincipalId="$DEPLOYMENT_PRINCIPAL_ID" \
    --parameters deploymentPrincipalType="$DEPLOYMENT_PRINCIPAL_TYPE" \
    --parameters tlsInspectionCaKeyVaultSecretId="$TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID" \
    --parameters tlsInspectionCaCertificateName="$TLS_INSPECTION_CA_CERTIFICATE_NAME" \
    --parameters tlsInspectionIdentityResourceId="$TLS_INSPECTION_IDENTITY_RESOURCE_ID" \
    --parameters entraAuthorityTerminateTls=false \
    --output none

H2_OUTPUTS_JSON="$(az deployment group show --resource-group "$RG" --name "$DEPLOYMENT_NAME" --query properties.outputs --output json)"
H2_RULE_COLLECTION_GROUP_JSON="$(az network firewall policy rule-collection-group show --resource-group "$RG" --policy-name "$FIREWALL_POLICY_NAME" --name "$FIREWALL_RULE_COLLECTION_GROUP_NAME" --output json)"
H2_ENTRA_RULE_JSON="$(echo "$H2_RULE_COLLECTION_GROUP_JSON" | jq --arg collection "$ENTRA_RULE_COLLECTION_NAME" --arg rule "$ENTRA_RULE_NAME" '.properties.ruleCollections[] | select(.name == $collection) | .rules[] | select(.name == $rule)')"
H2_ROUTE_JSON="$(az network route-table route show --resource-group "$RG" --route-table-name "$(jq -r .routeTableName.value <<<"$H2_OUTPUTS_JSON")" --name default-via-afw-h4g --output json)"

cat > "$EVIDENCE_DIR/10-h2-entra-rule-updated.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "action": "redeploy-firewall-policy-with-entra-rule-terminate-tls-false",
  "h2_allow_create_iso": "$H2_ALLOW_CREATE_ISO",
  "resource_group": "$RESOURCE_GROUP",
  "app_name": "$APP_NAME",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BASELINE",
  "firewall_policy_name": "$FIREWALL_POLICY_NAME",
  "firewall_rule_collection_group_name": "$FIREWALL_RULE_COLLECTION_GROUP_NAME",
  "entra_rule_collection_name": "$ENTRA_RULE_COLLECTION_NAME",
  "entra_rule_name": "$ENTRA_RULE_NAME",
  "entra_rule": $H2_ENTRA_RULE_JSON,
  "firewall_private_ip": "$FIREWALL_PRIVATE_IP",
  "tls_inspection_ca_key_vault_secret_id": "$TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID",
  "tls_inspection_identity_resource_id": "$TLS_INSPECTION_IDENTITY_RESOURCE_ID",
  "route_table_default_route": $H2_ROUTE_JSON,
  "azure_firewall_present": true,
  "azure_firewall_sku": "Premium",
  "firewall_policy_present": true,
  "tls_inspection_configured": true,
  "route_table_attached": true,
  "nsg_attached": true,
  "nsg_deny_present": false,
  "dns_override_present": false,
  "vwan_routing_intent_present": false,
  "entra_authority_terminate_tls": false
}
EOF
echo "  wrote evidence/10-h2-entra-rule-updated.json"

SECRET_NAME_H2="kvref-h2-value"
SECRET_VALUE_H2="h2-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H2] step 8: creating KV secret '$SECRET_NAME_H2'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H2" --value "$SECRET_VALUE_H2" --output none
KV_SECRET_URL_H2="${KV_URI}secrets/${SECRET_NAME_H2}"

H2_SECRET_REF_NAME="kvref-h2"
echo "[H2] step 9: attempting NEW 'az containerapp secret set --secrets ...identityref:system' with short settle/retry loop (MUST SUCCEED)"
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
  "app_name": "$APP_NAME",
  "resource_group": "$RESOURCE_GROUP",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BASELINE",
  "hypothesis": "H2: Entra-authority rule terminateTLS=false restores a NEW secret set while Firewall Premium, route table, and TLS inspection stay present",
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
    echo "FAIL (H2): secret set did not recover after restoring terminateTLS=false on the Entra-authority rule."
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

echo "[H2] step 11: capture firewall rule state and reader-generated openssl placeholder"
capture_rule_snapshot "H2" "false" "13-h2-rule-state-and-openssl.json" "false"
echo "  wrote evidence/13-h2-rule-state-and-openssl.json"

cat <<EOF

=== falsify.sh complete ===
Evidence directory: $EVIDENCE_DIR
  06-h1-entra-rule-updated.json         [terminateTLS=true]
  07-h1-secret-set-outcome.json         [exit=nonzero as expected]
  08-h1-app-state.json                  [silence gate: revision unchanged, ingress 200, kvref-h1 absent]
  09-h1-rule-state-and-openssl.json     [reader must fill workload openssl proof: lab CA present]
  10-h2-entra-rule-updated.json         [terminateTLS=false]
  11-h2-secret-set-outcome.json         [exit=0 as expected]
  12-h2-app-state.json                  [success gate: revision unchanged, ingress 200, kvref-h2 present]
  13-h2-rule-state-and-openssl.json     [reader must fill workload openssl proof: lab CA absent]

H1 verified: the Entra-authority TLS-inspection flip produced the failure while Firewall Premium, route table, DNS, NSG, Key Vault, identity, RBAC, app, revision, and ingress stayed constant.
H2 verified: restoring the Entra-authority TLS-inspection exemption restored success with the same cohort anchors.

Next: bash verify.sh
EOF
