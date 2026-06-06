#!/usr/bin/env bash
# falsify.sh — Scenario C falsification: the presence/absence of explicit /32
# UDR entries for PE NIC IPs controls whether PE traffic flows through the
# inspection firewall. Toggling these /32 entries flips firewall-log
# visibility from "ACR FQDNs visible" to "ACR FQDNs silently absent" — both
# while the workload pull continues to succeed.
#
# The proof is DELIBERATELY SUBTLE: in BOTH the bypass case and the recover
# case the v-bypass / v-recover image pulls SUCCEED and the new revisions
# become Healthy. The thing that DIFFERS is whether Azure Firewall
# diagnostic logs record the ACR FQDN in AZFWApplicationRule. This is the
# real-world failure mode for Scenario C: an operator believes inspection is
# happening because pulls work, but the firewall is silently bypassed and
# any FQDN-based block / audit policy is ineffective.
#
# Steps:
#   1. baseline assertion: revision Healthy on v1, / returns build_tag=v1,
#      AZFWApplicationRule shows ACR FQDN rows (proves firewall is seeing
#      ACR traffic in the baseline)
#   2. REMOVE the /32 UDR routes for each PE NIC IP (controlled variable OFF)
#   3. wait for UDR propagation
#   4. record the bypass-deploy timestamp (used as the KQL TimeGenerated floor)
#   5. deploy v-bypass and wait for Healthy
#   6. assert / returns build_tag=v-bypass (proves a fresh pull DID happen)
#   7. HARD FAIL gate: assert AZFWApplicationRule has ZERO new ACR FQDN rows
#      since the bypass timestamp (proves traffic bypassed the firewall)
#   8. RE-ADD the /32 UDR routes (controlled variable ON again)
#   9. wait for UDR propagation
#  10. record the recover-deploy timestamp
#  11. deploy v-recover and wait for Healthy
#  12. assert / returns build_tag=v-recover
#  13. HARD FAIL gate: assert AZFWApplicationRule has at least one NEW ACR
#      FQDN row since the recover timestamp (retry until log ingestion catches
#      up; proves the firewall is seeing ACR traffic again)
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-pe-forced-inspection}"
IMAGE_REPO="${IMAGE_REPO:-pe-forced-inspection-lab}"

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
echo "[falsify]   Firewall:         ${FW_NAME} (private IP ${FW_PRIVATE_IP})"
echo "[falsify]   Route table:      ${ROUTE_TABLE_NAME}"
echo "[falsify]   PE:               ${PE_NAME}"
echo "[falsify]   LAW customerId:   ${LAW_CUSTOMER_ID}"

if [ -z "$LAW_CUSTOMER_ID" ]; then
  echo "[falsify] FAIL: could not resolve Log Analytics workspace customerId."
  echo "[falsify]       Re-deploy main.bicep or verify the workspace still exists in ${RG}."
  exit 1
fi

echo "[falsify] discovering PE NIC IPs from PE networkInterfaces"
# customDnsConfigs is empty when the PE uses privateDnsZoneGroups (this lab's
# main.bicep configures privateDnsZoneGroups). FQDN -> IP mapping lives on
# the NIC's ipConfigurations[].privateLinkConnectionProperties.fqdns instead.
# Same pattern as labs/acr-network-path-pe-direct/verify.sh.
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
echo "[falsify]   PE NIC IPs:"
echo "$PE_IPS" | sed 's/^/[falsify]     /'

