#!/usr/bin/env bash
# trigger.sh — bring Scenario A (Public ACR via Firewall) to its BASELINE
# state: 3 image tags built in ACR, ACR locked down to allow ONLY the
# firewall's outbound public IP, app switched to the v1 image, replica Healthy.
#
# Steps:
#   1. read deployment outputs (RG, ACR, app, firewall PIP, FQDNs)
#   2. fetch ACR admin credentials (admin user is enabled by main.bicep)
#   3. build v1, v-broken, v-recover via `az acr build` WHILE ACR is still Allow
#      (each tag bakes a different BUILD_TAG -> different digest -> forces fresh pull)
#   4. lock down ACR: defaultAction=Deny, networkRuleBypassOptions=None,
#      ipRules=[firewall public IP] -- this is the controlled variable
#   5. attach the registry to the Container App with ACR admin creds
#      (NOT managed identity -- see scope note below)
#   6. switch the app image to v1 and wait for the new revision to be Healthy
#
# Scope note on auth: this lab uses ACR admin credentials, NOT a managed
# identity. The rationale is that managed identity introduces a control-plane
# token-exchange call (CAE control plane -> ACR for an ACR refresh token)
# whose network path is DIFFERENT from the replica's image-pull path. That
# confound is what made Labs 2 and 3 unable to cleanly demonstrate fresh-pull
# behavior. With admin creds, the only authentication is a Docker login
# happening over the replica's egress path through the firewall -- so the
# firewall's IP allowlist on ACR is genuinely the single controlled variable
# and the falsification proof is unambiguous.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-firewall-allowlist}"
IMAGE_REPO="${IMAGE_REPO:-firewall-allowlist-lab}"

# ----------------------------------------------------------------------------
# Step 1: read deployment outputs
# ----------------------------------------------------------------------------
# Read deployment outputs when available, otherwise look up resources directly.
# Direct lookup handles the case where the deployment record was lost (e.g. a
# subsequent failed redeploy) but the resources themselves are still healthy.
echo "[trigger] step 1: reading deployment outputs (with resource-lookup fallback) from ${DEPLOYMENT_NAME}"
ACR_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.registryName.value --output tsv 2>/dev/null || true)"
if [ -z "$ACR_NAME" ] || [ "$ACR_NAME" = "null" ]; then
  ACR_NAME="$(az acr list --resource-group "$RG" --query "[0].name" --output tsv)"
fi
ACR_LOGIN_SERVER="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.registryLoginServer.value --output tsv 2>/dev/null || true)"
if [ -z "$ACR_LOGIN_SERVER" ] || [ "$ACR_LOGIN_SERVER" = "null" ]; then
  ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer --output tsv)"
fi
APP_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.appName.value --output tsv 2>/dev/null || true)"
if [ -z "$APP_NAME" ] || [ "$APP_NAME" = "null" ]; then
  APP_NAME="$(az containerapp list --resource-group "$RG" --query "[0].name" --output tsv)"
fi
FW_PIP="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.firewallPublicIpAddress.value --output tsv 2>/dev/null || true)"
if [ -z "$FW_PIP" ] || [ "$FW_PIP" = "null" ]; then
  FW_PIP_NAME="$(az network firewall list --resource-group "$RG" \
    --query "[0].ipConfigurations[0].publicIPAddress.id" --output tsv | awk -F/ '{print $NF}')"
  FW_PIP="$(az network public-ip show --resource-group "$RG" --name "$FW_PIP_NAME" \
    --query ipAddress --output tsv)"
fi

if [ -z "$FW_PIP" ]; then
  echo "[trigger] FAIL: firewall public IP is empty in deployment outputs"
  exit 1
fi

echo "[trigger]   ACR:               ${ACR_NAME} (${ACR_LOGIN_SERVER})"
echo "[trigger]   Container App:     ${APP_NAME}"
echo "[trigger]   Firewall public IP: ${FW_PIP}  <-- controlled variable for falsify.sh"

# ----------------------------------------------------------------------------
# Step 2: fetch ACR admin credentials
# ----------------------------------------------------------------------------
echo "[trigger] step 2: fetching ACR admin credentials"
ACR_USERNAME="$(az acr credential show --name "$ACR_NAME" --query username --output tsv)"
ACR_PASSWORD="$(az acr credential show --name "$ACR_NAME" --query 'passwords[0].value' --output tsv)"
if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
  echo "[trigger] FAIL: could not fetch ACR admin credentials. Is adminUserEnabled=true?"
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 3: build v1, v-broken, v-recover WHILE ACR is still Allow
# ----------------------------------------------------------------------------
# All three tags must be built BEFORE locking down ACR. Once defaultAction=Deny
# is set, `az acr build` pushes (over the public endpoint from the build agent)
# would still work via the AzureContainerRegistry service-tag bypass, but
# `networkRuleBypassOptions=None` (which we set in step 4) closes even that.
# Building all tags now is simpler and matches what a real CI pipeline would
# do (build once, deploy many times).
echo "[trigger] step 3: building 3 image tags via az acr build (server-side)"
for tag in v1 v-broken v-recover; do
  echo "[trigger]   building ${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${tag}"
  az acr build \
    --registry "$ACR_NAME" \
    --image "${IMAGE_REPO}:${tag}" \
    --build-arg "BUILD_TAG=${tag}" \
    --file "${LAB_DIR}/workload/Dockerfile" \
    "${LAB_DIR}/workload" \
    --output none
