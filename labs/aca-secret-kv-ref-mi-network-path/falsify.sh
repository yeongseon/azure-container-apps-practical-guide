#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# falsify.sh — H1 trigger (fails) + H2 fix (recovers) with silence-gate proofs.
# -----------------------------------------------------------------------------
#
# Preconditions:
#   trigger.sh has completed successfully and produced:
#     evidence/01-deployment-outputs.json  (Bicep outputs)
#     evidence/04-h0-secret-set-outcome.json (baseline SUCCEEDED, exit_code=0)
#     evidence/05-h0-app-state-after.json  (baseline secret 'kvref-h0' present)
#
# H1 hypothesis (falsification target):
#     WHEN the Firewall Application Rule for the Entra authority is REMOVED
#          (so egress from snet-aca to login.microsoftonline.com is denied)
#     THEN `az containerapp secret set --identity system --key-vault-url ...`
#          FAILS because ACA control plane cannot complete OIDC discovery.
#
# H2 hypothesis (recovery):
#     WHEN the Firewall Application Rule for the Entra authority is RESTORED
#     THEN `az containerapp secret set --identity system --key-vault-url ...`
#          SUCCEEDS again.
#
# Silence-gate design (critical — secret updates do NOT create new revisions):
#     During H1, the failing `secret set` MUST NOT be inferred from revision
#     events or ContainerAppSystemLogs. The empirical silence-gate proof is:
#       (a) latestReadyRevisionName UNCHANGED vs baseline evidence 05
#       (b) ingress HTTP probe still returns 200 (existing revision unaffected)
#       (c) the H1 secret name is NOT present in configuration.secrets
#     Only ALL THREE together prove the failure was scoped to the control-plane
#     KV secret-reference resolution and did not touch the running workload.
#
# Smoking-gun evidence:
#     H1 = at least 1 row in AZFWApplicationRule with
#              Fqdn has "login.microsoftonline.com" AND Action == "Deny"
#          within the H1 window (SINCE H1 start timestamp).
#     H2 = at least 1 row with Action == "Allow" for the same Fqdn
#          within the H2 window.
#
# Evidence files emitted (numbered for cohort integrity):
#     06-h1-firewall-rule-removed.json     — Entra rule remove receipt
#     07-h1-secret-set-outcome.json        — H1 failing `secret set` outcome
#     08-h1-app-state.json                 — silence-gate proof (a)+(b)+(c)
#     09-h1-firewall-deny-log.json         — AZFWApplicationRule Deny row(s)
#     10-h2-firewall-rule-restored.json    — Entra rule restore receipt
#     11-h2-secret-set-outcome.json        — H2 successful `secret set` outcome
#     12-h2-app-state.json                 — post-restore app state
#     13-h2-firewall-allow-log.json        — AZFWApplicationRule Allow row(s)
#
# Required environment variables:
#     RG        resource group (same one used by trigger.sh)
#
# Required tools: az (Azure CLI), jq, curl, python3
# Required permissions: 'Network Contributor' at the firewall-policy scope
#     (to remove/re-add rule collections) AND 'Key Vault Secrets Officer'
#     at KV scope (to write kvref-h1/kvref-h2 KV secret values).
# -----------------------------------------------------------------------------

set -euo pipefail

: "${RG:?RG must be set (same value used by trigger.sh)}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$LAB_DIR/evidence"

# -----------------------------------------------------------------------------
# Preflight: read trigger.sh outputs from evidence/01
# -----------------------------------------------------------------------------
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
    echo "  falsify.sh requires a valid baseline. Fix trigger.sh outcome before proceeding."
    exit 1
fi

