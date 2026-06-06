#!/usr/bin/env bash
# falsify.sh — Scenario A falsification: ACR's IP allowlist is keyed on the
# firewall's outbound public IP. Toggling that single value flips fresh-pull
# behavior between success and failure.
#
# This is the FIRST lab in the 5-lab ACR network path series that cleanly
# demonstrates fresh-pull behavior. Labs 2 (private endpoint) and 3
# (record-level split-brain) could not script a broken-window fresh pull
# because their managed-identity auth introduced a control-plane token
# exchange whose network path is different from the replica's image-pull
# path. This lab uses ACR admin credentials (set up by trigger.sh), so
# the only network path that matters is the replica's egress through the
# firewall -- and the falsification proof is unambiguous.
#
# Steps:
#   1. baseline assertion: revision is Healthy on v1, / returns build_tag=v1
#   2. remove the firewall public IP from ACR's ipRules
#   3. wait for ACR firewall propagation
#   4. trigger a new revision deployment with the v-broken image
#   5. assert the new revision FAILS to provision (ImagePullFailure / 403)
#   6. assert the OLD v1 revision is STILL Healthy (cached image layers
#      survive the broken ACR window for already-running replicas)
#   7. re-add the firewall public IP to ACR's ipRules
#   8. wait for ACR firewall propagation
#   9. trigger a new revision deployment with the v-recover image
#  10. assert the recovery revision becomes Healthy and / returns build_tag=v-recover
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-firewall-allowlist}"
IMAGE_REPO="${IMAGE_REPO:-firewall-allowlist-lab}"

echo "[falsify] reading deployment outputs"
APP_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.appName.value --output tsv 2>/dev/null || true)"
if [ -z "$APP_NAME" ] || [ "$APP_NAME" = "null" ]; then
  APP_NAME="$(az containerapp list --resource-group "$RG" --query "[0].name" --output tsv)"
fi
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
FW_PIP="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.firewallPublicIpAddress.value --output tsv 2>/dev/null || true)"
if [ -z "$FW_PIP" ] || [ "$FW_PIP" = "null" ]; then
  FW_PIP_NAME="$(az network firewall list --resource-group "$RG" \
    --query "[0].ipConfigurations[0].publicIPAddress.id" --output tsv | awk -F/ '{print $NF}')"
  FW_PIP="$(az network public-ip show --resource-group "$RG" --name "$FW_PIP_NAME" \
    --query ipAddress --output tsv)"
fi
# Prefer the logAnalyticsCustomerId Bicep output (added for this lab). Older
# deployments that pre-date the output fall back to looking up the workspace
# directly by name. Both paths land on the same workspace customerId GUID.
LAW_CUSTOMER_ID="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.logAnalyticsCustomerId.value --output tsv 2>/dev/null || true)"
if [ -z "$LAW_CUSTOMER_ID" ] || [ "$LAW_CUSTOMER_ID" = "null" ]; then
  LAW_NAME="$(az deployment group show \
    --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
    --query properties.outputs.logAnalyticsName.value --output tsv 2>/dev/null || true)"
  if [ -z "$LAW_NAME" ] || [ "$LAW_NAME" = "null" ]; then
    LAW_NAME="$(az monitor log-analytics workspace list --resource-group "$RG" \
      --query "[0].name" --output tsv)"
  fi
  LAW_CUSTOMER_ID="$(az monitor log-analytics workspace show \
    --resource-group "$RG" --workspace-name "$LAW_NAME" \
    --query customerId --output tsv)"
fi
APP_FQDN="$(az containerapp show \
  --name "$APP_NAME" --resource-group "$RG" \
  --query properties.configuration.ingress.fqdn --output tsv)"

echo "[falsify]   App:              ${APP_NAME}"
echo "[falsify]   App FQDN:         ${APP_FQDN}"
echo "[falsify]   ACR:              ${ACR_NAME}"
echo "[falsify]   Firewall PIP:     ${FW_PIP}  <-- controlled variable"
echo "[falsify]   LAW customerId:   ${LAW_CUSTOMER_ID}"

