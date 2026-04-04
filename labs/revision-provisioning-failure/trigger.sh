#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for failed revision due to missing secret reference..."
sleep 30
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system --tail 20