APP_NAME="$(jq -r .app_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
ENVIRONMENT_NAME="$(jq -r .environment_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_NAME="$(jq -r .key_vault_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
KV_URI="$(jq -r .key_vault_uri "$EVIDENCE_DIR/01-deployment-outputs.json")"
FIREWALL_POLICY_NAME="$(jq -r .firewall_policy_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
LAW_CUSTOMER_ID="$(jq -r .log_analytics_customer_id "$EVIDENCE_DIR/01-deployment-outputs.json")"
ENTRA_RULE_COLLECTION_NAME="$(jq -r .entra_rule_collection_name "$EVIDENCE_DIR/01-deployment-outputs.json")"
ENTRA_RULE_NAME="$(jq -r .entra_rule_name "$EVIDENCE_DIR/01-deployment-outputs.json")"

# Bicep hard-codes the rule collection group name; falsify.sh addresses the
# collection inside it by name. The group name is deliberately not made a
# Bicep output because it is a lab-internal implementation detail — the
# operator-facing controlled variable is the RULE COLLECTION name.
RULE_COLLECTION_GROUP_NAME="aca-kv-entra-application"
# Priority and source addresses must match main.bicep so the restore in H2
# produces an equivalent rule collection to what H0 baseline used.
ENTRA_COLLECTION_PRIORITY=220
ACA_SUBNET_PREFIX="$(jq -r .base_name "$EVIDENCE_DIR/01-deployment-outputs.json" >/dev/null; az deployment group show --resource-group "$RG" --name aca-secret-kv-ref-mi-network-path --query properties.outputs.acaSubnetPrefix.value --output tsv 2>/dev/null || echo "10.90.0.0/23")"
ENTRA_FQDN_PRIMARY="login.microsoftonline.com"
ENTRA_FQDN_SECONDARY="login.microsoft.com"

# Baseline revision name from H0 evidence — silence gate compares against this.
LATEST_REV_BASELINE="$(jq -r .latest_ready_revision_name "$EVIDENCE_DIR/05-h0-app-state-after.json")"
APP_FQDN="$(jq -r .ingress_fqdn "$EVIDENCE_DIR/02-h0-app-state-before.json")"

START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "falsify.sh started at $START_ISO"
echo "  RG                              = $RG"
echo "  APP_NAME                        = $APP_NAME"
echo "  KV_NAME                         = $KV_NAME"
echo "  FIREWALL_POLICY_NAME            = $FIREWALL_POLICY_NAME"
echo "  ENTRA_RULE_COLLECTION_NAME      = $ENTRA_RULE_COLLECTION_NAME   <-- controlled variable"
echo "  LATEST_REV_BASELINE (from H0)   = $LATEST_REV_BASELINE"
echo "  APP_FQDN                        = $APP_FQDN"
echo "  LAW_CUSTOMER_ID                 = $LAW_CUSTOMER_ID"
echo ""

# -----------------------------------------------------------------------------
# Helper: query firewall for AZFWApplicationRule rows since a UTC timestamp
# -----------------------------------------------------------------------------
# Prints row count to stdout. Echoes preview rows (if any) to stderr.
# Schema tolerance: queries BOTH the modern resource-specific
# `AZFWApplicationRule` table (populated when the firewall diagnostic setting
# uses `logAnalyticsDestinationType: 'Dedicated'` — this lab's main.bicep does)
# AND the legacy `AzureDiagnostics` rows with
# `Category == 'AzureFirewallApplicationRule'`. Log ingestion latency for
# Azure Firewall Basic is typically 2-6 minutes, so callers must retry.
# Args: $1 = since timestamp (ISO 8601 UTC), $2 = Action filter (Deny or Allow)
count_azfw_entra_rows_since() {
    local since_iso="$1"
    local action_filter="$2"
    local kql
    kql="union isfuzzy=true
    (AZFWApplicationRule
        | where TimeGenerated >= datetime('${since_iso}')
        | where Fqdn has '${ENTRA_FQDN_PRIMARY}' or Fqdn has '${ENTRA_FQDN_SECONDARY}'
        | where Action == '${action_filter}'
        | project TimeGenerated, Fqdn, SourceIp, Action, Policy, RuleCollectionGroup, RuleCollection, Rule, Source='AZFWApplicationRule'),
    (AzureDiagnostics
        | where TimeGenerated >= datetime('${since_iso}')
        | where Category == 'AzureFirewallApplicationRule'
        | where msg_s contains '${ENTRA_FQDN_PRIMARY}' or msg_s contains '${ENTRA_FQDN_SECONDARY}'
        | where msg_s contains '${action_filter}'
        | project TimeGenerated, Fqdn=extract(@'to (\\S+):443', 1, msg_s), SourceIp=extract(@'from (\\d+\\.\\d+\\.\\d+\\.\\d+)', 1, msg_s), Action='${action_filter}', Policy='', RuleCollectionGroup='', RuleCollection='', Rule='', Source='AzureDiagnostics')
| order by TimeGenerated desc
| take 20"
    local rows
    rows="$(az monitor log-analytics query \
        --workspace "$LAW_CUSTOMER_ID" \
        --analytics-query "$kql" \
        --output tsv 2>/dev/null || true)"
    if [[ -n "$rows" ]]; then
        echo "$rows" | head -5 >&2
        # Row count = line count (each row is one line in tsv output).
        echo "$rows" | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# -----------------------------------------------------------------------------
# Helper: capture app state snapshot as JSON with silence-gate fields
# -----------------------------------------------------------------------------
# Args: $1 = expected_secret_name (whether it should be present or absent),
#       $2 = expected_secret_present (true or false)
# Writes stdout in JSON format matching evidence file schema.
capture_app_state_snapshot() {
    local expected_secret_name="$1"
    local expected_secret_present="$2"
    local app_json
    app_json="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --output json)"
    local latest_rev
    latest_rev="$(echo "$app_json" | jq -r .properties.latestReadyRevisionName)"
    local rev_unchanged
    if [[ "$latest_rev" == "$LATEST_REV_BASELINE" ]]; then
        rev_unchanged="true"
    else
        rev_unchanged="false"
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
    local secret_present_bool
    if [[ "${secret_present_count:-0}" -gt 0 ]]; then
        secret_present_bool="true"
    else
        secret_present_bool="false"
    fi
    local expectation_met
    if [[ "$secret_present_bool" == "$expected_secret_present" ]]; then
        expectation_met="true"
    else
        expectation_met="false"
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

# =============================================================================
# H1 PHASE — trigger the failure by removing the Entra Application Rule
# =============================================================================

# -----------------------------------------------------------------------------
# Step 1 — H1 start timestamp (bounds firewall Deny query window)
# -----------------------------------------------------------------------------
H1_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[H1] step 1: H1 start timestamp = $H1_START_ISO"

# -----------------------------------------------------------------------------
# Step 2 — Remove the Entra Application Rule collection
# -----------------------------------------------------------------------------
echo "[H1] step 2: REMOVING rule collection '$ENTRA_RULE_COLLECTION_NAME' from group '$RULE_COLLECTION_GROUP_NAME' in policy '$FIREWALL_POLICY_NAME'"
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
    echo "ERROR: rule-collection-group collection remove failed (exit=$REMOVE_EXIT)."
    echo "  stderr: $REMOVE_STDERR"
    exit 1
fi

# Verify the collection is no longer in the group.
POST_REMOVE_GROUP_JSON="$(az network firewall policy rule-collection-group show \
    --resource-group "$RG" \
    --policy-name "$FIREWALL_POLICY_NAME" \
    --name "$RULE_COLLECTION_GROUP_NAME" \
    --output json)"
POST_REMOVE_COLLECTION_NAMES="$(echo "$POST_REMOVE_GROUP_JSON" | jq -r '.ruleCollections[].name')"
if echo "$POST_REMOVE_COLLECTION_NAMES" | grep -q "^${ENTRA_RULE_COLLECTION_NAME}$"; then
    echo "ERROR: rule collection '$ENTRA_RULE_COLLECTION_NAME' still present after remove call."
    echo "  Current collections in group: $POST_REMOVE_COLLECTION_NAMES"
    exit 1
fi
echo "  removed OK. Remaining collections in group: $(echo "$POST_REMOVE_COLLECTION_NAMES" | tr '\n' ' ')"

cat > "$EVIDENCE_DIR/06-h1-firewall-rule-removed.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "action": "remove-rule-collection",
  "firewall_policy_name": "$FIREWALL_POLICY_NAME",
  "rule_collection_group_name": "$RULE_COLLECTION_GROUP_NAME",
  "rule_collection_name": "$ENTRA_RULE_COLLECTION_NAME",
  "remove_exit_code": $REMOVE_EXIT,
  "post_remove_collections_in_group": $(echo "$POST_REMOVE_COLLECTION_NAMES" | jq -R -s -c 'split("\n") | map(select(length > 0))'),
  "controlled_variable_absent_after_remove": true
}
EOF
echo "  wrote evidence/06-h1-firewall-rule-removed.json"

# -----------------------------------------------------------------------------
# Step 3 — Wait for firewall policy convergence
# -----------------------------------------------------------------------------
# Azure Firewall Basic reflects policy changes within seconds to about a minute.
# Using 60s to be safe — a short wait keeps the H1 timestamp window narrow so
# the KQL query stays focused on the H1 failure attempt, not on pre-remove
# traffic that would produce Allow rows and pollute the window.
echo "[H1] step 3: waiting 60s for firewall policy convergence"
sleep 60

# -----------------------------------------------------------------------------
# Step 4 — Create fresh KV secret for H1 attempt
# -----------------------------------------------------------------------------
# Using a distinct secret name per hypothesis (kvref-h0 / kvref-h1 / kvref-h2)
# ensures the presence/absence check in the silence gate is unambiguous:
# after H1, kvref-h1 must be ABSENT from configuration.secrets; after H2,
# kvref-h2 must be PRESENT. A shared name across phases would create
# ambiguity (was 'kvref' set by H0 or by H2?).
SECRET_NAME_H1="kvref-h1-value"
SECRET_VALUE_H1="h1-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H1] step 4: creating KV secret '$SECRET_NAME_H1' in vault '$KV_NAME'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H1" --value "$SECRET_VALUE_H1" --output none
KV_SECRET_URL_H1="${KV_URI}secrets/${SECRET_NAME_H1}"

# -----------------------------------------------------------------------------
# Step 5 — H1: attempt `az containerapp secret set` (MUST FAIL)
# -----------------------------------------------------------------------------
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
SET_STDOUT="$(cat "$SET_STDOUT_FILE")"
SET_STDERR="$(cat "$SET_STDERR_FILE")"
rm -f "$SET_STDOUT_FILE" "$SET_STDERR_FILE"

# Search stderr for the customer-facing failure signatures. Any of these
# substrings appearing is corroborating evidence of the OIDC-discovery
# failure mode; they are NOT hard gates because Azure CLI wrapping formats
# vary across CLI versions. The hard gates below are (a) exit != 0 and
# (b) the H1 secret name being ABSENT from configuration.secrets.
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
  "hypothesis": "H1: Entra Application Rule REMOVED -> \`az containerapp secret set\` FAILS at OIDC discovery",
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
    echo "FAIL (H1): 'az containerapp secret set' UNEXPECTEDLY SUCCEEDED with the Entra"
    echo "  Application Rule removed. Hypothesis H1 is FALSIFIED — one of:"
    echo "    (a) the Application Rule remove call did not actually converge in the"
    echo "        firewall data plane within the 60s wait,"
    echo "    (b) a broader allow rule (network rule with AzureActiveDirectory tag or"
    echo "        Application Rule with a *.microsoft.com wildcard) is silently"
    echo "        letting Entra traffic through — check main.bicep against the"
    echo "        anti-patterns comment,"
    echo "    (c) ACA control plane cached a token from the H0 attempt and did not"
    echo "        re-discover OIDC. Wait longer between H0 and H1 or force a token"
    echo "        eviction and re-run."
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 6 — Silence gate: revision unchanged + ingress 200 + secret absent
# -----------------------------------------------------------------------------
# The silence gate proves the H1 failure was scoped strictly to the KV
# secret-reference validation. The already-running revision must be
# unaffected, and the H1 secret must not have made it into the app config.
echo "[H1] step 6: silence-gate proof (revision unchanged + ingress 200 + kvref-h1 absent)"
H1_APP_STATE_JSON="$(capture_app_state_snapshot "$H1_SECRET_REF_NAME" "false")"
echo "$H1_APP_STATE_JSON" > "$EVIDENCE_DIR/08-h1-app-state.json"
echo "  wrote evidence/08-h1-app-state.json"

H1_REV_UNCHANGED="$(echo "$H1_APP_STATE_JSON" | jq -r .latest_revision_unchanged_vs_baseline)"
H1_HTTP="$(echo "$H1_APP_STATE_JSON" | jq -r .ingress_probe_http_code)"
H1_EXPECTATION_MET="$(echo "$H1_APP_STATE_JSON" | jq -r .secret_presence_expectation_met)"

if [[ "$H1_REV_UNCHANGED" != "true" ]]; then
    echo "FAIL (H1 silence gate): latestReadyRevisionName CHANGED after H1 secret-set attempt."
    echo "  Baseline: $LATEST_REV_BASELINE"
    echo "  Now:      $(echo "$H1_APP_STATE_JSON" | jq -r .latest_ready_revision_name)"
    echo "  A new revision is not expected because secret updates do not create revisions."
    echo "  Check whether trigger.sh or some other action produced a new revision between H0 and H1."
    exit 1
fi
if [[ "$H1_HTTP" != "200" ]]; then
    echo "FAIL (H1 silence gate): ingress HTTP probe returned $H1_HTTP (expected 200)."
    echo "  The existing revision should be unaffected by the failing control-plane operation."
    echo "  If ingress is down, either the firewall change disrupted the app path (should not — Entra rule"
    echo "  is not on the data path) or an unrelated failure occurred."
    exit 1
fi
if [[ "$H1_EXPECTATION_MET" != "true" ]]; then
    echo "FAIL (H1 silence gate): secret '$H1_SECRET_REF_NAME' presence expectation NOT MET."
    echo "  Expected: absent (secret set failed). Observed count: $(echo "$H1_APP_STATE_JSON" | jq -r .observed_secret_present_count)"
    echo "  If the secret IS present despite exit != 0, ACA may have persisted the reference"
    echo "  before the OIDC failure surfaced; the failure mode may not match the customer scenario."
    exit 1
fi
echo "  silence gate OK: revision unchanged=$H1_REV_UNCHANGED, http=$H1_HTTP, expectation_met=$H1_EXPECTATION_MET"

# -----------------------------------------------------------------------------
# Step 7 — Smoking-gun KQL for firewall Deny row naming login.microsoftonline.com
# -----------------------------------------------------------------------------
# Azure Firewall log ingestion latency in Basic tier is typically 2-6 minutes.
# We poll AZFWApplicationRule (and AzureDiagnostics as a schema-compat fallback)
# for up to 10 minutes (10 attempts x 60s), matching pe-forced-inspection lab.
echo "[H1] step 7: waiting for firewall Deny log for '$ENTRA_FQDN_PRIMARY' since $H1_START_ISO"
DENY_ROW_COUNT="0"
DENY_ATTEMPT_LOG="[]"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    echo "  attempt ${attempt}/10: querying AZFWApplicationRule for Deny + '$ENTRA_FQDN_PRIMARY' since $H1_START_ISO"
    DENY_ROW_COUNT="$(count_azfw_entra_rows_since "$H1_START_ISO" "Deny")"
    DENY_ATTEMPT_LOG="$(echo "$DENY_ATTEMPT_LOG" | jq --arg n "$attempt" --arg c "$DENY_ROW_COUNT" '. + [{attempt: ($n|tonumber), row_count: ($c|tonumber)}]')"
    if [[ "$DENY_ROW_COUNT" -gt 0 ]]; then
        echo "  SMOKING GUN found on attempt ${attempt}: ${DENY_ROW_COUNT} Deny row(s)"
        break
    fi
    echo "  no Deny rows yet; sleeping 60s (firewall log ingestion latency)"
    sleep 60
done

# Even if the smoking gun eventually appears, capture the full row payload
# for the evidence pack. Use a wider window (since H1 start) so all rows
# in the H1 window are captured, not just the count.
FINAL_DENY_KQL="AZFWApplicationRule
| where TimeGenerated >= datetime('$H1_START_ISO')
| where Fqdn has '$ENTRA_FQDN_PRIMARY' or Fqdn has '$ENTRA_FQDN_SECONDARY'
| where Action == 'Deny'
| project TimeGenerated, Fqdn, SourceIp, Action, Policy, RuleCollectionGroup, RuleCollection, Rule
| order by TimeGenerated desc
| take 20"
FINAL_DENY_ROWS_JSON="$(az monitor log-analytics query \
    --workspace "$LAW_CUSTOMER_ID" \
    --analytics-query "$FINAL_DENY_KQL" \
    --output json 2>/dev/null || echo '[]')"

cat > "$EVIDENCE_DIR/09-h1-firewall-deny-log.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H1",
  "log_analytics_customer_id": "$LAW_CUSTOMER_ID",
  "kql_window_start_iso": "$H1_START_ISO",
  "kql_query": $(printf '%s' "$FINAL_DENY_KQL" | jq -Rs .),
  "final_deny_row_count": $DENY_ROW_COUNT,
  "attempts": $DENY_ATTEMPT_LOG,
  "denied_fqdn_primary": "$ENTRA_FQDN_PRIMARY",
  "denied_fqdn_secondary": "$ENTRA_FQDN_SECONDARY",
  "deny_rows": $FINAL_DENY_ROWS_JSON
}
EOF
echo "  wrote evidence/09-h1-firewall-deny-log.json  [deny_row_count=$DENY_ROW_COUNT]"

if [[ "$DENY_ROW_COUNT" -lt 1 ]]; then
    echo "FAIL (H1 smoking gun): AZFWApplicationRule never recorded a Deny row for"
    echo "  '$ENTRA_FQDN_PRIMARY' within 10 minutes of the H1 secret-set attempt."
    echo "  The lab thesis REQUIRES this row to exist as empirical proof that the firewall"
    echo "  denied the OIDC discovery call. Without it, we can claim 'secret set failed'"
    echo "  but not 'secret set failed BECAUSE the firewall denied Entra discovery'."
    echo "  Possible causes:"
    echo "    (a) firewall diagnostic settings not flowing to LAW (check diag-to-law resource)"
    echo "    (b) log ingestion pipeline delayed >10m (rerun this step later)"
    echo "    (c) ACA control plane reached login.microsoftonline.com via a path that does"
    echo "        NOT traverse the customer subnet — this would be a Microsoft-internal"
    echo "        change that INVALIDATES the entire lab thesis; escalate before publishing."
    exit 1
fi

# =============================================================================
# H2 PHASE — restore the Entra Application Rule and verify recovery
# =============================================================================

# -----------------------------------------------------------------------------
# Step 8 — H2 start timestamp (bounds firewall Allow query window)
# -----------------------------------------------------------------------------
H2_START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""
echo "[H2] step 8: H2 start timestamp = $H2_START_ISO"

# -----------------------------------------------------------------------------
# Step 9 — Restore the Entra Application Rule collection
# -----------------------------------------------------------------------------
# Re-adds an equivalent rule collection: same name, same priority, same
# source addresses (snet-aca CIDR), same protocol (Https=443), same two
# target FQDNs. This mirrors what main.bicep would create if trigger.sh
# had just been re-run — no schema drift.
echo "[H2] step 9: RESTORING rule collection '$ENTRA_RULE_COLLECTION_NAME'"
RESTORE_STDOUT_FILE="$(mktemp)"
RESTORE_STDERR_FILE="$(mktemp)"
RESTORE_EXIT=0
az network firewall policy rule-collection-group collection add-filter-collection \
    --resource-group "$RG" \
    --policy-name "$FIREWALL_POLICY_NAME" \
    --rule-collection-group-name "$RULE_COLLECTION_GROUP_NAME" \
    --name "$ENTRA_RULE_COLLECTION_NAME" \
    --collection-priority "$ENTRA_COLLECTION_PRIORITY" \
    --action Allow \
    --rule-name "$ENTRA_RULE_NAME" \
    --rule-type ApplicationRule \
    --source-addresses "$ACA_SUBNET_PREFIX" \
    --protocols "Https=443" \
    --target-fqdns "$ENTRA_FQDN_PRIMARY" "$ENTRA_FQDN_SECONDARY" \
    --output json >"$RESTORE_STDOUT_FILE" 2>"$RESTORE_STDERR_FILE" || RESTORE_EXIT=$?
RESTORE_STDOUT="$(cat "$RESTORE_STDOUT_FILE")"
RESTORE_STDERR="$(cat "$RESTORE_STDERR_FILE")"
rm -f "$RESTORE_STDOUT_FILE" "$RESTORE_STDERR_FILE"

if [[ $RESTORE_EXIT -ne 0 ]]; then
    echo "ERROR: rule-collection-group collection add-filter-collection failed (exit=$RESTORE_EXIT)."
    echo "  stderr: $RESTORE_STDERR"
    exit 1
fi

# Verify the collection is present again.
POST_RESTORE_GROUP_JSON="$(az network firewall policy rule-collection-group show \
    --resource-group "$RG" \
    --policy-name "$FIREWALL_POLICY_NAME" \
    --name "$RULE_COLLECTION_GROUP_NAME" \
    --output json)"
POST_RESTORE_COLLECTION_NAMES="$(echo "$POST_RESTORE_GROUP_JSON" | jq -r '.ruleCollections[].name')"
if ! echo "$POST_RESTORE_COLLECTION_NAMES" | grep -q "^${ENTRA_RULE_COLLECTION_NAME}$"; then
    echo "ERROR: rule collection '$ENTRA_RULE_COLLECTION_NAME' NOT present after restore call."
    echo "  Current collections in group: $POST_RESTORE_COLLECTION_NAMES"
    exit 1
fi
RESTORED_FQDNS="$(echo "$POST_RESTORE_GROUP_JSON" | jq -c --arg cn "$ENTRA_RULE_COLLECTION_NAME" --arg rn "$ENTRA_RULE_NAME" '[.ruleCollections[] | select(.name == $cn) | .rules[] | select(.name == $rn) | .targetFqdns[]]')"
echo "  restored OK. Target FQDNs in restored rule: $RESTORED_FQDNS"

cat > "$EVIDENCE_DIR/10-h2-firewall-rule-restored.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "action": "restore-rule-collection",
  "firewall_policy_name": "$FIREWALL_POLICY_NAME",
  "rule_collection_group_name": "$RULE_COLLECTION_GROUP_NAME",
  "rule_collection_name": "$ENTRA_RULE_COLLECTION_NAME",
  "restore_exit_code": $RESTORE_EXIT,
  "post_restore_collections_in_group": $(echo "$POST_RESTORE_COLLECTION_NAMES" | jq -R -s -c 'split("\n") | map(select(length > 0))'),
  "restored_target_fqdns": $RESTORED_FQDNS,
  "controlled_variable_present_after_restore": true
}
EOF
echo "  wrote evidence/10-h2-firewall-rule-restored.json"

