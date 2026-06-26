#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/diagnostic-settings-missing/evidence"
UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export UTC_NOW EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR

if [ ! -d "${EVIDENCE_DIR}" ]; then
    echo "[FATAL] Evidence directory not found: ${EVIDENCE_DIR}"
    exit 1
fi

declare -a CANONICAL_FILES=(
    "00-trigger-run.txt"
    "00-verify-run.txt"
    "01-env-config-before.json"
    "02-app-config-before.json"
    "03-curl-before.json"
    "04-kql-before-console-raw.txt"
    "04-kql-before-system-raw.txt"
    "04-kql-before.json"
    "05-env-update-result.json"
    "06-env-config-after.json"
    "07-revisions-after.json"
    "08-curl-after.json"
    "09-kql-after-console-raw.txt"
    "09-kql-after-system-by-revision.json"
    "09-kql-after-system-raw.txt"
    "09-kql-after.json"
    "10-cli-versions.json"
    "11-cli-containerapp-ext.json"
    "12-region.json"
    "13-deployment-outputs.json"
)

declare -a GATE_OUTPUTS=(
    "14-cohort-integrity-gate.json"
    "15-baseline-silent-gate.json"
    "16-post-fix-populated-gate.json"
    "17-single-variable-falsification-gate.json"
)

MISSING_COUNT=0
for name in "${CANONICAL_FILES[@]}"; do
    if [ ! -f "${EVIDENCE_DIR}/${name}" ]; then
        echo "[WARN] Missing canonical evidence file: ${EVIDENCE_DIR}/${name}"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done

if [ "${MISSING_COUNT}" -gt 0 ]; then
    echo "[WARN] ${MISSING_COUNT} canonical file(s) missing. Gate 14 records the failure."
fi

echo "===== Phase B falsification gates -- diagnostic-settings-missing ====="
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
    "01-env-config-before.json",
    "02-app-config-before.json",
    "03-curl-before.json",
    "04-kql-before-console-raw.txt",
    "04-kql-before-system-raw.txt",
    "04-kql-before.json",
    "05-env-update-result.json",
    "06-env-config-after.json",
    "07-revisions-after.json",
    "08-curl-after.json",
    "09-kql-after-console-raw.txt",
    "09-kql-after-system-by-revision.json",
    "09-kql-after-system-raw.txt",
    "09-kql-after.json",
    "10-cli-versions.json",
    "11-cli-containerapp-ext.json",
    "12-region.json",
    "13-deployment-outputs.json",
]

PHASE_B_OUTPUTS = [
    "14-cohort-integrity-gate.json",
    "15-baseline-silent-gate.json",
    "16-post-fix-populated-gate.json",
    "17-single-variable-falsification-gate.json",
]

GATE14_REQUIRED_FALLBACK = [
    "01-env-config-before.json",
    "04-kql-before.json",
    "06-env-config-after.json",
    "07-revisions-after.json",
    "09-kql-after.json",
]

JUNK_SUFFIXES = (".swp", ".bak", ".tmp", ".swo", ".orig")
JUNK_NAMES = (".DS_Store", "Thumbs.db")


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


def deployment_outputs_root(payload: dict) -> dict:
    if isinstance(payload.get("properties"), dict) and isinstance(
        payload["properties"].get("outputs"), dict
    ):
        return payload["properties"]["outputs"]
    if isinstance(payload.get("outputs"), dict):
        return payload["outputs"]
    return {}


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


print("===== Gate 14 -- cohort_integrity =====")

present = [name for name in CANONICAL if (EVIDENCE_DIR / name).is_file()]
missing = [name for name in CANONICAL if not (EVIDENCE_DIR / name).is_file()]
required_present = all((EVIDENCE_DIR / name).is_file() for name in GATE14_REQUIRED_FALLBACK)

a_strong = len(present) == 20 and not missing
a_fallback = len(present) >= 18 and required_present
a_pass = a_strong or a_fallback

span_seconds = None
time_error = None
b_strong = False
b_fallback = False
baseline_completed = None
postfix_completed = None
try:
    curl_before = load_json("03-curl-before.json")
    curl_after = load_json("08-curl-after.json")
    baseline_completed = curl_before["utc_completed"]
    postfix_completed = curl_after["utc_completed"]
    start_dt = parse_iso8601(baseline_completed)
    finish_dt = parse_iso8601(postfix_completed)
    span_seconds = (finish_dt - start_dt).total_seconds()
    monotonic = finish_dt > start_dt
    b_strong = monotonic and span_seconds <= 30 * 60
    b_fallback = monotonic and span_seconds <= 90 * 60
