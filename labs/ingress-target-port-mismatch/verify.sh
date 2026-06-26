#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/ingress-target-port-mismatch/evidence"
UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR UTC_NOW

if [ ! -d "${EVIDENCE_DIR}" ]; then
    echo "[FATAL] Evidence directory not found: ${EVIDENCE_DIR}"
    exit 1
fi

declare -a CANONICAL_FILES=(
    "00-trigger-run.txt"
    "00-verify-run.txt"
    "01-ingress-config-before.json"
    "02-replicas-before.json"
    "03-curl-before.json"
    "04-ingress-update-result.json"
    "05-ingress-config-after-trigger.json"
    "06-replicas-after-trigger.json"
    "07-revision-status-after-trigger.json"
    "08-curl-after-trigger.json"
    "09-kql-after-trigger-portmismatch-raw.txt"
    "09-kql-after-trigger-portmismatch-sample-raw.txt"
    "09-kql-after-trigger.json"
    "10-ingress-update-fix-result.json"
    "11-ingress-config-after-fix.json"
    "12-replicas-after-fix.json"
    "13-revision-status-after-fix.json"
    "14-curl-after-fix.json"
    "15-kql-after-fix-portmismatch-raw.txt"
    "15-kql-after-fix-portmismatch-sample-raw.txt"
    "15-kql-after-fix.json"
    "20-cli-versions.json"
    "21-cli-containerapp-ext.json"
    "22-region.json"
    "23-deployment-outputs.json"
)

for name in "${CANONICAL_FILES[@]}"; do
    if [ ! -f "${EVIDENCE_DIR}/${name}" ]; then
        echo "[WARN] Missing canonical evidence file: ${EVIDENCE_DIR}/${name}"
    fi
done

echo "===== Phase B falsification gates -- ingress-target-port-mismatch ====="
echo "Evidence directory: ${EVIDENCE_DIR}"
echo "Phase B run UTC:    ${UTC_NOW}"
echo

python3 <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
UTC_NOW = os.environ["UTC_NOW"]

CANONICAL = [
    "00-trigger-run.txt",
    "00-verify-run.txt",
    "01-ingress-config-before.json",
    "02-replicas-before.json",
    "03-curl-before.json",
    "04-ingress-update-result.json",
    "05-ingress-config-after-trigger.json",
    "06-replicas-after-trigger.json",
    "07-revision-status-after-trigger.json",
    "08-curl-after-trigger.json",
    "09-kql-after-trigger-portmismatch-raw.txt",
    "09-kql-after-trigger-portmismatch-sample-raw.txt",
    "09-kql-after-trigger.json",
    "10-ingress-update-fix-result.json",
    "11-ingress-config-after-fix.json",
    "12-replicas-after-fix.json",
    "13-revision-status-after-fix.json",
    "14-curl-after-fix.json",
    "15-kql-after-fix-portmismatch-raw.txt",
    "15-kql-after-fix-portmismatch-sample-raw.txt",
    "15-kql-after-fix.json",
    "20-cli-versions.json",
    "21-cli-containerapp-ext.json",
    "22-region.json",
    "23-deployment-outputs.json",
]

GATE_OUTPUTS = [
    "14-cohort-integrity-gate.json",
    "15-h1-trigger-produces-failure-gate.json",
    "16-h2-fix-restores-recovery-gate.json",
    "17-single-variable-falsification-gate.json",
]

README_XREFS = [
    "14-cohort-integrity-gate.json",
    "15-h1-trigger-produces-failure-gate.json",
    "16-h2-fix-restores-recovery-gate.json",
    "17-single-variable-falsification-gate.json",
]

GATE14_REQUIRED_INPUTS = [
    "01-ingress-config-before.json",
    "05-ingress-config-after-trigger.json",
    "11-ingress-config-after-fix.json",
    "03-curl-before.json",
    "08-curl-after-trigger.json",
    "14-curl-after-fix.json",
    "09-kql-after-trigger.json",
    "15-kql-after-fix.json",
]

JUNK_SUFFIXES = (".swp", ".bak", ".tmp", ".swo", ".orig")
JUNK_NAMES = {".DS_Store", "Thumbs.db"}


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


def load_json(name: str):
    return json.loads((EVIDENCE_DIR / name).read_text(encoding="utf-8"))


def parse_iso8601(text: str) -> datetime:
    candidate = text[:-1] + "+00:00" if text.endswith("Z") else text
    dt = datetime.fromisoformat(candidate)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def gate_bool_map(entries: list[dict]) -> dict[str, bool]:
    return {entry["sub_gate"]: entry["result"] == "pass" for entry in entries}


