#!/usr/bin/env bash
# trigger.sh — bring Scenario C (ACR PE with Forced Inspection) to its
# BASELINE state: 3 image tags built in ACR, ACR locked down to PE-only,
# UDR augmented with /32 routes for each PE NIC IP so PE traffic is forced
# through the firewall, app switched to the v1 image, replica Healthy,
# AZFWApplicationRule rows for ACR FQDN observed in Log Analytics.
#
# Steps:
#   1. read deployment outputs (RG, ACR, app, firewall, route table, PE)
#   2. fetch ACR admin credentials (admin user is enabled by main.bicep)
#   3. build v1, v-bypass, v-recover via `az acr build` WHILE ACR is still
#      publicNetworkAccess=Enabled (each tag bakes a different BUILD_TAG ->
#      different digest -> forces fresh pull)
#   4. lock down ACR: publicNetworkAccess=Disabled so the only path is PE
#   5. discover PE NIC private IPs (registry + data) from the PE resource
#   6. add explicit /32 UDR routes for each PE NIC IP -> firewall private IP
#      (this is the controlled variable; the default 0.0.0.0/0 -> firewall
#      route is NOT sufficient because the system /32 route for the PE
#      wins on longest-prefix match)
#   7. attach the registry to the Container App with ACR admin credentials
#      (NOT managed identity -- see scope note below)
#   8. switch the app image to v1 and wait for the new revision to be Healthy
#   9. query AZFWApplicationRule for ACR FQDN entries to prove the firewall
#      is seeing ACR traffic (smoking gun for "inspection is working")
#
# Scope note on auth: this lab uses ACR admin credentials, NOT a managed
# identity. The same rationale as Lab 1 (Scenario A — firewall-allowlist)
# applies: managed identity introduces a control-plane token-exchange call
# whose network path is DIFFERENT from the replica's image-pull path. With
# MI, the workload's MI sidecar must also reach login.microsoftonline.com
# from inside snet-aca to acquire an AAD token. In a forced-inspection
# topology the AAD call must traverse the firewall, and the firewall must
# explicitly permit login.microsoftonline.com (plus the AAD discovery
# endpoints). That second auth path is a confound: a failed pull could be
# attributable to the PE data-plane path under test OR to the MI auth path
# that has nothing to do with the /32 UDR thesis.
#
# With admin credentials the only authentication is a docker login over the
# replica's egress path to the ACR FQDN. The ACR FQDN resolves via the
# private DNS zone to a PE NIC IP, so the entire auth+pull conversation
# rides on the same /32-controlled path. The /32 UDR entries for PE NIC IPs
# become the single controlled variable for the entire experiment, exactly
# as Lab 1 documented for its IP-allowlist controlled variable.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-pe-forced-inspection}"
IMAGE_REPO="${IMAGE_REPO:-pe-forced-inspection-lab}"

# ----------------------------------------------------------------------------
# Step 1: read deployment outputs (with resource-lookup fallback)
# ----------------------------------------------------------------------------
echo "[trigger] step 1: reading deployment outputs from ${DEPLOYMENT_NAME}"

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

FW_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.firewallName.value --output tsv 2>/dev/null || true)"
if [ -z "$FW_NAME" ] || [ "$FW_NAME" = "null" ]; then
  FW_NAME="$(az network firewall list --resource-group "$RG" --query "[0].name" --output tsv)"
fi

FW_PRIVATE_IP="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.firewallPrivateIp.value --output tsv 2>/dev/null || true)"
if [ -z "$FW_PRIVATE_IP" ] || [ "$FW_PRIVATE_IP" = "null" ]; then
  FW_PRIVATE_IP="$(az network firewall show --resource-group "$RG" --name "$FW_NAME" \
    --query "ipConfigurations[0].privateIPAddress" --output tsv)"
fi

