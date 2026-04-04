#!/usr/bin/env bash
set -euo pipefail

FQDN=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress.fqdn" --output tsv)
HTTP_CODE=$(curl --silent --output /tmp/aca-kv-lab.out --write-out "%{http_code}" "https://${FQDN}/health" || true)

if [ "$HTTP_CODE" = "200" ]; then
  echo "FAIL: App returned 200 before RBAC fix"
  exit 1
fi

echo "PASS: App returned HTTP $HTTP_CODE before RBAC fix"

APP_PRINCIPAL_ID=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "identity.principalId" --output tsv)
KV_ID=$(az keyvault show --name "$KV_NAME" --resource-group "$RG" --query "id" --output tsv)

az role assignment create \
  --assignee-object-id "$APP_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "$KV_ID"

az containerapp update --name "$APP_NAME" --resource-group "$RG" --set-env-vars "RESTART_TOKEN=$(date +%s)"
echo "Waiting for role propagation and new revision startup..."
sleep 60

HTTP_CODE=$(curl --silent --output /tmp/aca-kv-lab-fixed.out --write-out "%{http_code}" "https://${FQDN}/health" || true)
if [ "$HTTP_CODE" = "200" ]; then
  echo "PASS: App returned 200 after RBAC fix"
else
  echo "FAIL: App still failing after RBAC fix with HTTP $HTTP_CODE"
  exit 1
fi
