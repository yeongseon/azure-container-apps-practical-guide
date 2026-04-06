#!/bin/bash
set -euo pipefail

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --dapr-app-port 8081

echo "Changed Dapr appPort to 8081 to break service invocation."
echo "Re-run verify.sh after restoring the correct appPort."
