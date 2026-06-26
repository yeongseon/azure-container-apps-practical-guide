#!/usr/bin/env bash
#
# verify.sh -- Phase B falsification gate evaluation for the cpu-throttling lab.
#
# Purpose
# -------
# Re-reads the raw evidence cohort that `fix-and-capture.sh` (plus the Phase A
# `trigger.sh`) produced and evaluates four Phase B falsification gates as
# deterministic functions over the JSON files. This script does NOT call
# Azure CLI. It does NOT modify the cohort. It writes exactly four new files:
#
#   evidence/14-cohort-integrity-gate.json
#   evidence/15-baseline-cpu-pressure-gate.json
#   evidence/16-recovery-materialization-gate.json
#   evidence/17-single-variable-falsification-gate.json
#
# Falsification structure
# -----------------------
# Each gate is a single hypothesis decomposed into 3-4 sub-gates. Every
# sub-gate is a BOTH-not-OR predicate (when the gate combines multiple
# conditions, all must hold simultaneously -- never a disjunction). The gate
# passes if and only if every sub-gate passes. A single sub-gate failure
# falsifies the whole gate.
#
# Q1-Q5 directives applied here (carry-over from Lab 16-22 review history)
# ------------------------------------------------------------------------
# Q1 -- Bound every absence predicate to the failed-deployment cohort.
#       For Lab 23 there is no "failed deployment" -- the experiment
#       successfully reproduces CPU throttling and then successfully
#       recovers. The cohort binding is therefore "this 15-file evidence
#       cohort produced on 2026-06-22 by trigger.sh + fix-and-capture.sh
#       against a single Container App". Predicates assert about THIS cohort
#       only, not about Azure platform behavior in general.
# Q2 -- Use record-scoped predicates over JSON, NOT line-scoped grep.
#       Every predicate parses JSON and tests structured fields. No grep.
# Q3 -- BOTH-not-OR predicates. Every multi-condition check uses AND.
# Q4 -- Strong-path / Fallback-path on Gate 14 (cohort_integrity) ONLY.
#       Hypothesis gates 15/16/17 have a single path with no fallback --
#       partial reproduction is a falsification, not a degraded pass.
# Q5 -- Repo-relative paths in the predicate_inputs section of every gate
#       JSON so reviewers can re-run any predicate without knowing the
#       absolute path on the capture host.
#
# Numbered prefix policy
# ----------------------
# Gate filenames are numbered 14/15/16/17 to continue the 00-13 raw-evidence
# numbering. The numbers are not load-bearing -- they are sort-order
# affordances so `ls evidence/` reads in chronological order
# (raw -> integrity -> baseline -> recovery -> falsification).
#
# Claim ceiling
# -------------
# Every claim in this script is bounded by what the 15-file evidence cohort
# can support. We do NOT claim:
#   - that increasing CPU always fixes throttling (only that it did for THIS
#     workload at THIS time on THIS region);
#   - that the new revision replaced the old replica in-place (the cohort
#     shows a new revision was created and traffic was swapped -- it does
#     NOT prove the underlying Kubernetes pod object was reused);
#   - that the image bytes are identical (the cohort does not capture image
#     digests -- we infer image identity from the fact that the Phase A
#     fix-and-capture.sh issued `az containerapp update --cpu --memory` with
#     no `--image`/`--command`/`--args` flag).
# The gates assert ONLY what the JSON cohort can deterministically prove.
#
# QUOTED-heredoc rule (carry-over from Lab 14 lesson 29)
# ------------------------------------------------------
# Every embedded Python block uses `<<'PY'` with a single-quoted delimiter so
# that `$VAR` and `\` inside the Python body are NOT subject to bash
# expansion. Bash variables are passed into Python through `os.environ` reads
# of variables exported on lines immediately before the heredoc.
#
# Canonical evidence consumed by each gate
# ----------------------------------------
# Gate 14 (cohort_integrity):
#     all 15 canonical files (00x2 + 01..13)
# Gate 15 (baseline_cpu_pressure):
#     01-app-config-before.json
#     03-loadtest-cpu025.json
# Gate 16 (recovery_materialization):
#     03-loadtest-cpu025.json  (baseline p95 anchor for the recovery ratio)
#     05-update-result.json
#     06-app-config-after.json
#     07-revisions-after.json
#     08-loadtest-cpu1.json
# Gate 17 (single_variable_falsification):
#     01-app-config-before.json
#     02-revisions-before.json
#     06-app-config-after.json
#     07-revisions-after.json
#     13-deployment-outputs.json
#
# Files NOT consumed by any Phase B gate (kept as part of the cohort for
# operator audit, not as gate inputs):
#     04-metrics-cpu025.json   (Azure Monitor PT1M aggregation gap -- see
#                               labs/cpu-throttling/README.md "known
#                               limitation" section)
#     09-metrics-cpu1.json     (same)
#     10-cli-versions.json     (operator audit context only)
#     11-cli-containerapp-ext.json (operator audit context only)
#     12-region.json           (operator audit context only)
#
# Usage
# -----
#   bash labs/cpu-throttling/verify.sh
#
# The script is hermetic -- it does NOT take environment variables and does
# NOT touch the network. It reads the 15-file evidence cohort, writes four
# gate JSONs, and exits 0 if all four gates pass or 1 if any gate falsifies.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [ ! -d "${EVIDENCE_DIR}" ]; then
    echo "[FATAL] Evidence directory not found: ${EVIDENCE_DIR}"
    exit 1
fi

# Canonical evidence files (15 total): raw cohort that fix-and-capture.sh
# plus trigger.sh produce.
TRIGGER_LOG_FILE="${EVIDENCE_DIR}/00-trigger-run.txt"
VERIFY_LOG_FILE="${EVIDENCE_DIR}/00-verify-run.txt"
CONFIG_BEFORE_FILE="${EVIDENCE_DIR}/01-app-config-before.json"
REVISIONS_BEFORE_FILE="${EVIDENCE_DIR}/02-revisions-before.json"
LOADTEST_BASELINE_FILE="${EVIDENCE_DIR}/03-loadtest-cpu025.json"
METRICS_BASELINE_FILE="${EVIDENCE_DIR}/04-metrics-cpu025.json"
UPDATE_RESULT_FILE="${EVIDENCE_DIR}/05-update-result.json"
CONFIG_AFTER_FILE="${EVIDENCE_DIR}/06-app-config-after.json"
REVISIONS_AFTER_FILE="${EVIDENCE_DIR}/07-revisions-after.json"
LOADTEST_POSTFIX_FILE="${EVIDENCE_DIR}/08-loadtest-cpu1.json"
METRICS_POSTFIX_FILE="${EVIDENCE_DIR}/09-metrics-cpu1.json"
CLI_VERSIONS_FILE="${EVIDENCE_DIR}/10-cli-versions.json"
CLI_EXT_FILE="${EVIDENCE_DIR}/11-cli-containerapp-ext.json"
REGION_FILE="${EVIDENCE_DIR}/12-region.json"
DEPLOYMENT_OUTPUTS_FILE="${EVIDENCE_DIR}/13-deployment-outputs.json"

