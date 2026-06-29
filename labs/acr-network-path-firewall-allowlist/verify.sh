#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/acr-network-path-firewall-allowlist/evidence"
LAB_README_PATH="${SCRIPT_DIR}/README.md"
LAB_GUIDE_PATH="${SCRIPT_DIR}/../../docs/troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md"
UTC_NOW="${UTC_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR LAB_README_PATH LAB_GUIDE_PATH UTC_NOW

declare -a CANONICAL_RAW_FILES=(
    "01-app-spec-pre-fix.json"
    "02-revision-list-pre-fix.json"
    "03-acr-network-rules-pre-fix.json"
    "04-firewall-metadata-pre-fix.json"
    "05-baseline-success-window.json"
    "06-system-logs-pre-fix.json"
    "07-containerapp-spec-pre-fix.yaml"
    "08-h1-failure-window.json"
    "09-acr-network-rules-post-fix.json"
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

gate_number = int(os.environ['GATE_NUMBER'])
evidence_dir = Path(os.environ['EVIDENCE_DIR'])
lab_readme = Path(os.environ['LAB_README_PATH'])

RAW_FILES = [
    '01-app-spec-pre-fix.json',
    '02-revision-list-pre-fix.json',
    '03-acr-network-rules-pre-fix.json',
    '04-firewall-metadata-pre-fix.json',
    '05-baseline-success-window.json',
    '06-system-logs-pre-fix.json',
    '07-containerapp-spec-pre-fix.yaml',
    '08-h1-failure-window.json',
    '09-acr-network-rules-post-fix.json',
    '10-revision-list-post-fix.json',
    '11-app-spec-post-fix.json',
    '12-h2-recovery-window.json',
]

def load_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))

def load_yaml(path: Path):
    return yaml.safe_load(path.read_text(encoding='utf-8'))

if gate_number == 1:
    if evidence_dir.is_dir():
        print(f'evidence directory present at {evidence_dir}')
        raise SystemExit(0)
    print(f'evidence directory missing at {evidence_dir}')
    raise SystemExit(1)

if gate_number == 2:
    expected = RAW_FILES[:4]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print('missing canonical files: ' + ', '.join(missing))
        raise SystemExit(1)
    print('raw files 01-04 are present')
    raise SystemExit(0)

if gate_number == 3:
    expected = RAW_FILES[4:8]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print('missing canonical files: ' + ', '.join(missing))
        raise SystemExit(1)
    print('raw files 05-08 are present')
    raise SystemExit(0)

if gate_number == 4:
    expected = RAW_FILES[8:12]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print('missing canonical files: ' + ', '.join(missing))
        raise SystemExit(1)
    print('raw files 09-12 are present')
    raise SystemExit(0)

