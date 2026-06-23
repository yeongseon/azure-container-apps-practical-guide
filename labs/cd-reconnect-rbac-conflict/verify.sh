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
echo "verify.sh starting at ${UTC_NOW}"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "RG: ${RG}"
echo "ACR: ${ACR_NAME}"
echo "ACR ID: ${ACR_ID}"
echo "SP display name: ${SP_NAME}"
echo ""

echo "=== Phase 8: validate H1 evidence from trigger.sh ==="
H1_FILE="$EVIDENCE_DIR/07-h1-gate.json"
if [[ ! -f "$H1_FILE" ]]; then
    echo "INVALID RUN: $H1_FILE not found. Run trigger.sh first."
    exit 1
fi
H1_GATE=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['gate_classification'])")
H1_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['h1_all_subgates_pass'])")
SP_APP_ID=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['sp_app_id'])")
SP_OBJECT_ID=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['sp_object_id'])")
INITIAL_ASSIGNMENT_NAME=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['initial_deploy_window']['role_assignment_name'])")
CONFLICT_GUID_HEX=$(python3 -c "import json; print(json.load(open('$H1_FILE'))['rbac_observations']['conflict_guid_hex'])")
echo "H1 state: gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
echo "SP appId (from H1): ${SP_APP_ID}"
echo "SP objectId (from H1): ${SP_OBJECT_ID}"
echo "Initial deterministic GUID (from H1): ${INITIAL_ASSIGNMENT_NAME}"
echo "Conflict GUID (from H1): ${CONFLICT_GUID_HEX}"
if [[ "$H1_GATE" == "cd_rbac_conflict_did_not_materialize" ]]; then
    echo "INVALID RUN: H1 was FALSIFIED in trigger.sh. The reconnect ARM deployment succeeded instead of failing with RoleAssignmentExists; the baseline conflict state did not materialize so the recovery experiment cannot proceed."
    exit 1
fi
if [[ -z "$SP_APP_ID" ]] || [[ -z "$SP_OBJECT_ID" ]]; then
    echo "INVALID RUN: SP identifiers missing from H1 gate JSON."
    exit 1
fi
echo ""

echo "=== Phase 9: re-confirm conflict persists at start of verify (expected: same RoleAssignmentExists) ==="
NEW_NAME_VERIFY=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr '[:upper:]' '[:lower:]')
echo "Generated fresh roleAssignmentName for re-confirmation: ${NEW_NAME_VERIFY}"
REVERIFY_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Re-verify deploy UTC: ${REVERIFY_UTC}"

set +e
az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "lab-ra-verify-conflict" \
    --template-file "$TEMPLATE" \
    --parameters principalObjectId="$SP_OBJECT_ID" registryName="$ACR_NAME" roleAssignmentName="$NEW_NAME_VERIFY" \
    --output json \
    > "$EVIDENCE_DIR/08-deployment-reverify-conflict.txt" 2>&1
REVERIFY_EXIT_CODE=$?
set -e
echo "Re-verify deployment exit code: ${REVERIFY_EXIT_CODE} (expected: non-zero)"
echo "Re-verify raw output (first 20 lines):"
head -n 20 "$EVIDENCE_DIR/08-deployment-reverify-conflict.txt" || true
echo ""

REVERIFY_HAS_CONFLICT=false
if grep -qE 'RoleAssignmentExists|already exists' "$EVIDENCE_DIR/08-deployment-reverify-conflict.txt" 2>/dev/null; then
    REVERIFY_HAS_CONFLICT=true
fi
echo "Re-verify error contains RoleAssignmentExists: ${REVERIFY_HAS_CONFLICT} (expected: true)"
echo ""

echo "=== Phase 10: snapshot role assignment list pre-delete (expected: 1 assignment, name=initial GUID) ==="
az role assignment list \
    --subscription "$AZ_SUBSCRIPTION" \
    --assignee "$SP_APP_ID" \
    --scope "$ACR_ID" \
    --query "[].{name: name, roleDefinitionName: roleDefinitionName, principalType: principalType, scope: scope, createdOn: createdOn}" \
    --output json \
    > "$EVIDENCE_DIR/09-role-assignment-pre-delete.json"