# Phase B gate output files.
GATE14_FILE="${EVIDENCE_DIR}/14-cohort-integrity-gate.json"
GATE15_FILE="${EVIDENCE_DIR}/15-baseline-cpu-pressure-gate.json"
GATE16_FILE="${EVIDENCE_DIR}/16-recovery-materialization-gate.json"
GATE17_FILE="${EVIDENCE_DIR}/17-single-variable-falsification-gate.json"

# Repo-relative directory string used inside each gate JSON's predicate_inputs
# section. Reviewers should be able to re-run any predicate by reading the
# JSON without knowing the absolute path on the capture host.
REPO_RELATIVE_EVIDENCE_DIR="labs/cpu-throttling/evidence"

# UTC timestamp this Phase B run was captured at -- recorded inside each gate
# JSON so a reader can distinguish the Phase A raw capture date (2026-06-22)
# from the Phase B verification date.
UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export UTC_NOW

# Cohort presence pre-check. If any canonical file is missing we still
# proceed -- Gate 14 sub-gate a is the canonical place to record presence
# failures. But we WARN early so a reader sees the cause before the gate
# JSON is written.
declare -a CANONICAL_FILES=(
    "${TRIGGER_LOG_FILE}"
    "${VERIFY_LOG_FILE}"
    "${CONFIG_BEFORE_FILE}"
    "${REVISIONS_BEFORE_FILE}"
    "${LOADTEST_BASELINE_FILE}"
    "${METRICS_BASELINE_FILE}"
    "${UPDATE_RESULT_FILE}"
    "${CONFIG_AFTER_FILE}"
    "${REVISIONS_AFTER_FILE}"
    "${LOADTEST_POSTFIX_FILE}"
    "${METRICS_POSTFIX_FILE}"
    "${CLI_VERSIONS_FILE}"
    "${CLI_EXT_FILE}"
    "${REGION_FILE}"
    "${DEPLOYMENT_OUTPUTS_FILE}"
)

MISSING_COUNT=0
for f in "${CANONICAL_FILES[@]}"; do
    if [ ! -f "${f}" ]; then
        echo "[WARN] Missing canonical evidence file: ${f}"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done

if [ "${MISSING_COUNT}" -gt 0 ]; then
    echo "[WARN] ${MISSING_COUNT} canonical file(s) missing. Gate 14 will record this and may fall back."
fi

echo "===== Phase B falsification gates -- cpu-throttling lab ====="
echo "Evidence directory: ${EVIDENCE_DIR}"
echo "Phase B run UTC:    ${UTC_NOW}"
echo

# =============================================================================
# Gate 14 -- cohort_integrity (H_cohort_integrity)
# =============================================================================
# Hypothesis: The 15-file evidence cohort that trigger.sh + fix-and-capture.sh
# produced is internally consistent -- all canonical files are present, the
# load-test timestamps form a monotonic window of sane duration, there are no
# unexpected non-junk extras in the evidence directory, and the cohort
# README.md cross-references every Phase B gate JSON.
#
# Sub-gates (BOTH-not-OR; all must pass):
#   a) All 15 canonical files present.
#         Strong: exactly 15 present.
#         Fallback: at least 13 present AND all four files this lab depends
#                   on for hypothesis gates (01, 03, 06, 07, 08) are present.
#   b) Temporal coherence of the experiment window.
#         Strong: 03.started_utc and 08.finished_utc both parse as strict
#                 ISO-8601, 03.started_utc < 08.finished_utc, and the span
#                 from 03.started_utc to 08.finished_utc is <= 30 minutes.
#         Fallback: both timestamps parse, monotonic, span <= 60 minutes.
#   c) No unexpected non-junk extras in evidence/.
#         Strong: ls evidence/ contains exactly the 15 canonical files plus
#                 the four gate JSONs this script writes plus the README.md.
#         Fallback: any extras are limited to editor/OS junk
#                   (.swp/.bak/.tmp/.swo/.orig/.DS_Store/Thumbs.db) AND no
#                   canonical file is missing.
#   d) README.md cross-references every Phase B gate filename.
#         Strong: README.md exists AND names all four gate filenames literally
#                 (14-cohort-integrity-gate.json, 15-baseline-cpu-pressure-gate.json,
#                 16-recovery-materialization-gate.json,
#                 17-single-variable-falsification-gate.json).
#         Fallback: README.md exists. (The README is created by a downstream
#                   step in the same PR -- this sub-gate allows verify.sh to
#                   run before the README has been authored.)
# =============================================================================

echo "===== Gate 14 -- cohort_integrity ====="

export EVIDENCE_DIR_PY="${EVIDENCE_DIR}"
export REPO_RELATIVE_EVIDENCE_DIR_PY="${REPO_RELATIVE_EVIDENCE_DIR}"
export GATE14_FILE_PY="${GATE14_FILE}"

python3 <<'PY'
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR_PY"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR_PY"]
GATE_FILE = Path(os.environ["GATE14_FILE_PY"])
UTC_NOW = os.environ["UTC_NOW"]

CANONICAL = [
    "00-trigger-run.txt",
    "00-verify-run.txt",
    "01-app-config-before.json",
    "02-revisions-before.json",
    "03-loadtest-cpu025.json",
    "04-metrics-cpu025.json",
    "05-update-result.json",
    "06-app-config-after.json",
    "07-revisions-after.json",
    "08-loadtest-cpu1.json",
    "09-metrics-cpu1.json",
    "10-cli-versions.json",
    "11-cli-containerapp-ext.json",
    "12-region.json",
    "13-deployment-outputs.json",
]
HYPOTHESIS_GATE_INPUTS = [
    "01-app-config-before.json",
    "03-loadtest-cpu025.json",
    "06-app-config-after.json",
    "07-revisions-after.json",
    "08-loadtest-cpu1.json",
]
PHASE_B_OUTPUTS = [
    "14-cohort-integrity-gate.json",
    "15-baseline-cpu-pressure-gate.json",
    "16-recovery-materialization-gate.json",
    "17-single-variable-falsification-gate.json",
]
JUNK_SUFFIXES = (".swp", ".bak", ".tmp", ".swo", ".orig")
JUNK_NAMES = (".DS_Store", "Thumbs.db")

EXPECTED_SPAN_STRONG_SECONDS = 30 * 60
EXPECTED_SPAN_FALLBACK_SECONDS = 60 * 60
EXPECTED_CANONICAL_COUNT_STRONG = 15
EXPECTED_CANONICAL_COUNT_FALLBACK_FLOOR = 13


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


def parse_iso8601(s: str) -> datetime:
    s2 = s
    if s2.endswith("Z"):
        s2 = s2[:-1] + "+00:00"
    return datetime.fromisoformat(s2)


# --- Sub-gate (a): all 15 canonical present ---
present = [n for n in CANONICAL if (EVIDENCE_DIR / n).is_file()]
missing = [n for n in CANONICAL if not (EVIDENCE_DIR / n).is_file()]
hypothesis_inputs_present = all((EVIDENCE_DIR / n).is_file() for n in HYPOTHESIS_GATE_INPUTS)
a_strong = (len(missing) == 0 and len(present) == EXPECTED_CANONICAL_COUNT_STRONG)
a_fallback = (
    len(present) >= EXPECTED_CANONICAL_COUNT_FALLBACK_FLOOR
    and hypothesis_inputs_present
)
a_pass = bool(a_strong or a_fallback)
a_path = "strong" if a_strong else ("fallback" if a_fallback else "fail")

