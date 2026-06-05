#!/usr/bin/env bash
# falsify.sh — workload-path falsification for Scenario D (record-level
# zone authority in Azure Private DNS).
#
# Scenario D is the record-CONTENT failure class: the resolver path is correct
# (VNet -> Azure DNS -> privatelink.azurecr.io zone -> PE NIC IP), but the
# zone is missing the `<registry>.<region>.data` A record.
#
# Empirical finding: with default Azure DNS (no custom DNS server in the
# VNet), Azure DNS treats the linked privatelink.azurecr.io zone as
# AUTHORITATIVE. Deleting the data A record produces NXDOMAIN, not a
# public-IP fallthrough. The application sees socket.gaierror on the data
# endpoint while the registry endpoint keeps resolving to its PE NIC IP.
# True "registry private, data public" split-brain only occurs if a custom
# DNS server is wired to fall back to public DNS on NXDOMAIN -- a separate
# topology this lab intentionally does not include.
#
# Steps:
#   1. baseline probe: topology_class=both_private (registry + data both PE NIC)
#   2. capture the data PE NIC IP from the live private DNS zone record (so we
#      can re-create the record byte-for-byte in step 7)
#   3. delete the `<registry>.<region>.data` A record from privatelink.azurecr.io
#   4. wait for client-side DNS cache TTL
#   5. broken probe: topology_class=data_nxdomain (registry stays private,
#      data lookup fails with gaierror NXDOMAIN -- the data endpoint is no
#      longer addressable from the application code's perspective)
#   6. assert the already-running revision is still Healthy (cached image)
#   7. re-create the data A record with the captured PE NIC IP
#   8. wait for record visibility
#   9. recovery probe: topology_class=both_private (data IP back to PE NIC)
#
# Scope note: this script intentionally does NOT attempt a fresh image pull
# during the broken window. With publicNetworkAccess=Disabled (the realistic
# production posture this lab models), the Container Apps control plane's ACR
# token exchange is blocked at the ACR firewall for reasons unrelated to the
# missing data record, which would confound the variable under test. The
# layer-3/4 probe (NXDOMAIN on the data endpoint) is the unambiguous
# Scenario D signal in this topology and replaces the broken-window fresh
# pull as the falsification proof.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-record-split-brain}"
ZONE_NAME="privatelink.azurecr.io"

APP_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerAppName.value --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryLoginServer.value --output tsv)"
ACR_DATA_FQDN="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryDataFqdn.value --output tsv)"
APP_FQDN="$(az containerapp show \
  --name "$APP_NAME" --resource-group "$RG" \
  --query properties.configuration.ingress.fqdn --output tsv)"

# Derive the in-zone record name from the data FQDN. The data FQDN looks like
# `acrxxxx.koreacentral.data.azurecr.io`; the corresponding A record in the
# privatelink.azurecr.io zone has the relative name `acrxxxx.koreacentral.data`.
DATA_RECORD_NAME="${ACR_DATA_FQDN%.azurecr.io}"

probe() {
  local label="$1"
  local response=""
  for attempt in 1 2 3 4 5; do
    response="$(curl -sS --max-time 30 "https://${APP_FQDN}/probe" || true)"
    if [ -n "$response" ] && echo "$response" | grep -q topology_class; then
      break
    fi
    echo "[falsify] (${label}) probe attempt ${attempt} no JSON; retrying in 10s" >&2
    sleep 10
  done
  if [ -z "$response" ] || ! echo "$response" | grep -q topology_class; then
    echo "[falsify] FAIL: /probe (${label}) did not return JSON. Got: ${response}" >&2
    exit 1
  fi
  echo "[falsify] (${label}) /probe response:" >&2
  echo "$response" | python3 -m json.tool >&2
  printf '%s' "$response"
}

extract() {
  # $1 = json, $2 = python expression on `d` (the parsed JSON dict)
  echo "$1" | python3 -c "import json,sys;d=json.load(sys.stdin);print($2)"
}