# -----------------------------------------------------------------------------
# Step 10 — Wait for firewall policy convergence
# -----------------------------------------------------------------------------
echo "[H2] step 10: waiting 60s for firewall policy convergence"
sleep 60

# -----------------------------------------------------------------------------
# Step 11 — Create fresh KV secret for H2 attempt
# -----------------------------------------------------------------------------
SECRET_NAME_H2="kvref-h2-value"
SECRET_VALUE_H2="h2-value-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[H2] step 11: creating KV secret '$SECRET_NAME_H2' in vault '$KV_NAME'"
az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME_H2" --value "$SECRET_VALUE_H2" --output none
KV_SECRET_URL_H2="${KV_URI}secrets/${SECRET_NAME_H2}"

# -----------------------------------------------------------------------------
# Step 12 — H2: attempt `az containerapp secret set` (MUST SUCCEED)
# -----------------------------------------------------------------------------
H2_SECRET_REF_NAME="kvref-h2"
echo "[H2] step 12: attempting 'az containerapp secret set --identity system' (MUST SUCCEED)"
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
  "hypothesis": "H2: Entra Application Rule RESTORED -> \`az containerapp secret set\` SUCCEEDS",
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
    echo "FAIL (H2): 'az containerapp secret set' FAILED after restoring the Entra rule."
    echo "  stderr: $SET_STDERR"
    echo "  Possible causes:"
    echo "    (a) firewall policy change did not converge — wait longer and retry"
    echo "    (b) KV RBAC eviction for the app MI — check role assignments"
    echo "    (c) unrelated Azure outage in the region — check Service Health"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 13 — Post-H2 app state: revision unchanged + kvref-h2 present + HTTP 200
