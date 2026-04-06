#!/bin/bash
set -e

INGRESS_EXTERNAL=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.external" \
  --output tsv)

TARGET_PORT=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.targetPort" \
  --output tsv)

FQDN=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv)

echo "Ingress external: $INGRESS_EXTERNAL"
echo "Ingress target port: $TARGET_PORT"
echo "FQDN: $FQDN"

if [ "$INGRESS_EXTERNAL" != "true" ] || [ "$TARGET_PORT" != "8000" ]; then
  echo "FAIL: Ingress is not correctly configured. Expected external=true and targetPort=8000."
  exit 1
fi

if curl --silent --show-error --fail "https://${FQDN}" >/dev/null; then
  echo "PASS: Endpoint is reachable with a valid HTTPS response."
else
  echo "FAIL: Endpoint is not reachable over HTTPS."
  exit 1
fi
