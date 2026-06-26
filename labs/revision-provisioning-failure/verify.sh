#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/revision-provisioning-failure/evidence"
UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR UTC_NOW

declare -a CANONICAL_RAW_FILES=(
    "01-revision-list.json"
    "02-failed-revision-detail.json"
    "03-containerapp-spec.yaml"
    "04-system-logs.json"
    "05-replicas-failed.json"
    "06-console-logs.json"
    "07-kql-probefailed-rows.json"
    "08-kql-event-correlation.json"
    "09-kql-summary-by-reason.json"
    "10-kql-console-logs.json"
    "11-kql-postfix-verification.json"
    "12-revision-list-recovered.json"
)

declare -a PHASE_B_GATE_OUTPUTS=(
    "14-cohort-integrity-gate.json"
    "15-h1-trigger-produces-failure-gate.json"
    "16-h2-fix-restores-recovery-gate.json"
    "17-bounded-falsification-gate.json"
)

pass_gate() {
    local gate_number="$1"
    local detail="$2"
    echo "[Gate ${gate_number}/17] PASS ${detail}"
}

fail_gate() {
    local gate_number="$1"
    local detail="$2"
    echo "[Gate ${gate_number}/17] FAIL ${detail}"
    exit 1
}

run_python_gate() {
    local gate_number="$1"
    local gate_name="$2"
    local output
    if output="$(GATE_NUMBER="$gate_number" GATE_NAME="$gate_name" python3 <<'PY'
import json
import os
from pathlib import Path

gate_number = int(os.environ["GATE_NUMBER"])
gate_name = os.environ["GATE_NAME"]
evidence_dir = Path(os.environ["EVIDENCE_DIR"])

def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))

def load_jsonl(path: Path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]

def load_yaml(path: Path):
    import yaml
    return yaml.safe_load(path.read_text(encoding="utf-8"))

if gate_number == 1:
    if evidence_dir.is_dir():
        print(f"evidence directory present at {evidence_dir}")
        raise SystemExit(0)
    print(f"evidence directory missing at {evidence_dir}")
    raise SystemExit(1)

if gate_number == 2:
    expected = [
        "01-revision-list.json",
        "02-failed-revision-detail.json",
        "03-containerapp-spec.yaml",
        "04-system-logs.json",
        "05-replicas-failed.json",
        "06-console-logs.json",
        "07-kql-probefailed-rows.json",
        "08-kql-event-correlation.json",
        "09-kql-summary-by-reason.json",
        "10-kql-console-logs.json",
        "11-kql-postfix-verification.json",
        "12-revision-list-recovered.json",
    ]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print("missing raw files: " + ", ".join(missing))
        raise SystemExit(1)
    print("all 12 canonical raw evidence files are present")
    raise SystemExit(0)

