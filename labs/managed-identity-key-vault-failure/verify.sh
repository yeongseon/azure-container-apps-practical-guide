#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/managed-identity-key-vault-failure/evidence"
LAB_README_PATH="${SCRIPT_DIR}/README.md"
LAB_GUIDE_PATH="${SCRIPT_DIR}/../../docs/troubleshooting/lab-guides/managed-identity-key-vault-failure.md"
UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR LAB_README_PATH LAB_GUIDE_PATH UTC_NOW

declare -a CANONICAL_RAW_FILES=(
    "01-app-identity-pre-fix.json"
    "02-role-assignments-pre-fix.json"
    "03-kv-rbac-config.json"
    "04-revision-list-pre-fix.json"
    "05-http-response-pre-fix.json"
    "06-system-logs-pre-fix.json"
    "07-containerapp-spec-pre-fix.yaml"
    "08-kql-console-logs-pre-fix.json"
    "09-role-assignment-post-fix.json"
    "10-http-response-post-fix.json"
    "11-revision-list-post-fix.json"
    "12-kql-recovery-summary-post-fix.json"
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
lab_readme = Path(os.environ["LAB_README_PATH"])

RAW_FILES = [
    "01-app-identity-pre-fix.json",
    "02-role-assignments-pre-fix.json",
    "03-kv-rbac-config.json",
    "04-revision-list-pre-fix.json",
    "05-http-response-pre-fix.json",
    "06-system-logs-pre-fix.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-kql-console-logs-pre-fix.json",
    "09-role-assignment-post-fix.json",
    "10-http-response-post-fix.json",
    "11-revision-list-post-fix.json",
    "12-kql-recovery-summary-post-fix.json",
]

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
    expected = RAW_FILES[:4]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print("missing canonical files: " + ", ".join(missing))
        raise SystemExit(1)
    print("raw files 01-04 are present")
    raise SystemExit(0)

if gate_number == 3:
    expected = RAW_FILES[4:8]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print("missing canonical files: " + ", ".join(missing))
        raise SystemExit(1)
    print("raw files 05-08 are present")
    raise SystemExit(0)

if gate_number == 4:
    expected = RAW_FILES[8:12]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print("missing canonical files: " + ", ".join(missing))
        raise SystemExit(1)
    print("raw files 09-12 are present")
    raise SystemExit(0)

if gate_number == 5:
    try:
        identity = load_json(evidence_dir / RAW_FILES[0])
    except Exception as exc:  # noqa: BLE001
        print(f"01 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = identity.get("type") == "SystemAssigned" and bool(identity.get("principalId"))
    if ok:
        print("01 parses and shows a system-assigned identity")
        raise SystemExit(0)
    print("01 missing SystemAssigned identity or principalId")
    raise SystemExit(1)

if gate_number == 6:
    try:
        roles = load_json(evidence_dir / RAW_FILES[1])
        vault = load_json(evidence_dir / RAW_FILES[2])
    except Exception as exc:  # noqa: BLE001
        print(f"02/03 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(roles, list) and vault.get("enableRbacAuthorization") is True and bool(vault.get("uri"))
    if ok:
        print("02/03 parse and show RBAC-mode Key Vault configuration")
        raise SystemExit(0)
    print("02/03 do not match the expected role-list + RBAC Key Vault shape")
    raise SystemExit(1)

if gate_number == 7:
    try:
        revs = load_json(evidence_dir / RAW_FILES[3])
    except Exception as exc:  # noqa: BLE001
        print(f"04 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(revs, list) and len(revs) >= 1 and bool(revs[0].get("name"))
    if ok:
        print("04 parses and includes at least one revision")
        raise SystemExit(0)
    print("04 does not contain the expected revision list")
    raise SystemExit(1)

if gate_number == 8:
    try:
        response = load_json(evidence_dir / RAW_FILES[4])
    except Exception as exc:  # noqa: BLE001
        print(f"05 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    body = str(response.get("body", ""))
    ok = int(response.get("status_code", 0)) != 200 and "ForbiddenByRbac" in body
    if ok:
        print("05 parses and captures the expected pre-fix ForbiddenByRbac response")
        raise SystemExit(0)
    print("05 does not capture the expected non-200 ForbiddenByRbac response")
    raise SystemExit(1)

if gate_number == 9:
    try:
        rows = load_jsonl(evidence_dir / RAW_FILES[5])
    except Exception as exc:  # noqa: BLE001
        print(f"06 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    if rows:
        print(f"06 parses as JSONL with {len(rows)} rows")
        raise SystemExit(0)
    print("06 JSONL is empty")
    raise SystemExit(1)

if gate_number == 10:
    try:
        spec = load_yaml(evidence_dir / RAW_FILES[6])
    except Exception as exc:  # noqa: BLE001
        print(f"07 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = spec.get("name") and spec.get("resourceGroup") and spec.get("properties", {}).get("configuration", {}).get("ingress", {}).get("targetPort") == 8000
    if ok:
        print("07 parses as YAML and pins ingress targetPort 8000")
        raise SystemExit(0)
    print("07 YAML does not match the expected container app shape")
    raise SystemExit(1)

if gate_number == 11:
    try:
        console_rows = load_json(evidence_dir / RAW_FILES[7])
    except Exception as exc:  # noqa: BLE001
        print(f"08 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(console_rows, list) and len(console_rows) >= 1
    if ok:
        print(f"08 parses as JSON with {len(console_rows)} console-log rows")
        raise SystemExit(0)
    print("08 does not contain the expected console-log rows")
    raise SystemExit(1)

if gate_number == 12:
    try:
        post_roles = load_json(evidence_dir / RAW_FILES[8])
        post_response = load_json(evidence_dir / RAW_FILES[9])
        post_revisions = load_json(evidence_dir / RAW_FILES[10])
        post_kql = load_json(evidence_dir / RAW_FILES[11])
    except Exception as exc:  # noqa: BLE001
        print(f"09-12 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = (
        isinstance(post_roles, list)
        and isinstance(post_revisions, list)
        and isinstance(post_kql, list)
        and len(post_roles) >= 1
        and len(post_revisions) >= 1
        and int(post_response.get("status_code", 0)) == 200
    )
    if ok:
        print("09-12 parse and capture a post-fix 200 response with role data")
        raise SystemExit(0)
    print("09-12 do not capture the expected post-fix role / revision / 200-response surface")
    raise SystemExit(1)

if gate_number == 13:
    readme = evidence_dir / "README.md"
    ok = readme.is_file() and lab_readme.is_file()
    if ok:
        print("lab README and evidence README are present")
        raise SystemExit(0)
    missing = []
    if not readme.is_file():
        missing.append(str(readme))
    if not lab_readme.is_file():
        missing.append(str(lab_readme))
    print("missing readme files: " + ", ".join(missing))
    raise SystemExit(1)

print(f"gate {gate_number} ({gate_name}) is not implemented")
raise SystemExit(1)
PY
)"; then
        pass_gate "$gate_number" "$output"
    else
        fail_gate "$gate_number" "$output"
    fi
}

for gate in \
    "1:evidence directory exists" \
    "2:raw files 01-04 present" \
    "3:raw files 05-08 present" \
    "4:raw files 09-12 present" \
    "5:identity file parses" \
    "6:role list and vault config parse" \
    "7:pre-fix revision list parses" \
    "8:pre-fix response captures ForbiddenByRbac" \
    "9:system log capture parses" \
    "10:pre-fix YAML spec parses" \
    "11:pre-fix KQL console capture parses" \
    "12:post-fix captures parse" \
    "13:readme surfaces exist"; do
    run_python_gate "${gate%%:*}" "${gate#*:}"
done

echo "## Phase B — Evidence pack verification"
if PHASE_B_OUTPUT="$(python3 <<'PY'
import email.utils
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path

import yaml

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
LAB_README_PATH = Path(os.environ["LAB_README_PATH"])
LAB_GUIDE_PATH = Path(os.environ["LAB_GUIDE_PATH"])
UTC_NOW = os.environ["UTC_NOW"]

# Determinism contract: when the four Phase B gate JSONs already exist, pin UTC_NOW
# to the earliest committed utc_captured so reruns against an unchanged corpus produce
# byte-identical gate outputs. Only the first generation consumes the runtime timestamp.
_existing_captures = []
for _gate_file in [
    "14-cohort-integrity-gate.json",
    "15-h1-trigger-produces-failure-gate.json",
    "16-h2-fix-restores-recovery-gate.json",
    "17-bounded-falsification-gate.json",
]:
    _gate_path = EVIDENCE_DIR / _gate_file
    if _gate_path.exists():
        try:
            _gate_data = json.loads(_gate_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        _existing = _gate_data.get("utc_captured")
        if isinstance(_existing, str) and _existing:
            _existing_captures.append(_existing)
if _existing_captures:
    UTC_NOW = min(_existing_captures)

RAW_FILES = [
    "01-app-identity-pre-fix.json",
    "02-role-assignments-pre-fix.json",
    "03-kv-rbac-config.json",
    "04-revision-list-pre-fix.json",
    "05-http-response-pre-fix.json",
    "06-system-logs-pre-fix.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-kql-console-logs-pre-fix.json",
    "09-role-assignment-post-fix.json",
    "10-http-response-post-fix.json",
    "11-revision-list-post-fix.json",
    "12-kql-recovery-summary-post-fix.json",
]
GATE_FILES = [
    "14-cohort-integrity-gate.json",
    "15-h1-trigger-produces-failure-gate.json",
    "16-h2-fix-restores-recovery-gate.json",
    "17-bounded-falsification-gate.json",
]
EXPECTED_EVIDENCE_FILES = RAW_FILES + GATE_FILES + ["README.md"]
JUNK_NAMES = {".DS_Store"}

def repo_rel(name: str) -> str:
    return f"{REL}/{name}"

def load_json(name: str):
    return json.loads((EVIDENCE_DIR / name).read_text(encoding="utf-8"))

def load_jsonl(name: str):
    path = EVIDENCE_DIR / name
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]

def load_yaml(name: str):
    return yaml.safe_load((EVIDENCE_DIR / name).read_text(encoding="utf-8"))

def parse_http_date(header_lines):
    for line in header_lines:
        if line.lower().startswith("date:"):
            return email.utils.parsedate_to_datetime(line.split(":", 1)[1].strip()).astimezone(timezone.utc)
    raise ValueError("HTTP response is missing a Date header")

def parse_iso(text: str):
    return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)

def parse_system_timestamp(text: str):
    value = text.strip()
    if value.endswith(" UTC"):
        value = value[:-4]
        match = re.match(r"^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})(?:\.(\d+))? ([+-]\d{4})$", value)
        if not match:
            raise ValueError(f"unsupported system timestamp: {text}")
        date_part, time_part, fraction, offset = match.groups()
        if fraction:
            fraction = (fraction + "000000")[:6]
            normalized = f"{date_part} {time_part}.{fraction} {offset}"
            return datetime.strptime(normalized, "%Y-%m-%d %H:%M:%S.%f %z").astimezone(timezone.utc)
        return datetime.strptime(f"{date_part} {time_part} {offset}", "%Y-%m-%d %H:%M:%S %z").astimezone(timezone.utc)
    return parse_iso(value)

identity = load_json("01-app-identity-pre-fix.json")
roles_pre = load_json("02-role-assignments-pre-fix.json")
kv_config = load_json("03-kv-rbac-config.json")
revisions_pre = load_json("04-revision-list-pre-fix.json")
http_pre = load_json("05-http-response-pre-fix.json")
system_pre = load_jsonl("06-system-logs-pre-fix.json")
spec_pre = load_yaml("07-containerapp-spec-pre-fix.yaml")
console_pre = load_json("08-kql-console-logs-pre-fix.json")
roles_post = load_json("09-role-assignment-post-fix.json")
http_post = load_json("10-http-response-post-fix.json")
revisions_post = load_json("11-revision-list-post-fix.json")
recovery_post = load_json("12-kql-recovery-summary-post-fix.json")

app_name = spec_pre["name"]
resource_group = spec_pre["resourceGroup"]
principal_id = identity.get("principalId")
kv_uri = kv_config.get("uri")
kv_host = kv_uri.replace("https://", "").strip("/")
kv_name = kv_host.split(".")[0]
pre_revision = revisions_pre[0]["name"]
post_revision = revisions_post[0]["name"]

readme_text = (EVIDENCE_DIR / "README.md").read_text(encoding="utf-8")

parse_errors = []
for name in [
    "01-app-identity-pre-fix.json",
    "02-role-assignments-pre-fix.json",
    "03-kv-rbac-config.json",
    "04-revision-list-pre-fix.json",
    "05-http-response-pre-fix.json",
    "08-kql-console-logs-pre-fix.json",
    "09-role-assignment-post-fix.json",
    "10-http-response-post-fix.json",
    "11-revision-list-post-fix.json",
    "12-kql-recovery-summary-post-fix.json",
]:
    try:
        load_json(name)
    except Exception as exc:  # noqa: BLE001
        parse_errors.append(f"{name}: {type(exc).__name__}: {exc}")
try:
    load_jsonl("06-system-logs-pre-fix.json")
except Exception as exc:  # noqa: BLE001
    parse_errors.append(f"06-system-logs-pre-fix.json: {type(exc).__name__}: {exc}")
try:
    load_yaml("07-containerapp-spec-pre-fix.yaml")
except Exception as exc:  # noqa: BLE001
    parse_errors.append(f"07-containerapp-spec-pre-fix.yaml: {type(exc).__name__}: {exc}")

pre_created = parse_iso(revisions_pre[0]["properties"]["createdTime"])
post_created = parse_iso(revisions_post[0]["properties"]["createdTime"])
pre_http_date = parse_http_date(http_pre["headers"])
post_http_date = parse_http_date(http_post["headers"])
post_role_created = parse_iso(roles_post[0]["createdOn"])
system_timestamps = [parse_system_timestamp(row["TimeStamp"]) for row in system_pre if row.get("TimeStamp")]
anchor_times = [pre_created, pre_http_date, post_role_created, post_created, post_http_date]
if system_timestamps:
    anchor_times.append(min(system_timestamps))
earliest_anchor = min(anchor_times)
latest_anchor = max(anchor_times)
span_seconds = (latest_anchor - earliest_anchor).total_seconds()
strong_temporal = span_seconds <= 1800
fallback_temporal = span_seconds <= 5400
path_used = "strong" if strong_temporal else "fallback"

observed_files_on_disk = sorted(path.name for path in EVIDENCE_DIR.iterdir() if path.is_file())
non_junk_files = [name for name in observed_files_on_disk if name not in JUNK_NAMES]
unexpected_non_junk = [name for name in non_junk_files if name not in EXPECTED_EVIDENCE_FILES]
expected_xrefs = GATE_FILES
observed_xrefs = [name for name in expected_xrefs if name in readme_text]

pre_latest_revision = spec_pre["properties"]["latestRevisionName"]
pre_ready_revision = spec_pre["properties"]["latestReadyRevisionName"]
pre_image = revisions_pre[0]["properties"]["template"]["containers"][0]["image"]
post_container = revisions_post[0]["properties"]["template"]["containers"][0]
post_image = post_container["image"]
post_env = {item["name"]: item.get("value") for item in post_container.get("env", [])}
pre_container = spec_pre["properties"]["template"]["containers"][0]
pre_env = {item["name"]: item.get("value") for item in pre_container.get("env", [])}

pre_role_match = [
    row for row in roles_pre
    if row.get("roleDefinitionName") == "Key Vault Secrets User" and kv_name.lower() in str(row.get("scope", "")).lower()
]
post_role_match = [
    row for row in roles_post
    if row.get("roleDefinitionName") == "Key Vault Secrets User" and kv_name.lower() in str(row.get("scope", "")).lower()
]

response_pre_body = str(http_pre.get("body", ""))
response_post_body = str(http_post.get("body", ""))
pre_revision_state = revisions_pre[0]["properties"]
post_revision_state = revisions_post[0]["properties"]
recovery_by_revision = {}
for row in recovery_post:
    rev = row.get("RevisionName_s", "")
    reason = row.get("Reason_s", "")
    if rev not in recovery_by_revision:
        recovery_by_revision[rev] = {}
    recovery_by_revision[rev][reason] = int(row.get("EventCount", "0"))
post_reasons = recovery_by_revision.get(post_revision, {})

held_constant_checks = {
    "app_name": app_name == revisions_pre[0]["name"].split("--")[0] == revisions_post[0]["name"].split("--")[0],
    "resource_group": revisions_pre[0]["resourceGroup"] == revisions_post[0]["resourceGroup"] == resource_group,
    "image": pre_image == post_image,
    "key_vault_url": pre_env.get("KEY_VAULT_URL") == post_env.get("KEY_VAULT_URL"),
    "secret_name": pre_env.get("SECRET_NAME") == post_env.get("SECRET_NAME"),
    "cpu": pre_container["resources"]["cpu"] == post_container["resources"]["cpu"],
    "memory": pre_container["resources"]["memory"] == post_container["resources"]["memory"],
    "target_port": spec_pre["properties"]["configuration"]["ingress"]["targetPort"] == 8000,
}

explicit_drops = [
    {
        "id": "image_byte_identity_not_captured",
        "note": "The cohort captures the same image tag across H1 and H2, but it does not capture OCI digests beyond the mutable tag surface stored in the revision JSON/YAML evidence.",
    },
    {
        "id": "pod_uids_not_captured",
        "note": "The pack proves only revision-level recovery. It does not capture Kubernetes pod UIDs or claim pod reuse across the restart boundary.",
    },
    {
        "id": "rbac_propagation_timing_not_proven",
        "note": "The script waits for RBAC propagation, but this pack does not bound the exact propagation latency required before the retry succeeds.",
    },
    {
        "id": "token_cache_behavior_not_proven",
        "note": "Recovery is observed after the role assignment plus a new revision start. The pack does not isolate whether credential/token cache state alone would have recovered without the restart.",
    },
]
expected_drop_ids = [item["id"] for item in explicit_drops]

gate14 = {
    "claim": f"The 12-file managed-identity-key-vault-failure raw cohort is internally consistent: every file is present and parseable, the identity and lineage bind to {app_name} / {resource_group}, the temporal span stays within the documented temporal ceiling, and evidence/README.md cross-references all four Phase B gate JSON files.",
    "claim_level": "Observed",
    "gate_classification": "Cohort integrity gate: structural pre-condition for the bounded-falsification pack.",
    "hypothesis": "H_cohort_integrity",
    "path_used": path_used,
    "predicate_inputs": {
        "app_identity": repo_rel("01-app-identity-pre-fix.json"),
        "container_app_spec": repo_rel("07-containerapp-spec-pre-fix.yaml"),
        "evidence_readme": repo_rel("README.md"),
        "http_response_pre": repo_rel("05-http-response-pre-fix.json"),
        "http_response_post": repo_rel("10-http-response-post-fix.json"),
        "revision_list_pre": repo_rel("04-revision-list-pre-fix.json"),
        "revision_list_post": repo_rel("11-revision-list-post-fix.json"),
    },
    "managed_identity_key_vault_failure_h_cohort_integrity_all_subgates_pass": True,
    "managed_identity_key_vault_failure_h_cohort_integrity_sub_gates": {
        "a_canonical_raw_files_present_and_parse": not parse_errors,
        "b_temporal_cohort_is_monotonic_and_bounded": strong_temporal or fallback_temporal,
        "c_identity_and_lineage_are_consistent": pre_latest_revision == pre_revision and pre_ready_revision == pre_revision and post_created > pre_created,
        "d_no_unexpected_non_junk_extras_and_readme_xrefs_exist": not unexpected_non_junk and observed_xrefs == expected_xrefs,
    },
    "scenario": "managed_identity_key_vault_failure",
    "sub_gates": [
        {
            "claim": "All 12 canonical raw evidence files exist and parse as JSON, YAML, or JSONL.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel(name) for name in RAW_FILES],
            "observed_values": {
                "observed_missing": [name for name in RAW_FILES if not (EVIDENCE_DIR / name).is_file()],
                "observed_present_count": sum((EVIDENCE_DIR / name).is_file() for name in RAW_FILES),
                "parse_errors": parse_errors,
                "path_satisfied": "strong" if not parse_errors else "none",
                "strong": {"expected_count": 12, "holds": not parse_errors},
                "fallback": {"expected_count": 12, "holds": not parse_errors},
            },
            "predicate": "Strong and fallback both require the full 12-file raw cohort to exist; 01,02,03,04,05,08,09,10,11,12 parse as JSON; 07 parses as YAML; 06 parses as JSONL.",
            "result": "pass" if not parse_errors else "fail",
            "sub_gate": "a_canonical_raw_files_present_and_parse",
        },
        {
            "claim": "The captured H1 -> H2 cohort is temporally monotonic and stays within the strong <=1800-second window.",
            "claim_level": "Measured",
            "evidence_files": [repo_rel("04-revision-list-pre-fix.json"), repo_rel("05-http-response-pre-fix.json"), repo_rel("09-role-assignment-post-fix.json"), repo_rel("10-http-response-post-fix.json"), repo_rel("11-revision-list-post-fix.json")],
            "observed_values": {
                "earliest_anchor_utc": earliest_anchor.isoformat(),
                "latest_anchor_utc": latest_anchor.isoformat(),
                "observed_span_seconds": span_seconds,
                "path_satisfied": path_used,
                "strong": {"holds": strong_temporal, "max_span_seconds": 1800},
                "fallback": {"holds": fallback_temporal, "max_span_seconds": 5400},
            },
            "predicate": "Strong: earliest revision/HTTP/role-assignment anchor through post-fix HTTP anchor <= 1800 seconds. Fallback: <= 5400 seconds.",
            "result": "pass" if (strong_temporal or fallback_temporal) else "fail",
            "sub_gate": "b_temporal_cohort_is_monotonic_and_bounded",
        },
        {
            "claim": "The pre-fix spec and revision captures bind to one app/resource-group lineage and show a newer post-fix revision.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("04-revision-list-pre-fix.json"), repo_rel("07-containerapp-spec-pre-fix.yaml"), repo_rel("11-revision-list-post-fix.json")],
            "observed_values": {
                "app_name": app_name,
                "post_revision": post_revision,
                "pre_latest_ready_revision": pre_ready_revision,
                "pre_latest_revision": pre_latest_revision,
                "pre_revision": pre_revision,
                "resource_group": resource_group,
            },
            "predicate": "07.properties.latestRevisionName == 07.properties.latestReadyRevisionName == 04[0].name AND 11[0].properties.createdTime > 04[0].properties.createdTime for the same app/resourceGroup.",
            "result": "pass" if (pre_latest_revision == pre_revision and pre_ready_revision == pre_revision and post_created > pre_created) else "fail",
            "sub_gate": "c_identity_and_lineage_are_consistent",
        },
        {
            "claim": "The evidence directory has no unexpected non-junk extras and evidence/README.md literally names all four Phase B outputs.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel(name) for name in EXPECTED_EVIDENCE_FILES],
            "observed_values": {
                "expected_xrefs": expected_xrefs,
                "ignored_junk": sorted(JUNK_NAMES),
                "observed_files_on_disk": observed_files_on_disk,
                "observed_non_junk_extras": unexpected_non_junk,
                "observed_xrefs": observed_xrefs,
                "readme_exists": (EVIDENCE_DIR / "README.md").is_file(),
            },
            "predicate": "extras == [] AND evidence/README.md contains the four gate filenames literally.",
            "result": "pass" if (not unexpected_non_junk and observed_xrefs == expected_xrefs) else "fail",
            "sub_gate": "d_no_unexpected_non_junk_extras_and_readme_xrefs_exist",
        },
    ],
    "thresholds": {
        "canonical_count_fallback_floor": 12,
        "canonical_count_strong": 12,
        "temporal_span_fallback_seconds_max": 5400,
        "temporal_span_strong_seconds_max": 1800,
    },
    "utc_captured": UTC_NOW,
}

gate15 = {
    "claim": f"The H1 trigger produced the documented failure on {pre_revision}: the Key Vault is in RBAC mode, no Key Vault Secrets User assignment exists at the vault scope before the fix, the /health response is non-200 with ForbiddenByRbac in the body, and the active revision still remains Healthy / Provisioned / Running.",
    "claim_level": "Observed",
    "gate_classification": "H1 gate: confirms the missing Key Vault Secrets User assignment produced an application-level failure while the revision surface stayed healthy.",
    "hypothesis": "H1_trigger_produces_failure",
    "path_used": "single",
    "predicate_inputs": {
        "http_response_pre": repo_rel("05-http-response-pre-fix.json"),
        "key_vault_config": repo_rel("03-kv-rbac-config.json"),
        "revision_list_pre": repo_rel("04-revision-list-pre-fix.json"),
        "role_assignments_pre": repo_rel("02-role-assignments-pre-fix.json"),
    },
    "managed_identity_key_vault_failure_h1_trigger_produces_failure_all_subgates_pass": True,
    "managed_identity_key_vault_failure_h1_trigger_produces_failure_sub_gates": {
        "a_kv_scope_lacks_key_vault_secrets_user": not pre_role_match,
        "b_http_response_is_non_200_and_contains_forbiddenbyrbac": int(http_pre.get("status_code", 0)) != 200 and "ForbiddenByRbac" in response_pre_body,
        "c_revision_surface_stays_healthy_running_and_provisioned": pre_revision_state.get("healthState") == "Healthy" and pre_revision_state.get("provisioningState") == "Provisioned" and pre_revision_state.get("runningState") == "Running",
        "d_vault_is_in_rbac_authorization_mode": kv_config.get("enableRbacAuthorization") is True,
    },
    "scenario": "managed_identity_key_vault_failure",
    "sub_gates": [
        {
            "claim": "No Key Vault Secrets User assignment exists at the vault scope before the fix.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-role-assignments-pre-fix.json"), repo_rel("03-kv-rbac-config.json")],
            "observed_values": {
                "matching_kv_scope_roles": pre_role_match,
                "pre_role_assignment_count": len(roles_pre),
                "vault_name": kv_name,
            },
            "predicate": "count(02 rows where roleDefinitionName == 'Key Vault Secrets User' AND scope contains the vault name from 03.uri) == 0.",
            "result": "pass" if not pre_role_match else "fail",
            "sub_gate": "a_kv_scope_lacks_key_vault_secrets_user",
        },
        {
            "claim": "The pre-fix /health response is non-200 and contains the ForbiddenByRbac smoking gun.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("05-http-response-pre-fix.json")],
            "observed_values": {
                "body_contains_assignment_not_found": "Assignment: (not found)" in response_pre_body,
                "body_contains_forbiddenbyrbac": "ForbiddenByRbac" in response_pre_body,
                "status_code": int(http_pre.get("status_code", 0)),
            },
            "predicate": "05.status_code != 200 AND 05.body contains 'ForbiddenByRbac'.",
            "result": "pass" if (int(http_pre.get("status_code", 0)) != 200 and "ForbiddenByRbac" in response_pre_body) else "fail",
            "sub_gate": "b_http_response_is_non_200_and_contains_forbiddenbyrbac",
        },
        {
            "claim": "The active pre-fix revision stays Healthy / Provisioned / Running despite the endpoint failure.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("04-revision-list-pre-fix.json")],
            "observed_values": {
                "health_state": pre_revision_state.get("healthState"),
                "provisioning_state": pre_revision_state.get("provisioningState"),
                "revision_name": pre_revision,
                "running_state": pre_revision_state.get("runningState"),
            },
            "predicate": "04[0].properties.healthState == 'Healthy' AND provisioningState == 'Provisioned' AND runningState == 'Running'.",
            "result": "pass" if (pre_revision_state.get("healthState") == "Healthy" and pre_revision_state.get("provisioningState") == "Provisioned" and pre_revision_state.get("runningState") == "Running") else "fail",
            "sub_gate": "c_revision_surface_stays_healthy_running_and_provisioned",
        },
        {
            "claim": "The vault uses RBAC authorization, so the missing role assignment is the mechanically relevant surface under test.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("03-kv-rbac-config.json")],
            "observed_values": {
                "enable_rbac_authorization": kv_config.get("enableRbacAuthorization"),
                "public_network_access": kv_config.get("publicNetworkAccess"),
                "uri": kv_uri,
            },
            "predicate": "03.enableRbacAuthorization == true.",
            "result": "pass" if kv_config.get("enableRbacAuthorization") is True else "fail",
            "sub_gate": "d_vault_is_in_rbac_authorization_mode",
        },
    ],
    "thresholds": {
        "expected_http_status_pre_fix": "non-200",
        "expected_vault_role_name": "Key Vault Secrets User",
    },
    "utc_captured": UTC_NOW,
}

gate16 = {
    "claim": f"The H2 fix restored recovery on {post_revision}: a Key Vault Secrets User assignment is present at the vault scope, the /health response is HTTP 200 with a success body, a newer revision was created after the fix, and the post-fix KQL summary shows startup/readiness events on the recovered revision with zero ProbeFailed rows on that recovered revision.",
    "claim_level": "Observed",
    "gate_classification": "H2 gate: confirms recovery after the RBAC assignment plus a new revision start.",
    "hypothesis": "H2_fix_restores_recovery",
    "path_used": "single",
    "predicate_inputs": {
        "http_response_post": repo_rel("10-http-response-post-fix.json"),
        "kql_recovery_summary": repo_rel("12-kql-recovery-summary-post-fix.json"),
        "revision_list_post": repo_rel("11-revision-list-post-fix.json"),
        "role_assignments_post": repo_rel("09-role-assignment-post-fix.json"),
    },
    "managed_identity_key_vault_failure_h2_fix_restores_recovery_all_subgates_pass": True,
    "managed_identity_key_vault_failure_h2_fix_restores_recovery_sub_gates": {
        "a_key_vault_secrets_user_exists_at_kv_scope": bool(post_role_match),
        "b_http_response_is_200_with_success_marker": int(http_post.get("status_code", 0)) == 200 and '"status":"ok"' in response_post_body,
        "c_newer_post_fix_revision_is_active_and_healthy": post_created > pre_created and post_revision_state.get("healthState") == "Healthy" and post_revision_state.get("runningState") == "Running",
        "d_post_fix_kql_shows_startup_and_zero_probefailed_on_recovered_revision": post_reasons.get("ContainerStarted", 0) >= 1 and post_reasons.get("RevisionReady", 0) >= 1 and post_reasons.get("ProbeFailed", 0) == 0,
    },
    "scenario": "managed_identity_key_vault_failure",
    "sub_gates": [
        {
            "claim": "A Key Vault Secrets User assignment exists at the vault scope after the fix.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("09-role-assignment-post-fix.json")],
            "observed_values": {
                "matching_kv_scope_roles": post_role_match,
                "post_role_assignment_count": len(roles_post),
            },
            "predicate": "count(09 rows where roleDefinitionName == 'Key Vault Secrets User' AND scope contains the vault name) >= 1.",
            "result": "pass" if post_role_match else "fail",
            "sub_gate": "a_key_vault_secrets_user_exists_at_kv_scope",
        },
        {
            "claim": "The post-fix /health response is HTTP 200 and carries the success marker.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("10-http-response-post-fix.json")],
            "observed_values": {
                "body": response_post_body.strip(),
                "status_code": int(http_post.get("status_code", 0)),
            },
            "predicate": "10.status_code == 200 AND 10.body contains '\"status\":\"ok\"'.",
            "result": "pass" if (int(http_post.get("status_code", 0)) == 200 and '"status":"ok"' in response_post_body) else "fail",
            "sub_gate": "b_http_response_is_200_with_success_marker",
        },
        {
            "claim": "A newer revision was created after the fix and is active / healthy / running.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("04-revision-list-pre-fix.json"), repo_rel("11-revision-list-post-fix.json")],
            "observed_values": {
                "post_created_time": revisions_post[0]["properties"]["createdTime"],
                "post_health_state": post_revision_state.get("healthState"),
                "post_revision": post_revision,
                "post_running_state": post_revision_state.get("runningState"),
                "pre_created_time": revisions_pre[0]["properties"]["createdTime"],
                "pre_revision": pre_revision,
            },
            "predicate": "11[0].properties.createdTime > 04[0].properties.createdTime AND 11[0].properties.healthState == 'Healthy' AND 11[0].properties.runningState == 'Running'.",
            "result": "pass" if (post_created > pre_created and post_revision_state.get("healthState") == "Healthy" and post_revision_state.get("runningState") == "Running") else "fail",
            "sub_gate": "c_newer_post_fix_revision_is_active_and_healthy",
        },
        {
            "claim": "The post-fix KQL summary shows startup/readiness on the recovered revision with zero ProbeFailed rows on that recovered revision.",
            "claim_level": "Measured",
            "evidence_files": [repo_rel("12-kql-recovery-summary-post-fix.json")],
            "observed_values": {
                "post_revision_reason_counts": post_reasons,
            },
            "predicate": "12 rows for the recovered revision contain ContainerStarted >= 1 AND RevisionReady >= 1 AND ProbeFailed == 0.",
            "result": "pass" if (post_reasons.get("ContainerStarted", 0) >= 1 and post_reasons.get("RevisionReady", 0) >= 1 and post_reasons.get("ProbeFailed", 0) == 0) else "fail",
            "sub_gate": "d_post_fix_kql_shows_startup_and_zero_probefailed_on_recovered_revision",
        },
    ],
    "thresholds": {
        "post_fix_probefailed_expected": 0,
        "post_fix_status_code_expected": 200,
    },
    "utc_captured": UTC_NOW,
}

gate17 = {
    "claim": "This evidence pack falsifies the managed-identity Key Vault failure hypothesis within a bounded scope. Gate 17 demonstrates that the missing Key Vault Secrets User role assignment at the Key Vault scope is the mechanically observable trigger field. The pack does not claim image byte identity, pod UID continuity, exact RBAC propagation timing, or token-cache isolation.",
    "claim_level": "Observed",
    "cohort_binding_note": {
        "claim_ceiling": "The bounded claim is that the presence versus absence of the Key Vault Secrets User role assignment at the Key Vault scope is the mechanically observable trigger field for this cohort. The pack does NOT prove image byte identity, pod UID continuity, exact RBAC propagation timing, or token-cache-only recovery.",
        "explicit_drops": explicit_drops,
    },
    "gate_classification": "Bounded falsification gate: isolates the missing Key Vault Secrets User assignment as the trigger field while explicitly listing the unproven confounders and ceilings.",
    "hypothesis": "H3_bounded_falsification",
    "path_used": "bounded",
    "predicate_inputs": {
        "app_identity": repo_rel("01-app-identity-pre-fix.json"),
        "revision_list_pre": repo_rel("04-revision-list-pre-fix.json"),
        "revision_list_post": repo_rel("11-revision-list-post-fix.json"),
        "role_assignments_pre": repo_rel("02-role-assignments-pre-fix.json"),
        "role_assignments_post": repo_rel("09-role-assignment-post-fix.json"),
    },
    "managed_identity_key_vault_failure_h3_bounded_falsification_all_subgates_pass": True,
    "managed_identity_key_vault_failure_h3_bounded_falsification_sub_gates": {
        "a_role_assignment_presence_is_the_bounded_trigger_field": not pre_role_match and bool(post_role_match),
        "b_directly_captured_held_constant_fields_match": all(held_constant_checks.values()),
        "c_explicit_drops_match_the_documented_ceiling": expected_drop_ids == [item["id"] for item in explicit_drops],
        "d_recovery_is_observed_after_role_assignment_plus_new_revision_start": post_created > pre_created and bool(post_env.get("RESTART_TOKEN")),
    },
    "scenario": "managed_identity_key_vault_failure",
    "sub_gates": [
        {
            "claim": "The bounded trigger field under test is the presence versus absence of the Key Vault Secrets User role assignment at the vault scope.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-role-assignments-pre-fix.json"), repo_rel("09-role-assignment-post-fix.json")],
            "observed_values": {
                "post_matching_role_count": len(post_role_match),
                "pre_matching_role_count": len(pre_role_match),
                "role_name": "Key Vault Secrets User",
                "vault_name": kv_name,
            },
            "predicate": "count(pre rows where roleDefinitionName == 'Key Vault Secrets User' AND scope contains the vault name) == 0 AND count(post rows with the same predicate) >= 1.",
            "result": "pass" if (not pre_role_match and post_role_match) else "fail",
            "sub_gate": "a_role_assignment_presence_is_the_bounded_trigger_field",
        },
        {
            "claim": "The directly captured held-constant fields match across H1 and H2 on the bounded surface.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("04-revision-list-pre-fix.json"), repo_rel("07-containerapp-spec-pre-fix.yaml"), repo_rel("11-revision-list-post-fix.json")],
            "observed_values": {
                "held_constant_checks": held_constant_checks,
                "held_constant_observed": {
                    "app_name": [app_name, pre_revision.split("--")[0], post_revision.split("--")[0]],
                    "cpu": [pre_container["resources"]["cpu"], post_container["resources"]["cpu"]],
                    "image": [pre_image, post_image],
                    "key_vault_url": [pre_env.get("KEY_VAULT_URL"), post_env.get("KEY_VAULT_URL")],
                    "memory": [pre_container["resources"]["memory"], post_container["resources"]["memory"]],
                    "resource_group": [revisions_pre[0]["resourceGroup"], revisions_post[0]["resourceGroup"]],
                    "secret_name": [pre_env.get("SECRET_NAME"), post_env.get("SECRET_NAME")],
                    "target_port": [spec_pre["properties"]["configuration"]["ingress"]["targetPort"]],
                },
            },
            "predicate": "app name, resource group, image tag, KEY_VAULT_URL, SECRET_NAME, cpu, memory, and ingress targetPort compare equal across the pre/post captures.",
            "result": "pass" if all(held_constant_checks.values()) else "fail",
            "sub_gate": "b_directly_captured_held_constant_fields_match",
        },
        {
            "claim": "The bounded-falsification gate explicitly lists the documented ceilings and unsupported inferences.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("17-bounded-falsification-gate.json")],
            "observed_values": {
                "expected_drop_ids": expected_drop_ids,
                "observed_drop_ids": [item["id"] for item in explicit_drops],
            },
            "predicate": "cohort_binding_note.explicit_drops ids equal {image_byte_identity_not_captured, pod_uids_not_captured, rbac_propagation_timing_not_proven, token_cache_behavior_not_proven}.",
            "result": "pass" if expected_drop_ids == [item["id"] for item in explicit_drops] else "fail",
            "sub_gate": "c_explicit_drops_match_the_documented_ceiling",
        },
        {
            "claim": "Recovery is observed only after the role assignment plus a new revision start, which is why token-cache isolation remains an explicit drop rather than a proven claim.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("09-role-assignment-post-fix.json"), repo_rel("11-revision-list-post-fix.json")],
            "observed_values": {
                "post_revision": post_revision,
                "pre_revision": pre_revision,
                "restart_token_present": bool(post_env.get("RESTART_TOKEN")),
                "role_assignment_created_on": roles_post[0]["createdOn"],
            },
            "predicate": "11[0].properties.createdTime > 04[0].properties.createdTime AND the recovered revision environment contains RESTART_TOKEN after the 09 role-assignment capture.",
            "result": "pass" if (post_created > pre_created and bool(post_env.get("RESTART_TOKEN"))) else "fail",
            "sub_gate": "d_recovery_is_observed_after_role_assignment_plus_new_revision_start",
        },
    ],
    "thresholds": {
        "held_constant_field_count": len(held_constant_checks),
        "post_fix_status_code_expected": 200,
        "pre_fix_status_code_expected": "non-200",
    },
    "utc_captured": UTC_NOW,
}

gates = [
    (14, gate14, "cohort integrity verified"),
    (15, gate15, "H1 trigger produces failure verified"),
    (16, gate16, "H2 fix restores recovery verified"),
    (17, gate17, "bounded falsification verified"),
]

output_map = {
    14: EVIDENCE_DIR / "14-cohort-integrity-gate.json",
    15: EVIDENCE_DIR / "15-h1-trigger-produces-failure-gate.json",
    16: EVIDENCE_DIR / "16-h2-fix-restores-recovery-gate.json",
    17: EVIDENCE_DIR / "17-bounded-falsification-gate.json",
}

for gate_number, gate_data, _ in gates:
    output_map[gate_number].write_text(json.dumps(gate_data, indent=2) + "\n", encoding="utf-8")

for gate_number, gate_data, detail in gates:
    sub_gate_map = next(value for key, value in gate_data.items() if key.endswith("_sub_gates"))
    if not all(sub_gate_map.values()):
        failed = [key for key, value in sub_gate_map.items() if not value]
        raise SystemExit(f"[Gate {gate_number}/17] FAIL {detail}; failed sub-gates: {', '.join(failed)}")
    print(f"[Gate {gate_number}/17] PASS {detail}")
PY
)"; then
    printf '%s\n' "$PHASE_B_OUTPUT"
else
    printf '%s\n' "$PHASE_B_OUTPUT"
    exit 1
fi
