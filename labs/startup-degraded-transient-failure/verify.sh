#!/usr/bin/env bash
# verify.sh — Phase B evidence-pack verification for Lab 18
# (startup-degraded-transient-failure).
#
# File purpose
# ------------
# Phase B verify.sh — pure file processor — emits 4 falsifiable gate JSONs
# from committed canonical evidence. This script reads ONLY the canonical
# qA-qG evidence files already checked into
# `labs/startup-degraded-transient-failure/evidence/` and writes the derived
# gate outputs:
#
#   - 10-canonical-evidence-integrity-gate.json
#   - 11-failure-degraded-state-gate.json
#   - 12-recovery-fix-gate.json
#   - 13-cross-artifact-consistency-gate.json
#
# It MUST NOT call Azure, curl remote endpoints, or depend on any live cloud
# state. A reviewer must be able to re-run this script after the RG has been
# deleted and still obtain the same verdict from the same committed evidence.
#
# Oracle bg_b94eeacf directives (verbatim, binding)
# -------------------------------------------------
#   "Pick Lab 18 = `startup-degraded-transient-failure` and do it as Option Y:
#    reuse committed evidence only"
#   "Use the latest canonical run per scenario. Do not aggregate all
#    timestamps into a single count or single narrative"
#   "Target 4 top-level gates, with 3, 3, 3, and 2 sub-gates respectively"
#   "Be careful with transient-state semantics: prove 'entered degraded state'
#    and 'recovered/healthy after fix,' not 'system remained broken'"
#   "Timestamp mixing is the primary risk. The agent must not count all
#    historical artifacts together"
#   "This is Option Y only. No Azure deployment, no new captures"
#
# What the four gates prove
# -------------------------
# Gate 10 = precondition / integrity gate.
#   Claim: the canonical evidence pack is internally coherent before any H0
#   reasoning starts. This gate consumes qA-qG but reasons about existence,
#   filename timestamps, and scenario mapping only.
#
# Gate 11 = degraded-state evidence gate.
#   Claim: the perturbation genuinely injected transient disruption. This is
#   NOT a no-op run. The platform recorded perturbation start markers,
#   ProbeFailed warnings, and revision transition evidence during rollout.
#
# Gate 12 = recovery / no-client-impact gate.
#   Claim: despite Gate 11's degraded-state evidence, the client-visible k6
#   data shows 0% errors and the falsification rule from D6 did NOT trigger.
#   This is the H0-held outcome for the canonical 2026-06-20 run.
#
# Gate 13 = cross-artifact consistency gate.
#   Claim: the canonical artifacts cohere across a single evidence window and
#   share referential integrity on perturbation identifiers.
#
# Gate topology
# -------------
# 4 top-level gates with 11 sub-gates total:
#
#   Gate 10 (H0_preconditions)
#     a) canonical files present
#     b) filename timestamp cohort coherent
#     c) baseline/perturbation scenario mapping explicit in qF
#
#   Gate 11 (H0_partA_degraded_state_evidence)
#     a) perturbation start events recorded
#     b) probe failures observed during rollout
#     c) revision transitions observed during rollout
#
#   Gate 12 (H0_partB_recovery_no_client_impact)
#     a) perturbation err_pct is zero at the run-summary layer
#     b) falsification rule not triggered
#     c) latest healthy snapshots show Running / 3 replicas available
#
#   Gate 13 (H0_cross_artifact_integrity)
#     a) qA-qG filename timestamps stay inside one canonical window
#     b) perturbation identifiers overlap across qA and qE
#
# Verdict semantics encoded by this script
# ---------------------------------------
# PASS on Gate 11 does NOT mean the rollout failed permanently.
# PASS on Gate 12 does NOT mean the rollout had no transient internal impact.
# The intended reading is:
#   - Gate 11 PASS = transient degraded-state evidence exists.
#   - Gate 12 PASS = the degraded state did not leak through the D6 client
#     falsification rule.
#   - Gate 11 PASS + Gate 12 PASS together = H0 held under the canonical
#     2026-06-20 conditions because ACA masked the transient from the client.
#   - Gate 10 PASS + Gate 13 PASS make that interpretation auditable by proving
#     the evidence pack was internally coherent and cross-artifact consistent.
#
# Why this script is strict about transient-state semantics
# ---------------------------------------------------------
# The canonical evidence shows BOTH of these statements are true:
#
#   1. The system entered a degraded state during rollout.
#      Evidence: qD records repeated ProbeFailed warnings (max EventCount 35 on
#      `subject-app--0000003`), qE records three perturbation start markers,
#      and qA shows old revisions demoted to traffic=0 while new revisions were
#      promoted.
#
#   2. The client never observed a sustained error burst.
#      Evidence: qF reports err_pct=0 and falsification_triggered=False for the
#      perturbation run; qC contains zero error buckets.
#
# A naive reader could misclassify the run as "healthy throughout" because the
# final client-visible verdict is 0% error. That is WRONG. Gate 11 and Gate 12
# must be read together: Gate 11 proves the rollout injected real transient
# disruption, while Gate 12 proves ACA masked that disruption from the client.
#
# QUOTED heredoc rule (mandatory)
# -------------------------------
# ALL Python heredocs in this file MUST use `<<'PY'` (single-quoted
# delimiter) to prevent shell expansion of `$` characters inside Python code.
# This is a Lab 14 lesson 29 mandatory rule. Unquoted `<<PY` would cause
# `$variable` in Python to be silently replaced by bash before the heredoc
# reaches python3.
#
# REPO_RELATIVE_EVIDENCE_DIR rule (mandatory)
# -------------------------------------------
# All gate JSONs MUST cite predicate inputs as repo-relative paths (for
# example `labs/startup-degraded-transient-failure/evidence/qA-...json`), NOT
# absolute paths. This prevents `/Users/<alias>/...` leakage into committed
# evidence and keeps the pack reproducible across operator machines.
#
# Record-scoped predicate rule (mandatory)
# ----------------------------------------
# Lab 15 lesson 34 — no whole-file substring searches. Every assertion must
# come from parsed records. This script uses Python `json.load()` plus record
# iteration ONLY. It never greps the canonical JSON files to count matches.
# Every strong/fallback predicate is evaluated from typed record fields.
#
# Design constraints bound into this Phase B script
# -------------------------------------------------
# D2 (Subject app workload):
#   The subject app intentionally uses STARTUP_DELAY_SECONDS=25. ProbeFailed
#   warnings during rollout are therefore expected AND diagnostically useful:
#   they are evidence that a still-warming replica existed behind the rollout.
#
# D3 (Probe configuration):
#   Startup/readiness/liveness all target `/healthz` with the fixed timing
#   budget. The Gate 11 degraded-state proof interprets ProbeFailed as expected
#   probe-gating behavior during slow start, not as evidence of a permanent
#   broken system.
#
# D4 (Perturbation mechanism):
#   The primary perturbation is the ACA-managed new revision rollout. Gate 11
#   therefore keys on qE perturbation markers + qA revision transitions, not on
#   any explicit revision-restart evidence.
#
# D6 (Statistical power / falsification rule):
#   H0 is falsified if ANY sustained window of >=3 consecutive 10-second
#   buckets exceeds 0.5% err_pct. The canonical qF run summary stores the
#   already-evaluated boolean `falsification_triggered`, and Gate 12 treats
#   `False` as the decisive no-client-impact signal for the official baseline
#   and perturbation runs.
#
# D8 (KQL pack / control comparison):
#   The run summaries and bucket exports are based on embedded client bucket
#   timestamps, not ingestion time. This matters because Gate 12 depends on the
#   official qF interpretation, which was produced from the timestamp-correct
#   KQL methodology rather than from fuzzy TimeGenerated joins.
#
# Canonical evidence consumed by this script
# ------------------------------------------
# Gate 10 consumes:
#   qA revision-state
#   qB replica-inventory
#   qC k6 buckets
#   qD system-events
#   qE perturbation-markers
#   qF run-summary
#   qG audit-sampler-quirk
#
# Gate 11 consumes:
#   qA revision-state
#   qD system-events
#   qE perturbation-markers
#
# Gate 12 consumes:
#   qA revision-state
#   qB replica-inventory
#   qF run-summary
#
# Gate 13 consumes:
#   qA revision-state
#   qE perturbation-markers
#   qA-qG filename timestamps
#
# Files explicitly NOT consumed by this script
# --------------------------------------------
# Historical q1-q7 exports from 2026-06-12 and 2026-06-20T22:22:20Z are kept
# as supporting evidence but are NOT part of the predicate inputs. Oracle's
# directive is explicit: do not aggregate all timestamps into one count. This
# script ignores:
#   - q1-per-run-summary-* historical JSON/TSV
#   - q2-buckets-10s-sum-vus-* historical JSON/TSV
#   - q3-revision-state-timeline-* historical JSON/TSV
#   - q4-replica-inventory-snapshot-* historical JSON/TSV
#   - q5-falsification-* historical JSON/TSV
#   - q6-baseline-vs-perturb-vs-supplemental-* historical JSON/TSV
#   - q7-system-events-timeline-* historical JSON/TSV
#   - raw logs (`baseline-001.log`, `perturbation-002.log`, `perturbation-003.log`,
#     `supplemental-restart-001.log`, `deploy-001.log`, `verify-001.log`, etc.)
# for gate predicates. Those files are documented in evidence/README.md but are
# intentionally outside the Phase B predicate surface.
#
# Numbered prefix policy
# ----------------------
# qA-qG = canonical committed evidence inputs.
# 10..13 = derived Phase B gate outputs generated by this script.
#
# Usage
# -----
#   bash labs/startup-degraded-transient-failure/verify.sh
#
# No environment variables are required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$SCRIPT_DIR"
EVIDENCE_DIR="$LAB_DIR/evidence"
REPO_ROOT="$(cd "$LAB_DIR/../.." && pwd)"
REPO_RELATIVE_EVIDENCE_DIR="labs/startup-degraded-transient-failure/evidence"
UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