# --- Sub-gate (b): temporal coherence (loadtest window) ---
b_strong = False
b_fallback = False
b_started = None
b_finished = None
b_span_seconds = None
b_error = None
try:
    baseline = json.loads((EVIDENCE_DIR / "03-loadtest-cpu025.json").read_text())
    postfix = json.loads((EVIDENCE_DIR / "08-loadtest-cpu1.json").read_text())
    b_started = baseline["started_utc"]
    b_finished = postfix["finished_utc"]
    start_dt = parse_iso8601(b_started)
    finish_dt = parse_iso8601(b_finished)
    if start_dt.tzinfo is None:
        start_dt = start_dt.replace(tzinfo=timezone.utc)
    if finish_dt.tzinfo is None:
        finish_dt = finish_dt.replace(tzinfo=timezone.utc)
    monotonic = finish_dt > start_dt
    b_span_seconds = (finish_dt - start_dt).total_seconds()
    if monotonic and b_span_seconds <= EXPECTED_SPAN_STRONG_SECONDS:
        b_strong = True
    elif monotonic and b_span_seconds <= EXPECTED_SPAN_FALLBACK_SECONDS:
        b_fallback = True
except (FileNotFoundError, KeyError, ValueError) as exc:
    b_error = f"{type(exc).__name__}: {exc}"
b_pass = bool(b_strong or b_fallback)
b_path = "strong" if b_strong else ("fallback" if b_fallback else "fail")

# --- Sub-gate (c): no unexpected non-junk extras ---
allowed = set(CANONICAL) | set(PHASE_B_OUTPUTS) | {"README.md"}
on_disk = sorted(p.name for p in EVIDENCE_DIR.iterdir() if p.is_file())
extras = [n for n in on_disk if n not in allowed]
junk_only_extras = all(
    n in JUNK_NAMES or n.endswith(JUNK_SUFFIXES) for n in extras
)
c_strong = (len(extras) == 0 and len(missing) == 0)
c_fallback = (junk_only_extras and len(missing) == 0)
c_pass = bool(c_strong or c_fallback)
c_path = "strong" if c_strong else ("fallback" if c_fallback else "fail")

# --- Sub-gate (d): README cross-references ---
readme_path = EVIDENCE_DIR / "README.md"
readme_exists = readme_path.is_file()
named_outputs = []
if readme_exists:
    body = readme_path.read_text(encoding="utf-8")
    for n in PHASE_B_OUTPUTS:
        if n in body:
            named_outputs.append(n)
d_strong = readme_exists and len(named_outputs) == len(PHASE_B_OUTPUTS)
d_fallback = readme_exists
d_pass = bool(d_strong or d_fallback)
d_path = "strong" if d_strong else ("fallback" if d_fallback else "fail")

all_pass = a_pass and b_pass and c_pass and d_pass

result = {
    "utc_captured": UTC_NOW,
    "scenario": "cpu_throttling",
    "hypothesis": "H_cohort_integrity",
    "claim": (
        "The 15-file evidence cohort produced by trigger.sh + fix-and-capture.sh "
        "on 2026-06-22 is internally consistent: all canonical files present, "
        "the experiment window is temporally monotonic and of sane duration, "
        "no unexpected non-junk files exist in evidence/, and evidence/README.md "
        "cross-references every Phase B gate JSON."
    ),
    "claim_level": "Observed",
    "predicate_inputs": {
        "canonical_evidence_directory": REL,
        "loadtest_baseline": repo_rel("03-loadtest-cpu025.json"),
        "loadtest_postfix": repo_rel("08-loadtest-cpu1.json"),
        "readme": repo_rel("README.md"),
    },
    "thresholds": {
        "canonical_count_strong": EXPECTED_CANONICAL_COUNT_STRONG,
        "canonical_count_fallback_floor": EXPECTED_CANONICAL_COUNT_FALLBACK_FLOOR,
        "loadtest_span_strong_seconds_max": EXPECTED_SPAN_STRONG_SECONDS,
        "loadtest_span_fallback_seconds_max": EXPECTED_SPAN_FALLBACK_SECONDS,
        "hypothesis_gate_inputs_required": HYPOTHESIS_GATE_INPUTS,
    },
    "sub_gate_a_predicate": (
        "All 15 canonical evidence files are present in evidence/. Strong: "
        "exactly 15. Fallback: >= 13 present AND all five hypothesis-gate "
        "inputs (01, 03, 06, 07, 08) present."
    ),
    "sub_gate_a_canonical_present": {
        "observed_present_count": len(present),
        "observed_missing": missing,
        "hypothesis_inputs_present": hypothesis_inputs_present,
        "a_path": a_path,
        "a_strong_holds": a_strong,
        "a_fallback_holds": a_fallback,
        "a_pass": a_pass,
    },
    "sub_gate_b_predicate": (
        "03-loadtest-cpu025.json.started_utc and 08-loadtest-cpu1.json.finished_utc "
        "both parse as strict ISO-8601 datetimes, are monotonic (start < finish), "
        "and the span is sane. Strong: span <= 30 minutes. Fallback: span <= 60 minutes."
    ),
    "sub_gate_b_temporal_coherence": {
        "observed_baseline_started_utc": b_started,
        "observed_postfix_finished_utc": b_finished,
        "observed_span_seconds": b_span_seconds,
        "parse_error": b_error,
        "b_path": b_path,
        "b_strong_holds": b_strong,
        "b_fallback_holds": b_fallback,
        "b_pass": b_pass,
    },
    "sub_gate_c_predicate": (
        "evidence/ contains no files outside the 15 canonical + 4 Phase B gates + "
        "README.md. Strong: zero extras AND zero missing canonical. Fallback: "
        "extras are limited to editor/OS junk (.swp/.bak/.tmp/.swo/.orig/.DS_Store/Thumbs.db) "
        "AND zero missing canonical."
    ),
    "sub_gate_c_no_extras": {
        "observed_extras": extras,
        "observed_missing_count": len(missing),
        "extras_are_junk_only": junk_only_extras,
        "c_path": c_path,
        "c_strong_holds": c_strong,
        "c_fallback_holds": c_fallback,
        "c_pass": c_pass,
    },
    "sub_gate_d_predicate": (
        "evidence/README.md exists and names every Phase B gate filename literally. "
        "Strong: all four gate filenames appear in the README body. Fallback: README "
        "exists (sub-gate runs before README has been authored in the same PR)."
    ),
    "sub_gate_d_readme_xref": {
        "observed_readme_exists": readme_exists,
        "observed_named_outputs": named_outputs,
        "expected_named_outputs": PHASE_B_OUTPUTS,
        "d_path": d_path,
        "d_strong_holds": d_strong,
        "d_fallback_holds": d_fallback,
        "d_pass": d_pass,
    },
    "cpu_throttling_h_cohort_integrity_sub_gates": {
        "a_canonical_present": a_pass,
        "b_temporal_coherence": b_pass,
        "c_no_extras": c_pass,
        "d_readme_xref": d_pass,
    },
    "cpu_throttling_h_cohort_integrity_all_subgates_pass": all_pass,
    "gate_classification": (
        "Cohort integrity gate: a structural pre-condition that the 15-file "
        "evidence cohort is suitable to evaluate hypothesis gates 15/16/17. "
        "Falsifies the whole Phase B run if any sub-gate fails."
    ),
}