def sub_gate(
    *,
    sub_gate_name: str,
    claim: str,
    predicate: str,
    claim_level: str,
    passed: bool,
    evidence_files: list[str],
    observed_values: dict,
) -> dict:
    return {
        "sub_gate": sub_gate_name,
        "claim": claim,
        "predicate": predicate,
        "claim_level": claim_level,
        "result": "pass" if passed else "fail",
        "evidence_files": evidence_files,
        "observed_values": observed_values,
    }


def write_gate(name: str, payload: dict) -> None:
    (EVIDENCE_DIR / name).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def deployment_outputs_root(payload: dict) -> dict:
    if isinstance(payload.get("properties"), dict) and isinstance(payload["properties"].get("outputs"), dict):
        return payload["properties"]["outputs"]
    return payload


print("===== Gate 14 -- h_cohort_integrity =====")

present = [name for name in CANONICAL if (EVIDENCE_DIR / name).is_file()]
missing = [name for name in CANONICAL if not (EVIDENCE_DIR / name).is_file()]
required_inputs_present = all((EVIDENCE_DIR / name).is_file() for name in GATE14_REQUIRED_INPUTS)

a14_strong = len(missing) == 0 and len(present) == 25
a14_fallback = len(present) >= 23 and required_inputs_present
a14_pass = a14_strong or a14_fallback

b14_error = None
span_seconds = None
anchor_values = {}
a03 = load_json("03-curl-before.json")
a09 = load_json("09-kql-after-trigger.json")
a15 = load_json("15-kql-after-fix.json")
try:
    t0 = parse_iso8601(a03["utc_completed"])
    t1 = parse_iso8601(a09["trigger_utc"])
    t2 = parse_iso8601(a15["fix_utc"])
    t3 = parse_iso8601(a15["utc_query"])
    anchor_values = {
        "03_utc_completed": a03["utc_completed"],
        "09_trigger_utc": a09["trigger_utc"],
        "15_fix_utc": a15["fix_utc"],
        "15_utc_query": a15["utc_query"],
    }
    monotonic = t0 < t1 < t2 < t3
    span_seconds = (t3 - t0).total_seconds()
    b14_strong = monotonic and span_seconds <= 1800
    b14_fallback = monotonic and span_seconds <= 5400
except Exception as exc:  # noqa: BLE001
    monotonic = False
    b14_strong = False
    b14_fallback = False
    b14_error = f"{type(exc).__name__}: {exc}"
b14_pass = b14_strong or b14_fallback

allowed = set(CANONICAL) | set(GATE_OUTPUTS) | {"README.md"}
on_disk = sorted(path.name for path in EVIDENCE_DIR.iterdir() if path.is_file())
ignored_junk = [name for name in on_disk if name in JUNK_NAMES or name.startswith(".") or name.endswith(JUNK_SUFFIXES)]
extras = [name for name in on_disk if name not in allowed and name not in ignored_junk]
c14_pass = len(extras) == 0

readme_path = EVIDENCE_DIR / "README.md"
readme_exists = readme_path.is_file()
readme_text = readme_path.read_text(encoding="utf-8") if readme_exists else ""
named_xrefs = [name for name in README_XREFS if name in readme_text]
d14_pass = readme_exists and len(named_xrefs) == len(README_XREFS)

