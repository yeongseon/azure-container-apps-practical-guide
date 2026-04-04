#!/usr/bin/env bash
set -euo pipefail

HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[0].properties.healthState" --output tsv)
if [ "$HEALTH" != "Healthy" ]; then
  echo "PASS: Revision health is '$HEALTH' (expected non-Healthy)"
else
  echo "FAIL: Revision is Healthy — failure was not reproduced"
  exit 1
fi

az acr build --registry "$ACR_NAME" --image "${APP_NAME}:v1" ./workload
az containerapp update --name "$APP_NAME" --resource-group "$RG" --image "${ACR_NAME}.azurecr.io/${APP_NAME}:v1"
sleep 30

HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[0].properties.healthState" --output tsv)
echo "After fix: Revision health is '$HEALTH'"
