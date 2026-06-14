#!/usr/bin/env bash
# Deploy the replica-node-spread lab infrastructure.
#
# Creates the resource group (if missing), provisions (or reuses) an ACR
# named ${BASE_NAME}acr${SUFFIX}, builds the diag image into that ACR,
# then deploys the Bicep template wired to the freshly built image. The
# script is idempotent: re-running it rebuilds the diag image and pushes
# a fresh ARM deployment that re-points both apps at the new tag.
#
# Usage:
#   export RG="rg-aca-rns-lab"
#   export LOCATION="koreacentral"   # must support workload profiles
#   ./deploy.sh
#
# Optional overrides:
#   export BASE_NAME="rnslab"
#   export EXPIRY_HOURS=24
#   export ACR_NAME="myexistingacr"   # bring your own ACR
#   export SKIP_IMAGE_BUILD=1         # reuse the existing image tag
#
# REQUIRED env (defensive subscription guard):
#   SUBSCRIPTION_ID  Exact Azure subscription ID this lab targets.
#                    The script fails fast if `az account show` does not
#                    match. This prevents the failure mode where the
#                    operator's active subscription drifts from the lab
#                    record (e.g. left over from another project) and the
#                    deployment lands in the wrong account.

set -euo pipefail

# Defensive guard: prevent accidental cross-subscription deployment.
# All downstream az commands run against whatever subscription is active;
# this check fails fast if the operator's SUBSCRIPTION_ID does not match.
: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID must be exported (e.g. source /tmp/rns-lab.env)}"
ACTIVE_SUB=$(az account show --query id --output tsv 2>/dev/null || true)
if [[ "$ACTIVE_SUB" != "$SUBSCRIPTION_ID" ]]; then
  echo "ERROR: az active subscription mismatch" >&2
  echo "  expected: $SUBSCRIPTION_ID" >&2
  echo "  active  : $ACTIVE_SUB" >&2
  echo "  fix     : az account set --subscription $SUBSCRIPTION_ID" >&2
  exit 1
fi

RG="${RG:-rg-aca-rns-lab}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-rnslab}"
EXPIRY_HOURS="${EXPIRY_HOURS:-24}"
DIAG_IMAGE_REPO="rns-lab/diag"
DIAG_IMAGE_TAG="latest"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ">> Deploying replica-node-spread lab"
echo "   Resource group : $RG"
echo "   Location       : $LOCATION"
echo "   Base name      : $BASE_NAME"
echo "   Expiry hours   : $EXPIRY_HOURS"
echo

if ! az group show --name "$RG" --output none 2>/dev/null; then
  echo ">> Creating resource group $RG"
  az group create --name "$RG" --location "$LOCATION" \
    --tags lab=replica-node-spread managedBy=bicep \
    --output none
fi

# ---------------------------------------------------------------------
# ACR — provision if not supplied, then build the diag image into it.
# ---------------------------------------------------------------------
if [[ -z "${ACR_NAME:-}" ]]; then
  # ACR names must be globally unique, 5-50 lowercase alphanumerics. Derive
  # a deterministic suffix from the RG id so repeat runs converge on the
  # same name and we do not leak ACRs across re-deploys.
  SUFFIX=$(az group show --name "$RG" --query id --output tsv \
    | shasum | awk '{print substr($1,1,6)}')
  ACR_NAME="${BASE_NAME}acr${SUFFIX}"
fi
echo ">> ACR name      : $ACR_NAME"

if ! az acr show --resource-group "$RG" --name "$ACR_NAME" --output none 2>/dev/null; then
  echo ">> Creating ACR $ACR_NAME (Basic SKU, admin disabled)"
  az acr create --resource-group "$RG" --name "$ACR_NAME" \
    --sku Basic --admin-enabled false \
    --tags lab=replica-node-spread \
    --output none
fi

if [[ "${SKIP_IMAGE_BUILD:-}" != "1" ]]; then
  echo ">> Building diag image ${ACR_NAME}.azurecr.io/${DIAG_IMAGE_REPO}:${DIAG_IMAGE_TAG}"
  az acr build --registry "$ACR_NAME" \
    --image "${DIAG_IMAGE_REPO}:${DIAG_IMAGE_TAG}" \
    ./diag \
    --output none
else
  echo ">> SKIP_IMAGE_BUILD=1 — reusing existing image tag"
fi

DIAG_IMAGE="${ACR_NAME}.azurecr.io/${DIAG_IMAGE_REPO}:${DIAG_IMAGE_TAG}"

# ---------------------------------------------------------------------
# Bicep deployment — passes diagAcrName so the template grants AcrPull
# to the UAMI and wires both apps' registries block.
# ---------------------------------------------------------------------
DEPLOYMENT_NAME="rnslab-$(date -u +%Y%m%d%H%M%S)"

echo ">> Submitting deployment $DEPLOYMENT_NAME"
az deployment group create \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file ./infra/main.bicep \
  --parameters ./infra/main.parameters.json \
  --parameters baseName="$BASE_NAME" expiryHours="$EXPIRY_HOURS" \
               diagAcrName="$ACR_NAME" diagImage="$DIAG_IMAGE" \
  --output none

echo ">> Deployment complete. Outputs:"
az deployment group show \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --query 'properties.outputs' \
  --output json

cat <<EOF

Next steps:
  1. Verify the deployment:
       ./verify.sh

  2. Run the H3 falsification check (MUST pass before H1/H2 analysis):
       ./falsify.sh

  3. Run the full experiment (~40-70 minutes, repeats top scale 3x per profile):
       ./trigger.sh

  4. Analyze evidence:
       python3 ./analyze.py

  5. When done:
       ./cleanup.sh
EOF
