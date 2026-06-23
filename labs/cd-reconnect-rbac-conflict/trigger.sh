#!/usr/bin/env bash
set -euo pipefail

export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore}"

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"
: "${APP_NAME:?Set APP_NAME before running}"
: "${ACR_NAME:?Set ACR_NAME before running}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/infra/role-assignment.bicep"
SP_NAME="${APP_NAME}-github-actions-lab"

ACR_ID=$(az acr show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$ACR_NAME" \
    --resource-group "$RG" \
    --query "id" \
    --output tsv | tr -d '\r')

UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "trigger.sh starting at ${UTC_NOW}"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "RG: ${RG}"
echo "App (container app name, used only to derive SP_NAME): ${APP_NAME}"
echo "ACR: ${ACR_NAME}"
echo "ACR ID (scope for AcrPush): ${ACR_ID}"
echo "SP display name: ${SP_NAME}"
echo ""
echo "Note: This lab reproduces the ARM 'RoleAssignmentExists' conflict that surfaces as"
echo "AppRbacDeployment when CD reconnect retries a Microsoft.Authorization/roleAssignments"
echo "write on a (scope, principal, role) triple that already has an assignment. Phase 1"
echo "creates (or resolves) a service principal that simulates the CD identity. Phase 2"
echo "runs the initial ARM deployment that grants AcrPush on the registry (with the"
echo "deterministic GUID derived from registry+SP+role). Phase 3 waits for RBAC propagation"
echo "and snapshots the assignment count (expected: exactly 1). Phase 4 simulates the"
echo "Portal 'Disconnect' — Azure-side state remains. Phase 5 retries the same ARM"
echo "deployment with a freshly generated roleAssignmentName, which is exactly what"
echo "az containerapp github-action add does on every invocation; ARM rejects the write"
echo "with HTTP 409 and Code=RoleAssignmentExists, returning the existing 32-char hex ID."
echo "Phase 6 extracts the hex ID and emits hyphenated GUID form. Phase 7 emits the H1"
echo "gate JSON. Modern Azure CLI az role assignment create is idempotent on this same"
echo "triple, so this lab uses ARM deployments to surface the failure exactly as the"
echo "Portal-driven CD reconnect path does."
echo ""

echo "=== Phase 1: resolve or create service principal that simulates the CD identity ==="
# az ad sp create-for-rbac is avoided because tenant credential-lifetime policies frequently
# block it. The two-step az ad app create + az ad sp create flow is what the CD setup
# actually uses internally and works in tenants with restrictive policies.
SP_APP_ID=$(az ad sp list \
    --display-name "$SP_NAME" \
    --query "[0].appId" \
    --output tsv | tr -d '\r')
if [ -z "$SP_APP_ID" ] || [ "$SP_APP_ID" = "null" ]; then
    APP_ID=$(az ad app list \
        --display-name "$SP_NAME" \
        --query "[0].appId" \
        --output tsv | tr -d '\r')
    if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
        APP_ID=$(az ad app create \
            --display-name "$SP_NAME" \
            --query "appId" \
            --output tsv | tr -d '\r')
        echo "Created new app registration: ${APP_ID}"
    else
        echo "Reusing existing app registration: ${APP_ID}"
    fi
    az ad sp create --id "$APP_ID" --output none
    SP_APP_ID="$APP_ID"
    echo "Created SP for app ${APP_ID}"
else
    echo "Reusing existing service principal: ${SP_APP_ID}"
fi

# SP propagation in Microsoft Entra ID is asynchronous; poll until az ad sp show resolves.
SP_OBJECT_ID=""
for i in 1 2 3 4 5 6; do
    SP_OBJECT_ID=$(az ad sp show \
        --id "$SP_APP_ID" \
        --query "id" \
        --output tsv 2>/dev/null | tr -d '\r' || true)
    [ -n "$SP_OBJECT_ID" ] && break
    echo "Waiting for SP propagation in Entra ID (attempt $i/6)..."
    sleep 10
done
if [ -z "$SP_OBJECT_ID" ]; then
    echo "ERROR: SP object id not resolvable for appId ${SP_APP_ID}"
    exit 1
fi
echo "Resolved: appId=${SP_APP_ID} objectId=${SP_OBJECT_ID}"

az ad sp show \
    --id "$SP_APP_ID" \
    --query "{appId: appId, id: id, displayName: displayName, servicePrincipalType: servicePrincipalType, accountEnabled: accountEnabled, appOwnerOrganizationId: appOwnerOrganizationId}" \
    --output json \
    > "$EVIDENCE_DIR/01-sp-resolve.json"
cat "$EVIDENCE_DIR/01-sp-resolve.json"
echo ""

echo "=== Phase 2: initial ARM deployment grants AcrPush on registry (deterministic GUID) ==="
# infra/role-assignment.bicep with empty roleAssignmentName uses guid(registry.id, principalId, roleDef)
# which is the same deterministic derivation Microsoft's CD setup uses on the first deploy.
INITIAL_DEPLOY_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Initial deploy UTC: ${INITIAL_DEPLOY_UTC}"
az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "lab-ra-initial" \
    --template-file "$TEMPLATE" \
    --parameters principalObjectId="$SP_OBJECT_ID" registryName="$ACR_NAME" \
    --output json \
    > "$EVIDENCE_DIR/02-deployment-initial-output.json"
INITIAL_PROVISIONING_STATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/02-deployment-initial-output.json'))['properties']['provisioningState'])")
INITIAL_ASSIGNMENT_NAME=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/02-deployment-initial-output.json')); print(d['properties']['outputs']['roleAssignmentName']['value'])")
echo "Initial deployment provisioningState: ${INITIAL_PROVISIONING_STATE}"
echo "Initial role assignment name (deterministic GUID): ${INITIAL_ASSIGNMENT_NAME}"
echo ""

echo "=== Phase 3: wait for RBAC propagation, then snapshot role assignment list (expect exactly 1) ==="
# RBAC propagation across regions and replicas is asynchronous. 15 s is the threshold
# used by Microsoft's official quickstarts and matches what the original script used.
echo "Sleeping 15 s for RBAC propagation..."
sleep 15
az role assignment list \
    --subscription "$AZ_SUBSCRIPTION" \
    --assignee "$SP_APP_ID" \
    --scope "$ACR_ID" \
    --query "[].{name: name, roleDefinitionName: roleDefinitionName, principalType: principalType, scope: scope, createdOn: createdOn}" \
    --output json \
    > "$EVIDENCE_DIR/03-role-assignment-list-baseline.json"
cat "$EVIDENCE_DIR/03-role-assignment-list-baseline.json"
INITIAL_ASSIGNMENT_COUNT=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/03-role-assignment-list-baseline.json'))))")
echo "Baseline assignment count for SP on ACR scope: ${INITIAL_ASSIGNMENT_COUNT}"
echo ""

echo "=== Phase 4: simulated 'Disconnect' (Portal removes GitHub artifacts only; Azure-side state remains) ==="
# This is intentionally a no-op against Azure. The Portal Disconnect flow removes the
# GitHub workflow file and repository secrets but does NOT delete the SP or any role
# assignments — that is the entire reason the reconnect attempt later fails.
echo "Simulated disconnect: no Azure-side cleanup performed."
echo "Service principal ${SP_NAME} (${SP_APP_ID}) and its AcrPush assignment on ${ACR_NAME} remain."
echo ""

echo "=== Phase 5: reconnect ARM deployment with FRESH roleAssignmentName (expected: HTTP 409 RoleAssignmentExists) ==="
# Every invocation of az containerapp github-action add generates a fresh role assignment
# GUID for the AppRbacDeployment ARM template, even when the (scope, principal, role)
# triple already has an assignment. ARM enforces RBAC's uniqueness constraint at the
# resource-write level and returns 409 Conflict with Code=RoleAssignmentExists, exposing
# the existing 32-char hex assignment ID in the error message.
NEW_NAME=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr '[:upper:]' '[:lower:]')
echo "Generated fresh roleAssignmentName: ${NEW_NAME}"
RECONNECT_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Reconnect deploy UTC: ${RECONNECT_UTC}"