except Exception as exc:  # noqa: BLE001
    time_error = f"{type(exc).__name__}: {exc}"
    monotonic = False
b_pass = b_strong or b_fallback

allowed = set(CANONICAL) | set(PHASE_B_OUTPUTS) | {"README.md"}
on_disk = sorted(path.name for path in EVIDENCE_DIR.iterdir() if path.is_file())
extras = [name for name in on_disk if name not in allowed]
extras_junk_only = all(name in JUNK_NAMES or name.endswith(JUNK_SUFFIXES) for name in extras)
c_strong = len(extras) == 0
c_fallback = extras_junk_only
c_pass = c_strong or c_fallback

readme_path = EVIDENCE_DIR / "README.md"
readme_exists = readme_path.is_file()
named_outputs = []
if readme_exists:
    readme_text = readme_path.read_text(encoding="utf-8")
    named_outputs = [name for name in PHASE_B_OUTPUTS if name in readme_text]
d_strong = readme_exists and len(named_outputs) == len(PHASE_B_OUTPUTS)
d_fallback = readme_exists
d_pass = d_strong or d_fallback

gate14_sub_gates = [
    sub_gate(
        sub_gate_name="a_canonical_files_present",
        claim="The canonical Phase A evidence cohort is sufficiently complete to support hypothesis evaluation.",
        predicate=(
            "Strong: exactly 20 canonical files present. Fallback: at least 18 canonical files present AND "
            "all five hypothesis-gate inputs (01-env-config-before.json, 04-kql-before.json, "
            "06-env-config-after.json, 07-revisions-after.json, 09-kql-after.json) are present."
        ),
        claim_level="Observed",
        passed=a_pass,
        evidence_files=[repo_rel(name) for name in CANONICAL],
        observed_values={
            "observed_present_count": len(present),
            "observed_missing": missing,
            "required_fallback_inputs_present": required_present,
            "strong_holds": a_strong,
            "fallback_holds": a_fallback,
            "path_satisfied": "strong" if a_strong else ("fallback" if a_fallback else "fail"),
        },
    ),
    sub_gate(
        sub_gate_name="b_temporal_coherence",
        claim="The baseline curl completion and post-fix curl completion form a monotonic, bounded experiment window.",
        predicate=(
            "03-curl-before.json.utc_completed < 08-curl-after.json.utc_completed AND span <= 30 minutes "
            "for Strong or <= 90 minutes for Fallback."
        ),
        claim_level="Measured",
        passed=b_pass,
        evidence_files=[repo_rel("03-curl-before.json"), repo_rel("08-curl-after.json")],
        observed_values={
            "observed_baseline_utc_completed": baseline_completed,
            "observed_post_fix_utc_completed": postfix_completed,
            "observed_span_seconds": span_seconds,
            "monotonic": bool(b_strong or b_fallback),
            "parse_error": time_error,
            "strong_holds": b_strong,
            "fallback_holds": b_fallback,
            "path_satisfied": "strong" if b_strong else ("fallback" if b_fallback else "fail"),
        },
    ),
    sub_gate(
        sub_gate_name="c_no_unexpected_extras",
        claim="The evidence directory contains no unexpected non-junk extra files.",
        predicate=(
            "Strong: zero extras beyond the 20 canonical files, 4 Phase B gate files, and README.md. "
            "Fallback: extras limited to editor/OS junk only."
        ),
        claim_level="Observed",
        passed=c_pass,
        evidence_files=[repo_rel(name) for name in sorted(on_disk)],
        observed_values={
            "observed_files_on_disk": on_disk,
            "observed_extras": extras,
            "extras_junk_only": extras_junk_only,
            "strong_holds": c_strong,
            "fallback_holds": c_fallback,
            "path_satisfied": "strong" if c_strong else ("fallback" if c_fallback else "fail"),
        },
    ),
    sub_gate(
        sub_gate_name="d_readme_cross_reference",
        claim="The evidence-pack README exists and documents the Phase B gate outputs.",
        predicate=(
            "Strong: evidence/README.md exists and literally names all four Phase B gate JSON filenames. "
            "Fallback: evidence/README.md exists."
        ),
        claim_level="Observed",
        passed=d_pass,
        evidence_files=[repo_rel("README.md")],
        observed_values={
            "readme_exists": readme_exists,
            "observed_named_outputs": named_outputs,
            "expected_named_outputs": PHASE_B_OUTPUTS,
            "strong_holds": d_strong,
            "fallback_holds": d_fallback,
            "path_satisfied": "strong" if d_strong else ("fallback" if d_fallback else "fail"),
        },
    ),
]