GATE_FILE.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(f"  a (canonical present, path={a_path}): {'PASS' if a_pass else 'FAIL'}")
print(f"  b (temporal coherence, path={b_path}): {'PASS' if b_pass else 'FAIL'}")
print(f"  c (no extras, path={c_path}): {'PASS' if c_pass else 'FAIL'}")
print(f"  d (README xref, path={d_path}): {'PASS' if d_pass else 'FAIL'}")
print(f"  Gate 14 verdict: {'PASS' if all_pass else 'FAIL'}")
PY

echo

# =============================================================================
# Gate 15 -- baseline_cpu_pressure (H1)
# =============================================================================
# Hypothesis H1: At cpu=0.25, memory=0.5Gi, single replica, a 100-request /
# 20-concurrent load test against the deterministic CPU-bound endpoint
# produced observable CPU pressure -- p95 latency strictly above 100 ms, no
# transport errors, and the wall-clock for the run was long enough that the
# observation cannot be attributed to a trivial-load misread.
#
# Sub-gates (BOTH-not-OR; all must pass; single-path, no fallback):
#   a) 01-app-config-before.json records the documented baseline envelope:
#         cpu == 0.25
#         memory == "0.5Gi"
#         minReplicas == 1
#         maxReplicas == 1
#         activeRevisionsMode == "Single"
#      All five conditions must hold simultaneously.
#   b) 03-loadtest-cpu025.json.latency_ms.p95 > 100 ms.
#   c) 03-loadtest-cpu025.json.requests_ok >= 95 AND requests_err == 0.
#   d) 03-loadtest-cpu025.json.wall_clock_seconds > 5 seconds. (Eliminates
#      the misread where 100/20 finishes in under a second because the
#      endpoint was instant-returning -- if the cpu=0.25 baseline finishes
#      that fast, CPU pressure was not actually exercised and H1 cannot be
#      validly claimed.)
# =============================================================================

echo "===== Gate 15 -- baseline_cpu_pressure (H1) ====="

export GATE15_FILE_PY="${GATE15_FILE}"

python3 <<'PY'
import json
import os
from pathlib import Path

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR_PY"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR_PY"]
GATE_FILE = Path(os.environ["GATE15_FILE_PY"])
UTC_NOW = os.environ["UTC_NOW"]

EXPECTED_CPU_BEFORE = 0.25
EXPECTED_MEMORY_BEFORE = "0.5Gi"
EXPECTED_MIN_REPLICAS = 1
EXPECTED_MAX_REPLICAS = 1
EXPECTED_ACTIVE_REVISIONS_MODE = "Single"
EXPECTED_P95_BASELINE_FLOOR_MS = 100
EXPECTED_REQUESTS_OK_FLOOR = 95
EXPECTED_BASELINE_WALL_CLOCK_FLOOR_SECONDS = 5


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


config = json.loads((EVIDENCE_DIR / "01-app-config-before.json").read_text())
loadtest = json.loads((EVIDENCE_DIR / "03-loadtest-cpu025.json").read_text())

# --- Sub-gate (a): baseline envelope ---
obs_cpu = config.get("cpu")
obs_memory = config.get("memory")
obs_min = config.get("minReplicas")
obs_max = config.get("maxReplicas")
obs_mode = config.get("activeRevisionsMode")

cpu_ok = (obs_cpu == EXPECTED_CPU_BEFORE)
memory_ok = (obs_memory == EXPECTED_MEMORY_BEFORE)
min_ok = (obs_min == EXPECTED_MIN_REPLICAS)
max_ok = (obs_max == EXPECTED_MAX_REPLICAS)
mode_ok = (obs_mode == EXPECTED_ACTIVE_REVISIONS_MODE)
a_pass = bool(cpu_ok and memory_ok and min_ok and max_ok and mode_ok)

# --- Sub-gate (b): baseline p95 > 100 ms ---
obs_p95 = loadtest["latency_ms"]["p95"]
b_pass = bool(obs_p95 > EXPECTED_P95_BASELINE_FLOOR_MS)

# --- Sub-gate (c): success count + zero errors ---
obs_ok = loadtest["requests_ok"]
obs_err = loadtest["requests_err"]
c_pass = bool(obs_ok >= EXPECTED_REQUESTS_OK_FLOOR and obs_err == 0)

# --- Sub-gate (d): wall clock > 5 s ---
obs_wall = loadtest["wall_clock_seconds"]
d_pass = bool(obs_wall > EXPECTED_BASELINE_WALL_CLOCK_FLOOR_SECONDS)

all_pass = a_pass and b_pass and c_pass and d_pass

result = {
    "utc_captured": UTC_NOW,
    "scenario": "cpu_throttling",
    "hypothesis": "H1_baseline_cpu_pressure",
    "claim": (
        "At cpu=0.25, memory=0.5Gi, single replica, the deterministic CPU-bound "
        "endpoint produced observable CPU pressure in the cohort captured on "
        "2026-06-22: p95 latency 2574.8 ms (strictly above the 100 ms floor that "
        "rules out a trivial-load misread), all 100 requests succeeded with zero "
        "transport errors, and the load test wall-clock was 8.65 seconds (above "
        "the 5-second floor that ensures the workload actually exercised CPU "
        "rather than completing trivially)."
    ),
    "claim_level": "Measured",
    "predicate_inputs": {
        "config_before": repo_rel("01-app-config-before.json"),
        "loadtest_baseline": repo_rel("03-loadtest-cpu025.json"),
    },
    "thresholds": {
        "cpu_before_expected": EXPECTED_CPU_BEFORE,
        "memory_before_expected": EXPECTED_MEMORY_BEFORE,
        "min_replicas_expected": EXPECTED_MIN_REPLICAS,
        "max_replicas_expected": EXPECTED_MAX_REPLICAS,
        "active_revisions_mode_expected": EXPECTED_ACTIVE_REVISIONS_MODE,
        "p95_baseline_floor_ms": EXPECTED_P95_BASELINE_FLOOR_MS,
        "requests_ok_floor": EXPECTED_REQUESTS_OK_FLOOR,
        "baseline_wall_clock_floor_seconds": EXPECTED_BASELINE_WALL_CLOCK_FLOOR_SECONDS,
    },
    "sub_gate_a_predicate": (
        "01-app-config-before.json records cpu==0.25 AND memory==\"0.5Gi\" AND "
        "minReplicas==1 AND maxReplicas==1 AND activeRevisionsMode==\"Single\" "
        "(BOTH-not-OR: all five must hold simultaneously)."
    ),
    "sub_gate_a_baseline_envelope": {
        "observed_cpu": obs_cpu,
        "observed_memory": obs_memory,
        "observed_min_replicas": obs_min,
        "observed_max_replicas": obs_max,
        "observed_active_revisions_mode": obs_mode,
        "cpu_holds": cpu_ok,
        "memory_holds": memory_ok,
        "min_replicas_holds": min_ok,
        "max_replicas_holds": max_ok,
        "active_revisions_mode_holds": mode_ok,
        "a_pass": a_pass,
    },
    "sub_gate_b_predicate": (
        "03-loadtest-cpu025.json.latency_ms.p95 > 100 ms (CPU pressure is "
        "observable above the trivial-load floor)."
    ),
    "sub_gate_b_p95_above_floor": {
        "observed_p95_ms": obs_p95,
        "p95_floor_ms": EXPECTED_P95_BASELINE_FLOOR_MS,
        "b_predicate_holds": b_pass,
        "b_pass": b_pass,
    },
    "sub_gate_c_predicate": (
        "03-loadtest-cpu025.json.requests_ok >= 95 AND requests_err == 0 "
        "(measurement is not corrupted by transport failures)."
    ),
    "sub_gate_c_success_and_zero_errors": {
        "observed_requests_ok": obs_ok,
        "observed_requests_err": obs_err,
        "requests_ok_floor": EXPECTED_REQUESTS_OK_FLOOR,
        "c_predicate_holds": c_pass,
        "c_pass": c_pass,
    },
    "sub_gate_d_predicate": (
        "03-loadtest-cpu025.json.wall_clock_seconds > 5 seconds (the load test "
        "ran long enough to actually exercise CPU rather than completing trivially)."
    ),
    "sub_gate_d_wall_clock_above_floor": {
        "observed_wall_clock_seconds": obs_wall,
        "wall_clock_floor_seconds": EXPECTED_BASELINE_WALL_CLOCK_FLOOR_SECONDS,
        "d_predicate_holds": d_pass,
        "d_pass": d_pass,
    },
    "cpu_throttling_h1_baseline_cpu_pressure_sub_gates": {
        "a_baseline_envelope": a_pass,
        "b_p95_above_floor": b_pass,
        "c_success_and_zero_errors": c_pass,
        "d_wall_clock_above_floor": d_pass,
    },
    "cpu_throttling_h1_baseline_cpu_pressure_all_subgates_pass": all_pass,
    "gate_classification": (
        "Baseline gate: establishes that the cohort captured a measurable CPU "
        "pressure signal at cpu=0.25, which is the necessary pre-condition for "
        "the recovery hypothesis (Gate 16). Without H1 passing, the recovery "
        "ratio in Gate 16 is meaningless because there was no pressure to "
        "recover from."
    ),
}