# -----------------------------------------------------------------------------
echo "[H2] step 13: post-restore app state (revision unchanged + kvref-h2 present + ingress 200)"
H2_APP_STATE_JSON="$(capture_app_state_snapshot "$H2_SECRET_REF_NAME" "true")"
echo "$H2_APP_STATE_JSON" > "$EVIDENCE_DIR/12-h2-app-state.json"
echo "  wrote evidence/12-h2-app-state.json"

H2_REV_UNCHANGED="$(echo "$H2_APP_STATE_JSON" | jq -r .latest_revision_unchanged_vs_baseline)"
H2_HTTP="$(echo "$H2_APP_STATE_JSON" | jq -r .ingress_probe_http_code)"
H2_EXPECTATION_MET="$(echo "$H2_APP_STATE_JSON" | jq -r .secret_presence_expectation_met)"

if [[ "$H2_REV_UNCHANGED" != "true" ]]; then
    echo "WARN (H2): latestReadyRevisionName CHANGED after H2 secret-set attempt."
    echo "  Baseline: $LATEST_REV_BASELINE"
    echo "  Now:      $(echo "$H2_APP_STATE_JSON" | jq -r .latest_ready_revision_name)"
    echo "  Secret updates should not create new revisions. This is unexpected but"
    echo "  does not falsify H2. Continuing."
