#!/bin/bash
set -euo pipefail

if [ -z "${DAPR_APP_ID:-}" ]; then
  DAPR_APP_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query 'properties.configuration.dapr.appId' --output tsv)"
fi

az containerapp dapr enable \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --dapr-app-id "$DAPR_APP_ID" \
  --dapr-app-port 8081 \
  --dapr-app-protocol http

echo "Changed Dapr appPort to 8081 to break service invocation."
echo "Re-run verify.sh after restoring the correct appPort."
