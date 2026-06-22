#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set}"
: "${APP_NAME:?APP_NAME must be set}"

echo "==> Waiting up to 5 minutes for the large image to pull and the revision to become ready..."
for i in {1..30}; do
  HEALTH=$(az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "[0].properties.healthState" \
    --output tsv 2>/dev/null || echo "Unknown")
  STATE=$(az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "[0].properties.provisioningState" \
    --output tsv 2>/dev/null || echo "Unknown")
  printf "  [%02d/30] healthState=%s provisioningState=%s\n" "$i" "$HEALTH" "$STATE"
  if [ "$HEALTH" = "Healthy" ] && [ "$STATE" = "Provisioned" ]; then
    break
  fi
  sleep 10
done

echo ""
echo "==> Initial revision state:"
az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table

echo ""
echo "==> System logs for the initial (large image) revision — look for 'Successfully pulled image':"
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type system \
  --tail 50 \
  --output table

echo ""
echo "==> Use verify.sh to update to a smaller image and compare pull timings."