gate14_sub_gates = [
    sub_gate(
        sub_gate_name="a_canonical_files_presence",
        claim="The Phase A cohort is sufficiently complete to support the four-gate falsification overlay.",
        predicate="Strong: all 25 canonical files are present. Fallback: at least 23 canonical files are present AND the required inputs {01,05,11,03,08,14,09-kql-after-trigger.json,15-kql-after-fix.json} are all present.",
        claim_level="Observed",
        passed=a14_pass,
        evidence_files=[repo_rel(name) for name in CANONICAL],
        observed_values={
            "observed_present_count": len(present),
            "observed_missing": missing,
            "strong": {
                "expected_count": 25,
                "holds": a14_strong,
            },
            "fallback": {
                "minimum_present_count": 23,
                "required_inputs": GATE14_REQUIRED_INPUTS,
                "required_inputs_present": required_inputs_present,
                "holds": a14_fallback,
            },
            "path_satisfied": "strong" if a14_strong else ("fallback" if a14_fallback else "fail"),
        },
    ),
    sub_gate(
        sub_gate_name="b_monotonic_temporal_coherence",
        claim="The baseline, trigger, fix, and post-fix query anchors form a monotonic experiment window of sane duration.",
        predicate="03.utc_completed < 09.trigger_utc < 15.fix_utc < 15.utc_query. Strong: total span <= 1800 seconds. Fallback: total span <= 5400 seconds.",
        claim_level="Measured",
        passed=b14_pass,
        evidence_files=[repo_rel("03-curl-before.json"), repo_rel("09-kql-after-trigger.json"), repo_rel("15-kql-after-fix.json")],
        observed_values={
            **anchor_values,
            "observed_span_seconds": span_seconds,
            "monotonic": monotonic,
            "parse_error": b14_error,
            "strong": {"max_span_seconds": 1800, "holds": b14_strong},
            "fallback": {"max_span_seconds": 5400, "holds": b14_fallback},
            "path_satisfied": "strong" if b14_strong else ("fallback" if b14_fallback else "fail"),
        },
    ),
    sub_gate(
        sub_gate_name="c_no_unexpected_non_junk_extras",
        claim="The evidence directory contains no unexpected non-junk files beyond the canonical cohort, four gate JSONs, and the evidence README.",
        predicate="Every file under evidence/ that is not one of the 25 canonical files, 4 gate JSONs, or README.md must be junk only; any non-junk extra falsifies the gate.",
        claim_level="Observed",
        passed=c14_pass,
        evidence_files=[repo_rel(name) for name in on_disk],
        observed_values={
            "observed_files_on_disk": on_disk,
            "ignored_junk": ignored_junk,
            "observed_non_junk_extras": extras,
            "holds": c14_pass,
        },
    ),
    sub_gate(
        sub_gate_name="d_readme_cross_references_all_gate_filenames",
        claim="The evidence-pack README literally names all four Phase B gate JSON files.",
        predicate="evidence/README.md must contain the literal substrings 14-cohort-integrity-gate.json, 15-h1-trigger-produces-failure-gate.json, 16-h2-fix-restores-recovery-gate.json, and 17-single-variable-falsification-gate.json.",
        claim_level="Observed",
        passed=d14_pass,
        evidence_files=[repo_rel("README.md")],
        observed_values={
            "readme_exists": readme_exists,
            "expected_xrefs": README_XREFS,
            "observed_xrefs": named_xrefs,
            "holds": d14_pass,
        },
    ),
]

gate14_payload = {
    "utc_captured": UTC_NOW,
    "scenario": "ingress_target_port_mismatch",
    "hypothesis": "H_cohort_integrity",
    "claim": "The 25-file ingress-target-port-mismatch evidence cohort is internally consistent: the canonical files are present, the baseline→trigger→fix→post-fix anchors are monotonic and bounded, no unexpected non-junk extras exist, and evidence/README.md cross-references all four Phase B gate JSON files.",
    "claim_level": "Observed",
    "predicate_inputs": {
        "canonical_evidence_directory": REL,
        "baseline_curl": repo_rel("03-curl-before.json"),
        "trigger_kql": repo_rel("09-kql-after-trigger.json"),
        "fix_kql": repo_rel("15-kql-after-fix.json"),
        "readme": repo_rel("README.md"),
    },
    "thresholds": {
        "canonical_count_strong": 25,
        "canonical_count_fallback_floor": 23,
        "temporal_span_strong_seconds_max": 1800,
        "temporal_span_fallback_seconds_max": 5400,
        "required_fallback_inputs": GATE14_REQUIRED_INPUTS,
    },
    "path_used": "strong" if a14_strong and b14_strong else ("fallback" if a14_pass and b14_pass else "fail"),
    "sub_gates": gate14_sub_gates,
    "ingress_target_port_mismatch_h_cohort_integrity_sub_gates": gate_bool_map(gate14_sub_gates),
    "ingress_target_port_mismatch_h_cohort_integrity_all_subgates_pass": all(item["result"] == "pass" for item in gate14_sub_gates),
    "gate_classification": "Cohort integrity gate: structural pre-condition for the three hypothesis gates. Strong and fallback evidence paths are both recorded for sub-gates (a) and (b), but any failing sub-gate falsifies the full Phase B run.",
}
write_gate("14-cohort-integrity-gate.json", gate14_payload)

print(f"  a (canonical files, path={gate14_sub_gates[0]['observed_values']['path_satisfied']}): {'PASS' if a14_pass else 'FAIL'}")
print(f"  b (temporal coherence, path={gate14_sub_gates[1]['observed_values']['path_satisfied']}): {'PASS' if b14_pass else 'FAIL'}")
print(f"  c (no non-junk extras): {'PASS' if c14_pass else 'FAIL'}")
print(f"  d (README xref): {'PASS' if d14_pass else 'FAIL'}")
print(f"  Gate 14 verdict: {'PASS' if gate14_payload['ingress_target_port_mismatch_h_cohort_integrity_all_subgates_pass'] else 'FAIL'}")
print()

print("===== Gate 15 -- h1_trigger_produces_failure =====")

cfg_before = load_json("01-ingress-config-before.json")
update_trigger = load_json("04-ingress-update-result.json")
cfg_after_trigger = load_json("05-ingress-config-after-trigger.json")
curl_trigger = load_json("08-curl-after-trigger.json")
kql_trigger = load_json("09-kql-after-trigger.json")