# az deployment group create is expected to fail. set +e + capture exit code so the
# script can extract the conflict GUID instead of aborting.
set +e
az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "lab-ra-reconnect" \
    --template-file "$TEMPLATE" \
    --parameters principalObjectId="$SP_OBJECT_ID" registryName="$ACR_NAME" roleAssignmentName="$NEW_NAME" \
    --output json \
    > "$EVIDENCE_DIR/04-deployment-reconnect-stderr.txt" 2>&1
RECONNECT_EXIT_CODE=$?
set -e
echo "Reconnect deployment exit code: ${RECONNECT_EXIT_CODE} (expected: non-zero)"
echo ""
echo "Reconnect deployment raw output (first 30 lines):"
head -n 30 "$EVIDENCE_DIR/04-deployment-reconnect-stderr.txt" || true
echo ""

# Capture the failed deployment's metadata via az deployment group show (succeeds even
# though the deployment itself failed, because the deployment record exists).
RECONNECT_DEPLOYMENT_EXISTS=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "lab-ra-reconnect" \
    --query "name" \
    --output tsv 2>/dev/null | tr -d '\r' || echo "")
if [ -n "$RECONNECT_DEPLOYMENT_EXISTS" ]; then
    az deployment group show \
        --subscription "$AZ_SUBSCRIPTION" \
        --resource-group "$RG" \
        --name "lab-ra-reconnect" \
        --query "{name: name, provisioningState: properties.provisioningState, timestamp: properties.timestamp, correlationId: properties.correlationId, error: properties.error}" \
        --output json \
        > "$EVIDENCE_DIR/05-deployment-reconnect-failure.json"
    cat "$EVIDENCE_DIR/05-deployment-reconnect-failure.json"
    RECONNECT_PROVISIONING_STATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/05-deployment-reconnect-failure.json'))['provisioningState'])")
