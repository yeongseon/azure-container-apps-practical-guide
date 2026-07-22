#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set (e.g. rg-aca-kv-mi-netpath-h4g)}"
: "${LOCATION:?LOCATION must be set (e.g. koreacentral)}"
: "${BASE_NAME:?BASE_NAME must be set (3-11 chars, lowercase alphanumeric, e.g. acasech4g01)}"
: "${TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID:?TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID must be set to the Key Vault secret ID for the intermediate CA PFX}"
: "${TLS_INSPECTION_IDENTITY_RESOURCE_ID:?TLS_INSPECTION_IDENTITY_RESOURCE_ID must be set to the pre-created user-assigned identity resource ID that can read the CA secret}"

DEPLOYMENT_NAME="aca-secret-kv-ref-mi-network-path-h4g"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$LAB_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"

START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TLS_INSPECTION_CA_CERTIFICATE_NAME="${TLS_INSPECTION_CA_CERTIFICATE_NAME:-lab-h4g-intermediate-ca}"

echo "trigger.sh started at $START_ISO"
echo "  RG                                   = $RG"
echo "  LOCATION                             = $LOCATION"
echo "  BASE_NAME                            = $BASE_NAME"
echo "  TLS_INSPECTION_CA_CERTIFICATE_NAME   = $TLS_INSPECTION_CA_CERTIFICATE_NAME"
echo "  TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID= $TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID"
echo "  TLS_INSPECTION_IDENTITY_RESOURCE_ID  = $TLS_INSPECTION_IDENTITY_RESOURCE_ID"
echo ""

echo "[1/8] Resolving signed-in user object ID..."
if [[ -z "${DEPLOYMENT_PRINCIPAL_ID:-}" ]]; then
    DEPLOYMENT_PRINCIPAL_ID="$(az ad signed-in-user show --query id --output tsv 2>/dev/null || true)"
    if [[ -z "$DEPLOYMENT_PRINCIPAL_ID" ]]; then
        echo "ERROR: DEPLOYMENT_PRINCIPAL_ID is not set and 'az ad signed-in-user show' returned empty."
        exit 1
    fi
fi
DEPLOYMENT_PRINCIPAL_TYPE="${DEPLOYMENT_PRINCIPAL_TYPE:-User}"

echo "[2/8] Creating resource group '$RG' in '$LOCATION' (idempotent)..."
az group create --name "$RG" --location "$LOCATION" --output none

echo "[3/8] Deploying Bicep template (Azure Firewall Premium makes this the expensive step)..."
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

echo "[4/8] Reading Bicep outputs and topology anchors..."
OUTPUTS_JSON="$(az deployment group show --resource-group "$RG" --name "$DEPLOYMENT_NAME" --query properties.outputs --output json)"

APP_NAME="$(echo "$OUTPUTS_JSON" | jq -r .appName.value)"
ENVIRONMENT_NAME="$(echo "$OUTPUTS_JSON" | jq -r .environmentName.value)"
KV_NAME="$(echo "$OUTPUTS_JSON" | jq -r .keyVaultName.value)"
KV_URI="$(echo "$OUTPUTS_JSON" | jq -r .keyVaultUri.value)"
APP_PRINCIPAL_ID="$(echo "$OUTPUTS_JSON" | jq -r .appPrincipalId.value)"
TENANT_ID="$(echo "$OUTPUTS_JSON" | jq -r .tenantId.value)"
VNET_NAME="$(echo "$OUTPUTS_JSON" | jq -r .vnetName.value)"
ACA_SUBNET_NAME="$(echo "$OUTPUTS_JSON" | jq -r .acaSubnetName.value)"
ACA_SUBNET_PREFIX="$(echo "$OUTPUTS_JSON" | jq -r .acaSubnetPrefix.value)"
LAW_NAME="$(echo "$OUTPUTS_JSON" | jq -r .logAnalyticsName.value)"
LAW_CUSTOMER_ID="$(echo "$OUTPUTS_JSON" | jq -r .logAnalyticsCustomerId.value)"
NSG_NAME="$(echo "$OUTPUTS_JSON" | jq -r .nsgName.value)"
ROUTE_TABLE_NAME="$(echo "$OUTPUTS_JSON" | jq -r .routeTableName.value)"
FIREWALL_NAME="$(echo "$OUTPUTS_JSON" | jq -r .azureFirewallName.value)"
FIREWALL_POLICY_NAME="$(echo "$OUTPUTS_JSON" | jq -r .firewallPolicyName.value)"
FIREWALL_RULE_COLLECTION_GROUP_NAME="$(echo "$OUTPUTS_JSON" | jq -r .firewallRuleCollectionGroupName.value)"
ENTRA_RULE_COLLECTION_NAME="$(echo "$OUTPUTS_JSON" | jq -r .entraAuthorityRuleCollectionName.value)"
ENTRA_RULE_NAME="$(echo "$OUTPUTS_JSON" | jq -r .entraAuthorityRuleName.value)"
FIREWALL_PRIVATE_IP="$(echo "$OUTPUTS_JSON" | jq -r .azureFirewallPrivateIp.value)"
TLS_INSPECTION_IDENTITY_RESOURCE_ID="$(echo "$OUTPUTS_JSON" | jq -r .tlsInspectionIdentityResourceId.value)"