ROUTE_TABLE_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.routeTableName.value --output tsv 2>/dev/null || true)"
if [ -z "$ROUTE_TABLE_NAME" ] || [ "$ROUTE_TABLE_NAME" = "null" ]; then
  ROUTE_TABLE_NAME="$(az network route-table list --resource-group "$RG" --query "[0].name" --output tsv)"
fi

PE_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.privateEndpointName.value --output tsv 2>/dev/null || true)"
if [ -z "$PE_NAME" ] || [ "$PE_NAME" = "null" ]; then
  PE_NAME="$(az network private-endpoint list --resource-group "$RG" --query "[0].name" --output tsv)"
fi

REGISTRY_LOGIN_FQDN="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.registryLoginServer.value --output tsv 2>/dev/null || true)"
if [ -z "$REGISTRY_LOGIN_FQDN" ] || [ "$REGISTRY_LOGIN_FQDN" = "null" ]; then
  REGISTRY_LOGIN_FQDN="${ACR_LOGIN_SERVER}"
fi

echo "[trigger]   ACR:                  ${ACR_NAME} (${ACR_LOGIN_SERVER})"
echo "[trigger]   Container App:        ${APP_NAME}"
echo "[trigger]   Firewall:             ${FW_NAME} (private IP ${FW_PRIVATE_IP})"
echo "[trigger]   Route table:          ${ROUTE_TABLE_NAME}"
echo "[trigger]   Private Endpoint:     ${PE_NAME}"

# ----------------------------------------------------------------------------
# Step 2: fetch ACR admin credentials
# ----------------------------------------------------------------------------
# Fetched NOW (while ACR is publicly accessible) for two reasons:
#   (a) `az acr credential show` is a control-plane ARM call that needs ACR
#       to be reachable from the user's az-cli context. After step 4 sets
#       publicNetworkAccess=Disabled, the control-plane data-plane bridge
#       still works for credential queries, but fetching upfront keeps the
#       script tolerant of any future tightening.
#   (b) main.bicep ships ACR with adminUserEnabled=true. If a previous run
#       (or an operator) flipped admin user off, fail fast here with a
#       clear message rather than at the docker-login stage inside the
#       replica (which would surface as an opaque revision Unhealthy).
echo "[trigger] step 2: fetching ACR admin credentials"
ACR_USERNAME="$(az acr credential show --name "$ACR_NAME" --query username --output tsv)"
ACR_PASSWORD="$(az acr credential show --name "$ACR_NAME" --query 'passwords[0].value' --output tsv)"
if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
  echo "[trigger] FAIL: could not fetch ACR admin credentials. Is adminUserEnabled=true?"
  exit 1
fi
echo "[trigger]   admin user: ${ACR_USERNAME} (password elided)"

# ----------------------------------------------------------------------------
# Step 3: build v1, v-bypass, v-recover WHILE ACR is still publicly accessible
# ----------------------------------------------------------------------------
# All three tags must be built BEFORE switching ACR to publicNetworkAccess=Disabled.
# `az acr build` runs on ACR Tasks build agents that push to the registry over
# the public endpoint. Once public access is disabled, `az acr build` cannot
# push from outside the VNet. Building all tags now is simpler and matches what
# a real CI pipeline would do (build once, deploy many times).
echo "[trigger] step 3: building 3 image tags via az acr build"
for tag in v1 v-bypass v-recover; do
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
# Step 4: LOCK DOWN ACR to PE-only access
# ----------------------------------------------------------------------------
# publicNetworkAccess=Disabled forces every pull to go through the Private
# Endpoint. With public access still enabled, the replica might happen to
# resolve the ACR FQDN to the public IP (depending on DNS forwarder behavior),
# and the lab thesis would no longer cleanly attribute the firewall traffic
# (or lack of it) to the PE path. Disabling public access guarantees PE is
# the only data path.
echo "[trigger] step 4: setting ACR publicNetworkAccess=Disabled (PE-only)"
az acr update \
  --name "$ACR_NAME" \
  --public-network-enabled false \
  --output none