if [ -z "$LAW_CUSTOMER_ID" ]; then
  echo "[falsify] FAIL: could not resolve Log Analytics workspace customerId via either"
  echo "[falsify]       the logAnalyticsCustomerId Bicep output or the logAnalyticsName lookup."
  echo "[falsify]       Re-deploy main.bicep or verify the workspace still exists in ${RG}."
  exit 1
fi

# ----------------------------------------------------------------------------
# Helper: probe / and return JSON
# ----------------------------------------------------------------------------
probe_build_tag() {
  local label="$1"
  local response=""
  for attempt in 1 2 3 4 5; do
    response="$(curl -sS --max-time 30 "https://${APP_FQDN}/" || true)"
    if [ -n "$response" ] && echo "$response" | grep -q build_tag; then
      break
    fi
    echo "[falsify] (${label}) / attempt ${attempt} no JSON; retrying in 10s" >&2
    sleep 10
  done
  if [ -z "$response" ] || ! echo "$response" | grep -q build_tag; then
    echo "[falsify] FAIL: / (${label}) did not return JSON. Got: ${response}" >&2
    exit 1
  fi
  echo "[falsify] (${label}) / response:" >&2
  echo "$response" | python3 -m json.tool >&2
  printf '%s' "$response"
}

# ----------------------------------------------------------------------------
# Step 1: baseline assertion
# ----------------------------------------------------------------------------
echo "[falsify] step 1: baseline assertion (revision Healthy, / returns build_tag=v1)"
V1_REV="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "sort_by(@, &properties.createdTime) | [-1].name" --output tsv)"
V1_HEALTH="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "sort_by(@, &properties.createdTime) | [-1].properties.healthState" --output tsv)"
echo "[falsify]   baseline revision: ${V1_REV} healthState=${V1_HEALTH}"
if [ "$V1_HEALTH" != "Healthy" ]; then
  echo "[falsify] FAIL: baseline revision is not Healthy. Run trigger.sh + verify.sh first."
  exit 1
fi
BASELINE_JSON="$(probe_build_tag baseline)"
BASELINE_TAG="$(echo "$BASELINE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("build_tag",""))')"
if [ "$BASELINE_TAG" != "v1" ]; then
  echo "[falsify] FAIL: baseline build_tag=${BASELINE_TAG}, expected v1. Run trigger.sh first."
  exit 1
fi
echo "[falsify]   baseline OK: revision ${V1_REV} Healthy, build_tag=v1"

# ----------------------------------------------------------------------------
# Step 2: remove the firewall public IP from ACR's ipRules
# ----------------------------------------------------------------------------
echo "[falsify] step 2: REMOVE firewall public IP ${FW_PIP} from ACR ipRules"
az acr network-rule remove \
  --name "$ACR_NAME" \
  --ip-address "$FW_PIP" \
  --output none

echo "[falsify]   verifying ACR network rule set after removal:"
az acr show --name "$ACR_NAME" --query networkRuleSet --output json

# ----------------------------------------------------------------------------
# Step 3: wait for ACR firewall propagation
# ----------------------------------------------------------------------------
echo "[falsify] step 3: wait 60s for ACR firewall changes to propagate"
sleep 60

# ----------------------------------------------------------------------------
# Step 4: trigger a new revision deployment with the v-broken image
# ----------------------------------------------------------------------------
BROKEN_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-broken"
echo "[falsify] step 4: switching ${APP_NAME} to ${BROKEN_IMAGE}"
# Intentionally NOT setting BUILD_TAG via --set-env-vars. The Dockerfile bakes
# BUILD_TAG into the image. If ACR rejects the pull, the new revision never
# starts and the workload cannot report build_tag=v-broken. Image identity is
# the proof of a fresh pull; a runtime env-var override would muddy that proof.
az containerapp update \
  --name "$APP_NAME" --resource-group "$RG" \
  --image "$BROKEN_IMAGE" \
  --output none