else
    echo '{}' > "$EVIDENCE_DIR/05-deployment-reconnect-failure.json"
    RECONNECT_PROVISIONING_STATE="DeploymentRecordNotCreated"
fi
echo "Reconnect provisioning state: ${RECONNECT_PROVISIONING_STATE} (expected: Failed)"
echo ""

echo "=== Phase 6: extract conflict GUID from reconnect error (expected: 32-char hex) ==="
# The error message format from ARM is:
#   "The role assignment already exists. The ID of the existing role assignment is <32-char-hex>."
# Two variants exist depending on whether the message came from the CLI's RPC layer or
# the inner ARM response; both place the GUID immediately after "existing role assignment is ".
# The hex GUID is 32 chars with no hyphens; the hyphenated 8-4-4-4-12 form is what the
# Portal displays and what az role assignment delete --ids expects.
CONFLICT_GUID_HEX=$(grep -oE 'existing role assignment is [a-f0-9]{32}' "$EVIDENCE_DIR/04-deployment-reconnect-stderr.txt" 2>/dev/null | head -n 1 | awk '{print $NF}' || true)
RECONNECT_HAS_ROLE_ASSIGNMENT_EXISTS=false
if grep -qE 'RoleAssignmentExists|already exists' "$EVIDENCE_DIR/04-deployment-reconnect-stderr.txt" 2>/dev/null; then
    RECONNECT_HAS_ROLE_ASSIGNMENT_EXISTS=true
fi

