#!/bin/bash
set -e

echo "Introducing an ingress misconfiguration by setting the target port to 8081..."
az containerapp ingress update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --target-port 8081

echo "Misconfiguration applied."
echo "Changed: ingress target port now points to 8081 instead of the app's listening port (80)."
echo "This should make the external endpoint unreachable until the target port is fixed back to 80."

az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress" \
  --output table
