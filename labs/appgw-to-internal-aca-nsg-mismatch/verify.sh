#!/usr/bin/env bash
# verify.sh — pure file processor. Reads baseline / broken / fixed
# evidence files in evidence/ and emits evidence/verify-result.json with
# five gates. Does not call Azure APIs and does not depend on $RG.
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${EVIDENCE_DIR:-$LAB_DIR/evidence}"

gate_baseline_healthy=false
gate_broken_unhealthy=false
gate_rule100_dst_is_staticIp32=false
gate_fixed_healthy=false
gate_rule100_dst_is_cae_cidr=false

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
  dst=$(jq -r '.[] | select(.priority==100) | .destinationAddressPrefix // (.destinationAddressPrefixes // [""] | .[0])' \
    "$EVIDENCE_DIR/broken-nsg-rules.json")
  if [[ "$dst" == "${static_ip}/32" || "$dst" == "$static_ip" ]]; then
    gate_rule100_dst_is_staticIp32=true
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
# to restore Healthy without changing any other variable.
verdict='HYPOTHESIS_NOT_CONFIRMED'
if [[ "$gate_baseline_healthy" == "true" \
   && "$gate_broken_unhealthy" == "true" \
   && "$gate_rule100_dst_is_staticIp32" == "true" ]]; then
  verdict='HYPOTHESIS_CONFIRMED'
fi

falsification='NOT_YET_TESTED'
if [[ -f "$EVIDENCE_DIR/fixed-backend-health.json" ]]; then
  if [[ "$gate_fixed_healthy" == "true" && "$gate_rule100_dst_is_cae_cidr" == "true" ]]; then
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
    "E_fixed_rule100_dst_equals_cae_cidr": ${gate_rule100_dst_is_cae_cidr}
  },
  "verdict": "${verdict}",
  "falsification": "${falsification}"
}
EOF

echo "[verify] wrote $EVIDENCE_DIR/verify-result.json"
jq . "$EVIDENCE_DIR/verify-result.json"

if [[ "$verdict" != "HYPOTHESIS_CONFIRMED" ]]; then
  exit 1
fi