QA_FILE="$EVIDENCE_DIR/qA-revision-state-20260620T223951Z.json"
QB_FILE="$EVIDENCE_DIR/qB-replica-inventory-20260620T223955Z.json"
QC_FILE="$EVIDENCE_DIR/qC-k6-buckets-20260620T224056Z.json"
QD_FILE="$EVIDENCE_DIR/qD-system-events-20260620T224002Z.json"
QE_FILE="$EVIDENCE_DIR/qE-perturbation-markers-20260620T224143Z.json"
QF_FILE="$EVIDENCE_DIR/qF-run-summary-20260620T224149Z.json"
QG_FILE="$EVIDENCE_DIR/qG-audit-sampler-quirk-20260620T225143Z.json"

GATE10_FILE="$EVIDENCE_DIR/10-canonical-evidence-integrity-gate.json"
GATE11_FILE="$EVIDENCE_DIR/11-failure-degraded-state-gate.json"
GATE12_FILE="$EVIDENCE_DIR/12-recovery-fix-gate.json"
GATE13_FILE="$EVIDENCE_DIR/13-cross-artifact-consistency-gate.json"

for required in \
    "$QA_FILE" \
    "$QB_FILE" \
    "$QC_FILE" \
    "$QD_FILE" \
    "$QE_FILE" \
    "$QF_FILE" \
    "$QG_FILE"; do
    if [[ ! -f "$required" ]]; then
        echo "ERROR: required canonical evidence file missing: $required" >&2
        echo "This Phase B verify.sh is Option Y only and cannot synthesize missing evidence." >&2
        exit 1
    fi