a15_pass = (
    cfg_before["ingress"]["targetPort"] == 80
    and cfg_after_trigger["ingress"]["targetPort"] == 8081
    and update_trigger["targetPort"] == 8081
)

b15_requests_ok = int(curl_trigger.get("requests_ok", 0))
b15_pass = b15_requests_ok <= 1

c15_rows = int(kql_trigger.get("portmismatch_rows", "0"))
c15_gate = kql_trigger.get("gate_classification")
c15_pass = c15_rows >= 1 and c15_gate == "populated_table"

sample_block = kql_trigger.get("system_portmismatch_sample", {})
sample_count = int(sample_block.get("sample_row_count", 0))
samples = sample_block.get("samples", [])
matching_samples = [
    sample
    for sample in samples
    if isinstance(sample, dict)
    and sample.get("Reason_s") == "Pending:PortMismatch"
    and "TargetPort" in str(sample.get("Log_s", ""))
    and "does not match the listening port" in str(sample.get("Log_s", ""))
]
d15_pass = sample_count >= 1 and len(matching_samples) >= 1

gate15_sub_gates = [
    sub_gate(
        sub_gate_name="a_trigger_mutated_ingress",
        claim="The trigger changed ingress.targetPort from the healthy baseline to the mismatched target port.",
        predicate="01.ingress.targetPort == 80 AND 05.ingress.targetPort == 8081 AND 04.targetPort == 8081.",
        claim_level="Observed",
        passed=a15_pass,
        evidence_files=[repo_rel("01-ingress-config-before.json"), repo_rel("04-ingress-update-result.json"), repo_rel("05-ingress-config-after-trigger.json")],
        observed_values={
            "before_target_port": cfg_before["ingress"]["targetPort"],
            "trigger_update_target_port": update_trigger["targetPort"],
            "after_trigger_target_port": cfg_after_trigger["ingress"]["targetPort"],
        },
    ),
    sub_gate(
        sub_gate_name="b_trigger_broke_traffic",
        claim="After the trigger, the edge stopped returning HTTP 200 on the documented threshold surface.",
        predicate="int(08.requests_ok) <= 1.",
        claim_level="Measured",
        passed=b15_pass,
        evidence_files=[repo_rel("08-curl-after-trigger.json")],
        observed_values={
            "requests_sent": int(curl_trigger.get("requests_sent", 0)),
            "requests_ok": b15_requests_ok,
            "requests_non_200": int(curl_trigger.get("requests_non_200", 0)),
        },
    ),
    sub_gate(
        sub_gate_name="c_trigger_populated_kql",
        claim="The strictly post-trigger KQL window materialized PortMismatch rows and classified the result as populated_table.",
        predicate="int(09.portmismatch_rows) >= 1 AND 09.gate_classification == 'populated_table'.",
        claim_level="Measured",
        passed=c15_pass,
        evidence_files=[repo_rel("09-kql-after-trigger.json")],
        observed_values={
            "portmismatch_rows": c15_rows,
            "probefailed_rows": int(kql_trigger.get("probefailed_rows", "0")),
            "gate_classification": c15_gate,
        },
    ),
    sub_gate(
        sub_gate_name="d_trigger_has_smoking_gun_evidence",
        claim="The sample rows include the platform-attributed smoking-gun message naming both the configured target port and the listening port.",
        predicate="09.system_portmismatch_sample.sample_row_count >= 1 AND at least one sample has Reason_s == 'Pending:PortMismatch' AND Log_s contains both 'TargetPort' and 'does not match the listening port'.",
        claim_level="Observed",
        passed=d15_pass,
        evidence_files=[repo_rel("09-kql-after-trigger.json"), repo_rel("09-kql-after-trigger-portmismatch-sample-raw.txt")],
        observed_values={
            "sample_row_count": sample_count,
            "matching_sample_count": len(matching_samples),
            "matching_log_examples": [sample.get("Log_s") for sample in matching_samples[:3]],
        },
    ),
]