# ----------------------------------------------------------------------------
# Step 5: assert the new revision FAILS to provision
# ----------------------------------------------------------------------------
# The new revision should fail to pull v-broken because ACR returns 403 to the
# firewall's SNAT IP (which is no longer in ACR's allowlist). Container Apps
# surfaces this as provisioningState=Failed on the new revision and keeps the
# previous (v1) revision running. We poll for up to 5 minutes for the failure
# signal to surface clearly.
echo "[falsify] step 5: waiting up to 5 minutes for new revision to surface as Failed"
DEADLINE=$((SECONDS + 300))
BROKEN_REV=""
BROKEN_PROVISION=""
BROKEN_HEALTH=""
while [ $SECONDS -lt $DEADLINE ]; do
  BROKEN_REV="$(az containerapp revision list \
    --name "$APP_NAME" --resource-group "$RG" \
    --query "[?properties.template.containers[0].image=='${BROKEN_IMAGE}'] | sort_by(@, &properties.createdTime) | [-1].name" \
    --output tsv)"
  if [ -n "$BROKEN_REV" ]; then
    BROKEN_PROVISION="$(az containerapp revision show \
      --name "$APP_NAME" --resource-group "$RG" --revision "$BROKEN_REV" \
      --query 'properties.provisioningState' --output tsv)"
    BROKEN_HEALTH="$(az containerapp revision show \
      --name "$APP_NAME" --resource-group "$RG" --revision "$BROKEN_REV" \
      --query 'properties.healthState' --output tsv)"
    echo "[falsify]   broken revision ${BROKEN_REV}: provisioningState=${BROKEN_PROVISION} healthState=${BROKEN_HEALTH}"
    if [ "$BROKEN_PROVISION" = "Failed" ] || [ "$BROKEN_HEALTH" = "Unhealthy" ] || [ "$BROKEN_HEALTH" = "None" ]; then
      break
    fi
  else
    echo "[falsify]   broken revision not yet listed; waiting"
  fi
  sleep 15
done

if [ -z "$BROKEN_REV" ]; then
  echo "[falsify] FAIL: no revision running v-broken ever appeared in the revision list."
  echo "[falsify]       trigger.sh may have failed or v-broken was never deployed by step 4."
  echo "[falsify]       The lab thesis requires the broken-window pull to be ATTEMPTED."
  exit 1
fi

if [ "$BROKEN_PROVISION" != "Failed" ] && [ "$BROKEN_HEALTH" != "Unhealthy" ] && [ "$BROKEN_HEALTH" != "None" ]; then
  echo "[falsify] FAIL: broken revision ${BROKEN_REV} did not surface as Failed/Unhealthy/None."
  echo "[falsify]       provisioningState=${BROKEN_PROVISION} healthState=${BROKEN_HEALTH}"
  echo "[falsify]       The lab thesis requires the broken-window fresh pull to FAIL because"
  echo "[falsify]       the firewall PIP was removed from ACR ipRules. If the broken revision"
  echo "[falsify]       provisioned successfully, either (a) the ACR firewall change did not"
  echo "[falsify]       propagate, (b) ACR allow-lists are not the controlled variable here,"
  echo "[falsify]       or (c) the image was already cached on the replica node. Investigate"
  echo "[falsify]       before claiming the lab reproduced."
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 6: assert the OLD v1 revision is STILL Healthy and still serving
# ----------------------------------------------------------------------------
echo "[falsify] step 6: confirm OLD v1 revision (${V1_REV}) is STILL Healthy"
V1_HEALTH_AFTER="$(az containerapp revision show \
  --name "$APP_NAME" --resource-group "$RG" --revision "$V1_REV" \
  --query 'properties.healthState' --output tsv)"
V1_ACTIVE_AFTER="$(az containerapp revision show \
  --name "$APP_NAME" --resource-group "$RG" --revision "$V1_REV" \
  --query 'properties.active' --output tsv)"
