#!/usr/bin/env bash
# PII scrub for startup-degraded-transient-failure evidence files.
#
# Applies the AGENTS.md PII policy to all *.log / *.tsv / *.txt / *.json files
# in this directory. Idempotent - safe to re-run as new evidence files are added.
#
# Scrub rules (mirrors Portal capture PII_RULES in scripts/portal-capture-helpers.js,
# adapted for plaintext logs):
#
#   1. Azure subscription / tenant GUIDs
#        Loaded from an ignored local file (./.local/pii-values.env) or from
#        environment variables so real identifiers are NOT committed to git.
#        Supported vars:
#          REAL_SUB_A  - Primary subscription GUID
#          REAL_SUB_B  - 2026-06-20 repro subscription GUID
#          REAL_TENANT - FDPO tenant GUID used by 2026-06-20 repro
#        All map to -> 00000000-0000-0000-0000-000000000000
#      Scoped to known real GUIDs rather than a wildcard regex, because
#      correlation IDs and revision suffixes are also GUID-shaped but must
#      be preserved for evidence integrity. If a variable is empty, its
#      corresponding rule is skipped (no-op), which keeps this script safe
#      to run in CI environments that do not have the .local file.
#
#   2. Operator home directory path
#        /Users/yeongseonchoe/ -> /Users/demouser/
#      Aligns with the "yeongseon -> demouser" alias rule in AGENTS.md
#      (originally written for Portal screenshots; the same rule applies here
#      because home-directory paths leak the operator's OS username).
#
#   3. Bare operator alias
#        yeongseonchoe -> demouser
#      Catches occurrences that are NOT part of /Users/<alias>/ paths
#      (rule 2 only matches the path form). Order matters: rule 2 runs
#      first, then rule 3 catches the remaining bare occurrences.
#
# Usage:
#   bash scrub-pii.sh           # dry-run, prints what would change
#   bash scrub-pii.sh --apply   # apply changes in-place
#
# Local setup (one-time, for the lab maintainer):
#   mkdir -p ./.local
#   cat > ./.local/pii-values.env <<'EOF'
#   export REAL_SUB_A="<your-primary-subscription-guid>"
#   export REAL_SUB_B="<your-2026-06-20-repro-subscription-guid>"
#   export REAL_TENANT="<your-tenant-guid>"
#   EOF
#   bash scrub-pii.sh --apply

set -euo pipefail

cd "$(dirname "$0")"

MODE="${1:-dry-run}"

# Load real PII values from gitignored local file if it exists.
# Falls back to environment variables; empty values disable the rule.
if [ -f "./.local/pii-values.env" ]; then
  # shellcheck disable=SC1091
  source "./.local/pii-values.env"
fi
REAL_SUB_A="${REAL_SUB_A:-}"
REAL_SUB_B="${REAL_SUB_B:-}"
REAL_TENANT="${REAL_TENANT:-}"
PLACEHOLDER_GUID="00000000-0000-0000-0000-000000000000"
REAL_HOME="/Users/yeongseonchoe/"
PLACEHOLDER_HOME="/Users/demouser/"
REAL_ALIAS="yeongseonchoe"
PLACEHOLDER_ALIAS="demouser"

# Glob targets - skip .local/ (gitignored by design) and this script itself
mapfile -t TARGETS < <(find . -maxdepth 1 \
  \( -name '*.log' -o -name '*.tsv' -o -name '*.txt' -o -name '*.json' \) \
  -type f \
  -not -path './.local/*' \
  | sort)

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No target files found." >&2
  exit 0
fi

total_sub_hits=0
total_tenant_hits=0
total_home_hits=0
total_alias_hits=0

for f in "${TARGETS[@]}"; do
  sub_a_hits=0
  sub_b_hits=0
  tenant_hits=0
  if [ -n "$REAL_SUB_A" ]; then sub_a_hits=$(grep -c "$REAL_SUB_A" "$f" 2>/dev/null || true); fi
  if [ -n "$REAL_SUB_B" ]; then sub_b_hits=$(grep -c "$REAL_SUB_B" "$f" 2>/dev/null || true); fi
  if [ -n "$REAL_TENANT" ]; then tenant_hits=$(grep -c "$REAL_TENANT" "$f" 2>/dev/null || true); fi
  home_hits=$(grep -c "$REAL_HOME" "$f" 2>/dev/null || true)
  alias_hits=$(grep -c "$REAL_ALIAS" "$f" 2>/dev/null || true)
  sub_a_hits=${sub_a_hits:-0}
  sub_b_hits=${sub_b_hits:-0}
  tenant_hits=${tenant_hits:-0}
  home_hits=${home_hits:-0}
  alias_hits=${alias_hits:-0}
  sub_hits=$((sub_a_hits + sub_b_hits))
  # alias_hits includes /Users/<alias>/ matches; subtract home_hits to avoid double-count when reporting
  bare_alias_hits=$((alias_hits - home_hits))
  if [ "$bare_alias_hits" -lt 0 ]; then bare_alias_hits=0; fi

  if [ "$sub_hits" -gt 0 ] || [ "$tenant_hits" -gt 0 ] || [ "$home_hits" -gt 0 ] || [ "$bare_alias_hits" -gt 0 ]; then
    printf "  %-60s sub=%d tenant=%d home=%d alias=%d\n" "$f" "$sub_hits" "$tenant_hits" "$home_hits" "$bare_alias_hits"
    total_sub_hits=$((total_sub_hits + sub_hits))
    total_tenant_hits=$((total_tenant_hits + tenant_hits))
    total_home_hits=$((total_home_hits + home_hits))
    total_alias_hits=$((total_alias_hits + bare_alias_hits))

    if [ "$MODE" = "--apply" ]; then
      # macOS sed -i requires an empty extension argument.
      # Order: home FIRST (so the /Users/<alias>/ form is consumed before the bare-alias rule fires).
      # GUID rules are conditional: each rule is appended only if its REAL_* var is non-empty,
      # so this script never embeds real GUIDs in its own argv even when run in CI.
      sed_args=()
      if [ -n "$REAL_SUB_A" ]; then sed_args+=(-e "s|${REAL_SUB_A}|${PLACEHOLDER_GUID}|g"); fi
      if [ -n "$REAL_SUB_B" ]; then sed_args+=(-e "s|${REAL_SUB_B}|${PLACEHOLDER_GUID}|g"); fi
      if [ -n "$REAL_TENANT" ]; then sed_args+=(-e "s|${REAL_TENANT}|${PLACEHOLDER_GUID}|g"); fi
      sed -i '' "${sed_args[@]}" \
        -e "s|${REAL_HOME}|${PLACEHOLDER_HOME}|g" \
        -e "s|${REAL_ALIAS}|${PLACEHOLDER_ALIAS}|g" \
        "$f"
    fi
  fi
done

echo ""
echo "Total: sub=${total_sub_hits}, tenant=${total_tenant_hits}, home=${total_home_hits}, alias=${total_alias_hits}"
if [ "$MODE" != "--apply" ]; then
  echo "(dry-run; pass --apply to scrub in place)"
else
  echo "(scrub complete; verify with: bash $0 ; expect total=0)"
fi
