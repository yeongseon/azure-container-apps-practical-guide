#!/usr/bin/env bash
# Shell-level regression for Gate 11 sub-gate (d) "verdict_explainable".
#
# Originally contributed as a standalone fix for the absorbed predicate
# `d_verdict_explainable = strong or verdict_overall_pass`, which let a
# verdict.txt reading "Overall: PASS" carry the sub-gate even when the raw
# anchor contradicted it. That defect is now fixed by a tri-state predicate,
# and this script is retained because it exercises the shell entry point
# rather than the Python evaluator: it runs the real verify.sh against
# isolated fixture copies and reads the emitted gate JSON, which is the
# surface an operator actually invokes.
#
# Case 3 deliberately asserts a DIFFERENT outcome from the original
# contribution. That version expected a verdict reading "Overall: FAIL" over
# clean raw to PASS, on the grounds that raw wins. Raw primacy governs what
# the COHORT supports, but this sub-gate asks the narrower question of
# whether the verdict file is explainable from the raw records. A verdict
# that says FAIL while every recomputed check passes is not explainable, so
# it does not pass, and the direction is recorded as raw_contradicts_verdict.

set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ANCHOR="h3-20260614-143432"
failures=0

make_fixture() {
    local dest="$WORK/$1"
    mkdir -p "$dest"
    cp -r "$LAB_DIR"/. "$dest"/
    rm -rf "$dest/tests"
    # Generated gates are removed so an assertion can never read a committed
    # verdict instead of one this run emitted.
    rm -f "$dest"/evidence/1{0,1,2,3}-*-gate.json
    echo "$dest"
}

gate_d_field() {
    python3 - "$1/evidence/11-matrix-coherence-gate.json" "$2" <<'PY'
import json, sys
path, field = sys.argv[1], sys.argv[2]
print(json.load(open(path))["sub_gate_d_verdict_explainable"][field])
PY
}

expect() {
    if [ "$2" == "$3" ]; then
        echo "  ok    $1 = $2"
    else
        echo "  FAIL  $1 = $2 (expected $3)"
        failures=$((failures + 1))
    fi
}

echo "=== case 1: pristine cohort ==="
d1="$(make_fixture baseline)"; rc=0; bash "$d1/verify.sh" >"$d1/run.log" 2>&1 || rc=$?
expect "exit code" "$rc" "0"
expect "d_pass" "$(gate_d_field "$d1" d_pass)" "True"
expect "d_evidence_level" "$(gate_d_field "$d1" d_evidence_level)" "Observed"
expect "verdict_contradicts_raw" "$(gate_d_field "$d1" verdict_contradicts_raw)" "False"
expect "raw_contradicts_verdict" "$(gate_d_field "$d1" raw_contradicts_verdict)" "False"

echo "=== case 2: verdict says PASS, raw contradicts it ==="
d2="$(make_fixture contradict)"
python3 - "$d2/evidence/$ANCHOR.jsonl" <<'PY'
import json, sys
path = sys.argv[1]
records = [json.loads(line) for line in open(path) if line.strip()]
records[1]["uptime_seconds"], records[2]["uptime_seconds"] = (
    records[2]["uptime_seconds"], records[1]["uptime_seconds"])
open(path, "w").writelines(json.dumps(r) + "\n" for r in records)
PY
grep -qx "Overall: PASS" "$d2/evidence/$ANCHOR.verdict.txt" || { echo "  FAIL  precondition"; failures=$((failures+1)); }
rc=0; bash "$d2/verify.sh" >"$d2/run.log" 2>&1 || rc=$?
expect "exit code" "$rc" "1"
expect "d_pass" "$(gate_d_field "$d2" d_pass)" "False"
expect "d_evidence_level" "$(gate_d_field "$d2" d_evidence_level)" "Refuted"
expect "verdict_contradicts_raw" "$(gate_d_field "$d2" verdict_contradicts_raw)" "True"

echo "=== case 3: raw is clean, verdict says FAIL (unexplained disagreement) ==="
d3="$(make_fixture rawwins)"
sed -i 's/^Overall: PASS$/Overall: FAIL/' "$d3/evidence/$ANCHOR.verdict.txt"
rc=0; bash "$d3/verify.sh" >"$d3/run.log" 2>&1 || rc=$?
expect "all_four_checks_recomputable" "$(gate_d_field "$d3" all_four_checks_recomputable)" "True"
expect "verdict_overall_pass" "$(gate_d_field "$d3" verdict_overall_pass)" "False"
expect "raw_contradicts_verdict" "$(gate_d_field "$d3" raw_contradicts_verdict)" "True"
expect "d_pass" "$(gate_d_field "$d3" d_pass)" "False"

echo ""
if [ "$failures" -eq 0 ]; then
    echo "test_verify_verdict_explainable: all assertions passed"
else
    echo "test_verify_verdict_explainable: $failures assertion(s) FAILED"
    exit 1
fi