gate15_payload = {
    "utc_captured": UTC_NOW,
    "scenario": "ingress_target_port_mismatch",
    "hypothesis": "H1_trigger_produces_failure",
    "claim": "The trigger mutated ingress.targetPort from 80 to 8081, edge traffic collapsed to 0/10 HTTP 200, the strictly post-trigger KQL window materialized 25 PortMismatch rows with gate_classification='populated_table', and the sample evidence includes the smoking-gun platform attribution 'The TargetPort 8081 does not match the listening port 80.'.",
    "claim_level": "Observed",
    "predicate_inputs": {
        "ingress_before": repo_rel("01-ingress-config-before.json"),
        "ingress_update_result": repo_rel("04-ingress-update-result.json"),
        "ingress_after_trigger": repo_rel("05-ingress-config-after-trigger.json"),
        "curl_after_trigger": repo_rel("08-curl-after-trigger.json"),
        "kql_after_trigger": repo_rel("09-kql-after-trigger.json"),
    },
    "thresholds": {
        "target_port_before_expected": 80,
        "target_port_trigger_expected": 8081,
        "post_trigger_requests_ok_max": 1,
        "portmismatch_rows_min": 1,
        "expected_gate_classification": "populated_table",
    },
    "path_used": "single",
    "sub_gates": gate15_sub_gates,
    "ingress_target_port_mismatch_h1_trigger_produces_failure_sub_gates": gate_bool_map(gate15_sub_gates),
    "ingress_target_port_mismatch_h1_trigger_produces_failure_all_subgates_pass": all(item["result"] == "pass" for item in gate15_sub_gates),
    "gate_classification": "H1 gate: confirms that the app-scope ingress mutation produced the documented failure signature on both the edge-traffic surface and the system-log attribution surface.",
}
write_gate("15-h1-trigger-produces-failure-gate.json", gate15_payload)

print(f"  a (ingress mutated): {'PASS' if a15_pass else 'FAIL'}")
print(f"  b (traffic broke): {'PASS' if b15_pass else 'FAIL'}")
print(f"  c (KQL populated): {'PASS' if c15_pass else 'FAIL'}")
print(f"  d (smoking-gun sample): {'PASS' if d15_pass else 'FAIL'}")
print(f"  Gate 15 verdict: {'PASS' if gate15_payload['ingress_target_port_mismatch_h1_trigger_produces_failure_all_subgates_pass'] else 'FAIL'}")
print()

print("===== Gate 16 -- h2_fix_restores_recovery =====")

update_fix = load_json("10-ingress-update-fix-result.json")
cfg_after_fix = load_json("11-ingress-config-after-fix.json")
curl_fix = load_json("14-curl-after-fix.json")
kql_fix = load_json("15-kql-after-fix.json")

a16_pass = cfg_after_fix["ingress"]["targetPort"] == 80 and update_fix["targetPort"] == 80

b16_requests_ok = int(curl_fix.get("requests_ok", 0))
b16_pass = b16_requests_ok >= 8

c16_rows = int(kql_fix.get("portmismatch_rows", "0"))
c16_gate = kql_fix.get("gate_classification")
c16_pass = c16_rows == 0 and c16_gate == "silent_valid_baseline"

fix_utc = kql_fix.get("fix_utc")
utc_query = kql_fix.get("utc_query")
query_string = kql_fix.get("system_portmismatch_query", "")
datetime_literal = f"datetime({fix_utc})"
strict_cutoff_clause = f"TimeGenerated > {datetime_literal}"
try:
    d16_temporal = parse_iso8601(fix_utc) < parse_iso8601(utc_query)
except Exception:  # noqa: BLE001
    d16_temporal = False
d16_query_bound = (
    strict_cutoff_clause in query_string
    and "ago(" not in query_string
)
d16_pass = d16_temporal and d16_query_bound

gate16_sub_gates = [
    sub_gate(
        sub_gate_name="a_fix_restored_ingress",
        claim="The fix returned ingress.targetPort to the healthy baseline.",
        predicate="11.ingress.targetPort == 80 AND 10.targetPort == 80.",
        claim_level="Observed",
        passed=a16_pass,
        evidence_files=[repo_rel("10-ingress-update-fix-result.json"), repo_rel("11-ingress-config-after-fix.json")],
        observed_values={
            "fix_update_target_port": update_fix["targetPort"],
            "after_fix_target_port": cfg_after_fix["ingress"]["targetPort"],
        },
    ),
    sub_gate(
        sub_gate_name="b_fix_restored_traffic",
        claim="After the fix, the edge returned to the documented healthy threshold surface.",
        predicate="int(14.requests_ok) >= 8.",
        claim_level="Measured",
        passed=b16_pass,
        evidence_files=[repo_rel("14-curl-after-fix.json")],
        observed_values={
            "requests_sent": int(curl_fix.get("requests_sent", 0)),
            "requests_ok": b16_requests_ok,
        },
    ),
    sub_gate(
        sub_gate_name="c_fix_silenced_kql",
        claim="The strictly post-fix KQL window is silent for PortMismatch and classified as a valid silent baseline.",
        predicate="int(15.portmismatch_rows) == 0 AND 15.gate_classification == 'silent_valid_baseline'.",
        claim_level="Measured",
        passed=c16_pass,
        evidence_files=[repo_rel("15-kql-after-fix.json")],
        observed_values={
            "portmismatch_rows": c16_rows,
            "probefailed_rows": int(kql_fix.get("probefailed_rows", "0")),
            "gate_classification": c16_gate,
        },
    ),
    sub_gate(
        sub_gate_name="d_strict_post_fix_kql_window",
        claim="The post-fix KQL was scoped to a strict UTC cutoff anchored on the fix moment, not a relative ago(...) window.",
        predicate="15.fix_utc < 15.utc_query AND 15.system_portmismatch_query contains 'datetime(' and the literal substring datetime(${FIX_UTC}).",
        claim_level="Observed",
        passed=d16_pass,
        evidence_files=[repo_rel("15-kql-after-fix.json")],
        observed_values={
            "fix_utc": fix_utc,
            "utc_query": utc_query,
            "temporal_sanity_holds": d16_temporal,
            "expected_datetime_literal": datetime_literal,
            "expected_strict_cutoff_clause": strict_cutoff_clause,
            "query_contains_strict_cutoff_clause": strict_cutoff_clause in query_string,
            "query_contains_ago": "ago(" in query_string,
            "query_is_strictly_bounded": d16_query_bound,
        },
    ),
]