if gate_number == 3:
    import yaml
    parsed = []
    try:
        for name in [
            "01-revision-list.json",
            "02-failed-revision-detail.json",
            "05-replicas-failed.json",
            "07-kql-probefailed-rows.json",
            "08-kql-event-correlation.json",
            "09-kql-summary-by-reason.json",
            "10-kql-console-logs.json",
            "11-kql-postfix-verification.json",
            "12-revision-list-recovered.json",
        ]:
            load_json(evidence_dir / name)
            parsed.append(name)
        for name in ["04-system-logs.json", "06-console-logs.json"]:
            load_jsonl(evidence_dir / name)
            parsed.append(name)
        load_yaml(evidence_dir / "03-containerapp-spec.yaml")
        parsed.append("03-containerapp-spec.yaml")
    except Exception as exc:  # noqa: BLE001
        print(f"parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    print(f"all raw files parsed successfully ({len(parsed)} files)")
    raise SystemExit(0)

rev_list = load_json(evidence_dir / "01-revision-list.json")
failed = load_json(evidence_dir / "02-failed-revision-detail.json")
spec = load_yaml(evidence_dir / "03-containerapp-spec.yaml")
system_logs = load_jsonl(evidence_dir / "04-system-logs.json")
replicas = load_json(evidence_dir / "05-replicas-failed.json")
console_logs = load_jsonl(evidence_dir / "06-console-logs.json")
kql_probe = load_json(evidence_dir / "07-kql-probefailed-rows.json")
kql_corr = load_json(evidence_dir / "08-kql-event-correlation.json")
kql_summary = load_json(evidence_dir / "09-kql-summary-by-reason.json")
kql_console = load_json(evidence_dir / "10-kql-console-logs.json")
postfix = load_json(evidence_dir / "11-kql-postfix-verification.json")
recovered = load_json(evidence_dir / "12-revision-list-recovered.json")

APP_NAME = "ca-labrevprov-e2upm2"
RESOURCE_GROUP = "rg-aca-lab-revprov"
REGION = "koreacentral"
FAILED_REVISION = "ca-labrevprov-e2upm2--badpath2"
RECOVERED_REVISION = "ca-labrevprov-e2upm2--badpath3"
BASELINE_REVISION = "ca-labrevprov-e2upm2--badpath"
BAD_PATH = "/nonexistent-health-endpoint"

if gate_number == 4:
    ok = True
    details = []
    if spec.get("name") != APP_NAME:
        ok = False
        details.append("spec.name mismatch")
    if spec.get("resourceGroup") != RESOURCE_GROUP:
        ok = False
        details.append("spec.resourceGroup mismatch")
    if REGION not in str(spec.get("location", "")).lower().replace(" ", ""):
        ok = False
        details.append("spec.location mismatch")
    revision_names = sorted(item.get("name") for item in rev_list)
    if revision_names != sorted([BASELINE_REVISION, FAILED_REVISION]):
        ok = False
        details.append("unexpected revision names in 01")
    if failed.get("resourceGroup") != RESOURCE_GROUP or failed.get("name") != FAILED_REVISION:
        ok = False
        details.append("failed revision identity mismatch")
    recovered_name = recovered[0].get("name") if recovered else None
    if recovered_name != RECOVERED_REVISION:
        ok = False
        details.append("recovered revision identity mismatch")
    if ok:
        print(f"cohort identity pinned to {APP_NAME} / {RESOURCE_GROUP} / {REGION}")
        raise SystemExit(0)
    print("; ".join(details))
    raise SystemExit(1)

if gate_number == 5:
    created = {item["name"]: item["properties"]["createdTime"] for item in rev_list}
    ok = (
        len(rev_list) == 2
        and BASELINE_REVISION in created
        and FAILED_REVISION in created
        and created[BASELINE_REVISION] < created[FAILED_REVISION]
        and any(item["properties"].get("trafficWeight") == 100 for item in rev_list if item["name"] == FAILED_REVISION)
    )
    if ok:
        print(f"01-revision-list.json captures {BASELINE_REVISION} -> {FAILED_REVISION} progression")
        raise SystemExit(0)
    print("revision progression missing or not monotonic in 01-revision-list.json")
    raise SystemExit(1)

if gate_number == 6:
    props = failed.get("properties", {})
    ok = (
        failed.get("name") == FAILED_REVISION
        and props.get("healthState") == "Unhealthy"
        and props.get("provisioningState") == "Failed"
        and props.get("provisioningError") == "Container crashing: app"
        and props.get("runningStateDetails") == "1/1 Container crashing: app"
    )
    if ok:
        print("failed revision detail shows Unhealthy / Failed / Container crashing: app")
        raise SystemExit(0)
    print("failed revision detail does not match expected H1 failure state")
    raise SystemExit(1)

if gate_number == 7:
    probe = spec["properties"]["template"]["containers"][0]["probes"][0]
    ok = (
        spec["properties"]["configuration"]["activeRevisionsMode"] == "Single"
        and spec["properties"]["configuration"]["ingress"]["targetPort"] == 80
        and spec["properties"]["template"]["containers"][0]["image"] == "nginx:alpine"
        and probe["type"] == "Startup"
        and probe["httpGet"]["path"] == BAD_PATH
        and probe["httpGet"]["port"] == 80
        and probe["failureThreshold"] == 3
        and probe["periodSeconds"] == 5
    )
    if ok:
        print("container app spec pins nginx startup probe to the bad path on port 80")
        raise SystemExit(0)
    print("container app spec does not capture the expected bad startup probe surface")
    raise SystemExit(1)

if gate_number == 8:
    filtered = [r for r in system_logs if r.get("RevisionName") == FAILED_REVISION]
    probe_failed = [r for r in filtered if r.get("Reason") == "ProbeFailed"]
    terminated = [r for r in filtered if r.get("Reason") == "ContainerTerminated" and "ProbeFailure" in str(r.get("Msg", ""))]
    ok = len(probe_failed) >= 9 and len(terminated) >= 4
    if ok:
        print(f"system logs show {len(probe_failed)} ProbeFailed rows and {len(terminated)} ProbeFailure terminations")
        raise SystemExit(0)
    print(f"insufficient raw system-log failures: ProbeFailed={len(probe_failed)} ContainerTerminated={len(terminated)}")
    raise SystemExit(1)

if gate_number == 9:
    replica = replicas[0]["properties"] if replicas else {}
    container = replica.get("containers", [{}])[0]
    ok = (
        len(replicas) == 1
        and replicas[0].get("name", "").startswith(FAILED_REVISION)
        and replica.get("runningState") == "NotRunning"
        and container.get("ready") is False
        and int(container.get("restartCount", 0)) >= 3
        and container.get("runningState") == "Waiting"
        and "CrashLoopBackOff" in str(container.get("runningStateDetails", ""))
    )
    if ok:
        print("replica surface shows NotRunning + Waiting + CrashLoopBackOff on the failed revision")
        raise SystemExit(0)
    print("replica evidence does not show the expected failed-revision restart loop")
    raise SystemExit(1)

if gate_number == 10:
    has_404 = any(BAD_PATH in str(r.get("Log", "")) and "404" in str(r.get("Log", "")) for r in console_logs)
    has_sigquit = any("SIGQUIT" in str(r.get("Log", "")) for r in console_logs)
    has_sigchld = any("SIGCHLD" in str(r.get("Log", "")) for r in console_logs)
    ok = has_404 and has_sigquit and has_sigchld
    if ok:
        print("console logs show nginx 404 on the bad path plus SIGQUIT/SIGCHLD shutdown evidence")
        raise SystemExit(0)
    print("console logs missing nginx 404 and/or shutdown trail for the bad path")
    raise SystemExit(1)

if gate_number == 11:
    rows = [r for r in kql_probe if r.get("RevisionName_s") == FAILED_REVISION]
    has_404 = any(r.get("Reason_s") == "ProbeFailed" and "404" in str(r.get("Log_s", "")) for r in rows)
    has_restart = any(r.get("Reason_s") == "ProbeFailed" and "restarted" in str(r.get("Log_s", "")) for r in rows)
    ok = len(rows) >= 20 and has_404 and has_restart
    if ok:
        print(f"KQL ProbeFailed cohort is revision-scoped to {FAILED_REVISION} with {len(rows)} rows")
        raise SystemExit(0)
    print(f"KQL ProbeFailed cohort insufficient or not revision-scoped: rows={len(rows)}")
    raise SystemExit(1)

if gate_number == 12:
    rows = [r for r in kql_corr if r.get("RevisionName_s") == FAILED_REVISION]
    reasons = {r.get("Reason_s") for r in rows}
    ok = {"ContainerCreated", "ContainerStarted", "ProbeFailed", "ContainerTerminated"}.issubset(reasons)
    if ok:
        print("KQL correlation shows ContainerCreated -> ContainerStarted -> ProbeFailed -> ContainerTerminated")
        raise SystemExit(0)
    print(f"KQL correlation missing lifecycle reasons: observed={sorted(reasons)}")
    raise SystemExit(1)

if gate_number == 13:
    recovered_probe = recovered[0]["properties"]["template"]["containers"][0]["probes"][0]
    badpath3_rows = [r for r in postfix if r.get("RevisionName_s") == RECOVERED_REVISION]
    badpath3_reasons = {r.get("Reason_s") for r in badpath3_rows}
    has_badpath3_probe_failed = any(r.get("Reason_s") == "ProbeFailed" for r in badpath3_rows)
    ok = (
        recovered[0]["properties"].get("healthState") == "Healthy"
        and recovered[0]["properties"].get("provisioningState") == "Provisioned"
        and recovered_probe["httpGet"]["path"] == "/"
        and recovered_probe["httpGet"]["port"] == 80
        and "ContainerStarted" in badpath3_reasons
        and not has_badpath3_probe_failed
    )
    if ok:
        print("raw recovery evidence shows badpath3 Healthy with path=/ and no ProbeFailed rows")
        raise SystemExit(0)
    print("raw recovery evidence missing Healthy/path=/ or shows post-fix ProbeFailed on badpath3")
    raise SystemExit(1)

print(f"unsupported gate number {gate_number} for {gate_name}")
raise SystemExit(1)
PY
)"; then
        pass_gate "$gate_number" "$output"
    else
        fail_gate "$gate_number" "$output"
    fi
}

if [ ! -d "${EVIDENCE_DIR}" ]; then
    fail_gate 1 "evidence directory missing at ${EVIDENCE_DIR}"
fi

echo "===== Phase B falsification gates -- revision-provisioning-failure ====="
echo "Evidence directory: ${EVIDENCE_DIR}"
echo "Phase B run UTC:    ${UTC_NOW}"
echo

run_python_gate 1 "evidence_directory_exists"
run_python_gate 2 "canonical_raw_files_exist"
run_python_gate 3 "canonical_raw_files_parse"
run_python_gate 4 "cohort_identity_surface"
run_python_gate 5 "h1_revision_progression"
run_python_gate 6 "failed_revision_detail"
run_python_gate 7 "bad_probe_spec_surface"
run_python_gate 8 "raw_system_log_restart_loop"
run_python_gate 9 "failed_replica_surface"
run_python_gate 10 "console_404_smoking_gun"
run_python_gate 11 "kql_probefailed_rows"
run_python_gate 12 "kql_event_correlation"
run_python_gate 13 "raw_recovery_surface"