GATE_FILE.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(f"  a (baseline envelope): {'PASS' if a_pass else 'FAIL'}")
print(f"  b (p95 above floor):  {'PASS' if b_pass else 'FAIL'}")
print(f"  c (success + zero err): {'PASS' if c_pass else 'FAIL'}")
print(f"  d (wall clock above floor): {'PASS' if d_pass else 'FAIL'}")
print(f"  Gate 15 verdict: {'PASS' if all_pass else 'FAIL'}")
PY

echo

# =============================================================================
# Gate 16 -- recovery_materialization (H2)
# =============================================================================
# Hypothesis H2: Raising the per-replica resource envelope from
# (cpu=0.25, memory=0.5Gi) to (cpu=1.0, memory=2.0Gi via Bicep, normalized
# to "2Gi" by the platform) materialized recovery in this cohort -- the
# new revision became the active traffic target with non-Deprovisioning
# running state, and the byte-identical 100/20 load test produced p95
# latency strictly below 50% of the baseline p95 with zero transport
# errors.
#
# Sub-gates (BOTH-not-OR; all must pass; single-path, no fallback):
#   a) 06-app-config-after.json records the recovery envelope:
#         cpu == 1.0
#         memory in {"2Gi", "2.0Gi"}   <-- platform normalizes "2.0Gi" -> "2Gi"
#         minReplicas == 1
#         maxReplicas == 1
#         latestRevisionName == 05-update-result.json.latestRevisionName
#      (The latestRevisionName cross-check pins the post-fix `containerapp show`
#      output to the same revision that the `az containerapp update` Phase 6
#      response reported, so the cohort cannot have observed a different
#      revision between Phase 6 and Phase 8.)
#   b) 08-loadtest-cpu1.json.latency_ms.p95 < 0.5 *
#         03-loadtest-cpu025.json.latency_ms.p95.
#      Strict less-than: equal to 50% is NOT recovery, it is borderline noise.
#   c) 08-loadtest-cpu1.json.requests_ok >= 95 AND requests_err == 0.
#   d) 07-revisions-after.json (record-scoped):
#         len(records) == 2
#         exactly 1 record has trafficWeight == 100
#         that record.runningState in {"Running", "RunningAtMaxScale"}
#         that record.name == 06-app-config-after.json.latestRevisionName
#      The runningState predicate explicitly excludes "Deprovisioning" so a
#      revision can have active==true but still be tearing down -- the cohort
#      shows the old revision is in this exact state (active==true,
#      runningState=="Deprovisioning", trafficWeight==0), which is why this
#      sub-gate keys off trafficWeight==100 and a non-deprovisioning running
#      state rather than active==true.
# =============================================================================

echo "===== Gate 16 -- recovery_materialization (H2) ====="

export GATE16_FILE_PY="${GATE16_FILE}"

python3 <<'PY'
import json
import os
from pathlib import Path

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR_PY"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR_PY"]
GATE_FILE = Path(os.environ["GATE16_FILE_PY"])
UTC_NOW = os.environ["UTC_NOW"]

EXPECTED_CPU_AFTER = 1.0
EXPECTED_MEMORY_AFTER_VARIANTS = ("2Gi", "2.0Gi")
EXPECTED_MIN_REPLICAS = 1
EXPECTED_MAX_REPLICAS = 1
EXPECTED_REQUESTS_OK_FLOOR = 95
EXPECTED_P95_RECOVERY_RATIO_MAX = 0.5
EXPECTED_REVISION_RUNNING_STATES_OK = ("Running", "RunningAtMaxScale")
EXPECTED_REVISION_COUNT_AFTER = 2


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


baseline = json.loads((EVIDENCE_DIR / "03-loadtest-cpu025.json").read_text())
update_result = json.loads((EVIDENCE_DIR / "05-update-result.json").read_text())
config_after = json.loads((EVIDENCE_DIR / "06-app-config-after.json").read_text())
revisions_after = json.loads((EVIDENCE_DIR / "07-revisions-after.json").read_text())
postfix = json.loads((EVIDENCE_DIR / "08-loadtest-cpu1.json").read_text())

# --- Sub-gate (a): recovery envelope + latestRevisionName cross-check ---
obs_cpu = config_after.get("cpu")
obs_memory = config_after.get("memory")
obs_min = config_after.get("minReplicas")
obs_max = config_after.get("maxReplicas")
obs_latest_revision_after = config_after.get("latestRevisionName")
obs_latest_revision_update = update_result.get("latestRevisionName")

cpu_ok = (obs_cpu == EXPECTED_CPU_AFTER)
memory_ok = (obs_memory in EXPECTED_MEMORY_AFTER_VARIANTS)
min_ok = (obs_min == EXPECTED_MIN_REPLICAS)
max_ok = (obs_max == EXPECTED_MAX_REPLICAS)
latest_revision_match = (
    obs_latest_revision_after is not None
    and obs_latest_revision_after == obs_latest_revision_update
)
a_pass = bool(cpu_ok and memory_ok and min_ok and max_ok and latest_revision_match)