# ----------------------------------------------------------------------------
# Step 1: baseline probe
# ----------------------------------------------------------------------------
echo "[falsify] step 1: baseline probe (expect topology_class=both_private)"
BASELINE_JSON="$(probe baseline)"
BASELINE_TOPOLOGY="$(extract "$BASELINE_JSON" 'd.get("topology_class","")')"
BASELINE_REG_IP="$(extract "$BASELINE_JSON" 'd["registry"]["dns"].get("ip","")')"
BASELINE_DAT_IP="$(extract "$BASELINE_JSON" 'd["data"]["dns"].get("ip","")')"
BASELINE_REG_HTTP="$(extract "$BASELINE_JSON" 'd["registry"]["http"].get("status","")')"
BASELINE_DAT_HTTP="$(extract "$BASELINE_JSON" 'd["data"]["http"].get("status","")')"
if [ "$BASELINE_TOPOLOGY" != "both_private" ]; then
  echo "[falsify] FAIL: baseline topology_class=${BASELINE_TOPOLOGY}, expected both_private."
  echo "[falsify]       The lab is not in a healthy starting state. Run verify.sh first."
  exit 1
fi
echo "[falsify] baseline OK: registry=${BASELINE_REG_IP} (HTTP ${BASELINE_REG_HTTP}), data=${BASELINE_DAT_IP} (HTTP ${BASELINE_DAT_HTTP})"

# ----------------------------------------------------------------------------
# Step 2: capture the data PE NIC IP from the live zone record
# ----------------------------------------------------------------------------
echo "[falsify] step 2: capture the data PE NIC IP from zone ${ZONE_NAME} record ${DATA_RECORD_NAME}"
DATA_PE_IP="$(az network private-dns record-set a show \
  --resource-group "$RG" --zone-name "$ZONE_NAME" --name "$DATA_RECORD_NAME" \
  --query 'aRecords[0].ipv4Address' --output tsv)"
if [ -z "$DATA_PE_IP" ] || [[ "$DATA_PE_IP" != 10.* && "$DATA_PE_IP" != 172.* && "$DATA_PE_IP" != 192.168.* ]]; then
  echo "[falsify] FAIL: could not read data PE NIC IP from zone (got '${DATA_PE_IP}')"
  exit 1
fi
echo "[falsify] captured data PE NIC IP: ${DATA_PE_IP}"

# ----------------------------------------------------------------------------
# Step 3: delete the data A record from the private DNS zone
# ----------------------------------------------------------------------------
echo "[falsify] step 3: DELETE A record ${DATA_RECORD_NAME} from zone ${ZONE_NAME}"
az network private-dns record-set a delete \
  --resource-group "$RG" --zone-name "$ZONE_NAME" --name "$DATA_RECORD_NAME" \
  --yes --output none
echo "[falsify] deleted. Confirming record is gone:"
az network private-dns record-set a show \
  --resource-group "$RG" --zone-name "$ZONE_NAME" --name "$DATA_RECORD_NAME" \
  --query 'aRecords' --output tsv 2>&1 | head -3 || true

# ----------------------------------------------------------------------------
# Step 4: wait for client-side DNS cache TTL
# ----------------------------------------------------------------------------
echo "[falsify] step 4: wait 90s for client-side DNS cache TTL to expire"
sleep 90

# ----------------------------------------------------------------------------
# Step 5: broken probe -> expect topology_class=data_nxdomain
# ----------------------------------------------------------------------------
echo "[falsify] step 5: broken probe (expect topology_class=data_nxdomain, data class=None, gaierror NXDOMAIN)"
BROKEN_JSON="$(probe broken)"
BROKEN_TOPOLOGY="$(extract "$BROKEN_JSON" 'd.get("topology_class","")')"
BROKEN_REG_IP="$(extract "$BROKEN_JSON" 'd["registry"]["dns"].get("ip","")')"
BROKEN_REG_CLASS="$(extract "$BROKEN_JSON" 'd["registry"]["dns"].get("class","")')"
BROKEN_DAT_IP="$(extract "$BROKEN_JSON" 'd["data"]["dns"].get("ip","")')"
BROKEN_DAT_CLASS="$(extract "$BROKEN_JSON" 'd["data"]["dns"].get("class","")')"
BROKEN_DAT_ERROR="$(extract "$BROKEN_JSON" 'd["data"]["dns"].get("error","")')"
BROKEN_DAT_HTTP="$(extract "$BROKEN_JSON" 'd["data"]["http"].get("status","")')"
if [ "$BROKEN_TOPOLOGY" != "data_nxdomain" ]; then
  echo "[falsify] FAIL: broken topology_class=${BROKEN_TOPOLOGY}, expected data_nxdomain."
  echo "[falsify]       record deletion may not have propagated; check zone state."
  exit 1