if GATE14_OUTPUT="$(python3 <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import yaml

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
UTC_NOW = os.environ["UTC_NOW"]

APP_NAME = "ca-labrevprov-e2upm2"
RESOURCE_GROUP = "rg-aca-lab-revprov"
FAILED_REVISION = "ca-labrevprov-e2upm2--badpath2"
RECOVERED_REVISION = "ca-labrevprov-e2upm2--badpath3"

CANONICAL = [
    "01-revision-list.json",
    "02-failed-revision-detail.json",
    "03-containerapp-spec.yaml",
    "04-system-logs.json",
    "05-replicas-failed.json",
    "06-console-logs.json",
    "07-kql-probefailed-rows.json",
    "08-kql-event-correlation.json",
    "09-kql-summary-by-reason.json",
    "10-kql-console-logs.json",
    "11-kql-postfix-verification.json",
    "12-revision-list-recovered.json",
]
GATE_OUTPUTS = [
    "14-cohort-integrity-gate.json",
    "15-h1-trigger-produces-failure-gate.json",
    "16-h2-fix-restores-recovery-gate.json",
    "17-bounded-falsification-gate.json",
]
README_XREFS = list(GATE_OUTPUTS)
JUNK_SUFFIXES = (".swp", ".bak", ".tmp", ".swo", ".orig")
JUNK_NAMES = {".DS_Store", "Thumbs.db"}


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


def load_json(name: str):
    return json.loads((EVIDENCE_DIR / name).read_text(encoding="utf-8"))


def load_jsonl(name: str):
    return [json.loads(line) for line in (EVIDENCE_DIR / name).read_text(encoding="utf-8").splitlines() if line.strip()]


def load_yaml(name: str):
    return yaml.safe_load((EVIDENCE_DIR / name).read_text(encoding="utf-8"))


def parse_dt(text: str) -> datetime:
    candidate = text[:-1] + "+00:00" if text.endswith("Z") else text
    dt = datetime.fromisoformat(candidate)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def gate_bool_map(entries):
    return {entry["sub_gate"]: entry["result"] == "pass" for entry in entries}


def sub_gate(name, claim, predicate, level, passed, evidence_files, observed_values):
    return {
        "sub_gate": name,
        "claim": claim,
        "predicate": predicate,
        "claim_level": level,
        "result": "pass" if passed else "fail",
        "evidence_files": evidence_files,
        "observed_values": observed_values,
    }


present = [name for name in CANONICAL if (EVIDENCE_DIR / name).is_file()]
missing = [name for name in CANONICAL if not (EVIDENCE_DIR / name).is_file()]
a_strong = len(present) == 12 and not missing
a_fallback = a_strong
a_pass = a_strong or a_fallback

parse_errors = []
try:
    load_json("01-revision-list.json")
    load_json("02-failed-revision-detail.json")
    load_yaml("03-containerapp-spec.yaml")
    load_jsonl("04-system-logs.json")
    load_json("05-replicas-failed.json")
    load_jsonl("06-console-logs.json")
    load_json("07-kql-probefailed-rows.json")
    load_json("08-kql-event-correlation.json")
    load_json("09-kql-summary-by-reason.json")
    load_json("10-kql-console-logs.json")
    load_json("11-kql-postfix-verification.json")
    load_json("12-revision-list-recovered.json")
except Exception as exc:  # noqa: BLE001
    parse_errors.append(f"{type(exc).__name__}: {exc}")
b_parse_pass = not parse_errors

spec = load_yaml("03-containerapp-spec.yaml")
raw_revisions = load_json("01-revision-list.json")
failed = load_json("02-failed-revision-detail.json")
recovered = load_json("12-revision-list-recovered.json")

h1_anchor_start = parse_dt(raw_revisions[0]["properties"]["createdTime"])
h1_anchor_fail = parse_dt(raw_revisions[1]["properties"]["createdTime"])
h2_anchor_fix = parse_dt(recovered[0]["properties"]["createdTime"])
system_log_times = [parse_dt(r["TimeStamp"].replace(" +0000 UTC", "+00:00")) for r in load_jsonl("04-system-logs.json") if r.get("RevisionName") == FAILED_REVISION]
kql_probe_times = [parse_dt(r["TimeGenerated"]) for r in load_json("07-kql-probefailed-rows.json") if r.get("RevisionName_s") == FAILED_REVISION]
kql_corr_times = [parse_dt(r["TimeGenerated"]) for r in load_json("08-kql-event-correlation.json") if r.get("RevisionName_s") == FAILED_REVISION]
kql_console_times = [parse_dt(r["TimeGenerated"]) for r in load_json("10-kql-console-logs.json") if r.get("RevisionName_s") == FAILED_REVISION]
all_h1_times = [h1_anchor_start, h1_anchor_fail, *system_log_times, *kql_probe_times, *kql_corr_times, *kql_console_times]
earliest = min(all_h1_times)
latest = max([*all_h1_times, h2_anchor_fix])
span_seconds = (latest - earliest).total_seconds()
c_strong = span_seconds <= 1800
c_fallback = span_seconds <= 5400
c_pass = c_strong or c_fallback

lineage_ok = (
    spec.get("name") == APP_NAME
    and spec.get("resourceGroup") == RESOURCE_GROUP
    and failed.get("resourceGroup") == RESOURCE_GROUP
    and recovered[0].get("resourceGroup") == RESOURCE_GROUP
    and raw_revisions[0]["name"] == "ca-labrevprov-e2upm2--badpath"
    and raw_revisions[1]["name"] == FAILED_REVISION
    and recovered[0]["name"] == RECOVERED_REVISION
)

allowed = set(CANONICAL) | set(GATE_OUTPUTS) | {"README.md"}
on_disk = sorted(path.name for path in EVIDENCE_DIR.iterdir() if path.is_file())
ignored_junk = [name for name in on_disk if name in JUNK_NAMES or name.startswith(".") or name.endswith(JUNK_SUFFIXES)]
extras = [name for name in on_disk if name not in allowed and name not in ignored_junk]
d_pass = len(extras) == 0

readme_path = EVIDENCE_DIR / "README.md"
readme_exists = readme_path.is_file()
readme_text = readme_path.read_text(encoding="utf-8") if readme_exists else ""
named_xrefs = [name for name in README_XREFS if name in readme_text]
e_pass = readme_exists and len(named_xrefs) == len(README_XREFS)

