#!/usr/bin/env bash
# falsify.sh — workload-path falsification for Scenario E (DNS forwarder bypass).
#
# This lab makes a non-obvious Azure Container Apps behavior falsifiable:
# in this ACA reproduction, breaking the VNet custom DNS forwarder
# (swapping its upstream from Azure DNS 168.63.129.16 to public DNS
# 8.8.8.8) causes no immediate revision-health impact on the
# already-running revision, while application code inside the replica
# immediately sees a different DNS answer for the ACR FQDN — public
# registry IP instead of the PE NIC's RFC1918 IP.
#
# Steps:
#   1. baseline probe: first_class=private (workload sees PE NIC)
#   2. break dnsmasq upstream -> 8.8.8.8 (and wait for cache TTL)
#   3. broken probe: first_class=public (workload resolves publicly)
#   4. assert the already-running revision is still Healthy
#   5. restore dnsmasq upstream -> 168.63.129.16 (and wait for cache TTL)
#   6. recovery probe: first_class=private (workload sees PE NIC again)
#
# Scope note: this script intentionally does NOT attempt to deploy a
# fresh image during the broken window. With ACR configured for
# `publicNetworkAccess=Disabled` (the realistic production posture this
# lab models), the Container Apps control plane's ACR token exchange is
# blocked at the ACR firewall for reasons unrelated to dnsmasq, which
# would confound the variable under test. See the lab guide
# §"Why we do not script a broken-window fresh pull" for details.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-dns-forwarder-bypass}"

APP_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerAppName.value --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryLoginServer.value --output tsv)"
DNS_VM_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.dnsVmName.value --output tsv)"
APP_FQDN="$(az containerapp show \
  --name "$APP_NAME" --resource-group "$RG" \
  --query properties.configuration.ingress.fqdn --output tsv)"

run_on_vm() {
  az vm run-command invoke \
    --resource-group "$RG" --name "$DNS_VM_NAME" \
    --command-id RunShellScript \
    --scripts "$1" \
    --query 'value[0].message' --output tsv
}

probe() {
  local label="$1"
  local response=""
  for attempt in 1 2 3 4 5; do
    response="$(curl -sS --max-time 10 "https://${APP_FQDN}/probe" || true)"
    if [ -n "$response" ] && echo "$response" | grep -q first_class; then
      break
    fi
    echo "[falsify] (${label}) probe attempt ${attempt} no JSON; retrying in 10s" >&2
    sleep 10
  done
  if [ -z "$response" ] || ! echo "$response" | grep -q first_class; then
    echo "[falsify] FAIL: /probe (${label}) did not return JSON. Got: ${response}" >&2
    exit 1
  fi
  echo "[falsify] (${label}) /probe response: ${response}" >&2
  printf '%s' "$response"
}

extract_first_class() {
  echo "$1" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("first_class",""))'
}

extract_first_ip() {
  echo "$1" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("addresses",[{}])[0].get("ip",""))'
}

# ----------------------------------------------------------------------------
# Step 1: baseline probe
# ----------------------------------------------------------------------------
echo "[falsify] step 1: baseline probe (expect first_class=private, PE NIC IP)"
BASELINE_JSON="$(probe baseline)"
BASELINE_CLASS="$(extract_first_class "$BASELINE_JSON")"
BASELINE_IP="$(extract_first_ip "$BASELINE_JSON")"
if [ "$BASELINE_CLASS" != "private" ]; then
  echo "[falsify] FAIL: baseline first_class=${BASELINE_CLASS}, expected private."
  echo "[falsify]       The lab is not in a healthy starting state. Run verify.sh first."
  exit 1
fi
echo "[falsify] baseline OK: workload resolves ${ACR_LOGIN_SERVER} to private IP ${BASELINE_IP}"

# ----------------------------------------------------------------------------
# Step 2: break dnsmasq upstream -> 8.8.8.8
# ----------------------------------------------------------------------------
echo "[falsify] step 2: swap dnsmasq default upstream from Azure DNS (168.63.129.16) to public DNS (8.8.8.8) on ${DNS_VM_NAME}"
run_on_vm "sudo sed -i 's|^server=168.63.129.16\$|server=8.8.8.8|' /etc/dnsmasq.d/acr-lab.conf && sudo systemctl restart dnsmasq && grep -E '^server=' /etc/dnsmasq.d/acr-lab.conf"

echo "[falsify] step 2b: wait 60s for dnsmasq + workload DNS cache TTL to expire"
sleep 60

# ----------------------------------------------------------------------------
# Step 3: broken probe -> expect first_class=public
# ----------------------------------------------------------------------------
echo "[falsify] step 3: broken probe (expect first_class=public, internet IP)"
BROKEN_JSON="$(probe broken)"
BROKEN_CLASS="$(extract_first_class "$BROKEN_JSON")"
BROKEN_IP="$(extract_first_ip "$BROKEN_JSON")"
if [ "$BROKEN_CLASS" != "public" ]; then
  echo "[falsify] FAIL: broken first_class=${BROKEN_CLASS}, expected public."
  echo "[falsify]       dnsmasq swap may not have applied; check VM state."
  exit 1
fi
echo "[falsify] broken OK: workload resolves ${ACR_LOGIN_SERVER} to public IP ${BROKEN_IP} (forwarder bypass at workload layer)"

# ----------------------------------------------------------------------------
# Step 4: assert already-running revision is still Healthy
# ----------------------------------------------------------------------------
echo "[falsify] step 4: confirm the already-running revision is STILL Healthy"
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
# Step 5: restore dnsmasq upstream -> 168.63.129.16
# ----------------------------------------------------------------------------
echo "[falsify] step 5: restore dnsmasq upstream to Azure DNS (168.63.129.16)"
run_on_vm "sudo sed -i 's|^server=8.8.8.8\$|server=168.63.129.16|' /etc/dnsmasq.d/acr-lab.conf && sudo systemctl restart dnsmasq && grep -E '^server=' /etc/dnsmasq.d/acr-lab.conf"

echo "[falsify] step 5b: wait 60s for cache TTL to expire"
sleep 60

# ----------------------------------------------------------------------------
# Step 6: recovery probe -> expect first_class=private
# ----------------------------------------------------------------------------
echo "[falsify] step 6: recovery probe (expect first_class=private again)"
RECOVERY_JSON="$(probe recovery)"
RECOVERY_CLASS="$(extract_first_class "$RECOVERY_JSON")"
RECOVERY_IP="$(extract_first_ip "$RECOVERY_JSON")"
if [ "$RECOVERY_CLASS" != "private" ]; then
  echo "[falsify] FAIL: recovery first_class=${RECOVERY_CLASS}, expected private."
  echo "[falsify]       dnsmasq restore may not have applied; check VM state."
  exit 1
fi
echo "[falsify] recovery OK: workload resolves ${ACR_LOGIN_SERVER} to private IP ${RECOVERY_IP}"

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
echo "[falsify] PASS — workload-path falsification complete:"
echo "[falsify]   baseline   (server=168.63.129.16) -> first_class=private  (${BASELINE_IP})"
echo "[falsify]   broken     (server=8.8.8.8)       -> first_class=public   (${BROKEN_IP})"
echo "[falsify]   already-running revision ${PRE_REV}: healthState=${PRE_HEALTH} during broken window"
echo "[falsify]   recovery   (server=168.63.129.16) -> first_class=private  (${RECOVERY_IP})"
echo "[falsify] Scenario E (DNS forwarder bypass) reproduced at the workload layer."
echo "[falsify] No immediate revision-health impact was observed in this reproduction."
