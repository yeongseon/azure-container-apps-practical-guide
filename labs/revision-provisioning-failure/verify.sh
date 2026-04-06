#!/usr/bin/env bash
set -euo pipefail

echo "Checking current revision health..."
HEALTH=$(az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "sort_by([].{created:properties.createdTime,health:properties.healthState}, &created)[-1].health" \
    --output tsv)

echo "Current revision health: $HEALTH"

if [ "$HEALTH" = "Healthy" ]; then
    echo "PASS: Latest revision is Healthy"
else
    echo "INFO: Latest revision is '$HEALTH' - removing bad startup probe..."
    
    # Get the latest revision name to check its configuration
    LATEST_REVISION=$(az containerapp revision list \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --query "sort_by([].{created:properties.createdTime,name:name}, &created)[-1].name" \
        --output tsv)
    
    echo "Latest revision: $LATEST_REVISION"
    
    # Create a new revision without the startup probe by updating without probe flags
    # This effectively removes the startup probe configuration
    az containerapp update \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --set-env-vars "PROBE_FIX=$(date +%s)" \
        --container-name app \
        --startup-probe-disabled
    
    echo "Waiting for new revision to stabilize..."
    sleep 30
    
    POST_FIX_HEALTH=$(az containerapp revision list \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --query "sort_by([].{created:properties.createdTime,health:properties.healthState}, &created)[-1].health" \
        --output tsv)
    
    echo "After fix: Revision health is '$POST_FIX_HEALTH'"
    
    if [ "$POST_FIX_HEALTH" = "Healthy" ]; then
        echo "PASS: Recovery successful - startup probe removed"
    else
        echo "FAIL: Recovery unsuccessful"
        exit 1
    fi
fi