VNET_JSON="$(az network vnet show --resource-group "$RG" --name "$VNET_NAME" --output json)"
SUBNET_JSON="$(az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET_NAME" --name "$ACA_SUBNET_NAME" --output json)"
ROUTE_JSON="$(az network route-table route show --resource-group "$RG" --route-table-name "$ROUTE_TABLE_NAME" --name default-via-afw-h4g --output json)"
RULE_COLLECTION_GROUP_JSON="$(az network firewall policy rule-collection-group show --resource-group "$RG" --policy-name "$FIREWALL_POLICY_NAME" --name "$FIREWALL_RULE_COLLECTION_GROUP_NAME" --output json)"
ENTRA_RULE_JSON="$(echo "$RULE_COLLECTION_GROUP_JSON" | jq --arg collection "$ENTRA_RULE_COLLECTION_NAME" --arg rule "$ENTRA_RULE_NAME" '.properties.ruleCollections[] | select(.name == $collection) | .rules[] | select(.name == $rule)')"

cat > "$EVIDENCE_DIR/01-deployment-outputs.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "trigger_started_at_utc": "$START_ISO",
  "lab_name": "aca-secret-kv-ref-mi-network-path-h4g",
  "resource_group": "$RG",
  "location": "$LOCATION",
  "base_name": "$BASE_NAME",
  "tenant_id": "$TENANT_ID",
  "app_name": "$APP_NAME",
  "environment_name": "$ENVIRONMENT_NAME",
  "key_vault_name": "$KV_NAME",
  "key_vault_uri": "$KV_URI",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "vnet_name": "$VNET_NAME",
  "aca_subnet_name": "$ACA_SUBNET_NAME",
  "aca_subnet_prefix": "$ACA_SUBNET_PREFIX",
  "log_analytics_name": "$LAW_NAME",
  "log_analytics_customer_id": "$LAW_CUSTOMER_ID",
  "deployer_principal_id": "$DEPLOYMENT_PRINCIPAL_ID",
  "deployer_principal_type": "$DEPLOYMENT_PRINCIPAL_TYPE",
  "nsg_name": "$NSG_NAME",
  "route_table_name": "$ROUTE_TABLE_NAME",
  "azure_firewall_name": "$FIREWALL_NAME",
  "firewall_policy_name": "$FIREWALL_POLICY_NAME",
  "firewall_rule_collection_group_name": "$FIREWALL_RULE_COLLECTION_GROUP_NAME",
  "entra_rule_collection_name": "$ENTRA_RULE_COLLECTION_NAME",
  "entra_rule_name": "$ENTRA_RULE_NAME",
  "firewall_private_ip": "$FIREWALL_PRIVATE_IP",
  "tls_inspection_ca_key_vault_secret_id": "$TLS_INSPECTION_CA_KEY_VAULT_SECRET_ID",
  "tls_inspection_ca_certificate_name": "$TLS_INSPECTION_CA_CERTIFICATE_NAME",
  "tls_inspection_identity_resource_id": "$TLS_INSPECTION_IDENTITY_RESOURCE_ID",
  "vnet_dns_servers": $(echo "$VNET_JSON" | jq '.dhcpOptions.dnsServers // []'),
  "aca_subnet_route_table_id": $(echo "$SUBNET_JSON" | jq '.routeTable.id // null'),
  "aca_subnet_nsg_id": $(echo "$SUBNET_JSON" | jq '.networkSecurityGroup.id // null'),
  "route_table_default_route": $ROUTE_JSON,
  "entra_rule_snapshot": $ENTRA_RULE_JSON,
  "azure_firewall_present": true,
  "azure_firewall_sku": "Premium",
  "firewall_policy_present": true,
  "firewall_policy_sku": "Premium",
  "tls_inspection_configured": true,
  "route_table_attached": true,
  "uses_azure_provided_dns": true,
  "nsg_attached": true,
  "nsg_deny_present": false,
  "dns_override_present": false,
  "vwan_routing_intent_present": false,
  "entra_authority_terminate_tls": false
}
EOF
echo "  wrote evidence/01-deployment-outputs.json"

