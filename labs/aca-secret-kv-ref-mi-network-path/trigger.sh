#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# trigger.sh — Deploys the lab infrastructure and establishes H0 baseline.
# -----------------------------------------------------------------------------
#
# H0 baseline hypothesis:
#     WHEN the Firewall Application Rule for the Entra authority is present
#     THEN `az containerapp secret set --identity system --key-vault-url ...`
#          SUCCEEDS.
#
# This script deploys the infrastructure, waits for RBAC propagation on the
# Key Vault, verifies the app is healthy, creates a Key Vault secret using
# the deployer's identity, and executes a baseline `az containerapp secret set`
# that MUST succeed. If baseline succeeds, the lab is in a known-good state
# and falsify.sh can proceed to H1.
#
# Evidence files emitted (numbered for cohort integrity):
#     01-deployment-outputs.json         — Bicep deployment outputs
#     02-h0-app-state-before.json        — app state pre-baseline
#     03-h0-kv-secret-created.json       — KV secret create receipt
#     04-h0-secret-set-outcome.json      — baseline `az containerapp secret set` outcome
#     05-h0-app-state-after.json         — app state post-baseline (revision unchanged, secret present)
#
# Required environment variables:
#     RG            resource group name
#     LOCATION      Azure region (e.g. koreacentral, eastus)
#     BASE_NAME     3-11 chars, lowercase alphanumeric, for resource naming
#
# Required tools: az (Azure CLI), jq, curl
# Required permissions: Owner or User Access Administrator at the RG scope
#     (needed so the Bicep deployment can create role assignments at the
#     Key Vault scope).
# -----------------------------------------------------------------------------

set -euo pipefail

: "${RG:?RG must be set (e.g. rg-aca-kv-mi-netpath)}"
: "${LOCATION:?LOCATION must be set (e.g. koreacentral)}"
: "${BASE_NAME:?BASE_NAME must be set (3-11 chars, lowercase alphanumeric, e.g. kvminp01)}"

DEPLOYMENT_NAME="aca-secret-kv-ref-mi-network-path"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$LAB_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"

START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "trigger.sh started at $START_ISO"
echo "  RG        = $RG"
echo "  LOCATION  = $LOCATION"
echo "  BASE_NAME = $BASE_NAME"
echo ""

# -----------------------------------------------------------------------------
# Step 1 — Signed-in user object ID (needed by Bicep RBAC assignments)
# -----------------------------------------------------------------------------
echo "[1/9] Resolving signed-in user object ID..."
# Honor externally supplied DEPLOYMENT_PRINCIPAL_ID (e.g. from a service principal
# or CI environment). Only fall back to `az ad signed-in-user show` if the caller
# has not already resolved the principal ID out-of-band.
if [[ -z "${DEPLOYMENT_PRINCIPAL_ID:-}" ]]; then
    DEPLOYMENT_PRINCIPAL_ID="$(az ad signed-in-user show --query id --output tsv 2>/dev/null || true)"
    if [[ -z "$DEPLOYMENT_PRINCIPAL_ID" ]]; then
        echo "ERROR: DEPLOYMENT_PRINCIPAL_ID is not set and 'az ad signed-in-user show' returned empty."
        echo "Are you logged in with 'az login' as a user (not a service principal)?"
        echo "For service principals or CI, set DEPLOYMENT_PRINCIPAL_ID / DEPLOYMENT_PRINCIPAL_TYPE explicitly and re-run."
        exit 1
    fi
fi
DEPLOYMENT_PRINCIPAL_TYPE="${DEPLOYMENT_PRINCIPAL_TYPE:-User}"
echo "  principal_id   = $DEPLOYMENT_PRINCIPAL_ID"
echo "  principal_type = $DEPLOYMENT_PRINCIPAL_TYPE"

# -----------------------------------------------------------------------------
# Step 2 — Resource group (idempotent)
# -----------------------------------------------------------------------------
echo "[2/9] Creating resource group '$RG' in '$LOCATION' (idempotent)..."
az group create --name "$RG" --location "$LOCATION" --output none

# -----------------------------------------------------------------------------
# Step 3 — Bicep deployment
# -----------------------------------------------------------------------------
echo "[3/9] Deploying Bicep template (this typically takes 8-12 minutes for Firewall Basic)..."
az deployment group create \
    --resource-group "$RG" \
    --name "$DEPLOYMENT_NAME" \
    --template-file "$LAB_DIR/infra/main.bicep" \
    --parameters baseName="$BASE_NAME" \
                 deploymentPrincipalId="$DEPLOYMENT_PRINCIPAL_ID" \
                 deploymentPrincipalType="$DEPLOYMENT_PRINCIPAL_TYPE" \
    --output none

