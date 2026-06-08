#!/usr/bin/env bash
# Deploy the zone-redundancy-best-effort lab infrastructure.
#
# Creates the resource group (if missing), deploys the Bicep template,
# and prints the outputs needed by trigger.sh / verify.sh.
#
# Usage:
#   export RG="rg-aca-zr-lab"
#   export LOCATION="koreacentral"   # any region with workload-profile + AZs
#   ./deploy.sh
#
# Optional overrides:
#   export BASE_NAME="zrlab"
#   export EXPIRY_HOURS=48

set -euo pipefail

RG="${RG:-rg-aca-zr-lab}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-zrlab}"
EXPIRY_HOURS="${EXPIRY_HOURS:-48}"

echo ">> Deploying zone-redundancy-best-effort lab"
echo "   Resource group : $RG"
echo "   Location       : $LOCATION"
echo "   Base name      : $BASE_NAME"
echo "   Expiry hours   : $EXPIRY_HOURS"
echo

if ! az group show --name "$RG" --output none 2>/dev/null; then
  echo ">> Creating resource group $RG"
  az group create --name "$RG" --location "$LOCATION" --output none
fi

DEPLOYMENT_NAME="zrlab-$(date -u +%Y%m%d%H%M%S)"

echo ">> Submitting deployment $DEPLOYMENT_NAME"
az deployment group create \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file ./infra/main.bicep \
  --parameters ./infra/main.parameters.json \
  --parameters baseName="$BASE_NAME" expiryHours="$EXPIRY_HOURS" \
  --output none

echo ">> Deployment complete. Outputs:"
az deployment group show \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --query 'properties.outputs' \
  --output json

cat <<'EOF'

Next steps:
  1. (Optional) Build the audit image:
       cd audit && docker build -t <acr-or-local-tag> . && docker push <acr-or-local-tag>
     Then redeploy with --parameters auditImage=<that-tag>.

  2. Verify the deployment:
       ./verify.sh

  3. Start collecting placement samples (wait at least one cron tick, ~5 min).

  4. When ready to perturb:
       ./trigger.sh --client no-retry
       ./trigger.sh --client retry-backoff

  5. When done, clean up:
       ./cleanup.sh
EOF