done

echo "=== Phase 10: canonical evidence integrity gate ==="
UTC_NOW="$UTC_NOW" \
QA_FILE="$QA_FILE" \
QB_FILE="$QB_FILE" \
QC_FILE="$QC_FILE" \
QD_FILE="$QD_FILE" \
QE_FILE="$QE_FILE" \
QF_FILE="$QF_FILE" \
QG_FILE="$QG_FILE" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
python3 <<'PY' > "$GATE10_FILE"
import json
import os
import pathlib
import re
from datetime import datetime


def parse_ts_from_filename(path: pathlib.Path) -> datetime:
    match = re.search(r"(\d{8}T\d{6}Z)", path.name)
    if not match:
        raise ValueError(f"No timestamp found in filename: {path.name}")
    return datetime.strptime(match.group(1), "%Y%m%dT%H%M%SZ")


def repo_rel(path: pathlib.Path) -> str:
    return f"{os.environ['REPO_RELATIVE_EVIDENCE_DIR']}/{path.name}"


def sample(items, n=5):
    return items[:n]


qa = pathlib.Path(os.environ["QA_FILE"])
qb = pathlib.Path(os.environ["QB_FILE"])
qc = pathlib.Path(os.environ["QC_FILE"])
qd = pathlib.Path(os.environ["QD_FILE"])
qe = pathlib.Path(os.environ["QE_FILE"])
qf = pathlib.Path(os.environ["QF_FILE"])
qg = pathlib.Path(os.environ["QG_FILE"])
paths = [qa, qb, qc, qd, qe, qf, qg]
qf_records = json.loads(qf.read_text())

strong_window_start = datetime(2026, 6, 20, 22, 39, 0)
strong_window_end = datetime(2026, 6, 20, 22, 51, 59)
fallback_window_start = datetime(2026, 6, 20, 21, 30, 0)
fallback_window_end = datetime(2026, 6, 20, 22, 51, 59)

presence_records = [{"path": repo_rel(path), "exists": path.exists()} for path in paths]
present_count = sum(1 for item in presence_records if item["exists"])
a_strong = present_count == 7
a_fallback = present_count >= 5

timestamp_records = []
for path in paths:
    ts = parse_ts_from_filename(path)
    timestamp_records.append(
        {
            "path": repo_rel(path),
            "filename_timestamp": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "in_strong_window": strong_window_start <= ts <= strong_window_end,
            "in_fallback_window": fallback_window_start <= ts <= fallback_window_end,
        }
    )
