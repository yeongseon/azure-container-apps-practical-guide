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
    echo "INFO: Latest revision is '$HEALTH' - attempting fix..."
    
    az containerapp update \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --set-env-vars "PROBE_FIX=$(date +%s)"
    
    echo "Waiting for new revision..."
    sleep 30
    
    POST_FIX_HEALTH=$(az containerapp revision list \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --query "sort_by([].{created:properties.createdTime,health:properties.healthState}, &created)[-1].health" \
        --output tsv)
    
    echo "After fix: Revision health is '$POST_FIX_HEALTH'"
    
    if [ "$POST_FIX_HEALTH" = "Healthy" ]; then
        echo "PASS: Recovery successful"
    else
        echo "FAIL: Recovery unsuccessful"
        exit 1
    fi
fi
