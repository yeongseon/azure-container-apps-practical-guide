#!/usr/bin/env bash
set -euo pipefail

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

CLEANUP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "cleanup.sh starting at ${CLEANUP_UTC}"
echo "Subscription: ${AZ_SUBSCRIPTION}"
echo "RG: ${RG}"
echo ""

echo "==> Pre-cleanup resource inventory (snapshot before async delete)"
az resource list \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --query "[].{name: name, type: type, location: location}" \
    --output json \
    > "$EVIDENCE_DIR/23-pre-cleanup-resources.json" 2>&1 || true
cat "$EVIDENCE_DIR/23-pre-cleanup-resources.json" || true
echo ""

echo "==> Deleting resource group $RG (async)"
{
    echo "cleanup_utc=${CLEANUP_UTC}"
    echo "subscription=${AZ_SUBSCRIPTION}"
    echo "resource_group=${RG}"
    echo ""
    echo "command: az group delete --subscription \$AZ_SUBSCRIPTION --name \$RG --yes --no-wait"
    echo ""
} > "$EVIDENCE_DIR/24-cleanup-output.txt"

set +e
az group delete \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --yes \
    --no-wait \
    >> "$EVIDENCE_DIR/24-cleanup-output.txt" 2>&1
DELETE_EXIT_CODE=$?
set -e
echo "Delete command exit code: ${DELETE_EXIT_CODE} (expected: 0; deletion is async and completes in background)"
echo "delete_exit_code=${DELETE_EXIT_CODE}" >> "$EVIDENCE_DIR/24-cleanup-output.txt"
echo ""

cat "$EVIDENCE_DIR/24-cleanup-output.txt"
echo ""

echo "==> Resource group $RG deletion initiated (async). Verify completion later with:"
echo "    az group show --subscription \"$AZ_SUBSCRIPTION\" --name \"$RG\""
echo "    (Returns 'ResourceGroupNotFound' when delete completes.)"
