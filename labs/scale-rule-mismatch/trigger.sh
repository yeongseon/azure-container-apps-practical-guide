#!/usr/bin/env bash
set -euo pipefail

ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RG" --query "loginServer" --output tsv)
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query "username" --output tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" --output tsv)

az acr build --registry "$ACR_NAME" --image "${APP_NAME}:v1" ./workload

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "${ACR_LOGIN_SERVER}/${APP_NAME}:v1" \
  --registry-server "$ACR_LOGIN_SERVER" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --min-replicas 1 \
  --max-replicas 2 \
  --scale-rule-name "http-rule" \
  --scale-rule-type "http" \
  --scale-rule-metadata "concurrentRequests=500"

FQDN=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress.fqdn" --output tsv)
URL="https://${FQDN}/load"

if command -v hey >/dev/null 2>&1; then
  hey -z 45s -c 80 "$URL"
else
  for _ in $(seq 1 300); do
    curl --silent "$URL" > /dev/null &
  done
  wait
fi

sleep 15
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --output table