cat "$EVIDENCE_DIR/09-role-assignment-pre-delete.json"
PRE_DELETE_COUNT=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/09-role-assignment-pre-delete.json'))))")
PRE_DELETE_ASSIGNMENT_NAME=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/09-role-assignment-pre-delete.json')); print(d[0]['name'] if d else '')")
echo "Pre-delete assignment count: ${PRE_DELETE_COUNT} (expected: 1)"
echo "Pre-delete assignment name: ${PRE_DELETE_ASSIGNMENT_NAME} (expected: ${INITIAL_ASSIGNMENT_NAME})"
echo ""

if [[ -z "$PRE_DELETE_ASSIGNMENT_NAME" ]]; then
    echo "INVALID RUN: no role assignment found to delete. Cannot apply recovery."
    exit 1
fi

echo "=== Phase 11: apply recovery — delete conflicting role assignment ==="
DELETE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Delete UTC: ${DELETE_UTC}"
ASSIGNMENT_FULL_ID="${ACR_ID}/providers/Microsoft.Authorization/roleAssignments/${PRE_DELETE_ASSIGNMENT_NAME}"
echo "Deleting role assignment ID: ${ASSIGNMENT_FULL_ID}"

set +e
az role assignment delete \
    --subscription "$AZ_SUBSCRIPTION" \
    --ids "$ASSIGNMENT_FULL_ID" \
    > "$EVIDENCE_DIR/10-role-assignment-delete-output.txt" 2>&1
DELETE_EXIT_CODE=$?
set -e
echo "Delete command exit code: ${DELETE_EXIT_CODE} (expected: 0)"
cat "$EVIDENCE_DIR/10-role-assignment-delete-output.txt" || true
echo ""

echo "Sleeping 15 s for RBAC propagation after delete..."
sleep 15
echo ""

echo "=== Phase 12: retry ARM deployment with fresh roleAssignmentName (expected: Succeeded) ==="
RECOVERY_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Recovery deploy UTC: ${RECOVERY_UTC}"

set +e
# Split stdout/stderr so Bicep "new release available" WARNING (printed on stderr by
# the bicep transpiler) cannot pollute the JSON file that Python json.load() consumes.
# --only-show-errors is belt-and-suspenders against future Azure CLI WARNING noise.
az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name "lab-ra-verify-recovery" \
    --template-file "$TEMPLATE" \
    --parameters principalObjectId="$SP_OBJECT_ID" registryName="$ACR_NAME" roleAssignmentName="$NEW_NAME_VERIFY" \
    --only-show-errors \
    --output json \
    > "$EVIDENCE_DIR/11-deployment-recovery.json" \
    2> "$EVIDENCE_DIR/11-deployment-recovery.stderr"
RECOVERY_EXIT_CODE=$?
set -e
echo "Recovery deployment exit code: ${RECOVERY_EXIT_CODE} (expected: 0)"
echo ""

RECOVERY_PROVISIONING_STATE="Unknown"
RECOVERY_ASSIGNMENT_NAME=""
if [[ "$RECOVERY_EXIT_CODE" -eq 0 ]]; then
    RECOVERY_PROVISIONING_STATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/11-deployment-recovery.json'))['properties']['provisioningState'])" 2>/dev/null || echo "ParseError")
    RECOVERY_ASSIGNMENT_NAME=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/11-deployment-recovery.json')); print(d['properties']['outputs']['roleAssignmentName']['value'])" 2>/dev/null || echo "")
    echo "Recovery provisioningState: ${RECOVERY_PROVISIONING_STATE} (expected: Succeeded)"
    echo "Recovery assignment name (from Bicep output): ${RECOVERY_ASSIGNMENT_NAME} (expected: ${NEW_NAME_VERIFY})"
else
    echo "Recovery deployment failed — first 20 lines of stderr:"
    head -n 20 "$EVIDENCE_DIR/11-deployment-recovery.stderr" || true
fi
echo ""

