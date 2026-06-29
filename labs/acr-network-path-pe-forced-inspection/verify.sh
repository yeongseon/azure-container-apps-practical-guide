#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/acr-network-path-pe-forced-inspection/evidence"
LAB_README_PATH="${SCRIPT_DIR}/README.md"
LAB_GUIDE_PATH="${SCRIPT_DIR}/../../docs/troubleshooting/lab-guides/acr-network-path-pe-forced-inspection.md"
UTC_NOW="${UTC_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR LAB_README_PATH LAB_GUIDE_PATH UTC_NOW

declare -a CANONICAL_RAW_FILES=(
    "01-app-spec-pre-fix.json"
    "02-revision-list-pre-fix.json"
    "03-route-table-pre-fix.json"
    "04-pe-nic-config-pre-fix.json"
    "05-acr-public-access-pre-fix.json"
    "06-firewall-log-baseline.json"
    "07-containerapp-spec-pre-fix.yaml"
    "08-h1-silence-window.json"
    "09-route-table-post-fix.json"
    "10-revision-list-post-fix.json"
    "11-app-spec-post-fix.json"
    "12-h2-recovery-window.json"
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
    "03-route-table-pre-fix.json",
    "04-pe-nic-config-pre-fix.json",
    "05-acr-public-access-pre-fix.json",
    "06-firewall-log-baseline.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-h1-silence-window.json",
    "09-route-table-post-fix.json",
    "10-revision-list-post-fix.json",
    "11-app-spec-post-fix.json",
    "12-h2-recovery-window.json",
]