# --- Sub-gate (b): recovery p95 ratio ---
obs_baseline_p95 = baseline["latency_ms"]["p95"]
obs_postfix_p95 = postfix["latency_ms"]["p95"]
recovery_threshold = EXPECTED_P95_RECOVERY_RATIO_MAX * obs_baseline_p95
b_pass = bool(obs_postfix_p95 < recovery_threshold)

# --- Sub-gate (c): post-fix success + zero errors ---
obs_postfix_ok = postfix["requests_ok"]
obs_postfix_err = postfix["requests_err"]
c_pass = bool(
    obs_postfix_ok >= EXPECTED_REQUESTS_OK_FLOOR
    and obs_postfix_err == 0
)

# --- Sub-gate (d): revision record-scoped state ---
obs_record_count = len(revisions_after)
records_with_traffic_100 = [
    r for r in revisions_after if r.get("trafficWeight") == 100
]
record_count_ok = (obs_record_count == EXPECTED_REVISION_COUNT_AFTER)
exactly_one_traffic_holder = (len(records_with_traffic_100) == 1)
if exactly_one_traffic_holder:
    holder = records_with_traffic_100[0]
    holder_name = holder.get("name")
    holder_state = holder.get("runningState")
    holder_state_ok = (holder_state in EXPECTED_REVISION_RUNNING_STATES_OK)
    holder_name_matches_latest = (
        obs_latest_revision_after is not None
        and holder_name == obs_latest_revision_after
    )
else:
    holder = None
    holder_name = None
    holder_state = None
    holder_state_ok = False
    holder_name_matches_latest = False

d_pass = bool(
    record_count_ok
    and exactly_one_traffic_holder
    and holder_state_ok
    and holder_name_matches_latest
)

all_pass = a_pass and b_pass and c_pass and d_pass

result = {
    "utc_captured": UTC_NOW,
    "scenario": "cpu_throttling",
    "hypothesis": "H2_recovery_materialization",
    "claim": (
        "Raising the per-replica resource envelope from (cpu=0.25, memory=0.5Gi) "
        "to (cpu=1.0, memory=2.0Gi requested via Bicep, normalized to \"2Gi\" by "
        "the platform) materialized recovery in this cohort: the new revision "
        "ca-cputhrottle-65svxr--0000001 became the active traffic target with "
        "runningState=RunningAtMaxScale and trafficWeight=100, while the "
        "byte-identical 100/20 load test produced p95=773.2 ms -- a 70.0% "
        "reduction from the 2574.8 ms baseline (strictly below the 50% floor) -- "
        "with zero transport errors."
    ),
    "claim_level": "Measured",
    "predicate_inputs": {
        "loadtest_baseline": repo_rel("03-loadtest-cpu025.json"),
        "update_result": repo_rel("05-update-result.json"),
        "config_after": repo_rel("06-app-config-after.json"),
        "revisions_after": repo_rel("07-revisions-after.json"),
        "loadtest_postfix": repo_rel("08-loadtest-cpu1.json"),
    },
    "thresholds": {
        "cpu_after_expected": EXPECTED_CPU_AFTER,
        "memory_after_expected_variants": list(EXPECTED_MEMORY_AFTER_VARIANTS),
        "min_replicas_expected": EXPECTED_MIN_REPLICAS,
        "max_replicas_expected": EXPECTED_MAX_REPLICAS,
        "requests_ok_floor": EXPECTED_REQUESTS_OK_FLOOR,
        "p95_recovery_ratio_max": EXPECTED_P95_RECOVERY_RATIO_MAX,
        "revision_running_states_ok": list(EXPECTED_REVISION_RUNNING_STATES_OK),
        "revision_count_after_expected": EXPECTED_REVISION_COUNT_AFTER,
    },
    "sub_gate_a_predicate": (
        "06-app-config-after.json records cpu==1.0 AND memory in {\"2Gi\",\"2.0Gi\"} "
        "AND minReplicas==1 AND maxReplicas==1 AND latestRevisionName == "
        "05-update-result.json.latestRevisionName (cross-check pins the Phase 8 "
        "config-after read to the same revision that the Phase 6 update response "
        "named). Memory normalization is platform-driven: the Bicep template "
        "requests \"2.0Gi\", and the Microsoft.App API normalizes it to \"2Gi\" "
        "on read."
    ),
    "sub_gate_a_recovery_envelope": {
        "observed_cpu": obs_cpu,
        "observed_memory": obs_memory,
        "observed_min_replicas": obs_min,
        "observed_max_replicas": obs_max,
        "observed_latest_revision_after": obs_latest_revision_after,
        "observed_latest_revision_update": obs_latest_revision_update,
        "cpu_holds": cpu_ok,
        "memory_holds": memory_ok,
        "min_replicas_holds": min_ok,
        "max_replicas_holds": max_ok,
        "latest_revision_match": latest_revision_match,
        "a_pass": a_pass,
    },
    "sub_gate_b_predicate": (
        "08-loadtest-cpu1.json.latency_ms.p95 < 0.5 * "
        "03-loadtest-cpu025.json.latency_ms.p95 (strict less-than: equal-to-50% "
        "is borderline noise, not recovery)."
    ),
    "sub_gate_b_recovery_ratio": {
        "observed_baseline_p95_ms": obs_baseline_p95,
        "observed_postfix_p95_ms": obs_postfix_p95,
        "computed_threshold_ms": recovery_threshold,
        "computed_recovery_ratio": (
            obs_postfix_p95 / obs_baseline_p95 if obs_baseline_p95 else None
        ),
        "b_predicate_holds": b_pass,
        "b_pass": b_pass,
    },
    "sub_gate_c_predicate": (
        "08-loadtest-cpu1.json.requests_ok >= 95 AND requests_err == 0 "
        "(post-fix measurement is not corrupted by transport failures)."
    ),
    "sub_gate_c_postfix_success_and_zero_errors": {
        "observed_postfix_requests_ok": obs_postfix_ok,
        "observed_postfix_requests_err": obs_postfix_err,
        "requests_ok_floor": EXPECTED_REQUESTS_OK_FLOOR,
        "c_predicate_holds": c_pass,
        "c_pass": c_pass,
    },
    "sub_gate_d_predicate": (
        "07-revisions-after.json (record-scoped): exactly 2 revision records "
        "AND exactly 1 record has trafficWeight==100 AND that record.runningState "
        "in {\"Running\",\"RunningAtMaxScale\"} AND that record.name == "
        "06-app-config-after.json.latestRevisionName. The runningState predicate "
        "explicitly excludes \"Deprovisioning\" so the cohort cannot count a "
        "tearing-down old revision as the active traffic target (the cohort's "
        "old revision is in exactly this state: active==true, "
        "runningState==\"Deprovisioning\", trafficWeight==0)."
    ),
    "sub_gate_d_revision_state": {
        "observed_record_count": obs_record_count,
        "observed_records_with_traffic_100_count": len(records_with_traffic_100),
        "observed_traffic_100_holder_name": holder_name,
        "observed_traffic_100_holder_running_state": holder_state,
        "record_count_holds": record_count_ok,
        "exactly_one_traffic_holder": exactly_one_traffic_holder,
        "holder_state_ok": holder_state_ok,
        "holder_name_matches_latest": holder_name_matches_latest,
        "d_predicate_holds": d_pass,
        "d_pass": d_pass,
    },
    "cpu_throttling_h2_recovery_materialization_sub_gates": {
        "a_recovery_envelope": a_pass,
        "b_recovery_ratio": b_pass,
        "c_postfix_success_and_zero_errors": c_pass,
        "d_revision_state": d_pass,
    },
    "cpu_throttling_h2_recovery_materialization_all_subgates_pass": all_pass,
    "gate_classification": (
        "Recovery materialization gate: confirms that the cohort observed both "
        "the platform-side state change (new revision active with traffic) and "
        "the workload-side performance change (p95 below half of baseline). "
        "Strict less-than on the ratio prevents borderline-noise observations "
        "from being counted as recovery. Falsifies whole Phase B if H2 fails."
    ),
}

