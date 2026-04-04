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
  --target-port 8000 \
  --registry-server "$ACR_LOGIN_SERVER" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD"

echo "Waiting for healthy v1 revision..."
sleep 40

echo "Deploying intentionally broken v2 by changing ingress target port to 9999..."
az containerapp update --name "$APP_NAME" --resource-group "$RG" --target-port 9999
sleep 40

az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system --tail 20
