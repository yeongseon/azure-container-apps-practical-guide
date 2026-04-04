#!/usr/bin/env bash
set -euo pipefail

echo "Waiting 30s for revision to attempt image pull..."
sleep 30
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system --tail 20
echo "Check for ImagePullBackOff or manifest errors above."