sub_gates = [
    sub_gate(
        "a_canonical_raw_files_present_and_parse",
        "All 12 canonical Jun 21 raw evidence files exist and parse as JSON, YAML, or JSONL.",
        "Strong and fallback both require the full 12-file raw cohort to exist; 01,02,05,07,08,09,10,11,12 parse as JSON; 03 parses as YAML; 04 and 06 parse as JSONL.",
        "Observed",
        a_pass and b_parse_pass,
        [repo_rel(name) for name in CANONICAL],
        {
            "observed_present_count": len(present),
            "observed_missing": missing,
            "parse_errors": parse_errors,
            "strong": {"expected_count": 12, "holds": a_strong and b_parse_pass},
            "fallback": {"expected_count": 12, "holds": a_fallback and b_parse_pass},
            "path_satisfied": "strong" if a_strong and b_parse_pass else ("fallback" if a_fallback and b_parse_pass else "fail"),
        },
    ),
    sub_gate(
        "b_temporal_cohort_is_monotonic_and_bounded",
        "The baseline -> H1 failure -> H2 recovery anchors form a monotonic cohort with fallback ceiling <= 5400 seconds.",
        "Strong: earliest raw anchor through badpath3 creation <= 1800 seconds. Fallback: <= 5400 seconds.",
        "Measured",
        c_pass,
        [repo_rel("01-revision-list.json"), repo_rel("04-system-logs.json"), repo_rel("07-kql-probefailed-rows.json"), repo_rel("08-kql-event-correlation.json"), repo_rel("10-kql-console-logs.json"), repo_rel("12-revision-list-recovered.json")],
        {
            "earliest_anchor_utc": earliest.isoformat(),
            "latest_anchor_utc": latest.isoformat(),
            "observed_span_seconds": span_seconds,
            "strong": {"max_span_seconds": 1800, "holds": c_strong},
            "fallback": {"max_span_seconds": 5400, "holds": c_fallback},
            "path_satisfied": "strong" if c_strong else ("fallback" if c_fallback else "fail"),
        },
    ),
    sub_gate(
        "c_identity_and_lineage_are_consistent",
        "All raw files bind to the same Container App / resource group and the expected revision lineage badpath -> badpath2 -> badpath3.",
        "spec.name == ca-labrevprov-e2upm2 AND spec.resourceGroup == rg-aca-lab-revprov AND raw revision names are {badpath,badpath2} before recovery and badpath3 after recovery.",
        "Observed",
        lineage_ok,
        [repo_rel("01-revision-list.json"), repo_rel("02-failed-revision-detail.json"), repo_rel("03-containerapp-spec.yaml"), repo_rel("12-revision-list-recovered.json")],
        {
            "spec_name": spec.get("name"),
            "spec_resource_group": spec.get("resourceGroup"),
            "raw_revision_names": [item.get("name") for item in raw_revisions],
            "recovered_revision_name": recovered[0].get("name"),
            "holds": lineage_ok,
        },
    ),
    sub_gate(
        "d_no_unexpected_non_junk_extras_and_readme_xrefs_exist",
        "The evidence directory has no unexpected non-junk extras and evidence/README.md literally names all four Phase B outputs.",
        "extras == [] AND evidence/README.md contains the four gate filenames literally.",
        "Observed",
        d_pass and e_pass,
        [repo_rel(name) for name in on_disk],
        {
            "observed_files_on_disk": on_disk,
            "ignored_junk": ignored_junk,
            "observed_non_junk_extras": extras,
            "readme_exists": readme_exists,
            "expected_xrefs": README_XREFS,
            "observed_xrefs": named_xrefs,
            "extras_holds": d_pass,
            "readme_holds": e_pass,
        },
    ),
]

payload = {
    "utc_captured": UTC_NOW,
    "scenario": "revision_provisioning_failure",
    "hypothesis": "H_cohort_integrity",
    "claim": "The 12-file revision-provisioning-failure raw cohort is internally consistent: every file is present and parseable, the identity and lineage bind to ca-labrevprov-e2upm2 / rg-aca-lab-revprov, the temporal span uses the documented <=5400-second fallback ceiling, and evidence/README.md cross-references all four Phase B gate JSON files.",
    "claim_level": "Observed",
    "predicate_inputs": {
        "canonical_evidence_directory": REL,
        "revision_list_before": repo_rel("01-revision-list.json"),
        "failed_revision_detail": repo_rel("02-failed-revision-detail.json"),
        "container_app_spec": repo_rel("03-containerapp-spec.yaml"),
        "recovered_revision_list": repo_rel("12-revision-list-recovered.json"),
        "readme": repo_rel("README.md"),
    },
    "thresholds": {
        "canonical_count_strong": 12,
        "canonical_count_fallback_floor": 12,
        "temporal_span_strong_seconds_max": 1800,
        "temporal_span_fallback_seconds_max": 5400,
    },
    "path_used": "strong" if a_strong and c_strong else ("fallback" if a_pass and c_pass else "fail"),
    "sub_gates": sub_gates,
    "revision_provisioning_failure_h_cohort_integrity_sub_gates": gate_bool_map(sub_gates),
    "revision_provisioning_failure_h_cohort_integrity_all_subgates_pass": all(item["result"] == "pass" for item in sub_gates),
    "gate_classification": "Cohort integrity gate: structural pre-condition for the bounded-falsification pack. The temporal bound uses the documented fallback ceiling because the 53-minute baseline-to-fix span exceeds the 30-minute strong ceiling.",
}

(EVIDENCE_DIR / "14-cohort-integrity-gate.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
all_pass = payload["revision_provisioning_failure_h_cohort_integrity_all_subgates_pass"]
print("wrote 14-cohort-integrity-gate.json; verdict=" + ("PASS" if all_pass else "FAIL"))
raise SystemExit(0 if all_pass else 1)
PY
)"; then
    pass_gate 14 "$GATE14_OUTPUT"
else
    fail_gate 14 "$GATE14_OUTPUT"
fi

if GATE15_OUTPUT="$(python3 <<'PY'
import json
import os
from pathlib import Path

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
UTC_NOW = os.environ["UTC_NOW"]

FAILED_REVISION = "ca-labrevprov-e2upm2--badpath2"
BAD_PATH = "/nonexistent-health-endpoint"


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


def gate_bool_map(entries):
    return {entry["sub_gate"]: entry["result"] == "pass" for entry in entries}


def sub_gate(name, claim, predicate, level, passed, evidence_files, observed_values):
    return {
        "sub_gate": name,
        "claim": claim,
        "predicate": predicate,
        "claim_level": level,
        "result": "pass" if passed else "fail",
        "evidence_files": evidence_files,
        "observed_values": observed_values,
    }


failed = json.loads((EVIDENCE_DIR / "02-failed-revision-detail.json").read_text(encoding="utf-8"))
system_logs = [json.loads(line) for line in (EVIDENCE_DIR / "04-system-logs.json").read_text(encoding="utf-8").splitlines() if line.strip()]
kql_probe = json.loads((EVIDENCE_DIR / "07-kql-probefailed-rows.json").read_text(encoding="utf-8"))
kql_corr = json.loads((EVIDENCE_DIR / "08-kql-event-correlation.json").read_text(encoding="utf-8"))
kql_console = json.loads((EVIDENCE_DIR / "10-kql-console-logs.json").read_text(encoding="utf-8"))

props = failed["properties"]
a_pass = (
    failed["name"] == FAILED_REVISION
    and props.get("provisioningState") == "Failed"
    and props.get("healthState") == "Unhealthy"
    and props.get("provisioningError") == "Container crashing: app"
)