echo "=== Phase 13: snapshot role assignment list post-recovery (expected: exactly 1 assignment) ==="
echo "Sleeping 15 s for RBAC propagation after recovery deployment..."
sleep 15
az role assignment list \
    --subscription "$AZ_SUBSCRIPTION" \
    --assignee "$SP_APP_ID" \
    --scope "$ACR_ID" \
    --query "[].{name: name, roleDefinitionName: roleDefinitionName, principalType: principalType, scope: scope, createdOn: createdOn}" \
    --output json \
    > "$EVIDENCE_DIR/12-role-assignment-list-post-recovery.json"
cat "$EVIDENCE_DIR/12-role-assignment-list-post-recovery.json"
POST_RECOVERY_COUNT=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/12-role-assignment-list-post-recovery.json'))))")
POST_RECOVERY_ASSIGNMENT_NAME=$(python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/12-role-assignment-list-post-recovery.json')); print(d[0]['name'] if d else '')")
echo "Post-recovery assignment count: ${POST_RECOVERY_COUNT} (expected: 1)"
echo "Post-recovery assignment name: ${POST_RECOVERY_ASSIGNMENT_NAME} (expected: ${NEW_NAME_VERIFY})"
echo ""

echo "=== Phase 14: cardinality re-verify after additional RBAC settle window ==="
echo "Sleeping 15 s for additional RBAC settle..."
sleep 15
az role assignment list \
    --subscription "$AZ_SUBSCRIPTION" \
    --assignee "$SP_APP_ID" \
    --scope "$ACR_ID" \
    --query "[].{name: name, roleDefinitionName: roleDefinitionName, principalType: principalType, scope: scope, createdOn: createdOn}" \
    --output json \
    > "$EVIDENCE_DIR/13-role-assignment-list-cardinality-verify.json"
cat "$EVIDENCE_DIR/13-role-assignment-list-cardinality-verify.json"
CARDINALITY_VERIFY_COUNT=$(python3 -c "import json; print(len(json.load(open('$EVIDENCE_DIR/13-role-assignment-list-cardinality-verify.json'))))")
echo "Cardinality verify count: ${CARDINALITY_VERIFY_COUNT} (expected: 1, must equal post-recovery count)"
echo ""

echo "=== Phase 15: capture metadata + emit H2 gate ==="
az version --output json > "$EVIDENCE_DIR/18-cli-versions.json" 2>&1 || true
az extension list --query "[?name=='containerapp']" --output json > "$EVIDENCE_DIR/19-cli-containerapp-ext.json" 2>&1 || true
az group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --query "{name: name, location: location}" \
    --output json \
    > "$EVIDENCE_DIR/20-region.json" 2>&1 || true
az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs" \
    --output json \
    > "$EVIDENCE_DIR/21-deployment-outputs.json" 2>&1 || true

UTC_CAPTURED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export EVIDENCE_DIR AZ_SUBSCRIPTION RG SP_NAME SP_APP_ID SP_OBJECT_ID ACR_NAME ACR_ID
export INITIAL_ASSIGNMENT_NAME NEW_NAME_VERIFY
export REVERIFY_UTC REVERIFY_EXIT_CODE REVERIFY_HAS_CONFLICT
export DELETE_UTC DELETE_EXIT_CODE
export RECOVERY_UTC RECOVERY_EXIT_CODE RECOVERY_PROVISIONING_STATE RECOVERY_ASSIGNMENT_NAME
export PRE_DELETE_COUNT PRE_DELETE_ASSIGNMENT_NAME POST_RECOVERY_COUNT POST_RECOVERY_ASSIGNMENT_NAME CARDINALITY_VERIFY_COUNT
export UTC_CAPTURED

python3 <<'PYEOF'
import json, os

# H2 sub-gates for cd-reconnect-rbac-conflict recovery:
#
# a_conflict_still_reproduces_at_start_of_verify
#   Phase 9 az deployment exit code != 0 AND stderr contained RoleAssignmentExists.
#   This is the precondition: the H1 conflict must still be there at the start of the
#   recovery experiment. If the assignment was deleted between trigger.sh and verify.sh
#   by some external actor, this sub-gate fails and the recovery experiment is invalid.
# b_delete_succeeded
#   Phase 11 az role assignment delete exit code == 0.
# c_retry_deployment_succeeded
#   Phase 12 az deployment exit code == 0 AND provisioningState == 'Succeeded' AND
#   the Bicep output roleAssignmentName matches the fresh GUID we passed.
# d_final_assignment_count_is_one
#   Phase 13 list returns exactly 1 assignment AND Phase 14 cardinality re-verify also
#   returns exactly 1 (RBAC count is stable, not transient).

reverify_exit_code = int(os.environ['REVERIFY_EXIT_CODE'])
reverify_has_conflict = os.environ['REVERIFY_HAS_CONFLICT'].lower() == 'true'
delete_exit_code = int(os.environ['DELETE_EXIT_CODE'])
recovery_exit_code = int(os.environ['RECOVERY_EXIT_CODE'])
recovery_provisioning_state = os.environ['RECOVERY_PROVISIONING_STATE']
recovery_assignment_name = os.environ['RECOVERY_ASSIGNMENT_NAME']
new_name_verify = os.environ['NEW_NAME_VERIFY']
post_recovery_count = int(os.environ['POST_RECOVERY_COUNT'])
post_recovery_assignment_name = os.environ['POST_RECOVERY_ASSIGNMENT_NAME']
cardinality_verify_count = int(os.environ['CARDINALITY_VERIFY_COUNT'])
pre_delete_count = int(os.environ['PRE_DELETE_COUNT'])
pre_delete_assignment_name = os.environ['PRE_DELETE_ASSIGNMENT_NAME']
initial_assignment_name = os.environ['INITIAL_ASSIGNMENT_NAME']

a_conflict_still_reproduces_at_start_of_verify = (
    reverify_exit_code != 0 and reverify_has_conflict
)
b_delete_succeeded = delete_exit_code == 0
c_retry_deployment_succeeded = (
    recovery_exit_code == 0
    and recovery_provisioning_state == 'Succeeded'
    and recovery_assignment_name == new_name_verify
)
d_final_assignment_count_is_one = (
    post_recovery_count == 1
    and cardinality_verify_count == 1
    and post_recovery_assignment_name == new_name_verify
)

h2_sub_gates = {
    'a_conflict_still_reproduces_at_start_of_verify': a_conflict_still_reproduces_at_start_of_verify,
    'b_delete_succeeded': b_delete_succeeded,
    'c_retry_deployment_succeeded': c_retry_deployment_succeeded,
    'd_final_assignment_count_is_one': d_final_assignment_count_is_one,
}
h2_all_subgates_pass = all(h2_sub_gates.values())

# Classification logic:
#   cd_rbac_recovered_after_delete_retry      - all 4 sub-gates pass (expected here)
#   cd_rbac_did_not_recover                   - c (retry deployment) failed or d (final
#                                               count) failed, which means the documented
#                                               recovery procedure did not work.
#   partial_observation_some_subgates_failed  - everything else (e.g., delete succeeded
#                                               but conflict had already been cleared by
#                                               an external actor before verify started).

if h2_all_subgates_pass:
    gate_classification = 'cd_rbac_recovered_after_delete_retry'
elif not c_retry_deployment_succeeded or not d_final_assignment_count_is_one:
    gate_classification = 'cd_rbac_did_not_recover'
else:
    gate_classification = 'partial_observation_some_subgates_failed'

out = {
    'utc_captured': os.environ['UTC_CAPTURED'],
    'subscription': os.environ['AZ_SUBSCRIPTION'],
    'rg': os.environ['RG'],
    'acr_name': os.environ['ACR_NAME'],
    'acr_id': os.environ['ACR_ID'],
    'sp_name': os.environ['SP_NAME'],
    'sp_app_id': os.environ['SP_APP_ID'],
    'sp_object_id': os.environ['SP_OBJECT_ID'],
    'h1_initial_assignment_name': initial_assignment_name,
    'reverify_window': {
        'start_utc': os.environ['REVERIFY_UTC'],
        'fresh_role_assignment_name': new_name_verify,
        'cli_exit_code': reverify_exit_code,
        'error_contained_role_assignment_exists': reverify_has_conflict,
    },
    'delete_window': {
        'start_utc': os.environ['DELETE_UTC'],
        'deleted_assignment_name': pre_delete_assignment_name,
        'cli_exit_code': delete_exit_code,
    },
    'recovery_window': {
        'start_utc': os.environ['RECOVERY_UTC'],
        'role_assignment_name_passed': new_name_verify,
        'cli_exit_code': recovery_exit_code,
        'provisioning_state': recovery_provisioning_state,
        'role_assignment_name_emitted_by_bicep': recovery_assignment_name,
    },
    'rbac_observations': {
        'pre_delete_count': pre_delete_count,
        'pre_delete_assignment_name': pre_delete_assignment_name,
        'post_recovery_count': post_recovery_count,
        'post_recovery_assignment_name': post_recovery_assignment_name,
        'cardinality_verify_count': cardinality_verify_count,
    },
    'h2_sub_gates': h2_sub_gates,
    'h2_all_subgates_pass': h2_all_subgates_pass,
    'gate_classification': gate_classification,
}

with open(os.path.join(os.environ['EVIDENCE_DIR'], '14-h2-gate.json'), 'w') as f:
    json.dump(out, f, indent=2)
print(json.dumps({
    'gate_classification': out['gate_classification'],
    'h2_all_subgates_pass': out['h2_all_subgates_pass'],
    'h2_sub_gates': out['h2_sub_gates'],
    'baseline_vs_post_recovery_assignment_name': {
        'baseline': initial_assignment_name,
        'post_recovery': post_recovery_assignment_name,
        'changed': initial_assignment_name != post_recovery_assignment_name,
    },
}, indent=2))
PYEOF
echo ""

H2_GATE=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/14-h2-gate.json'))['gate_classification'])")
H2_ALL_SUBGATES_PASS=$(python3 -c "import json; print(json.load(open('$EVIDENCE_DIR/14-h2-gate.json'))['h2_all_subgates_pass'])")

echo "=== Verdict ==="
echo "H1 (trigger.sh): gate=${H1_GATE}, all_subgates_pass=${H1_ALL_SUBGATES_PASS}"
echo "H2 (verify.sh):  gate=${H2_GATE}, all_subgates_pass=${H2_ALL_SUBGATES_PASS}"
echo ""

H1_PASS=false
H2_PASS=false

if [[ "$H1_GATE" == "cd_rbac_conflict_reproduced" && "$H1_ALL_SUBGATES_PASS" == "True" ]]; then
    H1_PASS=true
fi
if [[ "$H2_GATE" == "cd_rbac_recovered_after_delete_retry" && "$H2_ALL_SUBGATES_PASS" == "True" ]]; then
    H2_PASS=true
fi

echo "H1 PASS: $H1_PASS"
echo "H2 PASS: $H2_PASS"

if [[ "$H1_PASS" == "true" && "$H2_PASS" == "true" ]]; then
    echo "VERDICT: SUPPORTED. The RBAC (scope, principal, role) uniqueness constraint is the controlling variable: ARM rejects a second roleAssignments write on the same triple (HTTP 409 RoleAssignmentExists) with a fresh role assignment GUID, and the documented recovery procedure (az role assignment delete + retry the ARM deployment) restores the working state with exactly one active assignment."
    exit 0
fi

if [[ "$H2_GATE" == "cd_rbac_did_not_recover" ]]; then
    echo "VERDICT: H2 FALSIFIED. The recovery procedure (delete conflicting assignment + retry the ARM deployment) did not produce a Succeeded provisioning state OR did not result in exactly one active assignment (gate=${H2_GATE}). Investigate az CLI version, RBAC propagation latency, or whether an external actor modified state between phases."
    exit 2
fi

echo "VERDICT: INVALID RUN. Unexpected combination of H1 gate=${H1_GATE} and H2 gate=${H2_GATE}. Inspect evidence files."
exit 1