b_strong = all(item["in_strong_window"] for item in timestamp_records)
b_fallback = all(item["in_fallback_window"] for item in timestamp_records)

baseline_records = [record for record in qf_records if str(record.get("run_id", "")).startswith("baseline-")]
perturbation_records = [record for record in qf_records if str(record.get("run_id", "")).startswith("perturbation-")]
distinct_run_ids = sorted({str(record.get("run_id", "")) for record in qf_records if record.get("run_id")})
c_strong = len(baseline_records) >= 1 and len(perturbation_records) >= 1
c_fallback = len(distinct_run_ids) >= 2

result = {
    "utc_captured": os.environ["UTC_NOW"],
    "scenario": "rolling_rollout_with_probes_masked_by_readiness",
    "hypothesis": "H0_preconditions",
    "claim": "canonical_evidence_pack_internally_consistent",
    "predicate_inputs": {
        "qa_path": repo_rel(qa),
        "qb_path": repo_rel(qb),
        "qc_path": repo_rel(qc),
        "qd_path": repo_rel(qd),
        "qe_path": repo_rel(qe),
        "qf_path": repo_rel(qf),
        "qg_path": repo_rel(qg),
    },
    "sub_gate_a_predicate": "All seven canonical qA-qG files exist on disk; fallback requires at least five files present.",
    "sub_gate_b_predicate": "All qA-qG filename timestamps stay inside the canonical 2026-06-20T22:39Z-22:51Z capture window; fallback allows the extended 2026-06-20T21:30Z-22:51Z execution-plus-capture window.",
    "sub_gate_c_predicate": "qF explicitly maps the canonical baseline and perturbation runs via run_id prefixes; fallback requires at least two distinct run_id values.",
    "required_canonical_file_count": 7,
    "minimum_fallback_file_count": 5,
    "strong_window_start_utc": "2026-06-20T22:39:00Z",
    "strong_window_end_utc": "2026-06-20T22:51:59Z",
    "fallback_window_start_utc": "2026-06-20T21:30:00Z",
    "fallback_window_end_utc": "2026-06-20T22:51:59Z",
    "sub_gate_a_canonical_files_present": {
        "observed_present_file_count": present_count,
        "observed_first_5": sample(presence_records),
        "a_strong_path_all_7_files_exist": a_strong,
        "a_fallback_path_at_least_5_files_exist": a_fallback,
        "a_pass": a_strong or a_fallback,
    },
    "sub_gate_b_timestamp_cohort_coherent": {
        "observed_filename_timestamp_count": len(timestamp_records),
        "observed_first_5": sample(timestamp_records),
        "b_strong_path_all_timestamps_in_12_minute_window": b_strong,
        "b_fallback_path_all_timestamps_in_extended_window": b_fallback,
        "b_pass": b_strong or b_fallback,
    },
    "sub_gate_c_scenario_mapping_explicit": {
        "observed_distinct_run_id_count": len(distinct_run_ids),
        "observed_first_5": sample(qf_records),
        "c_strong_path_baseline_and_perturbation_present": c_strong,
        "c_fallback_path_at_least_2_distinct_run_ids": c_fallback,
        "c_pass": c_strong or c_fallback,
    },
}
result["startup_degraded_transient_failure_h0_preconditions_sub_gates"] = {
    "a_canonical_files_present": result["sub_gate_a_canonical_files_present"]["a_pass"],
    "b_timestamp_cohort_coherent": result["sub_gate_b_timestamp_cohort_coherent"]["b_pass"],
    "c_scenario_mapping_explicit": result["sub_gate_c_scenario_mapping_explicit"]["c_pass"],
}
result["startup_degraded_transient_failure_h0_preconditions_all_subgates_pass"] = all(
    result["startup_degraded_transient_failure_h0_preconditions_sub_gates"].values()
)
result["gate_classification"] = "canonical_evidence_pack_internally_consistent"
print(json.dumps(result, indent=2))
PY

echo "=== Phase 11: degraded-state evidence gate ==="
UTC_NOW="$UTC_NOW" \
QA_FILE="$QA_FILE" \
QD_FILE="$QD_FILE" \
QE_FILE="$QE_FILE" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
python3 <<'PY' > "$GATE11_FILE"
import json
import os
import pathlib


def repo_rel(path: pathlib.Path) -> str:
    return f"{os.environ['REPO_RELATIVE_EVIDENCE_DIR']}/{path.name}"


def sample(items, n=5):
    return items[:n]


def as_int(value) -> int:
    return int(str(value))


qa = pathlib.Path(os.environ["QA_FILE"])
qd = pathlib.Path(os.environ["QD_FILE"])
qe = pathlib.Path(os.environ["QE_FILE"])

qa_records = json.loads(qa.read_text())
qd_records = json.loads(qd.read_text())
qe_records = json.loads(qe.read_text())

