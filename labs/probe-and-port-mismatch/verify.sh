#!/usr/bin/env bash
set -euo pipefail

HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([].{created:properties.createdTime,health:properties.healthState}, &created)[-1].health" --output tsv)

if [ "$HEALTH" = "Healthy" ]; then
  echo "FAIL: Revision is Healthy; expected unhealthy due to port mismatch"
  exit 1
fi

echo "PASS: Revision health is '$HEALTH' with mismatched target port"

az containerapp update --name "$APP_NAME" --resource-group "$RG" --target-port 3000
sleep 40

FIXED_HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([].{created:properties.createdTime,health:properties.healthState}, &created)[-1].health" --output tsv)
echo "After fix: Revision health is '$FIXED_HEALTH'"
