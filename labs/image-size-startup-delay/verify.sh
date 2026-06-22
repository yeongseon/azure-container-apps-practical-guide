#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set}"
: "${APP_NAME:?APP_NAME must be set}"
SMALL_IMAGE="${SMALL_IMAGE:-python:3.11-alpine}"

EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

echo "==> Capturing system logs from the LARGE image revision before applying the fix..."
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type system \
  --tail 100 \
  --output json \
  > "$EVIDENCE_DIR/system-logs-large.json"

INITIAL_REVISION=$(az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "[0].name" \
  --output tsv)
echo "    captured logs for revision: $INITIAL_REVISION"

echo ""
echo "==> Applying the documented fix: switch to a smaller image."
echo "    Old image: $(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query 'properties.template.containers[0].image' -o tsv)"
echo "    New image: $SMALL_IMAGE"
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$SMALL_IMAGE" \
  --output none

echo ""
echo "==> Waiting up to 3 minutes for the small image revision to become ready..."
for i in {1..18}; do
  LATEST=$(az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "[?properties.active] | [0]" \
    --output json)
  HEALTH=$(echo "$LATEST" | jq -r '.properties.healthState')
  STATE=$(echo "$LATEST" | jq -r '.properties.provisioningState')
  printf "  [%02d/18] healthState=%s provisioningState=%s\n" "$i" "$HEALTH" "$STATE"
  if [ "$HEALTH" = "Healthy" ] && [ "$STATE" = "Provisioned" ]; then
    break
  fi
  sleep 10
done

echo ""
echo "==> Capturing system logs from the SMALL image revision after the fix..."
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type system \
  --tail 100 \
  --output json \
  > "$EVIDENCE_DIR/system-logs-small.json"

echo ""
echo "==> Comparing image pull times from system logs..."
echo ""
echo "LARGE image evidence (from $EVIDENCE_DIR/system-logs-large.json):"
grep "Successfully pulled image" "$EVIDENCE_DIR/system-logs-large.json" \
  | jq -r '.Msg' 2>/dev/null \
  | head -5 \
  || echo "  (no 'Successfully pulled image' line found in logs; check raw JSON)"

echo ""
echo "SMALL image evidence (from $EVIDENCE_DIR/system-logs-small.json):"
grep "Successfully pulled image" "$EVIDENCE_DIR/system-logs-small.json" \
  | jq -r '.Msg' 2>/dev/null \
  | head -5 \
  || echo "  (no 'Successfully pulled image' line found in logs; check raw JSON)"

echo ""
echo "==> Recovery check:"
HEALTH=$(az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "[?properties.active] | [0].properties.healthState" \
  --output tsv)
if [ "$HEALTH" = "Healthy" ]; then
  echo "PASS: After switching to the small image, the active revision is Healthy."
else
  echo "FAIL: Active revision is '$HEALTH' (expected Healthy)."
  exit 1
fi

echo ""
echo "Evidence written to $EVIDENCE_DIR/"