system_probe = [r for r in system_logs if r.get("RevisionName") == FAILED_REVISION and r.get("Reason") == "ProbeFailed"]
system_terminated = [r for r in system_logs if r.get("RevisionName") == FAILED_REVISION and r.get("Reason") == "ContainerTerminated" and "ProbeFailure" in str(r.get("Msg", ""))]
b_pass = len(system_probe) >= 9 and len(system_terminated) >= 4

kql_probe_rows = [r for r in kql_probe if r.get("RevisionName_s") == FAILED_REVISION]
kql_corr_rows = [r for r in kql_corr if r.get("RevisionName_s") == FAILED_REVISION]
probe_has_rows = len(kql_probe_rows) >= 20
corr_has_terminated = any(r.get("Reason_s") == "ContainerTerminated" and "ProbeFailure" in str(r.get("Log_s", "")) for r in kql_corr_rows)
c_pass = probe_has_rows and corr_has_terminated

console_rows = [r for r in kql_console if r.get("RevisionName_s") == FAILED_REVISION]
has_404 = any(BAD_PATH in str(r.get("Log_s", "")) and "404" in str(r.get("Log_s", "")) for r in console_rows)
has_open_failed = any("open()" in str(r.get("Log_s", "")) and BAD_PATH in str(r.get("Log_s", "")) for r in console_rows)
d_pass = has_404 and has_open_failed

sub_gates = [
    sub_gate(
        "a_failed_revision_surface_matches_h1",
        "The failed revision detail is the documented H1 smoking gun: Unhealthy + Failed + provisioningError='Container crashing: app'.",
        "02.properties.provisioningState == 'Failed' AND 02.properties.healthState == 'Unhealthy' AND 02.properties.provisioningError == 'Container crashing: app'.",
        "Observed",
        a_pass,
        [repo_rel("02-failed-revision-detail.json")],
        {
            "revision_name": failed["name"],
            "provisioning_state": props.get("provisioningState"),
            "health_state": props.get("healthState"),
            "provisioning_error": props.get("provisioningError"),
        },
    ),
    sub_gate(
        "b_raw_system_logs_show_restart_loop",
        "Raw system logs show repeated startup-probe failures and ProbeFailure terminations on badpath2.",
        "count(04.Reason == ProbeFailed on badpath2) >= 9 AND count(04.Reason == ContainerTerminated with ProbeFailure on badpath2) >= 4.",
        "Measured",
        b_pass,
        [repo_rel("04-system-logs.json")],
        {
            "probefailed_event_count": len(system_probe),
            "containerterminated_probefailure_count": len(system_terminated),
        },
    ),
    sub_gate(
        "c_kql_h1_rows_bind_to_badpath2",
        "The KQL H1 evidence is revision-scoped to badpath2 and includes ProbeFailure termination correlation.",
        "count(07 rows where RevisionName_s == badpath2) >= 20 AND 08 contains at least one ContainerTerminated row with ProbeFailure on badpath2.",
        "Observed",
        c_pass,
        [repo_rel("07-kql-probefailed-rows.json"), repo_rel("08-kql-event-correlation.json")],
        {
            "kql_probefailed_row_count": len(kql_probe_rows),
            "kql_event_correlation_row_count": len(kql_corr_rows),
            "correlation_has_containerterminated_probefailure": corr_has_terminated,
        },
    ),
    sub_gate(
        "d_nginx_404_console_smoking_gun_present",
        "The application-level KQL console evidence shows nginx returning 404 on the bad probe path.",
        "10 contains at least one row with GET /nonexistent-health-endpoint ... 404 AND one row with open() ... nonexistent-health-endpoint failed.",
        "Observed",
        d_pass,
        [repo_rel("10-kql-console-logs.json")],
        {
            "console_row_count_for_failed_revision": len(console_rows),
            "has_404_access_log": has_404,
            "has_open_failed_error_log": has_open_failed,
        },
    ),
]

payload = {
    "utc_captured": UTC_NOW,
    "scenario": "revision_provisioning_failure",
    "hypothesis": "H1_trigger_produces_failure",
    "claim": "The H1 trigger produced the documented failure on ca-labrevprov-e2upm2--badpath2: the revision surface is Unhealthy/Failed with provisioningError='Container crashing: app', raw system logs show a repeated ProbeFailed -> ContainerTerminated(ProbeFailure) loop, KQL rows bind the failure to badpath2, and nginx console evidence shows 404 responses on /nonexistent-health-endpoint.",
    "claim_level": "Observed",
    "predicate_inputs": {
        "failed_revision_detail": repo_rel("02-failed-revision-detail.json"),
        "system_logs": repo_rel("04-system-logs.json"),
        "kql_probefailed_rows": repo_rel("07-kql-probefailed-rows.json"),
        "kql_event_correlation": repo_rel("08-kql-event-correlation.json"),
        "kql_console_logs": repo_rel("10-kql-console-logs.json"),
    },
    "thresholds": {
        "raw_system_probefailed_min": 9,
        "raw_system_containerterminated_min": 4,
        "kql_probefailed_rows_min": 20,
        "bad_probe_path": BAD_PATH,
    },
    "path_used": "single",
    "sub_gates": sub_gates,
    "revision_provisioning_failure_h1_trigger_produces_failure_sub_gates": gate_bool_map(sub_gates),
    "revision_provisioning_failure_h1_trigger_produces_failure_all_subgates_pass": all(item["result"] == "pass" for item in sub_gates),
    "gate_classification": "H1 gate: confirms the bad-path startup probe produced a revision-scoped restart loop and nginx 404 evidence on the probe target.",
}

(EVIDENCE_DIR / "15-h1-trigger-produces-failure-gate.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
all_pass = payload["revision_provisioning_failure_h1_trigger_produces_failure_all_subgates_pass"]
print("wrote 15-h1-trigger-produces-failure-gate.json; verdict=" + ("PASS" if all_pass else "FAIL"))
raise SystemExit(0 if all_pass else 1)
PY
)"; then
    pass_gate 15 "$GATE15_OUTPUT"
else
    fail_gate 15 "$GATE15_OUTPUT"
fi

if GATE16_OUTPUT="$(python3 <<'PY'
import json
import os
from pathlib import Path

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
UTC_NOW = os.environ["UTC_NOW"]

FAILED_REVISION = "ca-labrevprov-e2upm2--badpath2"
RECOVERED_REVISION = "ca-labrevprov-e2upm2--badpath3"


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


def gate_bool_map(entries):
    return {entry["sub_gate"]: entry["result"] == "pass" for entry in entries}


def sub_gate(name, claim, predicate, level, passed, evidence_files, observed_values):
    return {
        "sub_gate": name,
        "claim": claim,
        "predicate": predicate,
        "claim_level": level,
        "result": "pass" if passed else "fail",
        "evidence_files": evidence_files,
        "observed_values": observed_values,
    }


postfix = json.loads((EVIDENCE_DIR / "11-kql-postfix-verification.json").read_text(encoding="utf-8"))
recovered = json.loads((EVIDENCE_DIR / "12-revision-list-recovered.json").read_text(encoding="utf-8"))
rev = recovered[0]
props = rev["properties"]
container = props["template"]["containers"][0]
probe = container["probes"][0]

