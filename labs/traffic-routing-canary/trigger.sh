#!/bin/bash
set -e

GOOD_REVISION=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([].{name:name,created:properties.createdTime}, &created)[-1].name" --output tsv)

echo "Creating a bad revision by breaking the ingress target port..."
az containerapp update --name "$APP_NAME" --resource-group "$RG" --target-port 9999
sleep 40

BAD_REVISION=$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([].{name:name,created:properties.createdTime}, &created)[-1].name" --output tsv)

az containerapp ingress traffic set --name "$APP_NAME" --resource-group "$RG" --revision-weight "${GOOD_REVISION}=50" "${BAD_REVISION}=50"

echo "Triggered canary failure scenario."
echo "- Good revision: $GOOD_REVISION"
echo "- Bad revision: $BAD_REVISION"
echo "- Traffic split: 50% / 50%"
echo "The bad revision uses target port 9999, so requests should fail while traffic is split."