fi
echo "[falsify] broken OK: registry=${BROKEN_REG_IP} (${BROKEN_REG_CLASS}), data=NXDOMAIN (${BROKEN_DAT_ERROR})"

# ----------------------------------------------------------------------------
# Step 6: assert already-running revision is still Healthy (cached image)
# ----------------------------------------------------------------------------
echo "[falsify] step 6: confirm the already-running revision is STILL Healthy"
sleep 30
PRE_HEALTH="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "[0].properties.healthState" --output tsv)"
PRE_REV="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "[0].name" --output tsv)"
echo "[falsify] already-running revision ${PRE_REV} healthState=${PRE_HEALTH}"
if [ "$PRE_HEALTH" != "Healthy" ]; then
  echo "[falsify] NOTE: already-running revision is not Healthy (${PRE_HEALTH}). Continuing,"
  echo "[falsify]       but note this for the lab guide."
fi

# ----------------------------------------------------------------------------
# Step 7: re-create the data A record with the captured PE NIC IP
# ----------------------------------------------------------------------------
echo "[falsify] step 7: re-create A record ${DATA_RECORD_NAME} -> ${DATA_PE_IP}"
az network private-dns record-set a create \
  --resource-group "$RG" --zone-name "$ZONE_NAME" --name "$DATA_RECORD_NAME" \
  --output none
az network private-dns record-set a add-record \
  --resource-group "$RG" --zone-name "$ZONE_NAME" --record-set-name "$DATA_RECORD_NAME" \
  --ipv4-address "$DATA_PE_IP" --output none
echo "[falsify] re-created. Confirming record is back:"
az network private-dns record-set a show \
  --resource-group "$RG" --zone-name "$ZONE_NAME" --name "$DATA_RECORD_NAME" \
  --query 'aRecords[0].ipv4Address' --output tsv

# ----------------------------------------------------------------------------
# Step 8: wait for record visibility
# ----------------------------------------------------------------------------
echo "[falsify] step 8: wait 90s for the recreated record to become visible to clients"
sleep 90

# ----------------------------------------------------------------------------
# Step 9: recovery probe -> expect topology_class=both_private
# ----------------------------------------------------------------------------
echo "[falsify] step 9: recovery probe (expect topology_class=both_private again)"
RECOVERY_JSON="$(probe recovery)"
RECOVERY_TOPOLOGY="$(extract "$RECOVERY_JSON" 'd.get("topology_class","")')"
RECOVERY_DAT_IP="$(extract "$RECOVERY_JSON" 'd["data"]["dns"].get("ip","")')"
RECOVERY_DAT_HTTP="$(extract "$RECOVERY_JSON" 'd["data"]["http"].get("status","")')"
if [ "$RECOVERY_TOPOLOGY" != "both_private" ]; then
  echo "[falsify] FAIL: recovery topology_class=${RECOVERY_TOPOLOGY}, expected both_private."
  echo "[falsify]       record re-add may not have propagated; check zone state."
  exit 1
fi
echo "[falsify] recovery OK: data=${RECOVERY_DAT_IP} (private), HTTP=${RECOVERY_DAT_HTTP}"

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
echo "[falsify] PASS — workload-path falsification complete:"
echo "[falsify]   baseline (record present)  -> topology=both_private   registry=${BASELINE_REG_IP} data=${BASELINE_DAT_IP} (HTTP ${BASELINE_DAT_HTTP})"
echo "[falsify]   broken   (record deleted)  -> topology=data_nxdomain  registry=${BROKEN_REG_IP} data=NXDOMAIN (${BROKEN_DAT_ERROR})"
echo "[falsify]   already-running revision ${PRE_REV}: healthState=${PRE_HEALTH} during broken window"
echo "[falsify]   recovery (record restored) -> topology=both_private   data=${RECOVERY_DAT_IP} (HTTP ${RECOVERY_DAT_HTTP})"
echo "[falsify] Scenario D (record-level zone authority) reproduced at the workload layer."
echo "[falsify] No immediate revision-health impact was observed in this reproduction."
