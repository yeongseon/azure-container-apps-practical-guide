#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/acr-network-path-pe-direct/evidence"
LAB_README_PATH="${SCRIPT_DIR}/README.md"
LAB_GUIDE_PATH="${SCRIPT_DIR}/../../docs/troubleshooting/lab-guides/acr-network-path-pe-direct.md"
UTC_NOW="${UTC_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR LAB_README_PATH LAB_GUIDE_PATH UTC_NOW

declare -a CANONICAL_RAW_FILES=(
    "01-app-spec-pre-fix.json"
    "02-revision-list-pre-fix.json"
    "03-private-dns-link-list-pre-fix.json"
    "04-pe-nic-config-pre-fix.json"
    "05-acr-public-access-pre-fix.json"
    "06-system-logs-pre-fix.json"
    "07-containerapp-spec-pre-fix.yaml"
    "08-kql-imagepull-events-pre-fix.json"
    "09-private-dns-link-list-post-fix.json"
    "10-revision-list-post-fix.json"
    "11-app-spec-post-fix.json"
    "12-kql-imagepull-events-post-fix.json"
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
    "03-private-dns-link-list-pre-fix.json",
    "04-pe-nic-config-pre-fix.json",
    "05-acr-public-access-pre-fix.json",
    "06-system-logs-pre-fix.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-kql-imagepull-events-pre-fix.json",
    "09-private-dns-link-list-post-fix.json",
    "10-revision-list-post-fix.json",
    "11-app-spec-post-fix.json",
    "12-kql-imagepull-events-post-fix.json",
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
        pre_app = load_json(evidence_dir / RAW_FILES[0])
    except Exception as exc:  # noqa: BLE001
        print(f"01 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    container_app = pre_app.get("container_app", {})
    ok = bool(container_app.get("name")) and bool(container_app.get("resourceGroup")) and bool(container_app.get("properties", {}).get("latestRevisionName"))
    if ok:
        print("01 parses and captures the pre-fix container app surface")
        raise SystemExit(0)
    print("01 missing expected pre-fix container app fields")
    raise SystemExit(1)

if gate_number == 6:
    try:
        revisions = load_json(evidence_dir / RAW_FILES[1])
        links = load_json(evidence_dir / RAW_FILES[2])
    except Exception as exc:  # noqa: BLE001
        print(f"02/03 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(revisions, list) and len(revisions) >= 1 and isinstance(links, list) and len(links) == 0
    if ok:
        print("02/03 parse and show revisions plus an empty pre-fix DNS-link list")
        raise SystemExit(0)
    print("02/03 do not match the expected revision-list + empty-link shape")
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
        rows = load_jsonl(evidence_dir / RAW_FILES[5])
    except Exception as exc:  # noqa: BLE001
        print(f"06 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    if rows:
        print(f"06 parses as JSONL with {len(rows)} rows")
        raise SystemExit(0)
    print("06 JSONL is empty")
    raise SystemExit(1)

if gate_number == 9:
    try:
        spec = load_yaml(evidence_dir / RAW_FILES[6])
    except Exception as exc:  # noqa: BLE001
        print(f"07 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ingress = spec.get("properties", {}).get("configuration", {}).get("ingress", {})
    ok = bool(spec.get("name")) and bool(spec.get("resourceGroup")) and int(ingress.get("targetPort", 0)) == 80
    if ok:
        print("07 parses as YAML and pins ingress targetPort 80")
        raise SystemExit(0)
    print("07 YAML does not match the expected container app shape")
    raise SystemExit(1)

if gate_number == 10:
    try:
        pre_kql = load_json(evidence_dir / RAW_FILES[7])
    except Exception as exc:  # noqa: BLE001
        print(f"08 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    rows = pre_kql.get("rows", pre_kql)
    ok = isinstance(rows, list) and len(rows) >= 1
    if ok:
        print(f"08 parses as JSON with {len(rows)} KQL rows")
        raise SystemExit(0)
    print("08 does not contain the expected KQL rows")
    raise SystemExit(1)

if gate_number == 11:
    try:
        post_links = load_json(evidence_dir / RAW_FILES[8])
    except Exception as exc:  # noqa: BLE001
        print(f"09 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(post_links, list) and len(post_links) == 1
    if ok:
        print("09 parses and captures the restored VNet-to-zone link")
        raise SystemExit(0)
    print("09 does not capture exactly one restored VNet-to-zone link")
    raise SystemExit(1)

if gate_number == 12:
    try:
        revisions_post = load_json(evidence_dir / RAW_FILES[9])
        app_post = load_json(evidence_dir / RAW_FILES[10])
        kql_post = load_json(evidence_dir / RAW_FILES[11])
    except Exception as exc:  # noqa: BLE001
        print(f"10-12 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    rows = kql_post.get("rows", kql_post)
    ok = isinstance(revisions_post, list) and len(revisions_post) >= 1 and bool(app_post.get("container_app", {}).get("name")) and isinstance(rows, list) and len(rows) >= 1
    if ok:
        print("10-12 parse and capture the post-fix revision, app surface, and KQL recovery rows")
        raise SystemExit(0)
    print("10-12 do not capture the expected post-fix revision / app / KQL surface")
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
    "6:pre-fix revision and empty DNS-link list parse" \
    "7:pre-fix PE NIC and ACR access parse" \
    "8:pre-fix system logs parse" \
    "9:pre-fix YAML spec parses" \
    "10:pre-fix KQL capture parses" \
    "11:post-fix DNS-link capture parses" \
    "12:post-fix revision/app/KQL captures parse" \
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
    "03-private-dns-link-list-pre-fix.json",
    "04-pe-nic-config-pre-fix.json",
    "05-acr-public-access-pre-fix.json",
    "06-system-logs-pre-fix.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-kql-imagepull-events-pre-fix.json",
    "09-private-dns-link-list-post-fix.json",
    "10-revision-list-post-fix.json",
    "11-app-spec-post-fix.json",
    "12-kql-imagepull-events-post-fix.json",
]
GATE_FILES = [
    "14-cohort-integrity-gate.json",
    "15-h1-trigger-produces-failure-gate.json",
    "16-h2-fix-restores-recovery-gate.json",
    "17-bounded-falsification-gate.json",
]
DOCUMENTED_EXPLICIT_DROPS_CEILING = frozenset([
    "backoff_retry_timestamps",
    "build_tag_env_value",
    "dns_resolution_timing",
    "image_layer_sha",
    "pod_uid",
    "pull_duration_milliseconds",
    "replica_name_suffix",
    "revision_name_suffix",
])
EXPECTED_EVIDENCE_FILES = RAW_FILES + GATE_FILES + ["README.md"]
JUNK_NAMES = {".DS_Store"}
REVISION_ID_RE = re.compile(r"^/subscriptions/(?P<sub>[^/]+)/resourceGroups/(?P<rg>[^/]+)/providers/Microsoft\.App/containerApps/(?P<app>[^/]+)/revisions/(?P<rev>[^/]+)$")


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


def load_json(name: str):
    return json.loads((EVIDENCE_DIR / name).read_text(encoding="utf-8"))


def load_jsonl(name: str):
    return [json.loads(line) for line in (EVIDENCE_DIR / name).read_text(encoding="utf-8").splitlines() if line.strip()]


def load_yaml(name: str):
    return yaml.safe_load((EVIDENCE_DIR / name).read_text(encoding="utf-8"))


def resolve_anchor_timestamp(name: str):
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


def parse_iso(text: str):
    value = datetime.fromisoformat(text.replace("Z", "+00:00"))
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def parse_revision_id(revision_id: str):
    match = REVISION_ID_RE.match(revision_id)
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


def get_rows(payload):
    if isinstance(payload, dict) and isinstance(payload.get("rows"), list):
        return payload["rows"]
    if isinstance(payload, list):
        return payload
    return []


def image_tag(image: str):
    return image.split(":")[-1] if ":" in image else image


def extract_env(container):
    return {item.get("name"): item.get("value") for item in container.get("env", [])}


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


def link_summary(link_rows):
    return [
        {
            "name": row.get("name"),
            "virtualNetworkId": row.get("virtualNetwork", {}).get("id"),
            "registrationEnabled": row.get("registrationEnabled"),
            "virtualNetworkLinkState": row.get("virtualNetworkLinkState"),
            "provisioningState": row.get("provisioningState"),
        }
        for row in link_rows
    ]


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


def log_reason(row):
    return row.get("Reason") or row.get("Reason_s") or ""


def log_message(row):
    return row.get("Log") or row.get("Log_s") or ""


def log_revision(row):
    return row.get("RevisionName") or row.get("RevisionName_s") or ""


def log_replica(row):
    return row.get("ReplicaName") or row.get("ReplicaName_s") or ""


pre_app_payload = load_json("01-app-spec-pre-fix.json")
revisions_pre = load_json("02-revision-list-pre-fix.json")
links_pre = load_json("03-private-dns-link-list-pre-fix.json")
pe_nic_pre = load_json("04-pe-nic-config-pre-fix.json")
acr_pre = load_json("05-acr-public-access-pre-fix.json")
system_pre = load_jsonl("06-system-logs-pre-fix.json")
spec_pre = load_yaml("07-containerapp-spec-pre-fix.yaml")
kql_pre_payload = load_json("08-kql-imagepull-events-pre-fix.json")
links_post = load_json("09-private-dns-link-list-post-fix.json")
revisions_post = load_json("10-revision-list-post-fix.json")
post_payload = load_json("11-app-spec-post-fix.json")
kql_post_payload = load_json("12-kql-imagepull-events-post-fix.json")

pre_app = pre_app_payload["container_app"]
post_app = post_payload["container_app"]
post_acr = post_payload["acr"]
pe_nic_post = post_payload["pe_nic"]

app_name = pre_app["name"]
resource_group = pre_app["resourceGroup"]
login_server = pre_app_payload["capture_metadata"]["acr_login_server"]
vnet_id = pre_app_payload["capture_metadata"]["vnet_id"]
zone_name = pre_app_payload["capture_metadata"]["zone_name"]

parse_errors = []
for name in [
    "01-app-spec-pre-fix.json",
    "02-revision-list-pre-fix.json",
    "03-private-dns-link-list-pre-fix.json",
    "04-pe-nic-config-pre-fix.json",
    "05-acr-public-access-pre-fix.json",
    "08-kql-imagepull-events-pre-fix.json",
    "09-private-dns-link-list-post-fix.json",
    "10-revision-list-post-fix.json",
    "11-app-spec-post-fix.json",
    "12-kql-imagepull-events-post-fix.json",
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

pre_rows = get_rows(kql_pre_payload)
post_rows = get_rows(kql_post_payload)
pre_window_start = kql_pre_payload.get("window_start_utc")
pre_window_end = kql_pre_payload.get("window_end_utc")
post_window_start = kql_post_payload.get("window_start_utc")
post_window_end = kql_post_payload.get("window_end_utc")

pre_anchor_infos = {name: resolve_anchor_timestamp(name) for name in RAW_FILES[:8]}
post_anchor_infos = {name: resolve_anchor_timestamp(name) for name in RAW_FILES[8:]}
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
strong_temporal = utc_window_span_seconds <= 1800
fallback_temporal = utc_window_span_seconds <= 5400
path_used = "strong" if strong_temporal else "fallback"

observed_files_on_disk = sorted(path.name for path in EVIDENCE_DIR.iterdir() if path.is_file())
non_junk_files = [name for name in observed_files_on_disk if name not in JUNK_NAMES]
unexpected_non_junk = [name for name in non_junk_files if name not in EXPECTED_EVIDENCE_FILES]
readme_text = (EVIDENCE_DIR / "README.md").read_text(encoding="utf-8")
expected_xrefs = GATE_FILES
observed_xrefs = [name for name in expected_xrefs if name in readme_text]

pre_broken_revision = find_revision_by_tag(revisions_pre, "v-broken")
post_recover_revision = find_revision_by_tag(revisions_post, "v-recover")
post_latest_revision = sorted(revisions_post, key=revision_sort_key, reverse=True)[0] if revisions_post else None

pre_revision_id = pre_broken_revision.get("id") if pre_broken_revision else ""
post_revision_id = post_recover_revision.get("id") if post_recover_revision else ""
pre_revision_parts = parse_revision_id(pre_revision_id) if pre_revision_id else {"resource_group": None, "container_app": None, "revision": None}
post_revision_parts = parse_revision_id(post_revision_id) if post_revision_id else {"resource_group": None, "container_app": None, "revision": None}
pre_parse_ok = pre_revision_parts.get("resource_group") is not None and pre_revision_parts.get("container_app") is not None
post_parse_ok = post_revision_parts.get("resource_group") is not None and post_revision_parts.get("container_app") is not None
both_parse_ok = pre_parse_ok and post_parse_ok
pre_post_rg_equal = both_parse_ok and pre_revision_parts["resource_group"] == post_revision_parts["resource_group"]
pre_post_app_equal = both_parse_ok and pre_revision_parts["container_app"] == post_revision_parts["container_app"]
pre_post_lineage_equal = both_parse_ok and pre_post_rg_equal and pre_post_app_equal

pre_nic_map = nic_ip_map(pe_nic_pre)
post_nic_map = nic_ip_map(pe_nic_post)
pe_nic_unchanged = pre_nic_map == post_nic_map

pre_link_summary = link_summary(links_pre)
post_link_summary = link_summary(links_post)
post_link_vnet_ids = sorted([item["virtualNetworkId"] for item in post_link_summary if item.get("virtualNetworkId")])

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
        "identity_type": pre_app.get("identity", {}).get("type"),
        "revision": {
            "latest_ready_revision_name": pre_app.get("properties", {}).get("latestReadyRevisionName"),
            "latest_revision_name": pre_app.get("properties", {}).get("latestRevisionName"),
            "target_image": pre_broken_revision.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("image") if pre_broken_revision else None,
            "target_revision_name": pre_broken_revision.get("name") if pre_broken_revision else None,
        },
        "container": {
            "name": pre_container.get("name"),
            "image": pre_container.get("image"),
            "cpu": pre_container.get("resources", {}).get("cpu"),
            "memory": pre_container.get("resources", {}).get("memory"),
            "build_tag": pre_env.get("BUILD_TAG"),
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
        "defaultAction": acr_pre.get("networkRuleSet", {}).get("defaultAction"),
    },
    "dns_link": {
        "count": len(pre_link_summary),
        "vnet_ids": sorted([item["virtualNetworkId"] for item in pre_link_summary if item.get("virtualNetworkId")]),
    },
    "pe_nic": pre_nic_map,
}

post_norm = {
    "container_app": {
        "name": post_app.get("name"),
        "resource_group": post_app.get("resourceGroup"),
        "identity_type": post_app.get("identity", {}).get("type"),
        "revision": {
            "latest_ready_revision_name": post_app.get("properties", {}).get("latestReadyRevisionName"),
            "latest_revision_name": post_app.get("properties", {}).get("latestRevisionName"),
            "target_image": post_recover_revision.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("image") if post_recover_revision else None,
            "target_revision_name": post_recover_revision.get("name") if post_recover_revision else None,
        },
        "container": {
            "name": post_container.get("name"),
            "image": post_container.get("image"),
            "cpu": post_container.get("resources", {}).get("cpu"),
            "memory": post_container.get("resources", {}).get("memory"),
            "build_tag": post_env.get("BUILD_TAG"),
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
        "defaultAction": post_acr.get("networkRuleSet", {}).get("defaultAction"),
    },
    "dns_link": {
        "count": len(post_link_summary),
        "vnet_ids": post_link_vnet_ids,
    },
    "pe_nic": post_nic_map,
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
    "container_app.container.build_tag",
    "container_app.container.image",
    "container_app.revision.latest_ready_revision_name",
    "container_app.revision.latest_revision_name",
    "container_app.revision.target_image",
    "container_app.revision.target_revision_name",
    "dns_link.count",
    "dns_link.vnet_ids[0]",
}
unexpected_overlap_diffs = {
    path: value for path, value in overlap_diff_map.items()
    if path not in allowed_expected_diff_paths
}

pre_failure_reasons = [row for row in system_pre if log_reason(row) in {"PullingImage", "ImagePullUnauthorized", "ImagePullFailed", "BackOff", "PulledImage"}]
pre_unauthorized_rows = [row for row in pre_failure_reasons if log_reason(row) == "ImagePullUnauthorized"]
pre_backoff_rows = [row for row in pre_failure_reasons if log_reason(row) == "BackOff"]
pre_broken_rows = [row for row in pre_failure_reasons if "v-broken" in log_message(row)]
post_recovery_rows = [row for row in post_rows if "v-recover" in json.dumps(row)]
post_pulling_rows = [row for row in post_recovery_rows if log_reason(row) == "PullingImage"]
post_pulled_rows = [row for row in post_recovery_rows if log_reason(row) == "PulledImage"]

pre_kql_unauthorized_rows = [row for row in pre_rows if log_reason(row) == "ImagePullUnauthorized"]
pre_kql_broken_rows = [row for row in pre_rows if "v-broken" in json.dumps(row)]

failed_replica_counts = {}
for row in [*pre_unauthorized_rows, *pre_kql_unauthorized_rows]:
    replica_name = log_replica(row)
    if not replica_name:
        continue
    failed_replica_counts[replica_name] = failed_replica_counts.get(replica_name, 0) + 1
pre_failed_replica_loop = any(count >= 2 for count in failed_replica_counts.values())

pre_failure_correlated = bool(pre_unauthorized_rows or pre_kql_unauthorized_rows) and bool(pre_broken_rows or pre_kql_broken_rows)
pre_unhealthy_revision = None
for row in revisions_pre:
    props = row.get("properties", {})
    containers = props.get("template", {}).get("containers", [])
    image = containers[0].get("image", "") if containers else ""
    if image.endswith(":v-broken") and (
        props.get("healthState") == "Unhealthy"
        or props.get("runningState") in {"Failed", "NotRunning", "Degraded"}
        or props.get("provisioningState") in {"Failed", "ProvisioningFailed"}
    ):
        pre_unhealthy_revision = row
        break

post_recover_props = post_recover_revision.get("properties", {}) if post_recover_revision else {}
pre_broken_props = pre_broken_revision.get("properties", {}) if pre_broken_revision else {}
post_latest_props = post_latest_revision.get("properties", {}) if post_latest_revision else {}

h1_trigger_outcome = "trigger_produced_failure" if (pre_failure_correlated and (pre_unhealthy_revision is not None or pre_failed_replica_loop)) else "trigger_did_not_force_failure"

held_constant_checks = {
    "acr_public_network_access_disabled": {
        "pre_value": acr_pre.get("publicNetworkAccess"),
        "post_value": post_acr.get("publicNetworkAccess"),
        "equal": acr_pre.get("publicNetworkAccess") == post_acr.get("publicNetworkAccess") == "Disabled",
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
    "identity_type": {
        "pre_value": pre_app.get("identity", {}).get("type"),
        "post_value": post_app.get("identity", {}).get("type"),
        "equal": pre_app.get("identity", {}).get("type") == post_app.get("identity", {}).get("type"),
    },
    "container_name": {
        "pre_value": pre_container.get("name"),
        "post_value": post_container.get("name"),
        "equal": pre_container.get("name") == post_container.get("name"),
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
    "pe_nic_ip_map": {
        "pre_value": pre_nic_map,
        "post_value": post_nic_map,
        "equal": pe_nic_unchanged,
    },
}

explicit_drops = [
    {
        "id": "backoff_retry_timestamps",
        "note": "BackOff retry cadence is platform jitter, not the variable under test.",
    },
    {
        "id": "build_tag_env_value",
        "note": "BUILD_TAG changes on purpose to force a fresh pull and must not be treated as a held-constant field.",
    },
    {
        "id": "dns_resolution_timing",
        "note": "The pack proves link presence versus absence, not the exact resolver-latency delta for each lookup.",
    },
    {
        "id": "image_layer_sha",
        "note": "The raw cohort captures image tags, not immutable OCI layer digests.",
    },
    {
        "id": "pod_uid",
        "note": "The cohort proves revision-level pull behavior, not Kubernetes pod UID continuity.",
    },
    {
        "id": "pull_duration_milliseconds",
        "note": "Pull durations vary naturally across retries and are not the causal field under test.",
    },
    {
        "id": "replica_name_suffix",
        "note": "Replica suffixes are scheduler-generated and expected to differ across retries.",
    },
    {
        "id": "revision_name_suffix",
        "note": "Revision names change by design when a new image is deployed and are checked separately as a fresh-pull marker.",
    },
]
runtime_drop_ids = frozenset(item["id"] for item in explicit_drops)

subgate_14a_pass = not parse_errors
subgate_14b_pass = monotonic_ordering_holds and (strong_temporal or fallback_temporal)
subgate_14c_pass = both_parse_ok and pre_post_lineage_equal
subgate_14d_pass = pe_nic_unchanged and not unexpected_non_junk and observed_xrefs == expected_xrefs
gate_14_all_subgates_pass = all([subgate_14a_pass, subgate_14b_pass, subgate_14c_pass, subgate_14d_pass])

subgate_15a_pass = len(links_pre) == 0
subgate_15b_pass = acr_pre.get("publicNetworkAccess") == "Disabled"
subgate_15c_pass = pre_failure_correlated
subgate_15d_pass = pre_unhealthy_revision is not None or pre_failed_replica_loop
gate_15_all_subgates_pass = all([subgate_15a_pass, subgate_15b_pass, subgate_15c_pass, subgate_15d_pass])

subgate_16a_pass = len(post_link_summary) == 1 and post_link_vnet_ids == [vnet_id]
subgate_16b_pass = post_recover_revision is not None and post_recover_props.get("healthState") == "Healthy" and post_recover_props.get("active") is True and post_latest_revision and post_latest_revision.get("name") == post_recover_revision.get("name")
subgate_16c_pass = bool(post_pulling_rows) and bool(post_pulled_rows)
subgate_16d_pass = post_acr.get("publicNetworkAccess") == "Disabled"
gate_16_all_subgates_pass = all([subgate_16a_pass, subgate_16b_pass, subgate_16c_pass, subgate_16d_pass])

subgate_17a_pass = acr_pre.get("publicNetworkAccess") == "Disabled" and post_acr.get("publicNetworkAccess") == "Disabled" and pre_nic_map == post_nic_map and pre_post_lineage_equal
subgate_17b_pass = (
    pre_norm["dns_link"]["count"] == 0
    and post_norm["dns_link"]["count"] == 1
    and post_link_vnet_ids == [vnet_id]
    and pre_broken_revision is not None
    and post_recover_revision is not None
    and pre_broken_revision.get("name") != post_recover_revision.get("name")
    and image_tag(pre_broken_revision.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("image", "")) == "v-broken"
    and image_tag(post_recover_revision.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("image", "")) == "v-recover"
    and not unexpected_overlap_diffs
)
subgate_17c_pass = runtime_drop_ids == DOCUMENTED_EXPLICIT_DROPS_CEILING
subgate_17d_pass = all(item["equal"] for item in held_constant_checks.values()) and h1_trigger_outcome == "trigger_produced_failure"
gate_17_all_subgates_pass = all([subgate_17a_pass, subgate_17b_pass, subgate_17c_pass, subgate_17d_pass])

gate14 = {
    "claim": f"The 12-file acr-network-path-pe-direct raw cohort is internally consistent: every canonical file is present and parseable, every per-file UTC anchor falls within one bounded capture window, the pre/post revision IDs parse to the same {resource_group} / {app_name} lineage, and the PE NIC IP map stays unchanged across H1 and H2.",
    "claim_level": "Observed",
    "gate_classification": "Cohort integrity gate: structural pre-condition for the bounded-falsification pack.",
    "hypothesis": "H_cohort_integrity",
    "path_used": path_used,
    "predicate_inputs": {
        "app_spec_pre": repo_rel("01-app-spec-pre-fix.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
        "pe_nic_pre": repo_rel("04-pe-nic-config-pre-fix.json"),
        "app_spec_post": repo_rel("11-app-spec-post-fix.json"),
        "evidence_readme": repo_rel("README.md"),
    },
    "acr_network_path_pe_direct_h_cohort_integrity_all_subgates_pass": gate_14_all_subgates_pass,
    "acr_network_path_pe_direct_h_cohort_integrity_sub_gates": {
        "a_canonical_raw_files_present_and_parse": subgate_14a_pass,
        "b_every_per_file_utc_anchor_falls_within_one_bounded_window": subgate_14b_pass,
        "c_revision_id_lineage_parses_and_compares_equal": subgate_14c_pass,
        "d_pe_nic_ip_map_is_unchanged_and_readme_xrefs_exist": subgate_14d_pass,
    },
    "scenario": "acr_network_path_pe_direct",
    "sub_gates": [
        {
            "claim": "All 12 canonical raw evidence files exist and parse as JSON, YAML, or JSONL.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel(name) for name in RAW_FILES],
            "observed_values": {
                "observed_missing": [name for name in RAW_FILES if not (EVIDENCE_DIR / name).is_file()],
                "observed_present_count": sum((EVIDENCE_DIR / name).is_file() for name in RAW_FILES),
                "parse_errors": parse_errors,
                "strong": {"expected_count": 12, "holds": not parse_errors},
                "fallback": {"expected_count": 12, "holds": not parse_errors},
            },
            "predicate": "Strong and fallback both require the full 12-file raw cohort to exist; 01,02,03,04,05,08,09,10,11,12 parse as JSON; 07 parses as YAML; 06 parses as JSONL.",
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
            "claim": "The broken v-broken revision and recovered v-recover revision parse to the same resource-group/container-app lineage.",
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
            "predicate": "The v-broken revision ID in 02 and the v-recover revision ID in 10 both match the /subscriptions/.../resourceGroups/.../containerApps/.../revisions/... regex, and the parsed resourceGroup + containerApp components compare equal only when both parses succeed.",
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
    "claim": f"The H1 trigger produced the documented failure surface on {app_name}: the pre-fix DNS-link list is empty, ACR publicNetworkAccess stayed Disabled, the failure window contains ImagePullUnauthorized evidence for v-broken, and the forced fresh pull surfaced either a failing v-broken revision state or a repeated named-replica ImagePullUnauthorized loop. If the fresh pull did not fail, this gate stays failed with h1_trigger_outcome=trigger_did_not_force_failure.",
    "claim_level": "Observed",
    "gate_classification": "H1 gate: confirms that removing the VNet-to-privatelink.azurecr.io link forced a fresh-pull failure without opening ACR public access.",
    "hypothesis": "H1_trigger_produces_failure",
    "path_used": "single",
    "predicate_inputs": {
        "dns_links_pre": repo_rel("03-private-dns-link-list-pre-fix.json"),
        "acr_public_access_pre": repo_rel("05-acr-public-access-pre-fix.json"),
        "system_logs_pre": repo_rel("06-system-logs-pre-fix.json"),
        "kql_pre": repo_rel("08-kql-imagepull-events-pre-fix.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
    },
    "acr_network_path_pe_direct_h1_trigger_produces_failure_all_subgates_pass": gate_15_all_subgates_pass,
    "acr_network_path_pe_direct_h1_trigger_produces_failure_sub_gates": {
        "a_pre_fix_dns_link_list_is_empty": subgate_15a_pass,
        "b_acr_public_network_access_stays_disabled": subgate_15b_pass,
        "c_failure_window_contains_imagepullunauthorized_for_v_broken": subgate_15c_pass,
        "d_at_least_one_v_broken_revision_is_unhealthy_or_a_named_replica_enters_the_failure_loop": subgate_15d_pass,
    },
    "scenario": "acr_network_path_pe_direct",
    "h1_trigger_outcome": h1_trigger_outcome,
    "sub_gates": [
        {
            "claim": "The pre-fix DNS-link list is empty after the VNet link was removed.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("03-private-dns-link-list-pre-fix.json")],
            "observed_values": {
                "link_count": len(pre_link_summary),
                "links": pre_link_summary,
            },
            "predicate": "len(03) == 0.",
            "result": "pass" if subgate_15a_pass else "fail",
            "sub_gate": "a_pre_fix_dns_link_list_is_empty",
        },
        {
            "claim": "ACR publicNetworkAccess remains Disabled during the broken pull window.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("05-acr-public-access-pre-fix.json")],
            "observed_values": {
                "publicNetworkAccess": acr_pre.get("publicNetworkAccess"),
                "defaultAction": acr_pre.get("networkRuleSet", {}).get("defaultAction"),
            },
            "predicate": "05.publicNetworkAccess == 'Disabled'.",
            "result": "pass" if subgate_15b_pass else "fail",
            "sub_gate": "b_acr_public_network_access_stays_disabled",
        },
        {
            "claim": "The broken window contains ImagePullUnauthorized evidence correlated with the v-broken pull attempt.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("06-system-logs-pre-fix.json"), repo_rel("08-kql-imagepull-events-pre-fix.json")],
            "observed_values": {
                "pre_system_imagepullunauthorized_rows": pre_unauthorized_rows[:5],
                "pre_system_v_broken_rows": pre_broken_rows[:5],
                "pre_kql_imagepullunauthorized_rows": pre_kql_unauthorized_rows[:5],
                "pre_kql_v_broken_rows": pre_kql_broken_rows[:5],
                "pre_kql_window_start_utc": pre_window_start,
                "pre_kql_window_end_utc": pre_window_end,
            },
            "predicate": "At least one 06 or 08 row has Reason/ImagePullUnauthorized and at least one 06 or 08 row in the same broken window references v-broken.",
            "result": "pass" if subgate_15c_pass else "fail",
            "sub_gate": "c_failure_window_contains_imagepullunauthorized_for_v_broken",
        },
        {
            "claim": "At least one v-broken revision becomes unhealthy or a named v-broken replica enters the repeated ImagePullUnauthorized failure loop after the forced fresh pull attempt.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("06-system-logs-pre-fix.json"), repo_rel("08-kql-imagepull-events-pre-fix.json")],
            "observed_values": {
                "h1_trigger_outcome": h1_trigger_outcome,
                "failed_replica_counts": failed_replica_counts,
                "pre_failed_replica_loop": pre_failed_replica_loop,
                "matching_unhealthy_revision": pre_unhealthy_revision,
                "v_broken_revision": pre_broken_revision,
            },
            "predicate": "Either 02 contains a revision whose image endswith ':v-broken' and whose healthState == 'Unhealthy' OR runningState in {'Failed','NotRunning','Degraded'} OR provisioningState in {'Failed','ProvisioningFailed'}, OR the 06/08 unauthorized rows show the same named replica at least twice in the v-broken failure loop; otherwise the gate fails with h1_trigger_outcome='trigger_did_not_force_failure'.",
            "result": "pass" if subgate_15d_pass else "fail",
            "sub_gate": "d_at_least_one_v_broken_revision_is_unhealthy_or_a_named_replica_enters_the_failure_loop",
        },
    ],
    "thresholds": {
        "expected_acr_public_network_access": "Disabled",
        "expected_pre_fix_link_count": 0,
    },
    "utc_captured": UTC_NOW,
}

gate16 = {
    "claim": f"The H2 fix restored recovery on {app_name}: exactly one VNet link to {zone_name} is present again, the latest active v-recover revision is Healthy, the post-fix KQL window contains both PullingImage and PulledImage for v-recover, and ACR publicNetworkAccess still reads Disabled after the recovery. The fix is therefore the DNS-link restore, not public exposure of ACR.",
    "claim_level": "Observed",
    "gate_classification": "H2 gate: confirms recovery after restoring the VNet-to-privatelink.azurecr.io link and deploying v-recover.",
    "hypothesis": "H2_fix_restores_recovery",
    "path_used": "single",
    "predicate_inputs": {
        "dns_links_post": repo_rel("09-private-dns-link-list-post-fix.json"),
        "revision_list_post": repo_rel("10-revision-list-post-fix.json"),
        "app_spec_post": repo_rel("11-app-spec-post-fix.json"),
        "kql_post": repo_rel("12-kql-imagepull-events-post-fix.json"),
    },
    "acr_network_path_pe_direct_h2_fix_restores_recovery_all_subgates_pass": gate_16_all_subgates_pass,
    "acr_network_path_pe_direct_h2_fix_restores_recovery_sub_gates": {
        "a_exactly_one_vnet_link_points_to_the_lab_vnet": subgate_16a_pass,
        "b_latest_active_v_recover_revision_is_healthy": subgate_16b_pass,
        "c_post_fix_kql_contains_pullingimage_and_pulledimage_for_v_recover": subgate_16c_pass,
        "d_acr_public_network_access_stays_disabled_post_fix": subgate_16d_pass,
    },
    "scenario": "acr_network_path_pe_direct",
    "sub_gates": [
        {
            "claim": "Exactly one restored VNet link points to the lab VNet.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("09-private-dns-link-list-post-fix.json")],
            "observed_values": {
                "link_count": len(post_link_summary),
                "links": post_link_summary,
                "expected_vnet_id": vnet_id,
            },
            "predicate": "len(09) == 1 AND 09[0].virtualNetwork.id == the VNet ID captured in 01.capture_metadata.vnet_id.",
            "result": "pass" if subgate_16a_pass else "fail",
            "sub_gate": "a_exactly_one_vnet_link_points_to_the_lab_vnet",
        },
        {
            "claim": "The latest recovered v-recover revision is Healthy and active after the link is restored.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("10-revision-list-post-fix.json")],
            "observed_values": {
                "post_latest_revision": post_latest_revision,
                "post_recover_revision": post_recover_revision,
            },
            "predicate": "10 contains a revision whose image endswith ':v-recover', that revision has healthState == 'Healthy' and active == true, and that same revision is the latest revision in the post-fix capture.",
            "result": "pass" if subgate_16b_pass else "fail",
            "sub_gate": "b_latest_active_v_recover_revision_is_healthy",
        },
        {
            "claim": "The post-fix KQL window contains both PullingImage and PulledImage for v-recover.",
            "claim_level": "Measured",
            "evidence_files": [repo_rel("12-kql-imagepull-events-post-fix.json")],
            "observed_values": {
                "post_kql_window_start_utc": post_window_start,
                "post_kql_window_end_utc": post_window_end,
                "post_pulling_rows": post_pulling_rows[:5],
                "post_pulled_rows": post_pulled_rows[:5],
            },
            "predicate": "12 contains at least one row that references v-recover with Reason/PullingImage and at least one row that references v-recover with Reason/PulledImage.",
            "result": "pass" if subgate_16c_pass else "fail",
            "sub_gate": "c_post_fix_kql_contains_pullingimage_and_pulledimage_for_v_recover",
        },
        {
            "claim": "ACR publicNetworkAccess stays Disabled after the recovery, so the fix was not reopening the public path.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("11-app-spec-post-fix.json")],
            "observed_values": {
                "post_fix_publicNetworkAccess": post_acr.get("publicNetworkAccess"),
                "post_fix_defaultAction": post_acr.get("networkRuleSet", {}).get("defaultAction"),
            },
            "predicate": "11.acr.publicNetworkAccess == 'Disabled'.",
            "result": "pass" if subgate_16d_pass else "fail",
            "sub_gate": "d_acr_public_network_access_stays_disabled_post_fix",
        },
    ],
    "thresholds": {
        "expected_post_fix_link_count": 1,
        "expected_post_fix_public_network_access": "Disabled",
    },
    "utc_captured": UTC_NOW,
}

gate17 = {
    "claim": "This evidence pack falsifies the ACR Private Endpoint direct-path failure hypothesis within a bounded scope. Gate 17 demonstrates that the VNet-to-privatelink.azurecr.io link is the mechanically observable trigger field for this cohort: ACR public access stays Disabled on both sides, the PE NIC IP map stays constant, the same container-app lineage is preserved, the link count changes from 0 to 1 on the same VNet, and the image moves from v-broken to v-recover on a new revision. The pack does not claim exact retry timing, exact pull durations, layer SHA identity, pod UID continuity, replica suffix continuity, BUILD_TAG continuity, or revision suffix identity.",
    "claim_level": "Observed",
    "cohort_binding_note": {
        "claim_ceiling": "The bounded claim is that the VNet-to-privatelink.azurecr.io link is the mechanically observable trigger field for this single koreacentral cohort. The pack proves the broken window only when the link count is 0 while ACR public access remains Disabled, and proves recovery when the same VNet link count returns to 1 on the same PE topology with v-recover. The pack does NOT prove exact retry cadence, exact pull durations, layer SHA identity, pod UID continuity, replica suffix continuity, BUILD_TAG continuity, or revision suffix identity.",
        "explicit_drops": explicit_drops,
    },
    "gate_classification": "Bounded falsification gate: isolates the VNet-to-private-DNS link as the trigger while explicitly listing the unproven confounders and ceilings.",
    "hypothesis": "H3_bounded_falsification",
    "path_used": "bounded",
    "predicate_inputs": {
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
        "dns_links_pre": repo_rel("03-private-dns-link-list-pre-fix.json"),
        "dns_links_post": repo_rel("09-private-dns-link-list-post-fix.json"),
        "pe_nic_pre": repo_rel("04-pe-nic-config-pre-fix.json"),
        "revision_list_post": repo_rel("10-revision-list-post-fix.json"),
        "app_spec_post": repo_rel("11-app-spec-post-fix.json"),
    },
    "acr_network_path_pe_direct_h3_bounded_falsification_all_subgates_pass": gate_17_all_subgates_pass,
    "acr_network_path_pe_direct_h3_bounded_falsification_sub_gates": {
        "a_acr_public_access_and_pe_topology_stay_constant": subgate_17a_pass,
        "b_full_overlapping_h1_h2_diff_matches_the_bounded_trigger_story": subgate_17b_pass,
        "c_explicit_drops_match_the_documented_ceiling": subgate_17c_pass,
        "d_held_constant_fields_match_and_h1_really_failed": subgate_17d_pass,
    },
    "scenario": "acr_network_path_pe_direct",
    "sub_gates": [
        {
            "claim": "ACR public access, PE NIC topology, and container-app lineage stay constant across H1 and H2.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("04-pe-nic-config-pre-fix.json"), repo_rel("05-acr-public-access-pre-fix.json"), repo_rel("10-revision-list-post-fix.json"), repo_rel("11-app-spec-post-fix.json")],
            "observed_values": {
                "held_constant_checks": held_constant_checks,
                "pre_post_lineage_equal": pre_post_lineage_equal,
            },
            "predicate": "05.publicNetworkAccess == 'Disabled' AND 11.acr.publicNetworkAccess == 'Disabled' AND the normalized PE NIC ipConfigurations compare equal AND the parsed pre/post revision IDs compare equal on resourceGroup + containerApp.",
            "result": "pass" if subgate_17a_pass else "fail",
            "sub_gate": "a_acr_public_access_and_pe_topology_stay_constant",
        },
        {
            "claim": "The full overlapping H1↔H2 diff matches the bounded trigger story: the overlapping normalized surface changes only on the documented trigger/output paths, and the direct post-link evidence in 09 shows that the restored single link points back to the same VNet.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("01-app-spec-pre-fix.json"), repo_rel("03-private-dns-link-list-pre-fix.json"), repo_rel("09-private-dns-link-list-post-fix.json"), repo_rel("10-revision-list-post-fix.json"), repo_rel("11-app-spec-post-fix.json")],
            "observed_values": {
                "allowed_expected_diff_paths": sorted(allowed_expected_diff_paths),
                "full_overlap_diff": overlap_diff_map,
                "full_overlap_equal": overlap_same_map,
                "overlap_paths": overlap_paths,
                "unexpected_overlap_diffs": unexpected_overlap_diffs,
                "pre_link_count": pre_norm["dns_link"]["count"],
                "post_link_count": post_norm["dns_link"]["count"],
                "post_link_vnet_ids": post_link_vnet_ids,
                "pre_target_revision": pre_broken_revision.get("name") if pre_broken_revision else None,
                "post_target_revision": post_recover_revision.get("name") if post_recover_revision else None,
                "pre_target_image": pre_broken_revision.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("image") if pre_broken_revision else None,
                "post_target_image": post_recover_revision.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("image") if post_recover_revision else None,
            },
            "predicate": "Across the full normalized overlapping H1/H2 surface captured in 01/03/10/11, the only differing overlap paths are dns_link.count, latest revision names, target revision names, target images, and BUILD_TAG/image surfaces tied to the fresh pull; 09 separately shows that the restored single post-fix link points to the same VNet ID captured in 01. No other overlapping path may differ.",
            "result": "pass" if subgate_17b_pass else "fail",
            "sub_gate": "b_full_overlapping_h1_h2_diff_matches_the_bounded_trigger_story",
        },
        {
            "claim": "The bounded-falsification gate explicitly lists the documented ceilings and unsupported inferences.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("17-bounded-falsification-gate.json")],
            "observed_values": {
                "documented_ceiling_ids": sorted(DOCUMENTED_EXPLICIT_DROPS_CEILING),
                "observed_drop_ids": [item["id"] for item in explicit_drops],
            },
            "predicate": "cohort_binding_note.explicit_drops ids equal the static documented ceiling {backoff_retry_timestamps, build_tag_env_value, dns_resolution_timing, image_layer_sha, pod_uid, pull_duration_milliseconds, replica_name_suffix, revision_name_suffix} with no additions and no omissions.",
            "result": "pass" if subgate_17c_pass else "fail",
            "sub_gate": "c_explicit_drops_match_the_documented_ceiling",
        },
        {
            "claim": "The held-constant fields match and H1 really failed before H2 recovered.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("06-system-logs-pre-fix.json"), repo_rel("10-revision-list-post-fix.json"), repo_rel("11-app-spec-post-fix.json")],
            "observed_values": {
                "h1_trigger_outcome": h1_trigger_outcome,
                "held_constant_checks": held_constant_checks,
            },
            "predicate": "All held_constant_checks equal == true AND h1_trigger_outcome == 'trigger_produced_failure'.",
            "result": "pass" if subgate_17d_pass else "fail",
            "sub_gate": "d_held_constant_fields_match_and_h1_really_failed",
        },
    ],
    "thresholds": {
        "held_constant_field_count": len(held_constant_checks),
        "expected_post_fix_link_count": 1,
        "expected_pre_fix_link_count": 0,
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