echo "[trigger]   verifying ACR network state:"
az acr show --name "$ACR_NAME" \
  --query "{publicNetworkAccess:publicNetworkAccess, privateEndpointConnections:privateEndpointConnections[].privateLinkServiceConnectionState.status}" \
  --output table

echo "[trigger]   waiting 60s for ACR firewall + DNS propagation"
sleep 60

# ----------------------------------------------------------------------------
# Step 5: discover PE NIC private IPs (registry + data endpoints)
# ----------------------------------------------------------------------------
# The PE has two NIC IPs:
#   - one for the global login endpoint (<registry>.azurecr.io)
#   - one for the regional data endpoint (<registry>.<region>.data.azurecr.io)
# Both must have explicit /32 UDR entries or the firewall will see only one
# half of the pull conversation.
#
# When the PE uses privateDnsZoneGroups (recommended, and how this lab's
# main.bicep configures it), the platform populates Azure Private DNS Zone
# records directly and leaves customDnsConfigs empty. The FQDN -> IP mapping
# lives on the NIC's ipConfigurations[].privateLinkConnectionProperties.fqdns,
# so we enumerate all NICs attached to the PE and collect every private IP.
# This is the same pattern used by labs/acr-network-path-pe-direct/verify.sh.
echo "[trigger] step 5: discovering PE NIC IPs from PE networkInterfaces"
NIC_IDS="$(az network private-endpoint show \
  --name "$PE_NAME" --resource-group "$RG" \
  --query "networkInterfaces[].id" --output tsv)"

PE_IPS=""
for nic_id in $NIC_IDS; do
  nic_ips="$(az network nic show --ids "$nic_id" \
    --query "ipConfigurations[].privateIPAddress" --output tsv)"
  PE_IPS="${PE_IPS}${nic_ips}
"
done
PE_IPS="$(printf '%s' "$PE_IPS" | grep -v '^$' | sort -u)"

if [ -z "$PE_IPS" ]; then
  echo "[trigger] FAIL: could not discover any PE NIC IPs"
  exit 1
fi

echo "[trigger]   discovered PE NIC IPs:"
echo "$PE_IPS" | sed 's/^/[trigger]     /'

# ----------------------------------------------------------------------------
# Step 6: add explicit /32 UDR routes for each PE NIC IP -> firewall
# ----------------------------------------------------------------------------
# These routes are the CONTROLLED VARIABLE of the entire experiment. With
# them present, the longest-prefix match for any packet destined to a PE NIC
# IP is the explicit /32 entry pointing to the firewall, so the packet flows
# through the firewall and shows up in AZFWApplicationRule for the ACR FQDN.
# With them absent, the system-injected /32 route for the PE wins and the
# packet goes directly to the PE NIC, bypassing the firewall entirely.
#
# falsify.sh will REMOVE these routes to prove the bypass behavior, then
# RE-ADD them to prove recovery. Naming the routes with the PE IP embedded
# makes both removal and re-addition idempotent.
echo "[trigger] step 6: adding /32 UDR routes for each PE NIC IP -> firewall ${FW_PRIVATE_IP}"
while IFS= read -r ip; do
  if [ -z "$ip" ]; then
    continue
  fi
  route_name="pe-${ip//./-}"
  echo "[trigger]   adding route ${route_name}: ${ip}/32 -> ${FW_PRIVATE_IP}"
  az network route-table route create \
    --resource-group "$RG" \
    --route-table-name "$ROUTE_TABLE_NAME" \
    --name "$route_name" \
    --address-prefix "${ip}/32" \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$FW_PRIVATE_IP" \
    --output none
done <<< "$PE_IPS"

echo "[trigger]   route table after /32 additions:"
az network route-table route list \
  --resource-group "$RG" --route-table-name "$ROUTE_TABLE_NAME" \
  --query "[].{name:name, prefix:addressPrefix, nextHop:nextHopType, nextHopIp:nextHopIpAddress}" \
  --output table