if [ -z "$PE_IPS" ]; then
  echo "[falsify] FAIL: could not discover any PE NIC IPs"
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
# Helper: query firewall logs for ACR FQDNs since a given timestamp
# ----------------------------------------------------------------------------
# Returns row count to stdout. Echoes the first few rows (if any) to stderr
# for human debugging. Used by both the bypass gate (expects 0) and the
# recover gate (expects >= 1). Azure Firewall log ingestion latency is
# typically 3-6 minutes, so callers must retry.
#
# Schema tolerance: queries BOTH the modern resource-specific
# `AZFWApplicationRule` table (created when the firewall diagnostic setting
# uses `logAnalyticsDestinationType: 'Dedicated'`) AND the legacy
# `AzureDiagnostics` rows with `Category == 'AzureFirewallApplicationRule'`
# (legacy / AzureDiagnostics destination type). Changing destination type on
# an existing firewall does not retroactively rewrite already-shipped rows,
# and the change can take significant time to fully take effect for the live
# log stream, so a robust assertion has to look at both shapes. main.bicep
# now ships with the Dedicated setting, but the legacy fallback keeps this
# lab reproducible across older RGs where the diagnostic setting may still
# be in the AzureDiagnostics shape.
count_azfw_acr_rows_since() {
  local since_iso="$1"
  local kql="union isfuzzy=true
  (AZFWApplicationRule
    | where TimeGenerated >= datetime('${since_iso}')
    | where Fqdn endswith \".azurecr.io\"
    | project TimeGenerated, Fqdn, SourceIp, Source='AZFWApplicationRule'),
  (AzureDiagnostics
    | where TimeGenerated >= datetime('${since_iso}')
    | where Category == 'AzureFirewallApplicationRule'
    | where msg_s contains 'azurecr.io'
    | project TimeGenerated, Fqdn=extract(@'to (\\S+):443', 1, msg_s), SourceIp=extract(@'from (\\d+\\.\\d+\\.\\d+\\.\\d+)', 1, msg_s), Source='AzureDiagnostics')
| where Fqdn endswith \".azurecr.io\"
| order by TimeGenerated desc
| take 10"
  local rows
  rows="$(az monitor log-analytics query \
    --workspace "$LAW_CUSTOMER_ID" \
    --analytics-query "$kql" \
    --output tsv 2>/dev/null || true)"
  if [ -n "$rows" ]; then
    echo "$rows" | head -10 >&2
    echo "$rows" | wc -l | tr -d ' '
  else
    echo "0"
  fi
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

# Confirm baseline firewall visibility: AZFWApplicationRule should already
# contain at least one ACR FQDN row from the trigger.sh pull window. Without
# this baseline visibility the bypass step's "no new rows" assertion is
# vacuously true (you cannot detect bypass if the firewall NEVER sees ACR).
echo "[falsify] step 1b: confirm baseline firewall visibility (AZFWApplicationRule already has ACR rows)"
BASELINE_VISIBILITY="no"
for attempt in 1 2 3 4 5; do
  baseline_rows="$(count_azfw_acr_rows_since "$(date -u -v-30M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '30 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')")"
  if [ "$baseline_rows" -gt 0 ]; then
    echo "[falsify]   baseline visibility OK: ${baseline_rows} AZFWApplicationRule ACR row(s) in last 30m"
    BASELINE_VISIBILITY="yes"
    break
  fi
  echo "[falsify]   attempt ${attempt}/5: no baseline AZFWApplicationRule ACR rows yet, sleeping 60s"
  sleep 60
done
if [ "$BASELINE_VISIBILITY" != "yes" ]; then
  echo "[falsify] FAIL: AZFWApplicationRule never showed ACR rows in the baseline window."
  echo "[falsify]       The lab thesis requires the firewall to be seeing ACR traffic in"
  echo "[falsify]       the baseline state (with /32 UDR routes present). Without baseline"
  echo "[falsify]       visibility, the bypass test cannot prove anything. Either"
  echo "[falsify]       (a) firewall diagnostic settings are not flowing to LAW,"
  echo "[falsify]       (b) the trigger.sh pull never went through the firewall,"
  echo "[falsify]       (c) the /32 routes were missing from the start, or"
  echo "[falsify]       (d) the firewall log pipeline is severely delayed (>30m)."
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 2: REMOVE the /32 UDR routes for each PE NIC IP
# ----------------------------------------------------------------------------
echo "[falsify] step 2: REMOVING /32 UDR routes for PE NIC IPs (turning OFF inspection)"
while IFS= read -r ip; do
  if [ -z "$ip" ]; then
    continue
  fi
  route_name="pe-${ip//./-}"
  echo "[falsify]   removing route ${route_name} (${ip}/32)"
  az network route-table route delete \
    --resource-group "$RG" \
    --route-table-name "$ROUTE_TABLE_NAME" \
    --name "$route_name" \
    --output none
done <<< "$PE_IPS"

echo "[falsify]   route table after removal:"
az network route-table route list \
  --resource-group "$RG" --route-table-name "$ROUTE_TABLE_NAME" \
  --query "[].{name:name, prefix:addressPrefix, nextHop:nextHopType}" \
  --output table

# ----------------------------------------------------------------------------
# Step 3: wait for UDR propagation
# ----------------------------------------------------------------------------
# UDR changes can take 30-60s to reach the host data plane. The Container
# Apps node is a regular VM under the hood — same UDR propagation timing as
# any other Azure VM. Waiting too short here risks a race where v-bypass
# pulls partially through the firewall (mixed evidence).
echo "[falsify] step 3: wait 90s for UDR propagation"
sleep 90

# ----------------------------------------------------------------------------
# Step 4: record bypass deploy timestamp (KQL TimeGenerated floor)
# ----------------------------------------------------------------------------
# This timestamp is the floor for the bypass-test KQL query. Any
# AZFWApplicationRule row for ACR FQDN with TimeGenerated >= this value
# would be a row generated AFTER bypass was active. We expect ZERO such
# rows. Recording the timestamp BEFORE deploying v-bypass guarantees the
# pull (which happens after this timestamp) is the only event that could
# generate matching rows.
BYPASS_START_ISO="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "[falsify] step 4: bypass-deploy timestamp floor = ${BYPASS_START_ISO}"

# ----------------------------------------------------------------------------
# Step 5: deploy v-bypass
# ----------------------------------------------------------------------------
BYPASS_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-bypass"
echo "[falsify] step 5: switching ${APP_NAME} to ${BYPASS_IMAGE}"
# Same no-env-var rule as trigger.sh: image identity IS the proof. If we
# overrode BUILD_TAG via --set-env-vars, the workload would report
# build_tag=v-bypass even if the platform served from cache without
# actually pulling. The fresh-pull requirement is non-negotiable for this
# lab because the silent-bypass proof rests on the firewall observing a
# REAL pull happening over the PE path.
az containerapp update \
  --name "$APP_NAME" --resource-group "$RG" \
  --image "$BYPASS_IMAGE" \
  --output none

echo "[falsify] step 5b: waiting up to 5 minutes for v-bypass revision to reach Healthy"
DEADLINE=$((SECONDS + 300))
BYPASS_REV=""
BYPASS_HEALTH=""
while [ $SECONDS -lt $DEADLINE ]; do
  BYPASS_REV="$(az containerapp revision list \
    --name "$APP_NAME" --resource-group "$RG" \
    --query "[?properties.template.containers[0].image=='${BYPASS_IMAGE}'] | sort_by(@, &properties.createdTime) | [-1].name" \
    --output tsv)"
  if [ -n "$BYPASS_REV" ]; then
    BYPASS_HEALTH="$(az containerapp revision show \
      --name "$APP_NAME" --resource-group "$RG" --revision "$BYPASS_REV" \
      --query 'properties.healthState' --output tsv)"
    echo "[falsify]   v-bypass revision ${BYPASS_REV} healthState=${BYPASS_HEALTH}"
    if [ "$BYPASS_HEALTH" = "Healthy" ]; then
      break
    fi
  else
    echo "[falsify]   v-bypass revision not yet listed; waiting"
  fi
  sleep 15
done

if [ "$BYPASS_HEALTH" != "Healthy" ]; then
  echo "[falsify] FAIL: v-bypass revision did not become Healthy within 5 minutes."
  echo "[falsify]       The lab thesis requires v-bypass to SUCCEED in pulling (directly"
  echo "[falsify]       through PE, bypassing the firewall). If the pull failed, either"
  echo "[falsify]       (a) the PE path itself is broken (DNS / NSG / PE provisioning),"
  echo "[falsify]       (b) ACR access via PE is unhealthy, or"
  echo "[falsify]       (c) the platform-side image cache misbehavior is hiding the pull."
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 6: confirm v-bypass is actually serving (proves a real fresh pull
# happened over the PE path during the bypass window)
# ----------------------------------------------------------------------------
sleep 15
BYPASS_JSON="$(probe_build_tag bypass)"
BYPASS_TAG="$(echo "$BYPASS_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("build_tag",""))')"
echo "[falsify]   / during bypass returns build_tag=${BYPASS_TAG}"
if [ "$BYPASS_TAG" != "v-bypass" ]; then
  echo "[falsify] FAIL: bypass / returned build_tag=${BYPASS_TAG}, expected v-bypass."
  echo "[falsify]       Without proof that v-bypass actually got pulled, the silent-bypass"
  echo "[falsify]       gate is meaningless: if no pull happened, of course the firewall"
  echo "[falsify]       saw nothing."
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 7: HARD-FAIL GATE — assert AZFWApplicationRule has 0 new ACR rows
# ----------------------------------------------------------------------------
# This is the central proof of Scenario C: even though v-bypass was freshly
# pulled (confirmed in step 6) and the pull went over the PE NIC IPs, the
# firewall recorded ZERO AZFWApplicationRule rows for ACR FQDN since the
# bypass timestamp. The pull bypassed the firewall via the system /32
# route — the silent failure mode the lab is designed to demonstrate.
#
# We wait for log ingestion to give the firewall ample chance to record any
# evidence. Only after this dwell time can we assert "the firewall genuinely
# did not see this pull" rather than "the log row has not arrived yet".
echo "[falsify] step 7: HARD-FAIL gate — assert 0 NEW AZFWApplicationRule ACR rows since ${BYPASS_START_ISO}"
echo "[falsify]   waiting 5 minutes for AZFW log ingestion to catch up"
sleep 300

echo "[falsify]   querying AZFWApplicationRule SINCE ${BYPASS_START_ISO}"
BYPASS_NEW_ROWS="$(count_azfw_acr_rows_since "$BYPASS_START_ISO")"
echo "[falsify]   AZFWApplicationRule ACR rows since bypass: ${BYPASS_NEW_ROWS}"

if [ "$BYPASS_NEW_ROWS" -gt 0 ]; then
  echo "[falsify] FAIL: AZFWApplicationRule recorded ${BYPASS_NEW_ROWS} ACR row(s) AFTER"
  echo "[falsify]       removing the /32 UDR routes. The lab thesis requires ZERO new"
  echo "[falsify]       firewall ACR rows during the bypass window. If rows appeared,"
  echo "[falsify]       either (a) the /32 routes were not actually removed in step 2,"
  echo "[falsify]       (b) the UDR propagation in step 3 did not complete, or"
  echo "[falsify]       (c) some OTHER ACR consumer in the same subnet is still being"
  echo "[falsify]       routed through the firewall (rare in this lab but possible"
  echo "[falsify]       if the operator ran multiple deployments against the same RG)."
  exit 1
fi
echo "[falsify]   BYPASS PROOF: ${BYPASS_NEW_ROWS} NEW AZFWApplicationRule ACR rows = firewall silently bypassed"

# ----------------------------------------------------------------------------
# Step 8: RE-ADD the /32 UDR routes (turning inspection back ON)
# ----------------------------------------------------------------------------
echo "[falsify] step 8: RE-ADDING /32 UDR routes for PE NIC IPs (turning inspection back ON)"
while IFS= read -r ip; do
  if [ -z "$ip" ]; then
    continue
  fi
  route_name="pe-${ip//./-}"
  echo "[falsify]   re-adding route ${route_name}: ${ip}/32 -> ${FW_PRIVATE_IP}"
  az network route-table route create \
    --resource-group "$RG" \
    --route-table-name "$ROUTE_TABLE_NAME" \
    --name "$route_name" \
    --address-prefix "${ip}/32" \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$FW_PRIVATE_IP" \
    --output none
done <<< "$PE_IPS"

echo "[falsify]   route table after re-add:"
az network route-table route list \
  --resource-group "$RG" --route-table-name "$ROUTE_TABLE_NAME" \
  --query "[].{name:name, prefix:addressPrefix, nextHop:nextHopType, nextHopIp:nextHopIpAddress}" \
  --output table

# ----------------------------------------------------------------------------
# Step 9: wait for UDR propagation
# ----------------------------------------------------------------------------
echo "[falsify] step 9: wait 90s for UDR propagation"
sleep 90

# ----------------------------------------------------------------------------
# Step 10: record recover deploy timestamp
# ----------------------------------------------------------------------------
RECOVER_START_ISO="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "[falsify] step 10: recover-deploy timestamp floor = ${RECOVER_START_ISO}"

# ----------------------------------------------------------------------------
# Step 11: deploy v-recover
# ----------------------------------------------------------------------------
RECOVER_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:v-recover"
echo "[falsify] step 11: switching ${APP_NAME} to ${RECOVER_IMAGE}"
az containerapp update \
  --name "$APP_NAME" --resource-group "$RG" \
  --image "$RECOVER_IMAGE" \
  --output none

echo "[falsify] step 11b: waiting up to 5 minutes for v-recover revision to reach Healthy"
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
    echo "[falsify]   v-recover revision ${RECOVER_REV} healthState=${RECOVER_HEALTH}"
    if [ "$RECOVER_HEALTH" = "Healthy" ]; then
      break
    fi
  else
    echo "[falsify]   v-recover revision not yet listed; waiting"
  fi
  sleep 15
done

if [ "$RECOVER_HEALTH" != "Healthy" ]; then
  echo "[falsify] FAIL: v-recover revision did not become Healthy within 5 minutes."
  echo "[falsify]       After re-adding the /32 UDR routes, the pull should succeed via"
  echo "[falsify]       the firewall (which has app rules permitting ACR FQDNs). If the"
  echo "[falsify]       recover pull fails, the firewall app rules are likely incorrect"
  echo "[falsify]       or the firewall itself has become unhealthy."
  exit 1
fi

sleep 15
RECOVER_JSON="$(probe_build_tag recover)"
RECOVER_TAG="$(echo "$RECOVER_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("build_tag",""))')"
if [ "$RECOVER_TAG" != "v-recover" ]; then
  echo "[falsify] FAIL: recover / returns build_tag=${RECOVER_TAG}, expected v-recover"
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 13: HARD-FAIL GATE — assert AZFWApplicationRule has >=1 NEW ACR row
# ----------------------------------------------------------------------------
# After re-adding the /32 UDR routes and triggering a fresh pull, the firewall
# MUST see at least one ACR FQDN row in AZFWApplicationRule. This proves the
# /32 routes actually took effect (the symmetry of the bypass-test gate). If
# this gate fails the lab cannot claim recovery actually happened; the bypass
# test alone is not falsifiable proof of the thesis.
echo "[falsify] step 13: HARD-FAIL gate — assert >=1 NEW AZFWApplicationRule ACR row since ${RECOVER_START_ISO}"
RECOVER_NEW_ROWS="0"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  echo "[falsify]   recover-gate attempt ${attempt}/10: querying AZFWApplicationRule"
  RECOVER_NEW_ROWS="$(count_azfw_acr_rows_since "$RECOVER_START_ISO")"
  echo "[falsify]   rows so far: ${RECOVER_NEW_ROWS}"
  if [ "$RECOVER_NEW_ROWS" -gt 0 ]; then
    break
  fi
  echo "[falsify]   no rows yet, sleeping 60s (firewall log latency)"
  sleep 60