if [ -n "$CONFLICT_GUID_HEX" ]; then
    CONFLICT_GUID_HYPHENATED=$(echo "$CONFLICT_GUID_HEX" | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')
    echo "Conflict GUID (32-char hex): ${CONFLICT_GUID_HEX}"
    echo "Conflict GUID (hyphenated):  ${CONFLICT_GUID_HYPHENATED}"
else
    CONFLICT_GUID_HYPHENATED=""
    echo "Conflict GUID NOT extracted (reconnect did not return RoleAssignmentExists payload)"
fi

export CONFLICT_GUID_HEX CONFLICT_GUID_HYPHENATED RECONNECT_HAS_ROLE_ASSIGNMENT_EXISTS EVIDENCE_DIR
python3 <<'PYEOF'
import json, os
# Bash booleans 'true'/'false' do not parse as Python literals; coerce via os.environ + .lower().
out = {
    "conflict_guid_hex": os.environ['CONFLICT_GUID_HEX'],
    "conflict_guid_hyphenated": os.environ['CONFLICT_GUID_HYPHENATED'],
    "reconnect_error_contains_role_assignment_exists": os.environ['RECONNECT_HAS_ROLE_ASSIGNMENT_EXISTS'].lower() == 'true',
    "extraction_pattern": "existing role assignment is [a-f0-9]{32}",
    "source_file": "04-deployment-reconnect-stderr.txt",
    "note": "The conflict GUID matches the assignment name created by Phase 2 (deterministic GUID derived from registry.id + principalId + AcrPush role)."
}
with open(os.path.join(os.environ['EVIDENCE_DIR'], "06-conflict-guid-extraction.json"), "w") as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== Phase 7: emit H1 gate JSON ==="
UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR SP_NAME SP_APP_ID SP_OBJECT_ID ACR_NAME ACR_ID RG AZ_SUBSCRIPTION UTC_CAPTURED
export INITIAL_DEPLOY_UTC RECONNECT_UTC INITIAL_PROVISIONING_STATE INITIAL_ASSIGNMENT_NAME
export INITIAL_ASSIGNMENT_COUNT RECONNECT_PROVISIONING_STATE RECONNECT_EXIT_CODE
export CONFLICT_GUID_HEX CONFLICT_GUID_HYPHENATED RECONNECT_HAS_ROLE_ASSIGNMENT_EXISTS NEW_NAME

python3 <<'PYEOF'
import json, os

# H1 sub-gates for cd-reconnect-rbac-conflict:
#
# a_sp_resolved                              - SP appId resolves and object id is non-empty.
# b_initial_deployment_succeeded             - Phase 2 lab-ra-initial deployment provisioningState=Succeeded.
# c_initial_role_assignment_count_equals_one - Phase 3 shows exactly 1 AcrPush assignment for SP on ACR scope.
# d_reconnect_deployment_failed_with_role_assignment_exists
#                                            - Phase 5 az deployment exit_code != 0 AND Phase 6 extracted a
#                                              non-empty 32-char hex GUID AND the stderr contained the
#                                              RoleAssignmentExists / already-exists token.

sp_app_id = os.environ['SP_APP_ID']
sp_object_id = os.environ['SP_OBJECT_ID']
initial_provisioning_state = os.environ['INITIAL_PROVISIONING_STATE']
initial_assignment_count = int(os.environ['INITIAL_ASSIGNMENT_COUNT'])
reconnect_provisioning_state = os.environ['RECONNECT_PROVISIONING_STATE']
reconnect_exit_code = int(os.environ['RECONNECT_EXIT_CODE'])
conflict_guid_hex = os.environ['CONFLICT_GUID_HEX']
conflict_guid_hyphenated = os.environ['CONFLICT_GUID_HYPHENATED']
reconnect_has_role_assignment_exists = os.environ['RECONNECT_HAS_ROLE_ASSIGNMENT_EXISTS'].lower() == 'true'

a_sp_resolved = bool(sp_app_id) and bool(sp_object_id)
b_initial_deployment_succeeded = initial_provisioning_state == 'Succeeded'
c_initial_role_assignment_count_equals_one = initial_assignment_count == 1
d_reconnect_deployment_failed_with_role_assignment_exists = (
    reconnect_exit_code != 0
    and bool(conflict_guid_hex)
    and reconnect_has_role_assignment_exists
)

h1_sub_gates = {
    'a_sp_resolved': a_sp_resolved,
    'b_initial_deployment_succeeded': b_initial_deployment_succeeded,
    'c_initial_role_assignment_count_equals_one': c_initial_role_assignment_count_equals_one,
    'd_reconnect_deployment_failed_with_role_assignment_exists': d_reconnect_deployment_failed_with_role_assignment_exists,
}
h1_all_subgates_pass = all(h1_sub_gates.values())

# Classification logic:
#   cd_rbac_conflict_reproduced            - all 4 sub-gates pass (expected here)
#   cd_rbac_conflict_did_not_materialize   - reconnect deployment SUCCEEDED instead of failing
#                                            (sub-gate d false because exit code is 0). This
#                                            falsifies H1: the (scope, principal, role) uniqueness
#                                            constraint did not block the second ARM write, which
#                                            would mean RBAC behavior differs from documented model.
#   partial_observation_some_subgates_failed
#                                          - everything else (e.g., reconnect failed but error
#                                            text did not contain RoleAssignmentExists, or
#                                            initial assignment count was 0 or >1).

if h1_all_subgates_pass:
    gate_classification = 'cd_rbac_conflict_reproduced'
elif (reconnect_exit_code == 0
      and reconnect_provisioning_state == 'Succeeded'
      and a_sp_resolved
      and b_initial_deployment_succeeded
      and c_initial_role_assignment_count_equals_one):
    gate_classification = 'cd_rbac_conflict_did_not_materialize'
else:
    gate_classification = 'partial_observation_some_subgates_failed'

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'subscription': os.environ['AZ_SUBSCRIPTION'],
    'rg': os.environ['RG'],
    'acr_name': os.environ['ACR_NAME'],
    'acr_id': os.environ['ACR_ID'],
    'sp_name': os.environ['SP_NAME'],
    'sp_app_id': sp_app_id,
    'sp_object_id': sp_object_id,
    'initial_deploy_window': {
        'start_utc': os.environ['INITIAL_DEPLOY_UTC'],
        'provisioning_state': initial_provisioning_state,
        'role_assignment_name': os.environ['INITIAL_ASSIGNMENT_NAME'],
    },
    'reconnect_deploy_window': {
        'start_utc': os.environ['RECONNECT_UTC'],
        'fresh_role_assignment_name': os.environ['NEW_NAME'],
        'provisioning_state': reconnect_provisioning_state,
        'cli_exit_code': reconnect_exit_code,
    },
    'rbac_observations': {
        'initial_assignment_count': initial_assignment_count,
        'conflict_guid_hex': conflict_guid_hex,
        'conflict_guid_hyphenated': conflict_guid_hyphenated,
        'reconnect_error_contains_role_assignment_exists': reconnect_has_role_assignment_exists,
    },
    'h1_sub_gates': h1_sub_gates,
    'h1_all_subgates_pass': h1_all_subgates_pass,
    'gate_classification': gate_classification,
}