if gate_number == 5:
    try:
        payload = load_json(evidence_dir / RAW_FILES[0])
    except Exception as exc:
        print(f'01 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    container_app = payload.get('container_app', {})
    metadata = payload.get('capture_metadata', {})
    ok = bool(container_app.get('name')) and bool(container_app.get('resourceGroup')) and bool(metadata.get('acr_name')) and bool(metadata.get('firewall_public_ip'))
    if ok:
        print('01 parses and captures the app surface plus cohort anchors')
        raise SystemExit(0)
    print('01 missing expected container-app or metadata fields')
    raise SystemExit(1)

if gate_number == 6:
    try:
        revisions = load_json(evidence_dir / RAW_FILES[1])
        acr = load_json(evidence_dir / RAW_FILES[2])
    except Exception as exc:
        print(f'02/03 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = isinstance(revisions, list) and len(revisions) >= 2 and isinstance(acr.get('networkRuleSet', {}).get('ipRules', []), list)
    if ok:
        print('02/03 parse and capture the H1 revision list plus ACR rule state')
        raise SystemExit(0)
    print('02/03 do not match the expected H1 revision/rule shape')
    raise SystemExit(1)

if gate_number == 7:
    try:
        firewall = load_json(evidence_dir / RAW_FILES[3])
        baseline = load_json(evidence_dir / RAW_FILES[4])
    except Exception as exc:
        print(f'04/05 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = bool(firewall.get('public_ip', {}).get('ipAddress')) and isinstance(baseline.get('rows'), list) and baseline.get('window_start_utc')
    if ok:
        print('04/05 parse and capture firewall metadata plus baseline rows')
        raise SystemExit(0)
    print('04/05 do not match the expected firewall/baseline shape')
    raise SystemExit(1)

if gate_number == 8:
    try:
        system_rows = load_json(evidence_dir / RAW_FILES[5])
    except Exception as exc:
        print(f'06 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = isinstance(system_rows.get('rows'), list) and system_rows.get('query') and system_rows.get('window_start_utc')
    if ok:
        print(f"06 parses as a structured pre-fix system-log payload with {len(system_rows.get('rows', []))} rows")
        raise SystemExit(0)
    print('06 does not parse as the expected structured system-log payload')
    raise SystemExit(1)

if gate_number == 9:
    try:
        spec = load_yaml(evidence_dir / RAW_FILES[6])
    except Exception as exc:
        print(f'07 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ingress = spec.get('properties', {}).get('configuration', {}).get('ingress', {})
    ok = bool(spec.get('name')) and bool(spec.get('resourceGroup')) and int(ingress.get('targetPort', 0)) == 8080
    if ok:
        print('07 parses as YAML and pins ingress targetPort 8080')
        raise SystemExit(0)
    print('07 YAML does not match the expected app shape')
    raise SystemExit(1)

if gate_number == 10:
    try:
        h1 = load_json(evidence_dir / RAW_FILES[7])
    except Exception as exc:
        print(f'08 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = isinstance(h1.get('rows'), list) and isinstance(h1.get('http_response'), dict) and h1.get('h1_trigger_ts_utc')
    if ok:
        print('08 parses as the H1 failure-window payload')
        raise SystemExit(0)
    print('08 does not capture the expected H1 failure-window payload')
    raise SystemExit(1)

if gate_number == 11:
    try:
        acr_post = load_json(evidence_dir / RAW_FILES[8])
        revisions_post = load_json(evidence_dir / RAW_FILES[9])
    except Exception as exc:
        print(f'09/10 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = isinstance(acr_post.get('networkRuleSet', {}).get('ipRules', []), list) and isinstance(revisions_post, list) and len(revisions_post) >= 2
    if ok:
        print('09/10 parse and capture restored ACR rules plus H2 revisions')
        raise SystemExit(0)
    print('09/10 do not capture the expected H2 rule/revision surface')
    raise SystemExit(1)

if gate_number == 12:
    try:
        post_payload = load_json(evidence_dir / RAW_FILES[10])
        h2 = load_json(evidence_dir / RAW_FILES[11])
    except Exception as exc:
        print(f'11/12 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = bool(post_payload.get('container_app', {}).get('name')) and isinstance(h2.get('rows'), list) and isinstance(h2.get('http_response'), dict) and h2.get('h2_recovery_ts_utc')
    if ok:
        print('11/12 parse and capture the post-fix app surface plus H2 recovery payload')
        raise SystemExit(0)
    print('11/12 do not capture the expected post-fix composite surface')
    raise SystemExit(1)

if gate_number == 13:
    readme = evidence_dir / 'README.md'
    ok = readme.is_file() and lab_readme.is_file()
    if ok:
        print('lab README and evidence README are present')
        raise SystemExit(0)
    missing = []
    if not readme.is_file():
        missing.append(str(readme))
    if not lab_readme.is_file():
        missing.append(str(lab_readme))
    print('missing readme files: ' + ', '.join(missing))
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
    "6:pre-fix revisions and ACR rules parse" \
    "7:firewall metadata and baseline payload parse" \
    "8:pre-fix structured system logs parse" \
    "9:pre-fix YAML spec parses" \
    "10:h1 failure-window payload parses" \
    "11:post-fix ACR rules and revisions parse" \
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

EVIDENCE_DIR = Path(os.environ['EVIDENCE_DIR'])
REL = os.environ['REPO_RELATIVE_EVIDENCE_DIR']
UTC_NOW = os.environ['UTC_NOW']

_existing_captures = []
for gate_file in [
    '14-cohort-integrity-gate.json',
    '15-h1-trigger-produces-failure-gate.json',
    '16-h2-fix-restores-recovery-gate.json',
    '17-bounded-falsification-gate.json',
]:
    gate_path = EVIDENCE_DIR / gate_file
    if gate_path.exists():
        try:
            gate_data = json.loads(gate_path.read_text(encoding='utf-8'))
        except (OSError, json.JSONDecodeError):
            continue
        existing = gate_data.get('utc_captured')
        if isinstance(existing, str) and existing:
            _existing_captures.append(existing)
if _existing_captures:
    UTC_NOW = min(_existing_captures)

RAW_FILES = [
    '01-app-spec-pre-fix.json',
    '02-revision-list-pre-fix.json',
    '03-acr-network-rules-pre-fix.json',
    '04-firewall-metadata-pre-fix.json',
    '05-baseline-success-window.json',
    '06-system-logs-pre-fix.json',
    '07-containerapp-spec-pre-fix.yaml',
    '08-h1-failure-window.json',
    '09-acr-network-rules-post-fix.json',
    '10-revision-list-post-fix.json',
    '11-app-spec-post-fix.json',
    '12-h2-recovery-window.json',
]
GATE_FILES = [
    '14-cohort-integrity-gate.json',
    '15-h1-trigger-produces-failure-gate.json',
    '16-h2-fix-restores-recovery-gate.json',
    '17-bounded-falsification-gate.json',
]
EXPECTED_EVIDENCE_FILES = RAW_FILES + GATE_FILES + ['README.md']
JUNK_NAMES = {'.DS_Store'}
REVISION_ID_RE = re.compile(r'^/subscriptions/(?P<sub>[^/]+)/resourceGroups/(?P<rg>[^/]+)/providers/Microsoft\.App/containerApps/(?P<app>[^/]+)/revisions/(?P<rev>[^/]+)$')
DOCUMENTED_EXPLICIT_DROPS_CEILING = frozenset([
    'acr_firewall_internal_retry_schedule',
    'exact_pull_duration_milliseconds',
    'firewall_application_log_ingestion_latency',
    'image_layer_sha',
    'pod_uid',
    'replica_suffix_continuity',
    'revision_suffix_identity',
    'workload_source_ip_component_identity',
])

def repo_rel(name: str) -> str:
    return f'{REL}/{name}'

def load_json(name: str):
    return json.loads((EVIDENCE_DIR / name).read_text(encoding='utf-8'))

def load_yaml(name: str):
    return yaml.safe_load((EVIDENCE_DIR / name).read_text(encoding='utf-8'))

def parse_iso(text: str):
    value = datetime.fromisoformat(text.replace('Z', '+00:00'))
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)

def resolve_anchor_timestamp(name: str):
    if name == '05-baseline-success-window.json':
        dt = parse_iso(baseline_payload.get('window_end_utc'))
        return {'timestamp': dt, 'timestamp_utc': dt.isoformat(), 'time_source': 'payload.window_end_utc', 'raw_epoch': baseline_payload.get('window_end_utc')}
    if name == '06-system-logs-pre-fix.json':
        dt = parse_iso(system_pre_payload.get('window_end_utc'))
        return {'timestamp': dt, 'timestamp_utc': dt.isoformat(), 'time_source': 'payload.window_end_utc', 'raw_epoch': system_pre_payload.get('window_end_utc')}
    if name == '08-h1-failure-window.json':
        dt = parse_iso(h1_payload.get('h1_trigger_ts_utc'))
        return {'timestamp': dt, 'timestamp_utc': dt.isoformat(), 'time_source': 'payload.h1_trigger_ts_utc', 'raw_epoch': h1_payload.get('h1_trigger_ts_utc')}
    if name == '10-revision-list-post-fix.json' and post_recover_revision is not None:
        dt = parse_iso(post_recover_revision.get('properties', {}).get('createdTime'))
        return {'timestamp': dt, 'timestamp_utc': dt.isoformat(), 'time_source': 'revision.createdTime', 'raw_epoch': post_recover_revision.get('properties', {}).get('createdTime')}
    if name == '12-h2-recovery-window.json':
        dt = parse_iso(h2_payload.get('h2_recovery_ts_utc'))
        return {'timestamp': dt, 'timestamp_utc': dt.isoformat(), 'time_source': 'payload.h2_recovery_ts_utc', 'raw_epoch': h2_payload.get('h2_recovery_ts_utc')}
    stat = (EVIDENCE_DIR / name).stat()
    birthtime = getattr(stat, 'st_birthtime', None)
    if birthtime is not None and birthtime > 0:
        dt = datetime.fromtimestamp(birthtime, tz=timezone.utc)
        return {'timestamp': dt, 'timestamp_utc': dt.isoformat(), 'time_source': 'birthtime', 'raw_epoch': birthtime}
    dt = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)
    return {'timestamp': dt, 'timestamp_utc': dt.isoformat(), 'time_source': 'mtime', 'raw_epoch': stat.st_mtime}

def parse_revision_id(revision_id: str):
    match = REVISION_ID_RE.match(revision_id or '')
    if not match:
        return {'resource_group': None, 'container_app': None, 'revision': None}
    return {
        'resource_group': match.group('rg'),
        'container_app': match.group('app'),
        'revision': match.group('rev'),
    }

def flatten_json(prefix, value):
    if isinstance(value, dict):
        out = {}
        for key, inner in value.items():
            child = f'{prefix}.{key}' if prefix else key
            out.update(flatten_json(child, inner))
        return out
    if isinstance(value, list):
        out = {}
        for index, inner in enumerate(value):
            child = f'{prefix}[{index}]'
            out.update(flatten_json(child, inner))
        return out
    return {prefix: value}

def revision_sort_key(revision):
    created = revision.get('properties', {}).get('createdTime')
    return parse_iso(created) if created else datetime.min.replace(tzinfo=timezone.utc)

def find_revision_by_tag(revisions, tag: str):
    matches = []
    for row in revisions:
        containers = row.get('properties', {}).get('template', {}).get('containers', [])
        image = containers[0].get('image', '') if containers else ''
        if image.endswith(f':{tag}'):
            matches.append(row)
    if not matches:
        return None
    return sorted(matches, key=revision_sort_key, reverse=True)[0]

def extract_env(container):
    return {item.get('name'): item.get('value') for item in container.get('env', [])}

def image_tag(image: str):
    return image.split(':')[-1] if ':' in image else image

def log_reason(row):
    return row.get('Reason_s') or row.get('Reason') or ''

def log_message(row):
    return row.get('Log_s') or row.get('Log') or ''

def log_revision(row):
    return row.get('RevisionName_s') or row.get('RevisionName') or ''

def get_ip_rules(payload):
    rows = payload.get('networkRuleSet', {}).get('ipRules', []) or []
    out = []
    for row in rows:
        if isinstance(row, dict):
            out.append(row.get('ipAddressOrRange'))
        else:
            out.append(row)
    return sorted([value for value in out if value])

pre_app_payload = load_json('01-app-spec-pre-fix.json')
revisions_pre = load_json('02-revision-list-pre-fix.json')
acr_pre = load_json('03-acr-network-rules-pre-fix.json')
firewall_pre = load_json('04-firewall-metadata-pre-fix.json')
baseline_payload = load_json('05-baseline-success-window.json')
system_pre_payload = load_json('06-system-logs-pre-fix.json')
spec_pre = load_yaml('07-containerapp-spec-pre-fix.yaml')
h1_payload = load_json('08-h1-failure-window.json')
acr_post = load_json('09-acr-network-rules-post-fix.json')
revisions_post = load_json('10-revision-list-post-fix.json')
post_payload = load_json('11-app-spec-post-fix.json')
h2_payload = load_json('12-h2-recovery-window.json')

pre_app = pre_app_payload['container_app']
post_app = post_payload['container_app']
metadata = pre_app_payload['capture_metadata']
post_metadata = post_payload['capture_metadata']
post_broken_snapshot = post_metadata.get('broken_revision_post_deactivate') or {}

resource_group = metadata['resource_group']
app_name = metadata['app_name']
acr_name = metadata['acr_name']
fw_pip = metadata['firewall_public_ip']
firewall_private_ip = metadata['firewall_private_ip']
baseline_revision_name = metadata['baseline_revision_name']
broken_revision_name = metadata['broken_revision_name']
recover_revision_name = post_metadata['recover_revision_name']

baseline_rows = baseline_payload.get('rows', [])
pre_rows = system_pre_payload.get('rows', [])
post_rows = h2_payload.get('rows', [])

pre_broken_revision = find_revision_by_tag(revisions_pre, 'v-broken')
post_broken_revision = find_revision_by_tag(revisions_post, 'v-broken')
post_recover_revision = find_revision_by_tag(revisions_post, 'v-recover')
pre_baseline_revision = next((row for row in revisions_pre if row.get('name') == baseline_revision_name), None)
post_baseline_revision = next((row for row in revisions_post if row.get('name') == baseline_revision_name), None)
post_latest_revision = sorted(revisions_post, key=revision_sort_key, reverse=True)[0] if revisions_post else None

parse_errors = []
for name in [
    '01-app-spec-pre-fix.json', '02-revision-list-pre-fix.json', '03-acr-network-rules-pre-fix.json',
    '04-firewall-metadata-pre-fix.json', '05-baseline-success-window.json', '06-system-logs-pre-fix.json',
    '08-h1-failure-window.json', '09-acr-network-rules-post-fix.json', '10-revision-list-post-fix.json',
    '11-app-spec-post-fix.json', '12-h2-recovery-window.json',
]:
    try:
        load_json(name)
    except Exception as exc:
        parse_errors.append(f'{name}: {type(exc).__name__}: {exc}')
try:
    load_yaml('07-containerapp-spec-pre-fix.yaml')
except Exception as exc:
    parse_errors.append(f'07-containerapp-spec-pre-fix.yaml: {type(exc).__name__}: {exc}')

pre_anchor_files = ['05-baseline-success-window.json', '06-system-logs-pre-fix.json', '07-containerapp-spec-pre-fix.yaml', '08-h1-failure-window.json']
post_anchor_files = ['09-acr-network-rules-post-fix.json', '10-revision-list-post-fix.json', '12-h2-recovery-window.json']
pre_anchor_infos = {name: resolve_anchor_timestamp(name) for name in pre_anchor_files}
post_anchor_infos = {name: resolve_anchor_timestamp(name) for name in post_anchor_files}
all_anchor_infos = {**pre_anchor_infos, **post_anchor_infos}
monotonic_pairs = []
for pre_name, pre_info in pre_anchor_infos.items():
    for post_name, post_info in post_anchor_infos.items():
        monotonic_pairs.append({
            'pre_file': pre_name,
            'pre_timestamp_utc': pre_info['timestamp_utc'],
            'pre_time_source': pre_info['time_source'],
            'post_file': post_name,
            'post_timestamp_utc': post_info['timestamp_utc'],
            'post_time_source': post_info['time_source'],
            'delta_seconds': (post_info['timestamp'] - pre_info['timestamp']).total_seconds(),
            'holds': post_info['timestamp'] > pre_info['timestamp'],
        })
monotonic_ordering_holds = all(item['holds'] for item in monotonic_pairs)
sorted_anchor_sequence = [
    {
        'file': name,
        'timestamp_utc': info['timestamp_utc'],
        'time_source': info['time_source'],
        'anchor_class': 'pre' if name in pre_anchor_infos else 'post',
    }
    for name, info in sorted(all_anchor_infos.items(), key=lambda item: item[1]['timestamp'])
]
time_source_summary = {
    'birthtime_count': sum(1 for info in all_anchor_infos.values() if info['time_source'] == 'birthtime'),
    'mtime_count': sum(1 for info in all_anchor_infos.values() if info['time_source'] == 'mtime'),
    'fallback_used': any(info['time_source'] == 'mtime' for info in all_anchor_infos.values()),
}
utc_window_start = min(info['timestamp'] for info in all_anchor_infos.values())
utc_window_end = max(info['timestamp'] for info in all_anchor_infos.values())
utc_window_span_seconds = (utc_window_end - utc_window_start).total_seconds()
strong_temporal = monotonic_ordering_holds and utc_window_span_seconds <= 1800
fallback_temporal = monotonic_ordering_holds and utc_window_span_seconds <= 5400
path_used = 'strong' if strong_temporal else 'fallback'

observed_files_on_disk = sorted(path.name for path in EVIDENCE_DIR.iterdir() if path.is_file())
non_junk_files = [name for name in observed_files_on_disk if name not in JUNK_NAMES]
unexpected_non_junk = [name for name in non_junk_files if name not in EXPECTED_EVIDENCE_FILES]
readme_text = (EVIDENCE_DIR / 'README.md').read_text(encoding='utf-8')
expected_xrefs = GATE_FILES
observed_xrefs = [name for name in expected_xrefs if name in readme_text]

pre_revision_id = pre_broken_revision.get('id') if pre_broken_revision else ''
post_revision_id = post_recover_revision.get('id') if post_recover_revision else ''
pre_revision_parts = parse_revision_id(pre_revision_id)
post_revision_parts = parse_revision_id(post_revision_id)
pre_parse_ok = pre_revision_parts.get('resource_group') is not None and pre_revision_parts.get('container_app') is not None
post_parse_ok = post_revision_parts.get('resource_group') is not None and post_revision_parts.get('container_app') is not None
both_parse_ok = pre_parse_ok and post_parse_ok
pre_post_rg_equal = both_parse_ok and pre_revision_parts['resource_group'] == post_revision_parts['resource_group']
pre_post_app_equal = both_parse_ok and pre_revision_parts['container_app'] == post_revision_parts['container_app']
pre_post_lineage_equal = both_parse_ok and pre_post_rg_equal and pre_post_app_equal

pre_container = pre_app.get('properties', {}).get('template', {}).get('containers', [])[0]
post_container = post_app.get('properties', {}).get('template', {}).get('containers', [])[0]
pre_env = extract_env(pre_container)
post_env = extract_env(post_container)
pre_scale = pre_app.get('properties', {}).get('template', {}).get('scale', {})
post_scale = post_app.get('properties', {}).get('template', {}).get('scale', {})
pre_ingress = pre_app.get('properties', {}).get('configuration', {}).get('ingress', {})
post_ingress = post_app.get('properties', {}).get('configuration', {}).get('ingress', {})

pre_ip_rules = get_ip_rules(acr_pre)
post_ip_rules = get_ip_rules(acr_post)
fw_pip_in_post_rules = any(rule == fw_pip or rule == f'{fw_pip}/32' for rule in post_ip_rules)
fw_pip_in_pre_rules = any(rule == fw_pip or rule == f'{fw_pip}/32' for rule in pre_ip_rules)

baseline_pulling_rows = [row for row in baseline_rows if log_reason(row) == 'PullingImage' and baseline_revision_name in log_revision(row)]
baseline_pulled_rows = [row for row in baseline_rows if log_reason(row) == 'PulledImage' and baseline_revision_name in log_revision(row)]
pre_denied_rows = [row for row in pre_rows if 'DENIED' in log_message(row) and fw_pip in json.dumps(row)]
pre_vbroken_rows = [row for row in pre_rows if 'v-broken' in json.dumps(row)]
pre_unauthorized_rows = [row for row in pre_rows if log_reason(row) in {'ImagePullUnauthorized', 'ImagePullFailed', 'ContainerTerminated'}]
post_pulling_rows = [row for row in post_rows if log_reason(row) == 'PullingImage' and 'v-recover' in json.dumps(row)]
post_pulled_rows = [row for row in post_rows if log_reason(row) == 'PulledImage' and 'v-recover' in json.dumps(row)]
post_broken_success_rows = [row for row in post_rows if log_reason(row) == 'PulledImage' and 'v-broken' in json.dumps(row)]

broken_failure_states = {'Failed', 'ProvisioningFailed'}
broken_unhealthy_states = {'Unhealthy', 'None'}
broken_running_states = {'Failed', 'NotRunning', 'Degraded'}
pre_broken_props = pre_broken_revision.get('properties', {}) if pre_broken_revision else {}
post_broken_props = post_broken_revision.get('properties', {}) if post_broken_revision else {}
post_recover_props = post_recover_revision.get('properties', {}) if post_recover_revision else {}
post_broken_observed = post_broken_revision or post_broken_snapshot or None
post_broken_observed_props = post_broken_observed.get('properties', {}) if post_broken_observed else {}

pre_broken_failed = pre_broken_revision is not None and (
    pre_broken_props.get('provisioningState') in broken_failure_states
    or pre_broken_props.get('healthState') in broken_unhealthy_states
    or pre_broken_props.get('runningState') in broken_running_states
)
post_broken_failure_persists = post_broken_observed is not None and (
    post_broken_observed_props.get('provisioningState') in broken_failure_states
    or post_broken_observed_props.get('healthState') in broken_unhealthy_states
    or post_broken_observed_props.get('runningState') in broken_running_states
)
post_broken_inactive_after_explicit_deactivate = post_broken_observed is not None and (
    post_broken_observed_props.get('active') is False
    and post_broken_observed_props.get('replicas') == 0
    and post_broken_observed_props.get('runningState') == 'Stopped'
    and image_tag(post_broken_observed_props.get('template', {}).get('containers', [{}])[0].get('image', '')) == 'v-broken'
)
post_broken_no_h2_pull_success = not post_broken_success_rows
post_broken_not_retroactively_repaired = post_broken_failure_persists or (
    post_broken_inactive_after_explicit_deactivate and post_broken_no_h2_pull_success
)

pre_http_tag = h1_payload.get('http_response', {}).get('body_json', {}).get('build_tag')
post_http_tag = h2_payload.get('http_response', {}).get('body_json', {}).get('build_tag')

baseline_revision_healthy_pre = pre_baseline_revision is not None and pre_baseline_revision.get('properties', {}).get('healthState') == 'Healthy'
baseline_revision_healthy_post = post_baseline_revision is not None and post_baseline_revision.get('properties', {}).get('healthState') == 'Healthy'
workload_silence_revision_same = pre_baseline_revision is not None and pre_baseline_revision.get('name') == baseline_revision_name

pre_norm = {
    'container_app': {
        'name': pre_app.get('name'),
        'resource_group': pre_app.get('resourceGroup'),
        'revision': {
            'latest_ready_revision_name': pre_app.get('properties', {}).get('latestReadyRevisionName'),
            'latest_revision_name': pre_app.get('properties', {}).get('latestRevisionName'),
            'target_revision_name': pre_broken_revision.get('name') if pre_broken_revision else None,
            'target_image': pre_broken_revision.get('properties', {}).get('template', {}).get('containers', [{}])[0].get('image') if pre_broken_revision else None,
        },
        'container': {
            'name': pre_container.get('name'),
            'cpu': pre_container.get('resources', {}).get('cpu'),
            'memory': pre_container.get('resources', {}).get('memory'),
            'image_repository': pre_container.get('image', '').split(':')[0] if pre_container.get('image') else None,
            'acr_login_server': metadata.get('acr_login_server'),
        },
        'ingress': {
            'external': pre_ingress.get('external'),
            'target_port': pre_ingress.get('targetPort'),
        },
        'scale': {
            'min_replicas': pre_scale.get('minReplicas'),
            'max_replicas': pre_scale.get('maxReplicas'),
        },
    },
    'acr': {
        'publicNetworkAccess': acr_pre.get('publicNetworkAccess'),
        'networkRuleBypassOptions': acr_pre.get('networkRuleBypassOptions'),
        'defaultAction': acr_pre.get('networkRuleSet', {}).get('defaultAction'),
        'fw_pip_allowlisted': fw_pip_in_pre_rules,
    },
    'firewall': {
        'public_ip': fw_pip,
        'private_ip': firewall_private_ip,
        'policy_id': firewall_pre.get('firewall', {}).get('policyId'),
    },
    'workload': {
        'build_tag': pre_http_tag,
        'healthy_cached_revision_name': baseline_revision_name,
    },
}

post_norm = {
    'container_app': {
        'name': post_app.get('name'),
        'resource_group': post_app.get('resourceGroup'),
        'revision': {
            'latest_ready_revision_name': post_app.get('properties', {}).get('latestReadyRevisionName'),
            'latest_revision_name': post_app.get('properties', {}).get('latestRevisionName'),
            'target_revision_name': post_recover_revision.get('name') if post_recover_revision else None,
            'target_image': post_recover_revision.get('properties', {}).get('template', {}).get('containers', [{}])[0].get('image') if post_recover_revision else None,
        },
        'container': {
            'name': post_container.get('name'),
            'cpu': post_container.get('resources', {}).get('cpu'),
            'memory': post_container.get('resources', {}).get('memory'),
            'image_repository': post_container.get('image', '').split(':')[0] if post_container.get('image') else None,
            'acr_login_server': post_metadata.get('acr_login_server'),
        },
        'ingress': {
            'external': post_ingress.get('external'),
            'target_port': post_ingress.get('targetPort'),
        },
        'scale': {
            'min_replicas': post_scale.get('minReplicas'),
            'max_replicas': post_scale.get('maxReplicas'),
        },
    },
    'acr': {
        'publicNetworkAccess': acr_post.get('publicNetworkAccess'),
        'networkRuleBypassOptions': acr_post.get('networkRuleBypassOptions'),
        'defaultAction': acr_post.get('networkRuleSet', {}).get('defaultAction'),
        'fw_pip_allowlisted': fw_pip_in_post_rules,
    },
    'firewall': {
        'public_ip': post_metadata.get('firewall_public_ip'),
        'private_ip': post_metadata.get('firewall_private_ip'),
        'policy_id': post_payload.get('firewall', {}).get('policyId'),
    },
    'workload': {
        'build_tag': post_http_tag,
        'healthy_cached_revision_name': baseline_revision_name,
    },
}

flattened_pre = flatten_json('', pre_norm)
flattened_post = flatten_json('', post_norm)
overlap_paths = sorted(set(flattened_pre) & set(flattened_post))
overlap_diff_map = {path: {'pre_value': flattened_pre[path], 'post_value': flattened_post[path]} for path in overlap_paths if flattened_pre[path] != flattened_post[path]}
overlap_same_map = {path: flattened_pre[path] for path in overlap_paths if flattened_pre[path] == flattened_post[path]}
allowed_expected_diff_paths = {
    'acr.fw_pip_allowlisted',
    'container_app.revision.latest_ready_revision_name',
    'container_app.revision.latest_revision_name',
    'container_app.revision.target_image',
    'container_app.revision.target_revision_name',
    'workload.build_tag',
}
unexpected_overlap_diffs = {path: value for path, value in overlap_diff_map.items() if path not in allowed_expected_diff_paths}

held_constant_checks = {
    'acr_public_network_access_enabled': {
        'pre_value': acr_pre.get('publicNetworkAccess'),
        'post_value': acr_post.get('publicNetworkAccess'),
        'equal': acr_pre.get('publicNetworkAccess') == acr_post.get('publicNetworkAccess') == 'Enabled',
    },
    'acr_network_rule_bypass_none': {
        'pre_value': acr_pre.get('networkRuleBypassOptions'),
        'post_value': acr_post.get('networkRuleBypassOptions'),
        'equal': acr_pre.get('networkRuleBypassOptions') == acr_post.get('networkRuleBypassOptions') == 'None',
    },
    'acr_default_action_deny': {
        'pre_value': acr_pre.get('networkRuleSet', {}).get('defaultAction'),
        'post_value': acr_post.get('networkRuleSet', {}).get('defaultAction'),
        'equal': acr_pre.get('networkRuleSet', {}).get('defaultAction') == acr_post.get('networkRuleSet', {}).get('defaultAction') == 'Deny',
    },
    'acr_name': {
        'pre_value': metadata.get('acr_name'),
        'post_value': post_metadata.get('acr_name'),
        'equal': metadata.get('acr_name') == post_metadata.get('acr_name'),
    },
    'container_app_name': {
        'pre_value': pre_app.get('name'),
        'post_value': post_app.get('name'),
        'equal': pre_app.get('name') == post_app.get('name'),
    },
    'resource_group': {
        'pre_value': pre_app.get('resourceGroup'),
        'post_value': post_app.get('resourceGroup'),
        'equal': pre_app.get('resourceGroup') == post_app.get('resourceGroup'),
    },
    'container_name': {
        'pre_value': pre_container.get('name'),
        'post_value': post_container.get('name'),
        'equal': pre_container.get('name') == post_container.get('name'),
    },
    'image_repository': {
        'pre_value': pre_container.get('image', '').split(':')[0] if pre_container.get('image') else None,
        'post_value': post_container.get('image', '').split(':')[0] if post_container.get('image') else None,
        'equal': (pre_container.get('image', '').split(':')[0] if pre_container.get('image') else None) == (post_container.get('image', '').split(':')[0] if post_container.get('image') else None),
    },
    'cpu': {
        'pre_value': pre_container.get('resources', {}).get('cpu'),
        'post_value': post_container.get('resources', {}).get('cpu'),
        'equal': pre_container.get('resources', {}).get('cpu') == post_container.get('resources', {}).get('cpu'),
    },
    'memory': {
        'pre_value': pre_container.get('resources', {}).get('memory'),
        'post_value': post_container.get('resources', {}).get('memory'),
        'equal': pre_container.get('resources', {}).get('memory') == post_container.get('resources', {}).get('memory'),
    },
    'ingress_target_port': {
        'pre_value': pre_ingress.get('targetPort'),
        'post_value': post_ingress.get('targetPort'),
        'equal': pre_ingress.get('targetPort') == post_ingress.get('targetPort'),
    },
    'min_replicas': {
        'pre_value': pre_scale.get('minReplicas'),
        'post_value': post_scale.get('minReplicas'),
        'equal': pre_scale.get('minReplicas') == post_scale.get('minReplicas'),
    },
    'max_replicas': {
        'pre_value': pre_scale.get('maxReplicas'),
        'post_value': post_scale.get('maxReplicas'),
        'equal': pre_scale.get('maxReplicas') == post_scale.get('maxReplicas'),
    },
    'firewall_public_ip': {
        'pre_value': fw_pip,
        'post_value': post_metadata.get('firewall_public_ip'),
        'equal': fw_pip == post_metadata.get('firewall_public_ip'),
    },
    'firewall_private_ip': {
        'pre_value': firewall_private_ip,
        'post_value': post_metadata.get('firewall_private_ip'),
        'equal': firewall_private_ip == post_metadata.get('firewall_private_ip'),
    },
}

explicit_drops = [
    {'id': 'acr_firewall_internal_retry_schedule', 'note': 'The pack proves failure before fix and recovery after fix, not the exact internal retry cadence for the failed puller.'},
    {'id': 'exact_pull_duration_milliseconds', 'note': 'The pack proves success-versus-failure, not the exact duration of every layer download.'},
    {'id': 'firewall_application_log_ingestion_latency', 'note': 'This pack relies on Container Apps and ACR surfaces, not the exact second that every firewall diagnostic row lands.'},
    {'id': 'image_layer_sha', 'note': 'The pack proves tag-level image identity, not immutable OCI digests.'},
    {'id': 'pod_uid', 'note': 'The pack reasons at the revision/workload-response layer, not the Kubernetes pod UID layer.'},
    {'id': 'replica_suffix_continuity', 'note': 'Replica suffixes are scheduler-generated and are not part of the causal claim.'},
    {'id': 'revision_suffix_identity', 'note': 'Revision suffixes change by design on each deployment and are treated only as fresh-pull markers.'},
    {'id': 'workload_source_ip_component_identity', 'note': 'The evidence proves the firewall public IP that ACR rejected, not the exact internal ACA component identity behind the pull attempt.'},
]
runtime_drop_ids = frozenset(item['id'] for item in explicit_drops)

anchor_consistency = {
    'resource_group': {
        'pre_value': metadata.get('resource_group'),
        'post_value': post_metadata.get('resource_group'),
        'equal': metadata.get('resource_group') == post_metadata.get('resource_group') == resource_group,
    },
    'container_app': {
        'pre_value': metadata.get('app_name'),
        'post_value': post_metadata.get('app_name'),
        'equal': metadata.get('app_name') == post_metadata.get('app_name') == app_name,
    },
    'acr_name': {
        'pre_value': metadata.get('acr_name'),
        'post_value': post_metadata.get('acr_name'),
        'equal': metadata.get('acr_name') == post_metadata.get('acr_name') == acr_name,
    },
    'firewall_public_ip': {
        'pre_value': metadata.get('firewall_public_ip'),
        'post_value': post_metadata.get('firewall_public_ip'),
        'equal': metadata.get('firewall_public_ip') == post_metadata.get('firewall_public_ip') == fw_pip,
    },
}

subgate_14a_pass = not parse_errors
subgate_14b_pass = strong_temporal or fallback_temporal
subgate_14c_pass = both_parse_ok and pre_post_lineage_equal
subgate_14d_pass = all(item['equal'] for item in anchor_consistency.values())
subgate_14e_pass = not unexpected_non_junk and observed_xrefs == expected_xrefs and all(info['time_source'] for info in all_anchor_infos.values())
gate_14_all_subgates_pass = all([subgate_14a_pass, subgate_14b_pass, subgate_14c_pass, subgate_14d_pass, subgate_14e_pass])

subgate_15a_pass = bool(baseline_pulling_rows) and bool(baseline_pulled_rows)
subgate_15b_pass = acr_pre.get('publicNetworkAccess') == 'Enabled' and acr_pre.get('networkRuleBypassOptions') == 'None' and acr_pre.get('networkRuleSet', {}).get('defaultAction') == 'Deny' and not fw_pip_in_pre_rules and pre_ip_rules == []
subgate_15c_pass = bool(pre_denied_rows) and bool(pre_vbroken_rows) and fw_pip in json.dumps(pre_denied_rows[0])
subgate_15d_pass = pre_broken_failed
subgate_15e_pass = pre_http_tag == 'v1' and baseline_revision_healthy_pre and workload_silence_revision_same
gate_15_all_subgates_pass = all([subgate_15a_pass, subgate_15b_pass, subgate_15c_pass, subgate_15d_pass, subgate_15e_pass])

subgate_16a_pass = acr_post.get('publicNetworkAccess') == 'Enabled' and acr_post.get('networkRuleBypassOptions') == 'None' and acr_post.get('networkRuleSet', {}).get('defaultAction') == 'Deny' and fw_pip_in_post_rules and len(post_ip_rules) == 1
subgate_16b_pass = post_recover_revision is not None and post_recover_props.get('healthState') == 'Healthy' and post_recover_props.get('active') is True and post_latest_revision is not None and post_latest_revision.get('name') == post_recover_revision.get('name')
subgate_16c_pass = bool(post_pulling_rows) and bool(post_pulled_rows) and post_http_tag == 'v-recover'
subgate_16d_pass = post_broken_not_retroactively_repaired
gate_16_all_subgates_pass = all([subgate_16a_pass, subgate_16b_pass, subgate_16c_pass, subgate_16d_pass])

subgate_17a_pass = h1_payload.get('zero_successful_pulls_for_v_broken') is True and subgate_15a_pass
subgate_17b_pass = len(post_pulled_rows) > 0
subgate_17c_pass = workload_silence_revision_same and baseline_revision_healthy_pre and pre_http_tag == 'v1'
subgate_17d_pass = all(item['equal'] for item in held_constant_checks.values()) and not unexpected_overlap_diffs and runtime_drop_ids == DOCUMENTED_EXPLICIT_DROPS_CEILING and post_broken_not_retroactively_repaired
gate_17_all_subgates_pass = all([subgate_17a_pass, subgate_17b_pass, subgate_17c_pass, subgate_17d_pass])

gate14 = {
    'claim': f'The 12-file acr-network-path-firewall-allowlist raw cohort is internally consistent: every canonical file is present and parseable, the anchor timestamps stay inside one bounded UTC capture window, the pre/post revision IDs parse to the same {resource_group} / {app_name} lineage, and the four cohort anchors (resource group, container app, ACR, firewall public IP) compare equal across H1 and H2.',
    'claim_level': 'Observed',
    'gate_classification': 'Cohort integrity gate: structural pre-condition for the bounded-falsification pack.',
    'hypothesis': 'H_cohort_integrity',
    'path_used': path_used,
    'predicate_inputs': {
        'app_spec_pre': repo_rel('01-app-spec-pre-fix.json'),
        'revision_list_pre': repo_rel('02-revision-list-pre-fix.json'),
        'acr_rules_pre': repo_rel('03-acr-network-rules-pre-fix.json'),
        'acr_rules_post': repo_rel('09-acr-network-rules-post-fix.json'),
        'app_spec_post': repo_rel('11-app-spec-post-fix.json'),
        'evidence_readme': repo_rel('README.md'),
    },
    'acr_network_path_firewall_allowlist_h_cohort_integrity_all_subgates_pass': gate_14_all_subgates_pass,
    'acr_network_path_firewall_allowlist_h_cohort_integrity_sub_gates': {
        'a_canonical_raw_files_present_and_parse': subgate_14a_pass,
        'b_every_per_file_utc_anchor_falls_within_one_bounded_window': subgate_14b_pass,
        'c_revision_id_lineage_parses_and_compares_equal': subgate_14c_pass,
        'd_four_anchor_identifiers_compare_equal': subgate_14d_pass,
        'e_readme_xrefs_no_extras_and_time_source_disclosure_hold': subgate_14e_pass,
    },
    'scenario': 'acr_network_path_firewall_allowlist',
    'sub_gates': [
        {
            'claim': 'All 12 canonical raw evidence files exist and parse as JSON or YAML.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in RAW_FILES],
            'observed_values': {
                'observed_missing': [name for name in RAW_FILES if not (EVIDENCE_DIR / name).is_file()],
                'observed_present_count': sum((EVIDENCE_DIR / name).is_file() for name in RAW_FILES),
                'parse_errors': parse_errors,
                'strong': {'expected_count': 12, 'holds': not parse_errors},
                'fallback': {'expected_count': 12, 'holds': not parse_errors},
            },
            'predicate': 'Strong and fallback both require the full 12-file raw cohort to exist; 01,02,03,04,05,06,08,09,10,11,12 parse as JSON; 07 parses as YAML.',
            'result': 'pass' if subgate_14a_pass else 'fail',
            'sub_gate': 'a_canonical_raw_files_present_and_parse',
        },
        {
            'claim': 'Every per-file UTC anchor stays inside one coherent capture window and every post-fix anchor is later than every pre-fix anchor.',
            'claim_level': 'Measured',
            'evidence_files': [repo_rel(name) for name in RAW_FILES],
            'observed_values': {
                'utc_window_start': utc_window_start.isoformat(),
                'utc_window_end': utc_window_end.isoformat(),
                'utc_window_span_seconds': utc_window_span_seconds,
                'monotonic_ordering_holds': monotonic_ordering_holds,
                'pre_anchor_timestamps': {name: {'timestamp_utc': info['timestamp_utc'], 'time_source': info['time_source'], 'raw_epoch': info['raw_epoch']} for name, info in pre_anchor_infos.items()},
                'post_anchor_timestamps': {name: {'timestamp_utc': info['timestamp_utc'], 'time_source': info['time_source'], 'raw_epoch': info['raw_epoch']} for name, info in post_anchor_infos.items()},
                'sorted_anchor_sequence': sorted_anchor_sequence,
                'strict_pairwise_order_checks': monotonic_pairs,
                'strong': {'holds': strong_temporal, 'max_span_seconds': 1800},
                'fallback': {'holds': fallback_temporal, 'max_span_seconds': 5400},
                'time_source_summary': time_source_summary,
            },
            'predicate': 'All configured post-fix anchors are strictly later than the configured pre-fix anchors, and the total window is <= 1800 seconds on the strong path or <= 5400 seconds on the fallback path.',
            'result': 'pass' if subgate_14b_pass else 'fail',
            'sub_gate': 'b_every_per_file_utc_anchor_falls_within_one_bounded_window',
        },
        {
            'claim': 'The broken v-broken revision and recovered v-recover revision parse to the same resource-group/container-app lineage.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('02-revision-list-pre-fix.json'), repo_rel('10-revision-list-post-fix.json')],
            'observed_values': {
                'pre_revision_id': pre_revision_id,
                'post_revision_id': post_revision_id,
                'pre_parse_ok': pre_parse_ok,
                'post_parse_ok': post_parse_ok,
                'pre_resource_group': pre_revision_parts['resource_group'],
                'post_resource_group': post_revision_parts['resource_group'],
                'pre_container_app': pre_revision_parts['container_app'],
                'post_container_app': post_revision_parts['container_app'],
                'pre_post_rg_equal': pre_post_rg_equal,
                'pre_post_app_equal': pre_post_app_equal,
                'pre_post_lineage_equal': pre_post_lineage_equal,
            },
            'predicate': 'The v-broken revision ID in 02 and the v-recover revision ID in 10 both match the /subscriptions/.../resourceGroups/.../containerApps/.../revisions/... regex, and the parsed resourceGroup + containerApp components compare equal only when both parses succeed.',
            'result': 'pass' if subgate_14c_pass else 'fail',
            'sub_gate': 'c_revision_id_lineage_parses_and_compares_equal',
        },
        {
            'claim': 'The four cohort anchors compare equal across H1 and H2.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('01-app-spec-pre-fix.json'), repo_rel('04-firewall-metadata-pre-fix.json'), repo_rel('11-app-spec-post-fix.json')],
            'observed_values': anchor_consistency,
            'predicate': 'resource_group, container_app, acr_name, and firewall_public_ip compare equal across 01 and 11 metadata surfaces.',
            'result': 'pass' if subgate_14d_pass else 'fail',
            'sub_gate': 'd_four_anchor_identifiers_compare_equal',
        },
        {
            'claim': 'No unexpected evidence extras exist, the README names all four gate files literally, and every anchor carries an explicit time_source disclosure.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('README.md')],
            'observed_values': {
                'expected_xrefs': expected_xrefs,
                'observed_xrefs': observed_xrefs,
                'observed_files_on_disk': observed_files_on_disk,
                'observed_non_junk_extras': unexpected_non_junk,
                'time_source_summary': time_source_summary,
            },
            'predicate': 'extras == [] AND evidence/README.md contains the four gate filenames literally AND every anchor timestamp discloses a time_source.',
            'result': 'pass' if subgate_14e_pass else 'fail',
            'sub_gate': 'e_readme_xrefs_no_extras_and_time_source_disclosure_hold',
        },
    ],
    'thresholds': {
        'canonical_count_strong': 12,
        'canonical_count_fallback_floor': 12,
        'utc_window_span_strong_seconds_max': 1800,
        'utc_window_span_fallback_seconds_max': 5400,
    },
    'utc_captured': UTC_NOW,
}

gate15 = {
    'claim': f'The H1 trigger produced the documented Path A failure surface on {app_name}: the baseline window already proved the allow-listed path produced successful pull markers, the pre-fix ACR rule set removed the firewall public IP while ACR stayed locked down, the broken v-broken pull emitted DENIED/403 evidence naming {fw_pip}, the v-broken revision entered a failed state, and the already-cached {baseline_revision_name} revision kept serving build_tag=v1 during the broken window.',
    'claim_level': 'Observed',
    'gate_classification': 'H1 gate: confirms that removing the firewall public IP from ACR ipRules forced a fresh-pull failure without degrading the already-cached v1 revision.',
    'hypothesis': 'H1_trigger_produces_failure',
    'path_used': 'single',
    'predicate_inputs': {
        'baseline_success_window': repo_rel('05-baseline-success-window.json'),
        'acr_rules_pre': repo_rel('03-acr-network-rules-pre-fix.json'),
        'system_logs_pre': repo_rel('06-system-logs-pre-fix.json'),
        'h1_failure_window': repo_rel('08-h1-failure-window.json'),
        'revision_list_pre': repo_rel('02-revision-list-pre-fix.json'),
    },
    'acr_network_path_firewall_allowlist_h1_trigger_produces_failure_all_subgates_pass': gate_15_all_subgates_pass,
    'acr_network_path_firewall_allowlist_h1_trigger_produces_failure_sub_gates': {
        'a_baseline_presence_proves_success_markers_exist_when_fw_pip_is_allowlisted': subgate_15a_pass,
        'b_acr_stays_locked_down_while_fw_pip_is_removed': subgate_15b_pass,
        'c_h1_window_contains_denied_403_for_v_broken_naming_the_firewall_public_ip': subgate_15c_pass,
        'd_v_broken_revision_enters_a_failed_state': subgate_15d_pass,
        'e_cached_v1_revision_keeps_serving_during_the_broken_window': subgate_15e_pass,
    },
    'scenario': 'acr_network_path_firewall_allowlist',
    'sub_gates': [
        {
            'claim': 'The baseline window proves the allow-listed path emits successful pull markers.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('05-baseline-success-window.json')],
            'observed_values': {
                'baseline_revision_name': baseline_revision_name,
                'pulling_rows_preview': baseline_pulling_rows[:5],
                'pulled_rows_preview': baseline_pulled_rows[:5],
                'baseline_window_start_utc': baseline_payload.get('window_start_utc'),
                'baseline_window_end_utc': baseline_payload.get('window_end_utc'),
            },
            'predicate': 'At least one baseline PullingImage row and at least one baseline PulledImage row exist for the captured baseline revision.',
            'result': 'pass' if subgate_15a_pass else 'fail',
            'sub_gate': 'a_baseline_presence_proves_success_markers_exist_when_fw_pip_is_allowlisted',
        },
        {
            'claim': 'The pre-fix ACR rule set removed the firewall public IP while ACR stayed publicly reachable but locked down.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('03-acr-network-rules-pre-fix.json')],
            'observed_values': {
                'publicNetworkAccess': acr_pre.get('publicNetworkAccess'),
                'networkRuleBypassOptions': acr_pre.get('networkRuleBypassOptions'),
                'defaultAction': acr_pre.get('networkRuleSet', {}).get('defaultAction'),
                'ipRules': pre_ip_rules,
                'firewall_public_ip': fw_pip,
            },
            'predicate': "03.publicNetworkAccess == 'Enabled' AND 03.networkRuleBypassOptions == 'None' AND 03.networkRuleSet.defaultAction == 'Deny' AND 03.networkRuleSet.ipRules == [].",
            'result': 'pass' if subgate_15b_pass else 'fail',
            'sub_gate': 'b_acr_stays_locked_down_while_fw_pip_is_removed',
        },
        {
            'claim': 'The broken H1 window contains DENIED/403 evidence for v-broken that names the firewall public IP.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-system-logs-pre-fix.json'), repo_rel('08-h1-failure-window.json')],
            'observed_values': {
                'denied_rows_preview': pre_denied_rows[:5],
                'v_broken_rows_preview': pre_vbroken_rows[:5],
                'firewall_public_ip': fw_pip,
                'h1_trigger_ts_utc': h1_payload.get('h1_trigger_ts_utc'),
            },
            'predicate': 'At least one H1 row contains the DENIED message naming the firewall public IP, and at least one H1 row references v-broken in the same broken window.',
            'result': 'pass' if subgate_15c_pass else 'fail',
            'sub_gate': 'c_h1_window_contains_denied_403_for_v_broken_naming_the_firewall_public_ip',
        },
        {
            'claim': 'The v-broken revision enters a failed state during H1.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('02-revision-list-pre-fix.json')],
            'observed_values': {
                'broken_revision_name': broken_revision_name,
                'broken_revision': pre_broken_revision,
                'pre_broken_failed': pre_broken_failed,
            },
            'predicate': "The v-broken revision's provisioningState is Failed/ProvisioningFailed OR its healthState is Unhealthy/None OR its runningState is Failed/NotRunning/Degraded.",
            'result': 'pass' if subgate_15d_pass else 'fail',
            'sub_gate': 'd_v_broken_revision_enters_a_failed_state',
        },
        {
            'claim': 'The cached v1 revision keeps serving during the broken window.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('02-revision-list-pre-fix.json'), repo_rel('08-h1-failure-window.json')],
            'observed_values': {
                'baseline_revision_name': baseline_revision_name,
                'baseline_revision_healthy_pre': baseline_revision_healthy_pre,
                'http_response': h1_payload.get('http_response'),
                'workload_silence_revision_same': workload_silence_revision_same,
            },
            'predicate': "The captured baseline revision is Healthy in 02, the H1 / response returns build_tag='v1', and the cached revision name stays the same continuity anchor.",
            'result': 'pass' if subgate_15e_pass else 'fail',
            'sub_gate': 'e_cached_v1_revision_keeps_serving_during_the_broken_window',
        },
    ],
    'thresholds': {
        'baseline_presence_expected_min': 1,
        'expected_pre_fix_ip_rule_count': 0,
        'expected_pre_fix_public_network_access': 'Enabled',
    },
    'utc_captured': UTC_NOW,
}

gate16 = {
    'claim': f'The H2 fix restored fresh-pull recovery on {app_name}: the firewall public IP {fw_pip} is back in the ACR allowlist, the latest active v-recover revision is Healthy, the post-fix window contains PullingImage and PulledImage for v-recover with / returning build_tag=v-recover, and the earlier v-broken revision was not retroactively repaired after explicit deactivation.',
    'claim_level': 'Observed',
    'gate_classification': 'H2 gate: confirms recovery after re-adding the firewall public IP and deploying v-recover.',
    'hypothesis': 'H2_fix_restores_recovery',
    'path_used': 'single',
    'predicate_inputs': {
        'acr_rules_post': repo_rel('09-acr-network-rules-post-fix.json'),
        'revision_list_post': repo_rel('10-revision-list-post-fix.json'),
        'app_spec_post': repo_rel('11-app-spec-post-fix.json'),
        'h2_recovery_window': repo_rel('12-h2-recovery-window.json'),
    },
    'acr_network_path_firewall_allowlist_h2_fix_restores_recovery_all_subgates_pass': gate_16_all_subgates_pass,
    'acr_network_path_firewall_allowlist_h2_fix_restores_recovery_sub_gates': {
        'a_fw_pip_is_restored_as_the_only_acr_allowlist_entry': subgate_16a_pass,
        'b_latest_active_v_recover_revision_is_healthy': subgate_16b_pass,
        'c_post_fix_window_contains_successful_v_recover_pull_markers': subgate_16c_pass,
        'd_v_broken_revision_is_not_retroactively_repaired_after_explicit_deactivation': subgate_16d_pass,
    },
    'scenario': 'acr_network_path_firewall_allowlist',
    'sub_gates': [
        {
            'claim': 'The firewall public IP is restored as the only ACR allowlist entry.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('09-acr-network-rules-post-fix.json')],
            'observed_values': {
                'publicNetworkAccess': acr_post.get('publicNetworkAccess'),
                'networkRuleBypassOptions': acr_post.get('networkRuleBypassOptions'),
                'defaultAction': acr_post.get('networkRuleSet', {}).get('defaultAction'),
                'ipRules': post_ip_rules,
                'firewall_public_ip': fw_pip,
            },
            'predicate': "09.publicNetworkAccess == 'Enabled' AND 09.networkRuleBypassOptions == 'None' AND 09.defaultAction == 'Deny' AND 09.ipRules == [fw_pip].",
            'result': 'pass' if subgate_16a_pass else 'fail',
            'sub_gate': 'a_fw_pip_is_restored_as_the_only_acr_allowlist_entry',
        },
        {
            'claim': 'The latest recovered v-recover revision is Healthy and active.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-revision-list-post-fix.json')],
            'observed_values': {
                'post_latest_revision': post_latest_revision,
                'post_recover_revision': post_recover_revision,
            },
            'predicate': "10 contains a revision whose image endswith ':v-recover', that revision has healthState == 'Healthy' and active == true, and it is the latest post-fix revision.",
            'result': 'pass' if subgate_16b_pass else 'fail',
            'sub_gate': 'b_latest_active_v_recover_revision_is_healthy',
        },
        {
            'claim': 'The post-fix recovery window contains successful v-recover pull markers and the workload reports build_tag=v-recover.',
            'claim_level': 'Measured',
            'evidence_files': [repo_rel('12-h2-recovery-window.json')],
            'observed_values': {
                'pulling_rows_preview': post_pulling_rows[:5],
                'pulled_rows_preview': post_pulled_rows[:5],
                'http_response': h2_payload.get('http_response'),
            },
            'predicate': "12 contains at least one PullingImage row and at least one PulledImage row for v-recover, and 12.http_response.body_json.build_tag == 'v-recover'.",
            'result': 'pass' if subgate_16c_pass else 'fail',
            'sub_gate': 'c_post_fix_window_contains_successful_v_recover_pull_markers',
        },
        {
            'claim': 'The v-broken revision is not retroactively repaired after explicit deactivation and does not emit a successful PulledImage row in H2.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-revision-list-post-fix.json'), repo_rel('11-app-spec-post-fix.json'), repo_rel('12-h2-recovery-window.json')],
            'observed_values': {
                'post_broken_revision': post_broken_revision,
                'post_broken_snapshot': post_broken_snapshot,
                'post_broken_failure_persists': post_broken_failure_persists,
                'post_broken_inactive_after_explicit_deactivate': post_broken_inactive_after_explicit_deactivate,
                'post_broken_no_h2_pull_success': post_broken_no_h2_pull_success,
                'post_broken_not_retroactively_repaired': post_broken_not_retroactively_repaired,
                'post_broken_success_rows': post_broken_success_rows[:5],
            },
            'predicate': "The post-fix evidence proves either that the v-broken revision still carries a failed/unhealthy broken-pull state OR that the explicitly deactivated v-broken revision is inactive (active=false, replicas=0, runningState='Stopped', image endswith ':v-broken'), and no H2 PulledImage row references v-broken.",
            'result': 'pass' if subgate_16d_pass else 'fail',
            'sub_gate': 'd_v_broken_revision_is_not_retroactively_repaired_after_explicit_deactivation',
        },
    ],
    'thresholds': {
        'expected_post_fix_ip_rule_count': 1,
        'expected_post_fix_public_network_access': 'Enabled',
    },
    'utc_captured': UTC_NOW,
}