echo "[5/8] Waiting for KV RBAC propagation (deployer -> Secrets Officer)..."
KV_READY="no"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if az keyvault secret list --vault-name "$KV_NAME" --output none 2>/dev/null; then
        KV_READY="yes"
        break
    fi
    sleep 30
done
if [[ "$KV_READY" != "yes" ]]; then
    echo "ERROR: KV data-plane never became reachable via signed-in user identity after 5 minutes."
    exit 1
fi

echo "[6/8] Waiting for app latest revision to reach Healthy state..."
LATEST_REV_BEFORE=""
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    LATEST_REV_BEFORE="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query properties.latestReadyRevisionName --output tsv 2>/dev/null || true)"
    if [[ -n "$LATEST_REV_BEFORE" && "$LATEST_REV_BEFORE" != "null" ]]; then
        HEALTH_STATE="$(az containerapp revision show --name "$APP_NAME" --resource-group "$RG" --revision "$LATEST_REV_BEFORE" --query properties.healthState --output tsv 2>/dev/null || echo "unknown")"
        if [[ "$HEALTH_STATE" == "Healthy" ]]; then
            break
        fi
        echo "  attempt $attempt: revision '$LATEST_REV_BEFORE' health=$HEALTH_STATE, retrying in 20s..."
    else
        echo "  attempt $attempt: latestReadyRevisionName not yet populated, retrying in 20s..."
    fi
    sleep 20
done
if [[ -z "$LATEST_REV_BEFORE" || "$LATEST_REV_BEFORE" == "null" ]]; then
    echo "ERROR: Container App revision never became Ready."
    exit 1
fi

TMP_01="$(mktemp)"
jq --arg baseline_revision_name "$LATEST_REV_BEFORE" '. + {baseline_revision_name: $baseline_revision_name}' "$EVIDENCE_DIR/01-deployment-outputs.json" > "$TMP_01"
mv "$TMP_01" "$EVIDENCE_DIR/01-deployment-outputs.json"

APP_STATE_BEFORE="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --output json)"
APP_FQDN="$(echo "$APP_STATE_BEFORE" | jq -r .properties.configuration.ingress.fqdn)"
INGRESS_CHECK_BEFORE_HTTP="000"
if [[ -n "$APP_FQDN" && "$APP_FQDN" != "null" ]]; then
    for _ in 1 2 3; do
        : "$_"
        INGRESS_CHECK_BEFORE_HTTP="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "https://$APP_FQDN/" 2>/dev/null || echo "000")"
        if [[ "$INGRESS_CHECK_BEFORE_HTTP" == "200" ]]; then
            break
        fi
        sleep 10
    done
fi

cat > "$EVIDENCE_DIR/02-h0-app-state-before.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H0-before",
  "resource_group": "$RG",
  "app_name": "$APP_NAME",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BEFORE",
  "latest_ready_revision_name": "$LATEST_REV_BEFORE",
  "ingress_fqdn": "$APP_FQDN",
  "ingress_probe_http_code": "$INGRESS_CHECK_BEFORE_HTTP",
  "secrets_before": $(echo "$APP_STATE_BEFORE" | jq '.properties.configuration.secrets // []')
}
EOF
echo "  wrote evidence/02-h0-app-state-before.json"

SECRET_NAME_H0="kvref-h0-value"
SECRET_VALUE_H0="baseline-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[7/8] Creating KV secret '$SECRET_NAME_H0' in vault '$KV_NAME'..."
KV_CREATE_JSON="$(az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H0" --value "$SECRET_VALUE_H0" --output json)"
SECRET_ID_H0="$(echo "$KV_CREATE_JSON" | jq -r .id)"
KV_SECRET_URL_H0="${KV_URI}secrets/${SECRET_NAME_H0}"

cat > "$EVIDENCE_DIR/03-h0-kv-secret-created.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H0",
  "resource_group": "$RG",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_name": "$APP_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BEFORE",
  "secret_name": "$SECRET_NAME_H0",
  "secret_id_versioned": "$SECRET_ID_H0",
  "secret_url_versionless": "$KV_SECRET_URL_H0"
}
EOF
echo "  wrote evidence/03-h0-kv-secret-created.json"

