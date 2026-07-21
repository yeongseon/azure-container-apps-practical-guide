#!/usr/bin/env bash
set -euo pipefail
: "${RG:?RG (resource group) must be set}"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="$LAB_DIR/evidence"

if [[ -f "$EVIDENCE_DIR/06-h1-routing-intent-enabled.json" ]]; then
    VHUB_RG="$(jq -r '.virtual_hub_resource_group // empty' "$EVIDENCE_DIR/06-h1-routing-intent-enabled.json")"
    VHUB_NAME="$(jq -r '.virtual_hub_name // empty' "$EVIDENCE_DIR/06-h1-routing-intent-enabled.json")"
    ROUTING_INTENT_NAME="$(jq -r '.routing_intent_name // empty' "$EVIDENCE_DIR/06-h1-routing-intent-enabled.json")"
    CONNECTION_NAME="$(jq -r '.aca_vnet_connection_name // empty' "$EVIDENCE_DIR/06-h1-routing-intent-enabled.json")"

    if [[ -n "$VHUB_RG" && -n "$VHUB_NAME" && -n "$ROUTING_INTENT_NAME" ]]; then
        if az network vhub routing-intent show --name "$ROUTING_INTENT_NAME" --resource-group "$VHUB_RG" --vhub "$VHUB_NAME" --output none 2>/dev/null; then
            echo "[cleanup] deleting lab Routing Intent ${ROUTING_INTENT_NAME} from ${VHUB_NAME}"
            az network vhub routing-intent delete --name "$ROUTING_INTENT_NAME" --resource-group "$VHUB_RG" --vhub "$VHUB_NAME" --yes --output none
        fi
    fi

    if [[ -n "$VHUB_RG" && -n "$VHUB_NAME" && -n "$CONNECTION_NAME" ]]; then
        if az network vhub connection show --name "$CONNECTION_NAME" --resource-group "$VHUB_RG" --vhub-name "$VHUB_NAME" --output none 2>/dev/null; then
            echo "[cleanup] deleting lab HubVirtualNetworkConnection ${CONNECTION_NAME} from ${VHUB_NAME}"
            az network vhub connection delete --name "$CONNECTION_NAME" --resource-group "$VHUB_RG" --vhub-name "$VHUB_NAME" --yes --output none
        fi
    fi
fi

echo "[cleanup] deleting resource group ${RG} (async)"
az group delete --name "$RG" --yes --no-wait
echo "[cleanup] requested. Verify with: az group show --name $RG --output none"
echo "[cleanup] lab variant: aca-secret-kv-ref-mi-network-path-h4d"
echo "[cleanup] Synthetic secured-hub mode is expensive. Existing secured-hub mode deletes the lab-created Routing Intent and HubVirtualNetworkConnection when evidence/06 is available, then deletes only the lab resource group."