fi
if [[ "$H2_HTTP" != "200" ]]; then
    echo "WARN (H2): ingress HTTP probe returned $H2_HTTP (expected 200)."
fi
if [[ "$H2_EXPECTATION_MET" != "true" ]]; then
    echo "FAIL (H2): secret '$H2_SECRET_REF_NAME' presence expectation NOT MET."
    echo "  Expected: present (secret set succeeded). Observed count: $(echo "$H2_APP_STATE_JSON" | jq -r .observed_secret_present_count)"
    echo "  H2 exit code was 0 but the secret did not persist to configuration.secrets."
    echo "  This is a hard inconsistency and blocks the H2 recovery proof."
    exit 1
fi
echo "  H2 recovery OK: revision unchanged=$H2_REV_UNCHANGED, http=$H2_HTTP, expectation_met=$H2_EXPECTATION_MET"

# -----------------------------------------------------------------------------
# Step 14 — Smoking-gun KQL for firewall Allow row after restore
# -----------------------------------------------------------------------------
echo "[H2] step 14: waiting for firewall Allow log for '$ENTRA_FQDN_PRIMARY' since $H2_START_ISO"
ALLOW_ROW_COUNT="0"
ALLOW_ATTEMPT_LOG="[]"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    echo "  attempt ${attempt}/10: querying AZFWApplicationRule for Allow + '$ENTRA_FQDN_PRIMARY' since $H2_START_ISO"
    ALLOW_ROW_COUNT="$(count_azfw_entra_rows_since "$H2_START_ISO" "Allow")"
    ALLOW_ATTEMPT_LOG="$(echo "$ALLOW_ATTEMPT_LOG" | jq --arg n "$attempt" --arg c "$ALLOW_ROW_COUNT" '. + [{attempt: ($n|tonumber), row_count: ($c|tonumber)}]')"
    if [[ "$ALLOW_ROW_COUNT" -gt 0 ]]; then
        echo "  RECOVERY PROOF found on attempt ${attempt}: ${ALLOW_ROW_COUNT} Allow row(s)"
        break
    fi
    echo "  no Allow rows yet; sleeping 60s"
    sleep 60
