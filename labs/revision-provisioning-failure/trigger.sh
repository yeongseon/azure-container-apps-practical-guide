#!/usr/bin/env bash
set -euo pipefail

echo "Triggering revision failure by forcing a new revision..."
echo "Note: The helloworld image doesn't have custom probes, so we trigger a simple env var change"
echo "to demonstrate revision rollout and recovery patterns."

az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --set-env-vars "TRIGGER_TIMESTAMP=$(date +%s)"

echo ""
echo "Waiting for revision update..."
sleep 10

echo ""
echo "Checking revision status..."
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table

echo ""
echo "Checking system logs..."
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system --tail 20 2>/dev/null || echo "Logs may take a moment to appear"