a_pass = (
    rev["name"] == RECOVERED_REVISION
    and props.get("healthState") == "Healthy"
    and props.get("provisioningState") == "Provisioned"
    and props.get("runningState") == "RunningAtMaxScale"
    and props.get("trafficWeight") == 100
)

b_pass = (
    container.get("image") == "nginx:alpine"
    and probe.get("type") == "Startup"
    and probe["httpGet"].get("path") == "/"
    and probe["httpGet"].get("port") == 80
)

badpath3_rows = [r for r in postfix if r.get("RevisionName_s") == RECOVERED_REVISION]
badpath2_rows = [r for r in postfix if r.get("RevisionName_s") == FAILED_REVISION]
badpath3_reasons = {r.get("Reason_s") for r in badpath3_rows}
badpath3_counts = {r.get("Reason_s"): int(r.get("EventCount", "0")) for r in badpath3_rows}
badpath2_counts = {r.get("Reason_s"): int(r.get("EventCount", "0")) for r in badpath2_rows}
c_pass = (
    badpath3_counts.get("ContainerStarted", 0) >= 1
    and badpath3_counts.get("ContainerCreated", 0) >= 1
    and badpath3_counts.get("ProbeFailed", 0) == 0
    and badpath3_counts.get("ContainerTerminated", 0) == 0
)

d_pass = (
    badpath2_counts.get("ProbeFailed", 0) >= 56
    and badpath2_counts.get("ContainerTerminated", 0) >= 14
    and RECOVERED_REVISION not in {r.get("RevisionName_s") for r in postfix if r.get("Reason_s") == "ProbeFailed"}
)

sub_gates = [
    sub_gate(
        "a_recovered_revision_is_healthy_and_provisioned",
        "The recovered revision badpath3 is Healthy / Provisioned / RunningAtMaxScale with 100% traffic.",
        "12[0].name == badpath3 AND healthState == Healthy AND provisioningState == Provisioned AND runningState == RunningAtMaxScale AND trafficWeight == 100.",
        "Observed",
        a_pass,
        [repo_rel("12-revision-list-recovered.json")],
        {
            "revision_name": rev["name"],
            "health_state": props.get("healthState"),
            "provisioning_state": props.get("provisioningState"),
            "running_state": props.get("runningState"),
            "traffic_weight": props.get("trafficWeight"),
        },
    ),
    sub_gate(
        "b_fix_changed_probe_path_to_root",
        "The fix deployed the same nginx image with Startup probe path=/ on port 80.",
        "12[0].template.containers[0].image == nginx:alpine AND probe.type == Startup AND probe.httpGet.path == '/' AND probe.httpGet.port == 80.",
        "Observed",
        b_pass,
        [repo_rel("12-revision-list-recovered.json")],
        {
            "image": container.get("image"),
            "probe_type": probe.get("type"),
            "probe_path": probe["httpGet"].get("path"),
            "probe_port": probe["httpGet"].get("port"),
        },
    ),
    sub_gate(
        "c_postfix_kql_shows_clean_badpath3_surface",
        "Post-fix KQL shows badpath3 started successfully with zero ProbeFailed and zero ContainerTerminated rows.",
        "11 rows for badpath3 contain ContainerStarted >= 1 AND ContainerCreated >= 1 AND ProbeFailed == 0 AND ContainerTerminated == 0.",
        "Measured",
        c_pass,
        [repo_rel("11-kql-postfix-verification.json")],
        {
            "badpath3_reason_counts": badpath3_counts,
            "badpath3_reasons_present": sorted(badpath3_reasons),
        },
    ),
    sub_gate(
        "d_postfix_kql_retains_h1_history_only_on_badpath2",
        "The post-fix KQL evidence retains the historical H1 failures on badpath2 while showing none on badpath3.",
        "11 contains ProbeFailed >= 56 and ContainerTerminated >= 14 on badpath2 AND zero ProbeFailed rows on badpath3.",
        "Observed",
        d_pass,
        [repo_rel("11-kql-postfix-verification.json")],
        {
            "badpath2_reason_counts": badpath2_counts,
            "badpath3_reason_counts": badpath3_counts,
        },
    ),
]

payload = {
    "utc_captured": UTC_NOW,
    "scenario": "revision_provisioning_failure",
    "hypothesis": "H2_fix_restores_recovery",
    "claim": "The H2 fix restored recovery: ca-labrevprov-e2upm2--badpath3 is Healthy/Provisioned with startup probe path=/ on port 80, and the post-fix KQL verification shows badpath3 with startup success events but zero ProbeFailed / zero ContainerTerminated while the historical H1 failures remain isolated to badpath2.",
    "claim_level": "Observed",
    "predicate_inputs": {
        "postfix_verification": repo_rel("11-kql-postfix-verification.json"),
        "recovered_revision_list": repo_rel("12-revision-list-recovered.json"),
    },
    "thresholds": {
        "badpath3_probefailed_expected": 0,
        "badpath3_containerterminated_expected": 0,
        "badpath2_probefailed_floor": 56,
        "badpath2_containerterminated_floor": 14,
    },
    "path_used": "single",
    "sub_gates": sub_gates,
    "revision_provisioning_failure_h2_fix_restores_recovery_sub_gates": gate_bool_map(sub_gates),
    "revision_provisioning_failure_h2_fix_restores_recovery_all_subgates_pass": all(item["result"] == "pass" for item in sub_gates),
    "gate_classification": "H2 gate: confirms recovery on the fixed revision and explicitly scopes the retained ProbeFailed history to the old failed revision.",
}

(EVIDENCE_DIR / "16-h2-fix-restores-recovery-gate.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
all_pass = payload["revision_provisioning_failure_h2_fix_restores_recovery_all_subgates_pass"]
print("wrote 16-h2-fix-restores-recovery-gate.json; verdict=" + ("PASS" if all_pass else "FAIL"))
raise SystemExit(0 if all_pass else 1)
PY
)"; then
    pass_gate 16 "$GATE16_OUTPUT"
else
    fail_gate 16 "$GATE16_OUTPUT"
fi

if GATE17_OUTPUT="$(python3 <<'PY'
import json
import os
from pathlib import Path

import yaml

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
UTC_NOW = os.environ["UTC_NOW"]

APP_NAME = "ca-labrevprov-e2upm2"
BASELINE_REVISION = "ca-labrevprov-e2upm2--badpath"
FAILED_REVISION = "ca-labrevprov-e2upm2--badpath2"
RECOVERED_REVISION = "ca-labrevprov-e2upm2--badpath3"
BAD_PATH = "/nonexistent-health-endpoint"


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


def gate_bool_map(entries):
    return {entry["sub_gate"]: entry["result"] == "pass" for entry in entries}


def sub_gate(name, claim, predicate, level, passed, evidence_files, observed_values):
    return {
        "sub_gate": name,
        "claim": claim,
        "predicate": predicate,
        "claim_level": level,
        "result": "pass" if passed else "fail",
        "evidence_files": evidence_files,
        "observed_values": observed_values,
    }