done

FINAL_ALLOW_KQL="AZFWApplicationRule
| where TimeGenerated >= datetime('$H2_START_ISO')
| where Fqdn has '$ENTRA_FQDN_PRIMARY' or Fqdn has '$ENTRA_FQDN_SECONDARY'
| where Action == 'Allow'
| project TimeGenerated, Fqdn, SourceIp, Action, Policy, RuleCollectionGroup, RuleCollection, Rule
| order by TimeGenerated desc
| take 20"
FINAL_ALLOW_ROWS_JSON="$(az monitor log-analytics query \
    --workspace "$LAW_CUSTOMER_ID" \
    --analytics-query "$FINAL_ALLOW_KQL" \
    --output json 2>/dev/null || echo '[]')"

cat > "$EVIDENCE_DIR/13-h2-firewall-allow-log.json" <<EOF
{
  "captured_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "H2",
  "log_analytics_customer_id": "$LAW_CUSTOMER_ID",
  "kql_window_start_iso": "$H2_START_ISO",
  "kql_query": $(printf '%s' "$FINAL_ALLOW_KQL" | jq -Rs .),
  "final_allow_row_count": $ALLOW_ROW_COUNT,
  "attempts": $ALLOW_ATTEMPT_LOG,
  "allowed_fqdn_primary": "$ENTRA_FQDN_PRIMARY",
  "allowed_fqdn_secondary": "$ENTRA_FQDN_SECONDARY",
  "allow_rows": $FINAL_ALLOW_ROWS_JSON
}
EOF
echo "  wrote evidence/13-h2-firewall-allow-log.json  [allow_row_count=$ALLOW_ROW_COUNT]"