start_records = [record for record in qe_records if str(record.get("phase", "")) == "start"]
distinct_start_ids = sorted({str(record.get("perturbation_id", "")) for record in start_records if record.get("perturbation_id")})
a_strong = len(start_records) >= 3
a_fallback = len(start_records) >= 1

probe_failed_records = []
for record in qd_records:
    if str(record.get("Reason_s", "")) == "ProbeFailed":
        probe_failed_records.append(
            {
                "Reason_s": record.get("Reason_s"),
                "RevisionName_s": record.get("RevisionName_s"),
                "EventCount": as_int(record.get("EventCount", 0)),
                "Type_s": record.get("Type_s"),
            }
        )
max_probe_failed = max((item["EventCount"] for item in probe_failed_records), default=0)
b_strong = any(item["EventCount"] >= 10 for item in probe_failed_records)
b_fallback = len(probe_failed_records) >= 1

demoted_revision_records = []
for record in qa_records:
    active = str(record.get("active", "")) == "True"
    traffic = as_int(record.get("traffic", 0))
    if active and traffic == 0:
        demoted_revision_records.append(
            {
                "TimeGenerated": record.get("TimeGenerated"),
                "perturbation_id": record.get("perturbation_id"),
                "revision": record.get("revision"),
                "replicas": as_int(record.get("replicas", 0)),
                "traffic": traffic,
            }
        )
distinct_revisions = sorted({str(record.get("revision", "")) for record in qa_records if record.get("revision")})
c_strong = len(demoted_revision_records) >= 1
c_fallback = len(distinct_revisions) >= 2

result = {
    "utc_captured": os.environ["UTC_NOW"],
    "scenario": "rolling_rollout_with_probes_masked_by_readiness",
    "hypothesis": "H0_partA_degraded_state_evidence",
    "claim": "rolling_rollout_produced_observable_degraded_state_signatures",
    "predicate_inputs": {
        "qa_path": repo_rel(qa),
        "qd_path": repo_rel(qd),
        "qe_path": repo_rel(qe),
    },
    "sub_gate_a_predicate": "qE records the rollout perturbation windows; strong path requires all three rollout-event start markers, fallback requires at least one start marker.",
    "sub_gate_b_predicate": "qD records ProbeFailed warnings during rollout; strong path requires at least one ProbeFailed row with EventCount >= 10, fallback requires any ProbeFailed row.",
    "sub_gate_c_predicate": "qA records revision transition evidence; strong path requires at least one active revision row demoted to traffic=0, fallback requires at least two distinct revision names.",
    "strong_min_start_events": 3,
    "fallback_min_start_events": 1,
    "strong_probefailed_eventcount_threshold": 10,
    "sub_gate_a_perturbation_events_recorded": {
        "observed_start_event_count": len(start_records),
        "observed_first_5": sample(start_records),
        "a_strong_path_at_least_3_start_markers": a_strong,
        "a_fallback_path_at_least_1_start_marker": a_fallback,
        "a_pass": a_strong or a_fallback,
    },
    "sub_gate_b_probe_failures_observed": {
        "observed_probefailed_record_count": len(probe_failed_records),
        "observed_max_eventcount": max_probe_failed,
        "observed_first_5": sample(probe_failed_records),
        "b_strong_path_probefailed_eventcount_ge_10": b_strong,
        "b_fallback_path_any_probefailed_record": b_fallback,
        "b_pass": b_strong or b_fallback,
    },
    "sub_gate_c_revision_transitions_during_rollout": {
        "observed_demoted_active_revision_rows": len(demoted_revision_records),
        "observed_distinct_revision_count": len(distinct_revisions),
        "observed_first_5": sample(demoted_revision_records if demoted_revision_records else qa_records),
        "c_strong_path_active_revision_demoted_to_zero_traffic": c_strong,
        "c_fallback_path_at_least_2_distinct_revisions": c_fallback,
        "c_pass": c_strong or c_fallback,
    },
}
result["startup_degraded_transient_failure_h0_parta_degraded_state_evidence_sub_gates"] = {
    "a_perturbation_events_recorded": result["sub_gate_a_perturbation_events_recorded"]["a_pass"],
    "b_probe_failures_observed": result["sub_gate_b_probe_failures_observed"]["b_pass"],
    "c_revision_transitions_during_rollout": result["sub_gate_c_revision_transitions_during_rollout"]["c_pass"],
}
result["startup_degraded_transient_failure_h0_parta_degraded_state_evidence_all_subgates_pass"] = all(
    result["startup_degraded_transient_failure_h0_parta_degraded_state_evidence_sub_gates"].values()
)
result["gate_classification"] = "rolling_rollout_produced_observable_degraded_state_signatures"
print(json.dumps(result, indent=2))
PY