def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))

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
        payload = load_json(evidence_dir / RAW_FILES[0])
    except Exception as exc:  # noqa: BLE001
        print(f"01 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    container_app = payload.get("container_app", {})
    metadata = payload.get("capture_metadata", {})
    ok = bool(container_app.get("name")) and bool(container_app.get("resourceGroup")) and bool(metadata.get("acr_login_server")) and bool(metadata.get("firewall_private_ip"))
    if ok:
        print("01 parses and captures the app surface plus baseline metadata")
        raise SystemExit(0)
    print("01 missing expected app or capture-metadata fields")
    raise SystemExit(1)

if gate_number == 6:
    try:
        revisions = load_json(evidence_dir / RAW_FILES[1])
        routes = load_json(evidence_dir / RAW_FILES[2])
    except Exception as exc:  # noqa: BLE001
        print(f"02/03 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(revisions, list) and len(revisions) >= 1 and isinstance(routes, dict) and isinstance(routes.get("routes"), list)
    if ok:
        print("02/03 parse and capture the H1 revision list plus route-table state")
        raise SystemExit(0)
    print("02/03 do not match the expected revision-list + route-table shape")
    raise SystemExit(1)

if gate_number == 7:
    try:
        nic = load_json(evidence_dir / RAW_FILES[3])
        acr = load_json(evidence_dir / RAW_FILES[4])
    except Exception as exc:  # noqa: BLE001
        print(f"04/05 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = bool(nic.get("id")) and acr.get("publicNetworkAccess") == "Disabled"
    if ok:
        print("04/05 parse and capture the PE NIC plus Disabled ACR public access")
        raise SystemExit(0)
    print("04/05 do not match the expected PE NIC + Disabled ACR shape")
    raise SystemExit(1)

if gate_number == 8:
    try:
        baseline = load_json(evidence_dir / RAW_FILES[5])
    except Exception as exc:  # noqa: BLE001
        print(f"06 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    rows = baseline.get("rows", [])
    ok = isinstance(rows, list) and isinstance(baseline.get("query"), str) and baseline.get("window_start_utc") and baseline.get("window_end_utc")
    if ok:
        print(f"06 parses as a baseline firewall-log payload with {len(rows)} rows")
        raise SystemExit(0)
    print("06 does not parse as the expected firewall-log payload")
    raise SystemExit(1)

if gate_number == 9:
    try:
        spec = load_yaml(evidence_dir / RAW_FILES[6])
    except Exception as exc:  # noqa: BLE001
        print(f"07 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ingress = spec.get("properties", {}).get("configuration", {}).get("ingress", {})
    ok = bool(spec.get("name")) and bool(spec.get("resourceGroup")) and int(ingress.get("targetPort", 0)) == 8080
    if ok:
        print("07 parses as YAML and pins ingress targetPort 8080")
        raise SystemExit(0)
    print("07 YAML does not match the expected container app shape")
    raise SystemExit(1)

if gate_number == 10:
    try:
        h1 = load_json(evidence_dir / RAW_FILES[7])
    except Exception as exc:  # noqa: BLE001
        print(f"08 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(h1.get("firewall_rows"), list) and isinstance(h1.get("system_rows"), list) and isinstance(h1.get("http_response"), dict) and h1.get("h1_trigger_ts_utc")
    if ok:
        print("08 parses as the H1 silence-window payload")
        raise SystemExit(0)
    print("08 does not capture the expected H1 silence-window payload")
    raise SystemExit(1)

if gate_number == 11:
    try:
        route_post = load_json(evidence_dir / RAW_FILES[8])
        revisions_post = load_json(evidence_dir / RAW_FILES[9])
    except Exception as exc:  # noqa: BLE001
        print(f"09/10 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(route_post.get("routes"), list) and isinstance(revisions_post, list) and len(revisions_post) >= 1
    if ok:
        print("09/10 parse and capture the restored route table plus H2 revision list")
        raise SystemExit(0)
    print("09/10 do not capture the expected H2 route / revision surface")
    raise SystemExit(1)

if gate_number == 12:
    try:
        post_payload = load_json(evidence_dir / RAW_FILES[10])
        h2 = load_json(evidence_dir / RAW_FILES[11])
    except Exception as exc:  # noqa: BLE001
        print(f"11/12 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = bool(post_payload.get("container_app", {}).get("name")) and isinstance(h2.get("firewall_rows"), list) and isinstance(h2.get("http_response"), dict) and h2.get("h2_recovery_ts_utc")
    if ok:
        print("11/12 parse and capture the H2 composite app surface plus recovery payload")
        raise SystemExit(0)
    print("11/12 do not capture the expected H2 composite surface")
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
    "6:pre-fix revisions and route table parse" \
    "7:pre-fix PE NIC and ACR access parse" \
    "8:baseline firewall-log payload parses" \
    "9:pre-fix YAML spec parses" \
    "10:h1 silence-window payload parses" \
    "11:post-fix route and revision captures parse" \
    "12:post-fix composite captures parse" \
    "13:readme surfaces exist"; do
    run_python_gate "${gate%%:*}" "${gate#*:}"
done

echo "## Phase B — Evidence pack verification"
if PHASE_B_OUTPUT="$(python3 <<'PY'
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
    "03-route-table-pre-fix.json",
    "04-pe-nic-config-pre-fix.json",
    "05-acr-public-access-pre-fix.json",
    "06-firewall-log-baseline.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-h1-silence-window.json",
    "09-route-table-post-fix.json",
    "10-revision-list-post-fix.json",
    "11-app-spec-post-fix.json",
    "12-h2-recovery-window.json",
]
GATE_FILES = [
    "14-cohort-integrity-gate.json",
    "15-h1-trigger-produces-failure-gate.json",
    "16-h2-fix-restores-recovery-gate.json",
    "17-bounded-falsification-gate.json",
]
EXPECTED_EVIDENCE_FILES = RAW_FILES + GATE_FILES + ["README.md"]
JUNK_NAMES = {".DS_Store"}
REVISION_ID_RE = re.compile(r"^/subscriptions/(?P<sub>[^/]+)/resourceGroups/(?P<rg>[^/]+)/providers/Microsoft\.App/containerApps/(?P<app>[^/]+)/revisions/(?P<rev>[^/]+)$")
DOCUMENTED_EXPLICIT_DROPS_CEILING = frozenset([
    "acr_firewall_log_ingestion_latency",
    "exact_pull_duration_milliseconds",
    "image_layer_sha",
    "node_image_cache_internals",
    "pod_uid_continuity",
    "replica_suffix_continuity",
    "route_propagation_subsecond_timing",
    "workload_source_ip_component_identity",
])

def repo_rel(name: str) -> str:
    return f"{REL}/{name}"

def load_json(name: str):
    return json.loads((EVIDENCE_DIR / name).read_text(encoding="utf-8"))

def load_yaml(name: str):
    return yaml.safe_load((EVIDENCE_DIR / name).read_text(encoding="utf-8"))

def parse_iso(text: str):
    value = datetime.fromisoformat(text.replace("Z", "+00:00"))
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)

def resolve_anchor_timestamp(name: str):
    if name == "06-firewall-log-baseline.json":
        dt = parse_iso(baseline_payload.get("window_end_utc"))
        return {
            "timestamp": dt,
            "timestamp_utc": dt.isoformat(),
            "time_source": "payload.window_end_utc",
            "raw_epoch": baseline_payload.get("window_end_utc"),
        }
    if name == "08-h1-silence-window.json":
        dt = parse_iso(h1_payload.get("h1_trigger_ts_utc"))
        return {
            "timestamp": dt,
            "timestamp_utc": dt.isoformat(),
            "time_source": "payload.h1_trigger_ts_utc",
            "raw_epoch": h1_payload.get("h1_trigger_ts_utc"),
        }
    if name == "02-revision-list-pre-fix.json" and pre_bypass_revision is not None:
        dt = parse_iso(pre_bypass_revision.get("properties", {}).get("createdTime"))
        return {
            "timestamp": dt,
            "timestamp_utc": dt.isoformat(),
            "time_source": "revision.createdTime",
            "raw_epoch": pre_bypass_revision.get("properties", {}).get("createdTime"),
        }
    if name == "09-route-table-post-fix.json":
        dt = parse_iso(h2_payload.get("h2_recovery_ts_utc"))
        return {
            "timestamp": dt,
            "timestamp_utc": dt.isoformat(),
            "time_source": "payload.h2_recovery_ts_utc",
            "raw_epoch": h2_payload.get("h2_recovery_ts_utc"),
        }
    if name == "10-revision-list-post-fix.json" and post_recover_revision is not None:
        dt = parse_iso(post_recover_revision.get("properties", {}).get("createdTime"))
        return {
            "timestamp": dt,
            "timestamp_utc": dt.isoformat(),
            "time_source": "revision.createdTime",
            "raw_epoch": post_recover_revision.get("properties", {}).get("createdTime"),
        }
    if name == "12-h2-recovery-window.json":
        dt = parse_iso(h2_payload.get("h2_recovery_ts_utc"))
        return {
            "timestamp": dt,
            "timestamp_utc": dt.isoformat(),
            "time_source": "payload.h2_recovery_ts_utc",
            "raw_epoch": h2_payload.get("h2_recovery_ts_utc"),
        }
    stat = (EVIDENCE_DIR / name).stat()
    birthtime = getattr(stat, "st_birthtime", None)
    if birthtime is not None and birthtime > 0:
        dt = datetime.fromtimestamp(birthtime, tz=timezone.utc)
        return {
            "timestamp": dt,
            "timestamp_utc": dt.isoformat(),
            "time_source": "birthtime",
            "raw_epoch": birthtime,
        }
    dt = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)
    return {
        "timestamp": dt,
        "timestamp_utc": dt.isoformat(),
        "time_source": "mtime",
        "raw_epoch": stat.st_mtime,
    }

def parse_revision_id(revision_id: str):
    match = REVISION_ID_RE.match(revision_id or "")
    if not match:
        return {"resource_group": None, "container_app": None, "revision": None}
    return {
        "resource_group": match.group("rg"),
        "container_app": match.group("app"),
        "revision": match.group("rev"),
    }

def flatten_json(prefix, value):
    if isinstance(value, dict):
        out = {}
        for key, inner in value.items():
            child = f"{prefix}.{key}" if prefix else key
            out.update(flatten_json(child, inner))
        return out
    if isinstance(value, list):
        out = {}
        for index, inner in enumerate(value):
            child = f"{prefix}[{index}]"
            out.update(flatten_json(child, inner))
        return out
    return {prefix: value}

def revision_sort_key(revision):
    created = revision.get("properties", {}).get("createdTime")
    return parse_iso(created) if created else datetime.min.replace(tzinfo=timezone.utc)

def find_revision_by_tag(revisions, tag: str):
    matches = []
    for row in revisions:
        containers = row.get("properties", {}).get("template", {}).get("containers", [])
        image = containers[0].get("image", "") if containers else ""
        if image.endswith(f":{tag}"):
            matches.append(row)
    if not matches:
        return None
    return sorted(matches, key=revision_sort_key, reverse=True)[0]

def nic_ip_map(nic_payload):
    mapping = []
    for config in nic_payload.get("ipConfigurations", []):
        fqdns = config.get("privateLinkConnectionProperties", {}).get("fqdns", []) or []
        mapping.append({
            "name": config.get("name"),
            "private_ip": config.get("privateIPAddress"),
            "fqdns": sorted(fqdns),
        })
    return sorted(mapping, key=lambda item: (item["private_ip"] or "", ",".join(item["fqdns"])))

def route_summary(route_payload):
    rows = route_payload.get("routes", route_payload)
    out = []
    for row in rows:
        out.append({
            "name": row.get("name"),
            "addressPrefix": row.get("addressPrefix"),
            "nextHopType": row.get("nextHopType"),
            "nextHopIpAddress": row.get("nextHopIpAddress"),
        })
    return sorted(out, key=lambda item: item.get("name") or "")

def exact_pe_route_state(route_rows, pe_ips, firewall_private_ip):
    route_map = {row.get("addressPrefix"): row for row in route_rows}
    details = []
    all_present = True
    for ip in pe_ips:
        row = route_map.get(f"{ip}/32")
        holds = bool(row) and row.get("nextHopType") == "VirtualAppliance" and row.get("nextHopIpAddress") == firewall_private_ip
        details.append({
            "private_ip": ip,
            "route": row,
            "holds": holds,
        })
        all_present = all_present and holds
    return all_present, details

def exact_pe_route_absence(route_rows, pe_ips):
    prefixes = {row.get("addressPrefix") for row in route_rows}
    details = []
    all_absent = True
    for ip in pe_ips:
        holds = f"{ip}/32" not in prefixes
        details.append({"private_ip": ip, "holds": holds})
        all_absent = all_absent and holds
    return all_absent, details

def extract_env(container):
    return {item.get("name"): item.get("value") for item in container.get("env", [])}

def image_tag(image: str):
    return image.split(":")[-1] if ":" in image else image

pre_app_payload = load_json("01-app-spec-pre-fix.json")
revisions_pre = load_json("02-revision-list-pre-fix.json")
route_pre_payload = load_json("03-route-table-pre-fix.json")
pe_nic_pre = load_json("04-pe-nic-config-pre-fix.json")
acr_pre = load_json("05-acr-public-access-pre-fix.json")
baseline_payload = load_json("06-firewall-log-baseline.json")
spec_pre = load_yaml("07-containerapp-spec-pre-fix.yaml")
h1_payload = load_json("08-h1-silence-window.json")
route_post_payload = load_json("09-route-table-post-fix.json")
revisions_post = load_json("10-revision-list-post-fix.json")
post_payload = load_json("11-app-spec-post-fix.json")
h2_payload = load_json("12-h2-recovery-window.json")

pre_app = pre_app_payload["container_app"]
post_app = post_payload["container_app"]
post_acr = post_payload["acr"]
pe_nic_post = post_payload["pe_nic"]
capture_meta = pre_app_payload["capture_metadata"]

app_name = pre_app["name"]
resource_group = pre_app["resourceGroup"]
acr_login_server = capture_meta["acr_login_server"]
acr_data_fqdn = capture_meta["acr_data_fqdn"]
firewall_private_ip = capture_meta["firewall_private_ip"]
pe_ip_map = capture_meta["pe_ip_map"]
pe_ips = sorted(item["private_ip"] for item in pe_ip_map if item.get("private_ip"))

route_pre = route_summary(route_pre_payload)
route_post = route_summary(route_post_payload)
default_route_pre = next((row for row in route_pre if row.get("name") == "default-via-afw"), None)
default_route_post = next((row for row in route_post if row.get("name") == "default-via-afw"), None)
pre_route_absent, pre_route_absence_details = exact_pe_route_absence(route_pre, pe_ips)
post_route_present, post_route_present_details = exact_pe_route_state(route_post, pe_ips, firewall_private_ip)

pre_nic_map = nic_ip_map(pe_nic_pre)
post_nic_map = nic_ip_map(pe_nic_post)
pe_nic_unchanged = pre_nic_map == post_nic_map

baseline_rows = baseline_payload.get("rows", [])
h1_rows = h1_payload.get("firewall_rows", [])
h2_rows = h2_payload.get("firewall_rows", [])
baseline_acr_fw_log_count = int(baseline_payload.get("row_count", len(baseline_rows)))
h1_window_acr_fw_log_count = int(h1_payload.get("firewall_row_count", len(h1_rows)))
h2_window_acr_fw_log_count = int(h2_payload.get("firewall_row_count", len(h2_rows)))

baseline_window_start = baseline_payload.get("window_start_utc")
baseline_window_end = baseline_payload.get("window_end_utc")
h1_trigger_ts_utc = h1_payload.get("h1_trigger_ts_utc")
h2_recovery_ts_utc = h2_payload.get("h2_recovery_ts_utc")

baseline_sources = sorted({row.get("Source") for row in baseline_rows if row.get("Source")})
h1_sources = sorted({row.get("Source") for row in h1_rows if row.get("Source")})
h2_sources = sorted({row.get("Source") for row in h2_rows if row.get("Source")})

baseline_fqdns = sorted({row.get("Fqdn") for row in baseline_rows if row.get("Fqdn")})
h1_fqdns = sorted({row.get("Fqdn") for row in h1_rows if row.get("Fqdn")})
h2_fqdns = sorted({row.get("Fqdn") for row in h2_rows if row.get("Fqdn")})

pre_bypass_revision = find_revision_by_tag(revisions_pre, "v-bypass")
post_recover_revision = find_revision_by_tag(revisions_post, "v-recover")
baseline_revision = find_revision_by_tag(revisions_post, "v1") or find_revision_by_tag(revisions_pre, "v1")
post_latest_revision = sorted(revisions_post, key=revision_sort_key, reverse=True)[0] if revisions_post else None

parse_errors = []
for name in [
    "01-app-spec-pre-fix.json",
    "02-revision-list-pre-fix.json",
    "03-route-table-pre-fix.json",
    "04-pe-nic-config-pre-fix.json",
    "05-acr-public-access-pre-fix.json",
    "06-firewall-log-baseline.json",
    "08-h1-silence-window.json",
    "09-route-table-post-fix.json",
    "10-revision-list-post-fix.json",
    "11-app-spec-post-fix.json",
    "12-h2-recovery-window.json",
]:
    try:
        load_json(name)
    except Exception as exc:  # noqa: BLE001
        parse_errors.append(f"{name}: {type(exc).__name__}: {exc}")
try:
    load_yaml("07-containerapp-spec-pre-fix.yaml")
except Exception as exc:  # noqa: BLE001
    parse_errors.append(f"07-containerapp-spec-pre-fix.yaml: {type(exc).__name__}: {exc}")

pre_anchor_files = [
    "02-revision-list-pre-fix.json",
    "06-firewall-log-baseline.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-h1-silence-window.json",
]
post_anchor_files = [
    "09-route-table-post-fix.json",
    "10-revision-list-post-fix.json",
    "12-h2-recovery-window.json",
]
pre_anchor_infos = {name: resolve_anchor_timestamp(name) for name in pre_anchor_files}
post_anchor_infos = {name: resolve_anchor_timestamp(name) for name in post_anchor_files}
all_anchor_infos = {**pre_anchor_infos, **post_anchor_infos}
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
    for name, info in sorted(all_anchor_infos.items(), key=lambda item: item[1]["timestamp"])
]
time_source_summary = {
    "birthtime_count": sum(1 for info in all_anchor_infos.values() if info["time_source"] == "birthtime"),
    "mtime_count": sum(1 for info in all_anchor_infos.values() if info["time_source"] == "mtime"),
    "fallback_used": any(info["time_source"] == "mtime" for info in all_anchor_infos.values()),
}
utc_window_start = min(info["timestamp"] for info in all_anchor_infos.values())
utc_window_end = max(info["timestamp"] for info in all_anchor_infos.values())
utc_window_span_seconds = (utc_window_end - utc_window_start).total_seconds()
strong_temporal = monotonic_ordering_holds and utc_window_span_seconds <= 1800
fallback_temporal = monotonic_ordering_holds and utc_window_span_seconds <= 5400
path_used = "strong" if strong_temporal else "fallback"

observed_files_on_disk = sorted(path.name for path in EVIDENCE_DIR.iterdir() if path.is_file())
non_junk_files = [name for name in observed_files_on_disk if name not in JUNK_NAMES]
unexpected_non_junk = [name for name in non_junk_files if name not in EXPECTED_EVIDENCE_FILES]
readme_text = (EVIDENCE_DIR / "README.md").read_text(encoding="utf-8")
expected_xrefs = GATE_FILES
observed_xrefs = [name for name in expected_xrefs if name in readme_text]

pre_revision_id = pre_bypass_revision.get("id") if pre_bypass_revision else ""
post_revision_id = post_recover_revision.get("id") if post_recover_revision else ""
pre_revision_parts = parse_revision_id(pre_revision_id)
post_revision_parts = parse_revision_id(post_revision_id)
pre_parse_ok = pre_revision_parts.get("resource_group") is not None and pre_revision_parts.get("container_app") is not None
post_parse_ok = post_revision_parts.get("resource_group") is not None and post_revision_parts.get("container_app") is not None
both_parse_ok = pre_parse_ok and post_parse_ok
pre_post_rg_equal = both_parse_ok and pre_revision_parts["resource_group"] == post_revision_parts["resource_group"]
pre_post_app_equal = both_parse_ok and pre_revision_parts["container_app"] == post_revision_parts["container_app"]
pre_post_lineage_equal = both_parse_ok and pre_post_rg_equal and pre_post_app_equal

pre_bypass_props = pre_bypass_revision.get("properties", {}) if pre_bypass_revision else {}
post_recover_props = post_recover_revision.get("properties", {}) if post_recover_revision else {}
post_latest_props = post_latest_revision.get("properties", {}) if post_latest_revision else {}

all_revisions_healthy_pre = all(
    row.get("properties", {}).get("healthState") == "Healthy"
    and row.get("properties", {}).get("runningState") in {"Running", "RunningAtMaxScale", None}
    and row.get("properties", {}).get("provisioningState") in {"Provisioned", None}
    for row in revisions_pre
)
all_revisions_healthy_post = all(
    row.get("properties", {}).get("healthState") == "Healthy"
    and row.get("properties", {}).get("runningState") in {"Running", "RunningAtMaxScale", None}
    and row.get("properties", {}).get("provisioningState") in {"Provisioned", None}
    for row in revisions_post
)

pre_h1_counts = {
    "imagepull_failed_count": int(h1_payload.get("imagepull_failed_count", 0)),
    "revision_failed_count": int(h1_payload.get("revision_failed_count", 0)),
    "imagepull_unauthorized_count": int(h1_payload.get("imagepull_unauthorized_count", 0)),
    "zero_imagepull_failures": bool(h1_payload.get("zero_imagepull_failures", False)),
    "zero_revision_failures": bool(h1_payload.get("zero_revision_failures", False)),
    "all_revisions_healthy": bool(h1_payload.get("all_revisions_healthy", False)),
}
post_h2_counts = {
    "imagepull_failed_count": int(h2_payload.get("imagepull_failed_count", 0)),
    "revision_failed_count": int(h2_payload.get("revision_failed_count", 0)),
    "imagepull_unauthorized_count": int(h2_payload.get("imagepull_unauthorized_count", 0)),
    "zero_imagepull_failures": bool(h2_payload.get("zero_imagepull_failures", False)),
    "zero_revision_failures": bool(h2_payload.get("zero_revision_failures", False)),
    "all_revisions_healthy": bool(h2_payload.get("all_revisions_healthy", False)),
}

overall_zero_imagepull_failures = pre_h1_counts["zero_imagepull_failures"] and post_h2_counts["zero_imagepull_failures"]
overall_zero_revision_failures = pre_h1_counts["zero_revision_failures"] and post_h2_counts["zero_revision_failures"]
all_revisions_healthy_throughout = all_revisions_healthy_pre and all_revisions_healthy_post and pre_h1_counts["all_revisions_healthy"] and post_h2_counts["all_revisions_healthy"]

pre_container = pre_app.get("properties", {}).get("template", {}).get("containers", [])[0]
post_container = post_app.get("properties", {}).get("template", {}).get("containers", [])[0]
pre_env = extract_env(pre_container)
post_env = extract_env(post_container)
pre_scale = pre_app.get("properties", {}).get("template", {}).get("scale", {})
post_scale = post_app.get("properties", {}).get("template", {}).get("scale", {})
pre_ingress = pre_app.get("properties", {}).get("configuration", {}).get("ingress", {})
post_ingress = post_app.get("properties", {}).get("configuration", {}).get("ingress", {})

pre_norm = {
    "container_app": {
        "name": pre_app.get("name"),
        "resource_group": pre_app.get("resourceGroup"),
        "revision": {
            "latest_ready_revision_name": pre_app.get("properties", {}).get("latestReadyRevisionName"),
            "latest_revision_name": pre_app.get("properties", {}).get("latestRevisionName"),
            "target_revision_name": pre_bypass_revision.get("name") if pre_bypass_revision else None,
            "target_image": pre_bypass_revision.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("image") if pre_bypass_revision else None,
        },
        "container": {
            "name": pre_container.get("name"),
            "cpu": pre_container.get("resources", {}).get("cpu"),
            "memory": pre_container.get("resources", {}).get("memory"),
            "image_repository": pre_container.get("image", "").split(":")[0] if pre_container.get("image") else None,
            "acr_login_server": pre_env.get("ACR_LOGIN_SERVER"),
        },
        "ingress": {
            "external": pre_ingress.get("external"),
            "target_port": pre_ingress.get("targetPort"),
        },
        "scale": {
            "min_replicas": pre_scale.get("minReplicas"),
            "max_replicas": pre_scale.get("maxReplicas"),
        },
    },
    "acr": {
        "publicNetworkAccess": acr_pre.get("publicNetworkAccess"),
        "loginServer": acr_pre.get("loginServer"),
    },
    "pe_nic": pre_nic_map,
    "route_table": {
        "default_route": default_route_pre,
        "pe32_present": False,
    },
    "firewall_observation": {
        "baseline_presence_count": baseline_acr_fw_log_count,
        "h1_window_count": h1_window_acr_fw_log_count,
        "h2_window_count": h2_window_acr_fw_log_count,
    },
    "workload": {
        "build_tag": h1_payload.get("http_response", {}).get("body_json", {}).get("build_tag"),
        "all_revisions_healthy": pre_h1_counts["all_revisions_healthy"],
        "zero_imagepull_failures": pre_h1_counts["zero_imagepull_failures"],
        "zero_revision_failures": pre_h1_counts["zero_revision_failures"],
    },
}

post_norm = {
    "container_app": {
        "name": post_app.get("name"),
        "resource_group": post_app.get("resourceGroup"),
        "revision": {
            "latest_ready_revision_name": post_app.get("properties", {}).get("latestReadyRevisionName"),
            "latest_revision_name": post_app.get("properties", {}).get("latestRevisionName"),
            "target_revision_name": post_recover_revision.get("name") if post_recover_revision else None,
            "target_image": post_recover_revision.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("image") if post_recover_revision else None,
        },
        "container": {
            "name": post_container.get("name"),
            "cpu": post_container.get("resources", {}).get("cpu"),
            "memory": post_container.get("resources", {}).get("memory"),
            "image_repository": post_container.get("image", "").split(":")[0] if post_container.get("image") else None,
            "acr_login_server": post_env.get("ACR_LOGIN_SERVER"),
        },
        "ingress": {
            "external": post_ingress.get("external"),
            "target_port": post_ingress.get("targetPort"),
        },
        "scale": {
            "min_replicas": post_scale.get("minReplicas"),
            "max_replicas": post_scale.get("maxReplicas"),
        },
    },
    "acr": {
        "publicNetworkAccess": post_acr.get("publicNetworkAccess"),
        "loginServer": post_acr.get("loginServer"),
    },
    "pe_nic": post_nic_map,
    "route_table": {
        "default_route": default_route_post,
        "pe32_present": True,
    },
    "firewall_observation": {
        "baseline_presence_count": baseline_acr_fw_log_count,
        "h1_window_count": h1_window_acr_fw_log_count,
        "h2_window_count": h2_window_acr_fw_log_count,
    },
    "workload": {
        "build_tag": h2_payload.get("http_response", {}).get("body_json", {}).get("build_tag"),
        "all_revisions_healthy": post_h2_counts["all_revisions_healthy"],
        "zero_imagepull_failures": post_h2_counts["zero_imagepull_failures"],
        "zero_revision_failures": post_h2_counts["zero_revision_failures"],
    },
}

flattened_pre = flatten_json("", pre_norm)
flattened_post = flatten_json("", post_norm)
overlap_paths = sorted(set(flattened_pre) & set(flattened_post))
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
allowed_expected_diff_paths = {
    "container_app.revision.latest_ready_revision_name",
    "container_app.revision.latest_revision_name",
    "container_app.revision.target_image",
    "container_app.revision.target_revision_name",
    "route_table.pe32_present",
    "workload.build_tag",
}
unexpected_overlap_diffs = {
    path: value for path, value in overlap_diff_map.items()
    if path not in allowed_expected_diff_paths
}

held_constant_checks = {
    "acr_public_network_access_disabled": {
        "pre_value": acr_pre.get("publicNetworkAccess"),
        "post_value": post_acr.get("publicNetworkAccess"),
        "equal": acr_pre.get("publicNetworkAccess") == post_acr.get("publicNetworkAccess") == "Disabled",
    },
    "acr_login_server": {
        "pre_value": acr_pre.get("loginServer"),
        "post_value": post_acr.get("loginServer"),
        "equal": acr_pre.get("loginServer") == post_acr.get("loginServer"),
    },
    "container_app_name": {
        "pre_value": pre_app.get("name"),
        "post_value": post_app.get("name"),
        "equal": pre_app.get("name") == post_app.get("name"),
    },
    "resource_group": {
        "pre_value": pre_app.get("resourceGroup"),
        "post_value": post_app.get("resourceGroup"),
        "equal": pre_app.get("resourceGroup") == post_app.get("resourceGroup"),
    },
    "container_name": {
        "pre_value": pre_container.get("name"),
        "post_value": post_container.get("name"),
        "equal": pre_container.get("name") == post_container.get("name"),
    },
    "image_repository": {
        "pre_value": pre_container.get("image", "").split(":")[0] if pre_container.get("image") else None,
        "post_value": post_container.get("image", "").split(":")[0] if post_container.get("image") else None,
        "equal": (pre_container.get("image", "").split(":")[0] if pre_container.get("image") else None) == (post_container.get("image", "").split(":")[0] if post_container.get("image") else None),
    },
    "cpu": {
        "pre_value": pre_container.get("resources", {}).get("cpu"),
        "post_value": post_container.get("resources", {}).get("cpu"),
        "equal": pre_container.get("resources", {}).get("cpu") == post_container.get("resources", {}).get("cpu"),
    },
    "memory": {
        "pre_value": pre_container.get("resources", {}).get("memory"),
        "post_value": post_container.get("resources", {}).get("memory"),
        "equal": pre_container.get("resources", {}).get("memory") == post_container.get("resources", {}).get("memory"),
    },
    "ingress_target_port": {
        "pre_value": pre_ingress.get("targetPort"),
        "post_value": post_ingress.get("targetPort"),
        "equal": pre_ingress.get("targetPort") == post_ingress.get("targetPort"),
    },
    "min_replicas": {
        "pre_value": pre_scale.get("minReplicas"),
        "post_value": post_scale.get("minReplicas"),
        "equal": pre_scale.get("minReplicas") == post_scale.get("minReplicas"),
    },
    "max_replicas": {
        "pre_value": pre_scale.get("maxReplicas"),
        "post_value": post_scale.get("maxReplicas"),
        "equal": pre_scale.get("maxReplicas") == post_scale.get("maxReplicas"),
    },
    "default_route": {
        "pre_value": default_route_pre,
        "post_value": default_route_post,
        "equal": default_route_pre == default_route_post,
    },
    "pe_nic_ip_map": {
        "pre_value": pre_nic_map,
        "post_value": post_nic_map,
        "equal": pe_nic_unchanged,
    },
}

explicit_drops = [
    {
        "id": "acr_firewall_log_ingestion_latency",
        "note": "The pack proves presence-versus-absence after bounded waits, not the exact second that every Azure Firewall log row landed in Log Analytics.",
    },
    {
        "id": "exact_pull_duration_milliseconds",
        "note": "The pack proves the pull succeeded and whether the firewall saw it, not the exact transfer duration of each image layer.",
    },
    {
        "id": "image_layer_sha",
        "note": "The pack proves tag-level fresh-pull identity through build_tag and image references, not immutable OCI layer digests.",
    },
    {
        "id": "node_image_cache_internals",
        "note": "The pack does not inspect the hidden node cache implementation beyond the observed fresh-pull markers carried by the new tags and responses.",
    },
    {
        "id": "pod_uid_continuity",
        "note": "The pack reasons at the revision and workload-response layer, not at the Kubernetes pod UID layer.",
    },
    {
        "id": "replica_suffix_continuity",
        "note": "Replica suffixes are scheduler-generated and are not the causal field under test for the silence-gate claim.",
    },
    {
        "id": "route_propagation_subsecond_timing",
        "note": "The pack documents bounded route-propagation waits but does not claim the exact subsecond convergence time of the UDR updates.",
    },
    {
        "id": "workload_source_ip_component_identity",
        "note": "The firewall sees an ACA workload-subnet source IP, but the pack does not overclaim which internal ACA component emitted that exact connection.",
    },
]
runtime_drop_ids = frozenset(item["id"] for item in explicit_drops)

subgate_14a_pass = not parse_errors
subgate_14b_pass = strong_temporal or fallback_temporal
subgate_14c_pass = both_parse_ok and pre_post_lineage_equal
subgate_14d_pass = pe_nic_unchanged and not unexpected_non_junk and observed_xrefs == expected_xrefs
subgate_14e_pass = utc_window_start <= utc_window_end and all(item["timestamp_utc"] for item in all_anchor_infos.values())
gate_14_all_subgates_pass = all([subgate_14a_pass, subgate_14b_pass, subgate_14c_pass, subgate_14d_pass, subgate_14e_pass])

subgate_15a_pass = baseline_acr_fw_log_count > 0
subgate_15b_pass = pre_route_absent and default_route_pre is not None and default_route_pre.get("addressPrefix") == "0.0.0.0/0"
subgate_15c_pass = acr_pre.get("publicNetworkAccess") == "Disabled" and pre_bypass_revision is not None and pre_bypass_props.get("healthState") == "Healthy" and image_tag(pre_bypass_revision.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("image", "")) == "v-bypass" and h1_payload.get("http_response", {}).get("body_json", {}).get("build_tag") == "v-bypass"
subgate_15d_pass = h1_window_acr_fw_log_count == 0
subgate_15e_pass = all_revisions_healthy_pre and pre_h1_counts["all_revisions_healthy"] and pre_h1_counts["zero_imagepull_failures"] and pre_h1_counts["zero_revision_failures"]
gate_15_all_subgates_pass = all([subgate_15a_pass, subgate_15b_pass, subgate_15c_pass, subgate_15d_pass, subgate_15e_pass])

subgate_16a_pass = post_route_present and default_route_post is not None and default_route_post.get("addressPrefix") == "0.0.0.0/0"
subgate_16b_pass = post_recover_revision is not None and post_recover_props.get("healthState") == "Healthy" and post_recover_props.get("active") is True and post_latest_revision and post_latest_revision.get("name") == post_recover_revision.get("name")
subgate_16c_pass = h2_window_acr_fw_log_count > 0 and h2_payload.get("http_response", {}).get("body_json", {}).get("build_tag") == "v-recover"
subgate_16d_pass = post_acr.get("publicNetworkAccess") == "Disabled" and all_revisions_healthy_post and post_h2_counts["all_revisions_healthy"] and post_h2_counts["zero_imagepull_failures"] and post_h2_counts["zero_revision_failures"]
gate_16_all_subgates_pass = all([subgate_16a_pass, subgate_16b_pass, subgate_16c_pass, subgate_16d_pass])

subgate_17a_pass = h1_window_acr_fw_log_count == 0 and baseline_acr_fw_log_count > 0
subgate_17b_pass = h2_window_acr_fw_log_count > 0
subgate_17c_pass = all_revisions_healthy_throughout and overall_zero_imagepull_failures and overall_zero_revision_failures and pre_h1_counts["imagepull_failed_count"] == 0 and post_h2_counts["imagepull_failed_count"] == 0 and pre_h1_counts["revision_failed_count"] == 0 and post_h2_counts["revision_failed_count"] == 0
subgate_17d_pass = all(item["equal"] for item in held_constant_checks.values()) and not unexpected_overlap_diffs and runtime_drop_ids == DOCUMENTED_EXPLICIT_DROPS_CEILING
gate_17_all_subgates_pass = all([subgate_17a_pass, subgate_17b_pass, subgate_17c_pass, subgate_17d_pass])

gate14 = {
    "claim": f"The 12-file acr-network-path-pe-forced-inspection raw cohort is internally consistent: every canonical file is present and parseable, every per-file UTC anchor falls within one bounded capture window, the H1 and H2 revision IDs parse to the same {resource_group} / {app_name} lineage, and the PE NIC IP map stays unchanged across the silence-gate arc.",
    "claim_level": "Observed",
    "gate_classification": "Cohort integrity gate: structural pre-condition for the bounded-falsification pack.",
    "hypothesis": "H_cohort_integrity",
    "path_used": path_used,
    "predicate_inputs": {
        "app_spec_pre": repo_rel("01-app-spec-pre-fix.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
        "pe_nic_pre": repo_rel("04-pe-nic-config-pre-fix.json"),
        "route_table_post": repo_rel("09-route-table-post-fix.json"),
        "app_spec_post": repo_rel("11-app-spec-post-fix.json"),
        "evidence_readme": repo_rel("README.md"),
    },
    "acr_network_path_pe_forced_inspection_h_cohort_integrity_all_subgates_pass": gate_14_all_subgates_pass,
    "acr_network_path_pe_forced_inspection_h_cohort_integrity_sub_gates": {
        "a_canonical_raw_files_present_and_parse": subgate_14a_pass,
        "b_every_per_file_utc_anchor_falls_within_one_bounded_window": subgate_14b_pass,
        "c_revision_id_lineage_parses_and_compares_equal": subgate_14c_pass,
        "d_pe_nic_ip_map_is_unchanged_and_readme_xrefs_exist": subgate_14d_pass,
        "e_utc_reference_and_span_math_stay_consistent": subgate_14e_pass,
    },
    "scenario": "acr_network_path_pe_forced_inspection",
    "sub_gates": [
        {
            "claim": "All 12 canonical raw evidence files exist and parse as JSON or YAML.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel(name) for name in RAW_FILES],
            "observed_values": {
                "observed_missing": [name for name in RAW_FILES if not (EVIDENCE_DIR / name).is_file()],
                "observed_present_count": sum((EVIDENCE_DIR / name).is_file() for name in RAW_FILES),
                "parse_errors": parse_errors,
                "strong": {"expected_count": 12, "holds": not parse_errors},
                "fallback": {"expected_count": 12, "holds": not parse_errors},
            },
            "predicate": "Strong and fallback both require the full 12-file raw cohort to exist; 01,02,03,04,05,06,08,09,10,11,12 parse as JSON; 07 parses as YAML.",
            "result": "pass" if subgate_14a_pass else "fail",
            "sub_gate": "a_canonical_raw_files_present_and_parse",
        },
        {
            "claim": "Every per-file UTC anchor stays inside one coherent capture window and every post-fix anchor is later than every pre-fix anchor.",
            "claim_level": "Measured",
            "evidence_files": [repo_rel(name) for name in RAW_FILES],
            "observed_values": {
                "utc_window_start": utc_window_start.isoformat(),
                "utc_window_end": utc_window_end.isoformat(),
                "utc_window_span_seconds": utc_window_span_seconds,
                "monotonic_ordering_holds": monotonic_ordering_holds,
                "pre_anchor_timestamps": {name: {"timestamp_utc": info["timestamp_utc"], "time_source": info["time_source"], "raw_epoch": info["raw_epoch"]} for name, info in pre_anchor_infos.items()},
                "post_anchor_timestamps": {name: {"timestamp_utc": info["timestamp_utc"], "time_source": info["time_source"], "raw_epoch": info["raw_epoch"]} for name, info in post_anchor_infos.items()},
                "sorted_anchor_sequence": sorted_anchor_sequence,
                "strict_pairwise_order_checks": monotonic_pairs,
                "strong": {"holds": strong_temporal, "max_span_seconds": 1800},
                "fallback": {"holds": fallback_temporal, "max_span_seconds": 5400},
                "time_source_summary": time_source_summary,
            },
            "predicate": "All configured post-fix file birth-times (falling back to mtime when birth-time is unavailable) are strictly later than all configured pre-fix file anchors, and the total window is <= 1800 seconds on the strong path or <= 5400 seconds on the fallback path.",
            "result": "pass" if subgate_14b_pass else "fail",
            "sub_gate": "b_every_per_file_utc_anchor_falls_within_one_bounded_window",
        },
        {
            "claim": "The H1 bypass revision and H2 recovery revision parse to the same resource-group/container-app lineage.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("10-revision-list-post-fix.json")],
            "observed_values": {
                "pre_revision_id": pre_revision_id,
                "post_revision_id": post_revision_id,
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
            "predicate": "The v-bypass revision ID in 02 and the v-recover revision ID in 10 both match the /subscriptions/.../resourceGroups/.../containerApps/.../revisions/... regex, and the parsed resourceGroup + containerApp components compare equal only when both parses succeed.",
            "result": "pass" if subgate_14c_pass else "fail",
            "sub_gate": "c_revision_id_lineage_parses_and_compares_equal",
        },
        {
            "claim": "The PE NIC IP map is unchanged across H1 and H2, no unexpected non-junk extras exist, and evidence/README.md literally names all four Phase B outputs.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("04-pe-nic-config-pre-fix.json"), repo_rel("11-app-spec-post-fix.json"), repo_rel("README.md")],
            "observed_values": {
                "expected_xrefs": expected_xrefs,
                "ignored_junk": sorted(JUNK_NAMES),
                "observed_files_on_disk": observed_files_on_disk,
                "observed_non_junk_extras": unexpected_non_junk,
                "observed_xrefs": observed_xrefs,
                "pre_nic_map": pre_nic_map,
                "post_nic_map": post_nic_map,
                "pe_nic_unchanged": pe_nic_unchanged,
            },
            "predicate": "The normalized PE NIC ipConfigurations captured in 04 and 11.pe_nic compare equal, extras == [], and evidence/README.md contains the four gate filenames literally.",
            "result": "pass" if subgate_14d_pass else "fail",
            "sub_gate": "d_pe_nic_ip_map_is_unchanged_and_readme_xrefs_exist",
        },
        {
            "claim": "UTC references and span math are internally consistent.",
            "claim_level": "Measured",
            "evidence_files": [repo_rel(name) for name in RAW_FILES],
            "observed_values": {
                "utc_window_start": utc_window_start.isoformat(),
                "utc_window_end": utc_window_end.isoformat(),
                "utc_window_span_seconds": utc_window_span_seconds,
                "time_source_summary": time_source_summary,
            },
            "predicate": "utc_window_start <= utc_window_end and every anchor has an explicit time_source disclosure.",
            "result": "pass" if subgate_14e_pass else "fail",
            "sub_gate": "e_utc_reference_and_span_math_stay_consistent",
        },
    ],
    "thresholds": {
        "canonical_count_strong": 12,
        "canonical_count_fallback_floor": 12,
        "utc_window_span_strong_seconds_max": 1800,
        "utc_window_span_fallback_seconds_max": 5400,
    },
    "utc_captured": UTC_NOW,
}

gate15 = {
    "claim": f"The H1 trigger produced the Path C silence-gate surface on {app_name}: the baseline pull window already proved the firewall saw ACR traffic, the PE /32 UDR routes were removed while the default route stayed in place, ACR public access stayed Disabled, the v-bypass pull still succeeded to a Healthy revision, and the broken H1 window contains zero new Azure Firewall ACR rows.",
    "claim_level": "Observed",
    "gate_classification": "H1 gate: confirms that removing the PE /32 UDR routes silently bypassed the firewall without breaking the pull.",
    "hypothesis": "H1_trigger_produces_failure",
    "path_used": "single",
    "predicate_inputs": {
        "baseline_firewall_log": repo_rel("06-firewall-log-baseline.json"),
        "route_table_pre": repo_rel("03-route-table-pre-fix.json"),
        "acr_public_access_pre": repo_rel("05-acr-public-access-pre-fix.json"),
        "h1_silence_window": repo_rel("08-h1-silence-window.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
    },
    "acr_network_path_pe_forced_inspection_h1_trigger_produces_failure_all_subgates_pass": gate_15_all_subgates_pass,
    "acr_network_path_pe_forced_inspection_h1_trigger_produces_failure_sub_gates": {
        "a_baseline_presence_proves_the_firewall_would_see_acr_when_routes_are_intact": subgate_15a_pass,
        "b_pe_32_routes_are_removed_while_the_default_route_stays": subgate_15b_pass,
        "c_bypass_pull_succeeds_while_acr_stays_pe_only": subgate_15c_pass,
        "d_h1_window_contains_zero_new_acr_firewall_rows": subgate_15d_pass,
        "e_workload_silence_holds_during_h1": subgate_15e_pass,
    },
    "scenario": "acr_network_path_pe_forced_inspection",
    "sub_gates": [
        {
            "claim": "The baseline pull window proves the firewall would emit ACR rows when the /32 routes are intact.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("06-firewall-log-baseline.json")],
            "observed_values": {
                "baseline_acr_fw_log_count": baseline_acr_fw_log_count,
                "baseline_fqdns": baseline_fqdns,
                "baseline_sources": baseline_sources,
                "baseline_window_start_utc": baseline_window_start,
                "baseline_window_end_utc": baseline_window_end,
                "rows_preview": baseline_rows[:10],
            },
            "predicate": "baseline_acr_fw_log_count > 0.",
            "result": "pass" if subgate_15a_pass else "fail",
            "sub_gate": "a_baseline_presence_proves_the_firewall_would_see_acr_when_routes_are_intact",
        },
        {
            "claim": "The pre-fix route table removed the PE /32 UDR routes while preserving the default firewall route.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("03-route-table-pre-fix.json")],
            "observed_values": {
                "default_route": default_route_pre,
                "pe_route_absence_details": pre_route_absence_details,
                "route_rows": route_pre,
            },
            "predicate": "default-via-afw remains present with 0.0.0.0/0, and no ${ip}/32 entry exists for any PE IP captured in 01.capture_metadata.pe_ip_map.",
            "result": "pass" if subgate_15b_pass else "fail",
            "sub_gate": "b_pe_32_routes_are_removed_while_the_default_route_stays",
        },
        {
            "claim": "The v-bypass pull succeeded while ACR stayed PE-only.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("05-acr-public-access-pre-fix.json"), repo_rel("08-h1-silence-window.json")],
            "observed_values": {
                "publicNetworkAccess": acr_pre.get("publicNetworkAccess"),
                "v_bypass_revision": pre_bypass_revision,
                "http_response": h1_payload.get("http_response"),
            },
            "predicate": "05.publicNetworkAccess == 'Disabled' AND the H1 revision/image tag is v-bypass AND the H1 / response reports build_tag=v-bypass while the revision healthState is Healthy.",
            "result": "pass" if subgate_15c_pass else "fail",
            "sub_gate": "c_bypass_pull_succeeds_while_acr_stays_pe_only",
        },
        {
            "claim": "The H1 broken window contains zero new Azure Firewall ACR rows.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("08-h1-silence-window.json")],
            "observed_values": {
                "h1_trigger_ts_utc": h1_trigger_ts_utc,
                "h1_window_acr_fw_log_count": h1_window_acr_fw_log_count,
                "h1_fqdns": h1_fqdns,
                "h1_sources": h1_sources,
                "rows_preview": h1_rows[:10],
            },
            "predicate": "h1_window_acr_fw_log_count == 0 for the firewall query anchored after h1_trigger_ts_utc.",
            "result": "pass" if subgate_15d_pass else "fail",
            "sub_gate": "d_h1_window_contains_zero_new_acr_firewall_rows",
        },
        {
            "claim": "The H1 window is silent at the workload surface: all revisions stayed Healthy and no ImagePullFailed or RevisionFailed events were recorded.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("08-h1-silence-window.json")],
            "observed_values": {
                "all_revisions_healthy_pre": all_revisions_healthy_pre,
                "h1_counts": pre_h1_counts,
                "revision_rows": revisions_pre,
            },
            "predicate": "all revisions in 02 are Healthy and the H1 payload records zero ImagePullFailed plus zero RevisionFailed while explicitly asserting all_revisions_healthy.",
            "result": "pass" if subgate_15e_pass else "fail",
            "sub_gate": "e_workload_silence_holds_during_h1",
        },
    ],
    "thresholds": {
        "baseline_presence_expected_min": 1,
        "h1_firewall_row_count_expected": 0,
        "expected_acr_public_network_access": "Disabled",
    },
    "utc_captured": UTC_NOW,
}

gate16 = {
    "claim": f"The H2 fix restored recovery on {app_name}: the exact PE /32 UDR routes were re-added, the latest active v-recover revision is Healthy, the H2 window contains new firewall ACR rows again, and ACR public access still reads Disabled while the bounded terminal-failure-silence invariant remains intact (zero ImagePullFailed and zero RevisionFailed, with any non-terminal ImagePullUnauthorized rows disclosed separately).",
    "claim_level": "Observed",
    "gate_classification": "H2 gate: confirms that re-adding the PE /32 UDR routes restores firewall visibility without changing pull success semantics.",
    "hypothesis": "H2_fix_restores_recovery",
    "path_used": "single",
    "predicate_inputs": {
        "route_table_post": repo_rel("09-route-table-post-fix.json"),
        "revision_list_post": repo_rel("10-revision-list-post-fix.json"),
        "app_spec_post": repo_rel("11-app-spec-post-fix.json"),
        "h2_recovery_window": repo_rel("12-h2-recovery-window.json"),
    },
    "acr_network_path_pe_forced_inspection_h2_fix_restores_recovery_all_subgates_pass": gate_16_all_subgates_pass,
    "acr_network_path_pe_forced_inspection_h2_fix_restores_recovery_sub_gates": {
        "a_exact_pe_32_routes_are_restored": subgate_16a_pass,
        "b_latest_active_v_recover_revision_is_healthy": subgate_16b_pass,
        "c_h2_window_contains_new_acr_firewall_rows_and_v_recover_response": subgate_16c_pass,
        "d_acr_stays_pe_only_and_workload_silence_remains_intact": subgate_16d_pass,
    },
    "scenario": "acr_network_path_pe_forced_inspection",
    "sub_gates": [
        {
            "claim": "The post-fix route table restored the exact PE /32 UDR routes with the firewall private IP as next hop.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("09-route-table-post-fix.json")],
            "observed_values": {
                "default_route": default_route_post,
                "pe_route_present_details": post_route_present_details,
                "route_rows": route_post,
            },
            "predicate": "default-via-afw remains present and every PE IP from 01.capture_metadata.pe_ip_map has an exact /32 VirtualAppliance route pointing to the captured firewall private IP.",
            "result": "pass" if subgate_16a_pass else "fail",
            "sub_gate": "a_exact_pe_32_routes_are_restored",
        },
        {
            "claim": "The latest active v-recover revision is Healthy.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("10-revision-list-post-fix.json")],
            "observed_values": {
                "post_latest_revision": post_latest_revision,
                "post_recover_revision": post_recover_revision,
            },
            "predicate": "A revision whose image tag is v-recover exists in 10, healthState == 'Healthy', active == true, and it is the latest revision in the list.",
            "result": "pass" if subgate_16b_pass else "fail",
            "sub_gate": "b_latest_active_v_recover_revision_is_healthy",
        },
        {
            "claim": "The H2 window contains new firewall ACR rows again and the workload serves v-recover.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("12-h2-recovery-window.json")],
            "observed_values": {
                "h2_recovery_ts_utc": h2_recovery_ts_utc,
                "h2_window_acr_fw_log_count": h2_window_acr_fw_log_count,
                "h2_fqdns": h2_fqdns,
                "h2_sources": h2_sources,
                "rows_preview": h2_rows[:10],
                "http_response": h2_payload.get("http_response"),
            },
            "predicate": "h2_window_acr_fw_log_count > 0 after h2_recovery_ts_utc and the H2 / response reports build_tag=v-recover.",
            "result": "pass" if subgate_16c_pass else "fail",
            "sub_gate": "c_h2_window_contains_new_acr_firewall_rows_and_v_recover_response",
        },
        {
            "claim": "ACR stays PE-only and the bounded terminal-failure-silence invariant still holds after recovery.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("11-app-spec-post-fix.json"), repo_rel("12-h2-recovery-window.json")],
            "observed_values": {
                "publicNetworkAccess": post_acr.get("publicNetworkAccess"),
                "all_revisions_healthy_post": all_revisions_healthy_post,
                "h2_counts": post_h2_counts,
            },
            "predicate": "11.acr.publicNetworkAccess == 'Disabled' and 12 records all_revisions_healthy plus zero ImagePullFailed and zero RevisionFailed while separately disclosing any ImagePullUnauthorized counts and 10 shows all revisions Healthy.",
            "result": "pass" if subgate_16d_pass else "fail",
            "sub_gate": "d_acr_stays_pe_only_and_workload_silence_remains_intact",
        },
    ],
    "thresholds": {
        "h2_firewall_row_count_expected_min": 1,
        "expected_acr_public_network_access": "Disabled",
    },
    "utc_captured": UTC_NOW,
}

gate17 = {
    "claim": "This evidence pack falsifies the Path C inspection assumption within a bounded scope. Silence-gate proof requires three non-vacuous observations together: baseline-presence (the firewall did see ACR when the /32 routes were intact), bypass-absence (the firewall saw zero ACR rows after the /32 routes were removed), and bounded workload silence (pulls still succeeded, revisions stayed Healthy throughout, and no terminal ImagePullFailed or RevisionFailed events surfaced). Recovery-presence then closes the loop by showing the firewall sees ACR again once the /32 routes return.",
    "claim_level": "Observed",
    "cohort_binding_note": {
        "claim_ceiling": "The bounded claim is that explicit /32 UDR routes for the captured PE NIC IPs are the mechanically observable trigger field controlling Azure Firewall visibility into this ACR Private Endpoint pull path. The pack does NOT prove exact pull durations, OCI layer digests, cache internals, pod continuity, replica suffix continuity, precise route-propagation timing, or the internal identity of the ACA workload-subnet component that emitted the pull.",
        "explicit_drops": explicit_drops,
    },
    "gate_classification": "Bounded falsification gate: isolates the PE /32 UDR routes as the trigger field while explicitly listing the silence-gate preconditions and unsupported inferences.",
    "hypothesis": "H3_bounded_falsification",
    "path_used": "bounded",
    "predicate_inputs": {
        "baseline_firewall_log": repo_rel("06-firewall-log-baseline.json"),
        "h1_silence_window": repo_rel("08-h1-silence-window.json"),
        "route_table_pre": repo_rel("03-route-table-pre-fix.json"),
        "route_table_post": repo_rel("09-route-table-post-fix.json"),
        "h2_recovery_window": repo_rel("12-h2-recovery-window.json"),
    },
    "acr_network_path_pe_forced_inspection_h3_bounded_falsification_all_subgates_pass": gate_17_all_subgates_pass,
    "acr_network_path_pe_forced_inspection_h3_bounded_falsification_sub_gates": {
        "a_bypass_absence_is_real_only_because_baseline_presence_was_proven": subgate_17a_pass,
        "b_recovery_presence_restores_firewall_visibility": subgate_17b_pass,
        "c_workload_silence_holds_throughout_with_zero_pull_failures": subgate_17c_pass,
        "d_only_the_documented_route_field_changes_and_the_claim_ceiling_is_static": subgate_17d_pass,
    },
    "scenario": "acr_network_path_pe_forced_inspection",
    "sub_gates": [
        {
            "claim": "The H1 bypass-absence claim is non-vacuous only because the baseline window already proved the firewall would see ACR traffic when the /32 routes were intact.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("06-firewall-log-baseline.json"), repo_rel("08-h1-silence-window.json")],
            "observed_values": {
                "baseline_acr_fw_log_count": baseline_acr_fw_log_count,
                "h1_window_acr_fw_log_count": h1_window_acr_fw_log_count,
                "baseline_window": {"start": baseline_window_start, "end": baseline_window_end},
                "h1_trigger_ts_utc": h1_trigger_ts_utc,
            },
            "predicate": "baseline_acr_fw_log_count > 0 AND h1_window_acr_fw_log_count == 0.",
            "result": "pass" if subgate_17a_pass else "fail",
            "sub_gate": "a_bypass_absence_is_real_only_because_baseline_presence_was_proven",
        },
        {
            "claim": "The H2 recovery window restores firewall visibility into ACR traffic.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("12-h2-recovery-window.json")],
            "observed_values": {
                "h2_window_acr_fw_log_count": h2_window_acr_fw_log_count,
                "h2_recovery_ts_utc": h2_recovery_ts_utc,
                "rows_preview": h2_rows[:10],
            },
            "predicate": "h2_window_acr_fw_log_count > 0.",
            "result": "pass" if subgate_17b_pass else "fail",
            "sub_gate": "b_recovery_presence_restores_firewall_visibility",
        },
        {
            "claim": "The lab is silent at the bounded terminal-failure surface: all revisions stayed Healthy throughout and zero ImagePullFailed / RevisionFailed events were recorded, while any non-terminal ImagePullUnauthorized rows are disclosed separately.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("08-h1-silence-window.json"), repo_rel("10-revision-list-post-fix.json"), repo_rel("12-h2-recovery-window.json")],
            "observed_values": {
                "all_revisions_healthy_throughout": all_revisions_healthy_throughout,
                "overall_zero_imagepull_failures": overall_zero_imagepull_failures,
                "overall_zero_revision_failures": overall_zero_revision_failures,
                "h1_counts": pre_h1_counts,
                "h2_counts": post_h2_counts,
            },
            "predicate": "all_revisions_healthy_throughout == true AND overall_zero_imagepull_failures == true AND overall_zero_revision_failures == true.",
            "result": "pass" if subgate_17c_pass else "fail",
            "sub_gate": "c_workload_silence_holds_throughout_with_zero_pull_failures",
        },
        {
            "claim": "Only the documented route-field overlap changes across H1 and H2, and the explicit claim ceiling stays static.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("03-route-table-pre-fix.json"), repo_rel("09-route-table-post-fix.json"), repo_rel("11-app-spec-post-fix.json")],
            "observed_values": {
                "held_constant_checks": held_constant_checks,
                "allowed_expected_diff_paths": sorted(allowed_expected_diff_paths),
                "overlap_diff_map": overlap_diff_map,
                "unexpected_overlap_diffs": unexpected_overlap_diffs,
                "runtime_drop_ids": sorted(runtime_drop_ids),
                "documented_drop_ids": sorted(DOCUMENTED_EXPLICIT_DROPS_CEILING),
            },
            "predicate": "All held_constant_checks compare equal, overlap diffs are limited to the documented route/revision/build-tag fields, and explicit_drops exactly match the documented static ceiling.",
            "result": "pass" if subgate_17d_pass else "fail",
            "sub_gate": "d_only_the_documented_route_field_changes_and_the_claim_ceiling_is_static",
        },
    ],
    "thresholds": {
        "baseline_presence_expected_min": 1,
        "h1_firewall_row_count_expected": 0,
        "h2_firewall_row_count_expected_min": 1,
    },
    "utc_captured": UTC_NOW,
}

for name, payload in [
    ("14-cohort-integrity-gate.json", gate14),
    ("15-h1-trigger-produces-failure-gate.json", gate15),
    ("16-h2-fix-restores-recovery-gate.json", gate16),
    ("17-bounded-falsification-gate.json", gate17),
]:
    (EVIDENCE_DIR / name).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

summary_lines = [
    f"[Gate 14/17] {'PASS' if gate_14_all_subgates_pass else 'FAIL'} cohort integrity gate written to {repo_rel('14-cohort-integrity-gate.json')}",
    f"[Gate 15/17] {'PASS' if gate_15_all_subgates_pass else 'FAIL'} H1 silence gate written to {repo_rel('15-h1-trigger-produces-failure-gate.json')}",
    f"[Gate 16/17] {'PASS' if gate_16_all_subgates_pass else 'FAIL'} H2 recovery gate written to {repo_rel('16-h2-fix-restores-recovery-gate.json')}",
    f"[Gate 17/17] {'PASS' if gate_17_all_subgates_pass else 'FAIL'} bounded falsification gate written to {repo_rel('17-bounded-falsification-gate.json')}",
]

if all([gate_14_all_subgates_pass, gate_15_all_subgates_pass, gate_16_all_subgates_pass, gate_17_all_subgates_pass]):
    print("\n".join(summary_lines))
    raise SystemExit(0)

print("\n".join(summary_lines))
raise SystemExit(1)
PY
)"; then
    printf '%s\n' "$PHASE_B_OUTPUT"
else
    printf '%s\n' "$PHASE_B_OUTPUT"
    exit 1
fi