echo "[trigger]   waiting 30s for UDR propagation"
sleep 30

# ----------------------------------------------------------------------------
# Step 7: attach the registry to the Container App with admin credentials
# ----------------------------------------------------------------------------
# `az containerapp registry set` stores the username/password as a Container
# App secret and wires the registry into the app configuration so subsequent
# `az containerapp update --image <fqdn>/<repo>:<tag>` calls authenticate
# automatically. No managed identity, no AcrPull role assignment, no
# AAD-discovery round-trip — just docker login over the same PE path the
# image pull will use.
echo "[trigger] step 7: attaching ACR to ${APP_NAME} with admin credentials"
az containerapp registry set \
  --name "$APP_NAME" --resource-group "$RG" \
  --server "$ACR_LOGIN_SERVER" \
  --username "$ACR_USERNAME" \
  --password "$ACR_PASSWORD" \
  --output none

# ----------------------------------------------------------------------------
# Step 8: switch the app to v1 and wait for the new revision to be Healthy
# ----------------------------------------------------------------------------
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v1"
echo "[trigger] step 8: switching ${APP_NAME} to ${FULL_IMAGE}"
# Intentionally NOT setting BUILD_TAG as a runtime env-var. The Dockerfile
# bakes BUILD_TAG into the image via ARG+ENV, so the value the workload reads
# at / comes from the *image*, not from the Container App spec. If the image
# was never pulled, the workload cannot return the correct build_tag — image
# identity IS the proof of a fresh pull. Overriding via --set-env-vars would
# muddy that proof and break the falsification logic in falsify.sh.
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

# ----------------------------------------------------------------------------
# Step 9: confirm firewall is seeing ACR traffic (smoking gun "inspection on")
# ----------------------------------------------------------------------------
# Look for AZFWApplicationRule entries for the ACR FQDN. The first appearance
# typically takes 3-5 minutes after the pull completes (Azure Firewall log
# pipeline latency). This is INFORMATIONAL in trigger.sh — falsify.sh re-runs
# the same query with a stricter assertion gate. If trigger.sh sees the row
# right away, great; if not, falsify.sh will retry until ingestion catches up.
echo "[trigger] step 9: probing AZFWApplicationRule for ACR FQDN (informational)"
LAW_CUSTOMER_ID="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.logAnalyticsCustomerId.value --output tsv 2>/dev/null || true)"
if [ -n "$LAW_CUSTOMER_ID" ] && [ "$LAW_CUSTOMER_ID" != "null" ]; then
  KQL_PROBE="AZFWApplicationRule
| where TimeGenerated > ago(15m)
| where Fqdn endswith \".azurecr.io\"
| project TimeGenerated, Action, Fqdn, SourceIp
| order by TimeGenerated desc
| take 5"
  echo "[trigger]   querying LAW (will retry up to 3 times)"
  for attempt in 1 2 3; do
    PROBE_ROWS="$(az monitor log-analytics query \
      --workspace "$LAW_CUSTOMER_ID" \
      --analytics-query "$KQL_PROBE" \
      --output tsv 2>/dev/null || true)"
    if [ -n "$PROBE_ROWS" ]; then
      echo "[trigger]   AZFWApplicationRule rows seen on attempt ${attempt}:"
      echo "$PROBE_ROWS" | head -10
      break
    fi
    echo "[trigger]   attempt ${attempt}/3: no rows yet, sleeping 60s (firewall log latency)"
    sleep 60
  done
fi

echo "[trigger] PASS: ${APP_NAME} is running ${FULL_IMAGE} on revision ${LATEST_REV} (Healthy)"
echo "[trigger]       PE NIC IPs:"
echo "$PE_IPS" | sed 's/^/[trigger]         /'
echo "[trigger]       All PE NIC IPs now have /32 UDR routes -> firewall ${FW_PRIVATE_IP}"
echo "[trigger] Baseline state established. Run verify.sh to confirm, then falsify.sh."