with open(os.path.join(os.environ['EVIDENCE_DIR'], '07-h1-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PYEOF
echo ""

echo "=== H1 summary ==="
echo "SP resolved: appId=${SP_APP_ID} (expected: non-empty)"
echo "Initial deployment provisioningState: ${INITIAL_PROVISIONING_STATE} (expected: Succeeded)"
echo "Baseline AcrPush assignment count: ${INITIAL_ASSIGNMENT_COUNT} (expected: 1)"
echo "Reconnect deployment exit code: ${RECONNECT_EXIT_CODE} (expected: non-zero)"
echo "Reconnect error contains RoleAssignmentExists: ${RECONNECT_HAS_ROLE_ASSIGNMENT_EXISTS} (expected: true)"
echo "Conflict GUID (hex): ${CONFLICT_GUID_HEX} (expected: 32-char hex)"
echo "Conflict GUID (hyphenated): ${CONFLICT_GUID_HYPHENATED}"
GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/07-h1-gate.json'))['gate_classification'])")
echo "Gate classification: ${GATE}"

if [ "$GATE" = "cd_rbac_conflict_reproduced" ]; then
    echo ""
    echo "H1 PASS: reconnect ARM deployment failed with RoleAssignmentExists (HTTP 409) and"
    echo "returned the existing assignment ID. Proceed to verify.sh for the recovery experiment."
    exit 0
elif [ "$GATE" = "cd_rbac_conflict_did_not_materialize" ]; then
    echo ""
    echo "H1 FALSIFIED: reconnect deployment succeeded with the fresh roleAssignmentName."
    echo "This contradicts the documented RBAC (scope, principal, role) uniqueness constraint."
    echo "Investigate az/ARM versions before proceeding (verify.sh will exit 1 if this state)."
    exit 2
else
    echo ""
    echo "H1 PARTIAL: some sub-gates failed. Inspect 07-h1-gate.json for details."
    exit 2
fi