gate14_strong_path = {
    "description": "All four sub-gates satisfy their Strong predicates.",
    "sub_gates": {
        "a_canonical_files_present": a_strong,
        "b_temporal_coherence": b_strong,
        "c_no_unexpected_extras": c_strong,
        "d_readme_cross_reference": d_strong,
    },
}
gate14_strong_path["all_subgates_pass"] = all(gate14_strong_path["sub_gates"].values())

gate14_fallback_path = {
    "description": "All four sub-gates satisfy at least their Fallback predicates.",
    "sub_gates": {
        "a_canonical_files_present": a_fallback,
        "b_temporal_coherence": b_fallback,
        "c_no_unexpected_extras": c_fallback,
        "d_readme_cross_reference": d_fallback,
    },
}
gate14_fallback_path["all_subgates_pass"] = all(gate14_fallback_path["sub_gates"].values())

gate14_all_pass = all(item["result"] == "pass" for item in gate14_sub_gates)
gate14_path_used = (
    "strong"
    if gate14_strong_path["all_subgates_pass"]
    else ("fallback" if gate14_fallback_path["all_subgates_pass"] else "fail")
)

gate14_payload = {
    "utc_captured": UTC_NOW,
    "scenario": "diagnostic_settings_missing",
    "hypothesis": "H_cohort_integrity",
    "claim": (
        "The 20-file diagnostic-settings-missing evidence cohort is internally consistent: the canonical files are present, "
        "the baseline and post-fix traffic captures form a sane monotonic window, the evidence directory contains no unexpected "
        "non-junk extras, and evidence/README.md documents the Phase B gate outputs."
    ),
    "claim_level": "Observed",
    "predicate_inputs": {
        "canonical_evidence_directory": REL,
        "curl_before": repo_rel("03-curl-before.json"),
        "curl_after": repo_rel("08-curl-after.json"),
        "readme": repo_rel("README.md"),
    },
    "thresholds": {
        "canonical_count_strong": 20,
        "canonical_count_fallback_floor": 18,
        "temporal_span_strong_seconds_max": 1800,
        "temporal_span_fallback_seconds_max": 5400,
        "required_fallback_inputs": GATE14_REQUIRED_FALLBACK,
    },
    "strong_path": gate14_strong_path,
    "fallback_path": gate14_fallback_path,
    "path_used": gate14_path_used,
    "sub_gates": gate14_sub_gates,
    "diagnostic_settings_missing_h_cohort_integrity_sub_gates": {
        item["sub_gate"]: item["result"] == "pass" for item in gate14_sub_gates
    },
    "diagnostic_settings_missing_h_cohort_integrity_all_subgates_pass": gate14_all_pass,
    "gate_classification": (
        "Cohort integrity gate: structural pre-condition for the three hypothesis gates. Strong and Fallback are both "
        "evaluated and recorded, but any failing sub-gate falsifies the full Phase B run."
    ),
}

write_gate("14-cohort-integrity-gate.json", gate14_payload)
print(f"  a (canonical files, path={gate14_sub_gates[0]['observed_values']['path_satisfied']}): {'PASS' if a_pass else 'FAIL'}")
print(f"  b (temporal coherence, path={gate14_sub_gates[1]['observed_values']['path_satisfied']}): {'PASS' if b_pass else 'FAIL'}")
print(f"  c (no extras, path={gate14_sub_gates[2]['observed_values']['path_satisfied']}): {'PASS' if c_pass else 'FAIL'}")
print(f"  d (README xref, path={gate14_sub_gates[3]['observed_values']['path_satisfied']}): {'PASS' if d_pass else 'FAIL'}")
print(f"  Gate 14 verdict: {'PASS' if gate14_all_pass else 'FAIL'}")
print()

print("===== Gate 15 -- h1_baseline_silent =====")

env_before = load_json("01-env-config-before.json")
kql_before = load_json("04-kql-before.json")
curl_before = load_json("03-curl-before.json")

obs_destination_before = env_before.get("destination")
obs_law_before = env_before.get("logAnalyticsConfiguration")
a15_pass = obs_destination_before is None and obs_law_before is None

obs_console_rows_before = int(kql_before.get("console_rows", 0))
obs_system_rows_before = int(kql_before.get("system_rows", 0))
b15_pass = obs_console_rows_before == 0 and obs_system_rows_before == 0