echo "[8/8] H0: Attempting baseline 'az containerapp secret set --secrets ...identityref:system' (MUST succeed)..."
BASELINE_SECRET_REF_NAME="kvref-h0"
SET_STDOUT_FILE="$(mktemp)"
SET_STDERR_FILE="$(mktemp)"
SET_EXIT=0
az containerapp secret set \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --secrets "${BASELINE_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H0},identityref:system" \
    --output json >"$SET_STDOUT_FILE" 2>"$SET_STDERR_FILE" || SET_EXIT=$?
SET_STDOUT="$(cat "$SET_STDOUT_FILE")"
SET_STDERR="$(cat "$SET_STDERR_FILE")"
rm -f "$SET_STDOUT_FILE" "$SET_STDERR_FILE"

cat > "$EVIDENCE_DIR/04-h0-secret-set-outcome.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H0",
  "app_name": "$APP_NAME",
  "resource_group": "$RG",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BEFORE",
  "hypothesis": "Baseline: Azure Firewall Premium present, TLS inspection configured, but Entra-authority rule terminateTLS=false -> az containerapp secret set SUCCEEDS",
  "command": "az containerapp secret set --name $APP_NAME --resource-group $RG --secrets ${BASELINE_SECRET_REF_NAME}=keyvaultref:${KV_SECRET_URL_H0},identityref:system",
  "exit_code": $SET_EXIT,
  "expected_exit_code": 0,
  "outcome": $([ $SET_EXIT -eq 0 ] && echo '"success"' || echo '"failure"'),
  "stdout": $(printf '%s' "$SET_STDOUT" | jq -Rs .),
  "stderr": $(printf '%s' "$SET_STDERR" | jq -Rs .)
}
EOF
echo "  wrote evidence/04-h0-secret-set-outcome.json"
if [[ $SET_EXIT -ne 0 ]]; then
    echo "ERROR: H0 baseline FAILED. Exit=$SET_EXIT"
    exit 1
fi

APP_STATE_AFTER="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --output json)"
LATEST_REV_AFTER="$(echo "$APP_STATE_AFTER" | jq -r .properties.latestReadyRevisionName)"
INGRESS_CHECK_AFTER_HTTP="000"
if [[ -n "$APP_FQDN" && "$APP_FQDN" != "null" ]]; then
    for _ in 1 2 3; do
        : "$_"
        INGRESS_CHECK_AFTER_HTTP="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "https://$APP_FQDN/" 2>/dev/null || echo "000")"
        if [[ "$INGRESS_CHECK_AFTER_HTTP" == "200" ]]; then
            break
        fi
        sleep 5
    done
fi
SECRETS_AFTER_JSON="$(echo "$APP_STATE_AFTER" | jq '.properties.configuration.secrets // []')"
BASELINE_SECRET_PRESENT="$(echo "$SECRETS_AFTER_JSON" | jq -r --arg n "$BASELINE_SECRET_REF_NAME" 'map(select(.name == $n)) | length')"
if [[ "$LATEST_REV_BEFORE" == "$LATEST_REV_AFTER" ]]; then
    REV_UNCHANGED="true"
else
    REV_UNCHANGED="false"
fi

cat > "$EVIDENCE_DIR/05-h0-app-state-after.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H0-after",
  "resource_group": "$RG",
  "app_name": "$APP_NAME",
  "environment_name": "$ENVIRONMENT_NAME",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "key_vault_name": "$KV_NAME",
  "tenant_id": "$TENANT_ID",
  "baseline_revision_name": "$LATEST_REV_BEFORE",
  "latest_ready_revision_name": "$LATEST_REV_AFTER",
  "latest_revision_unchanged_vs_before": $REV_UNCHANGED,
  "ingress_probe_http_code": "$INGRESS_CHECK_AFTER_HTTP",
  "baseline_secret_ref_name": "$BASELINE_SECRET_REF_NAME",
  "baseline_secret_present_in_config_count": ${BASELINE_SECRET_PRESENT:-0},
  "secrets_after": $SECRETS_AFTER_JSON
}
EOF
echo "  wrote evidence/05-h0-app-state-after.json"

echo ""
echo "=== trigger.sh complete ==="
echo "Evidence directory: $EVIDENCE_DIR"
echo "  01-deployment-outputs.json"
echo "  02-h0-app-state-before.json"
echo "  03-h0-kv-secret-created.json"
echo "  04-h0-secret-set-outcome.json     [H0 outcome=success, exit=$SET_EXIT]"
echo "  05-h0-app-state-after.json        [secret present=${BASELINE_SECRET_PRESENT:-0}, revision_unchanged=$REV_UNCHANGED]"
echo ""
echo "Next: bash falsify.sh"
