#!/usr/bin/env bash
# PII scrub for Stage B evidence files.
#
# Applies the AGENTS.md PII policy to all *.log / *.tsv / *.txt files in this
# directory. Idempotent - safe to re-run as new evidence files are added.
#
# Scrub rules (mirrors Portal capture PII_RULES in scripts/portal-capture-helpers.js,
# adapted for plaintext logs):
#
#   1. Azure subscription / tenant / object / resource GUID
#        75ad149b-d193-4aad-b02b-573802921f9e (this lab's real sub)
#        -> 00000000-0000-0000-0000-000000000000
#      We intentionally scope to the known real GUID rather than a wildcard
#      GUID regex, because correlation IDs and revision suffixes are also
#      GUID-shaped but must be preserved for evidence integrity.
#
#   2. Operator home directory path
#        /Users/yeongseonchoe/ -> /Users/demouser/
#      Aligns with the "yeongseon -> demouser" alias rule in AGENTS.md
#      (originally written for Portal screenshots; the same rule applies here
#      because home-directory paths leak the operator's OS username).
#
# Usage:
#   bash scrub-pii.sh           # dry-run, prints what would change
#   bash scrub-pii.sh --apply   # apply changes in-place

set -euo pipefail

cd "$(dirname "$0")"

MODE="${1:-dry-run}"

REAL_SUB="75ad149b-d193-4aad-b02b-573802921f9e"
PLACEHOLDER_SUB="00000000-0000-0000-0000-000000000000"
REAL_HOME="/Users/yeongseonchoe/"
PLACEHOLDER_HOME="/Users/demouser/"

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
total_home_hits=0

for f in "${TARGETS[@]}"; do
  sub_hits=$(grep -c "$REAL_SUB" "$f" 2>/dev/null || true)
  home_hits=$(grep -c "$REAL_HOME" "$f" 2>/dev/null || true)
  sub_hits=${sub_hits:-0}
  home_hits=${home_hits:-0}

  if [ "$sub_hits" -gt 0 ] || [ "$home_hits" -gt 0 ]; then
    printf "  %-50s sub=%d home=%d\n" "$f" "$sub_hits" "$home_hits"
    total_sub_hits=$((total_sub_hits + sub_hits))
    total_home_hits=$((total_home_hits + home_hits))

    if [ "$MODE" = "--apply" ]; then
      # macOS sed -i requires an empty extension argument
      sed -i '' \
        -e "s|${REAL_SUB}|${PLACEHOLDER_SUB}|g" \
        -e "s|${REAL_HOME}|${PLACEHOLDER_HOME}|g" \
        "$f"
    fi
  fi
done

echo ""
echo "Total: sub=${total_sub_hits}, home=${total_home_hits}"
if [ "$MODE" != "--apply" ]; then
  echo "(dry-run; pass --apply to scrub in place)"
else
  echo "(scrub complete; verify with: bash $0 ; expect total=0)"
fi
