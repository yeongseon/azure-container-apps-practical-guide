#!/usr/bin/env bash
set -euo pipefail

FQDN=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress.fqdn" --output tsv)
URL="https://${FQDN}/load"

if command -v hey >/dev/null 2>&1; then
  hey -z 30s -c 60 "$URL"
else
  for _ in $(seq 1 250); do
    curl --silent "$URL" > /dev/null &
  done
  wait
fi

sleep 15
REPLICAS_BEFORE=$(az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --query "length(@)" --output tsv)

if [ "$REPLICAS_BEFORE" -le 1 ]; then
  echo "PASS: Replica count stayed at $REPLICAS_BEFORE with mismatched threshold"
else
  echo "FAIL: Replica count unexpectedly scaled to $REPLICAS_BEFORE before fix"
  exit 1
fi

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --min-replicas 1 \
  --max-replicas 10 \
  --scale-rule-name "http-rule" \
  --scale-rule-type "http" \
  --scale-rule-metadata "concurrentRequests=10"

if command -v hey >/dev/null 2>&1; then
  hey -z 45s -c 80 "$URL"
else
  for _ in $(seq 1 400); do
    curl --silent "$URL" > /dev/null &
  done
  wait
fi

sleep 20
REPLICAS_AFTER=$(az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --query "length(@)" --output tsv)

if [ "$REPLICAS_AFTER" -gt 1 ]; then
  echo "PASS: Replica count increased to $REPLICAS_AFTER after scale rule fix"
else
  echo "FAIL: Replica count is still $REPLICAS_AFTER after fix"
  exit 1
fi
