#!/usr/bin/env bash
set -euo pipefail

HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([].{created:properties.createdTime,health:properties.healthState}, &created)[-1].health" --output tsv)

if [ "$HEALTH" = "Healthy" ]; then
  echo "FAIL: Revision is Healthy; expected Failed due to missing secret"
  exit 1
fi

echo "PASS: Revision health is '$HEALTH' due to missing secret"

az containerapp secret set --name "$APP_NAME" --resource-group "$RG" --secrets "missing-secret=resolved-value"
az containerapp update --name "$APP_NAME" --resource-group "$RG" --set-env-vars "REVISION_FIX_TOKEN=$(date +%s)"
sleep 40

POST_FIX_HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([].{created:properties.createdTime,health:properties.healthState}, &created)[-1].health" --output tsv)
echo "After fix: Revision health is '$POST_FIX_HEALTH'"