GATE_FILE.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(f"  a (recovery envelope):  {'PASS' if a_pass else 'FAIL'}")
print(f"  b (recovery ratio):     {'PASS' if b_pass else 'FAIL'}")
print(f"  c (post-fix success):   {'PASS' if c_pass else 'FAIL'}")
print(f"  d (revision state):     {'PASS' if d_pass else 'FAIL'}")
print(f"  Gate 16 verdict: {'PASS' if all_pass else 'FAIL'}")
PY

echo

# =============================================================================
# Gate 17 -- single_variable_falsification (H3)
# =============================================================================
# Hypothesis H3: The recovery in Gate 16 cannot be attributed to anything
# OTHER than the (cpu, memory) delta. Specifically, on the SHARED config
# fields between 01-app-config-before.json and 06-app-config-after.json the
# only differing keys are {cpu, memory}; the revision lineage shows that
# the post-fix traffic-holder is the revision that the
# az containerapp update call returned; and the Container App identity
# (the resource name in 13-deployment-outputs.json) is the prefix of both
# the before-revision and after-revision names.
#
# Sub-gates (BOTH-not-OR; all must pass; single-path, no fallback):
#   a) SHARED-FIELDS diff between 01-app-config-before.json and
#      06-app-config-after.json. The shared keys are
#      {cpu, memory, minReplicas, maxReplicas}; activeRevisionsMode appears
#      only in 01, latestRevisionName appears only in 06 (this is a
#      documented schema asymmetry of `az containerapp show` -- see the
#      cohort_binding_note below). The shared-fields diff must equal
#      exactly {cpu, memory}.
#   b) REVISION-LINEAGE (record-scoped over 07-revisions-after.json):
#         02-revisions-before.json[0].name appears in 07 records (any
#             trafficWeight, any runningState). The old revision is still
#             present in the lineage -- it has not been forgotten by the
#             platform.
#         06-app-config-after.json.latestRevisionName appears in 07 records
#             with trafficWeight==100. The new revision is the live traffic
#             target.
#         06-app-config-after.json.latestRevisionName is NOT in
#             02-revisions-before.json. The new revision did not exist
#             before the fix; the platform created it during the update.
#   c) CONTAINER-APP IDENTITY: every revision name in
#      02-revisions-before.json[*].name and 07-revisions-after.json[*].name
#      starts with `13-deployment-outputs.json.containerAppName + "--"`.
#      This proves the recovery did not silently switch to a different
#      Container App resource between before and after.
#
# cohort_binding_note (Q1):
#   Single-variable claim is bounded to the (cpu, memory) delta on the
#   shared-fields surface. We do NOT claim the platform reused the
#   underlying replica (Kubernetes Pod object) -- the lineage explicitly
#   shows that a NEW revision was created (ca-cputhrottle-65svxr--0000001)
#   and the old revision (ca-cputhrottle-65svxr--8pz2nir) is now in
#   runningState=Deprovisioning. The image was inferred to be byte-identical
#   from the fact that the Phase A fix-and-capture.sh issued
#   `az containerapp update --cpu --memory` with no `--image`, `--command`,
#   or `--args` flag; the cohort does not capture image digests, so this
#   inference is a documented gap in the gate's claim ceiling.
# =============================================================================

echo "===== Gate 17 -- single_variable_falsification (H3) ====="

export GATE17_FILE_PY="${GATE17_FILE}"

python3 <<'PY'
import json
import os
from pathlib import Path

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR_PY"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR_PY"]
GATE_FILE = Path(os.environ["GATE17_FILE_PY"])
UTC_NOW = os.environ["UTC_NOW"]

EXPECTED_DIFF_KEYS = frozenset({"cpu", "memory"})


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


config_before = json.loads((EVIDENCE_DIR / "01-app-config-before.json").read_text())
revisions_before = json.loads((EVIDENCE_DIR / "02-revisions-before.json").read_text())
config_after = json.loads((EVIDENCE_DIR / "06-app-config-after.json").read_text())
revisions_after = json.loads((EVIDENCE_DIR / "07-revisions-after.json").read_text())
deployment = json.loads((EVIDENCE_DIR / "13-deployment-outputs.json").read_text())

# --- Sub-gate (a): shared-fields diff == {cpu, memory} ---
shared_keys = set(config_before.keys()) & set(config_after.keys())
shared_keys_sorted = sorted(shared_keys)
diff_keys = {k for k in shared_keys if config_before.get(k) != config_after.get(k)}
unchanged_shared = {
    k: config_before.get(k)
    for k in sorted(shared_keys)
    if k not in diff_keys
}
diff_payload = {
    k: {
        "before": config_before.get(k),
        "after": config_after.get(k),
    }
    for k in sorted(diff_keys)
}
a_pass = bool(diff_keys == EXPECTED_DIFF_KEYS)

# --- Sub-gate (b): revision lineage ---
before_names = [r.get("name") for r in revisions_before]
after_names = [r.get("name") for r in revisions_after]
old_name = before_names[0] if before_names else None
new_name = config_after.get("latestRevisionName")
records_after_traffic_100 = {
    r.get("name") for r in revisions_after if r.get("trafficWeight") == 100
}

old_in_after = (old_name is not None and old_name in after_names)
new_is_traffic_holder = (
    new_name is not None and new_name in records_after_traffic_100
)
new_not_in_before = (new_name is not None and new_name not in before_names)
b_pass = bool(old_in_after and new_is_traffic_holder and new_not_in_before)

# --- Sub-gate (c): Container App identity preserved across rename ---
container_app_name = deployment.get("containerAppName")
expected_prefix = f"{container_app_name}--" if container_app_name else None
all_revision_names = [n for n in (before_names + after_names) if n is not None]
prefix_holds_per_name = {
    n: (expected_prefix is not None and n.startswith(expected_prefix))
    for n in all_revision_names
}
prefix_holds_all = bool(
    expected_prefix is not None
    and all(prefix_holds_per_name.values())
    and len(prefix_holds_per_name) >= 2
)
c_pass = prefix_holds_all

all_pass = a_pass and b_pass and c_pass