echo "[falsify]   v1 revision ${V1_REV}: healthState=${V1_HEALTH_AFTER} active=${V1_ACTIVE_AFTER}"

DURING_BROKEN_JSON="$(probe_build_tag broken-window)"
DURING_BROKEN_TAG="$(echo "$DURING_BROKEN_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("build_tag",""))')"
echo "[falsify]   / during broken window returns build_tag=${DURING_BROKEN_TAG}"
if [ "$DURING_BROKEN_TAG" != "v1" ]; then
  echo "[falsify] FAIL: during broken window, / returned build_tag=${DURING_BROKEN_TAG}, expected v1."
  echo "[falsify]       The lab thesis requires the cached v1 revision to keep serving while"
  echo "[falsify]       the v-broken pull fails. If v1 is no longer serving, either (a) the"
  echo "[falsify]       cached image layers were evicted, (b) the broken revision actually"
  echo "[falsify]       provisioned and took traffic, or (c) the platform promoted a"
  echo "[falsify]       different revision. The 'old revision keeps serving' guarantee is"
  echo "[falsify]       a core Container Apps property that this lab depends on."
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 6.5: KQL smoking-gun — assert ContainerAppSystemLogs_CL recorded the
# DENIED message naming the firewall PIP as the rejected source IP. This is
# the empirical proof that ACR's network rule set is keyed on the firewall's
# SNAT public IP, not on any replica IP. Without this row, the lab can only
# claim "the pull failed", not "the pull failed BECAUSE ACR rejected the
# firewall PIP". Logs typically land in LAW within 1-3 minutes after the
# failure, so we retry up to 5 times with 30s sleeps.
# ----------------------------------------------------------------------------
echo "[falsify] step 6.5: querying ContainerAppSystemLogs_CL for DENIED + firewall PIP smoking-gun"
KQL_DENIED="ContainerAppSystemLogs_CL
| where TimeGenerated > ago(15m)
| where Log_s contains 'DENIED' or Log_s contains 'denied' or Log_s contains '403'
| where Log_s contains '${FW_PIP}'
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
| take 5"

DENIED_FOUND="no"
DENIED_ROWS=""
for attempt in 1 2 3 4 5; do
  DENIED_ROWS="$(az monitor log-analytics query \
    --workspace "$LAW_CUSTOMER_ID" \
    --analytics-query "$KQL_DENIED" \
    --output tsv 2>/dev/null || true)"
  if [ -n "$DENIED_ROWS" ]; then
    DENIED_FOUND="yes"
    echo "[falsify]   SMOKING GUN found on attempt ${attempt}:"
    echo "$DENIED_ROWS" | head -10
    break
  fi
  echo "[falsify]   attempt ${attempt}/5: row not yet ingested, sleeping 30s"
  sleep 30
done

if [ "$DENIED_FOUND" != "yes" ]; then
  echo "[falsify] FAIL: ContainerAppSystemLogs_CL never recorded DENIED + firewall PIP ${FW_PIP}."
  echo "[falsify]       The lab thesis REQUIRES this row to exist. Either"
  echo "[falsify]       (a) the broken-window pull did not actually generate a DENIED log,"
  echo "[falsify]       (b) Container App diagnostic settings are not flowing to LAW, or"
  echo "[falsify]       (c) the message format changed and the KQL filter no longer matches."
  echo "[falsify]       Without this row, the lab can only claim 'pull failed', not 'pull"
  echo "[falsify]       failed BECAUSE ACR rejected the firewall PIP'. That distinction is"
  echo "[falsify]       the entire point of Scenario A."
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 7: re-add the firewall public IP to ACR's ipRules
# ----------------------------------------------------------------------------
echo "[falsify] step 7: RE-ADD firewall public IP ${FW_PIP} to ACR ipRules"
az acr network-rule add \
  --name "$ACR_NAME" \
  --ip-address "$FW_PIP" \
  --output none

