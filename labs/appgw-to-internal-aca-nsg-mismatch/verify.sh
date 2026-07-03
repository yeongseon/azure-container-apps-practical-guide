#!/usr/bin/env bash
# verify.sh — pure file processor. Reads baseline / broken / fixed
# evidence files in evidence/ and emits evidence/verify-result.json with
# seven gates (A/B/C confirm H1, D/E close falsification, F/G actively
# exclude H2 and H3 as compounding causes). Does not call Azure APIs
# and does not depend on $RG.
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${EVIDENCE_DIR:-$LAB_DIR/evidence}"

gate_baseline_healthy=false
gate_broken_unhealthy=false
gate_rule100_dst_is_staticIp32=false
gate_fixed_healthy=false
gate_rule100_dst_is_cae_cidr=false
gate_rule100_ports_intact=false
gate_rule200_azlb_allow_present=false

# All AppGW backend-health JSON blobs nest each backend server under
# backendAddressPools[].backendHttpSettingsCollection[].servers[]. We
# collect every .health value with a recursive descent and check that
# the unique set is exactly {"Healthy"} or contains "Unhealthy".
health_values() {
  jq -r '[.. | .health? // empty] | unique | .[]' "$1" 2>/dev/null | sort -u
}

if [[ -f "$EVIDENCE_DIR/baseline-backend-health.json" ]]; then
  values=$(health_values "$EVIDENCE_DIR/baseline-backend-health.json")
  if [[ "$values" == "Healthy" ]]; then
    gate_baseline_healthy=true
  fi
fi

if [[ -f "$EVIDENCE_DIR/broken-backend-health.json" ]]; then
  values=$(health_values "$EVIDENCE_DIR/broken-backend-health.json")
  if echo "$values" | grep -q "Unhealthy"; then
    gate_broken_unhealthy=true
  fi
fi

if [[ -f "$EVIDENCE_DIR/fixed-backend-health.json" ]]; then
  values=$(health_values "$EVIDENCE_DIR/fixed-backend-health.json")
  if [[ "$values" == "Healthy" ]]; then
    gate_fixed_healthy=true
  fi
fi

if [[ -f "$EVIDENCE_DIR/broken-nsg-rules.json" && -f "$EVIDENCE_DIR/deploy-outputs.json" ]]; then
  static_ip=$(jq -r '.environmentStaticIp.value' "$EVIDENCE_DIR/deploy-outputs.json")
  cae_cidr=$(jq -r '.caeSubnetPrefix.value' "$EVIDENCE_DIR/deploy-outputs.json")

  # Gate C: rule 100 Destination is staticIp/32 (or bare staticIp).
  dst=$(jq -r '.[] | select(.priority==100) | .destinationAddressPrefix // (.destinationAddressPrefixes // [""] | .[0])' \
    "$EVIDENCE_DIR/broken-nsg-rules.json")
  if [[ "$dst" == "${static_ip}/32" || "$dst" == "$static_ip" ]]; then
    gate_rule100_dst_is_staticIp32=true
  fi

  # Gate F (H2 exclusion): rule 100 destination port list contains both
  # 443 and 31443. If either is missing, H2 (missing edge-proxy ports)
  # becomes a compounding driver and the single-variable claim collapses.
  ports=$(jq -r '.[] | select(.priority==100) | ([.destinationPortRange] + (.destinationPortRanges // []) | .[] // empty)' \
    "$EVIDENCE_DIR/broken-nsg-rules.json" 2>/dev/null | sort -u)
  if echo "$ports" | grep -qx "443" && echo "$ports" | grep -qx "31443"; then
    gate_rule100_ports_intact=true
  fi

  # Gate G (H3 exclusion): a rule with Source=AzureLoadBalancer and
  # Destination=CAE subnet CIDR exists at priority strictly less than 4096.
  # If missing or ordered after the deny, H3 (AzureLoadBalancer default
  # rule shadowed by higher-priority custom Deny) becomes a compounding
  # driver.
  azlb_rule_priority=$(jq -r --arg cae "$cae_cidr" \
    '.[] | select((.sourceAddressPrefix // (.sourceAddressPrefixes // [""] | .[0])) == "AzureLoadBalancer") | select(((.destinationAddressPrefix // (.destinationAddressPrefixes // [""] | .[0])) == $cae)) | .priority' \
    "$EVIDENCE_DIR/broken-nsg-rules.json" 2>/dev/null | head -n1)
  if [[ -n "$azlb_rule_priority" && "$azlb_rule_priority" -lt 4096 ]]; then
    gate_rule200_azlb_allow_present=true
  fi