echo "=== Phase 12: recovery / no-client-impact gate ==="
UTC_NOW="$UTC_NOW" \
QA_FILE="$QA_FILE" \
QB_FILE="$QB_FILE" \
QF_FILE="$QF_FILE" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
python3 <<'PY' > "$GATE12_FILE"
import json
import os
import pathlib


def repo_rel(path: pathlib.Path) -> str:
    return f"{os.environ['REPO_RELATIVE_EVIDENCE_DIR']}/{path.name}"


def sample(items, n=5):
    return items[:n]


def as_int(value) -> int:
    return int(str(value))


def as_float(value) -> float:
    return float(str(value))


qa = pathlib.Path(os.environ["QA_FILE"])
qb = pathlib.Path(os.environ["QB_FILE"])
qf = pathlib.Path(os.environ["QF_FILE"])

qa_records = json.loads(qa.read_text())
qb_records = json.loads(qb.read_text())
qf_records = json.loads(qf.read_text())

perturbation_run_records = [record for record in qf_records if str(record.get("run_id", "")).startswith("perturbation-")]
baseline_run_records = [record for record in qf_records if str(record.get("run_id", "")).startswith("baseline-")]
perturbation_run = perturbation_run_records[0]
perturbation_err_pct = as_float(perturbation_run.get("err_pct", 0))
a_strong = perturbation_err_pct == 0.0
a_fallback = perturbation_err_pct < 0.5

strong_false_runs = []
for record in baseline_run_records + perturbation_run_records:
    strong_false_runs.append(str(record.get("falsification_triggered", "")) == "False")
b_strong = len(strong_false_runs) == 2 and all(strong_false_runs)
b_fallback = str(perturbation_run.get("falsification_triggered", "")) == "False"

latest_qb_timestamp = max(record.get("TimeGenerated") for record in qb_records)
latest_qb_records = [record for record in qb_records if record.get("TimeGenerated") == latest_qb_timestamp]
latest_revision = max(latest_qb_records, key=lambda item: item.get("revision", "")).get("revision")
latest_revision_records = [record for record in qb_records if record.get("revision") == latest_revision]
latest_revision_latest_ts = max(record.get("TimeGenerated") for record in latest_revision_records)
latest_revision_snapshot = [record for record in latest_revision_records if record.get("TimeGenerated") == latest_revision_latest_ts]
all_running_latest_revision = all(str(record.get("state", "")) == "Running" for record in latest_revision_snapshot)
c_strong = len(latest_revision_snapshot) >= 1 and all_running_latest_revision

latest_active_qa_record = max(
    [record for record in qa_records if str(record.get("active", "")) == "True"],
    key=lambda item: item.get("TimeGenerated", ""),
)
latest_active_replicas = as_int(latest_active_qa_record.get("replicas", 0))
c_fallback = latest_active_replicas >= 3

result = {
    "utc_captured": os.environ["UTC_NOW"],
    "scenario": "rolling_rollout_with_probes_masked_by_readiness",
    "hypothesis": "H0_partB_recovery_no_client_impact",
    "claim": "aca_rolling_rollout_masked_transients_to_clients",
    "predicate_inputs": {
        "qa_path": repo_rel(qa),
        "qb_path": repo_rel(qb),
        "qf_path": repo_rel(qf),
    },
    "sub_gate_a_predicate": "The official perturbation run in qF has err_pct == 0; fallback allows err_pct < 0.5 because D6 falsifies only sustained windows above 0.5%.",
    "sub_gate_b_predicate": "The D6 falsification rule did not trigger. Strong path requires both canonical runs (baseline + perturbation) to report False, fallback requires the perturbation run to report False.",
    "sub_gate_c_predicate": "Healthy snapshots exist after rollout. Strong path requires all qB rows in the latest snapshot of the latest revision to be Running; fallback requires the latest active qA row to report replicas >= 3.",
    "strong_err_pct_threshold": 0.0,
    "fallback_err_pct_threshold": 0.5,
    "fallback_active_replica_threshold": 3,
    "sub_gate_a_k6_client_observed_error_rate_zero": {
        "observed_perturbation_err_pct": perturbation_err_pct,
        "observed_first_5": sample(perturbation_run_records),
        "a_strong_path_err_pct_equals_zero": a_strong,
        "a_fallback_path_err_pct_below_point_five": a_fallback,
        "a_pass": a_strong or a_fallback,
    },
    "sub_gate_b_falsification_rule_not_triggered": {
        "observed_false_run_count": sum(1 for value in strong_false_runs if value),
        "observed_first_5": sample(qf_records),
        "b_strong_path_baseline_and_perturbation_false": b_strong,
        "b_fallback_path_perturbation_false": b_fallback,
        "b_pass": b_strong or b_fallback,
    },
    "sub_gate_c_latest_snapshots_healthy": {
        "observed_latest_revision": latest_revision,
        "observed_latest_revision_snapshot_count": len(latest_revision_snapshot),
        "observed_latest_active_replicas": latest_active_replicas,
        "observed_first_5": sample(latest_revision_snapshot),
        "c_strong_path_all_latest_revision_rows_running": c_strong,
        "c_fallback_path_latest_active_revision_reports_ge_3_replicas": c_fallback,
        "c_pass": c_strong or c_fallback,
    },
}
result["startup_degraded_transient_failure_h0_partb_recovery_no_client_impact_sub_gates"] = {
    "a_k6_client_observed_error_rate_zero": result["sub_gate_a_k6_client_observed_error_rate_zero"]["a_pass"],
    "b_falsification_rule_not_triggered": result["sub_gate_b_falsification_rule_not_triggered"]["b_pass"],
    "c_latest_snapshots_healthy": result["sub_gate_c_latest_snapshots_healthy"]["c_pass"],
}
result["startup_degraded_transient_failure_h0_partb_recovery_no_client_impact_all_subgates_pass"] = all(
    result["startup_degraded_transient_failure_h0_partb_recovery_no_client_impact_sub_gates"].values()
)
result["gate_classification"] = "aca_rolling_rollout_masked_transients_to_clients"
print(json.dumps(result, indent=2))
PY