obs_console_class_before = kql_before.get("console_gate_classification")
obs_system_class_before = kql_before.get("system_gate_classification")
c15_pass = (
    obs_console_class_before == "silent_valid_baseline"
    and obs_system_class_before == "silent_valid_baseline"
)

obs_requests_ok_before = int(curl_before.get("requests_ok", 0))
d15_pass = obs_requests_ok_before >= 8

gate15_sub_gates = [
    sub_gate(
        sub_gate_name="a_env_destination_and_workspace_null",
        claim="The baseline environment has no configured Log Analytics destination.",
        predicate=(
            "01-env-config-before.json records destination == None AND logAnalyticsConfiguration == None."
        ),
        claim_level="Observed",
        passed=a15_pass,
        evidence_files=[repo_rel("01-env-config-before.json")],
        observed_values={
            "observed_destination": obs_destination_before,
            "observed_log_analytics_configuration_is_none": obs_law_before is None,
        },
    ),
    sub_gate(
        sub_gate_name="b_baseline_rows_zero_in_both_tables",
        claim="The baseline KQL result is silent in both console and system tables.",
        predicate=(
            "04-kql-before.json records int(console_rows) == 0 AND int(system_rows) == 0."
        ),
        claim_level="Measured",
        passed=b15_pass,
        evidence_files=[repo_rel("04-kql-before.json")],
        observed_values={
            "observed_console_rows": obs_console_rows_before,
            "observed_system_rows": obs_system_rows_before,
        },
    ),
    sub_gate(
        sub_gate_name="c_baseline_classifications_silent_valid_baseline",
        claim="The baseline silence is classified as valid baseline silence, not as an unexpected query error.",
        predicate=(
            "04-kql-before.json records console_gate_classification == 'silent_valid_baseline' AND "
            "system_gate_classification == 'silent_valid_baseline'."
        ),
        claim_level="Observed",
        passed=c15_pass,
        evidence_files=[repo_rel("04-kql-before.json")],
        observed_values={
            "observed_console_gate_classification": obs_console_class_before,
            "observed_system_gate_classification": obs_system_class_before,
        },
    ),
    sub_gate(
        sub_gate_name="d_baseline_traffic_generated",
        claim="The baseline silence is meaningful because traffic was actually sent to the baseline revision.",
        predicate=(
            "03-curl-before.json.requests_ok >= 8."
        ),
        claim_level="Measured",
        passed=d15_pass,
        evidence_files=[repo_rel("03-curl-before.json")],
        observed_values={
            "observed_requests_ok": obs_requests_ok_before,
            "observed_requests_sent": curl_before.get("requests_sent"),
        },
    ),
]

gate15_all_pass = all(item["result"] == "pass" for item in gate15_sub_gates)
gate15_payload = {
    "utc_captured": UTC_NOW,
    "scenario": "diagnostic_settings_missing",
    "hypothesis": "H1_baseline_silent",
    "claim": (
        "With appLogsConfiguration absent at the environment scope, the baseline cohort is silent in both ContainerAppConsoleLogs_CL "
        "and ContainerAppSystemLogs_CL after real request traffic and a full ingestion wait."
    ),
    "claim_level": "Observed",
    "predicate_inputs": {
        "env_config_before": repo_rel("01-env-config-before.json"),
        "curl_before": repo_rel("03-curl-before.json"),
        "kql_before": repo_rel("04-kql-before.json"),
    },
    "path_used": "single",
    "sub_gates": gate15_sub_gates,
    "diagnostic_settings_missing_h1_baseline_silent_sub_gates": {
        item["sub_gate"]: item["result"] == "pass" for item in gate15_sub_gates
    },
    "diagnostic_settings_missing_h1_baseline_silent_all_subgates_pass": gate15_all_pass,
    "gate_classification": (
        "Baseline silence gate: proves the null environment configuration coincided with zero rows in both log tables after traffic."
    ),
}

write_gate("15-baseline-silent-gate.json", gate15_payload)
print(f"  a (env null state): {'PASS' if a15_pass else 'FAIL'}")
print(f"  b (baseline zero rows): {'PASS' if b15_pass else 'FAIL'}")
print(f"  c (baseline classifications): {'PASS' if c15_pass else 'FAIL'}")
print(f"  d (baseline traffic generated): {'PASS' if d15_pass else 'FAIL'}")
print(f"  Gate 15 verdict: {'PASS' if gate15_all_pass else 'FAIL'}")
print()

