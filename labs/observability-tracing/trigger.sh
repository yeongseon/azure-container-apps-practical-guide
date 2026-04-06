#!/bin/bash
set -e

az containerapp update \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://invalid/"

echo "Telemetry settings were misconfigured on $APP_NAME."
echo "The application should now stop sending Application Insights traces until the connection string is restored."
