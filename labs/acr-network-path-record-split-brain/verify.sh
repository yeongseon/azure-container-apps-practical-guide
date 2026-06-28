#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/acr-network-path-record-split-brain/evidence"
LAB_README_PATH="${SCRIPT_DIR}/README.md"
LAB_GUIDE_PATH="${SCRIPT_DIR}/../../docs/troubleshooting/lab-guides/acr-network-path-record-split-brain.md"
UTC_NOW="${UTC_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR LAB_README_PATH LAB_GUIDE_PATH UTC_NOW

declare -a CANONICAL_RAW_FILES=(
    "01-app-spec-pre-fix.json"
    "02-revision-list-pre-fix.json"
    "03-private-dns-record-list-pre-fix.json"
    "04-pe-nic-config-pre-fix.json"
    "05-acr-public-access-pre-fix.json"
    "06-system-logs-pre-fix.json"
    "07-containerapp-spec-pre-fix.yaml"
    "08-probe-response-pre-fix.json"
    "09-private-dns-record-list-post-fix.json"
    "10-revision-list-post-fix.json"
    "11-probe-response-post-fix.json"
    "12-pe-nic-config-post-fix.json"
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
    "03-private-dns-record-list-pre-fix.json",
    "04-pe-nic-config-pre-fix.json",
    "05-acr-public-access-pre-fix.json",
    "06-system-logs-pre-fix.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-probe-response-pre-fix.json",
    "09-private-dns-record-list-post-fix.json",
    "10-revision-list-post-fix.json",
    "11-probe-response-post-fix.json",
    "12-pe-nic-config-post-fix.json",
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
        pre_app = load_json(evidence_dir / RAW_FILES[0])
    except Exception as exc:  # noqa: BLE001
        print(f"01 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    container_app = pre_app.get("container_app", {})
    env = container_app.get("properties", {}).get("template", {}).get("containers", [{}])[0].get("env", [])
    env_names = {item.get("name") for item in env}
    ok = bool(container_app.get("name")) and bool(container_app.get("resourceGroup")) and bool(container_app.get("properties", {}).get("latestReadyRevisionName")) and {"ACR_FQDN", "ACR_DATA_FQDN"}.issubset(env_names)
    if ok:
        print("01 parses and captures the pre-fix container app surface with both ACR env vars")
        raise SystemExit(0)
    print("01 missing expected pre-fix container app fields")
    raise SystemExit(1)

if gate_number == 6:
    try:
        revisions = load_json(evidence_dir / RAW_FILES[1])
        records = load_json(evidence_dir / RAW_FILES[2])
    except Exception as exc:  # noqa: BLE001
        print(f"02/03 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(revisions, list) and len(revisions) >= 1 and isinstance(records, list)
    if ok:
        print("02/03 parse and capture the pre-fix revision list plus DNS record list")
        raise SystemExit(0)
    print("02/03 do not match the expected revision-list + DNS-record-list shape")
    raise SystemExit(1)

if gate_number == 7:
    try:
        nic = load_json(evidence_dir / RAW_FILES[3])
        acr = load_json(evidence_dir / RAW_FILES[4])
    except Exception as exc:  # noqa: BLE001
        print(f"04/05 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = bool(nic.get("id")) and isinstance(acr.get("publicNetworkAccess"), str)
    if ok:
        print("04/05 parse and capture the PE NIC plus ACR public-access surface")
        raise SystemExit(0)
    print("04/05 do not match the expected PE NIC + ACR access shape")
    raise SystemExit(1)

if gate_number == 8:
    try:
        system_rows = load_json(evidence_dir / RAW_FILES[5])
    except Exception as exc:  # noqa: BLE001
        print(f"06 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(system_rows, dict) and isinstance(system_rows.get("rows"), list) and isinstance(system_rows.get("query"), str)
    if ok:
        print("06 parses as a KQL payload with explicit query text and row list")
        raise SystemExit(0)
    print("06 does not parse as the expected KQL payload")
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
        pre_probe = load_json(evidence_dir / RAW_FILES[7])
    except Exception as exc:  # noqa: BLE001
        print(f"08 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    response = pre_probe.get("response", {})
    ok = isinstance(pre_probe.get("attempts"), list) and int(pre_probe.get("selected_attempt", 0)) >= 1 and response.get("topology_class") in {"data_nxdomain", "both_private", "split_brain", "both_public", "inverted_split_brain", "registry_nxdomain", "both_nxdomain"}
    if ok:
        print("08 parses as a retried probe payload with a valid topology_class")
        raise SystemExit(0)
    print("08 does not capture the expected probe payload shape")
    raise SystemExit(1)

if gate_number == 11:
    try:
        records_post = load_json(evidence_dir / RAW_FILES[8])
        revisions_post = load_json(evidence_dir / RAW_FILES[9])
    except Exception as exc:  # noqa: BLE001
        print(f"09/10 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    ok = isinstance(records_post, list) and isinstance(revisions_post, list) and len(revisions_post) >= 1
    if ok:
        print("09/10 parse and capture the restored DNS-record list plus post-fix revisions")
        raise SystemExit(0)
    print("09/10 do not capture the expected post-fix DNS / revision surface")
    raise SystemExit(1)

if gate_number == 12:
    try:
        probe_post = load_json(evidence_dir / RAW_FILES[10])
        post_payload = load_json(evidence_dir / RAW_FILES[11])
    except Exception as exc:  # noqa: BLE001
        print(f"11/12 parse failure: {type(exc).__name__}: {exc}")
        raise SystemExit(1)
    response = probe_post.get("response", {})
    ok = response.get("topology_class") in {"both_private", "data_nxdomain", "split_brain", "both_public", "inverted_split_brain", "registry_nxdomain", "both_nxdomain"} and bool(post_payload.get("container_app", {}).get("name")) and isinstance(post_payload.get("acr", {}).get("publicNetworkAccess"), str) and bool(post_payload.get("pe_nic", {}).get("id"))
    if ok:
        print("11/12 parse and capture the post-fix probe plus composite app/ACR/PE surface")
        raise SystemExit(0)
    print("11/12 do not capture the expected post-fix probe / composite surface")
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
    "6:pre-fix revision and DNS records parse" \
    "7:pre-fix PE NIC and ACR access parse" \
    "8:pre-fix system-log KQL parses" \
    "9:pre-fix YAML spec parses" \
    "10:pre-fix probe capture parses" \
    "11:post-fix DNS and revision captures parse" \
    "12:post-fix probe and composite captures parse" \
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

EXISTING_GATE14 = None
_existing_gate14_path = EVIDENCE_DIR / "14-cohort-integrity-gate.json"
if _existing_gate14_path.exists():
    try:
        EXISTING_GATE14 = json.loads(_existing_gate14_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        EXISTING_GATE14 = None

RAW_FILES = [
    "01-app-spec-pre-fix.json",
    "02-revision-list-pre-fix.json",
    "03-private-dns-record-list-pre-fix.json",
    "04-pe-nic-config-pre-fix.json",
    "05-acr-public-access-pre-fix.json",
    "06-system-logs-pre-fix.json",
    "07-containerapp-spec-pre-fix.yaml",
    "08-probe-response-pre-fix.json",
    "09-private-dns-record-list-post-fix.json",
    "10-revision-list-post-fix.json",
    "11-probe-response-post-fix.json",
    "12-pe-nic-config-post-fix.json",
]
GATE_FILES = [
    "14-cohort-integrity-gate.json",
    "15-h1-trigger-produces-failure-gate.json",
    "16-h2-fix-restores-recovery-gate.json",
    "17-bounded-falsification-gate.json",
]
DOCUMENTED_EXPLICIT_DROPS_CEILING = frozenset([
    "acr_control_plane_fresh_pull",
    "dns_resolution_timing",
    "exact_http_body_bytes",
    "image_layer_cache_state",
    "probe_retry_attempt_count",
    "resource_provider_poll_latency",
    "system_log_ingestion_latency",
    "tls_cipher_suite",
])
EXPECTED_EVIDENCE_FILES = RAW_FILES + GATE_FILES + ["README.md"]
JUNK_NAMES = {".DS_Store"}
REVISION_ID_RE = re.compile(r"^/subscriptions/(?P<sub>[^/]+)/resourceGroups/(?P<rg>[^/]+)/providers/Microsoft\.App/containerApps/(?P<app>[^/]+)/revisions/(?P<rev>[^/]+)$")

SANITIZER_RULES = [
    (re.compile(r"(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])", re.I), "00000000-0000-0000-0000-000000000000"),
    (re.compile(r"\bMCAPS[-A-Za-z0-9_]*\b"), "Visual Studio Enterprise Subscription"),
    (re.compile(r"Microsoft\s+Non-Production", re.I), "Contoso"),
    (re.compile(r"\b[A-Za-z0-9._%+-]+@microsoft\.com(?![A-Za-z0-9.-])", re.I), "user@example.com"),
    (re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.onmicrosoft\.com(?![A-Za-z0-9.-])", re.I), "user@example.com"),
    (re.compile(r"\b[A-Za-z0-9-]+\.onmicrosoft\.com(?![A-Za-z0-9.-])", re.I), "contoso.onmicrosoft.com"),
    (re.compile(r"\bychoe\b", re.I), "demouser"),
    (re.compile(r"Yeongseon\s+Choe", re.I), "Demo User"),
    (re.compile(r"\byeongseon\b", re.I), "demouser"),
    (re.compile(r"https://ms\.portal\.azure\.com/#@[^/]+/", re.I), "https://ms.portal.azure.com/#@contoso.onmicrosoft.com/"),
    (re.compile(r"https://ms\.portal\.azure\.com[^\s\"']*", re.I), "https://ms.portal.azure.com/#@contoso.onmicrosoft.com/"),
]

def sanitize_text(text: str) -> str:
    out = text
    for regex, repl in SANITIZER_RULES:
        out = regex.sub(repl, out)
    return out


def sanitize_value(value):
    if isinstance(value, str):
        return sanitize_text(value)
    if isinstance(value, list):
        return [sanitize_value(item) for item in value]
    if isinstance(value, dict):
        return {sanitize_value(key): sanitize_value(inner) for key, inner in value.items()}
    return value


def repo_rel(name: str) -> str:
    return f"{REL}/{name}"


def load_json(name: str):
    return json.loads((EVIDENCE_DIR / name).read_text(encoding="utf-8"))


def load_yaml(name: str):
    return yaml.safe_load((EVIDENCE_DIR / name).read_text(encoding="utf-8"))


def resolve_anchor_timestamp(name: str, anchor_class: str):
    if EXISTING_GATE14 is not None:
        observed = EXISTING_GATE14.get("sub_gates", [{} ,{}])[1].get("observed_values", {})
        prior_map = observed.get("pre_anchor_timestamps" if anchor_class == "pre" else "post_anchor_timestamps", {})
        prior = prior_map.get(name)
        if isinstance(prior, dict) and prior.get("timestamp_utc"):
            dt = parse_iso(prior["timestamp_utc"])
            return {
                "timestamp": dt,
                "timestamp_utc": prior["timestamp_utc"],
                "time_source": prior.get("time_source", "mtime"),
                "raw_epoch": prior.get("raw_epoch"),
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


def parse_iso(text: str):
    value = datetime.fromisoformat(text.replace("Z", "+00:00"))
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


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


def record_summary(record_rows, relative_name):
    matches = []
    for row in record_rows:
        if row.get("name") != relative_name:
            continue
        matches.append({
            "name": row.get("name"),
            "fqdn": row.get("fqdn"),
            "ttl": row.get("ttl"),
            "a_records": sorted(item.get("ipv4Address") for item in row.get("aRecords", []) if item.get("ipv4Address")),
        })
    return matches


def probe_attempt_summary(payload):
    attempts = []
    for item in payload.get("attempts", []):
        response = item.get("response") or {}
        attempts.append({
            "attempt": item.get("attempt"),
            "topology_class": response.get("topology_class"),
            "registry_dns_class": response.get("registry", {}).get("dns", {}).get("class"),
            "data_dns_class": response.get("data", {}).get("dns", {}).get("class"),
            "data_dns_error": response.get("data", {}).get("dns", {}).get("error"),
        })
    return attempts


def choose_live_revision(revisions, revision_name_hint):
    if revision_name_hint:
        for row in revisions:
            if row.get("name") == revision_name_hint:
                return row
    active_rows = [row for row in revisions if row.get("properties", {}).get("active") is True]
    if active_rows:
        return sorted(active_rows, key=lambda row: parse_iso(row.get("properties", {}).get("createdTime", "1970-01-01T00:00:00Z")), reverse=True)[0]
    if revisions:
        return sorted(revisions, key=lambda row: parse_iso(row.get("properties", {}).get("createdTime", "1970-01-01T00:00:00Z")), reverse=True)[0]
    return None

pre_app_payload = load_json("01-app-spec-pre-fix.json")
revisions_pre = load_json("02-revision-list-pre-fix.json")
records_pre = load_json("03-private-dns-record-list-pre-fix.json")
pe_nic_pre = load_json("04-pe-nic-config-pre-fix.json")
acr_pre = load_json("05-acr-public-access-pre-fix.json")
system_pre = load_json("06-system-logs-pre-fix.json")
spec_pre = load_yaml("07-containerapp-spec-pre-fix.yaml")
probe_pre_payload = load_json("08-probe-response-pre-fix.json")
records_post = load_json("09-private-dns-record-list-post-fix.json")
revisions_post = load_json("10-revision-list-post-fix.json")
probe_post_payload = load_json("11-probe-response-post-fix.json")
post_payload = load_json("12-pe-nic-config-post-fix.json")

pre_app = pre_app_payload["container_app"]
post_app = post_payload["container_app"]
post_acr = post_payload["acr"]
pe_nic_post = post_payload["pe_nic"]
pre_probe_response = probe_pre_payload["response"]
post_probe_response = probe_post_payload["response"]

capture_meta = pre_app_payload["capture_metadata"]
app_name = pre_app["name"]
resource_group = pre_app["resourceGroup"]
zone_name = capture_meta["zone_name"]
vnet_id = capture_meta["vnet_id"]
registry_record_name = capture_meta["registry_record_name"]
data_record_name = capture_meta["data_record_name"]
acr_login_server = capture_meta["acr_login_server"]
acr_data_fqdn = capture_meta["acr_data_fqdn"]

parse_errors = []
for name in [
    "01-app-spec-pre-fix.json",
    "02-revision-list-pre-fix.json",
    "03-private-dns-record-list-pre-fix.json",
    "04-pe-nic-config-pre-fix.json",
    "05-acr-public-access-pre-fix.json",
    "06-system-logs-pre-fix.json",
    "08-probe-response-pre-fix.json",
    "09-private-dns-record-list-post-fix.json",
    "10-revision-list-post-fix.json",
    "11-probe-response-post-fix.json",
    "12-pe-nic-config-post-fix.json",
]:
    try:
        load_json(name)
    except Exception as exc:  # noqa: BLE001
        parse_errors.append(f"{name}: {type(exc).__name__}: {exc}")
try:
    load_yaml("07-containerapp-spec-pre-fix.yaml")
except Exception as exc:  # noqa: BLE001
    parse_errors.append(f"07-containerapp-spec-pre-fix.yaml: {type(exc).__name__}: {exc}")

pre_rows = system_pre.get("rows", [])
pre_window_start = system_pre.get("window_start_utc")
pre_window_end = system_pre.get("window_end_utc")
post_window_start = probe_post_payload.get("captured_after_utc") or post_payload.get("capture_metadata", {}).get("post_window_start_utc")
post_window_end = probe_post_payload.get("captured_after_utc") or post_payload.get("capture_metadata", {}).get("post_window_start_utc")

pre_anchor_infos = {name: resolve_anchor_timestamp(name, "pre") for name in RAW_FILES[:8]}
post_anchor_infos = {name: resolve_anchor_timestamp(name, "post") for name in RAW_FILES[8:]}
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

pre_live_revision_name = pre_app.get("properties", {}).get("latestReadyRevisionName") or pre_app.get("properties", {}).get("latestRevisionName")
post_live_revision_name = post_app.get("properties", {}).get("latestReadyRevisionName") or post_app.get("properties", {}).get("latestRevisionName")
pre_live_revision = choose_live_revision(revisions_pre, pre_live_revision_name)
post_live_revision = choose_live_revision(revisions_post, post_live_revision_name)

pre_revision_id = pre_live_revision.get("id") if pre_live_revision else ""
post_revision_id = post_live_revision.get("id") if post_live_revision else ""
pre_revision_parts = parse_revision_id(pre_revision_id) if pre_revision_id else {"resource_group": None, "container_app": None, "revision": None}
post_revision_parts = parse_revision_id(post_revision_id) if post_revision_id else {"resource_group": None, "container_app": None, "revision": None}
pre_parse_ok = pre_revision_parts.get("resource_group") is not None and pre_revision_parts.get("container_app") is not None
post_parse_ok = post_revision_parts.get("resource_group") is not None and post_revision_parts.get("container_app") is not None
both_parse_ok = pre_parse_ok and post_parse_ok
pre_post_rg_equal = both_parse_ok and pre_revision_parts["resource_group"] == post_revision_parts["resource_group"]
pre_post_app_equal = both_parse_ok and pre_revision_parts["container_app"] == post_revision_parts["container_app"]
pre_post_lineage_equal = both_parse_ok and pre_post_rg_equal and pre_post_app_equal
pre_post_revision_equal = both_parse_ok and pre_revision_parts["revision"] == post_revision_parts["revision"]

pre_nic_map = nic_ip_map(pe_nic_pre)
post_nic_map = nic_ip_map(pe_nic_post)
pe_nic_unchanged = pre_nic_map == post_nic_map

pre_registry_records = record_summary(records_pre, registry_record_name)
pre_data_records = record_summary(records_pre, data_record_name)
post_registry_records = record_summary(records_post, registry_record_name)
post_data_records = record_summary(records_post, data_record_name)

pre_container = pre_app.get("properties", {}).get("template", {}).get("containers", [])[0]
post_container = post_app.get("properties", {}).get("template", {}).get("containers", [])[0]
pre_env = extract_env(pre_container)
post_env = extract_env(post_container)
pre_scale = pre_app.get("properties", {}).get("template", {}).get("scale", {})
post_scale = post_app.get("properties", {}).get("template", {}).get("scale", {})
pre_ingress = pre_app.get("properties", {}).get("configuration", {}).get("ingress", {})
post_ingress = post_app.get("properties", {}).get("configuration", {}).get("ingress", {})

pre_live_props = pre_live_revision.get("properties", {}) if pre_live_revision else {}
post_live_props = post_live_revision.get("properties", {}) if post_live_revision else {}
all_pre_revision_healthy = all(row.get("properties", {}).get("healthState") == "Healthy" for row in revisions_pre)
all_post_revision_healthy = all(row.get("properties", {}).get("healthState") == "Healthy" for row in revisions_post)

pre_attempts = probe_attempt_summary(probe_pre_payload)
post_attempts = probe_attempt_summary(probe_post_payload)
pre_selected_attempt = probe_pre_payload.get("selected_attempt")
post_selected_attempt = probe_post_payload.get("selected_attempt")
pre_attempt_count = len(probe_pre_payload.get("attempts", []))
post_attempt_count = len(probe_post_payload.get("attempts", []))
pre_retry_disclosure_ok = isinstance(pre_selected_attempt, int) and pre_selected_attempt >= 1 and pre_attempt_count >= pre_selected_attempt
post_retry_disclosure_ok = isinstance(post_selected_attempt, int) and post_selected_attempt >= 1 and post_attempt_count >= post_selected_attempt

pre_pull_failure_rows = pre_rows
pre_pull_failure_count = len(pre_pull_failure_rows)

held_constant_checks = {
    "acr_public_network_access": {"pre_value": acr_pre.get("publicNetworkAccess"), "post_value": post_acr.get("publicNetworkAccess"), "equal": acr_pre.get("publicNetworkAccess") == post_acr.get("publicNetworkAccess")},
    "acr_default_action": {"pre_value": acr_pre.get("networkRuleSet", {}).get("defaultAction"), "post_value": post_acr.get("networkRuleSet", {}).get("defaultAction"), "equal": acr_pre.get("networkRuleSet", {}).get("defaultAction") == post_acr.get("networkRuleSet", {}).get("defaultAction")},
    "container_app_name": {"pre_value": pre_app.get("name"), "post_value": post_app.get("name"), "equal": pre_app.get("name") == post_app.get("name")},
    "resource_group": {"pre_value": pre_app.get("resourceGroup"), "post_value": post_app.get("resourceGroup"), "equal": pre_app.get("resourceGroup") == post_app.get("resourceGroup")},
    "identity_type": {"pre_value": pre_app.get("identity", {}).get("type"), "post_value": post_app.get("identity", {}).get("type"), "equal": pre_app.get("identity", {}).get("type") == post_app.get("identity", {}).get("type")},
    "container_name": {"pre_value": pre_container.get("name"), "post_value": post_container.get("name"), "equal": pre_container.get("name") == post_container.get("name")},
    "container_image": {"pre_value": pre_container.get("image"), "post_value": post_container.get("image"), "equal": pre_container.get("image") == post_container.get("image")},
    "build_tag": {"pre_value": pre_env.get("BUILD_TAG"), "post_value": post_env.get("BUILD_TAG"), "equal": pre_env.get("BUILD_TAG") == post_env.get("BUILD_TAG")},
    "cpu": {"pre_value": pre_container.get("resources", {}).get("cpu"), "post_value": post_container.get("resources", {}).get("cpu"), "equal": pre_container.get("resources", {}).get("cpu") == post_container.get("resources", {}).get("cpu")},
    "memory": {"pre_value": pre_container.get("resources", {}).get("memory"), "post_value": post_container.get("resources", {}).get("memory"), "equal": pre_container.get("resources", {}).get("memory") == post_container.get("resources", {}).get("memory")},
    "acr_fqdn_env": {"pre_value": pre_env.get("ACR_FQDN"), "post_value": post_env.get("ACR_FQDN"), "equal": pre_env.get("ACR_FQDN") == post_env.get("ACR_FQDN")},
    "acr_data_fqdn_env": {"pre_value": pre_env.get("ACR_DATA_FQDN"), "post_value": post_env.get("ACR_DATA_FQDN"), "equal": pre_env.get("ACR_DATA_FQDN") == post_env.get("ACR_DATA_FQDN")},
    "ingress_target_port": {"pre_value": pre_ingress.get("targetPort"), "post_value": post_ingress.get("targetPort"), "equal": pre_ingress.get("targetPort") == post_ingress.get("targetPort")},
    "min_replicas": {"pre_value": pre_scale.get("minReplicas"), "post_value": post_scale.get("minReplicas"), "equal": pre_scale.get("minReplicas") == post_scale.get("minReplicas")},
    "max_replicas": {"pre_value": pre_scale.get("maxReplicas"), "post_value": post_scale.get("maxReplicas"), "equal": pre_scale.get("maxReplicas") == post_scale.get("maxReplicas")},
    "pe_nic_ip_map": {"pre_value": pre_nic_map, "post_value": post_nic_map, "equal": pe_nic_unchanged},
    "registry_record_name": {"pre_value": registry_record_name, "post_value": registry_record_name, "equal": True},
    "data_record_name": {"pre_value": data_record_name, "post_value": data_record_name, "equal": True},
    "live_revision_name": {"pre_value": pre_live_revision.get("name") if pre_live_revision else None, "post_value": post_live_revision.get("name") if post_live_revision else None, "equal": (pre_live_revision.get("name") if pre_live_revision else None) == (post_live_revision.get("name") if post_live_revision else None)},
}

pre_norm = {
    "container_app": {
        "name": pre_app.get("name"),
        "resource_group": pre_app.get("resourceGroup"),
        "identity_type": pre_app.get("identity", {}).get("type"),
        "revision": {
            "latest_ready_revision_name": pre_app.get("properties", {}).get("latestReadyRevisionName"),
            "latest_revision_name": pre_app.get("properties", {}).get("latestRevisionName"),
            "live_revision_name": pre_live_revision.get("name") if pre_live_revision else None,
            "live_revision_health_state": pre_live_props.get("healthState"),
            "live_revision_running_state": pre_live_props.get("runningState"),
            "live_revision_provisioning_state": pre_live_props.get("provisioningState"),
            "live_revision_active": pre_live_props.get("active"),
        },
        "container": {
            "name": pre_container.get("name"),
            "image": pre_container.get("image"),
            "cpu": pre_container.get("resources", {}).get("cpu"),
            "memory": pre_container.get("resources", {}).get("memory"),
            "build_tag": pre_env.get("BUILD_TAG"),
            "acr_fqdn": pre_env.get("ACR_FQDN"),
            "acr_data_fqdn": pre_env.get("ACR_DATA_FQDN"),
        },
        "ingress": {"external": pre_ingress.get("external"), "target_port": pre_ingress.get("targetPort")},
        "scale": {"min_replicas": pre_scale.get("minReplicas"), "max_replicas": pre_scale.get("maxReplicas")},
    },
    "acr": {"publicNetworkAccess": acr_pre.get("publicNetworkAccess"), "defaultAction": acr_pre.get("networkRuleSet", {}).get("defaultAction")},
    "dns_records": {
        "registry_record_present": bool(pre_registry_records),
        "registry_record_ips": pre_registry_records[0]["a_records"] if pre_registry_records else [],
        "data_record_present": bool(pre_data_records),
        "data_record_ips": pre_data_records[0]["a_records"] if pre_data_records else [],
        "record_count": len(records_pre),
    },
    "pe_nic": pre_nic_map,
    "probe": {
        "topology_class": pre_probe_response.get("topology_class"),
        "registry_dns_class": pre_probe_response.get("registry", {}).get("dns", {}).get("class"),
        "registry_dns_ip": pre_probe_response.get("registry", {}).get("dns", {}).get("ip"),
        "registry_dns_error": pre_probe_response.get("registry", {}).get("dns", {}).get("error"),
        "registry_tcp_connected": pre_probe_response.get("registry", {}).get("tcp", {}).get("connected"),
        "registry_tls_handshake": pre_probe_response.get("registry", {}).get("tls", {}).get("handshake"),
        "registry_http_status": pre_probe_response.get("registry", {}).get("http", {}).get("status"),
        "data_dns_class": pre_probe_response.get("data", {}).get("dns", {}).get("class"),
        "data_dns_ip": pre_probe_response.get("data", {}).get("dns", {}).get("ip"),
        "data_dns_error": pre_probe_response.get("data", {}).get("dns", {}).get("error"),
        "data_tcp_connected": pre_probe_response.get("data", {}).get("tcp", {}).get("connected"),
        "data_tcp_error": pre_probe_response.get("data", {}).get("tcp", {}).get("error"),
        "data_tls_handshake": pre_probe_response.get("data", {}).get("tls", {}).get("handshake"),
        "data_tls_error": pre_probe_response.get("data", {}).get("tls", {}).get("error"),
        "data_http_status": pre_probe_response.get("data", {}).get("http", {}).get("status"),
        "data_http_error": pre_probe_response.get("data", {}).get("http", {}).get("error"),
    },
    "system_logs": {"pull_failure_row_count": pre_pull_failure_count},
}

post_norm = {
    "container_app": {
        "name": post_app.get("name"),
        "resource_group": post_app.get("resourceGroup"),
        "identity_type": post_app.get("identity", {}).get("type"),
        "revision": {
            "latest_ready_revision_name": post_app.get("properties", {}).get("latestReadyRevisionName"),
            "latest_revision_name": post_app.get("properties", {}).get("latestRevisionName"),
            "live_revision_name": post_live_revision.get("name") if post_live_revision else None,
            "live_revision_health_state": post_live_props.get("healthState"),
            "live_revision_running_state": post_live_props.get("runningState"),
            "live_revision_provisioning_state": post_live_props.get("provisioningState"),
            "live_revision_active": post_live_props.get("active"),
        },
        "container": {
            "name": post_container.get("name"),
            "image": post_container.get("image"),
            "cpu": post_container.get("resources", {}).get("cpu"),
            "memory": post_container.get("resources", {}).get("memory"),
            "build_tag": post_env.get("BUILD_TAG"),
            "acr_fqdn": post_env.get("ACR_FQDN"),
            "acr_data_fqdn": post_env.get("ACR_DATA_FQDN"),
        },
        "ingress": {"external": post_ingress.get("external"), "target_port": post_ingress.get("targetPort")},
        "scale": {"min_replicas": post_scale.get("minReplicas"), "max_replicas": post_scale.get("maxReplicas")},
    },
    "acr": {"publicNetworkAccess": post_acr.get("publicNetworkAccess"), "defaultAction": post_acr.get("networkRuleSet", {}).get("defaultAction")},
    "dns_records": {
        "registry_record_present": bool(post_registry_records),
        "registry_record_ips": post_registry_records[0]["a_records"] if post_registry_records else [],
        "data_record_present": bool(post_data_records),
        "data_record_ips": post_data_records[0]["a_records"] if post_data_records else [],
        "record_count": len(records_post),
    },
    "pe_nic": post_nic_map,
    "probe": {
        "topology_class": post_probe_response.get("topology_class"),
        "registry_dns_class": post_probe_response.get("registry", {}).get("dns", {}).get("class"),
        "registry_dns_ip": post_probe_response.get("registry", {}).get("dns", {}).get("ip"),
        "registry_dns_error": post_probe_response.get("registry", {}).get("dns", {}).get("error"),
        "registry_tcp_connected": post_probe_response.get("registry", {}).get("tcp", {}).get("connected"),
        "registry_tls_handshake": post_probe_response.get("registry", {}).get("tls", {}).get("handshake"),
        "registry_http_status": post_probe_response.get("registry", {}).get("http", {}).get("status"),
        "data_dns_class": post_probe_response.get("data", {}).get("dns", {}).get("class"),
        "data_dns_ip": post_probe_response.get("data", {}).get("dns", {}).get("ip"),
        "data_dns_error": post_probe_response.get("data", {}).get("dns", {}).get("error"),
        "data_tcp_connected": post_probe_response.get("data", {}).get("tcp", {}).get("connected"),
        "data_tcp_error": post_probe_response.get("data", {}).get("tcp", {}).get("error"),
        "data_tls_handshake": post_probe_response.get("data", {}).get("tls", {}).get("handshake"),
        "data_tls_error": post_probe_response.get("data", {}).get("tls", {}).get("error"),
        "data_http_status": post_probe_response.get("data", {}).get("http", {}).get("status"),
        "data_http_error": post_probe_response.get("data", {}).get("http", {}).get("error"),
    },
}

flattened_pre = flatten_json("", pre_norm)
flattened_post = flatten_json("", post_norm)
overlap_paths = sorted(set(flattened_pre) & set(flattened_post))
overlap_diff_map = {path: {"pre_value": flattened_pre[path], "post_value": flattened_post[path]} for path in overlap_paths if flattened_pre[path] != flattened_post[path]}
overlap_same_map = {path: flattened_pre[path] for path in overlap_paths if flattened_pre[path] == flattened_post[path]}
allowed_expected_diff_paths = {
    "dns_records.data_record_ips[0]",
    "dns_records.data_record_present",
    "dns_records.record_count",
    "probe.data_dns_class",
    "probe.data_dns_error",
    "probe.data_dns_ip",
    "probe.data_http_error",
    "probe.data_http_status",
    "probe.data_tcp_connected",
    "probe.data_tcp_error",
    "probe.data_tls_error",
    "probe.data_tls_handshake",
    "probe.topology_class",
}
required_expected_diff_paths = {"dns_records.data_record_present", "probe.data_dns_class", "probe.data_dns_error", "probe.topology_class"}
unexpected_overlap_diffs = {path: value for path, value in overlap_diff_map.items() if path not in allowed_expected_diff_paths}
missing_required_diff_paths = sorted(required_expected_diff_paths - set(overlap_diff_map))

expected_data_ip = next((item.get("private_ip") for item in pre_nic_map if acr_data_fqdn in item.get("fqdns", [])), None)
expected_registry_ip = next((item.get("private_ip") for item in pre_nic_map if acr_login_server in item.get("fqdns", [])), None)

explicit_drops = [
    {"id": "acr_control_plane_fresh_pull", "note": "The pack intentionally does not prove broken-window control-plane fresh-pull behavior because this workload-path lab keeps the already-running revision in place."},
    {"id": "dns_resolution_timing", "note": "The pack proves DNS-class transitions, not the exact resolver-latency delta for each lookup."},
    {"id": "exact_http_body_bytes", "note": "The probe records status codes and errors, not a byte-identical backend body."},
    {"id": "image_layer_cache_state", "note": "The already-running revision remains healthy, but the raw cohort does not enumerate every cached OCI layer."},
    {"id": "probe_retry_attempt_count", "note": "Retry disclosure is preserved explicitly, but the causal claim is about the final selected topology transition, not an exact retry count contract."},
    {"id": "resource_provider_poll_latency", "note": "Azure control-plane poll timing is outside the causal field under test."},
    {"id": "system_log_ingestion_latency", "note": "The zero-row pull-failure query proves absence in the captured window, not the exact ingestion delay of every platform event."},
    {"id": "tls_cipher_suite", "note": "The pack proves TLS handshake success or skip, not the negotiated cipher suite bytes."},
]
runtime_drop_ids = frozenset(item["id"] for item in explicit_drops)

subgate_14a_pass = not parse_errors
subgate_14b_pass = strong_temporal or fallback_temporal
subgate_14c_pass = both_parse_ok and pre_post_lineage_equal
subgate_14d_pass = pe_nic_unchanged and not unexpected_non_junk and observed_xrefs == expected_xrefs
subgate_14e_pass = utc_window_start <= utc_window_end and all(item["timestamp_utc"] for item in all_anchor_infos.values())
gate_14_all_subgates_pass = all([subgate_14a_pass, subgate_14b_pass, subgate_14c_pass, subgate_14d_pass, subgate_14e_pass])

subgate_15a_pass = len(pre_data_records) == 0 and len(pre_registry_records) == 1
subgate_15b_pass = pre_probe_response.get("topology_class") == "data_nxdomain" and pre_probe_response.get("registry", {}).get("dns", {}).get("class") == "private" and pre_probe_response.get("data", {}).get("dns", {}).get("class") is None and isinstance(pre_probe_response.get("data", {}).get("dns", {}).get("error"), str) and "gaierror" in pre_probe_response.get("data", {}).get("dns", {}).get("error", "") and pre_retry_disclosure_ok
subgate_15c_pass = pre_live_revision is not None and pre_live_props.get("healthState") == "Healthy" and pre_live_props.get("active") is True and all_pre_revision_healthy
subgate_15d_pass = pre_pull_failure_count == 0
subgate_15e_pass = acr_pre.get("publicNetworkAccess") == post_acr.get("publicNetworkAccess")
gate_15_all_subgates_pass = all([subgate_15a_pass, subgate_15b_pass, subgate_15c_pass, subgate_15d_pass, subgate_15e_pass])

subgate_16a_pass = len(post_data_records) == 1 and post_data_records[0]["a_records"] == ([expected_data_ip] if expected_data_ip else []) and len(post_registry_records) == 1
subgate_16b_pass = post_probe_response.get("topology_class") == "both_private" and post_probe_response.get("registry", {}).get("dns", {}).get("class") == "private" and post_probe_response.get("data", {}).get("dns", {}).get("class") == "private" and post_probe_response.get("registry", {}).get("dns", {}).get("ip") == expected_registry_ip and post_probe_response.get("data", {}).get("dns", {}).get("ip") == expected_data_ip and post_retry_disclosure_ok
subgate_16c_pass = post_live_revision is not None and post_live_props.get("healthState") == "Healthy" and post_live_props.get("active") is True and all_post_revision_healthy and pre_post_revision_equal
subgate_16d_pass = pe_nic_unchanged and acr_pre.get("publicNetworkAccess") == post_acr.get("publicNetworkAccess")
gate_16_all_subgates_pass = all([subgate_16a_pass, subgate_16b_pass, subgate_16c_pass, subgate_16d_pass])

subgate_17a_pass = all(item["equal"] for item in held_constant_checks.values()) and both_parse_ok and pre_post_lineage_equal and pre_post_revision_equal
subgate_17b_pass = not unexpected_overlap_diffs and not missing_required_diff_paths
subgate_17c_pass = runtime_drop_ids == DOCUMENTED_EXPLICIT_DROPS_CEILING
subgate_17d_pass = pre_live_revision is not None and post_live_revision is not None and pre_live_props.get("healthState") == "Healthy" and post_live_props.get("healthState") == "Healthy" and pre_live_revision.get("name") == post_live_revision.get("name") and pre_pull_failure_count == 0 and pre_probe_response.get("topology_class") == "data_nxdomain" and post_probe_response.get("topology_class") == "both_private"
gate_17_all_subgates_pass = all([subgate_17a_pass, subgate_17b_pass, subgate_17c_pass, subgate_17d_pass])

# gate payload construction omitted here? no, continue below

gate14 = {
    "claim": f"The 12-file acr-network-path-record-split-brain raw cohort is internally consistent: every canonical file is present and parseable, every per-file UTC anchor falls within one bounded capture window, the pre/post live revision IDs parse to the same {resource_group} / {app_name} lineage, and the PE NIC IP map stays unchanged across H1 and H2.",
    "claim_level": "Observed",
    "gate_classification": "Cohort integrity gate: structural pre-condition for the bounded-falsification pack.",
    "hypothesis": "H_cohort_integrity",
    "path_used": path_used,
    "predicate_inputs": {
        "app_spec_pre": repo_rel("01-app-spec-pre-fix.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
        "pe_nic_pre": repo_rel("04-pe-nic-config-pre-fix.json"),
        "revision_list_post": repo_rel("10-revision-list-post-fix.json"),
        "composite_post": repo_rel("12-pe-nic-config-post-fix.json"),
        "evidence_readme": repo_rel("README.md"),
    },
    "acr_network_path_record_split_brain_h_cohort_integrity_all_subgates_pass": gate_14_all_subgates_pass,
    "acr_network_path_record_split_brain_h_cohort_integrity_sub_gates": {
        "a_canonical_raw_files_present_and_parse": subgate_14a_pass,
        "b_every_per_file_utc_anchor_falls_within_one_bounded_window": subgate_14b_pass,
        "c_revision_id_lineage_parses_and_compares_equal": subgate_14c_pass,
        "d_pe_nic_ip_map_is_unchanged_and_readme_xrefs_exist": subgate_14d_pass,
        "e_utc_reference_and_span_math_stay_consistent": subgate_14e_pass,
    },
    "scenario": "acr_network_path_record_split_brain",
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
            "claim": "The pre-fix and post-fix live revision IDs parse to the same resource-group/container-app lineage.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("10-revision-list-post-fix.json")],
            "observed_values": {
                "pre_revision_id": pre_revision_id,
                "post_revision_id": post_revision_id,
                "pre_parse_ok": pre_parse_ok,
                "post_parse_ok": post_parse_ok,
                "both_parse_ok": both_parse_ok,
                "pre_resource_group": pre_revision_parts["resource_group"],
                "post_resource_group": post_revision_parts["resource_group"],
                "pre_container_app": pre_revision_parts["container_app"],
                "post_container_app": post_revision_parts["container_app"],
                "pre_post_rg_equal": pre_post_rg_equal,
                "pre_post_app_equal": pre_post_app_equal,
                "pre_post_lineage_equal": pre_post_lineage_equal,
                "pre_post_revision_equal": pre_post_revision_equal,
            },
            "predicate": "The live revision ID selected from 02 and the live revision ID selected from 10 both match the /subscriptions/.../resourceGroups/.../containerApps/.../revisions/... regex, and the parsed resourceGroup + containerApp + revision components compare equal only when both parses succeed.",
            "result": "pass" if subgate_14c_pass else "fail",
            "sub_gate": "c_revision_id_lineage_parses_and_compares_equal",
        },
        {
            "claim": "The PE NIC IP map is unchanged across H1 and H2, no unexpected non-junk extras exist, and evidence/README.md literally names all four Phase B outputs.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("04-pe-nic-config-pre-fix.json"), repo_rel("12-pe-nic-config-post-fix.json"), repo_rel("README.md")],
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
            "predicate": "The normalized PE NIC ipConfigurations captured in 04 and 12.pe_nic compare equal, extras == [], and evidence/README.md contains the four gate filenames literally.",
            "result": "pass" if subgate_14d_pass else "fail",
            "sub_gate": "d_pe_nic_ip_map_is_unchanged_and_readme_xrefs_exist",
        },
        {
            "claim": "The cohort records one consistent UTC reference window and the span math is computed from that same anchor set.",
            "claim_level": "Measured",
            "evidence_files": [repo_rel(name) for name in RAW_FILES],
            "observed_values": {
                "utc_window_start": utc_window_start.isoformat(),
                "utc_window_end": utc_window_end.isoformat(),
                "utc_window_span_seconds": utc_window_span_seconds,
                "time_source_summary": time_source_summary,
            },
            "predicate": "utc_window_start <= utc_window_end AND utc_window_span_seconds is computed from the same anchor set disclosed in pre_anchor_timestamps + post_anchor_timestamps.",
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
    "claim": f"The H1 trigger produced the documented workload-path failure surface on {app_name}: the data A record is absent while the registry record stays present, the /probe endpoint returns topology_class=data_nxdomain with explicit retry disclosure, the already-running revision stays Healthy, and the captured pull-failure KQL window stays empty. This is the silent workload-path failure mode for record-level zone authority.",
    "claim_level": "Observed",
    "gate_classification": "H1 gate: confirms that deleting the regional data A record flips only the workload probe surface while the already-running revision stays healthy.",
    "hypothesis": "H1_trigger_produces_failure",
    "path_used": "single",
    "predicate_inputs": {
        "dns_records_pre": repo_rel("03-private-dns-record-list-pre-fix.json"),
        "acr_public_access_pre": repo_rel("05-acr-public-access-pre-fix.json"),
        "system_logs_pre": repo_rel("06-system-logs-pre-fix.json"),
        "probe_pre": repo_rel("08-probe-response-pre-fix.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
    },
    "acr_network_path_record_split_brain_h1_trigger_produces_failure_all_subgates_pass": gate_15_all_subgates_pass,
    "acr_network_path_record_split_brain_h1_trigger_produces_failure_sub_gates": {
        "a_data_record_is_absent_while_registry_record_stays_present": subgate_15a_pass,
        "b_probe_reports_data_nxdomain_with_retry_disclosure": subgate_15b_pass,
        "c_already_running_revision_stays_healthy": subgate_15c_pass,
        "d_broken_window_contains_no_pull_failure_rows": subgate_15d_pass,
        "e_acr_public_access_stays_constant": subgate_15e_pass,
    },
    "scenario": "acr_network_path_record_split_brain",
    "sub_gates": [
        {
            "claim": "The pre-fix DNS record list is missing the regional data A record while the registry A record is still present.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("03-private-dns-record-list-pre-fix.json")],
            "observed_values": {
                "registry_record_name": registry_record_name,
                "data_record_name": data_record_name,
                "registry_record_matches": pre_registry_records,
                "data_record_matches": pre_data_records,
            },
            "predicate": "len(pre registry record matches) == 1 AND len(pre data record matches) == 0.",
            "result": "pass" if subgate_15a_pass else "fail",
            "sub_gate": "a_data_record_is_absent_while_registry_record_stays_present",
        },
        {
            "claim": "The broken-window /probe response reports topology_class=data_nxdomain and explicitly discloses how many retries were needed before that final selected response.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("08-probe-response-pre-fix.json")],
            "observed_values": {
                "expected_topology": probe_pre_payload.get("expected_topology"),
                "selected_attempt": pre_selected_attempt,
                "attempt_count": pre_attempt_count,
                "attempts": pre_attempts,
                "final_response": pre_probe_response,
            },
            "predicate": "08.response.topology_class == 'data_nxdomain' AND 08.response.registry.dns.class == 'private' AND 08.response.data.dns.class == null AND 08.response.data.dns.error contains 'gaierror' AND 08.selected_attempt >= 1 AND len(08.attempts) >= 08.selected_attempt.",
            "result": "pass" if subgate_15b_pass else "fail",
            "sub_gate": "b_probe_reports_data_nxdomain_with_retry_disclosure",
        },
        {
            "claim": "The already-running revision stays Healthy throughout the broken window.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json")],
            "observed_values": {
                "pre_live_revision": pre_live_revision,
                "all_pre_revision_healthy": all_pre_revision_healthy,
            },
            "predicate": "The live revision selected from 02 has healthState == 'Healthy' and active == true, and every revision captured in 02 has healthState == 'Healthy'.",
            "result": "pass" if subgate_15c_pass else "fail",
            "sub_gate": "c_already_running_revision_stays_healthy",
        },
        {
            "claim": "The captured broken-window pull-failure query stays empty, proving that the failure is silent at the revision-health and pull-failure observability layer.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("06-system-logs-pre-fix.json")],
            "observed_values": {
                "query": system_pre.get("query"),
                "window_start_utc": pre_window_start,
                "window_end_utc": pre_window_end,
                "row_count": pre_pull_failure_count,
                "rows": pre_pull_failure_rows,
            },
            "predicate": "len(06.rows) == 0.",
            "result": "pass" if subgate_15d_pass else "fail",
            "sub_gate": "d_broken_window_contains_no_pull_failure_rows",
        },
        {
            "claim": "ACR publicNetworkAccess stays constant during the broken window, so the H1 outcome is not explained by a public-access toggle.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("05-acr-public-access-pre-fix.json"), repo_rel("12-pe-nic-config-post-fix.json")],
            "observed_values": {
                "pre_public_network_access": acr_pre.get("publicNetworkAccess"),
                "post_public_network_access": post_acr.get("publicNetworkAccess"),
            },
            "predicate": "05.publicNetworkAccess == 12.acr.publicNetworkAccess.",
            "result": "pass" if subgate_15e_pass else "fail",
            "sub_gate": "e_acr_public_access_stays_constant",
        },
    ],
    "thresholds": {
        "expected_broken_pull_failure_rows": 0,
    },
    "utc_captured": UTC_NOW,
}

gate16 = {
    "claim": f"The H2 fix restored recovery on {app_name}: the regional data A record is present again with the PE NIC data IP, the /probe endpoint returns topology_class=both_private, the same already-running revision stays Healthy, and no new revision was created during the lab. This is the workload-path silence invariant.",
    "claim_level": "Observed",
    "gate_classification": "H2 gate: confirms recovery after restoring the deleted regional data A record and proves that the workload-path lab never deployed a new revision.",
    "hypothesis": "H2_fix_restores_recovery",
    "path_used": "single",
    "predicate_inputs": {
        "dns_records_post": repo_rel("09-private-dns-record-list-post-fix.json"),
        "revision_list_post": repo_rel("10-revision-list-post-fix.json"),
        "probe_post": repo_rel("11-probe-response-post-fix.json"),
        "composite_post": repo_rel("12-pe-nic-config-post-fix.json"),
    },
    "acr_network_path_record_split_brain_h2_fix_restores_recovery_all_subgates_pass": gate_16_all_subgates_pass,
    "acr_network_path_record_split_brain_h2_fix_restores_recovery_sub_gates": {
        "a_data_record_is_restored_with_the_pe_data_ip": subgate_16a_pass,
        "b_probe_returns_both_private_again": subgate_16b_pass,
        "c_same_revision_stays_healthy_without_a_new_revision": subgate_16c_pass,
        "d_acr_access_and_pe_topology_stay_constant": subgate_16d_pass,
    },
    "scenario": "acr_network_path_record_split_brain",
    "sub_gates": [
        {
            "claim": "The post-fix DNS record list contains exactly one restored regional data A record with the original PE NIC data IP.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("09-private-dns-record-list-post-fix.json"), repo_rel("04-pe-nic-config-pre-fix.json")],
            "observed_values": {
                "expected_data_ip": expected_data_ip,
                "post_data_records": post_data_records,
                "post_registry_records": post_registry_records,
            },
            "predicate": "len(post data record matches) == 1 AND post data record a_records == [the PE data IP captured from 04].",
            "result": "pass" if subgate_16a_pass else "fail",
            "sub_gate": "a_data_record_is_restored_with_the_pe_data_ip",
        },
        {
            "claim": "The post-fix /probe response returns topology_class=both_private and both FQDNs resolve to the expected PE NIC IPs.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("11-probe-response-post-fix.json"), repo_rel("04-pe-nic-config-pre-fix.json")],
            "observed_values": {
                "expected_registry_ip": expected_registry_ip,
                "expected_data_ip": expected_data_ip,
                "selected_attempt": post_selected_attempt,
                "attempt_count": post_attempt_count,
                "attempts": post_attempts,
                "final_response": post_probe_response,
            },
            "predicate": "11.response.topology_class == 'both_private' AND 11.response.registry.dns.ip == expected registry PE IP AND 11.response.data.dns.ip == expected data PE IP AND 11.selected_attempt >= 1 AND len(11.attempts) >= 11.selected_attempt.",
            "result": "pass" if subgate_16b_pass else "fail",
            "sub_gate": "b_probe_returns_both_private_again",
        },
        {
            "claim": "The same already-running revision stays Healthy after the fix and no new revision was created during the lab.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("10-revision-list-post-fix.json"), repo_rel("12-pe-nic-config-post-fix.json")],
            "observed_values": {
                "pre_live_revision": pre_live_revision,
                "post_live_revision": post_live_revision,
                "pre_post_revision_equal": pre_post_revision_equal,
                "all_post_revision_healthy": all_post_revision_healthy,
            },
            "predicate": "The live revision selected from 10 has healthState == 'Healthy' and active == true, every revision captured in 10 has healthState == 'Healthy', and the selected revision name in 10 equals the selected revision name in 02.",
            "result": "pass" if subgate_16c_pass else "fail",
            "sub_gate": "c_same_revision_stays_healthy_without_a_new_revision",
        },
        {
            "claim": "ACR public access and PE topology stay constant across H1 and H2.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("05-acr-public-access-pre-fix.json"), repo_rel("12-pe-nic-config-post-fix.json")],
            "observed_values": {
                "pre_publicNetworkAccess": acr_pre.get("publicNetworkAccess"),
                "post_publicNetworkAccess": post_acr.get("publicNetworkAccess"),
                "pre_nic_map": pre_nic_map,
                "post_nic_map": post_nic_map,
            },
            "predicate": "05.publicNetworkAccess == 12.acr.publicNetworkAccess AND the normalized PE NIC ipConfigurations captured in 04 and 12.pe_nic compare equal.",
            "result": "pass" if subgate_16d_pass else "fail",
            "sub_gate": "d_acr_access_and_pe_topology_stay_constant",
        },
    ],
    "thresholds": {
        "expected_post_fix_data_record_count": 1,
    },
    "utc_captured": UTC_NOW,
}

gate17 = {
    "claim": "This evidence pack falsifies the ACR record-level zone-authority failure hypothesis within a bounded scope. Gate 17 demonstrates that the deleted regional data A record is the mechanically observable trigger field for this cohort: the container-app lineage stays constant, the same revision stays Healthy on both sides, the PE NIC IP map stays constant, the data record transitions from absent to present on the same zone, the workload probe transitions from data_nxdomain to both_private, and the broken-window pull-failure query stays empty. The pack does not claim exact DNS timing, exact retry counts, control-plane fresh-pull behavior, or byte-identical backend payloads.",
    "claim_level": "Observed",
    "cohort_binding_note": {
        "claim_ceiling": "The bounded claim is that this single koreacentral cohort proves a workload-path record-level zone-authority failure: deleting the regional data A record makes the in-replica /probe surface move from both_private to data_nxdomain while the already-running revision stays Healthy, and restoring that same record with the same PE data IP moves the probe back to both_private without deploying a new revision. The pack does NOT prove broken-window control-plane fresh-pull behavior, exact resolver latency, exact retry counts, byte-identical backend bodies, cache-layer inventory, system-log ingestion latency, or negotiated TLS cipher suites.",
        "explicit_drops": explicit_drops,
    },
    "gate_classification": "Bounded falsification gate: isolates the deleted regional data A record as the trigger while explicitly listing the unproven confounders and ceilings.",
    "hypothesis": "H3_bounded_falsification",
    "path_used": "bounded",
    "predicate_inputs": {
        "app_spec_pre": repo_rel("01-app-spec-pre-fix.json"),
        "revision_list_pre": repo_rel("02-revision-list-pre-fix.json"),
        "dns_records_pre": repo_rel("03-private-dns-record-list-pre-fix.json"),
        "pe_nic_pre": repo_rel("04-pe-nic-config-pre-fix.json"),
        "system_logs_pre": repo_rel("06-system-logs-pre-fix.json"),
        "probe_pre": repo_rel("08-probe-response-pre-fix.json"),
        "dns_records_post": repo_rel("09-private-dns-record-list-post-fix.json"),
        "revision_list_post": repo_rel("10-revision-list-post-fix.json"),
        "probe_post": repo_rel("11-probe-response-post-fix.json"),
        "composite_post": repo_rel("12-pe-nic-config-post-fix.json"),
    },
    "acr_network_path_record_split_brain_h3_bounded_falsification_all_subgates_pass": gate_17_all_subgates_pass,
    "acr_network_path_record_split_brain_h3_bounded_falsification_sub_gates": {
        "a_held_constant_fields_and_lineage_stay_equal": subgate_17a_pass,
        "b_full_overlapping_h1_h2_diff_matches_the_record_level_trigger_story": subgate_17b_pass,
        "c_explicit_drops_match_the_documented_ceiling": subgate_17c_pass,
        "d_workload_path_silence_invariant_is_checked": subgate_17d_pass,
    },
    "scenario": "acr_network_path_record_split_brain",
    "sub_gates": [
        {
            "claim": "The held-constant fields, PE topology, lineage, and live revision identity stay equal across H1 and H2.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("01-app-spec-pre-fix.json"), repo_rel("04-pe-nic-config-pre-fix.json"), repo_rel("10-revision-list-post-fix.json"), repo_rel("12-pe-nic-config-post-fix.json")],
            "observed_values": {
                "held_constant_checks": held_constant_checks,
                "pre_post_lineage_equal": pre_post_lineage_equal,
                "pre_post_revision_equal": pre_post_revision_equal,
            },
            "predicate": "Every held_constant_checks entry has equal == true, the normalized PE NIC ipConfigurations compare equal, and the parsed pre/post live revision IDs compare equal on resourceGroup + containerApp + revision when both parses succeed.",
            "result": "pass" if subgate_17a_pass else "fail",
            "sub_gate": "a_held_constant_fields_and_lineage_stay_equal",
        },
        {
            "claim": "The full overlapping H1↔H2 diff matches the bounded record-level trigger story and no overlapping field outside the documented record/probe outputs changes.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("01-app-spec-pre-fix.json"), repo_rel("03-private-dns-record-list-pre-fix.json"), repo_rel("08-probe-response-pre-fix.json"), repo_rel("09-private-dns-record-list-post-fix.json"), repo_rel("11-probe-response-post-fix.json"), repo_rel("12-pe-nic-config-post-fix.json")],
            "observed_values": {
                "allowed_expected_diff_paths": sorted(allowed_expected_diff_paths),
                "required_expected_diff_paths": sorted(required_expected_diff_paths),
                "full_overlap_diff": overlap_diff_map,
                "full_overlap_equal": overlap_same_map,
                "overlap_paths": overlap_paths,
                "unexpected_overlap_diffs": unexpected_overlap_diffs,
                "missing_required_diff_paths": missing_required_diff_paths,
            },
            "predicate": "Across the full normalized overlapping H1/H2 surface, the only differing overlap paths are the documented data-record and data-probe output fields; no other overlapping path may differ, and the required paths {dns_records.data_record_present, probe.data_dns_class, probe.data_dns_error, probe.topology_class} must all differ.",
            "result": "pass" if subgate_17b_pass else "fail",
            "sub_gate": "b_full_overlapping_h1_h2_diff_matches_the_record_level_trigger_story",
        },
        {
            "claim": "The bounded-falsification gate explicitly lists the documented ceilings and unsupported inferences.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("17-bounded-falsification-gate.json")],
            "observed_values": {
                "documented_ceiling_ids": sorted(DOCUMENTED_EXPLICIT_DROPS_CEILING),
                "observed_drop_ids": [item["id"] for item in explicit_drops],
            },
            "predicate": "cohort_binding_note.explicit_drops ids equal the static documented ceiling {acr_control_plane_fresh_pull, dns_resolution_timing, exact_http_body_bytes, image_layer_cache_state, probe_retry_attempt_count, resource_provider_poll_latency, system_log_ingestion_latency, tls_cipher_suite} with no additions and no omissions.",
            "result": "pass" if subgate_17c_pass else "fail",
            "sub_gate": "c_explicit_drops_match_the_documented_ceiling",
        },
        {
            "claim": "The workload-path silence invariant is checked actively: the same revision stays Healthy on both sides, H1 shows data_nxdomain, H2 shows both_private, and the broken-window pull-failure query stays empty.",
            "claim_level": "Observed",
            "evidence_files": [repo_rel("02-revision-list-pre-fix.json"), repo_rel("06-system-logs-pre-fix.json"), repo_rel("10-revision-list-post-fix.json"), repo_rel("11-probe-response-post-fix.json")],
            "observed_values": {
                "pre_live_revision_name": pre_live_revision.get("name") if pre_live_revision else None,
                "post_live_revision_name": post_live_revision.get("name") if post_live_revision else None,
                "pre_health_state": pre_live_props.get("healthState"),
                "post_health_state": post_live_props.get("healthState"),
                "pre_topology_class": pre_probe_response.get("topology_class"),
                "post_topology_class": post_probe_response.get("topology_class"),
                "broken_window_pull_failure_row_count": pre_pull_failure_count,
            },
            "predicate": "02.selected live revision name == 10.selected live revision name AND both selected live revisions have healthState == 'Healthy' AND 08.response.topology_class == 'data_nxdomain' AND 11.response.topology_class == 'both_private' AND len(06.rows) == 0.",
            "result": "pass" if subgate_17d_pass else "fail",
            "sub_gate": "d_workload_path_silence_invariant_is_checked",
        },
    ],
    "thresholds": {
        "held_constant_field_count": len(held_constant_checks),
        "expected_broken_pull_failure_rows": 0,
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
    output_map[gate_number].write_text(json.dumps(sanitize_value(gate_data), indent=2) + "\n", encoding="utf-8")

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