gate17 = {
    'claim': 'This evidence pack falsifies the Path A firewall-allowlist hypothesis within a bounded scope. Non-vacuous proof requires four observations together: baseline-presence (successful pull markers existed before the allowlist entry was removed), bypass-absence (the broken window produced zero successful v-broken pull markers and instead emitted DENIED/403 evidence naming the firewall public IP), recovery-presence (successful v-recover pull markers returned after the allowlist entry was restored), and workload-path silence (the H1 broken-window / response continued to report build_tag=v1 from the cached baseline path). The bounded claim is only that the single firewall public IP entry in ACR ipRules is the mechanically observable trigger field for this cohort.',
    'claim_level': 'Observed',
    'cohort_binding_note': {
        'claim_ceiling': 'The bounded claim is that the single firewall public IP entry in ACR networkRuleSet.ipRules is the mechanically observable trigger field controlling fresh-pull success in this one koreacentral cohort. The pack does NOT prove exact retry cadence, exact pull durations, OCI digests, pod continuity, replica suffix continuity, revision suffix identity, internal firewall ingestion latency, or the specific internal ACA component identity behind the pull attempt.',
        'explicit_drops': explicit_drops,
    },
    'gate_classification': 'Bounded falsification gate: isolates the ACR firewall allowlist entry as the trigger field while explicitly listing the claim ceiling and the cached-revision silence invariant.',
    'hypothesis': 'H3_bounded_falsification',
    'path_used': 'bounded',
    'predicate_inputs': {
        'baseline_success_window': repo_rel('05-baseline-success-window.json'),
        'h1_failure_window': repo_rel('08-h1-failure-window.json'),
        'acr_rules_pre': repo_rel('03-acr-network-rules-pre-fix.json'),
        'acr_rules_post': repo_rel('09-acr-network-rules-post-fix.json'),
        'h2_recovery_window': repo_rel('12-h2-recovery-window.json'),
    },
    'acr_network_path_firewall_allowlist_h3_bounded_falsification_all_subgates_pass': gate_17_all_subgates_pass,
    'acr_network_path_firewall_allowlist_h3_bounded_falsification_sub_gates': {
        'a_bypass_absence_is_real_only_because_baseline_presence_was_proven': subgate_17a_pass,
        'b_recovery_presence_restores_successful_pull_markers': subgate_17b_pass,
        'c_workload_silence_holds_on_the_cached_v1_revision': subgate_17c_pass,
        'd_only_the_documented_rule_and_revision_fields_change_and_the_claim_ceiling_is_static': subgate_17d_pass,
    },
    'scenario': 'acr_network_path_firewall_allowlist',
    'sub_gates': [
        {
            'claim': 'The H1 absence claim is non-vacuous only because the baseline window already proved successful pull markers existed while the firewall public IP was allow-listed.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('05-baseline-success-window.json'), repo_rel('08-h1-failure-window.json')],
            'observed_values': {
                'baseline_pulled_count': len(baseline_pulled_rows),
                'h1_zero_successful_pulls_for_v_broken': h1_payload.get('zero_successful_pulls_for_v_broken'),
                'baseline_window': {'start': baseline_payload.get('window_start_utc'), 'end': baseline_payload.get('window_end_utc')},
                'h1_trigger_ts_utc': h1_payload.get('h1_trigger_ts_utc'),
            },
            'predicate': 'baseline_pulled_count > 0 AND h1_zero_successful_pulls_for_v_broken == true.',
            'result': 'pass' if subgate_17a_pass else 'fail',
            'sub_gate': 'a_bypass_absence_is_real_only_because_baseline_presence_was_proven',
        },
        {
            'claim': 'The H2 recovery window restores successful v-recover pull markers.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('12-h2-recovery-window.json')],
            'observed_values': {
                'pulled_count': len(post_pulled_rows),
                'h2_recovery_ts_utc': h2_payload.get('h2_recovery_ts_utc'),
                'rows_preview': post_pulled_rows[:10],
            },
            'predicate': 'len(post_pulled_rows) > 0.',
            'result': 'pass' if subgate_17b_pass else 'fail',
            'sub_gate': 'b_recovery_presence_restores_successful_pull_markers',
        },
        {
            'claim': 'The workload path is silent during H1: the cached baseline path stayed healthy before the break and the broken-window / response continued to report build_tag=v1.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('02-revision-list-pre-fix.json'), repo_rel('08-h1-failure-window.json'), repo_rel('10-revision-list-post-fix.json')],
            'observed_values': {
                'baseline_revision_name': baseline_revision_name,
                'pre_baseline_revision': pre_baseline_revision,
                'post_baseline_revision': post_baseline_revision,
                'baseline_revision_healthy_pre': baseline_revision_healthy_pre,
                'http_response': h1_payload.get('http_response'),
            },
            'predicate': "The captured baseline revision is Healthy in 02 and 08.http_response.body_json.build_tag == 'v1', proving the cached v1 revision kept serving throughout H1.",
            'result': 'pass' if subgate_17c_pass else 'fail',
            'sub_gate': 'c_workload_silence_holds_on_the_cached_v1_revision',
        },
        {
            'claim': 'Only the documented rule/revision overlap fields change across H1 and H2, and the explicit claim ceiling stays static.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('03-acr-network-rules-pre-fix.json'), repo_rel('09-acr-network-rules-post-fix.json'), repo_rel('11-app-spec-post-fix.json')],
            'observed_values': {
                'held_constant_checks': held_constant_checks,
                'allowed_expected_diff_paths': sorted(allowed_expected_diff_paths),
                'overlap_diff_map': overlap_diff_map,
                'overlap_same_map': overlap_same_map,
                'unexpected_overlap_diffs': unexpected_overlap_diffs,
                'runtime_drop_ids': sorted(runtime_drop_ids),
                'documented_drop_ids': sorted(DOCUMENTED_EXPLICIT_DROPS_CEILING),
                'post_broken_failure_persists': post_broken_failure_persists,
                'post_broken_inactive_after_explicit_deactivate': post_broken_inactive_after_explicit_deactivate,
                'post_broken_no_h2_pull_success': post_broken_no_h2_pull_success,
                'post_broken_not_retroactively_repaired': post_broken_not_retroactively_repaired,
            },
            'predicate': 'All held_constant_checks compare equal, overlap diffs are limited to the documented rule/revision/build_tag fields, explicit_drops exactly match the documented ceiling, and the post-fix evidence shows the v-broken revision was not retroactively repaired.',
            'result': 'pass' if subgate_17d_pass else 'fail',
            'sub_gate': 'd_only_the_documented_rule_and_revision_fields_change_and_the_claim_ceiling_is_static',
        },
    ],
    'thresholds': {
        'baseline_presence_expected_min': 1,
        'h1_successful_pull_expected': 0,
        'h2_successful_pull_expected_min': 1,
    },
    'utc_captured': UTC_NOW,
}

gates = [
    (14, gate14, 'cohort integrity verified'),
    (15, gate15, 'H1 trigger produces failure verified'),
    (16, gate16, 'H2 fix restores recovery verified'),
    (17, gate17, 'bounded falsification verified'),
]

output_map = {
    14: EVIDENCE_DIR / '14-cohort-integrity-gate.json',
    15: EVIDENCE_DIR / '15-h1-trigger-produces-failure-gate.json',
    16: EVIDENCE_DIR / '16-h2-fix-restores-recovery-gate.json',
    17: EVIDENCE_DIR / '17-bounded-falsification-gate.json',
}

for gate_number, gate_data, _ in gates:
    output_map[gate_number].write_text(json.dumps(gate_data, indent=2) + '\n', encoding='utf-8')

for gate_number, gate_data, detail in gates:
    sub_gate_map = next(value for key, value in gate_data.items() if key.endswith('_sub_gates'))
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