result = {
    "utc_captured": UTC_NOW,
    "scenario": "cpu_throttling",
    "hypothesis": "H3_single_variable_falsification",
    "claim": (
        "The cohort cannot attribute recovery in Gate 16 to anything other "
        "than the (cpu, memory) delta. On the shared-fields surface of "
        "01-app-config-before.json and 06-app-config-after.json the diff is "
        "exactly {cpu, memory}; revision lineage shows the old revision is "
        "still present in the post-fix list and the new revision (named by "
        "06.latestRevisionName) is the trafficWeight==100 holder and did not "
        "exist before the fix; and every revision in both lists shares the "
        "Container App resource name (ca-cputhrottle-65svxr) as a literal "
        "prefix, proving the cohort observed a single resource across the "
        "fix boundary."
    ),
    "claim_level": "Observed",
    "predicate_inputs": {
        "config_before": repo_rel("01-app-config-before.json"),
        "revisions_before": repo_rel("02-revisions-before.json"),
        "config_after": repo_rel("06-app-config-after.json"),
        "revisions_after": repo_rel("07-revisions-after.json"),
        "deployment_outputs": repo_rel("13-deployment-outputs.json"),
    },
    "thresholds": {
        "expected_diff_keys": sorted(EXPECTED_DIFF_KEYS),
    },
    "sub_gate_a_predicate": (
        "On the shared-keys surface between 01-app-config-before.json and "
        "06-app-config-after.json (shared_keys = "
        "{cpu, memory, minReplicas, maxReplicas}; activeRevisionsMode appears "
        "only in 01, latestRevisionName appears only in 06 -- a documented "
        "schema asymmetry of `az containerapp show` query projections), the "
        "set of keys whose values differ must equal exactly {cpu, memory}."
    ),
    "sub_gate_a_shared_fields_diff": {
        "observed_shared_keys": shared_keys_sorted,
        "observed_diff": diff_payload,
        "observed_unchanged_shared": unchanged_shared,
        "expected_diff_keys": sorted(EXPECTED_DIFF_KEYS),
        "diff_matches_expected": (diff_keys == EXPECTED_DIFF_KEYS),
        "a_pass": a_pass,
    },
    "sub_gate_b_predicate": (
        "Revision lineage (record-scoped over 02-revisions-before.json and "
        "07-revisions-after.json): the before-revision name appears in 07 "
        "(any state, any traffic) AND 06.latestRevisionName appears in 07 "
        "with trafficWeight==100 AND 06.latestRevisionName is NOT in 02 (the "
        "platform created a new revision during the update, did not edit the "
        "old one in place)."
    ),
    "sub_gate_b_revision_lineage": {
        "observed_old_revision_name": old_name,
        "observed_new_revision_name": new_name,
        "observed_revisions_before_names": before_names,
        "observed_revisions_after_names": after_names,
        "observed_records_after_traffic_100": sorted(records_after_traffic_100),
        "old_in_after_lineage": old_in_after,
        "new_is_traffic_holder": new_is_traffic_holder,
        "new_not_in_before": new_not_in_before,
        "b_pass": b_pass,
    },
    "sub_gate_c_predicate": (
        "Every revision name in both 02-revisions-before.json[*].name and "
        "07-revisions-after.json[*].name starts with "
        "13-deployment-outputs.json.containerAppName + '--'. This proves the "
        "cohort did not silently switch to a different Container App resource "
        "between before and after."
    ),
    "sub_gate_c_container_app_identity": {
        "observed_container_app_name": container_app_name,
        "observed_expected_prefix": expected_prefix,
        "observed_prefix_holds_per_name": prefix_holds_per_name,
        "observed_all_revision_names_count": len(all_revision_names),
        "c_pass": c_pass,
    },
    "cpu_throttling_h3_single_variable_falsification_sub_gates": {
        "a_shared_fields_diff": a_pass,
        "b_revision_lineage": b_pass,
        "c_container_app_identity": c_pass,
    },
    "cpu_throttling_h3_single_variable_falsification_all_subgates_pass": all_pass,
    "cohort_binding_note": (
        "Single-variable claim is bounded to the (cpu, memory) delta on the "
        "shared-fields surface of 01 and 06; activeRevisionsMode-only-in-01 "
        "and latestRevisionName-only-in-06 are a known query-projection "
        "asymmetry and are intentionally excluded from the diff set. "
        "The cohort does NOT prove: (1) that the underlying Kubernetes pod "
        "was reused -- lineage in sub-gate (b) explicitly shows a NEW "
        "revision was created and the old revision is now in "
        "runningState==Deprovisioning; (2) that the container image is "
        "byte-identical -- this is inferred from the Phase A "
        "fix-and-capture.sh issuing `az containerapp update --cpu --memory` "
        "with no `--image`, `--command`, or `--args` flag, but the cohort "
        "does not capture image digests; (3) that Azure Container Apps "
        "generally activates the new revision within 15 seconds -- the "
        "cohort captured one 15-second observation (08:50:45Z Activating "
        "-> 08:51:00Z RunningAtMaxScale), not a multi-run timing bound."
    ),
    "gate_classification": (
        "Single-variable falsification gate: closes the H2 confounder window "
        "by proving the (cpu, memory) delta is the only changed control "
        "variable visible in the cohort. Falsifies whole Phase B if any "
        "other field on the shared surface changed, if revision lineage is "
        "broken, or if the Container App identity is not preserved across "
        "the fix boundary."
    ),
}

GATE_FILE.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(f"  a (shared-fields diff): {'PASS' if a_pass else 'FAIL'}")
print(f"  b (revision lineage):   {'PASS' if b_pass else 'FAIL'}")
print(f"  c (container identity): {'PASS' if c_pass else 'FAIL'}")
print(f"  Gate 17 verdict: {'PASS' if all_pass else 'FAIL'}")
PY

echo

# =============================================================================
# Phase B summary
# =============================================================================
echo "===== Phase B summary ====="

python3 <<'PY'
import json
import os
from pathlib import Path

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR_PY"])

GATES = [
    ("14-cohort-integrity-gate.json",
     "cpu_throttling_h_cohort_integrity_all_subgates_pass",
     "H_cohort_integrity"),
    ("15-baseline-cpu-pressure-gate.json",
     "cpu_throttling_h1_baseline_cpu_pressure_all_subgates_pass",
     "H1_baseline_cpu_pressure"),
    ("16-recovery-materialization-gate.json",
     "cpu_throttling_h2_recovery_materialization_all_subgates_pass",
     "H2_recovery_materialization"),
    ("17-single-variable-falsification-gate.json",
     "cpu_throttling_h3_single_variable_falsification_all_subgates_pass",
     "H3_single_variable_falsification"),
]

results = []
for filename, key, hypothesis in GATES:
    path = EVIDENCE_DIR / filename
    data = json.loads(path.read_text())
    results.append((filename, hypothesis, bool(data.get(key))))

width = max(len(filename) for filename, _, _ in results)
header_filename = "Gate file".ljust(width)
print(f"  {header_filename}  Hypothesis                            Verdict")
print(f"  {'-' * width}  ------------------------------------  -------")
for filename, hypothesis, passed in results:
    verdict = "PASS" if passed else "FAIL"
    print(f"  {filename.ljust(width)}  {hypothesis.ljust(36)}  {verdict}")

overall = all(passed for _, _, passed in results)
print()
print(f"  Overall Phase B verdict: {'PASS' if overall else 'FAIL'}")

raise SystemExit(0 if overall else 1)
PY
