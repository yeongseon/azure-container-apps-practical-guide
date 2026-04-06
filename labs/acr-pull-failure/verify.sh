#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[0].properties.healthState" --output tsv)
if [ "$HEALTH" != "Healthy" ]; then
  echo "PASS: Revision health is '$HEALTH' (expected non-Healthy)"
else
  echo "FAIL: Revision is Healthy — failure was not reproduced"
  exit 1
fi

az acr build --registry "$ACR_NAME" --image "labacr:v1" "${SCRIPT_DIR}/workload"
az containerapp update --name "$APP_NAME" --resource-group "$RG" --image "${ACR_NAME}.azurecr.io/labacr:v1"
sleep 30

HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[0].properties.healthState" --output tsv)
echo "After fix: Revision health is '$HEALTH'"

if [ "$HEALTH" = "Healthy" ]; then
    echo "PASS: Recovery successful"
else
    echo "FAIL: Recovery unsuccessful"
    exit 1
fi