before = json.loads((EVIDENCE_DIR / "02-failed-revision-detail.json").read_text(encoding="utf-8"))
spec = yaml.safe_load((EVIDENCE_DIR / "03-containerapp-spec.yaml").read_text(encoding="utf-8"))
after = json.loads((EVIDENCE_DIR / "12-revision-list-recovered.json").read_text(encoding="utf-8"))[0]
lineage = json.loads((EVIDENCE_DIR / "01-revision-list.json").read_text(encoding="utf-8"))

h1_probe = before["properties"]["template"]["containers"][0]["probes"][0]
h2_probe = after["properties"]["template"]["containers"][0]["probes"][0]
spec_probe = spec["properties"]["template"]["containers"][0]["probes"][0]

path_delta = [h1_probe["httpGet"].get("path"), h2_probe["httpGet"].get("path")]
a_pass = path_delta == [BAD_PATH, "/"] and spec_probe["httpGet"].get("path") == BAD_PATH

probe_surface_differences = {}
for key, h1_value, h2_value in [
    ("httpGet.path", h1_probe["httpGet"].get("path"), h2_probe["httpGet"].get("path")),
    ("httpGet.port", h1_probe["httpGet"].get("port"), h2_probe["httpGet"].get("port")),
    ("httpGet.scheme", h1_probe["httpGet"].get("scheme"), h2_probe["httpGet"].get("scheme")),
    ("type", h1_probe.get("type"), h2_probe.get("type")),
    ("failureThreshold", h1_probe.get("failureThreshold"), h2_probe.get("failureThreshold")),
    ("periodSeconds", h1_probe.get("periodSeconds"), h2_probe.get("periodSeconds")),
    ("initialDelaySeconds", h1_probe.get("initialDelaySeconds"), h2_probe.get("initialDelaySeconds")),
    ("successThreshold", h1_probe.get("successThreshold"), h2_probe.get("successThreshold")),
    ("timeoutSeconds", h1_probe.get("timeoutSeconds"), h2_probe.get("timeoutSeconds")),
]:
    if h1_value != h2_value:
        probe_surface_differences[key] = [h1_value, h2_value]

expected_probe_difference_keys = {
    "httpGet.path",
    "httpGet.scheme",
    "initialDelaySeconds",
    "successThreshold",
    "timeoutSeconds",
}

held_constant_observed = {
    "container_app_name": [spec.get("name"), before.get("name").rsplit("--", 1)[0], after.get("name").rsplit("--", 1)[0]],
    "image_tag": [before["properties"]["template"]["containers"][0].get("image"), after["properties"]["template"]["containers"][0].get("image")],
    "http_port": [h1_probe["httpGet"].get("port"), h2_probe["httpGet"].get("port")],
    "probe_type": [h1_probe.get("type"), h2_probe.get("type")],
    "failure_threshold": [h1_probe.get("failureThreshold"), h2_probe.get("failureThreshold")],
    "period_seconds": [h1_probe.get("periodSeconds"), h2_probe.get("periodSeconds")],
    "cpu": [before["properties"]["template"]["containers"][0]["resources"].get("cpu"), after["properties"]["template"]["containers"][0]["resources"].get("cpu")],
    "memory": [before["properties"]["template"]["containers"][0]["resources"].get("memory"), after["properties"]["template"]["containers"][0]["resources"].get("memory")],
    "resource_group": [before.get("resourceGroup"), after.get("resourceGroup")],
}

all_constant_checks = {
    key: len(set(values)) == 1 for key, values in held_constant_observed.items()
}
b_pass = all(all_constant_checks.values()) and set(probe_surface_differences) == expected_probe_difference_keys

explicit_drops = [
    {
        "id": "probe_field_delta_minus_path_is_not_bounded",
        "note": "H1 vs H2 also differ in httpGet.scheme, initialDelaySeconds, timeoutSeconds, and successThreshold; these probe-field deltas are documented confounders, not bounded variables.",
    },
    {
        "id": "image_byte_identity_not_captured",
        "note": "The H1/H2 image tag remains nginx:alpine, but the cohort does not capture image digests.",
    },
    {
        "id": "pod_reuse_not_proven",
        "note": "Revision names differ (badpath2 vs badpath3), so the cohort does not claim pod reuse.",
    },
    {
        "id": "socket_listening_port_not_directly_observed",
        "note": "Port 80 is inferred from the spec and nginx behavior, not from a direct socket capture inside the container.",
    },
]
baseline_image = lineage[0]["properties"]["template"]["containers"][0].get("image")
h1_image = before["properties"]["template"]["containers"][0].get("image")
h2_image = after["properties"]["template"]["containers"][0].get("image")
expected_drop_ids = {
    "probe_field_delta_minus_path_is_not_bounded",
    "image_byte_identity_not_captured",
    "pod_reuse_not_proven",
    "socket_listening_port_not_directly_observed",
}
c_pass = {item["id"] for item in explicit_drops} == expected_drop_ids and set(probe_surface_differences) == expected_probe_difference_keys

created = {item["name"]: item["properties"]["createdTime"] for item in lineage}
d_pass = (
    lineage[0]["name"] == BASELINE_REVISION
    and lineage[1]["name"] == FAILED_REVISION
    and after["name"] == RECOVERED_REVISION
    and BASELINE_REVISION in created
    and FAILED_REVISION in created
    and created[BASELINE_REVISION] < created[FAILED_REVISION] < after["properties"]["createdTime"]
    and all(name.startswith(f"{APP_NAME}--badpath") for name in [BASELINE_REVISION, FAILED_REVISION, RECOVERED_REVISION])
    and baseline_image != h1_image
    and h1_image == h2_image
)