print("===== Gate 16 -- h2_post_fix_populated =====")

env_after = load_json("06-env-config-after.json")
kql_after = load_json("09-kql-after.json")
curl_after = load_json("08-curl-after.json")
revisions_after = load_json("07-revisions-after.json")
deployment_outputs = deployment_outputs_root(load_json("13-deployment-outputs.json"))

expected_customer_id = (
    deployment_outputs.get("logAnalyticsCustomerId", {}) or {}
).get("value")
observed_destination_after = env_after.get("destination")
observed_law_after = env_after.get("logAnalyticsConfiguration")
observed_customer_id_after = None
if isinstance(observed_law_after, dict):
    observed_customer_id_after = observed_law_after.get("customerId")
a16_pass = (
    observed_destination_after == "log-analytics"
    and observed_law_after is not None
    and observed_customer_id_after == expected_customer_id
)

obs_console_rows_after = int(kql_after.get("console_rows", 0))
obs_system_rows_after = int(kql_after.get("system_rows", 0))
b16_pass = obs_console_rows_after >= 1 and obs_system_rows_after >= 1

obs_console_class_after = kql_after.get("console_gate_classification")
obs_system_class_after = kql_after.get("system_gate_classification")
c16_pass = (
    obs_console_class_after == "populated_table"
    and obs_system_class_after == "populated_table"
)

requests_ok_after = int(curl_after.get("requests_ok", 0))
record_count_after = len(revisions_after) if isinstance(revisions_after, list) else -1
traffic_holders = [
    record for record in revisions_after
    if isinstance(revisions_after, list) and record.get("trafficWeight") == 100
]
exactly_one_holder = len(traffic_holders) == 1
holder = traffic_holders[0] if exactly_one_holder else {}
holder_name = holder.get("name") if isinstance(holder, dict) else None
holder_state = holder.get("runningState") if isinstance(holder, dict) else None
holder_state_ok = holder_state in {"Running", "RunningAtMaxScale"}
curl_post_fix_revision = curl_after.get("post_fix_revision")
kql_post_fix_revision = kql_after.get("post_fix_revision")
name_equality = (
    holder_name is not None
    and holder_name == curl_post_fix_revision
    and holder_name == kql_post_fix_revision
)
d16_pass = (
    requests_ok_after >= 8
    and isinstance(revisions_after, list)
    and record_count_after == 2
    and exactly_one_holder
    and holder_state_ok
    and name_equality
)

gate16_sub_gates = [
    sub_gate(
        sub_gate_name="a_env_destination_and_customer_id_match",
        claim="The post-fix environment readback is pinned to the intended Log Analytics workspace.",
        predicate=(
            "06-env-config-after.json records destination == 'log-analytics' AND logAnalyticsConfiguration is not None AND "
            "logAnalyticsConfiguration.customerId == 13-deployment-outputs.json.outputs.logAnalyticsCustomerId.value."
        ),
        claim_level="Observed",
        passed=a16_pass,
        evidence_files=[repo_rel("06-env-config-after.json"), repo_rel("13-deployment-outputs.json")],
        observed_values={
            "observed_destination": observed_destination_after,
            "observed_log_analytics_configuration_present": observed_law_after is not None,
            "customer_id_matches_deployment_output": observed_customer_id_after == expected_customer_id,
            "customer_id_redacted": "<workspace-customer-id>",
        },
    ),
    sub_gate(
        sub_gate_name="b_post_fix_rows_populated_in_both_tables",
        claim="The post-fix KQL result contains at least one row in both tables.",
        predicate=(
            "09-kql-after.json records int(console_rows) >= 1 AND int(system_rows) >= 1."
        ),
        claim_level="Measured",
        passed=b16_pass,
        evidence_files=[repo_rel("09-kql-after.json")],
        observed_values={
            "observed_console_rows": obs_console_rows_after,
            "observed_system_rows": obs_system_rows_after,
            "rows_are_string_encoded_in_source_json": True,
        },
    ),
    sub_gate(
        sub_gate_name="c_post_fix_classifications_populated_table",
        claim="The post-fix rows are classified as populated_table in both tables.",
        predicate=(
            "09-kql-after.json records console_gate_classification == 'populated_table' AND system_gate_classification == 'populated_table'."
        ),
        claim_level="Observed",
        passed=c16_pass,
        evidence_files=[repo_rel("09-kql-after.json")],
        observed_values={
            "observed_console_gate_classification": obs_console_class_after,
            "observed_system_gate_classification": obs_system_class_after,
        },
    ),
    sub_gate(
        sub_gate_name="d_post_fix_traffic_holder_is_new_running_revision",
        claim="Traffic after the fix was served by the single running post-fix revision.",
        predicate=(
            "08-curl-after.json.requests_ok >= 8 AND 07-revisions-after.json is a 2-record top-level array AND exactly 1 record has "
            "trafficWeight == 100 AND that record.runningState in {'Running','RunningAtMaxScale'} AND that record.name == "
            "08-curl-after.json.post_fix_revision == 09-kql-after.json.post_fix_revision."
        ),
        claim_level="Observed",
        passed=d16_pass,
        evidence_files=[
            repo_rel("07-revisions-after.json"),
            repo_rel("08-curl-after.json"),
            repo_rel("09-kql-after.json"),
        ],
        observed_values={
            "observed_requests_ok": requests_ok_after,
            "observed_revision_record_count": record_count_after,
            "observed_traffic_holder_count": len(traffic_holders),
            "observed_traffic_holder_name": holder_name,
            "observed_traffic_holder_running_state": holder_state,
            "observed_curl_post_fix_revision": curl_post_fix_revision,
            "observed_kql_post_fix_revision": kql_post_fix_revision,
            "holder_name_matches_all_three_sources": name_equality,
        },
    ),
]