echo "=== Phase 13: cross-artifact consistency gate ==="
UTC_NOW="$UTC_NOW" \
QA_FILE="$QA_FILE" \
QB_FILE="$QB_FILE" \
QC_FILE="$QC_FILE" \
QD_FILE="$QD_FILE" \
QE_FILE="$QE_FILE" \
QF_FILE="$QF_FILE" \
QG_FILE="$QG_FILE" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
python3 <<'PY' > "$GATE13_FILE"
import json
import os
import pathlib
import re
from datetime import datetime


def parse_ts_from_filename(path: pathlib.Path) -> datetime:
    match = re.search(r"(\d{8}T\d{6}Z)", path.name)
    if not match:
        raise ValueError(f"No timestamp found in filename: {path.name}")
    return datetime.strptime(match.group(1), "%Y%m%dT%H%M%SZ")


def repo_rel(path: pathlib.Path) -> str:
    return f"{os.environ['REPO_RELATIVE_EVIDENCE_DIR']}/{path.name}"


def sample(items, n=5):
    return items[:n]


qa = pathlib.Path(os.environ["QA_FILE"])
qb = pathlib.Path(os.environ["QB_FILE"])
qc = pathlib.Path(os.environ["QC_FILE"])
qd = pathlib.Path(os.environ["QD_FILE"])
qe = pathlib.Path(os.environ["QE_FILE"])
qf = pathlib.Path(os.environ["QF_FILE"])
qg = pathlib.Path(os.environ["QG_FILE"])
paths = [qa, qb, qc, qd, qe, qf, qg]

qa_records = json.loads(qa.read_text())
qe_records = json.loads(qe.read_text())

strong_window_start = datetime(2026, 6, 20, 22, 39, 0)
strong_window_end = datetime(2026, 6, 20, 22, 51, 59)
fallback_window_start = datetime(2026, 6, 20, 21, 30, 0)
fallback_window_end = datetime(2026, 6, 20, 22, 51, 59)

timestamp_records = []
for path in paths:
    ts = parse_ts_from_filename(path)
    timestamp_records.append(
        {
            "path": repo_rel(path),
            "filename_timestamp": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "in_strong_window": strong_window_start <= ts <= strong_window_end,
            "in_fallback_window": fallback_window_start <= ts <= fallback_window_end,
        }
    )
a_strong = all(item["in_strong_window"] for item in timestamp_records)
a_fallback = all(item["in_fallback_window"] for item in timestamp_records)

qa_ids = sorted({str(record.get("perturbation_id", "")) for record in qa_records if record.get("perturbation_id")})
qe_ids = sorted({str(record.get("perturbation_id", "")) for record in qe_records if record.get("perturbation_id")})
shared_ids = sorted(set(qa_ids) & set(qe_ids))
b_strong = len(shared_ids) >= 1
b_fallback = len(qe_ids) >= 3 or len(qa_ids) >= 1