fi

if [[ -f "$EVIDENCE_DIR/fixed-nsg-rules.json" && -f "$EVIDENCE_DIR/deploy-outputs.json" ]]; then
  cae_cidr=$(jq -r '.caeSubnetPrefix.value' "$EVIDENCE_DIR/deploy-outputs.json")
  dst=$(jq -r '.[] | select(.priority==100) | .destinationAddressPrefix // (.destinationAddressPrefixes // [""] | .[0])' \
    "$EVIDENCE_DIR/fixed-nsg-rules.json")
  if [[ "$dst" == "$cae_cidr" ]]; then
    gate_rule100_dst_is_cae_cidr=true
  fi
fi

# H1 confirmed: baseline Healthy AND broken Unhealthy AND rule-100 destination
# was staticIp/32. Falsification requires the fix (destination -> CAE CIDR)
# to restore Healthy without changing any other variable AND requires gates
# F and G to have been true on the broken snapshot (H2 and H3 excluded).
verdict='HYPOTHESIS_NOT_CONFIRMED'
if [[ "$gate_baseline_healthy" == "true" \
   && "$gate_broken_unhealthy" == "true" \
   && "$gate_rule100_dst_is_staticIp32" == "true" ]]; then
  verdict='HYPOTHESIS_CONFIRMED'
fi

falsification='NOT_YET_TESTED'
if [[ -f "$EVIDENCE_DIR/fixed-backend-health.json" ]]; then
  if [[ "$gate_fixed_healthy" == "true" \
     && "$gate_rule100_dst_is_cae_cidr" == "true" \
     && "$gate_rule100_ports_intact" == "true" \
     && "$gate_rule200_azlb_allow_present" == "true" ]]; then
    falsification='FIX_VERIFIED'
  else
    falsification='FIX_DID_NOT_RECOVER'
  fi
fi

cat > "$EVIDENCE_DIR/verify-result.json" <<EOF
{
  "gates": {
    "A_baseline_backend_healthy": ${gate_baseline_healthy},
    "B_broken_backend_unhealthy": ${gate_broken_unhealthy},
    "C_broken_rule100_dst_equals_staticIp32": ${gate_rule100_dst_is_staticIp32},
    "D_fixed_backend_healthy": ${gate_fixed_healthy},
    "E_fixed_rule100_dst_equals_cae_cidr": ${gate_rule100_dst_is_cae_cidr},
    "F_broken_rule100_ports_intact_h2_excluded": ${gate_rule100_ports_intact},
    "G_broken_rule200_azlb_allow_present_h3_excluded": ${gate_rule200_azlb_allow_present}
  },
  "verdict": "${verdict}",
  "falsification": "${falsification}"
}
EOF

echo "[verify] wrote $EVIDENCE_DIR/verify-result.json"
jq . "$EVIDENCE_DIR/verify-result.json"

# Exit non-zero on any of:
#   - H1 not confirmed by gates A + B + C
#   - Broken snapshot exists but gates F or G false (H2 or H3 not excluded)
#   - Fixed snapshot exists but falsification != FIX_VERIFIED
# This makes the lab fail loudly instead of green-lighting a run where
# the fix silently did not recover or a compounding cause is present.
if [[ "$verdict" != "HYPOTHESIS_CONFIRMED" ]]; then
  echo "[verify] FAIL: verdict = ${verdict} (gates A+B+C not all true)" >&2
  exit 1
fi

if [[ -f "$EVIDENCE_DIR/broken-nsg-rules.json" ]]; then
  if [[ "$gate_rule100_ports_intact" != "true" || "$gate_rule200_azlb_allow_present" != "true" ]]; then
    echo "[verify] FAIL: gate F (${gate_rule100_ports_intact}) or gate G (${gate_rule200_azlb_allow_present}) false — H2 or H3 not excluded on broken snapshot" >&2
    exit 1
  fi
fi

if [[ -f "$EVIDENCE_DIR/fixed-backend-health.json" && "$falsification" != "FIX_VERIFIED" ]]; then
  echo "[verify] FAIL: falsification = ${falsification} (fix ran but recovery not verified)" >&2
  exit 1
fi