gate16_all_pass = all(item["result"] == "pass" for item in gate16_sub_gates)
gate16_payload = {
    "utc_captured": UTC_NOW,
    "scenario": "diagnostic_settings_missing",
    "hypothesis": "H2_post_fix_populated",
    "claim": (
        "After the environment-level log routing fix and a forced new revision, both ContainerAppConsoleLogs_CL and "
        "ContainerAppSystemLogs_CL materialized and populated for the same app and same workspace."
    ),
    "claim_level": "Observed",
    "predicate_inputs": {
        "env_config_after": repo_rel("06-env-config-after.json"),
        "revisions_after": repo_rel("07-revisions-after.json"),
        "curl_after": repo_rel("08-curl-after.json"),
        "kql_after": repo_rel("09-kql-after.json"),
        "deployment_outputs": repo_rel("13-deployment-outputs.json"),
    },
    "path_used": "single",
    "sub_gates": gate16_sub_gates,
    "diagnostic_settings_missing_h2_post_fix_populated_sub_gates": {
        item["sub_gate"]: item["result"] == "pass" for item in gate16_sub_gates
    },
    "diagnostic_settings_missing_h2_post_fix_populated_all_subgates_pass": gate16_all_pass,
    "gate_classification": (
        "Post-fix materialization gate: proves the environment update restored ingestion to both tables and that the observed post-fix traffic "
        "belongs to the new traffic-holding revision."
    ),
}

write_gate("16-post-fix-populated-gate.json", gate16_payload)
print(f"  a (env destination + workspace match): {'PASS' if a16_pass else 'FAIL'}")
print(f"  b (post-fix rows populated): {'PASS' if b16_pass else 'FAIL'}")
print(f"  c (post-fix classifications): {'PASS' if c16_pass else 'FAIL'}")
print(f"  d (post-fix traffic holder): {'PASS' if d16_pass else 'FAIL'}")
print(f"  Gate 16 verdict: {'PASS' if gate16_all_pass else 'FAIL'}")
print()

print("===== Gate 17 -- h3_single_variable_falsification =====")

shared_keys = set(env_before.keys()) & set(env_after.keys())
shared_keys_sorted = sorted(shared_keys)
diff_keys = sorted(key for key in shared_keys if env_before.get(key) != env_after.get(key))
unchanged_keys = sorted(key for key in shared_keys if key not in diff_keys)
a17_pass = shared_keys == {"destination", "logAnalyticsConfiguration"} and set(diff_keys) == {"destination", "logAnalyticsConfiguration"}

baseline_revision = load_json("02-app-config-before.json").get("latestRevisionName")
after_revision_names = [record.get("name") for record in revisions_after if isinstance(record, dict)]
holder_names = [record.get("name") for record in traffic_holders if isinstance(record, dict)]
post_fix_revision = curl_post_fix_revision
baseline_in_after = baseline_revision in after_revision_names
post_fix_in_holder = post_fix_revision in holder_names
post_fix_differs_from_baseline = post_fix_revision is not None and post_fix_revision != baseline_revision
b17_pass = baseline_in_after and post_fix_in_holder and post_fix_differs_from_baseline