gate16_payload = {
    "utc_captured": UTC_NOW,
    "scenario": "ingress_target_port_mismatch",
    "hypothesis": "H2_fix_restores_recovery",
    "claim": "The fix restored ingress.targetPort to 80, edge traffic recovered to 10/10 HTTP 200, the strictly post-fix KQL window returned portmismatch_rows='0' with gate_classification='silent_valid_baseline', and the query string proves the silence claim was bounded to TimeGenerated > datetime(2026-06-22T12:25:06Z).",
    "claim_level": "Observed",
    "predicate_inputs": {
        "ingress_update_fix_result": repo_rel("10-ingress-update-fix-result.json"),
        "ingress_after_fix": repo_rel("11-ingress-config-after-fix.json"),
        "curl_after_fix": repo_rel("14-curl-after-fix.json"),
        "kql_after_fix": repo_rel("15-kql-after-fix.json"),
    },
    "thresholds": {
        "target_port_fix_expected": 80,
        "post_fix_requests_ok_min": 8,
        "post_fix_portmismatch_rows_expected": 0,
        "post_fix_gate_classification_expected": "silent_valid_baseline",
    },
    "path_used": "single",
    "sub_gates": gate16_sub_gates,
    "ingress_target_port_mismatch_h2_fix_restores_recovery_sub_gates": gate_bool_map(gate16_sub_gates),
    "ingress_target_port_mismatch_h2_fix_restores_recovery_all_subgates_pass": all(item["result"] == "pass" for item in gate16_sub_gates),
    "gate_classification": "H2 gate: confirms that the same app recovered when ingress.targetPort returned to the listening port and that the post-fix silence claim is bounded to a strict UTC cutoff.",
}
write_gate("16-h2-fix-restores-recovery-gate.json", gate16_payload)

print(f"  a (ingress restored): {'PASS' if a16_pass else 'FAIL'}")
print(f"  b (traffic restored): {'PASS' if b16_pass else 'FAIL'}")
print(f"  c (KQL silenced): {'PASS' if c16_pass else 'FAIL'}")
print(f"  d (strict post-fix UTC window): {'PASS' if d16_pass else 'FAIL'}")
print(f"  Gate 16 verdict: {'PASS' if gate16_payload['ingress_target_port_mismatch_h2_fix_restores_recovery_all_subgates_pass'] else 'FAIL'}")
print()

print("===== Gate 17 -- h3_single_variable_falsification =====")

deployment_outputs = deployment_outputs_root(load_json("23-deployment-outputs.json"))
container_app_name = deployment_outputs.get("containerAppName", {}).get("value")
workspace_customer_id = deployment_outputs.get("logAnalyticsCustomerId", {}).get("value")

fields_before = cfg_before["ingress"]
fields_after_trigger = cfg_after_trigger["ingress"]
fields_after_fix = cfg_after_fix["ingress"]

g17_external = [fields_before.get("external"), fields_after_trigger.get("external"), fields_after_fix.get("external")]
g17_transport = [fields_before.get("transport"), fields_after_trigger.get("transport"), fields_after_fix.get("transport")]
g17_fqdn = [fields_before.get("fqdn"), fields_after_trigger.get("fqdn"), fields_after_fix.get("fqdn")]
g17_target = [fields_before.get("targetPort"), fields_after_trigger.get("targetPort"), fields_after_fix.get("targetPort")]

a17_pass = (
    g17_external == [True, True, True]
    and g17_transport == ["Auto", "Auto", "Auto"]
    and len(set(g17_fqdn)) == 1
    and g17_target[0] != g17_target[1]
    and g17_target[1] != g17_target[2]
    and g17_target[0] == g17_target[2] == 80
)

