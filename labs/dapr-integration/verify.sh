#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/dapr-integration/evidence"
LAB_README_PATH="${SCRIPT_DIR}/README.md"
LAB_GUIDE_PATH="${SCRIPT_DIR}/../../docs/troubleshooting/lab-guides/dapr-integration.md"
UTC_NOW="${UTC_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR LAB_README_PATH LAB_GUIDE_PATH UTC_NOW

declare -a CANONICAL_RAW_FILES=(
    "01-app-spec-pre-fix.json"
    "02-revision-list-pre-fix.json"
    "03-dapr-config-pre-fix.json"
    "04-http-response-pre-fix.json"
    "05-dapr-invoke-pre-fix.json"
    "06-system-logs-pre-fix.json"
    "07-containerapp-spec-pre-fix.yaml"
    "08-kql-console-logs-pre-fix.json"
    "09-dapr-config-post-fix.json"
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

import yaml

gate_number = int(os.environ["GATE_NUMBER"])
evidence_dir = Path(os.environ["EVIDENCE_DIR"])
lab_readme = Path(os.environ["LAB_README_PATH"])

RAW_FILES = [
    "01-app-spec-pre-fix.json",
    "02-revision-list-pre-fix.json",
    "03-dapr-config-pre-fix.json",
    "04-http-response-pre-fix.json",
    "05-dapr-invoke-pre-fix.json",
    "06-system-logs-pre-fix.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-kql-console-logs-pre-fix.json",
    "09-dapr-config-post-fix.json",
    "10-http-response-post-fix.json",
    "11-revision-list-post-fix.json",
    "12-kql-recovery-summary-post-fix.json",
]

def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))

def load_jsonl(path: Path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]