echo "[falsify]   verifying ACR network rule set after recovery:"
az acr show --name "$ACR_NAME" --query networkRuleSet --output json

# ----------------------------------------------------------------------------
# Step 8: wait for ACR firewall propagation
# ----------------------------------------------------------------------------
echo "[falsify] step 8: wait 60s for ACR firewall changes to propagate"
sleep 60

# ----------------------------------------------------------------------------
# Step 9: trigger a new revision deployment with v-recover
# ----------------------------------------------------------------------------
RECOVER_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-recover"
echo "[falsify] step 9: switching ${APP_NAME} to ${RECOVER_IMAGE}"
# Same rationale as steps 4 and trigger.sh step 6: do NOT override BUILD_TAG
# via --set-env-vars. The recovery proof requires the workload to report
# build_tag=v-recover at /, which can only happen if the v-recover image was
# actually pulled. Image identity is the proof.
az containerapp update \
  --name "$APP_NAME" --resource-group "$RG" \
  --image "$RECOVER_IMAGE" \
  --output none

# ----------------------------------------------------------------------------
# Step 10: assert the recovery revision becomes Healthy
# ----------------------------------------------------------------------------
echo "[falsify] step 10: waiting up to 5 minutes for recovery revision to reach Healthy"
DEADLINE=$((SECONDS + 300))
RECOVER_REV=""
RECOVER_HEALTH=""
while [ $SECONDS -lt $DEADLINE ]; do
  RECOVER_REV="$(az containerapp revision list \
    --name "$APP_NAME" --resource-group "$RG" \
    --query "[?properties.template.containers[0].image=='${RECOVER_IMAGE}'] | sort_by(@, &properties.createdTime) | [-1].name" \
    --output tsv)"
  if [ -n "$RECOVER_REV" ]; then
    RECOVER_HEALTH="$(az containerapp revision show \
      --name "$APP_NAME" --resource-group "$RG" --revision "$RECOVER_REV" \
      --query 'properties.healthState' --output tsv)"
    echo "[falsify]   recovery revision ${RECOVER_REV} healthState=${RECOVER_HEALTH}"
    if [ "$RECOVER_HEALTH" = "Healthy" ]; then
      break
    fi
  else
    echo "[falsify]   recovery revision not yet listed; waiting"
  fi
  sleep 15
done

if [ "$RECOVER_HEALTH" != "Healthy" ]; then
  echo "[falsify] FAIL: recovery revision did not become Healthy within 5 minutes"
  echo "[falsify]       last state: ${RECOVER_REV} healthState=${RECOVER_HEALTH}"
  exit 1
fi

sleep 15
RECOVER_JSON="$(probe_build_tag recovery)"
RECOVER_TAG="$(echo "$RECOVER_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("build_tag",""))')"
if [ "$RECOVER_TAG" != "v-recover" ]; then
  echo "[falsify] FAIL: recovery / returns build_tag=${RECOVER_TAG}, expected v-recover"
  exit 1
fi

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
echo "[falsify] PASS -- workload-path falsification complete:"
echo "[falsify]   baseline (FW PIP in ACR allowlist)     -> v1 revision ${V1_REV} Healthy, / -> build_tag=v1"
echo "[falsify]   broken   (FW PIP removed from allowlist) -> v-broken revision ${BROKEN_REV} provisioningState=${BROKEN_PROVISION} healthState=${BROKEN_HEALTH}"
echo "[falsify]   during broken window: v1 revision ${V1_REV} STILL healthState=${V1_HEALTH_AFTER}, / -> build_tag=${DURING_BROKEN_TAG}"
echo "[falsify]   smoking gun: ContainerAppSystemLogs_CL recorded DENIED + firewall PIP ${FW_PIP}"
echo "[falsify]   recovery (FW PIP re-added)              -> v-recover revision ${RECOVER_REV} Healthy, / -> build_tag=v-recover"
echo "[falsify] Scenario A (Public ACR via Firewall) reproduced end-to-end with fresh-pull proof."