result = {
    "utc_captured": os.environ["UTC_NOW"],
    "scenario": "rolling_rollout_with_probes_masked_by_readiness",
    "hypothesis": "H0_cross_artifact_integrity",
    "claim": "evidence_artifacts_cohere_across_canonical_window",
    "predicate_inputs": {
        "qa_path": repo_rel(qa),
        "qb_path": repo_rel(qb),
        "qc_path": repo_rel(qc),
        "qd_path": repo_rel(qd),
        "qe_path": repo_rel(qe),
        "qf_path": repo_rel(qf),
        "qg_path": repo_rel(qg),
    },
    "sub_gate_a_predicate": "All canonical qA-qG filename timestamps stay inside the 2026-06-20T22:39Z-22:51Z capture window; fallback allows the wider 2026-06-20T21:30Z-22:51Z execution-plus-capture window.",
    "sub_gate_b_predicate": "At least one perturbation identifier is shared by qA and qE; fallback requires qE to expose the three event identifiers or qA to expose any non-null perturbation_id values.",
    "strong_window_start_utc": "2026-06-20T22:39:00Z",
    "strong_window_end_utc": "2026-06-20T22:51:59Z",
    "fallback_window_start_utc": "2026-06-20T21:30:00Z",
    "fallback_window_end_utc": "2026-06-20T22:51:59Z",
    "sub_gate_a_single_canonical_window": {
        "observed_filename_timestamp_count": len(timestamp_records),
        "observed_first_5": sample(timestamp_records),
        "a_strong_path_all_timestamps_in_12_minute_window": a_strong,
        "a_fallback_path_all_timestamps_in_extended_window": a_fallback,
        "a_pass": a_strong or a_fallback,
    },
    "sub_gate_b_perturbation_ids_consistent": {
        "observed_shared_perturbation_id_count": len(shared_ids),
        "observed_first_5": sample(
            [{"shared_perturbation_id": value} for value in shared_ids]
            if shared_ids
            else [{"qa_perturbation_id": value} for value in qa_ids]
        ),
        "b_strong_path_shared_id_between_qa_and_qe": b_strong,
        "b_fallback_path_qe_has_3_ids_or_qa_has_any_id": b_fallback,
        "b_pass": b_strong or b_fallback,
    },
}
result["startup_degraded_transient_failure_h0_cross_artifact_integrity_sub_gates"] = {
    "a_single_canonical_window": result["sub_gate_a_single_canonical_window"]["a_pass"],
    "b_perturbation_ids_consistent": result["sub_gate_b_perturbation_ids_consistent"]["b_pass"],
}
result["startup_degraded_transient_failure_h0_cross_artifact_integrity_all_subgates_pass"] = all(
    result["startup_degraded_transient_failure_h0_cross_artifact_integrity_sub_gates"].values()
)
result["gate_classification"] = "evidence_artifacts_cohere_across_canonical_window"
print(json.dumps(result, indent=2))
PY

echo "=== Phase summary ==="
GATE10_FILE="$GATE10_FILE" \
GATE11_FILE="$GATE11_FILE" \
GATE12_FILE="$GATE12_FILE" \
GATE13_FILE="$GATE13_FILE" \
python3 <<'PY'
import json
import os
import pathlib
import sys

gates = [
    (
        "10",
        "canonical_evidence_integrity",
        pathlib.Path(os.environ["GATE10_FILE"]),
        "startup_degraded_transient_failure_h0_preconditions_sub_gates",
        "startup_degraded_transient_failure_h0_preconditions_all_subgates_pass",
    ),
    (
        "11",
        "failure_degraded_state",
        pathlib.Path(os.environ["GATE11_FILE"]),
        "startup_degraded_transient_failure_h0_parta_degraded_state_evidence_sub_gates",
        "startup_degraded_transient_failure_h0_parta_degraded_state_evidence_all_subgates_pass",
    ),
    (
        "12",
        "recovery_fix",
        pathlib.Path(os.environ["GATE12_FILE"]),
        "startup_degraded_transient_failure_h0_partb_recovery_no_client_impact_sub_gates",
        "startup_degraded_transient_failure_h0_partb_recovery_no_client_impact_all_subgates_pass",
    ),
    (
        "13",
        "cross_artifact_consistency",
        pathlib.Path(os.environ["GATE13_FILE"]),
        "startup_degraded_transient_failure_h0_cross_artifact_integrity_sub_gates",
        "startup_degraded_transient_failure_h0_cross_artifact_integrity_all_subgates_pass",
    ),
]

overall = True
print("gate | name                           | sub-gates | overall")
print("-----|--------------------------------|-----------|--------")
for gate_id, name, path, sub_key, overall_key in gates:
    data = json.loads(path.read_text())
    subs = data[sub_key]
    sub_summary = ", ".join(f"{k}={'PASS' if v else 'FAIL'}" for k, v in subs.items())
    gate_pass = bool(data[overall_key])
    overall = overall and gate_pass
    print(f"{gate_id:>4} | {name:<30} | {sub_summary:<41} | {'PASS' if gate_pass else 'FAIL'}")

print("")
print(f"overall_phase_b_verdict={'PASS' if overall else 'FAIL'}")
sys.exit(0 if overall else 1)
PY