sub_gates = [
    sub_gate(
        "a_probe_path_is_the_bounded_trigger_field",
        "The mechanically observable trigger field under test is the startup-probe httpGet.path: H1 uses /nonexistent-health-endpoint and H2 uses /.",
        "H1 probe path == '/nonexistent-health-endpoint' AND H2 probe path == '/' AND the spec capture for badpath2 also shows '/nonexistent-health-endpoint'.",
        "Observed",
        a_pass,
        [repo_rel("02-failed-revision-detail.json"), repo_rel("03-containerapp-spec.yaml"), repo_rel("12-revision-list-recovered.json")],
        {
            "h1_probe_path": h1_probe["httpGet"].get("path"),
            "spec_probe_path": spec_probe["httpGet"].get("path"),
            "h2_probe_path": h2_probe["httpGet"].get("path"),
        },
    ),
    sub_gate(
        "b_held_constant_fields_match_byte_for_byte",
        "The directly captured held-constant fields across H1 and H2 are byte-identical, and the full H1↔H2 probe diff shows no unexpected deltas beyond the documented confounders.",
        "container_app_name, image_tag, httpGet.port, type, failureThreshold, periodSeconds, cpu, memory, and resource_group compare equal across H1 and H2 AND observed probe diff keys equal {httpGet.path, httpGet.scheme, initialDelaySeconds, successThreshold, timeoutSeconds}.",
        "Observed",
        b_pass,
        [repo_rel("02-failed-revision-detail.json"), repo_rel("03-containerapp-spec.yaml"), repo_rel("12-revision-list-recovered.json")],
        {
            "held_constant_observed": held_constant_observed,
            "held_constant_checks": all_constant_checks,
            "expected_probe_difference_keys": sorted(expected_probe_difference_keys),
            "observed_probe_differences": probe_surface_differences,
        },
    ),
    sub_gate(
        "c_explicit_drops_document_the_confounders",
        "The bounded-falsification gate explicitly lists the documented confounders, and the probe-field drop matches the actual H1↔H2 diff.",
        "cohort_binding_note.explicit_drops ids equal {probe_field_delta_minus_path_is_not_bounded, image_byte_identity_not_captured, pod_reuse_not_proven, socket_listening_port_not_directly_observed} AND observed probe diff keys equal {httpGet.path, httpGet.scheme, initialDelaySeconds, successThreshold, timeoutSeconds}.",
        "Observed",
        c_pass,
        [repo_rel("17-bounded-falsification-gate.json")],
        {
            "expected_drop_ids": sorted(expected_drop_ids),
            "observed_drop_ids": sorted(item["id"] for item in explicit_drops),
            "expected_probe_difference_keys": sorted(expected_probe_difference_keys),
            "observed_probe_difference_keys": sorted(probe_surface_differences),
        },
    ),
    sub_gate(
        "d_revision_lineage_is_clear_and_ordered",
        "The lineage badpath -> badpath2 -> badpath3 is clear across the before/recovery captures, and the pre-trigger baseline disclosure records that badpath still used the original helloworld image while the bounded comparison begins at badpath2 -> badpath3.",
        "01 contains badpath and badpath2, 12 contains badpath3, createdTime ordering is badpath < badpath2 < badpath3, and baseline image != H1/H2 image while H1/H2 image tags match.",
        "Observed",
        d_pass,
        [repo_rel("01-revision-list.json"), repo_rel("02-failed-revision-detail.json"), repo_rel("12-revision-list-recovered.json")],
        {
            "lineage_created_times": {
                BASELINE_REVISION: created.get(BASELINE_REVISION),
                FAILED_REVISION: created.get(FAILED_REVISION),
                RECOVERED_REVISION: after["properties"].get("createdTime"),
            },
            "lineage_names": [BASELINE_REVISION, FAILED_REVISION, RECOVERED_REVISION],
            "baseline_image": baseline_image,
            "h1_image": h1_image,
            "h2_image": h2_image,
            "bounded_comparison_revisions": [FAILED_REVISION, RECOVERED_REVISION],
        },
    ),
]

payload = {
    "utc_captured": UTC_NOW,
    "scenario": "revision_provisioning_failure",
    "hypothesis": "H3_bounded_falsification",
    "claim": "This evidence pack falsifies the startup-probe failure hypothesis within a bounded scope. Gate 17 demonstrates that probe-path reachability is the mechanically observable trigger field while held-constant fields remain byte-identical on the bounded surface. The pack does not claim single-variable falsification because non-path probe fields also changed and are documented as explicit confounders.",
    "claim_level": "Observed",
    "predicate_inputs": {
        "failed_revision_detail": repo_rel("02-failed-revision-detail.json"),
        "container_app_spec": repo_rel("03-containerapp-spec.yaml"),
        "revision_list_before": repo_rel("01-revision-list.json"),
        "recovered_revision_list": repo_rel("12-revision-list-recovered.json"),
    },
    "thresholds": {
        "h1_path_expected": BAD_PATH,
        "h2_path_expected": "/",
        "held_constant_field_count": len(held_constant_observed),
    },
    "path_used": "bounded",
    "sub_gates": sub_gates,
    "revision_provisioning_failure_h3_bounded_falsification_sub_gates": gate_bool_map(sub_gates),
    "revision_provisioning_failure_h3_bounded_falsification_all_subgates_pass": all(item["result"] == "pass" for item in sub_gates),
    "cohort_binding_note": {
        "claim_ceiling": "The bounded claim is that probe-path reachability is the mechanically observable trigger field in this cohort. The pack does NOT prove image byte identity, pod reuse, direct socket observation, or that the non-path probe-field deltas are bounded.",
        "explicit_drops": explicit_drops,
    },
    "gate_classification": "Bounded falsification gate: isolates the path reachability claim while explicitly documenting the confounding probe-field deltas and other unsupported inferences.",
}

(EVIDENCE_DIR / "17-bounded-falsification-gate.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
all_pass = payload["revision_provisioning_failure_h3_bounded_falsification_all_subgates_pass"]
print("wrote 17-bounded-falsification-gate.json; verdict=" + ("PASS" if all_pass else "FAIL"))
raise SystemExit(0 if all_pass else 1)
PY
)"; then
    pass_gate 17 "$GATE17_OUTPUT"
else
    fail_gate 17 "$GATE17_OUTPUT"
fi

python3 <<'PY'
import json
import os
from pathlib import Path

evidence_dir = Path(os.environ["EVIDENCE_DIR"])
gates = [
    ("14-cohort-integrity-gate.json", "revision_provisioning_failure_h_cohort_integrity_all_subgates_pass", "H_cohort_integrity"),
    ("15-h1-trigger-produces-failure-gate.json", "revision_provisioning_failure_h1_trigger_produces_failure_all_subgates_pass", "H1_trigger_produces_failure"),
    ("16-h2-fix-restores-recovery-gate.json", "revision_provisioning_failure_h2_fix_restores_recovery_all_subgates_pass", "H2_fix_restores_recovery"),
    ("17-bounded-falsification-gate.json", "revision_provisioning_failure_h3_bounded_falsification_all_subgates_pass", "H3_bounded_falsification"),
]

summary = []
total = 0
passed = 0
overall = True
for filename, key, hypothesis in gates:
    payload = json.loads((evidence_dir / filename).read_text(encoding="utf-8"))
    gate_pass = bool(payload.get(key))
    sub_total = len(payload.get("sub_gates", []))
    sub_pass = sum(1 for item in payload.get("sub_gates", []) if item.get("result") == "pass")
    total += sub_total
    passed += sub_pass
    overall = overall and gate_pass
    summary.append((filename, hypothesis, sub_pass, sub_total, gate_pass))

print()
print("===== Phase B summary =====")
print("Gate file                                   Hypothesis                           Sub-gates  Verdict")
print("------------------------------------------  -----------------------------------  ---------  -------")
for filename, hypothesis, sub_pass, sub_total, gate_pass in summary:
    print(f"{filename:<42}  {hypothesis:<35}  {str(sub_pass) + '/' + str(sub_total):>9}  {'PASS' if gate_pass else 'FAIL'}")
print()
print(f"TOTAL: {passed}/{total} Phase B sub-gates PASS")
print(f"PHASE B VERDICT: {'PASS' if overall else 'FAIL'}")
raise SystemExit(0 if overall else 1)
PY
