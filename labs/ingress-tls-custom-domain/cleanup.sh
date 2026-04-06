#!/bin/bash
set -e

echo "Deleting resource group $RG..."
az group delete --name "$RG" --yes --no-wait
echo "Cleanup initiated."