container_app_name = (deployment_outputs.get("containerAppName", {}) or {}).get("value")
expected_prefix = f"{container_app_name}--" if container_app_name else None
prefix_checks = {
    name: bool(expected_prefix and isinstance(name, str) and name.startswith(expected_prefix))
    for name in after_revision_names
}
c17_pass = bool(prefix_checks) and all(prefix_checks.values())

gate17_sub_gates = [
    sub_gate(
        sub_gate_name="a_shared_env_config_surface_bounded_to_intentional_payload",
        claim="The entire shared-key surface diff is bounded to the intentional environment log-routing payload.",
        predicate=(
            "Shared keys between 01-env-config-before.json and 06-env-config-after.json are exactly {destination, logAnalyticsConfiguration} AND "
            "the diff set on that shared surface is exactly {destination, logAnalyticsConfiguration}."
        ),
        claim_level="Observed",
        passed=a17_pass,
        evidence_files=[repo_rel("01-env-config-before.json"), repo_rel("06-env-config-after.json")],
        observed_values={
            "observed_shared_keys": shared_keys_sorted,
            "observed_diff_keys": diff_keys,
            "observed_unchanged_shared_keys": unchanged_keys,
            "destination_before": env_before.get("destination"),
            "destination_after": env_after.get("destination"),
            "log_analytics_configuration_changed": env_before.get("logAnalyticsConfiguration") != env_after.get("logAnalyticsConfiguration"),
            "co_set_operation_note": (
                "destination and logAnalyticsConfiguration were co-set by one az containerapp env update --logs-destination --logs-workspace-id "
                "--logs-workspace-key call; this is a single platform-mutable diff bounded to the intentional env-config payload, not a single-key claim."
            ),
        },
    ),
    sub_gate(
        sub_gate_name="b_revision_lineage_new_revision_created_for_fix",
        claim="The baseline revision remains in lineage, and the traffic-holding revision after the fix is a new revision.",
        predicate=(
            "02-app-config-before.json.latestRevisionName appears in 07-revisions-after.json[*].name AND 08-curl-after.json.post_fix_revision appears "
            "in 07 with trafficWeight == 100 AND post_fix_revision != 02.latestRevisionName."
        ),
        claim_level="Observed",
        passed=b17_pass,
        evidence_files=[
            repo_rel("02-app-config-before.json"),
            repo_rel("07-revisions-after.json"),
            repo_rel("08-curl-after.json"),
        ],
        observed_values={
            "observed_baseline_revision": baseline_revision,
            "observed_post_fix_revision": post_fix_revision,
            "observed_revision_names_after": after_revision_names,
            "observed_traffic_holder_names": holder_names,
            "baseline_revision_present_after_fix": baseline_in_after,
            "post_fix_revision_is_traffic_holder": post_fix_in_holder,
            "post_fix_revision_differs_from_baseline": post_fix_differs_from_baseline,
        },
    ),
    sub_gate(
        sub_gate_name="c_container_app_identity_preserved_across_revisions",
        claim="All post-fix revisions belong to the same Container App resource.",
        predicate=(
            "Every 07-revisions-after.json[*].name starts with 13-deployment-outputs.json.outputs.containerAppName.value + '--'."
        ),
        claim_level="Observed",
        passed=c17_pass,
        evidence_files=[repo_rel("07-revisions-after.json"), repo_rel("13-deployment-outputs.json")],
        observed_values={
            "observed_container_app_name": container_app_name,
            "observed_expected_prefix": expected_prefix,
            "observed_prefix_checks": prefix_checks,
        },
    ),
]

