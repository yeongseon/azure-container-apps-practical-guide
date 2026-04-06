#!/usr/bin/env bash
set -euo pipefail

echo "Triggering revision failure by adding a startup probe to a non-existent path..."

az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --set-env-vars "PROBE_TRIGGER=$(date +%s)" \
    --container-name app \
    --startup-probe-path "/nonexistent-health-endpoint" \
    --startup-probe-port 80 \
    --startup-probe-failure-threshold 3 \
    --startup-probe-period-seconds 5

echo ""
echo "Waiting for revision update..."
sleep 30

echo ""
echo "Checking revision status..."
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table

echo ""
echo "Checking system logs for probe failures..."
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system --tail 30 2>/dev/null || echo "Logs may take a moment to appear"
