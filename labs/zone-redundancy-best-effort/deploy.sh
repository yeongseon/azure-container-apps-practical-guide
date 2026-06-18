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
  1. (Optional) Build the audit image and redeploy to enable real
     ReplicaInventorySample events (otherwise the placeholder Job
     just emits a single notice JSON):
       export ACR="<your-acr>.azurecr.io"
       az acr build --registry "$(basename "$ACR" .azurecr.io)" \
         --image "zr-lab/audit:latest" ./audit
       az deployment group create \
         --resource-group "$RG" --template-file ./infra/main.bicep \
         --parameters ./infra/main.parameters.json \
         --parameters auditImage="${ACR}/zr-lab/audit:latest" \
         --parameters auditAcrName="$(basename "$ACR" .azurecr.io)"
     The Bicep looks up the ACR as an existing resource in the current
     resource group, so the ACR must live in $RG. Without auditAcrName
     the Job has no AcrPull role assignment and the first image pull
     fails with 401 Unauthorized.

  2. (Optional) Build the custom subject-app image and redeploy to
     populate AppRequests for KQL pack Q5 and capture C9. See
     labs/zone-redundancy-best-effort/apps/README.md for the full
     az acr build + az deployment group create flow (including the
     required appAcrName parameter for private ACR images).

  3. Verify the deployment:
       ./verify.sh

  4. Start collecting placement samples (wait at least one cron tick, ~5 min).

  5. When ready to perturb:
       ./trigger.sh --combined --client no-retry --duration 180 --app app-min3
       ./trigger.sh --combined --client retry-backoff --duration 180 --app app-min3

  6. When done, clean up:
       ./cleanup.sh
EOF