if [[ "$ALLOW_ROW_COUNT" -lt 1 ]]; then
    echo "FAIL (H2 recovery gate): AZFWApplicationRule never recorded an Allow row for"
    echo "  '$ENTRA_FQDN_PRIMARY' within 10 minutes of the H2 secret-set success."
    echo "  H2 exit code was 0 (secret set succeeded), but we have no firewall log"
    echo "  showing the Entra discovery call passed through the restored rule."
    echo "  This is inconsistent — investigate before publishing:"
    echo "    (a) the H2 success may have used a cached OIDC discovery result"
    echo "    (b) diagnostic settings may have regressed between H1 and H2"
    echo "    (c) log ingestion pipeline may be severely delayed"
    exit 1
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=== falsify.sh complete ==="
echo "Evidence directory: $EVIDENCE_DIR"
echo "  06-h1-firewall-rule-removed.json    [removed '$ENTRA_RULE_COLLECTION_NAME']"
echo "  07-h1-secret-set-outcome.json       [exit=nonzero as expected]"
echo "  08-h1-app-state.json                [silence gate: revision unchanged, ingress 200, kvref-h1 absent]"
echo "  09-h1-firewall-deny-log.json        [Deny rows for '$ENTRA_FQDN_PRIMARY' since $H1_START_ISO = $DENY_ROW_COUNT]"
echo "  10-h2-firewall-rule-restored.json   [restored '$ENTRA_RULE_COLLECTION_NAME']"
echo "  11-h2-secret-set-outcome.json       [exit=0 as expected]"
echo "  12-h2-app-state.json                [kvref-h2 present, ingress 200]"
echo "  13-h2-firewall-allow-log.json       [Allow rows for '$ENTRA_FQDN_PRIMARY' since $H2_START_ISO = $ALLOW_ROW_COUNT]"
echo ""
echo "H1 falsified: Entra Application Rule REMOVED -> secret set FAILED + firewall recorded Deny."
echo "H2 verified:  Entra Application Rule RESTORED -> secret set SUCCEEDED + firewall recorded Allow."
echo ""
echo "Next: bash verify.sh   (hermetic gate re-computation from committed evidence)"