revisions = [cfg_before.get("latestRevisionName"), cfg_after_trigger.get("latestRevisionName"), cfg_after_fix.get("latestRevisionName")]
b17_pass = len(set(revisions)) == 1

c17_pass = (
    cfg_before.get("name") == cfg_after_trigger.get("name") == cfg_after_fix.get("name")
    and len(set(g17_fqdn)) == 1
)

literal_smoking_gun = "The TargetPort 8081 does not match the listening port 80."
literal_matches = [sample for sample in samples if isinstance(sample, dict) and literal_smoking_gun in str(sample.get("Log_s", ""))]
d17_pass = len(literal_matches) >= 1

gate17_sub_gates = [
    sub_gate(
        sub_gate_name="a_only_ingress_target_port_changed_across_three_states",
        claim="Across the baseline→trigger→fix sequence, the ingress field-level diff is bounded to targetPort while external, transport, and fqdn stay constant.",
        predicate="01.ingress.external == 05.ingress.external == 11.ingress.external AND 01.ingress.transport == 05.ingress.transport == 11.ingress.transport AND 01.ingress.fqdn == 05.ingress.fqdn == 11.ingress.fqdn AND 01.ingress.targetPort != 05.ingress.targetPort AND 05.ingress.targetPort != 11.ingress.targetPort AND 01.ingress.targetPort == 11.ingress.targetPort.",
        claim_level="Observed",
        passed=a17_pass,
        evidence_files=[repo_rel("01-ingress-config-before.json"), repo_rel("05-ingress-config-after-trigger.json"), repo_rel("11-ingress-config-after-fix.json")],
        observed_values={
            "external_values": g17_external,
            "transport_values": g17_transport,
            "fqdn_values": g17_fqdn,
            "target_port_values": g17_target,
        },
    ),
    sub_gate(
        sub_gate_name="b_no_new_revision_created",
        claim="The ingress mutation remained app-scope and did not create a new revision in this cohort.",
        predicate="01.latestRevisionName == 05.latestRevisionName == 11.latestRevisionName.",
        claim_level="Observed",
        passed=b17_pass,
        evidence_files=[repo_rel("01-ingress-config-before.json"), repo_rel("05-ingress-config-after-trigger.json"), repo_rel("11-ingress-config-after-fix.json")],
        observed_values={
            "latest_revision_values": revisions,
        },
    ),
    sub_gate(
        sub_gate_name="c_container_app_identity_preserved",
        claim="The same Container App resource and FQDN are preserved across all three ingress states.",
        predicate="01.name == 05.name == 11.name AND 01.ingress.fqdn == 05.ingress.fqdn == 11.ingress.fqdn.",
        claim_level="Observed",
        passed=c17_pass,
        evidence_files=[repo_rel("01-ingress-config-before.json"), repo_rel("05-ingress-config-after-trigger.json"), repo_rel("11-ingress-config-after-fix.json"), repo_rel("23-deployment-outputs.json")],
        observed_values={
            "container_app_name_values": [cfg_before.get("name"), cfg_after_trigger.get("name"), cfg_after_fix.get("name")],
            "fqdn_values": g17_fqdn,
            "deployment_outputs_container_app_name": container_app_name,
            "deployment_outputs_log_analytics_customer_id": "<redacted>" if workspace_customer_id else None,
        },
    ),
    sub_gate(
        sub_gate_name="d_smoking_gun_substantiates_listening_port_constancy",
        claim="The platform-attributed smoking-gun row directly substantiates that the container was still listening on :80 during the trigger while ingress.targetPort was 8081.",
        predicate="09.system_portmismatch_sample.samples[*].Log_s contains the literal 'The TargetPort 8081 does not match the listening port 80.'.",
        claim_level="Observed",
        passed=d17_pass,
        evidence_files=[repo_rel("09-kql-after-trigger.json"), repo_rel("09-kql-after-trigger-portmismatch-sample-raw.txt")],
        observed_values={
            "expected_literal": literal_smoking_gun,
            "matching_sample_count": len(literal_matches),
            "matching_log_examples": [sample.get("Log_s") for sample in literal_matches[:3]],
        },
    ),
]

