#!/bin/bash
set -euo pipefail

DAPR_CONFIG=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.dapr" \
  --output json)

echo "$DAPR_CONFIG"

EXPECTED_APP_PORT=$(echo "$DAPR_CONFIG" | python -c 'import json,sys; print(json.load(sys.stdin).get("appPort"))')

if [ "$EXPECTED_APP_PORT" != "8000" ]; then
  echo "FAIL: Dapr appPort is '$EXPECTED_APP_PORT'; expected 8000"
  exit 1
fi

az containerapp exec \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --command "curl --silent --show-error --fail http://127.0.0.1:3500/v1.0/healthz"

echo "PASS: Dapr is enabled, appPort is correct, and the health endpoint responded successfully."