done

if [ "$RECOVER_NEW_ROWS" -eq 0 ]; then
  echo "[falsify] FAIL: AZFWApplicationRule never recorded any new ACR row after re-adding"
  echo "[falsify]       /32 UDR routes (over 10 minutes of waiting). The thesis requires"
  echo "[falsify]       the firewall to see ACR traffic again once inspection is restored."
  echo "[falsify]       Either (a) UDR re-add did not propagate, (b) the firewall diagnostic"
  echo "[falsify]       settings stopped flowing to LAW, or (c) the v-recover pull served"
  echo "[falsify]       entirely from the node's image cache (no fresh PE traffic to inspect)."
  exit 1
fi

echo "[falsify]   RECOVER PROOF: ${RECOVER_NEW_ROWS} NEW AZFWApplicationRule ACR row(s) = firewall seeing ACR traffic again"

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
echo "[falsify] PASS -- Scenario C falsification complete:"
echo "[falsify]   baseline (/32 PE routes present)         -> revision ${V1_REV} Healthy, build_tag=v1, firewall SEES ACR rows"
echo "[falsify]   bypass   (/32 PE routes removed)         -> revision ${BYPASS_REV} Healthy build_tag=v-bypass, firewall sees ZERO new ACR rows"
echo "[falsify]   recover  (/32 PE routes re-added)        -> revision ${RECOVER_REV} Healthy build_tag=v-recover, firewall sees ${RECOVER_NEW_ROWS} new ACR row(s)"
echo "[falsify] Scenario C (ACR PE with Forced Inspection) reproduced end-to-end:"
echo "[falsify]   pulls SUCCEED in both bypass and recover cases — the failure mode is"
echo "[falsify]   the SILENCE in AZFWApplicationRule during the bypass window."