def load_yaml(path: Path):
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
        app = load_json(evidence_dir / RAW_FILES[0])
    except Exception as exc:  # noqa: BLE001
        print(f"01 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    dapr = app.get("properties", {}).get("configuration", {}).get("dapr", {})
    ingress = app.get("properties", {}).get("configuration", {}).get("ingress", {})
    ok = bool(app.get("name")) and dapr.get("enabled") is True and int(dapr.get("appPort", 0)) == 8081 and int(ingress.get("targetPort", 0)) == 8000
    if ok:
        print("01 parses and shows Dapr enabled with pre-fix appPort 8081 and ingress targetPort 8000")
        raise SystemExit(0)
    print("01 missing expected pre-fix app spec shape")
    raise SystemExit(1)

if gate_number == 6:
    try:
        revisions = load_json(evidence_dir / RAW_FILES[1])
        dapr = load_json(evidence_dir / RAW_FILES[2])
    except Exception as exc:  # noqa: BLE001
        print(f"02/03 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(revisions, list) and len(revisions) >= 1 and dapr.get("enabled") is True and int(dapr.get("appPort", 0)) == 8081
    if ok:
        print("02/03 parse and show a broken revision with pre-fix appPort 8081")
        raise SystemExit(0)
    print("02/03 do not match the expected revision-list + Dapr-config shape")
    raise SystemExit(1)

if gate_number == 7:
    try:
        response = load_json(evidence_dir / RAW_FILES[3])
    except Exception as exc:  # noqa: BLE001
        print(f"04 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = int(response.get("status_code", 0)) == 200 and "OK" in str(response.get("body", ""))
    if ok:
        print("04 parses and captures a pre-fix ingress HTTP 200 response")
        raise SystemExit(0)
    print("04 does not capture the expected pre-fix ingress 200 response")
    raise SystemExit(1)

if gate_number == 8:
    try:
        invoke = load_json(evidence_dir / RAW_FILES[4])
    except Exception as exc:  # noqa: BLE001
        print(f"05 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    combined = f"{invoke.get('stdout', '')}\n{invoke.get('stderr', '')}"
    ok = "ClusterExecFailure" in combined or int(invoke.get("exit_code", 0)) != 0 or any(token in combined for token in ["ERR_DIRECT_INVOKE", "connection refused", "502", "500"])
    if ok:
        print("05 parses and captures a failing pre-fix exec transcript while probing the Dapr invoke path")
        raise SystemExit(0)
    print("05 does not capture the expected failing exec transcript")
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
    dapr = spec.get("properties", {}).get("configuration", {}).get("dapr", {})
    ingress = spec.get("properties", {}).get("configuration", {}).get("ingress", {})
    containers = spec.get("properties", {}).get("template", {}).get("containers", [])
    image = containers[0].get("image") if containers else ""
    ok = spec.get("name") and spec.get("resourceGroup") and dapr.get("enabled") is True and int(dapr.get("appPort", 0)) == 8081 and int(ingress.get("targetPort", 0)) == 8000 and "azurecr.io" in str(image)
    if ok:
        print("07 parses as YAML and pins the ACR-backed pre-fix app spec")
        raise SystemExit(0)
    print("07 YAML does not match the expected pre-fix app spec shape")
    raise SystemExit(1)

if gate_number == 11:
    try:
        console_rows = load_json(evidence_dir / RAW_FILES[7])
    except Exception as exc:  # noqa: BLE001
        print(f"08 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(console_rows, list) and len(console_rows) >= 1
    if ok:
        print(f"08 parses as JSON with {len(console_rows)} Log Analytics rows")
        raise SystemExit(0)
    print("08 does not contain the expected Log Analytics rows")
    raise SystemExit(1)

if gate_number == 12:
    try:
        post_dapr = load_json(evidence_dir / RAW_FILES[8])
        post_http = load_json(evidence_dir / RAW_FILES[9])
        post_revisions = load_json(evidence_dir / RAW_FILES[10])
        post_kql = load_json(evidence_dir / RAW_FILES[11])
    except Exception as exc:  # noqa: BLE001
        print(f"09-12 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = (
        post_dapr.get("enabled") is True
        and int(post_dapr.get("appPort", 0)) == 8000
        and int(post_http.get("status_code", 0)) == 200
        and isinstance(post_revisions, list)
        and len(post_revisions) >= 1
        and isinstance(post_kql, list)
        and len(post_kql) >= 1
    )
    if ok:
        print("09-12 parse and capture the restored Dapr config, HTTP 200, newer revision, and KQL summary")
        raise SystemExit(0)
    print("09-12 do not capture the expected post-fix Dapr / revision / 200-response surface")
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
    "5:pre-fix app spec parses" \
    "6:pre-fix revision and dapr config parse" \
    "7:pre-fix ingress response parses" \
    "8:pre-fix Dapr invoke failure parses" \
    "9:system log capture parses" \
    "10:pre-fix YAML spec parses" \
    "11:pre-fix KQL capture parses" \
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
    "01-app-spec-pre-fix.json",
    "02-revision-list-pre-fix.json",
    "03-dapr-config-pre-fix.json",
    "04-http-response-pre-fix.json",
    "05-dapr-invoke-pre-fix.json",
    "06-system-logs-pre-fix.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-kql-console-logs-pre-fix.json",
    "09-dapr-config-post-fix.json",
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
DOCUMENTED_EXPLICIT_DROPS_CEILING = frozenset([
    "image_byte_identity",
    "pod_uid_continuity",
    "dapr_sidecar_pid_continuity",
    "dapr_health_probe_timing",
    "dns_resolution_timing",
])
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

def resolve_anchor_timestamp(name: str):
    stat = (EVIDENCE_DIR / name).stat()
    ts = getattr(stat, "st_birthtime", None)
    if ts is not None and ts > 0:
        dt = datetime.fromtimestamp(ts, tz=timezone.utc)
        return {
            "timestamp": dt,
            "timestamp_utc": dt.isoformat(),
            "time_source": "birthtime",
            "raw_epoch": ts,
        }
    dt = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)
    return {
        "timestamp": dt,
        "timestamp_utc": dt.isoformat(),
        "time_source": "mtime",
        "raw_epoch": stat.st_mtime,
    }

def parse_revision_id(revision_id: str):
    match = re.match(
        r"^/subscriptions/(?P<sub>[^/]+)/resourceGroups/(?P<rg>[^/]+)/providers/Microsoft\.App/containerApps/(?P<app>[^/]+)/revisions/(?P<rev>[^/]+)$",
        revision_id,
    )
    if not match:
        return {"resource_group": None, "container_app": None, "revision": None}
    return {
        "resource_group": match.group("rg"),
        "container_app": match.group("app"),
        "revision": match.group("rev"),
    }

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

def flatten_json(prefix, value):
    if isinstance(value, dict):
        out = {}
        for key, inner in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else key
            out.update(flatten_json(child_prefix, inner))
        return out
    if isinstance(value, list):
        out = {}
        for index, inner in enumerate(value):
            child_prefix = f"{prefix}[{index}]"
            out.update(flatten_json(child_prefix, inner))
        return out
    return {prefix: value}

app_pre = load_json("01-app-spec-pre-fix.json")
revisions_pre = load_json("02-revision-list-pre-fix.json")
dapr_pre = load_json("03-dapr-config-pre-fix.json")
http_pre = load_json("04-http-response-pre-fix.json")
invoke_pre = load_json("05-dapr-invoke-pre-fix.json")
system_pre = load_jsonl("06-system-logs-pre-fix.json")
spec_pre = load_yaml("07-containerapp-spec-pre-fix.yaml")
kql_pre = load_json("08-kql-console-logs-pre-fix.json")
dapr_post = load_json("09-dapr-config-post-fix.json")
http_post = load_json("10-http-response-post-fix.json")
revisions_post = load_json("11-revision-list-post-fix.json")
recovery_post = load_json("12-kql-recovery-summary-post-fix.json")

app_name = app_pre["name"]
resource_group = app_pre["resourceGroup"]
pre_revision = revisions_pre[0]["name"]
post_revision = revisions_post[0]["name"]
pre_revision_id = revisions_pre[0]["id"]
post_revision_id = revisions_post[0]["id"]

parse_errors = []
for name in [
    "01-app-spec-pre-fix.json",
    "02-revision-list-pre-fix.json",
    "03-dapr-config-pre-fix.json",
    "04-http-response-pre-fix.json",
    "05-dapr-invoke-pre-fix.json",
    "08-kql-console-logs-pre-fix.json",
    "09-dapr-config-post-fix.json",
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
system_timestamps = []
for row in system_pre:
    if row.get("TimeStamp"):
        try:
            system_timestamps.append(parse_system_timestamp(row["TimeStamp"]))
        except ValueError:
            continue

pre_anchor_files = [
    "01-app-spec-pre-fix.json",
    "02-revision-list-pre-fix.json",
    "03-dapr-config-pre-fix.json",
    "04-http-response-pre-fix.json",
    "05-dapr-invoke-pre-fix.json",
    "07-containerapp-spec-pre-fix.yaml",
]
post_anchor_files = [
    "08-kql-console-logs-pre-fix.json",
    "09-dapr-config-post-fix.json",
    "10-http-response-post-fix.json",
    "11-revision-list-post-fix.json",
    "12-kql-recovery-summary-post-fix.json",
]
pre_anchor_infos = {name: resolve_anchor_timestamp(name) for name in pre_anchor_files}
post_anchor_infos = {name: resolve_anchor_timestamp(name) for name in post_anchor_files}
monotonic_pairs = []
for pre_name, pre_info in pre_anchor_infos.items():
    for post_name, post_info in post_anchor_infos.items():
        monotonic_pairs.append({
            "pre_file": pre_name,
            "pre_timestamp_utc": pre_info["timestamp_utc"],
            "pre_time_source": pre_info["time_source"],
            "post_file": post_name,
            "post_timestamp_utc": post_info["timestamp_utc"],
            "post_time_source": post_info["time_source"],
            "delta_seconds": (post_info["timestamp"] - pre_info["timestamp"]).total_seconds(),
            "holds": post_info["timestamp"] > pre_info["timestamp"],
        })
monotonic_ordering_holds = all(item["holds"] for item in monotonic_pairs)
sorted_anchor_sequence = [
    {
        "file": name,
        "timestamp_utc": info["timestamp_utc"],
        "time_source": info["time_source"],
        "anchor_class": "pre" if name in pre_anchor_infos else "post",
    }
    for name, info in sorted({**pre_anchor_infos, **post_anchor_infos}.items(), key=lambda item: item[1]["timestamp"])
]
time_source_summary = {
    "birthtime_count": sum(1 for info in [*pre_anchor_infos.values(), *post_anchor_infos.values()] if info["time_source"] == "birthtime"),
    "mtime_count": sum(1 for info in [*pre_anchor_infos.values(), *post_anchor_infos.values()] if info["time_source"] == "mtime"),
    "fallback_used": any(info["time_source"] == "mtime" for info in [*pre_anchor_infos.values(), *post_anchor_infos.values()]),
}
anchor_times = [pre_created, pre_http_date, post_created, post_http_date]
if system_timestamps:
    anchor_times.append(min(system_timestamps))
earliest_anchor = min(anchor_times)
latest_anchor = max(anchor_times)
span_seconds = (latest_anchor - earliest_anchor).total_seconds()
strong_temporal = span_seconds <= 1800
fallback_temporal = span_seconds <= 5400
path_used = "strong" if strong_temporal else "fallback"

readme_text = (EVIDENCE_DIR / "README.md").read_text(encoding="utf-8")
observed_files_on_disk = sorted(path.name for path in EVIDENCE_DIR.iterdir() if path.is_file())
non_junk_files = [name for name in observed_files_on_disk if name not in JUNK_NAMES]
unexpected_non_junk = [name for name in non_junk_files if name not in EXPECTED_EVIDENCE_FILES]
expected_xrefs = GATE_FILES
observed_xrefs = [name for name in expected_xrefs if name in readme_text]

pre_revision_state = revisions_pre[0]["properties"]
post_revision_state = revisions_post[0]["properties"]
pre_revision_parts = parse_revision_id(pre_revision_id)
post_revision_parts = parse_revision_id(post_revision_id)
pre_lineage_holds = f"/resourceGroups/{resource_group}/" in pre_revision_id and f"/containerApps/{app_name}/" in pre_revision_id
post_lineage_holds = f"/resourceGroups/{resource_group}/" in post_revision_id and f"/containerApps/{app_name}/" in post_revision_id
pre_parse_ok = pre_revision_parts.get("resource_group") is not None and pre_revision_parts.get("container_app") is not None
post_parse_ok = post_revision_parts.get("resource_group") is not None and post_revision_parts.get("container_app") is not None
both_parse_ok = pre_parse_ok and post_parse_ok
pre_post_rg_equal = both_parse_ok and pre_revision_parts["resource_group"] == post_revision_parts["resource_group"]
pre_post_app_equal = both_parse_ok and pre_revision_parts["container_app"] == post_revision_parts["container_app"]
pre_post_lineage_equal = both_parse_ok and pre_post_rg_equal and pre_post_app_equal

response_pre_body = str(http_pre.get("body", "")).strip()
response_post_body = str(http_post.get("body", "")).strip()
invoke_pre_combined = f"{invoke_pre.get('stdout', '')}\n{invoke_pre.get('stderr', '')}"
pre_probe_failed_rows = [
    row for row in system_pre
    if row.get("ContainerAppName") == app_name and row.get("Reason") == "ProbeFailed"
]

pre_dapr_enabled = dapr_pre.get("enabled") is True
post_dapr_enabled = dapr_post.get("enabled") is True
pre_app_port = int(dapr_pre.get("appPort", 0))
post_app_port = int(dapr_post.get("appPort", 0))
pre_target_port = int(spec_pre["properties"]["configuration"]["ingress"].get("targetPort", 0))
pre_spec_dapr = spec_pre["properties"]["configuration"]["dapr"]
pre_spec_image = spec_pre["properties"]["template"]["containers"][0]["image"]
pre_spec_resources = spec_pre["properties"]["template"]["containers"][0]["resources"]
pre_spec_scale = spec_pre["properties"]["template"].get("scale", {})
post_template = revisions_post[0]["properties"]["template"]
pre_template = revisions_pre[0]["properties"]["template"]

flattened_pre = flatten_json("", dapr_pre)
flattened_post = flatten_json("", dapr_post)
overlap_paths = sorted(set(flattened_pre) & set(flattened_post))
overlap_equal_map = {
    path: flattened_pre[path] == flattened_post[path]
    for path in overlap_paths
}
overlap_diff_map = {
    path: {
        "pre_value": flattened_pre[path],
        "post_value": flattened_post[path],
    }
    for path in overlap_paths
    if flattened_pre[path] != flattened_post[path]
}
overlap_same_map = {
    path: flattened_pre[path]
    for path in overlap_paths
    if flattened_pre[path] == flattened_post[path]
}

held_constant_checks = {
    "dapr.enabled": {
        "pre_value": dapr_pre.get("enabled"),
        "post_value": dapr_post.get("enabled"),
        "equal": dapr_pre.get("enabled") == dapr_post.get("enabled") == True,
    },
    "dapr.appId": {
        "pre_value": dapr_pre.get("appId"),
        "post_value": dapr_post.get("appId"),
        "equal": dapr_pre.get("appId") == dapr_post.get("appId"),
    },
    "dapr.appProtocol": {
        "pre_value": dapr_pre.get("appProtocol"),
        "post_value": dapr_post.get("appProtocol"),
        "equal": dapr_pre.get("appProtocol") == dapr_post.get("appProtocol"),
    },
}

explicit_drops = [
    {
        "id": "image_byte_identity",
        "note": "The pack proves only the ACR image tag visible in the spec/revision surfaces. It does not capture immutable OCI digests.",
    },
    {
        "id": "pod_uid_continuity",
        "note": "The cohort stays at the revision surface and does not capture Kubernetes pod UIDs or container restart reuse.",
    },
    {
        "id": "dapr_sidecar_pid_continuity",
        "note": "The pack proves only revision-level behavior; it does not capture the sidecar process ID before and after the restore.",
    },
    {
        "id": "dapr_health_probe_timing",
        "note": "The reproduction proves failure versus recovery but does not bound the exact number of probe intervals required before each state became visible.",
    },
    {
        "id": "dns_resolution_timing",
        "note": "The scenario does not isolate or measure internal name-resolution timing for Dapr sidecar calls.",
    },
]
runtime_drop_ids = frozenset(item["id"] for item in explicit_drops)

recovery_by_revision = {}
for row in recovery_post:
    rev = row.get("RevisionName_s", "")
    reason = row.get("Reason_s", "")
    if rev not in recovery_by_revision:
        recovery_by_revision[rev] = {}
    recovery_by_revision[rev][reason] = int(row.get("EventCount", "0"))
post_reasons = recovery_by_revision.get(post_revision, {})
post_probe_failed = sum(count for reason, count in post_reasons.items() if reason == "ProbeFailed")
post_started_count = sum(count for reason, count in post_reasons.items() if reason == "ContainerStarted")

subgate_14a_pass = not parse_errors
subgate_14b_pass = monotonic_ordering_holds and (strong_temporal or fallback_temporal)
subgate_14c_pass = (
    app_pre["properties"]["latestRevisionName"] == pre_revision
    and app_pre["properties"]["latestReadyRevisionName"] == pre_revision
    and pre_lineage_holds
    and post_lineage_holds
    and both_parse_ok
    and pre_post_lineage_equal
)
subgate_14d_pass = not unexpected_non_junk and observed_xrefs == expected_xrefs
gate_14_all_subgates_pass = all([subgate_14a_pass, subgate_14b_pass, subgate_14c_pass, subgate_14d_pass])

subgate_15a_pass = pre_dapr_enabled and pre_app_port == 8081
subgate_15b_pass = int(http_pre.get("status_code", 0)) == 200 and "OK" in response_pre_body
subgate_15c_pass = "ClusterExecFailure" in invoke_pre_combined or int(invoke_pre.get("exit_code", 0)) != 0 or any(token.lower() in invoke_pre_combined.lower() for token in ["err_direct_invoke", "connection refused", "500", "502"])
subgate_15d_pass = bool(pre_probe_failed_rows)
subgate_15e_pass = pre_revision_state.get("active") is True and pre_revision_state.get("runningState") == "Running"
gate_15_all_subgates_pass = all([subgate_15a_pass, subgate_15b_pass, subgate_15c_pass, subgate_15d_pass, subgate_15e_pass])

subgate_16a_pass = post_dapr_enabled and post_app_port == 8000
subgate_16b_pass = int(http_post.get("status_code", 0)) == 200 and "OK" in response_post_body
subgate_16c_pass = post_revision_state.get("active") is True and post_revision_state.get("healthState") == "Healthy" and post_revision_state.get("runningState") == "Running" and post_http_date > pre_http_date
subgate_16d_pass = post_started_count >= 1
gate_16_all_subgates_pass = all([subgate_16a_pass, subgate_16b_pass, subgate_16c_pass, subgate_16d_pass])

subgate_17a_pass = pre_app_port == 8081 and post_app_port == 8000 and pre_dapr_enabled and post_dapr_enabled
subgate_17b_pass = (
    set(overlap_diff_map) == {"appPort"}
    and all(item["equal"] for item in held_constant_checks.values())
    and pre_spec_dapr.get("enabled") is True
    and int(pre_spec_dapr.get("appPort", 0)) == 8081
    and pre_target_port == 8000
)
subgate_17c_pass = runtime_drop_ids == DOCUMENTED_EXPLICIT_DROPS_CEILING
subgate_17d_pass = post_app_port == 8000 and post_http_date > pre_http_date and int(http_post.get("status_code", 0)) == 200 and subgate_15c_pass
gate_17_all_subgates_pass = all([subgate_17a_pass, subgate_17b_pass, subgate_17c_pass, subgate_17d_pass])

gate14 = {
    "claim": f"The 12-file dapr-integration raw cohort is internally consistent: every file is present and parseable, the app lineage binds to {app_name} / {resource_group}, the temporal span stays within the documented temporal ceiling, and evidence/README.md cross-references all four Phase B gate JSON files.",
    "claim_level": "Observed",
    "gate_classification": "Cohort integrity gate: structural pre-condition for the bounded-falsification pack.",
    "hypothesis": "H_cohort_integrity",
    "path_used": path_used,
    "predicate_inputs": {
        "app_spec_pre": repo_rel("01-app-spec-pre-fix.json"),
        "http_response_pre": repo_rel("04-http-response-pre-fix.json"),
        "http_response_post": repo_rel("10-http-response-post-fix.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
        "revision_list_post": repo_rel("11-revision-list-post-fix.json"),
        "evidence_readme": repo_rel("README.md"),
    },
    "dapr_integration_h_cohort_integrity_all_subgates_pass": gate_14_all_subgates_pass,
    "dapr_integration_h_cohort_integrity_sub_gates": {
        "a_canonical_raw_files_present_and_parse": subgate_14a_pass,
        "b_temporal_cohort_is_monotonic_and_bounded": subgate_14b_pass,
        "c_identity_and_lineage_are_consistent": subgate_14c_pass,
        "d_no_unexpected_non_junk_extras_and_readme_xrefs_exist": subgate_14d_pass,
    },
    "scenario": "dapr_integration",
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
            "result": "pass" if subgate_14a_pass else "fail",
            "sub_gate": "a_canonical_raw_files_present_and_parse",
        },
        {
            "claim": "The captured H1 -> H2 cohort is temporally monotonic by capture order and stays within the documented temporal ceiling.",
            "claim_level": "Measured",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("04-http-response-pre-fix.json"), repo_rel("09-dapr-config-post-fix.json"), repo_rel("10-http-response-post-fix.json"), repo_rel("11-revision-list-post-fix.json")],
            "observed_values": {
                "earliest_anchor_utc": earliest_anchor.isoformat(),
                "latest_anchor_utc": latest_anchor.isoformat(),
                "monotonic_ordering_holds": monotonic_ordering_holds,
                "observed_span_seconds": span_seconds,
                "path_satisfied": path_used,
                "post_anchor_timestamps": {
                    name: {
                        "timestamp_utc": value["timestamp_utc"],
                        "time_source": value["time_source"],
                        "raw_epoch": value["raw_epoch"],
                    }
                    for name, value in post_anchor_infos.items()
                },
                "pre_anchor_timestamps": {
                    name: {
                        "timestamp_utc": value["timestamp_utc"],
                        "time_source": value["time_source"],
                        "raw_epoch": value["raw_epoch"],
                    }
                    for name, value in pre_anchor_infos.items()
                },
                "sorted_anchor_sequence": sorted_anchor_sequence,
                "strong": {"holds": strong_temporal, "max_span_seconds": 1800},
                "fallback": {"holds": fallback_temporal, "max_span_seconds": 5400},
                "strict_pairwise_order_checks": monotonic_pairs,
                "time_source_summary": time_source_summary,
            },
            "predicate": "All configured post-fix capture-order anchor file birth-times (falling back to mtime when birth-time is unavailable) are strictly later than all configured pre-fix anchor file birth-times, and the total span is <= 1800 seconds on the strong path or <= 5400 seconds on the fallback path.",
            "result": "pass" if subgate_14b_pass else "fail",
            "sub_gate": "b_temporal_cohort_is_monotonic_and_bounded",
        },
        {
            "claim": "The pre-fix app spec and revision captures bind to one app/resource-group lineage and show a newer post-fix revision.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("01-app-spec-pre-fix.json"), repo_rel("02-revision-list-pre-fix.json"), repo_rel("11-revision-list-post-fix.json")],
            "observed_values": {
                "app_name": app_name,
                "resource_group": resource_group,
                "pre_revision": pre_revision,
                "post_revision": post_revision,
                "pre_revision_id": pre_revision_id,
                "post_revision_id": post_revision_id,
                "pre_latest_revision": app_pre["properties"]["latestRevisionName"],
                "pre_latest_ready_revision": app_pre["properties"]["latestReadyRevisionName"],
                "pre_lineage_holds": pre_lineage_holds,
                "post_lineage_holds": post_lineage_holds,
                "pre_parse_ok": pre_parse_ok,
                "post_parse_ok": post_parse_ok,
                "pre_resource_group": pre_revision_parts["resource_group"],
                "post_resource_group": post_revision_parts["resource_group"],
                "pre_container_app": pre_revision_parts["container_app"],
                "post_container_app": post_revision_parts["container_app"],
                "pre_post_rg_equal": pre_post_rg_equal,
                "pre_post_app_equal": pre_post_app_equal,
                "pre_post_lineage_equal": pre_post_lineage_equal,
            },
            "predicate": "01.properties.latestRevisionName == 01.properties.latestReadyRevisionName == 02[0].name AND both 02[0].id and 11[0].id contain the expected app/resourceGroup substrings AND the parsed resourceGroup/containerApp components extracted from 02[0].id and 11[0].id compare equal.",
            "result": "pass" if subgate_14c_pass else "fail",
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
            "result": "pass" if subgate_14d_pass else "fail",
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
    "claim": f"The H1 trigger produced the documented pre-fix failure surface on {pre_revision}: Dapr remained enabled but appPort changed to 8081, ingress / still returned HTTP 200 from the app, the exec transcript used to probe the loopback Dapr invoke path failed, system logs showed ProbeFailed rows, and the active revision stayed Running.",
    "claim_level": "Observed",
    "gate_classification": "H1 gate: confirms the Dapr appPort mismatch produced the observed pre-fix failure surface while ingress reachability remained intact.",
    "hypothesis": "H1_trigger_produces_failure",
    "path_used": "single",
    "predicate_inputs": {
        "dapr_config_pre": repo_rel("03-dapr-config-pre-fix.json"),
        "http_response_pre": repo_rel("04-http-response-pre-fix.json"),
        "dapr_invoke_pre": repo_rel("05-dapr-invoke-pre-fix.json"),
        "system_logs_pre": repo_rel("06-system-logs-pre-fix.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
    },
    "dapr_integration_h1_trigger_produces_failure_all_subgates_pass": gate_15_all_subgates_pass,
    "dapr_integration_h1_trigger_produces_failure_sub_gates": {
        "a_dapr_stays_enabled_while_appport_is_8081": subgate_15a_pass,
        "b_ingress_root_still_returns_http_200": subgate_15b_pass,
        "c_exec_transcript_for_loopback_dapr_probe_fails": subgate_15c_pass,
        "d_system_logs_show_probefailed_rows": subgate_15d_pass,
        "e_active_revision_stays_running": subgate_15e_pass,
    },
    "scenario": "dapr_integration",
    "sub_gates": [
        {
            "claim": "The pre-fix Dapr config keeps Dapr enabled while changing appPort to 8081.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("03-dapr-config-pre-fix.json")],
            "observed_values": {
                "app_id": dapr_pre.get("appId"),
                "app_port": pre_app_port,
                "app_protocol": dapr_pre.get("appProtocol"),
                "enabled": dapr_pre.get("enabled"),
            },
            "predicate": "03.enabled == true AND 03.appPort == 8081.",
            "result": "pass" if subgate_15a_pass else "fail",
            "sub_gate": "a_dapr_stays_enabled_while_appport_is_8081",
        },
        {
            "claim": "The pre-fix ingress root still returns HTTP 200 from the app workload.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("04-http-response-pre-fix.json")],
            "observed_values": {
                "body": response_pre_body,
                "status_code": int(http_pre.get("status_code", 0)),
            },
            "predicate": "04.status_code == 200 AND 04.body contains 'OK'.",
            "result": "pass" if subgate_15b_pass else "fail",
            "sub_gate": "b_ingress_root_still_returns_http_200",
        },
        {
            "claim": "The pre-fix exec transcript used to probe the loopback Dapr invoke path fails.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("05-dapr-invoke-pre-fix.json")],
            "observed_values": {
                "exit_code": int(invoke_pre.get("exit_code", 0)),
                "stderr": invoke_pre.get("stderr", ""),
                "stdout": invoke_pre.get("stdout", ""),
            },
            "predicate": "05.exit_code != 0 OR the combined stdout/stderr contains one of {ClusterExecFailure, ERR_DIRECT_INVOKE, connection refused, 500, 502}.",
            "result": "pass" if subgate_15c_pass else "fail",
            "sub_gate": "c_exec_transcript_for_loopback_dapr_probe_fails",
        },
        {
            "claim": "The pre-fix system-log capture shows ProbeFailed rows on the triggered appPort 8081 window.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("06-system-logs-pre-fix.json")],
            "observed_values": {
                "probe_failed_row_count": len(pre_probe_failed_rows),
                "sample_probe_failed_rows": pre_probe_failed_rows[:3],
            },
            "predicate": "06 contains at least one row where ContainerAppName matches the app and Reason == 'ProbeFailed'.",
            "result": "pass" if subgate_15d_pass else "fail",
            "sub_gate": "d_system_logs_show_probefailed_rows",
        },
        {
            "claim": "The active pre-fix revision stays Running while the observed failure surface is present.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json")],
            "observed_values": {
                "active": pre_revision_state.get("active"),
                "health_state": pre_revision_state.get("healthState"),
                "provisioning_state": pre_revision_state.get("provisioningState"),
                "revision_name": pre_revision,
                "running_state": pre_revision_state.get("runningState"),
            },
            "predicate": "02[0].properties.active == true AND 02[0].properties.runningState == 'Running'.",
            "result": "pass" if subgate_15e_pass else "fail",
            "sub_gate": "e_active_revision_stays_running",
        },
    ],
    "thresholds": {
        "expected_pre_fix_app_port": 8081,
        "expected_pre_fix_ingress_status": 200,
    },
    "utc_captured": UTC_NOW,
}

gate16 = {
    "claim": f"The H2 fix restored recovery on {post_revision}: Dapr stayed enabled while appPort returned to 8000, ingress / returned HTTP 200, the active revision was healthy/running in the post-fix capture window, and the post-fix KQL summary still shows startup activity for the revision in that restore window.",
    "claim_level": "Observed",
    "gate_classification": "H2 gate: confirms recovery after restoring Dapr appPort to the real listener.",
    "hypothesis": "H2_fix_restores_recovery",
    "path_used": "single",
    "predicate_inputs": {
        "dapr_config_post": repo_rel("09-dapr-config-post-fix.json"),
        "http_response_post": repo_rel("10-http-response-post-fix.json"),
        "revision_list_post": repo_rel("11-revision-list-post-fix.json"),
        "kql_recovery_summary": repo_rel("12-kql-recovery-summary-post-fix.json"),
    },
    "dapr_integration_h2_fix_restores_recovery_all_subgates_pass": gate_16_all_subgates_pass,
    "dapr_integration_h2_fix_restores_recovery_sub_gates": {
        "a_dapr_stays_enabled_while_appport_returns_to_8000": subgate_16a_pass,
        "b_ingress_root_returns_http_200_after_fix": subgate_16b_pass,
        "c_post_fix_revision_is_active_healthy_running_and_later_in_time": subgate_16c_pass,
        "d_post_fix_kql_shows_containerstarted_in_restore_window": subgate_16d_pass,
    },
    "scenario": "dapr_integration",
    "sub_gates": [
        {
            "claim": "The post-fix Dapr config keeps Dapr enabled while restoring appPort to 8000.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("09-dapr-config-post-fix.json")],
            "observed_values": {
                "app_id": dapr_post.get("appId"),
                "app_port": post_app_port,
                "app_protocol": dapr_post.get("appProtocol"),
                "enabled": dapr_post.get("enabled"),
            },
            "predicate": "09.enabled == true AND 09.appPort == 8000.",
            "result": "pass" if subgate_16a_pass else "fail",
            "sub_gate": "a_dapr_stays_enabled_while_appport_returns_to_8000",
        },
        {
            "claim": "The post-fix ingress root returns HTTP 200 from the app workload.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("10-http-response-post-fix.json")],
            "observed_values": {
                "body": response_post_body,
                "status_code": int(http_post.get("status_code", 0)),
            },
            "predicate": "10.status_code == 200 AND 10.body contains 'OK'.",
            "result": "pass" if subgate_16b_pass else "fail",
            "sub_gate": "b_ingress_root_returns_http_200_after_fix",
        },
        {
            "claim": "The post-fix capture shows an active / healthy / running revision after the restore window.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("11-revision-list-post-fix.json")],
            "observed_values": {
                "pre_created_time": revisions_pre[0]["properties"]["createdTime"],
                "post_created_time": revisions_post[0]["properties"]["createdTime"],
                "pre_http_date": pre_http_date.isoformat(),
                "post_http_date": post_http_date.isoformat(),
                "post_revision": post_revision,
                "post_health_state": post_revision_state.get("healthState"),
                "post_running_state": post_revision_state.get("runningState"),
                "active": post_revision_state.get("active"),
            },
            "predicate": "11[0].properties.active == true AND 11[0].properties.healthState == 'Healthy' AND 11[0].properties.runningState == 'Running' AND the HTTP Date header captured in 10 is later than the HTTP Date header captured in 04.",
            "result": "pass" if subgate_16c_pass else "fail",
            "sub_gate": "c_post_fix_revision_is_active_healthy_running_and_later_in_time",
        },
        {
            "claim": "The post-fix KQL summary shows ContainerStarted activity for the revision in the restore window.",
            "claim_level": "Measured",
            "evidence_files": [repo_rel("12-kql-recovery-summary-post-fix.json")],
            "observed_values": {
                "post_revision_reason_counts": post_reasons,
                "post_container_started": post_started_count,
                "post_probe_failed": post_probe_failed,
            },
            "predicate": "12 rows for the recovered revision contain ContainerStarted >= 1.",
            "result": "pass" if subgate_16d_pass else "fail",
            "sub_gate": "d_post_fix_kql_shows_containerstarted_in_restore_window",
        },
    ],
    "thresholds": {
        "expected_post_fix_app_port": 8000,
        "post_fix_status_code_expected": 200,
    },
    "utc_captured": UTC_NOW,
}

gate17 = {
    "claim": "This evidence pack falsifies the Dapr integration failure hypothesis within a bounded scope. Gate 17 demonstrates that the Dapr appPort field is the mechanically observable trigger field for this cohort while Dapr stays enabled and the app keeps listening on ingress targetPort 8000. The pack does not claim image byte identity, pod UID continuity, Dapr sidecar PID continuity, exact Dapr health-probe timing, or exact DNS-resolution timing.",
    "claim_level": "Observed",
    "cohort_binding_note": {
        "claim_ceiling": "The bounded claim is that the Dapr appPort field is the mechanically observable trigger field for this cohort: 8081 breaks loopback Dapr invocation while ingress / remains HTTP 200, and 8000 restores the recovered revision. The pack does NOT prove image byte identity, pod UID continuity, Dapr sidecar PID continuity, exact Dapr health-probe timing, or exact DNS-resolution timing.",
        "explicit_drops": explicit_drops,
    },
    "gate_classification": "Bounded falsification gate: isolates the Dapr appPort field as the trigger while explicitly listing the unproven confounders and ceilings.",
    "hypothesis": "H3_bounded_falsification",
    "path_used": "bounded",
    "predicate_inputs": {
        "app_spec_pre": repo_rel("01-app-spec-pre-fix.json"),
        "dapr_config_pre": repo_rel("03-dapr-config-pre-fix.json"),
        "dapr_config_post": repo_rel("09-dapr-config-post-fix.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
        "revision_list_post": repo_rel("11-revision-list-post-fix.json"),
    },
    "dapr_integration_h3_bounded_falsification_all_subgates_pass": gate_17_all_subgates_pass,
    "dapr_integration_h3_bounded_falsification_sub_gates": {
        "a_appport_is_the_bounded_trigger_field": subgate_17a_pass,
        "b_directly_captured_held_constant_fields_match": subgate_17b_pass,
        "c_explicit_drops_match_the_documented_ceiling": subgate_17c_pass,
        "d_recovery_is_observed_after_restoring_8000_in_a_later_capture_window": subgate_17d_pass,
    },
    "scenario": "dapr_integration",
    "sub_gates": [
        {
            "claim": "The bounded trigger field under test is the Dapr appPort value while Dapr stays enabled on both sides.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("03-dapr-config-pre-fix.json"), repo_rel("09-dapr-config-post-fix.json")],
            "observed_values": {
                "pre_app_port": pre_app_port,
                "post_app_port": post_app_port,
                "pre_enabled": dapr_pre.get("enabled"),
                "post_enabled": dapr_post.get("enabled"),
            },
            "predicate": "03.enabled == true AND 09.enabled == true AND 03.appPort == 8081 AND 09.appPort == 8000.",
            "result": "pass" if subgate_17a_pass else "fail",
            "sub_gate": "a_appport_is_the_bounded_trigger_field",
        },
        {
            "claim": "The directly captured held-constant fields match across H1 and H2 on the bounded Dapr config surface, and the pre-fix full app spec cross-references the same Dapr + ingress pairing.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("03-dapr-config-pre-fix.json"), repo_rel("07-containerapp-spec-pre-fix.yaml"), repo_rel("09-dapr-config-post-fix.json")],
            "observed_values": {
                "full_overlap_diff": overlap_diff_map,
                "full_overlap_equal": overlap_same_map,
                "overlap_paths": overlap_paths,
                "held_constant_checks": held_constant_checks,
                "pre_fix_spec_cross_reference": {
                    "image": pre_spec_image,
                    "ingress_target_port": pre_target_port,
                    "pre_fix_spec_dapr": pre_spec_dapr,
                    "resources": pre_spec_resources,
                    "scale": pre_spec_scale,
                },
            },
            "predicate": "Across the full overlapping field set captured in both 03 and 09, the only differing path is appPort; appId, appProtocol, and enabled compare equal. 07 cross-references the same pre-fix app spec with Dapr enabled, appPort 8081, and ingress targetPort 8000 on the ACR-backed Flask workload.",
            "result": "pass" if subgate_17b_pass else "fail",
            "sub_gate": "b_directly_captured_held_constant_fields_match",
        },
        {
            "claim": "The bounded-falsification gate explicitly lists the documented ceilings and unsupported inferences.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("17-bounded-falsification-gate.json")],
            "observed_values": {
                "documented_ceiling_ids": sorted(DOCUMENTED_EXPLICIT_DROPS_CEILING),
                "observed_drop_ids": [item["id"] for item in explicit_drops],
            },
            "predicate": "cohort_binding_note.explicit_drops ids equal the static documented ceiling {image_byte_identity, pod_uid_continuity, dapr_sidecar_pid_continuity, dapr_health_probe_timing, dns_resolution_timing} with no additions and no omissions.",
            "result": "pass" if subgate_17c_pass else "fail",
            "sub_gate": "c_explicit_drops_match_the_documented_ceiling",
        },
        {
            "claim": "Recovery is observed only after restoring Dapr appPort to 8000 in a later post-fix capture window.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("09-dapr-config-post-fix.json"), repo_rel("10-http-response-post-fix.json"), repo_rel("11-revision-list-post-fix.json")],
            "observed_values": {
                "post_fix_http_status": int(http_post.get("status_code", 0)),
                "post_revision": post_revision,
                "post_http_date": post_http_date.isoformat(),
                "pre_revision": pre_revision,
                "pre_http_date": pre_http_date.isoformat(),
                "restored_app_port": post_app_port,
            },
            "predicate": "09.appPort == 8000 AND 10.status_code == 200 AND the HTTP Date header captured in 10 is later than the HTTP Date header captured in 04.",
            "result": "pass" if subgate_17d_pass else "fail",
            "sub_gate": "d_recovery_is_observed_after_restoring_8000_in_a_later_capture_window",
        },
    ],
    "thresholds": {
        "held_constant_field_count": len(held_constant_checks),
        "post_fix_status_code_expected": 200,
        "pre_fix_status_code_expected": 200,
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
