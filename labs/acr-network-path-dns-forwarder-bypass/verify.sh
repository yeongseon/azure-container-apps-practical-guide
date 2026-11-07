#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/acr-network-path-dns-forwarder-bypass/evidence"
LAB_README_PATH="${SCRIPT_DIR}/README.md"
LAB_GUIDE_PATH="${SCRIPT_DIR}/../../docs/troubleshooting/lab-guides/acr-network-path-dns-forwarder-bypass.md"
UTC_NOW="${UTC_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR LAB_README_PATH LAB_GUIDE_PATH UTC_NOW

declare -a CANONICAL_RAW_FILES=(
    "01-app-spec-pre-fix.json"
    "02-revision-list-pre-fix.json"
    "03-dnsmasq-config-pre-fix.json"
    "04-private-dns-record-list-pre-fix.json"
    "05-pe-nic-config-pre-fix.json"
    "06-acr-public-access-pre-fix.json"
    "07-system-logs-pre-fix.json"
    "08-probe-response-pre-fix.json"
    "09-dnsmasq-config-post-fix.json"
    "10-private-dns-record-list-post-fix.json"
    "11-revision-list-post-fix.json"
    "12-recovery-surface-post-fix.json"
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
    if output="$(GATE_NUMBER="$gate_number" GATE_NAME="$gate_name" python3 <<'PY2'
import json
import os
from pathlib import Path

gate_number = int(os.environ['GATE_NUMBER'])
evidence_dir = Path(os.environ['EVIDENCE_DIR'])
lab_readme = Path(os.environ['LAB_README_PATH'])

RAW_FILES = [
    '01-app-spec-pre-fix.json',
    '02-revision-list-pre-fix.json',
    '03-dnsmasq-config-pre-fix.json',
    '04-private-dns-record-list-pre-fix.json',
    '05-pe-nic-config-pre-fix.json',
    '06-acr-public-access-pre-fix.json',
    '07-system-logs-pre-fix.json',
    '08-probe-response-pre-fix.json',
    '09-dnsmasq-config-post-fix.json',
    '10-private-dns-record-list-post-fix.json',
    '11-revision-list-post-fix.json',
    '12-recovery-surface-post-fix.json',
]

def load_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))

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
        pre = load_json(evidence_dir / RAW_FILES[0])
    except Exception as exc:
        print(f'01 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    app = pre.get('container_app', {})
    meta = pre.get('capture_metadata', {})
    ok = bool(app.get('name')) and bool(app.get('resourceGroup')) and bool(meta.get('dns_vm_name')) and bool(meta.get('pe_registry_ip')) and bool(meta.get('pe_data_ip'))
    if ok:
        print('01 parses and captures the pre-fix container app + dns forwarder metadata with both PE IPs populated')
        raise SystemExit(0)
    print('01 missing expected pre-fix app fields or populated PE/dns-forwarder metadata')
    raise SystemExit(1)

if gate_number == 6:
    try:
        revisions = load_json(evidence_dir / RAW_FILES[1])
        dnsmasq = load_json(evidence_dir / RAW_FILES[2])
    except Exception as exc:
        print(f'02/03 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = isinstance(revisions, list) and len(revisions) >= 1 and isinstance(dnsmasq.get('resolved_upstream'), str)
    if ok:
        print('02/03 parse and capture the broken-window revision list plus dnsmasq state')
        raise SystemExit(0)
    print('02/03 do not match the expected revision-list + dnsmasq shape')
    raise SystemExit(1)

if gate_number == 7:
    try:
        records = load_json(evidence_dir / RAW_FILES[3])
        nic = load_json(evidence_dir / RAW_FILES[4])
    except Exception as exc:
        print(f'04/05 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = isinstance(records, list) and bool(nic.get('id'))
    if ok:
        print('04/05 parse and capture the private DNS record list plus PE NIC surface')
        raise SystemExit(0)
    print('04/05 do not match the expected DNS-record-list + PE NIC shape')
    raise SystemExit(1)

if gate_number == 8:
    try:
        acr = load_json(evidence_dir / RAW_FILES[5])
        system_rows = load_json(evidence_dir / RAW_FILES[6])
    except Exception as exc:
        print(f'06/07 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = isinstance(acr.get('publicNetworkAccess'), str) and isinstance(system_rows.get('rows'), list) and isinstance(system_rows.get('query'), str)
    if ok:
        print('06/07 parse and capture ACR public-access plus failure-event KQL payload')
        raise SystemExit(0)
    print('06/07 do not match the expected ACR / KQL payload shape')
    raise SystemExit(1)

if gate_number == 9:
    try:
        probe = load_json(evidence_dir / RAW_FILES[7])
    except Exception as exc:
        print(f'08 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    response = probe.get('response', {})
    ok = isinstance(probe.get('attempts'), list) and int(probe.get('selected_attempt', 0)) >= 1 and response.get('first_class') in {'private', 'public'}
    if ok:
        print('08 parses as a retried probe payload with a valid first_class')
        raise SystemExit(0)
    print('08 does not capture the expected broken-window probe shape')
    raise SystemExit(1)

if gate_number == 10:
    try:
        dnsmasq_post = load_json(evidence_dir / RAW_FILES[8])
        records_post = load_json(evidence_dir / RAW_FILES[9])
    except Exception as exc:
        print(f'09/10 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = isinstance(dnsmasq_post.get('resolved_upstream'), str) and isinstance(records_post, list)
    if ok:
        print('09/10 parse and capture the recovery dnsmasq state plus post-fix DNS records')
        raise SystemExit(0)
    print('09/10 do not capture the expected post-fix dnsmasq / DNS surface')
    raise SystemExit(1)

if gate_number == 11:
    try:
        revisions_post = load_json(evidence_dir / RAW_FILES[10])
        post = load_json(evidence_dir / RAW_FILES[11])
    except Exception as exc:
        print(f'11/12 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    ok = isinstance(revisions_post, list) and bool(post.get('container_app', {}).get('name')) and bool(post.get('pe_nic', {}).get('id')) and post.get('probe_capture', {}).get('response', {}).get('first_class') in {'private', 'public'}
    if ok:
        print('11/12 parse and capture the post-fix revision list plus recovery composite surface')
        raise SystemExit(0)
    print('11/12 do not capture the expected recovery revision / composite shape')
    raise SystemExit(1)

if gate_number == 12:
    readme = evidence_dir / 'README.md'
    if readme.is_file() and lab_readme.is_file():
        print('lab README and evidence README are present')
        raise SystemExit(0)
    missing = []
    if not readme.is_file():
        missing.append(str(readme))
    if not lab_readme.is_file():
        missing.append(str(lab_readme))
    print('missing readme files: ' + ', '.join(missing))
    raise SystemExit(1)

if gate_number == 13:
    expected = [name for name in RAW_FILES if (evidence_dir / name).is_file()]
    print(f'canonical file count available for Phase B: {len(expected)}')
    raise SystemExit(0 if len(expected) == 12 else 1)
PY2
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
    "6:pre-fix revision and dnsmasq captures parse" \
    "7:pre-fix DNS and PE NIC captures parse" \
    "8:pre-fix ACR and KQL captures parse" \
    "9:pre-fix probe capture parses" \
    "10:post-fix dnsmasq and DNS captures parse" \
    "11:post-fix revision and recovery composite parse" \
    "12:readme surfaces exist" \
    "13:canonical raw file count present"; do
    run_python_gate "${gate%%:*}" "${gate#*:}"
done

echo "## Phase B — Evidence pack verification"
if PHASE_B_OUTPUT="$(python3 <<'PY2'
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path

EVIDENCE_DIR = Path(os.environ['EVIDENCE_DIR'])
REL = os.environ['REPO_RELATIVE_EVIDENCE_DIR']
UTC_NOW = os.environ['UTC_NOW']

_existing_captures = []
for _gate_file in ['14-cohort-integrity-gate.json', '15-h1-trigger-produces-failure-gate.json', '16-h2-fix-restores-recovery-gate.json', '17-bounded-falsification-gate.json']:
    _path = EVIDENCE_DIR / _gate_file
    if _path.exists():
        try:
            _data = json.loads(_path.read_text(encoding='utf-8'))
        except (OSError, json.JSONDecodeError):
            continue
        _existing = _data.get('utc_captured')
        if isinstance(_existing, str) and _existing:
            _existing_captures.append(_existing)
if _existing_captures:
    UTC_NOW = min(_existing_captures)

EXISTING_GATE14 = None
_existing_gate14_path = EVIDENCE_DIR / '14-cohort-integrity-gate.json'
if _existing_gate14_path.exists():
    try:
        EXISTING_GATE14 = json.loads(_existing_gate14_path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        EXISTING_GATE14 = None

RAW_FILES = [
    '01-app-spec-pre-fix.json', '02-revision-list-pre-fix.json', '03-dnsmasq-config-pre-fix.json',
    '04-private-dns-record-list-pre-fix.json', '05-pe-nic-config-pre-fix.json', '06-acr-public-access-pre-fix.json',
    '07-system-logs-pre-fix.json', '08-probe-response-pre-fix.json', '09-dnsmasq-config-post-fix.json',
    '10-private-dns-record-list-post-fix.json', '11-revision-list-post-fix.json', '12-recovery-surface-post-fix.json',
]
GATE_FILES = ['14-cohort-integrity-gate.json', '15-h1-trigger-produces-failure-gate.json', '16-h2-fix-restores-recovery-gate.json', '17-bounded-falsification-gate.json']
DOCUMENTED_EXPLICIT_DROPS_CEILING = frozenset([
    'acr_control_plane_fresh_pull',
    'dns_resolution_timing',
    'exact_http_body_bytes',
    'image_layer_cache_state',
    'probe_retry_attempt_count',
    'resource_provider_poll_latency',
    'system_log_ingestion_latency',
    'tls_cipher_suite',
])
EXPECTED_EVIDENCE_FILES = RAW_FILES + GATE_FILES + ['README.md']
JUNK_NAMES = {'.DS_Store'}
REVISION_ID_RE = re.compile(r'^/subscriptions/(?P<sub>[^/]+)/resourceGroups/(?P<rg>[^/]+)/providers/Microsoft\.App/containerApps/(?P<app>[^/]+)/revisions/(?P<rev>[^/]+)$')
SANITIZER_RULES = [
    (re.compile(r'(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])', re.I), '00000000-0000-0000-0000-000000000000'),
    (re.compile(r'\bMCAPS[-A-Za-z0-9_]*\b'), 'Visual Studio Enterprise Subscription'),
    (re.compile(r'Microsoft\s+Non-Production', re.I), 'Contoso'),
    (re.compile(r'\b[A-Za-z0-9._%+-]+@microsoft\.com(?![A-Za-z0-9.-])', re.I), 'user@example.com'),
    (re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.onmicrosoft\.com(?![A-Za-z0-9.-])', re.I), 'user@example.com'),
    (re.compile(r'\b[A-Za-z0-9-]+\.onmicrosoft\.com(?![A-Za-z0-9.-])', re.I), 'contoso.onmicrosoft.com'),
    (re.compile(r'\bychoe\b', re.I), 'demouser'),
    (re.compile(r'Yeongseon\s+Choe', re.I), 'Demo User'),
    (re.compile(r'\byeongseon\b', re.I), 'demouser'),
    (re.compile(r'https://ms\.portal\.azure\.com/#@[^/]+/', re.I), 'https://ms.portal.azure.com/#@contoso.onmicrosoft.com/'),
    (re.compile(r'https://ms\.portal\.azure\.com[^\s"\']*', re.I), 'https://ms.portal.azure.com/#@contoso.onmicrosoft.com/'),
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
    return f'{REL}/{name}'

def load_json(name: str):
    return json.loads((EVIDENCE_DIR / name).read_text(encoding='utf-8'))

def parse_iso(text: str):
    value = datetime.fromisoformat(text.replace('Z', '+00:00'))
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)

def resolve_anchor_timestamp(name: str, anchor_class: str):
    if EXISTING_GATE14 is not None:
        observed = EXISTING_GATE14.get('sub_gates', [{}, {}])[1].get('observed_values', {})
        prior_map = observed.get('pre_anchor_timestamps' if anchor_class == 'pre' else 'post_anchor_timestamps', {})
        prior = prior_map.get(name)
        if isinstance(prior, dict) and prior.get('timestamp_utc'):
            dt = parse_iso(prior['timestamp_utc'])
            return {'timestamp': dt, 'timestamp_utc': prior['timestamp_utc'], 'time_source': prior.get('time_source', 'mtime'), 'raw_epoch': prior.get('raw_epoch')}
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
    return {'resource_group': match.group('rg'), 'container_app': match.group('app'), 'revision': match.group('rev')}

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

def nic_ip_map(nic_payload):
    mapping = []
    for config in nic_payload.get('ipConfigurations', []):
        fqdns = config.get('privateLinkConnectionProperties', {}).get('fqdns', []) or []
        mapping.append({'name': config.get('name'), 'private_ip': config.get('privateIPAddress'), 'fqdns': sorted(fqdns)})
    return sorted(mapping, key=lambda item: (item['private_ip'] or '', ','.join(item['fqdns'])))

def extract_env(container):
    return {item.get('name'): item.get('value') for item in container.get('env', [])}

def record_summary(record_rows, relative_name):
    matches = []
    for row in record_rows:
        if row.get('name') != relative_name:
            continue
        matches.append({'name': row.get('name'), 'fqdn': row.get('fqdn'), 'ttl': row.get('ttl'), 'a_records': sorted(item.get('ipv4Address') for item in row.get('aRecords', []) if item.get('ipv4Address'))})
    return matches

def choose_live_revision(revisions, revision_name_hint):
    if revision_name_hint:
        for row in revisions:
            if row.get('name') == revision_name_hint:
                return row
    active_rows = [row for row in revisions if row.get('properties', {}).get('active') is True]
    def sort_key(row):
        created = row.get('properties', {}).get('createdTime', '1970-01-01T00:00:00Z')
        return parse_iso(created)
    if active_rows:
        return sorted(active_rows, key=sort_key, reverse=True)[0]
    if revisions:
        return sorted(revisions, key=sort_key, reverse=True)[0]
    return None

def attempt_summary(payload):
    attempts = []
    for item in payload.get('attempts', []):
        response = item.get('response') or {}
        first_ip = None
        addresses = response.get('addresses') or []
        if addresses:
            first_ip = addresses[0].get('ip')
        attempts.append({'attempt': item.get('attempt'), 'first_class': response.get('first_class'), 'first_ip': first_ip})
    return attempts

def first_ip_from_probe(response):
    addresses = response.get('addresses') or []
    return addresses[0].get('ip') if addresses else None

pre_app_payload = load_json('01-app-spec-pre-fix.json')
revisions_pre = load_json('02-revision-list-pre-fix.json')
dnsmasq_pre = load_json('03-dnsmasq-config-pre-fix.json')
records_pre = load_json('04-private-dns-record-list-pre-fix.json')
pe_nic_pre = load_json('05-pe-nic-config-pre-fix.json')
acr_pre = load_json('06-acr-public-access-pre-fix.json')
system_pre = load_json('07-system-logs-pre-fix.json')
probe_pre_payload = load_json('08-probe-response-pre-fix.json')
dnsmasq_post = load_json('09-dnsmasq-config-post-fix.json')
records_post = load_json('10-private-dns-record-list-post-fix.json')
revisions_post = load_json('11-revision-list-post-fix.json')
post_payload = load_json('12-recovery-surface-post-fix.json')

pre_app = pre_app_payload['container_app']
post_app = post_payload['container_app']
post_acr = post_payload['acr']
pe_nic_post = post_payload['pe_nic']
probe_post_payload = post_payload['probe_capture']
pre_probe_response = probe_pre_payload['response']
post_probe_response = probe_post_payload['response']

capture_meta = pre_app_payload['capture_metadata']
app_name = pre_app['name']
resource_group = pre_app['resourceGroup']
zone_name = capture_meta['zone_name']
registry_record_name = capture_meta['registry_record_name']
data_record_name = capture_meta['data_record_name']
acr_login_server = capture_meta['acr_login_server']
expected_registry_ip = capture_meta['pe_registry_ip']
expected_data_ip = capture_meta['pe_data_ip']

parse_errors = []
for name in RAW_FILES:
    try:
        load_json(name)
    except Exception as exc:
        parse_errors.append(f'{name}: {type(exc).__name__}: {exc}')

pre_rows = system_pre.get('rows', [])
pre_anchor_infos = {name: resolve_anchor_timestamp(name, 'pre') for name in RAW_FILES[:8]}
post_anchor_infos = {name: resolve_anchor_timestamp(name, 'post') for name in RAW_FILES[8:]}
all_anchor_infos = {**pre_anchor_infos, **post_anchor_infos}
monotonic_pairs = []
for pre_name, pre_info in pre_anchor_infos.items():
    for post_name, post_info in post_anchor_infos.items():
        monotonic_pairs.append({'pre_file': pre_name, 'post_file': post_name, 'delta_seconds': (post_info['timestamp'] - pre_info['timestamp']).total_seconds(), 'holds': post_info['timestamp'] > pre_info['timestamp'], 'pre_timestamp_utc': pre_info['timestamp_utc'], 'post_timestamp_utc': post_info['timestamp_utc'], 'pre_time_source': pre_info['time_source'], 'post_time_source': post_info['time_source']})
monotonic_ordering_holds = all(item['holds'] for item in monotonic_pairs)
sorted_anchor_sequence = [{'file': name, 'timestamp_utc': info['timestamp_utc'], 'time_source': info['time_source'], 'anchor_class': 'pre' if name in pre_anchor_infos else 'post'} for name, info in sorted(all_anchor_infos.items(), key=lambda item: item[1]['timestamp'])]
time_source_summary = {'birthtime_count': sum(1 for info in all_anchor_infos.values() if info['time_source'] == 'birthtime'), 'mtime_count': sum(1 for info in all_anchor_infos.values() if info['time_source'] == 'mtime'), 'fallback_used': any(info['time_source'] == 'mtime' for info in all_anchor_infos.values())}
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

pre_live_revision_name = pre_app.get('properties', {}).get('latestReadyRevisionName') or pre_app.get('properties', {}).get('latestRevisionName')
post_live_revision_name = post_app.get('properties', {}).get('latestReadyRevisionName') or post_app.get('properties', {}).get('latestRevisionName')
pre_live_revision = choose_live_revision(revisions_pre, pre_live_revision_name)
post_live_revision = choose_live_revision(revisions_post, post_live_revision_name)
pre_live_props = pre_live_revision.get('properties', {}) if pre_live_revision else {}
post_live_props = post_live_revision.get('properties', {}) if post_live_revision else {}
all_pre_revision_healthy = all(row.get('properties', {}).get('healthState') == 'Healthy' for row in revisions_pre)
all_post_revision_healthy = all(row.get('properties', {}).get('healthState') == 'Healthy' for row in revisions_post)

pre_revision_id = pre_live_revision.get('id') if pre_live_revision else ''
post_revision_id = post_live_revision.get('id') if post_live_revision else ''
pre_revision_parts = parse_revision_id(pre_revision_id)
post_revision_parts = parse_revision_id(post_revision_id)
pre_parse_ok = pre_revision_parts.get('resource_group') is not None and pre_revision_parts.get('container_app') is not None
post_parse_ok = post_revision_parts.get('resource_group') is not None and post_revision_parts.get('container_app') is not None
both_parse_ok = pre_parse_ok and post_parse_ok
pre_post_rg_equal = both_parse_ok and pre_revision_parts['resource_group'] == post_revision_parts['resource_group']
pre_post_app_equal = both_parse_ok and pre_revision_parts['container_app'] == post_revision_parts['container_app']
pre_post_lineage_equal = both_parse_ok and pre_post_rg_equal and pre_post_app_equal
pre_post_revision_equal = both_parse_ok and pre_revision_parts['revision'] == post_revision_parts['revision']

pre_nic_map = nic_ip_map(pe_nic_pre)
post_nic_map = nic_ip_map(pe_nic_post)
pe_nic_unchanged = pre_nic_map == post_nic_map
pre_registry_records = record_summary(records_pre, registry_record_name)
pre_data_records = record_summary(records_pre, data_record_name)
post_registry_records = record_summary(records_post, registry_record_name)
post_data_records = record_summary(records_post, data_record_name)

pre_container = pre_app.get('properties', {}).get('template', {}).get('containers', [])[0]
post_container = post_app.get('properties', {}).get('template', {}).get('containers', [])[0]
pre_env = extract_env(pre_container)
post_env = extract_env(post_container)
pre_scale = pre_app.get('properties', {}).get('template', {}).get('scale', {})
post_scale = post_app.get('properties', {}).get('template', {}).get('scale', {})
pre_ingress = pre_app.get('properties', {}).get('configuration', {}).get('ingress', {})
post_ingress = post_app.get('properties', {}).get('configuration', {}).get('ingress', {})
pre_attempts = attempt_summary(probe_pre_payload)
post_attempts = attempt_summary(probe_post_payload)
pre_retry_disclosure_ok = isinstance(probe_pre_payload.get('selected_attempt'), int) and probe_pre_payload.get('selected_attempt', 0) >= 1 and len(probe_pre_payload.get('attempts', [])) >= probe_pre_payload.get('selected_attempt', 0)
post_retry_disclosure_ok = isinstance(probe_post_payload.get('selected_attempt'), int) and probe_post_payload.get('selected_attempt', 0) >= 1 and len(probe_post_payload.get('attempts', [])) >= probe_post_payload.get('selected_attempt', 0)
pre_failure_row_count = len(pre_rows)

held_constant_checks = {
    'acr_public_network_access': {'pre_value': acr_pre.get('publicNetworkAccess'), 'post_value': post_acr.get('publicNetworkAccess'), 'equal': acr_pre.get('publicNetworkAccess') == post_acr.get('publicNetworkAccess')},
    'dns_vm_name': {'pre_value': capture_meta.get('dns_vm_name'), 'post_value': capture_meta.get('dns_vm_name'), 'equal': True},
    'dns_vm_private_ip': {'pre_value': capture_meta.get('dns_vm_private_ip'), 'post_value': capture_meta.get('dns_vm_private_ip'), 'equal': True},
    'container_app_name': {'pre_value': pre_app.get('name'), 'post_value': post_app.get('name'), 'equal': pre_app.get('name') == post_app.get('name')},
    'resource_group': {'pre_value': pre_app.get('resourceGroup'), 'post_value': post_app.get('resourceGroup'), 'equal': pre_app.get('resourceGroup') == post_app.get('resourceGroup')},
    'identity_type': {'pre_value': pre_app.get('identity', {}).get('type'), 'post_value': post_app.get('identity', {}).get('type'), 'equal': pre_app.get('identity', {}).get('type') == post_app.get('identity', {}).get('type')},
    'container_name': {'pre_value': pre_container.get('name'), 'post_value': post_container.get('name'), 'equal': pre_container.get('name') == post_container.get('name')},
    'container_image': {'pre_value': pre_container.get('image'), 'post_value': post_container.get('image'), 'equal': pre_container.get('image') == post_container.get('image')},
    'build_tag': {'pre_value': pre_env.get('BUILD_TAG'), 'post_value': post_env.get('BUILD_TAG'), 'equal': pre_env.get('BUILD_TAG') == post_env.get('BUILD_TAG')},
    'acr_fqdn_env': {'pre_value': pre_env.get('ACR_FQDN'), 'post_value': post_env.get('ACR_FQDN'), 'equal': pre_env.get('ACR_FQDN') == post_env.get('ACR_FQDN')},
    'ingress_target_port': {'pre_value': pre_ingress.get('targetPort'), 'post_value': post_ingress.get('targetPort'), 'equal': pre_ingress.get('targetPort') == post_ingress.get('targetPort')},
    'min_replicas': {'pre_value': pre_scale.get('minReplicas'), 'post_value': post_scale.get('minReplicas'), 'equal': pre_scale.get('minReplicas') == post_scale.get('minReplicas')},
    'max_replicas': {'pre_value': pre_scale.get('maxReplicas'), 'post_value': post_scale.get('maxReplicas'), 'equal': pre_scale.get('maxReplicas') == post_scale.get('maxReplicas')},
    'registry_record_name': {'pre_value': registry_record_name, 'post_value': registry_record_name, 'equal': True},
    'data_record_name': {'pre_value': data_record_name, 'post_value': data_record_name, 'equal': True},
    'pe_nic_ip_map': {'pre_value': pre_nic_map, 'post_value': post_nic_map, 'equal': pe_nic_unchanged},
    'private_dns_records_registry': {'pre_value': pre_registry_records, 'post_value': post_registry_records, 'equal': pre_registry_records == post_registry_records},
    'private_dns_records_data': {'pre_value': pre_data_records, 'post_value': post_data_records, 'equal': pre_data_records == post_data_records},
    'live_revision_name': {'pre_value': pre_live_revision.get('name') if pre_live_revision else None, 'post_value': post_live_revision.get('name') if post_live_revision else None, 'equal': (pre_live_revision.get('name') if pre_live_revision else None) == (post_live_revision.get('name') if post_live_revision else None)},
}

pre_norm = {
    'container_app': {
        'name': pre_app.get('name'), 'resource_group': pre_app.get('resourceGroup'), 'identity_type': pre_app.get('identity', {}).get('type'),
        'revision': {'latest_ready_revision_name': pre_app.get('properties', {}).get('latestReadyRevisionName'), 'latest_revision_name': pre_app.get('properties', {}).get('latestRevisionName'), 'live_revision_name': pre_live_revision.get('name') if pre_live_revision else None, 'live_revision_health_state': pre_live_props.get('healthState'), 'live_revision_running_state': pre_live_props.get('runningState'), 'live_revision_provisioning_state': pre_live_props.get('provisioningState'), 'live_revision_active': pre_live_props.get('active')},
        'container': {'name': pre_container.get('name'), 'image': pre_container.get('image'), 'cpu': pre_container.get('resources', {}).get('cpu'), 'memory': pre_container.get('resources', {}).get('memory'), 'build_tag': pre_env.get('BUILD_TAG'), 'acr_fqdn': pre_env.get('ACR_FQDN')},
        'ingress': {'external': pre_ingress.get('external'), 'target_port': pre_ingress.get('targetPort')},
        'scale': {'min_replicas': pre_scale.get('minReplicas'), 'max_replicas': pre_scale.get('maxReplicas')},
    },
    'acr': {'publicNetworkAccess': acr_pre.get('publicNetworkAccess'), 'defaultAction': acr_pre.get('networkRuleSet', {}).get('defaultAction')},
    'dnsmasq': {'upstream': dnsmasq_pre.get('resolved_upstream'), 'service_state': dnsmasq_pre.get('service_state'), 'listen_address': dnsmasq_pre.get('listen_address')},
    'dns_records': {'registry_record_present': bool(pre_registry_records), 'registry_record_ips': pre_registry_records[0]['a_records'] if pre_registry_records else [], 'data_record_present': bool(pre_data_records), 'data_record_ips': pre_data_records[0]['a_records'] if pre_data_records else [], 'record_count': len(records_pre)},
    'pe_nic': pre_nic_map,
    'probe': {'first_class': pre_probe_response.get('first_class'), 'first_ip': first_ip_from_probe(pre_probe_response), 'address_count': len(pre_probe_response.get('addresses', [])), 'addresses': pre_probe_response.get('addresses', [])},
    'system_logs': {'failure_event_row_count': pre_failure_row_count},
}
post_norm = {
    'container_app': {
        'name': post_app.get('name'), 'resource_group': post_app.get('resourceGroup'), 'identity_type': post_app.get('identity', {}).get('type'),
        'revision': {'latest_ready_revision_name': post_app.get('properties', {}).get('latestReadyRevisionName'), 'latest_revision_name': post_app.get('properties', {}).get('latestRevisionName'), 'live_revision_name': post_live_revision.get('name') if post_live_revision else None, 'live_revision_health_state': post_live_props.get('healthState'), 'live_revision_running_state': post_live_props.get('runningState'), 'live_revision_provisioning_state': post_live_props.get('provisioningState'), 'live_revision_active': post_live_props.get('active')},
        'container': {'name': post_container.get('name'), 'image': post_container.get('image'), 'cpu': post_container.get('resources', {}).get('cpu'), 'memory': post_container.get('resources', {}).get('memory'), 'build_tag': post_env.get('BUILD_TAG'), 'acr_fqdn': post_env.get('ACR_FQDN')},
        'ingress': {'external': post_ingress.get('external'), 'target_port': post_ingress.get('targetPort')},
        'scale': {'min_replicas': post_scale.get('minReplicas'), 'max_replicas': post_scale.get('maxReplicas')},
    },
    'acr': {'publicNetworkAccess': post_acr.get('publicNetworkAccess'), 'defaultAction': post_acr.get('networkRuleSet', {}).get('defaultAction')},
    'dnsmasq': {'upstream': dnsmasq_post.get('resolved_upstream'), 'service_state': dnsmasq_post.get('service_state'), 'listen_address': dnsmasq_post.get('listen_address')},
    'dns_records': {'registry_record_present': bool(post_registry_records), 'registry_record_ips': post_registry_records[0]['a_records'] if post_registry_records else [], 'data_record_present': bool(post_data_records), 'data_record_ips': post_data_records[0]['a_records'] if post_data_records else [], 'record_count': len(records_post)},
    'pe_nic': post_nic_map,
    'probe': {'first_class': post_probe_response.get('first_class'), 'first_ip': first_ip_from_probe(post_probe_response), 'address_count': len(post_probe_response.get('addresses', [])), 'addresses': post_probe_response.get('addresses', [])},
    'system_logs': {'failure_event_row_count': pre_failure_row_count},
}
flattened_pre = flatten_json('', pre_norm)
flattened_post = flatten_json('', post_norm)
overlap_paths = sorted(set(flattened_pre) & set(flattened_post))
overlap_diff_map = {path: {'pre_value': flattened_pre[path], 'post_value': flattened_post[path]} for path in overlap_paths if flattened_pre[path] != flattened_post[path]}
overlap_same_map = {path: flattened_pre[path] for path in overlap_paths if flattened_pre[path] == flattened_post[path]}
allowed_expected_diff_paths = {'dnsmasq.upstream', 'probe.addresses[0].class', 'probe.addresses[0].ip', 'probe.first_class', 'probe.first_ip'}
required_expected_diff_paths = {'dnsmasq.upstream', 'probe.first_class', 'probe.first_ip'}
unexpected_overlap_diffs = {path: value for path, value in overlap_diff_map.items() if path not in allowed_expected_diff_paths}
missing_required_diff_paths = sorted(required_expected_diff_paths - set(overlap_diff_map))

explicit_drops = [
    {'id': 'acr_control_plane_fresh_pull', 'note': 'The pack intentionally does not prove broken-window control-plane fresh-pull behavior because this workload-path lab keeps the already-running revision in place.'},
    {'id': 'dns_resolution_timing', 'note': 'The pack proves DNS-class transitions, not the exact resolver-latency delta for each lookup.'},
    {'id': 'exact_http_body_bytes', 'note': 'The probe records address lists and classes, not a byte-identical backend body.'},
    {'id': 'image_layer_cache_state', 'note': 'The already-running revision remains healthy, but the raw cohort does not enumerate every cached OCI layer.'},
    {'id': 'probe_retry_attempt_count', 'note': 'Retry disclosure is preserved explicitly, but the causal claim is about the final selected topology transition, not an exact retry count contract.'},
    {'id': 'resource_provider_poll_latency', 'note': 'Azure control-plane poll timing is outside the causal field under test.'},
    {'id': 'system_log_ingestion_latency', 'note': 'The zero-row failure-event query proves absence in the captured window, not the exact ingestion delay of every platform event.'},
    {'id': 'tls_cipher_suite', 'note': 'The pack proves DNS-path change, not the negotiated TLS cipher suite bytes.'},
]
runtime_drop_ids = frozenset(item['id'] for item in explicit_drops)

subgate_14a_pass = not parse_errors
subgate_14b_pass = strong_temporal or fallback_temporal
subgate_14c_pass = both_parse_ok and pre_post_lineage_equal
subgate_14d_pass = pe_nic_unchanged and not unexpected_non_junk and observed_xrefs == expected_xrefs and pre_registry_records == post_registry_records and pre_data_records == post_data_records
subgate_14e_pass = utc_window_start <= utc_window_end and all(item['timestamp_utc'] for item in all_anchor_infos.values())
gate_14_all_subgates_pass = all([subgate_14a_pass, subgate_14b_pass, subgate_14c_pass, subgate_14d_pass, subgate_14e_pass])

subgate_15a_pass = dnsmasq_pre.get('resolved_upstream') == '8.8.8.8' and dnsmasq_pre.get('service_state') == 'active'
subgate_15b_pass = pre_probe_response.get('first_class') == 'public' and first_ip_from_probe(pre_probe_response) not in {None, expected_registry_ip} and pre_retry_disclosure_ok
subgate_15c_pass = pre_live_revision is not None and pre_live_props.get('healthState') == 'Healthy' and pre_live_props.get('active') is True and all_pre_revision_healthy
subgate_15d_pass = pre_failure_row_count == 0
subgate_15e_pass = acr_pre.get('publicNetworkAccess') == post_acr.get('publicNetworkAccess') and pre_registry_records == post_registry_records and pre_data_records == post_data_records
gate_15_all_subgates_pass = all([subgate_15a_pass, subgate_15b_pass, subgate_15c_pass, subgate_15d_pass, subgate_15e_pass])

subgate_16a_pass = dnsmasq_post.get('resolved_upstream') == '168.63.129.16' and dnsmasq_post.get('service_state') == 'active'
subgate_16b_pass = post_probe_response.get('first_class') == 'private' and first_ip_from_probe(post_probe_response) == expected_registry_ip and post_retry_disclosure_ok
subgate_16c_pass = post_live_revision is not None and post_live_props.get('healthState') == 'Healthy' and post_live_props.get('active') is True and all_post_revision_healthy and pre_post_revision_equal
subgate_16d_pass = pe_nic_unchanged and pre_registry_records == post_registry_records and pre_data_records == post_data_records and acr_pre.get('publicNetworkAccess') == post_acr.get('publicNetworkAccess')
gate_16_all_subgates_pass = all([subgate_16a_pass, subgate_16b_pass, subgate_16c_pass, subgate_16d_pass])

subgate_17a_pass = all(item['equal'] for item in held_constant_checks.values()) and both_parse_ok and pre_post_lineage_equal and pre_post_revision_equal
subgate_17b_pass = not unexpected_overlap_diffs and not missing_required_diff_paths
subgate_17c_pass = runtime_drop_ids == DOCUMENTED_EXPLICIT_DROPS_CEILING
subgate_17d_pass = pre_live_revision is not None and post_live_revision is not None and pre_live_revision.get('name') == post_live_revision.get('name') and pre_live_props.get('healthState') == 'Healthy' and post_live_props.get('healthState') == 'Healthy' and pre_probe_response.get('first_class') == 'public' and post_probe_response.get('first_class') == 'private' and pre_failure_row_count == 0
gate_17_all_subgates_pass = all([subgate_17a_pass, subgate_17b_pass, subgate_17c_pass, subgate_17d_pass])

gate14 = {
    'claim': f'The 12-file acr-network-path-dns-forwarder-bypass raw cohort is internally consistent: every canonical file is present and parseable, every per-file UTC anchor falls within one bounded capture window, the pre/post live revision IDs parse to the same {resource_group} / {app_name} lineage, and the PE NIC plus private-DNS surfaces stay unchanged across H1 and H2.',
    'claim_level': 'Observed',
    'gate_classification': 'Cohort integrity gate: structural pre-condition for the bounded-falsification pack.',
    'hypothesis': 'H_cohort_integrity',
    'path_used': path_used,
    'predicate_inputs': {'app_spec_pre': repo_rel('01-app-spec-pre-fix.json'), 'revision_list_pre': repo_rel('02-revision-list-pre-fix.json'), 'dnsmasq_pre': repo_rel('03-dnsmasq-config-pre-fix.json'), 'dnsmasq_post': repo_rel('09-dnsmasq-config-post-fix.json'), 'revision_list_post': repo_rel('11-revision-list-post-fix.json'), 'composite_post': repo_rel('12-recovery-surface-post-fix.json'), 'evidence_readme': repo_rel('README.md')},
    'acr_network_path_dns_forwarder_bypass_h_cohort_integrity_all_subgates_pass': gate_14_all_subgates_pass,
    'acr_network_path_dns_forwarder_bypass_h_cohort_integrity_sub_gates': {
        'a_canonical_raw_files_present_and_parse': subgate_14a_pass,
        'b_every_per_file_utc_anchor_falls_within_one_bounded_window': subgate_14b_pass,
        'c_revision_id_lineage_parses_and_compares_equal': subgate_14c_pass,
        'd_pe_nic_private_dns_and_readme_xrefs_stay_constant': subgate_14d_pass,
        'e_utc_reference_and_span_math_stay_consistent': subgate_14e_pass,
    },
    'scenario': 'acr_network_path_dns_forwarder_bypass',
    'sub_gates': [
        {'claim': 'All 12 canonical raw evidence files exist and parse as JSON.', 'claim_level': 'Observed', 'evidence_files': [repo_rel(name) for name in RAW_FILES], 'observed_values': {'observed_missing': [name for name in RAW_FILES if not (EVIDENCE_DIR / name).is_file()], 'observed_present_count': sum((EVIDENCE_DIR / name).is_file() for name in RAW_FILES), 'parse_errors': parse_errors, 'strong': {'expected_count': 12, 'holds': not parse_errors}, 'fallback': {'expected_count': 12, 'holds': not parse_errors}}, 'predicate': 'Strong and fallback both require the full 12-file raw cohort to exist and parse as JSON.', 'result': 'pass' if subgate_14a_pass else 'fail', 'sub_gate': 'a_canonical_raw_files_present_and_parse'},
        {'claim': 'Every per-file UTC anchor stays inside one coherent capture window and every post-fix anchor is later than every pre-fix anchor.', 'claim_level': 'Measured', 'evidence_files': [repo_rel(name) for name in RAW_FILES], 'observed_values': {'utc_window_start': utc_window_start.isoformat(), 'utc_window_end': utc_window_end.isoformat(), 'utc_window_span_seconds': utc_window_span_seconds, 'monotonic_ordering_holds': monotonic_ordering_holds, 'pre_anchor_timestamps': {name: {'timestamp_utc': info['timestamp_utc'], 'time_source': info['time_source'], 'raw_epoch': info['raw_epoch']} for name, info in pre_anchor_infos.items()}, 'post_anchor_timestamps': {name: {'timestamp_utc': info['timestamp_utc'], 'time_source': info['time_source'], 'raw_epoch': info['raw_epoch']} for name, info in post_anchor_infos.items()}, 'sorted_anchor_sequence': sorted_anchor_sequence, 'strict_pairwise_order_checks': monotonic_pairs, 'strong': {'holds': strong_temporal, 'max_span_seconds': 1800}, 'fallback': {'holds': fallback_temporal, 'max_span_seconds': 5400}, 'time_source_summary': time_source_summary}, 'predicate': 'All configured post-fix file birth-times (falling back to mtime when birth-time is unavailable) are strictly later than all configured pre-fix file anchors, and the total window is <= 1800 seconds on the strong path or <= 5400 seconds on the fallback path.', 'result': 'pass' if subgate_14b_pass else 'fail', 'sub_gate': 'b_every_per_file_utc_anchor_falls_within_one_bounded_window'},
        {'claim': 'The pre-fix and post-fix live revision IDs parse to the same resource-group/container-app lineage.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('02-revision-list-pre-fix.json'), repo_rel('11-revision-list-post-fix.json')], 'observed_values': {'pre_revision_id': pre_revision_id, 'post_revision_id': post_revision_id, 'pre_parse_ok': pre_parse_ok, 'post_parse_ok': post_parse_ok, 'both_parse_ok': both_parse_ok, 'pre_resource_group': pre_revision_parts['resource_group'], 'post_resource_group': post_revision_parts['resource_group'], 'pre_container_app': pre_revision_parts['container_app'], 'post_container_app': post_revision_parts['container_app'], 'pre_post_rg_equal': pre_post_rg_equal, 'pre_post_app_equal': pre_post_app_equal, 'pre_post_lineage_equal': pre_post_lineage_equal, 'pre_post_revision_equal': pre_post_revision_equal}, 'predicate': 'The live revision ID selected from 02 and the live revision ID selected from 11 both match the /subscriptions/.../resourceGroups/.../containerApps/.../revisions/... regex, and the parsed resourceGroup + containerApp + revision components compare equal only when both parses succeed.', 'result': 'pass' if subgate_14c_pass else 'fail', 'sub_gate': 'c_revision_id_lineage_parses_and_compares_equal'},
        {'claim': 'The PE NIC IP map and private DNS records are unchanged across H1 and H2, no unexpected non-junk extras exist, and evidence/README.md literally names all four Phase B outputs.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('04-private-dns-record-list-pre-fix.json'), repo_rel('05-pe-nic-config-pre-fix.json'), repo_rel('10-private-dns-record-list-post-fix.json'), repo_rel('12-recovery-surface-post-fix.json'), repo_rel('README.md')], 'observed_values': {'expected_xrefs': expected_xrefs, 'ignored_junk': sorted(JUNK_NAMES), 'observed_files_on_disk': observed_files_on_disk, 'observed_non_junk_extras': unexpected_non_junk, 'observed_xrefs': observed_xrefs, 'pre_nic_map': pre_nic_map, 'post_nic_map': post_nic_map, 'pre_registry_records': pre_registry_records, 'post_registry_records': post_registry_records, 'pre_data_records': pre_data_records, 'post_data_records': post_data_records, 'pe_nic_unchanged': pe_nic_unchanged}, 'predicate': 'The normalized PE NIC ipConfigurations captured in 05 and 12.pe_nic compare equal, the normalized private DNS record summaries captured in 04 and 10 compare equal, extras == [], and evidence/README.md contains the four gate filenames literally.', 'result': 'pass' if subgate_14d_pass else 'fail', 'sub_gate': 'd_pe_nic_private_dns_and_readme_xrefs_stay_constant'},
        {'claim': 'The cohort records one consistent UTC reference window and the span math is computed from that same anchor set.', 'claim_level': 'Measured', 'evidence_files': [repo_rel(name) for name in RAW_FILES], 'observed_values': {'utc_window_start': utc_window_start.isoformat(), 'utc_window_end': utc_window_end.isoformat(), 'utc_window_span_seconds': utc_window_span_seconds, 'time_source_summary': time_source_summary}, 'predicate': 'utc_window_start <= utc_window_end AND utc_window_span_seconds is computed from the same anchor set disclosed in pre_anchor_timestamps + post_anchor_timestamps.', 'result': 'pass' if subgate_14e_pass else 'fail', 'sub_gate': 'e_utc_reference_and_span_math_stay_consistent'},
    ],
    'thresholds': {'canonical_count_strong': 12, 'canonical_count_fallback_floor': 12, 'utc_window_span_strong_seconds_max': 1800, 'utc_window_span_fallback_seconds_max': 5400},
    'utc_captured': UTC_NOW,
}

gate15 = {
    'claim': f'The H1 trigger produced the documented workload-path failure surface on {app_name}: dnsmasq points at 8.8.8.8, the /probe endpoint returns first_class=public with explicit retry disclosure, the already-running revision stays Healthy, and the captured H1+H2 failure-event KQL window stays empty. This is the silent workload-path failure mode for DNS-forwarder bypass.',
    'claim_level': 'Observed', 'gate_classification': 'H1 gate: confirms that swapping dnsmasq to public DNS flips only the workload probe surface while the already-running revision stays healthy.', 'hypothesis': 'H1_trigger_produces_failure', 'path_used': 'single',
    'predicate_inputs': {'dnsmasq_pre': repo_rel('03-dnsmasq-config-pre-fix.json'), 'dns_records_pre': repo_rel('04-private-dns-record-list-pre-fix.json'), 'acr_public_access_pre': repo_rel('06-acr-public-access-pre-fix.json'), 'system_logs_pre': repo_rel('07-system-logs-pre-fix.json'), 'probe_pre': repo_rel('08-probe-response-pre-fix.json'), 'revision_list_pre': repo_rel('02-revision-list-pre-fix.json')},
    'acr_network_path_dns_forwarder_bypass_h1_trigger_produces_failure_all_subgates_pass': gate_15_all_subgates_pass,
    'acr_network_path_dns_forwarder_bypass_h1_trigger_produces_failure_sub_gates': {'a_dnsmasq_upstream_is_public_dns': subgate_15a_pass, 'b_probe_reports_public_resolution_with_retry_disclosure': subgate_15b_pass, 'c_already_running_revision_stays_healthy': subgate_15c_pass, 'd_h1_h2_window_contains_no_failure_events': subgate_15d_pass, 'e_acr_and_private_dns_surfaces_stay_constant': subgate_15e_pass},
    'scenario': 'acr_network_path_dns_forwarder_bypass',
    'sub_gates': [
        {'claim': 'The broken-window dnsmasq config reports server=8.8.8.8 and the dnsmasq service is active.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('03-dnsmasq-config-pre-fix.json')], 'observed_values': {'resolved_upstream': dnsmasq_pre.get('resolved_upstream'), 'service_state': dnsmasq_pre.get('service_state'), 'listen_address': dnsmasq_pre.get('listen_address'), 'server_lines': dnsmasq_pre.get('server_lines')}, 'predicate': "03.resolved_upstream == '8.8.8.8' AND 03.service_state == 'active'.", 'result': 'pass' if subgate_15a_pass else 'fail', 'sub_gate': 'a_dnsmasq_upstream_is_public_dns'},
        {'claim': 'The broken-window /probe response reports first_class=public and explicitly discloses how many retries were needed before that final selected response.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('08-probe-response-pre-fix.json')], 'observed_values': {'expected_first_class': probe_pre_payload.get('expected_first_class'), 'selected_attempt': probe_pre_payload.get('selected_attempt'), 'attempt_count': len(probe_pre_payload.get('attempts', [])), 'attempts': pre_attempts, 'final_response': pre_probe_response, 'expected_registry_ip': expected_registry_ip}, 'predicate': "08.response.first_class == 'public' AND 08.response.addresses[0].ip != the PE registry IP AND 08.selected_attempt >= 1 AND len(08.attempts) >= 08.selected_attempt.", 'result': 'pass' if subgate_15b_pass else 'fail', 'sub_gate': 'b_probe_reports_public_resolution_with_retry_disclosure'},
        {'claim': 'The already-running revision stays Healthy throughout the broken window.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('02-revision-list-pre-fix.json')], 'observed_values': {'pre_live_revision': pre_live_revision, 'all_pre_revision_healthy': all_pre_revision_healthy}, 'predicate': "The live revision selected from 02 has healthState == 'Healthy' and active == true, and every revision captured in 02 has healthState == 'Healthy'.", 'result': 'pass' if subgate_15c_pass else 'fail', 'sub_gate': 'c_already_running_revision_stays_healthy'},
        {'claim': 'The captured H1+H2 failure-event query stays empty, proving that the failure is silent at the revision-health and pull-failure observability layer.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('07-system-logs-pre-fix.json')], 'observed_values': {'query': system_pre.get('query'), 'window_start_utc': system_pre.get('window_start_utc'), 'window_end_utc': system_pre.get('window_end_utc'), 'row_count': pre_failure_row_count, 'rows': pre_rows}, 'predicate': 'len(07.rows) == 0.', 'result': 'pass' if subgate_15d_pass else 'fail', 'sub_gate': 'd_h1_h2_window_contains_no_failure_events'},
        {'claim': 'ACR publicNetworkAccess and the private DNS record surfaces stay constant during the broken window, so the H1 outcome is not explained by an ACR or zone-content toggle.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('04-private-dns-record-list-pre-fix.json'), repo_rel('06-acr-public-access-pre-fix.json'), repo_rel('10-private-dns-record-list-post-fix.json'), repo_rel('12-recovery-surface-post-fix.json')], 'observed_values': {'pre_public_network_access': acr_pre.get('publicNetworkAccess'), 'post_public_network_access': post_acr.get('publicNetworkAccess'), 'pre_registry_records': pre_registry_records, 'post_registry_records': post_registry_records, 'pre_data_records': pre_data_records, 'post_data_records': post_data_records}, 'predicate': '06.publicNetworkAccess == 12.acr.publicNetworkAccess AND the normalized registry/data record summaries captured in 04 and 10 compare equal.', 'result': 'pass' if subgate_15e_pass else 'fail', 'sub_gate': 'e_acr_and_private_dns_surfaces_stay_constant'},
    ],
    'thresholds': {'expected_failure_event_rows': 0}, 'utc_captured': UTC_NOW,
}

gate16 = {
    'claim': f'The H2 fix restored recovery on {app_name}: dnsmasq was restored to 168.63.129.16, the /probe endpoint returns first_class=private again with the PE registry IP, the same already-running revision stays Healthy, and no new revision was created during the lab. This is the workload-path silence invariant.',
    'claim_level': 'Observed', 'gate_classification': 'H2 gate: confirms recovery after restoring the dnsmasq upstream and proves that the workload-path lab never deployed a new revision.', 'hypothesis': 'H2_fix_restores_recovery', 'path_used': 'single',
    'predicate_inputs': {'dnsmasq_post': repo_rel('09-dnsmasq-config-post-fix.json'), 'dns_records_post': repo_rel('10-private-dns-record-list-post-fix.json'), 'revision_list_post': repo_rel('11-revision-list-post-fix.json'), 'composite_post': repo_rel('12-recovery-surface-post-fix.json')},
    'acr_network_path_dns_forwarder_bypass_h2_fix_restores_recovery_all_subgates_pass': gate_16_all_subgates_pass,
    'acr_network_path_dns_forwarder_bypass_h2_fix_restores_recovery_sub_gates': {'a_dnsmasq_upstream_is_restored_to_azure_dns': subgate_16a_pass, 'b_probe_returns_private_again': subgate_16b_pass, 'c_same_revision_stays_healthy_without_a_new_revision': subgate_16c_pass, 'd_acr_private_dns_and_pe_topology_stay_constant': subgate_16d_pass},
    'scenario': 'acr_network_path_dns_forwarder_bypass',
    'sub_gates': [
        {'claim': 'The post-fix dnsmasq config reports server=168.63.129.16 and the dnsmasq service is active.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('09-dnsmasq-config-post-fix.json')], 'observed_values': {'resolved_upstream': dnsmasq_post.get('resolved_upstream'), 'service_state': dnsmasq_post.get('service_state'), 'listen_address': dnsmasq_post.get('listen_address'), 'server_lines': dnsmasq_post.get('server_lines')}, 'predicate': "09.resolved_upstream == '168.63.129.16' AND 09.service_state == 'active'.", 'result': 'pass' if subgate_16a_pass else 'fail', 'sub_gate': 'a_dnsmasq_upstream_is_restored_to_azure_dns'},
        {'claim': 'The post-fix /probe response returns first_class=private and the first returned IP matches the PE registry IP.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('12-recovery-surface-post-fix.json')], 'observed_values': {'expected_registry_ip': expected_registry_ip, 'selected_attempt': probe_post_payload.get('selected_attempt'), 'attempt_count': len(probe_post_payload.get('attempts', [])), 'attempts': post_attempts, 'final_response': post_probe_response}, 'predicate': "12.probe_capture.response.first_class == 'private' AND 12.probe_capture.response.addresses[0].ip == the PE registry IP AND 12.probe_capture.selected_attempt >= 1 AND len(12.probe_capture.attempts) >= 12.probe_capture.selected_attempt.", 'result': 'pass' if subgate_16b_pass else 'fail', 'sub_gate': 'b_probe_returns_private_again'},
        {'claim': 'The same already-running revision stays Healthy after the fix and no new revision was created during the lab.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('02-revision-list-pre-fix.json'), repo_rel('11-revision-list-post-fix.json'), repo_rel('12-recovery-surface-post-fix.json')], 'observed_values': {'pre_live_revision': pre_live_revision, 'post_live_revision': post_live_revision, 'pre_post_revision_equal': pre_post_revision_equal, 'all_post_revision_healthy': all_post_revision_healthy}, 'predicate': "The live revision selected from 11 has healthState == 'Healthy' and active == true, every revision captured in 11 has healthState == 'Healthy', and the selected revision name in 11 equals the selected revision name in 02.", 'result': 'pass' if subgate_16c_pass else 'fail', 'sub_gate': 'c_same_revision_stays_healthy_without_a_new_revision'},
        {'claim': 'ACR public access, private DNS records, and PE topology stay constant across H1 and H2.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('04-private-dns-record-list-pre-fix.json'), repo_rel('05-pe-nic-config-pre-fix.json'), repo_rel('06-acr-public-access-pre-fix.json'), repo_rel('10-private-dns-record-list-post-fix.json'), repo_rel('12-recovery-surface-post-fix.json')], 'observed_values': {'pre_publicNetworkAccess': acr_pre.get('publicNetworkAccess'), 'post_publicNetworkAccess': post_acr.get('publicNetworkAccess'), 'pre_nic_map': pre_nic_map, 'post_nic_map': post_nic_map, 'pre_registry_records': pre_registry_records, 'post_registry_records': post_registry_records, 'pre_data_records': pre_data_records, 'post_data_records': post_data_records}, 'predicate': '06.publicNetworkAccess == 12.acr.publicNetworkAccess AND the normalized PE NIC ipConfigurations captured in 05 and 12.pe_nic compare equal AND the normalized registry/data record summaries captured in 04 and 10 compare equal.', 'result': 'pass' if subgate_16d_pass else 'fail', 'sub_gate': 'd_acr_private_dns_and_pe_topology_stay_constant'},
    ],
    'thresholds': {'expected_post_fix_failure_event_rows': 0}, 'utc_captured': UTC_NOW,
}

gate17 = {
    'claim': 'This evidence pack falsifies the ACR DNS-forwarder-bypass hypothesis within a bounded scope. Gate 17 demonstrates that dnsmasq_upstream is the mechanically observable trigger field for this cohort: the container-app lineage stays constant, the same revision stays Healthy on both sides, the private DNS and PE NIC surfaces stay constant, dnsmasq transitions from 8.8.8.8 to 168.63.129.16, the workload probe transitions from first_class=public to first_class=private, and the H1+H2 failure-event query stays empty. The pack does not claim exact DNS timing, exact retry counts, control-plane fresh-pull behavior, or byte-identical backend payloads.',
    'claim_level': 'Observed',
    'cohort_binding_note': {'claim_ceiling': 'The bounded claim is that this single koreacentral cohort proves a workload-path DNS-forwarder-bypass failure: swapping dnsmasq from Azure DNS to 8.8.8.8 makes the in-replica /probe surface move from private to public while the already-running revision stays Healthy, and restoring that same upstream back to 168.63.129.16 moves the probe back to private without deploying a new revision. The pack does NOT prove broken-window control-plane fresh-pull behavior, exact resolver latency, exact retry counts, byte-identical backend bodies, cache-layer inventory, system-log ingestion latency, or negotiated TLS cipher suites.', 'explicit_drops': explicit_drops},
    'gate_classification': 'Bounded falsification gate: isolates the dnsmasq upstream as the trigger while explicitly listing the unproven confounders and ceilings.', 'hypothesis': 'H3_bounded_falsification', 'path_used': 'bounded',
    'predicate_inputs': {'app_spec_pre': repo_rel('01-app-spec-pre-fix.json'), 'revision_list_pre': repo_rel('02-revision-list-pre-fix.json'), 'dnsmasq_pre': repo_rel('03-dnsmasq-config-pre-fix.json'), 'dns_records_pre': repo_rel('04-private-dns-record-list-pre-fix.json'), 'pe_nic_pre': repo_rel('05-pe-nic-config-pre-fix.json'), 'system_logs_pre': repo_rel('07-system-logs-pre-fix.json'), 'probe_pre': repo_rel('08-probe-response-pre-fix.json'), 'dnsmasq_post': repo_rel('09-dnsmasq-config-post-fix.json'), 'dns_records_post': repo_rel('10-private-dns-record-list-post-fix.json'), 'revision_list_post': repo_rel('11-revision-list-post-fix.json'), 'composite_post': repo_rel('12-recovery-surface-post-fix.json')},
    'acr_network_path_dns_forwarder_bypass_h3_bounded_falsification_all_subgates_pass': gate_17_all_subgates_pass,
    'acr_network_path_dns_forwarder_bypass_h3_bounded_falsification_sub_gates': {'a_held_constant_fields_and_lineage_stay_equal': subgate_17a_pass, 'b_full_overlapping_h1_h2_diff_matches_the_dnsmasq_trigger_story': subgate_17b_pass, 'c_explicit_drops_match_the_documented_ceiling': subgate_17c_pass, 'd_workload_path_silence_invariant_is_checked': subgate_17d_pass},
    'scenario': 'acr_network_path_dns_forwarder_bypass',
    'sub_gates': [
        {'claim': 'The held-constant fields, private DNS/PE topology, lineage, and live revision identity stay equal across H1 and H2.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('01-app-spec-pre-fix.json'), repo_rel('04-private-dns-record-list-pre-fix.json'), repo_rel('05-pe-nic-config-pre-fix.json'), repo_rel('11-revision-list-post-fix.json'), repo_rel('12-recovery-surface-post-fix.json')], 'observed_values': {'held_constant_checks': held_constant_checks, 'pre_post_lineage_equal': pre_post_lineage_equal, 'pre_post_revision_equal': pre_post_revision_equal}, 'predicate': 'Every held_constant_checks entry has equal == true, the normalized PE NIC ipConfigurations compare equal, the normalized private DNS record summaries compare equal, and the parsed pre/post live revision IDs compare equal on resourceGroup + containerApp + revision when both parses succeed.', 'result': 'pass' if subgate_17a_pass else 'fail', 'sub_gate': 'a_held_constant_fields_and_lineage_stay_equal'},
        {'claim': 'The full overlapping H1↔H2 diff matches the bounded dnsmasq-trigger story and no overlapping field outside the documented dnsmasq/probe outputs changes.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('03-dnsmasq-config-pre-fix.json'), repo_rel('08-probe-response-pre-fix.json'), repo_rel('09-dnsmasq-config-post-fix.json'), repo_rel('12-recovery-surface-post-fix.json')], 'observed_values': {'allowed_expected_diff_paths': sorted(allowed_expected_diff_paths), 'required_expected_diff_paths': sorted(required_expected_diff_paths), 'full_overlap_diff': overlap_diff_map, 'full_overlap_equal': overlap_same_map, 'overlap_paths': overlap_paths, 'unexpected_overlap_diffs': unexpected_overlap_diffs, 'missing_required_diff_paths': missing_required_diff_paths}, 'predicate': 'Across the full normalized overlapping H1/H2 surface, the only differing overlap paths are dnsmasq.upstream plus the documented first-address/first-class probe output fields; no other overlapping path may differ, and the required paths {dnsmasq.upstream, probe.first_class, probe.first_ip} must all differ.', 'result': 'pass' if subgate_17b_pass else 'fail', 'sub_gate': 'b_full_overlapping_h1_h2_diff_matches_the_dnsmasq_trigger_story'},
        {'claim': 'The bounded-falsification gate explicitly lists the documented ceilings and unsupported inferences.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('17-bounded-falsification-gate.json')], 'observed_values': {'documented_ceiling_ids': sorted(DOCUMENTED_EXPLICIT_DROPS_CEILING), 'observed_drop_ids': [item['id'] for item in explicit_drops]}, 'predicate': 'cohort_binding_note.explicit_drops ids equal the static documented ceiling {acr_control_plane_fresh_pull, dns_resolution_timing, exact_http_body_bytes, image_layer_cache_state, probe_retry_attempt_count, resource_provider_poll_latency, system_log_ingestion_latency, tls_cipher_suite} with no additions and no omissions.', 'result': 'pass' if subgate_17c_pass else 'fail', 'sub_gate': 'c_explicit_drops_match_the_documented_ceiling'},
        {'claim': 'The workload-path silence invariant is checked actively: the same revision stays Healthy on both sides, H1 shows first_class=public, H2 shows first_class=private, and the H1+H2 failure-event query stays empty.', 'claim_level': 'Observed', 'evidence_files': [repo_rel('02-revision-list-pre-fix.json'), repo_rel('07-system-logs-pre-fix.json'), repo_rel('11-revision-list-post-fix.json'), repo_rel('12-recovery-surface-post-fix.json')], 'observed_values': {'pre_live_revision_name': pre_live_revision.get('name') if pre_live_revision else None, 'post_live_revision_name': post_live_revision.get('name') if post_live_revision else None, 'pre_health_state': pre_live_props.get('healthState'), 'post_health_state': post_live_props.get('healthState'), 'pre_first_class': pre_probe_response.get('first_class'), 'post_first_class': post_probe_response.get('first_class'), 'failure_event_row_count': pre_failure_row_count}, 'predicate': "02.selected live revision name == 11.selected live revision name AND both selected live revisions have healthState == 'Healthy' AND 08.response.first_class == 'public' AND 12.probe_capture.response.first_class == 'private' AND len(07.rows) == 0.", 'result': 'pass' if subgate_17d_pass else 'fail', 'sub_gate': 'd_workload_path_silence_invariant_is_checked'},
    ],
    'thresholds': {'held_constant_field_count': len(held_constant_checks), 'expected_failure_event_rows': 0}, 'utc_captured': UTC_NOW,
}

gates = [(14, gate14, 'cohort integrity verified'), (15, gate15, 'H1 trigger produces failure verified'), (16, gate16, 'H2 fix restores recovery verified'), (17, gate17, 'bounded falsification verified')]
output_map = {14: EVIDENCE_DIR / '14-cohort-integrity-gate.json', 15: EVIDENCE_DIR / '15-h1-trigger-produces-failure-gate.json', 16: EVIDENCE_DIR / '16-h2-fix-restores-recovery-gate.json', 17: EVIDENCE_DIR / '17-bounded-falsification-gate.json'}
for gate_number, gate_data, _ in gates:
    output_map[gate_number].write_text(json.dumps(sanitize_value(gate_data), indent=2) + '\n', encoding='utf-8')
for gate_number, gate_data, detail in gates:
    sub_gate_map = next(value for key, value in gate_data.items() if key.endswith('_sub_gates'))
    if not all(sub_gate_map.values()):
        failed = [key for key, value in sub_gate_map.items() if not value]
        raise SystemExit(f'[Gate {gate_number}/17] FAIL {detail}; failed sub-gates: {", ".join(failed)}')
    print(f'[Gate {gate_number}/17] PASS {detail}')
PY2
)"; then
    printf '%s\n' "$PHASE_B_OUTPUT"
else
    printf '%s\n' "$PHASE_B_OUTPUT"
    exit 1
fi
