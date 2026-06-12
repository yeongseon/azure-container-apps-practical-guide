#!/usr/bin/env bash
# Deploy the startup-degraded-transient-failure lab infrastructure (Stage B).
#
# Creates the resource group (if missing), deploys the Bicep template,
# and prints the outputs needed by trigger.sh / verify.sh.
#
# Usage:
#   export RG="rg-aca-startup-degraded"
#   export LOCATION="koreacentral"
#   export ACR_NAME="<your-acr-without-azurecrio>"  # optional but recommended
#   ./deploy.sh
#
# Optional overrides:
#   export BASE_NAME="sdlab"
#   export EXPIRY_HOURS=48
#   export SUBJECT_STARTUP_DELAY_SECONDS=25
#   export SUBJECT_REQUEST_DELAY_MS=0
#   export SUBJECT_IMAGE="<your-acr>.azurecr.io/startup-degraded/subject:latest"
#   export AUDIT_IMAGE="<your-acr>.azurecr.io/startup-degraded/audit:latest"
#   export PERTURBATION_SAMPLER_IMAGE="<your-acr>.azurecr.io/startup-degraded/perturbation-sampler:latest"
#   export LOADGEN_IMAGE="<your-acr>.azurecr.io/startup-degraded/loadgen:latest"

set -euo pipefail

RG="${RG:-rg-aca-startup-degraded}"
LOCATION="${LOCATION:-koreacentral}"
BASE_NAME="${BASE_NAME:-sdlab}"
EXPIRY_HOURS="${EXPIRY_HOURS:-48}"
SUBJECT_STARTUP_DELAY_SECONDS="${SUBJECT_STARTUP_DELAY_SECONDS:-25}"
SUBJECT_REQUEST_DELAY_MS="${SUBJECT_REQUEST_DELAY_MS:-0}"

PARAM_ARGS=(
  --parameters ./infra/main.parameters.json
  --parameters
  "baseName=${BASE_NAME}"
  "expiryHours=${EXPIRY_HOURS}"
  "subjectStartupDelaySeconds=${SUBJECT_STARTUP_DELAY_SECONDS}"
  "subjectRequestDelayMs=${SUBJECT_REQUEST_DELAY_MS}"
)

if [[ -n "${ACR_NAME:-}" ]]; then
  PARAM_ARGS+=("acrName=${ACR_NAME}")
fi
if [[ -n "${SUBJECT_IMAGE:-}" ]]; then
  PARAM_ARGS+=("subjectImage=${SUBJECT_IMAGE}")
fi
if [[ -n "${AUDIT_IMAGE:-}" ]]; then
  PARAM_ARGS+=("auditImage=${AUDIT_IMAGE}")
fi
if [[ -n "${PERTURBATION_SAMPLER_IMAGE:-}" ]]; then
  PARAM_ARGS+=("perturbationSamplerImage=${PERTURBATION_SAMPLER_IMAGE}")
fi
if [[ -n "${LOADGEN_IMAGE:-}" ]]; then
  PARAM_ARGS+=("loadgenImage=${LOADGEN_IMAGE}")
fi

echo ">> Deploying startup-degraded-transient-failure lab (issue #205)"
echo "   Resource group       : $RG"
echo "   Location             : $LOCATION"
echo "   Base name            : $BASE_NAME"
echo "   Expiry hours         : $EXPIRY_HOURS"
echo "   Startup delay (sec)  : $SUBJECT_STARTUP_DELAY_SECONDS"
echo "   Request delay (ms)   : $SUBJECT_REQUEST_DELAY_MS"
echo "   ACR                  : ${ACR_NAME:-<placeholder images>}"
echo

if ! az group show --name "$RG" --output none 2>/dev/null; then
  echo ">> Creating resource group $RG"
  az group create --name "$RG" --location "$LOCATION" --output none
fi

DEPLOYMENT_NAME="sdlab-$(date -u +%Y%m%d%H%M%S)"

echo ">> Submitting deployment $DEPLOYMENT_NAME"
az deployment group create \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file ./infra/main.bicep \
  "${PARAM_ARGS[@]}" \
  --output none

echo ">> Deployment complete. Outputs:"
az deployment group show \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --query 'properties.outputs' \
  --output json

cat <<'EOF'

Next steps:
  1. (Recommended) Build all three custom images into your ACR:
       az acr build --registry "$ACR_NAME" --image startup-degraded/subject:latest               ./subject
       az acr build --registry "$ACR_NAME" --image startup-degraded/audit:latest                 ./audit
       az acr build --registry "$ACR_NAME" --image startup-degraded/perturbation-sampler:latest  ./perturbation-sampler
       az acr build --registry "$ACR_NAME" --image startup-degraded/loadgen:latest               ./loadgen
     Then redeploy with --parameters subjectImage=... auditImage=... perturbationSamplerImage=... loadgenImage=...

  2. Verify the deployment:
       ./verify.sh

  3. Run preflight calibration (proves 200 RPS consumes nontrivial headroom):
       ./trigger.sh --preflight

  4. Run baseline (30 min, no perturbation):
       ./trigger.sh --baseline --duration 1800

  5. Run perturbation phase (12 events over ~2 hours):
       ./trigger.sh --perturbation --events 12 --interval 600

  6. Run supplemental revision-restart phase (optional):
       ./trigger.sh --supplemental-restart --events 3 --interval 600

  7. Cleanup:
       ./cleanup.sh
EOF