gate17_all_pass = all(item["result"] == "pass" for item in gate17_sub_gates)
gate17_payload = {
    "utc_captured": UTC_NOW,
    "scenario": "diagnostic_settings_missing",
    "hypothesis": "H3_single_variable_falsification",
    "claim": (
        "The observed before/after ingestion change is bounded to the intentional environment log-routing mutation plus the forced revision creation used "
        "to emit fresh platform events; no additional shared env-config field changed within the cohort surface."
    ),
    "claim_level": "Observed",
    "predicate_inputs": {
        "env_config_before": repo_rel("01-env-config-before.json"),
        "app_config_before": repo_rel("02-app-config-before.json"),
        "env_config_after": repo_rel("06-env-config-after.json"),
        "revisions_after": repo_rel("07-revisions-after.json"),
        "curl_after": repo_rel("08-curl-after.json"),
        "deployment_outputs": repo_rel("13-deployment-outputs.json"),
    },
    "path_used": "single",
    "sub_gates": gate17_sub_gates,
    "diagnostic_settings_missing_h3_single_variable_falsification_sub_gates": {
        item["sub_gate"]: item["result"] == "pass" for item in gate17_sub_gates
    },
    "diagnostic_settings_missing_h3_single_variable_falsification_all_subgates_pass": gate17_all_pass,
    "cohort_binding_note": {
        "claim_ceiling": (
            "The falsification claim is bounded to the intentional environment log-routing payload and the forced revision lineage captured in this cohort."
        ),
        "explicit_drops": [
            "Image byte-identity NOT cohort-evidenced — inferred from the Phase A fix-and-capture.sh Phase 8 env-var-only app update having no --image flag; the cohort does not capture image digests, so byte-identity is argued only from the absence of an image change in that operation.",
            "Pod reuse NOT claimed — under activeRevisionsMode: Single, the FIXAPPLIED env-var update creates a new revision by design; sub-gate (b) shows post_fix_revision != baseline_revision, and the cohort does not capture pod UIDs.",
            "5-minute ingestion latency window is a per-reproduction observation, NOT an SLA — Microsoft Learn does not document a strict SLA for *_CL table ingestion lag (https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash); 300 seconds was sufficient on 2026-06-22 in koreacentral, but slower regions or busier workspaces may need longer.",
            "Helloworld stdout volume per request is NOT a row-per-request guarantee — mcr.microsoft.com/azuredocs/containerapps-helloworld emits Nginx access logs, but row counts vary with buffering and ingestion behavior; this cohort observed 1 console row and 34 system rows from 10 post-fix requests, so Gate 16 uses a >= 1 row threshold."
        ],
    },
    "gate_classification": (
        "Single-variable falsification gate: bounds the observed change to the intentional env-config mutation surface and the forced post-fix revision lineage, while explicitly documenting what the cohort does not prove."
    ),
}

write_gate("17-single-variable-falsification-gate.json", gate17_payload)
print(f"  a (shared env-config surface): {'PASS' if a17_pass else 'FAIL'}")
print(f"  b (revision lineage): {'PASS' if b17_pass else 'FAIL'}")
print(f"  c (container app identity): {'PASS' if c17_pass else 'FAIL'}")
print(f"  Gate 17 verdict: {'PASS' if gate17_all_pass else 'FAIL'}")
print()

print("===== Phase B summary =====")

gates = [
    (
        "14-cohort-integrity-gate.json",
        "diagnostic_settings_missing_h_cohort_integrity_all_subgates_pass",
        "H_cohort_integrity",
    ),
    (
        "15-baseline-silent-gate.json",
        "diagnostic_settings_missing_h1_baseline_silent_all_subgates_pass",
        "H1_baseline_silent",
    ),
    (
        "16-post-fix-populated-gate.json",
        "diagnostic_settings_missing_h2_post_fix_populated_all_subgates_pass",
        "H2_post_fix_populated",
    ),
    (
        "17-single-variable-falsification-gate.json",
        "diagnostic_settings_missing_h3_single_variable_falsification_all_subgates_pass",
        "H3_single_variable_falsification",
    ),
]

summary_rows = []
total_subgates = 0
passed_subgates = 0
overall = True
for filename, key, hypothesis in gates:
    payload = load_json(filename)
    gate_pass = bool(payload.get(key))
    subgate_count = len(payload.get("sub_gates", []))
    subgate_pass = sum(1 for item in payload.get("sub_gates", []) if item.get("result") == "pass")
    total_subgates += subgate_count
    passed_subgates += subgate_pass
    overall = overall and gate_pass
    summary_rows.append((filename, hypothesis, subgate_pass, subgate_count, gate_pass))

width = max(len(row[0]) for row in summary_rows)
print(f"  {'Gate file'.ljust(width)}  Hypothesis                           Sub-gates  Verdict")
print(f"  {'-' * width}  -----------------------------------  ---------  -------")
for filename, hypothesis, subgate_pass, subgate_count, gate_pass in summary_rows:
    verdict = "PASS" if gate_pass else "FAIL"
    print(
        f"  {filename.ljust(width)}  {hypothesis.ljust(35)}  {str(subgate_pass) + '/' + str(subgate_count):>9}  {verdict}"
    )

print()
print(f"  Total sub-gates passed: {passed_subgates}/{total_subgates}")
print(f"  Overall Phase B verdict: {'PASS' if overall else 'FAIL'}")

raise SystemExit(0 if overall else 1)
PY
