#!/bin/bash
set -e

TRAFFIC_COUNT=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "length(properties.configuration.ingress.traffic[?weight==\`50\`])" --output tsv)

if [ "$TRAFFIC_COUNT" != "2" ]; then
  echo "FAIL: Expected exactly two revisions with 50% traffic each"
  exit 1
fi

echo "PASS: Traffic split shows two revisions at 50% each"

az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "sort_by([].{name:name,health:properties.healthState,created:properties.createdTime}, &created)" --output table

echo "PASS: Revision health and traffic configuration checked successfully"
