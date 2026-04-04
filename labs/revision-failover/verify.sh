#!/usr/bin/env bash
set -euo pipefail

LATEST_HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([].{name:name,created:properties.createdTime,health:properties.healthState}, &created)[-1].health" --output tsv)

if [ "$LATEST_HEALTH" = "Healthy" ]; then
  echo "FAIL: Latest revision is Healthy; expected unhealthy revision after trigger"
  exit 1
fi

echo "PASS: Latest revision health is '$LATEST_HEALTH'"

HEALTHY_REVISION=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([?properties.healthState=='Healthy'].{name:name,created:properties.createdTime}, &created)[-1].name" --output tsv)

if [ -z "$HEALTHY_REVISION" ] || [ "$HEALTHY_REVISION" = "null" ]; then
  echo "FAIL: Could not find a healthy revision to roll back to"
  exit 1
fi

az containerapp ingress traffic set --name "$APP_NAME" --resource-group "$RG" --revision-weight "${HEALTHY_REVISION}=100"
az containerapp update --name "$APP_NAME" --resource-group "$RG" --target-port 8000
sleep 40

POST_FIX_HEALTH=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([].{name:name,created:properties.createdTime,health:properties.healthState}, &created)[-1].health" --output tsv)

echo "Healthy revision used for rollback: $HEALTHY_REVISION"
echo "After rollback/fix, latest revision health is '$POST_FIX_HEALTH'"