done

# ----------------------------------------------------------------------------
# Step 4: LOCK DOWN ACR -- this is the central thesis of Scenario A
# ----------------------------------------------------------------------------
# defaultAction=Deny             -> reject any source IP not explicitly allowed
# networkRuleBypassOptions=None  -> close the AzureServices bypass too
# ipRules=[FW_PIP]               -> allow only the firewall's SNAT public IP
#
# Any image pull from this ACR that does NOT egress through the firewall (and
# thus does NOT SNAT to FW_PIP) is rejected by ACR's firewall layer with HTTP
# 403 before reaching the registry backend. This is the single controlled
# variable for the entire lab.
echo "[trigger] step 4: locking down ACR network rule set"
echo "[trigger]   defaultAction=Deny, networkRuleBypassOptions=None, ipRules=[${FW_PIP}]"
az acr network-rule add \
  --name "$ACR_NAME" \
  --ip-address "$FW_PIP" \
  --output none
az acr update \
  --name "$ACR_NAME" \
  --default-action Deny \
  --allow-trusted-services false \
  --output none

echo "[trigger]   verifying ACR network rule set after lockdown:"
az acr show --name "$ACR_NAME" --query networkRuleSet --output json

echo "[trigger]   waiting 30s for ACR firewall rules to propagate"
sleep 30

# ----------------------------------------------------------------------------
# Step 5: attach the registry to the Container App with admin creds
# ----------------------------------------------------------------------------
echo "[trigger] step 5: attaching ACR to ${APP_NAME} with admin credentials"
az containerapp registry set \
  --name "$APP_NAME" --resource-group "$RG" \
  --server "$ACR_LOGIN_SERVER" \
  --username "$ACR_USERNAME" \
  --password "$ACR_PASSWORD" \
  --output none

# ----------------------------------------------------------------------------
# Step 6: switch the app to v1 and wait for the new revision to be Healthy
# ----------------------------------------------------------------------------
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v1"
echo "[trigger] step 6: switching ${APP_NAME} to ${FULL_IMAGE}"
# Intentionally NOT setting BUILD_TAG as a runtime env-var. The Dockerfile bakes
# BUILD_TAG into the image via ARG+ENV, so the value the workload reads at /
# comes from the *image*, not from the Container App spec. If the image was
# never pulled (e.g. ACR firewall rejected the request), the workload cannot
# return the correct build_tag — image identity IS the proof of a fresh pull.
# Overriding via --set-env-vars would muddy that proof.
az containerapp update \
  --name "$APP_NAME" --resource-group "$RG" \
  --image "$FULL_IMAGE" \
  --output none

echo "[trigger] waiting up to 5 minutes for the v1 revision to reach Healthy"
DEADLINE=$((SECONDS + 300))
LATEST_REV=""
LATEST_HEALTH=""
while [ $SECONDS -lt $DEADLINE ]; do
  LATEST_REV="$(az containerapp revision list \
    --name "$APP_NAME" --resource-group "$RG" \
    --query "sort_by(@, &properties.createdTime) | [-1].name" --output tsv)"
  LATEST_HEALTH="$(az containerapp revision list \
    --name "$APP_NAME" --resource-group "$RG" \
    --query "sort_by(@, &properties.createdTime) | [-1].properties.healthState" --output tsv)"
  echo "[trigger]   revision ${LATEST_REV} healthState=${LATEST_HEALTH}"
  if [ "$LATEST_HEALTH" = "Healthy" ]; then
    break
  fi
  sleep 15
done

if [ "$LATEST_HEALTH" != "Healthy" ]; then
  echo "[trigger] FAIL: revision ${LATEST_REV} did not become Healthy within 5 minutes"
  echo "[trigger]       inspect with:"
  echo "         az containerapp logs show --name $APP_NAME --resource-group $RG --type system --tail 50"
  exit 1
fi

echo "[trigger] PASS: ${APP_NAME} is running ${FULL_IMAGE} on revision ${LATEST_REV} (Healthy)"
echo "[trigger] Baseline state established. Run verify.sh to confirm, then falsify.sh."
