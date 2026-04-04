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
  --registry-password "$ACR_PASSWORD"

echo "Waiting for app startup with missing Key Vault RBAC..."
sleep 40

FQDN=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress.fqdn" --output tsv)
curl --silent --show-error --fail "https://${FQDN}/health" || true
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system --tail 20