# -----------------------------------------------------------------------------
# Step 4 — Read Bicep outputs
# -----------------------------------------------------------------------------
echo "[4/9] Reading Bicep outputs..."
OUTPUTS_JSON="$(az deployment group show --resource-group "$RG" --name "$DEPLOYMENT_NAME" --query properties.outputs --output json)"

APP_NAME="$(echo "$OUTPUTS_JSON" | jq -r .appName.value)"
ENVIRONMENT_NAME="$(echo "$OUTPUTS_JSON" | jq -r .environmentName.value)"
KV_NAME="$(echo "$OUTPUTS_JSON" | jq -r .keyVaultName.value)"
KV_URI="$(echo "$OUTPUTS_JSON" | jq -r .keyVaultUri.value)"
APP_PRINCIPAL_ID="$(echo "$OUTPUTS_JSON" | jq -r .appPrincipalId.value)"
FIREWALL_NAME="$(echo "$OUTPUTS_JSON" | jq -r .firewallName.value)"
FIREWALL_POLICY_NAME="$(echo "$OUTPUTS_JSON" | jq -r .firewallPolicyName.value)"
FIREWALL_PUBLIC_IP="$(echo "$OUTPUTS_JSON" | jq -r .firewallPublicIpAddress.value)"
LAW_NAME="$(echo "$OUTPUTS_JSON" | jq -r .logAnalyticsName.value)"
LAW_CUSTOMER_ID="$(echo "$OUTPUTS_JSON" | jq -r .logAnalyticsCustomerId.value)"
ENTRA_RULE_COLLECTION_NAME="$(echo "$OUTPUTS_JSON" | jq -r .entraAuthorityRuleCollectionName.value)"
ENTRA_RULE_NAME="$(echo "$OUTPUTS_JSON" | jq -r .entraAuthorityRuleName.value)"

cat > "$EVIDENCE_DIR/01-deployment-outputs.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "trigger_started_at_utc": "$START_ISO",
  "lab_name": "aca-secret-kv-ref-mi-network-path",
  "resource_group": "$RG",
  "location": "$LOCATION",
  "base_name": "$BASE_NAME",
  "app_name": "$APP_NAME",
  "environment_name": "$ENVIRONMENT_NAME",
  "key_vault_name": "$KV_NAME",
  "key_vault_uri": "$KV_URI",
  "app_principal_id": "$APP_PRINCIPAL_ID",
  "firewall_name": "$FIREWALL_NAME",
  "firewall_policy_name": "$FIREWALL_POLICY_NAME",
  "firewall_public_ip": "$FIREWALL_PUBLIC_IP",
  "log_analytics_name": "$LAW_NAME",
  "log_analytics_customer_id": "$LAW_CUSTOMER_ID",
  "deployer_principal_id": "$DEPLOYMENT_PRINCIPAL_ID",
  "deployer_principal_type": "$DEPLOYMENT_PRINCIPAL_TYPE",
  "entra_rule_collection_name": "$ENTRA_RULE_COLLECTION_NAME",
  "entra_rule_name": "$ENTRA_RULE_NAME"
}
EOF
echo "  wrote evidence/01-deployment-outputs.json"

# -----------------------------------------------------------------------------
# Step 5 — Wait for Key Vault RBAC propagation
# -----------------------------------------------------------------------------
# Bicep just granted the deployer 'Key Vault Secrets Officer' at KV scope.
# RBAC on Key Vault typically propagates within 30-120 seconds, but can
# take up to 5 minutes on the first assignment.
echo "[5/9] Waiting for KV RBAC propagation (deployer -> Secrets Officer)..."
KV_READY="no"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if az keyvault secret list --vault-name "$KV_NAME" --output none 2>/dev/null; then
        KV_READY="yes"
        echo "  KV data-plane reachable after ${attempt} attempt(s)."
        break
    fi
    echo "  attempt $attempt: KV data-plane not yet reachable, retrying in 30s..."
    sleep 30
done
if [[ "$KV_READY" != "yes" ]]; then
    echo "ERROR: KV data-plane never became reachable via signed-in user identity after 5 minutes."
    echo "  Check: 'az role assignment list --scope $(az keyvault show --name $KV_NAME --resource-group $RG --query id --output tsv) --assignee $DEPLOYMENT_PRINCIPAL_ID'"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 6 — Wait for Container App revision to be Healthy
