#!/bin/bash
set -e

az group delete \
  --name "$RG" \
  --yes \
  --no-wait

echo "Cleanup initiated for resource group $RG."