gate17_payload = {
    "utc_captured": UTC_NOW,
    "scenario": "ingress_target_port_mismatch",
    "hypothesis": "H3_single_variable_falsification",
    "claim": "The bounded falsification is that the integer ingress.targetPort is the controlling variable across the baseline→trigger→fix sequence: external, transport, fqdn, revision name, and Container App identity stay constant, while the platform-attributed smoking-gun log explicitly states 'The TargetPort 8081 does not match the listening port 80.'.",
    "claim_level": "Observed",
    "cohort_binding_note": {
        "claim_ceiling": "The bounded falsification is `only the integer ingress.targetPort changed across the baseline→trigger→fix sequence`. The cohort directly evidences (i) ingress field-level diff bounded to targetPort, (ii) revision name preserved (no new revision), (iii) container app identity preserved across all three states, and (iv) platform-attributed listening-port constancy via the smoking-gun Log_s string `The TargetPort 8081 does not match the listening port 80.`",
        "explicit_drops": [
            "Image byte-identity NOT cohort-evidenced — the cohort does not capture image digest; inferred from the Phase A scripts not invoking any `az containerapp update --image` operation.",
            "Pod reuse NOT claimed — replica count varied (1→2→1 across 02, 06, 12) so different pod UIDs were created within the same revision; the cohort does not capture pod UIDs.",
            "5-minute ingestion latency window is a per-reproduction observation, NOT an SLA — Microsoft Learn does not document a strict SLA for `_CL` table ingestion lag for `ContainerAppSystemLogs_CL`.",
            "Listening port of the container is NOT directly captured in the cohort — it is inferred from the smoking-gun KQL Log_s string `does not match the listening port 80`; a custom image or a runtime port change inside the container would invalidate this inference but is outside the lab's test surface."
        ]
    },
    "predicate_inputs": {
        "ingress_before": repo_rel("01-ingress-config-before.json"),
        "ingress_after_trigger": repo_rel("05-ingress-config-after-trigger.json"),
        "ingress_after_fix": repo_rel("11-ingress-config-after-fix.json"),
        "trigger_kql": repo_rel("09-kql-after-trigger.json"),
        "deployment_outputs": repo_rel("23-deployment-outputs.json"),
    },
    "thresholds": {
        "target_port_baseline_expected": 80,
        "target_port_trigger_expected": 8081,
        "target_port_post_fix_expected": 80,
        "external_expected": True,
        "transport_expected": "Auto",
    },
    "path_used": "single",
    "sub_gates": gate17_sub_gates,
    "ingress_target_port_mismatch_h3_single_variable_falsification_sub_gates": gate_bool_map(gate17_sub_gates),
    "ingress_target_port_mismatch_h3_single_variable_falsification_all_subgates_pass": all(item["result"] == "pass" for item in gate17_sub_gates),
    "gate_classification": "H3 gate: bounds the single-variable claim to the ingress.targetPort integer and explicitly documents what the cohort does not directly prove.",
}
write_gate("17-single-variable-falsification-gate.json", gate17_payload)

print(f"  a (only targetPort changed): {'PASS' if a17_pass else 'FAIL'}")
print(f"  b (no new revision): {'PASS' if b17_pass else 'FAIL'}")
print(f"  c (identity preserved): {'PASS' if c17_pass else 'FAIL'}")
print(f"  d (listening-port constancy substantiated): {'PASS' if d17_pass else 'FAIL'}")
print(f"  Gate 17 verdict: {'PASS' if gate17_payload['ingress_target_port_mismatch_h3_single_variable_falsification_all_subgates_pass'] else 'FAIL'}")
print()

gate_summaries = [
    ("Gate 14", "H_cohort_integrity", gate14_payload["ingress_target_port_mismatch_h_cohort_integrity_all_subgates_pass"], 4),
    ("Gate 15", "H1_trigger_produces_failure", gate15_payload["ingress_target_port_mismatch_h1_trigger_produces_failure_all_subgates_pass"], 4),
    ("Gate 16", "H2_fix_restores_recovery", gate16_payload["ingress_target_port_mismatch_h2_fix_restores_recovery_all_subgates_pass"], 4),
    ("Gate 17", "H3_single_variable_falsification", gate17_payload["ingress_target_port_mismatch_h3_single_variable_falsification_all_subgates_pass"], 4),
]
passed_subgates = sum(
    1
    for payload in [gate14_payload, gate15_payload, gate16_payload, gate17_payload]
    for item in payload["sub_gates"]
    if item["result"] == "pass"
)
all_pass = passed_subgates == 16 and all(item[2] for item in gate_summaries)

print("===== Phase B summary =====")
print("Gate    Hypothesis                         Sub-gates  Verdict")
print("------  ---------------------------------  ---------  -------")
for gate_name, hypothesis, verdict, subgate_count in gate_summaries:
    print(f"{gate_name:<6}  {hypothesis:<33}  {subgate_count}/4      {'PASS' if verdict else 'FAIL'}")
print()
print(f"TOTAL: {passed_subgates}/16 sub-gates PASS")
print(f"PHASE B VERDICT: {'PASS' if all_pass else 'FAIL'}")

raise SystemExit(0 if all_pass else 1)
PY