# -----------------------------------------------------------------------------
echo "[6/9] Waiting for app latest revision to reach Healthy state..."
LATEST_REV_BEFORE=""
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    LATEST_REV_BEFORE="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query properties.latestReadyRevisionName --output tsv 2>/dev/null || true)"
    if [[ -n "$LATEST_REV_BEFORE" && "$LATEST_REV_BEFORE" != "null" ]]; then
        HEALTH_STATE="$(az containerapp revision show --name "$APP_NAME" --resource-group "$RG" --revision "$LATEST_REV_BEFORE" --query properties.healthState --output tsv 2>/dev/null || echo "unknown")"
        if [[ "$HEALTH_STATE" == "Healthy" ]]; then
            echo "  Revision '$LATEST_REV_BEFORE' is Healthy after ${attempt} attempt(s)."
            break
        fi
        echo "  attempt $attempt: revision '$LATEST_REV_BEFORE' health=$HEALTH_STATE, retrying in 20s..."
    else
        echo "  attempt $attempt: latestReadyRevisionName not yet populated, retrying in 20s..."
    fi
    sleep 20
done

if [[ -z "$LATEST_REV_BEFORE" || "$LATEST_REV_BEFORE" == "null" ]]; then
    echo "ERROR: Container App revision never became Ready. Check firewall Application Rules and image pull."
    exit 1
fi

APP_STATE_BEFORE="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --output json)"
APP_FQDN="$(echo "$APP_STATE_BEFORE" | jq -r .properties.configuration.ingress.fqdn)"

INGRESS_CHECK_BEFORE_HTTP="000"
if [[ -n "$APP_FQDN" && "$APP_FQDN" != "null" ]]; then
    for attempt in 1 2 3; do
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
  "app_name": "$APP_NAME",
  "latest_ready_revision_name": "$LATEST_REV_BEFORE",
  "ingress_fqdn": "$APP_FQDN",
  "ingress_probe_http_code": "$INGRESS_CHECK_BEFORE_HTTP",
  "secrets_before": $(echo "$APP_STATE_BEFORE" | jq '.properties.configuration.secrets // []')
}
EOF
echo "  wrote evidence/02-h0-app-state-before.json"
echo "  latest_ready_revision   = $LATEST_REV_BEFORE"
echo "  ingress_fqdn            = $APP_FQDN"
echo "  ingress_probe_http_code = $INGRESS_CHECK_BEFORE_HTTP"

# -----------------------------------------------------------------------------
# Step 7 — Create Key Vault secret (using deployer's Secrets Officer role)
# -----------------------------------------------------------------------------
SECRET_NAME_H0="kvref-h0-value"
SECRET_VALUE_H0="baseline-value-$(date -u +%Y%m%dT%H%M%SZ)"

echo "[7/9] Creating KV secret '$SECRET_NAME_H0' in vault '$KV_NAME'..."
KV_CREATE_JSON="$(az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H0" --value "$SECRET_VALUE_H0" --output json)"
SECRET_ID_H0="$(echo "$KV_CREATE_JSON" | jq -r .id)"

# Versionless URI so the ACA secret reference always resolves the latest version.
KV_SECRET_URL_H0="${KV_URI}secrets/${SECRET_NAME_H0}"

cat > "$EVIDENCE_DIR/03-h0-kv-secret-created.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H0",
  "key_vault_name": "$KV_NAME",
  "secret_name": "$SECRET_NAME_H0",
  "secret_id_versioned": "$SECRET_ID_H0",
  "secret_url_versionless": "$KV_SECRET_URL_H0"
}
EOF
echo "  wrote evidence/03-h0-kv-secret-created.json"

# -----------------------------------------------------------------------------
# Step 8 — Baseline `az containerapp secret set` (H0 — MUST succeed)
# -----------------------------------------------------------------------------
BASELINE_SECRET_REF_NAME="kvref-h0"

echo "[8/9] H0: Attempting baseline 'az containerapp secret set --identity system' (MUST succeed)..."
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
  "hypothesis": "Baseline: Entra Application Rule PRESENT -> `az containerapp secret set` SUCCEEDS",
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
    echo "  stderr: $SET_STDERR"
    echo ""
    echo "Diagnosis checklist:"
    echo "  - Firewall Application Rule 'allow-entra-login' present? (should be)"
    echo "  - KV role assignment for app MI propagated? (may need up to 5 min)"
    echo "  - App revision Healthy?"
    exit 1
fi
echo "  H0 SUCCEEDED. Baseline is valid."

# -----------------------------------------------------------------------------
# Step 9 — Capture app state after baseline
# -----------------------------------------------------------------------------
echo "[9/9] Capturing app state after baseline..."
APP_STATE_AFTER="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --output json)"
LATEST_REV_AFTER="$(echo "$APP_STATE_AFTER" | jq -r .properties.latestReadyRevisionName)"

INGRESS_CHECK_AFTER_HTTP="000"
if [[ -n "$APP_FQDN" && "$APP_FQDN" != "null" ]]; then
    for attempt in 1 2 3; do
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
  "app_name": "$APP_NAME",
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
echo "  05-h0-app-state-after.json         [secret present=${BASELINE_SECRET_PRESENT:-0}, revision_unchanged=$REV_UNCHANGED]"
echo ""
echo "Next: bash falsify.sh"
