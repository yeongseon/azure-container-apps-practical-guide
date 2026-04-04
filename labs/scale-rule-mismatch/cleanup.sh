#!/usr/bin/env bash
set -euo pipefail

echo "Deleting resource group $RG..."
az group delete --name "$RG" --yes --no-wait
echo "Cleanup initiated (async)."
