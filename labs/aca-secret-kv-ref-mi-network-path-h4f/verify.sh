#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/aca-secret-kv-ref-mi-network-path-h4f/evidence"
LAB_README_PATH="${SCRIPT_DIR}/README.md"
UTC_NOW="${UTC_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR LAB_README_PATH UTC_NOW

python3 <<'PY'
import json
import os
import sys
from pathlib import Path

evidence_dir = Path(os.environ['EVIDENCE_DIR'])
repo_rel_dir = os.environ['REPO_RELATIVE_EVIDENCE_DIR']
utc_now = os.environ['UTC_NOW']

RAW_FILES = [
    '01-deployment-outputs.json',
    '02-h0-app-state-before.json',
    '03-h0-kv-secret-created.json',
    '04-h0-secret-set-outcome.json',
    '05-h0-app-state-after.json',
    '06-h1-nva-drop-rule-installed.json',
    '07-h1-secret-set-outcome.json',
    '08-h1-app-state.json',
    '09-h1-nva-rule-state-and-workload-probe.json',
    '10-h2-nva-drop-rule-removed.json',
    '11-h2-secret-set-outcome.json',
    '12-h2-app-state.json',
    '13-h2-nva-rule-state-and-workload-probe.json',
]

GATE_OUTPUTS = [
    '14-cohort-integrity-gate.json',
    '15-h1-nva-surrogate-drop-produces-failure-gate.json',
    '16-h2-nva-surrogate-allow-restores-success-gate.json',
    '17-bounded-falsification-gate.json',
]

SCENARIO = 'aca_secret_kv_ref_mi_network_path_h4f'

ENTRA_PROBE_HOSTS = ['login.microsoftonline.com', 'login.microsoft.com']
DROP_RULE_COMMENT = 'h4f-drop-entra-443'


def repo_rel(name: str) -> str:
    return f'{repo_rel_dir}/{name}'


def load_json(name: str):
    return json.loads((evidence_dir / name).read_text(encoding='utf-8'))


def pass_gate(number: int, detail: str):
    print(f'[Gate {number}/17] PASS {detail}')


def fail_gate(number: int, detail: str):
    print(f'[Gate {number}/17] FAIL {detail}')
    sys.exit(1)


def contains_forbidden_storage_or_flowlog_artifact(payload) -> bool:
    forbidden_markers = (
        'network watcher flow-log',
        'flow-log',
        'flow log',
        'storageaccount',
        'storage account',
        'traffic analytics',
    )

    def walk(value):
        if isinstance(value, dict):
            return any(walk(v) or walk(k) for k, v in value.items())
        if isinstance(value, list):
            return any(walk(v) for v in value)
        if isinstance(value, str):
            lowered = value.lower()
            return any(marker in lowered for marker in forbidden_markers)
        return False

    return walk(payload)


def route_points_to_nva(doc: dict, expected_ip: str) -> bool:
    route = (doc or {}).get('route_table_default_route') or {}
    return (
        route.get('addressPrefix') == '0.0.0.0/0'
        and route.get('nextHopType') == 'VirtualAppliance'
        and ((route.get('nextHopIpAddress') or '') == expected_ip)
    )


def required_anchor_map(doc: dict, file_name: str):
    keys = [
        'resource_group',
        'environment_name',
        'app_name',
        'app_principal_id',
        'key_vault_name',
        'tenant_id',
        'baseline_revision_name',
    ]
    missing = [key for key in keys if doc.get(key) in (None, '')]
    if missing:
        fail_gate(14, f'{file_name} missing required anchor field(s): {", ".join(missing)}')
    return {key: doc.get(key) for key in keys}


def route_anchor_map(doc: dict, file_name: str):
    route = doc.get('route_table_default_route') or {}
    required = ['addressPrefix', 'nextHopType', 'nextHopIpAddress']
    missing = [key for key in required if route.get(key) in (None, '')]
    if missing:
        fail_gate(14, f'{file_name} missing required route anchor field(s): {", ".join(missing)}')
    if (doc.get('nva_private_ip') or '') in ('', None):
        fail_gate(14, f'{file_name} missing required nva_private_ip anchor')
    if (doc.get('nva_vm_name') or '') in ('', None):
        fail_gate(14, f'{file_name} missing required nva_vm_name anchor')
    return {
        'nva_vm_name': doc.get('nva_vm_name'),
        'nva_private_ip': doc.get('nva_private_ip'),
        'addressPrefix': route.get('addressPrefix'),
        'nextHopType': route.get('nextHopType'),
        'nextHopIpAddress': route.get('nextHopIpAddress'),
    }


def classify_h1_stderr(stderr_text: str):
    # NOTE: the exact production stderr string is PENDING a real NVA-surrogate run
    # and must not be asserted verbatim. This classifier intentionally accepts
    # (managed-identity clue OR OIDC clue) AND a network / timeout / connection clue.
    text = (stderr_text or '').lower()
    managed_identity_or_oidc_clues = [
        'failed to update secrets',
        'unable to get value using managed identity',
        'openid-configuration',
        'openid connect',
        'login.microsoftonline.com',
    ]
    network_timeout_or_connection_clues = [
        'timeout',
        'timed out',
        'connection reset',
        'connection refused',
        'eof',
        'no such host',
        'temporary failure in name resolution',
        'dial tcp',
        'i/o timeout',
    ]
    forbidden_non_h4f_clues = [
        'secretnotfound',
        'secret not found',
        'forbidden',
        'does not have secrets get permission',
        'key vault secrets user',
        'failed to provision revision',
        'revision failed',
        'errimagepull',
        'imagepullbackoff',
    ]
    found_managed_or_oidc = [c for c in managed_identity_or_oidc_clues if c in text]
    found_network = [c for c in network_timeout_or_connection_clues if c in text]
    forbidden_found = [c for c in forbidden_non_h4f_clues if c in text]
    return {
        'managed_or_oidc_clues_found': found_managed_or_oidc,
        'network_timeout_or_connection_clues_found': found_network,
        'forbidden_non_h4f_clues_found': forbidden_found,
        'passes_classifier': bool(found_managed_or_oidc) and bool(found_network) and not forbidden_found,
    }


def workload_probes_all_outcome(doc: dict, expected_outcome: str) -> bool:
    probe = (doc or {}).get('workload_probe') or {}
    for host in ENTRA_PROBE_HOSTS:
        entry = probe.get(host) or {}
        if entry.get('outcome') != expected_outcome:
            return False
    return True


def nva_rule_state_present(doc: dict):
    state = (doc or {}).get('nva_rule_state') or {}
    return state.get('rule_present')


if not evidence_dir.is_dir():
    fail_gate(1, f'evidence directory missing at {evidence_dir}')
pass_gate(1, f'evidence directory present at {evidence_dir}')

for gate_number, subset, label in [
    (2, RAW_FILES[0:5], 'H0 raw files 01-05 present'),
    (3, RAW_FILES[5:9], 'H1 raw files 06-09 present'),
    (4, RAW_FILES[9:13], 'H2 raw files 10-13 present'),
]:
    missing = [name for name in subset if not (evidence_dir / name).is_file()]
    if missing:
        fail_gate(gate_number, f'missing files: {", ".join(missing)}')
    pass_gate(gate_number, label)

try:
    d01 = load_json(RAW_FILES[0])
    d02 = load_json(RAW_FILES[1])
    d03 = load_json(RAW_FILES[2])
    d04 = load_json(RAW_FILES[3])
    d05 = load_json(RAW_FILES[4])
    d06 = load_json(RAW_FILES[5])
    d07 = load_json(RAW_FILES[6])
    d08 = load_json(RAW_FILES[7])
    d09 = load_json(RAW_FILES[8])
    d10 = load_json(RAW_FILES[9])
    d11 = load_json(RAW_FILES[10])
    d12 = load_json(RAW_FILES[11])
    d13 = load_json(RAW_FILES[12])
except Exception as exc:
    fail_gate(5, f'parse failure while loading raw cohort: {type(exc).__name__}: {exc}')

required_01 = [
    'lab_name', 'resource_group', 'location', 'app_name', 'environment_name',
    'key_vault_name', 'key_vault_uri', 'app_principal_id', 'vnet_name',
    'aca_subnet_name', 'aca_subnet_prefix', 'log_analytics_name', 'log_analytics_customer_id',
    'route_table_name', 'nva_vm_name', 'nva_nic_name', 'nva_private_ip',
]
missing_01 = [key for key in required_01 if d01.get(key) in (None, '')]
if missing_01 or d01.get('lab_name') != 'aca-secret-kv-ref-mi-network-path-h4f':
    fail_gate(5, f"01 anchors invalid; missing={missing_01}, lab_name={d01.get('lab_name')}")
pass_gate(5, '01 parses and carries H4f cohort anchors')

if d02.get('phase') != 'H0-before' or not d02.get('app_name') or not d02.get('latest_ready_revision_name') or not d02.get('ingress_fqdn'):
    fail_gate(6, '02 missing H0-before surface fields')
pass_gate(6, '02 H0-before surface valid')

if d03.get('phase') != 'H0' or 'secrets/' not in (d03.get('secret_url_versionless') or ''):
    fail_gate(7, '03 missing versionless Key Vault URL')
pass_gate(7, '03 versionless Key Vault URL valid')

if d04.get('phase') != 'H0' or d04.get('exit_code') != 0 or d04.get('outcome') != 'success':
    fail_gate(8, f"04 H0 baseline invalid: exit={d04.get('exit_code')} outcome={d04.get('outcome')}")
pass_gate(8, '04 H0 baseline succeeded')

if d05.get('phase') != 'H0-after' or d05.get('latest_revision_unchanged_vs_before') is not True or int(d05.get('baseline_secret_present_in_config_count') or 0) < 1:
    fail_gate(9, '05 H0-after invariant invalid')
pass_gate(9, '05 H0 success gate valid')

nva_private_ip = d01.get('nva_private_ip') or ''
nva_vm_name = d01.get('nva_vm_name') or ''

gate10_problems = []
if d01.get('nva_surrogate_present') is not True or d01.get('nva_surrogate_type') != 'linux_forwarding_vm':
    gate10_problems.append('01 must prove a Linux NVA surrogate is present')
if d01.get('nva_nic_ip_forwarding_enabled') is not True:
    gate10_problems.append('01 must prove the NVA NIC has Azure IP forwarding enabled')
if d01.get('nva_os_ip_forwarding_enabled') is not True:
    gate10_problems.append('01 must prove the NVA guest OS has IP forwarding enabled')
if d01.get('nva_nat_enabled') is not True:
    gate10_problems.append('01 must prove the NVA guest OS has NAT/masquerade enabled')
if d01.get('route_table_attached') is not True or d01.get('aca_subnet_route_table_id') in (None, ''):
    gate10_problems.append('01 must prove a route table is attached to the ACA subnet')
if not route_points_to_nva(d01, nva_private_ip) or d01.get('default_route_points_to_nva_surrogate') is not True:
    gate10_problems.append('01 must prove the default route points to the NVA surrogate private IP')
if d01.get('uses_azure_provided_dns') is not True or (d01.get('vnet_dns_servers') or []) != []:
    gate10_problems.append('01 must prove the VNet uses Azure-provided DNS (no custom dnsServers)')
if d01.get('azure_firewall_present') is not False:
    gate10_problems.append('01 must prove no Azure Firewall is present (H4f topology has no firewall)')
if d01.get('firewall_policy_present') is not False:
    gate10_problems.append('01 must prove no Firewall Policy is present')
if d01.get('tls_inspection_configured') is not False:
    gate10_problems.append('01 must prove no TLS inspection is configured')
if d01.get('nsg_deny_present') is not False:
    gate10_problems.append('01 must prove no NSG deny trigger is present')
if d01.get('dns_override_present') is not False:
    gate10_problems.append('01 must prove no custom DNS override exists')
if d01.get('vwan_routing_intent_present') is not False:
    gate10_problems.append('01 must prove no Virtual WAN routing intent exists')
if contains_forbidden_storage_or_flowlog_artifact([d01, d06, d09, d10, d13]):
    gate10_problems.append('The cohort must not reference storage-account, flow-log, or Traffic Analytics artifacts')
if gate10_problems:
    fail_gate(10, '; '.join(gate10_problems))
pass_gate(10, '01 proves the H4f topology anchors: Linux NVA surrogate + NIC/OS forwarding + NAT + route table to NVA, with no Azure Firewall / TLS inspection / DNS / NSG / Virtual WAN confounder')

if d07.get('phase') != 'H1' or not isinstance(d07.get('exit_code'), int) or d07.get('exit_code') == 0 or d07.get('outcome') != 'failure':
    fail_gate(11, '07 H1 secret set did not fail as expected')
pass_gate(11, '07 H1 secret set failed')

if d08.get('latest_revision_unchanged_vs_baseline') is not True or d08.get('ingress_probe_http_code') != '200' or d08.get('secret_presence_expectation_met') is not True or d08.get('observed_secret_present') is not False:
    fail_gate(12, '08 H1 silence gate invalid')
pass_gate(12, '08 H1 silence gate valid')

if d11.get('phase') != 'H2' or d11.get('exit_code') != 0 or d11.get('outcome') != 'success':
    fail_gate(13, '11 H2 secret set must succeed')
if d12.get('latest_revision_unchanged_vs_baseline') is not True or d12.get('ingress_probe_http_code') != '200' or d12.get('secret_presence_expectation_met') is not True or d12.get('observed_secret_present') is not True:
    fail_gate(13, '12 H2 success gate invalid')
pass_gate(13, '09-13 H1 NVA-drop failure + H2 NVA-allow recovery cohort valid')

app_name = d01['app_name']
resource_group = d01['resource_group']
location = d01['location']
baseline_revision_name = d02['latest_ready_revision_name']

h0_anchor_docs = {
    '01': required_anchor_map(d01, '01-deployment-outputs.json'),
    '02': required_anchor_map(d02, '02-h0-app-state-before.json'),
    '03': required_anchor_map(d03, '03-h0-kv-secret-created.json'),
    '04': required_anchor_map(d04, '04-h0-secret-set-outcome.json'),
    '05': required_anchor_map(d05, '05-h0-app-state-after.json'),
}
h1_anchor_docs = {
    '06': required_anchor_map(d06, '06-h1-nva-drop-rule-installed.json'),
    '07': required_anchor_map(d07, '07-h1-secret-set-outcome.json'),
    '08': required_anchor_map(d08, '08-h1-app-state.json'),
    '09': required_anchor_map(d09, '09-h1-nva-rule-state-and-workload-probe.json'),
}
h2_anchor_docs = {
    '10': required_anchor_map(d10, '10-h2-nva-drop-rule-removed.json'),
    '11': required_anchor_map(d11, '11-h2-secret-set-outcome.json'),
    '12': required_anchor_map(d12, '12-h2-app-state.json'),
    '13': required_anchor_map(d13, '13-h2-nva-rule-state-and-workload-probe.json'),
}
anchor_reference = h0_anchor_docs['01']
anchor_consistency = {
    phase_file: anchor_values == anchor_reference
    for phase_file, anchor_values in {**h0_anchor_docs, **h1_anchor_docs, **h2_anchor_docs}.items()
}
route_anchor_docs = {
    '01': route_anchor_map(d01, '01-deployment-outputs.json'),
    '06': route_anchor_map(d06, '06-h1-nva-drop-rule-installed.json'),
    '09': route_anchor_map(d09, '09-h1-nva-rule-state-and-workload-probe.json'),
    '10': route_anchor_map(d10, '10-h2-nva-drop-rule-removed.json'),
    '13': route_anchor_map(d13, '13-h2-nva-rule-state-and-workload-probe.json'),
}
route_anchor_reference = route_anchor_docs['01']
route_anchor_consistency = {phase_file: route_values == route_anchor_reference for phase_file, route_values in route_anchor_docs.items()}

timestamp_pairs = [
    ('01', d01.get('captured_at_utc'), '02', d02.get('captured_at_utc')),
    ('02', d02.get('captured_at_utc'), '03', d03.get('captured_at_utc')),
    ('03', d03.get('captured_at_utc'), '04', d04.get('captured_at_utc')),
    ('04', d04.get('captured_at_utc'), '05', d05.get('captured_at_utc')),
    ('05', d05.get('captured_at_utc'), '06', d06.get('captured_at_utc')),
    ('06', d06.get('captured_at_utc'), '07', d07.get('captured_at_utc')),
    ('07', d07.get('captured_at_utc'), '08', d08.get('captured_at_utc')),
    ('08', d08.get('captured_at_utc'), '09', d09.get('captured_at_utc')),
    ('09', d09.get('captured_at_utc'), '10', d10.get('captured_at_utc')),
    ('10', d10.get('captured_at_utc'), '11', d11.get('captured_at_utc')),
    ('11', d11.get('captured_at_utc'), '12', d12.get('captured_at_utc')),
    ('12', d12.get('captured_at_utc'), '13', d13.get('captured_at_utc')),
]
timestamp_violations = [f'{l}({lt}) > {r}({rt})' for l, lt, r, rt in timestamp_pairs if not lt or not rt or lt > rt]

app_name_refs = {
    phase_file: anchor_values['app_name']
    for phase_file, anchor_values in {**h0_anchor_docs, **h1_anchor_docs, **h2_anchor_docs}.items()
}
nva_vm_name_refs = {
    '01': d01.get('nva_vm_name'),
    '06': d06.get('nva_vm_name'),
    '09': d09.get('nva_vm_name'),
    '10': d10.get('nva_vm_name'),
    '13': d13.get('nva_vm_name'),
}
rev_h0_after = d05.get('latest_ready_revision_name')
rev_h1 = d08.get('latest_ready_revision_name')
rev_h2 = d12.get('latest_ready_revision_name')

subgate_14a = len(timestamp_violations) == 0
subgate_14b = all(value == app_name for value in app_name_refs.values())
subgate_14c = all(value == nva_vm_name for value in nva_vm_name_refs.values())
subgate_14d = baseline_revision_name == rev_h0_after == rev_h1 == rev_h2
subgate_14e = (
    all(anchor_consistency.values())
    and all(route_anchor_consistency.values())
    and d01.get('nva_surrogate_present') is True
    and d01.get('nva_surrogate_type') == 'linux_forwarding_vm'
    and d01.get('nva_nic_ip_forwarding_enabled') is True
    and d01.get('nva_os_ip_forwarding_enabled') is True
    and d01.get('nva_nat_enabled') is True
    and d01.get('route_table_attached') is True
    and route_points_to_nva(d01, nva_private_ip)
    and d01.get('default_route_points_to_nva_surrogate') is True
    and d01.get('azure_firewall_present') is False
    and d01.get('firewall_policy_present') is False
    and d01.get('tls_inspection_configured') is False
    and d01.get('nsg_deny_present') is False
    and d01.get('dns_override_present') is False
    and d01.get('vwan_routing_intent_present') is False
    and not contains_forbidden_storage_or_flowlog_artifact([d01, d06, d07, d08, d09, d10, d11, d12, d13])
)
gate14_all = all([subgate_14a, subgate_14b, subgate_14c, subgate_14d, subgate_14e])

gate14 = {
    'claim': (
        f'The evidence cohort for the aca-secret-kv-ref-mi-network-path-h4f lab on {app_name} '
        f'in {resource_group} ({location}) is internally consistent: all 13 raw files are present '
        f'and parseable, timestamps are monotonic, cross-file anchors agree, the baseline revision '
        f'{baseline_revision_name!r} stays unchanged across H0/H1/H2, and the deployed topology proves '
        f'a Linux NVA surrogate with NIC + OS IP forwarding, NAT, a route table with 0.0.0.0/0 to {nva_private_ip!r}, '
        f'no Azure Firewall, no TLS inspection, no NSG-deny trigger, no DNS override, and no Virtual WAN routing intent.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'Cohort integrity gate.',
    'hypothesis': 'H0_cohort_integrity',
    'path_used': 'single',
    'predicate_inputs': {f'file_{i:02d}': repo_rel(name) for i, name in enumerate(RAW_FILES, start=1)},
    f'{SCENARIO}_h0_cohort_integrity_all_subgates_pass': gate14_all,
    f'{SCENARIO}_h0_cohort_integrity_sub_gates': {
        'a_timestamps_monotonically_ordered_across_h0_h1_h2': subgate_14a,
        'b_app_name_anchor_consistent_across_all_files': subgate_14b,
        'c_nva_vm_name_anchor_consistent': subgate_14c,
        'd_baseline_revision_silence_invariant_holds': subgate_14d,
        'e_full_cohort_anchor_contract_and_h4f_topology_hold': subgate_14e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'Every consecutive pair of raw files has non-decreasing captured_at_utc timestamps.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in RAW_FILES],
            'observed_values': {'violations': timestamp_violations},
            'predicate': 'For every adjacent pair i, i.captured_at_utc <= (i+1).captured_at_utc.',
            'result': 'pass' if subgate_14a else 'fail',
            'sub_gate': 'a_timestamps_monotonically_ordered_across_h0_h1_h2',
        },
        {
            'claim': f'All app_name references equal {app_name!r}.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '02-h0-app-state-before.json', '05-h0-app-state-after.json', '08-h1-app-state.json', '12-h2-app-state.json']],
            'observed_values': app_name_refs,
            'predicate': 'All app_name fields equal 01.app_name.',
            'result': 'pass' if subgate_14b else 'fail',
            'sub_gate': 'b_app_name_anchor_consistent_across_all_files',
        },
        {
            'claim': f'All nva_vm_name references equal {nva_vm_name!r}.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-nva-drop-rule-installed.json', '09-h1-nva-rule-state-and-workload-probe.json', '10-h2-nva-drop-rule-removed.json', '13-h2-nva-rule-state-and-workload-probe.json']],
            'observed_values': nva_vm_name_refs,
            'predicate': 'All nva_vm_name fields equal 01.nva_vm_name.',
            'result': 'pass' if subgate_14c else 'fail',
            'sub_gate': 'c_nva_vm_name_anchor_consistent',
        },
        {
            'claim': f'The baseline revision {baseline_revision_name!r} stays identical across 02, 05, 08, and 12.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['02-h0-app-state-before.json', '05-h0-app-state-after.json', '08-h1-app-state.json', '12-h2-app-state.json']],
            'observed_values': {'02': baseline_revision_name, '05': rev_h0_after, '08': rev_h1, '12': rev_h2},
            'predicate': '02.latest_ready_revision_name == 05.latest_ready_revision_name == 08.latest_ready_revision_name == 12.latest_ready_revision_name.',
            'result': 'pass' if subgate_14d else 'fail',
            'sub_gate': 'd_baseline_revision_silence_invariant_holds',
        },
        {
            'claim': 'The full cohort-consistency contract and H4f topology both hold: resource group, environment name, app principal ID, Key Vault, tenant ID, and baseline revision are byte-equal across H0/H1/H2, the route-table default next hop and NVA private IP stay byte-equal across H0/H1/H2, and 01 proves the Linux NVA surrogate with forwarding + NAT while Azure Firewall / TLS inspection / NSG / DNS / Virtual WAN confounders remain absent.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in RAW_FILES],
            'observed_values': {
                'anchor_reference': anchor_reference,
                'anchor_consistency': anchor_consistency,
                'route_anchor_reference': route_anchor_reference,
                'route_anchor_consistency': route_anchor_consistency,
                'nva_surrogate_present': d01.get('nva_surrogate_present'),
                'nva_surrogate_type': d01.get('nva_surrogate_type'),
                'nva_nic_ip_forwarding_enabled': d01.get('nva_nic_ip_forwarding_enabled'),
                'nva_os_ip_forwarding_enabled': d01.get('nva_os_ip_forwarding_enabled'),
                'nva_nat_enabled': d01.get('nva_nat_enabled'),
                'route_table_attached': d01.get('route_table_attached'),
                'default_route_next_hop': (d01.get('route_table_default_route') or {}).get('nextHopIpAddress'),
                'azure_firewall_present': d01.get('azure_firewall_present'),
                'firewall_policy_present': d01.get('firewall_policy_present'),
                'tls_inspection_configured': d01.get('tls_inspection_configured'),
                'nsg_deny_present': d01.get('nsg_deny_present'),
                'dns_override_present': d01.get('dns_override_present'),
                'vwan_routing_intent_present': d01.get('vwan_routing_intent_present'),
            },
            'predicate': 'All required anchor fields are present and byte-equal across H0/H1/H2, all route default-route + NVA private IP anchors are present and byte-equal across H0/H1/H2, and 01 proves the Linux NVA surrogate with NIC/OS forwarding + NAT + route-table-to-NVA with no Azure Firewall / TLS inspection / NSG deny / DNS override / Virtual WAN routing intent confounder.',
            'result': 'pass' if subgate_14e else 'fail',
            'sub_gate': 'e_full_cohort_anchor_contract_and_h4f_topology_hold',
        },
    ],
    'thresholds': {'expected_raw_file_count': 13, 'expected_gate_output_count': 4},
    'utc_captured': utc_now,
}

h1_classifier = classify_h1_stderr(d07.get('stderr') or '')
h1_rule_install = (d06.get('nva_rule_installation') or {})
h1_service_tag = (d06.get('azure_active_directory_service_tag') or {})

subgate_15a = isinstance(d07.get('exit_code'), int) and d07.get('exit_code') != 0 and h1_classifier['passes_classifier']
subgate_15b = (
    d08.get('latest_revision_unchanged_vs_baseline') is True
    and d08.get('ingress_probe_http_code') == '200'
    and d08.get('secret_presence_expectation_met') is True
    and d08.get('observed_secret_present') is False
)
subgate_15c = (
    h1_rule_install.get('rule_present') is True
    and h1_rule_install.get('rule_comment') == DROP_RULE_COMMENT
    and int(h1_rule_install.get('dest_prefix_count') or 0) >= 1
    and int(h1_service_tag.get('prefix_count') or 0) >= 1
)
subgate_15d = workload_probes_all_outcome(d09, 'failure') and nva_rule_state_present(d09) is True
subgate_15e = route_points_to_nva(d06, nva_private_ip) and d06.get('nva_private_ip') == nva_private_ip and d06.get('nva_vm_name') == nva_vm_name
gate15_all = all([subgate_15a, subgate_15b, subgate_15c, subgate_15d, subgate_15e])

gate15 = {
    'claim': (
        f'H1 proves the NVA-surrogate forwarding-plane trigger: after the Linux NVA surrogate {nva_vm_name!r} installs a single nftables '
        f'DROP rule (comment {DROP_RULE_COMMENT!r}) for AzureActiveDirectory service-tag IPv4 prefixes on tcp/443, '
        f'`az containerapp secret set --secrets <name>=keyvaultref:<url>,identityref:system` fails on {app_name}, stderr matches a managed-identity / OIDC clue plus a network / timeout clue, '
        f'the baseline revision {baseline_revision_name!r} keeps serving HTTP 200, kvref-h1 stays absent, and workload-replica probes to both Entra authority hosts fail.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H1 NVA-surrogate drop gate.',
    'hypothesis': 'H1_nva_surrogate_drop_produces_failure',
    'path_used': 'single',
    'predicate_inputs': {
        'h1_rule_install': repo_rel('06-h1-nva-drop-rule-installed.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_app_state': repo_rel('08-h1-app-state.json'),
        'h1_rule_state_and_workload_probe': repo_rel('09-h1-nva-rule-state-and-workload-probe.json'),
    },
    f'{SCENARIO}_h1_nva_surrogate_drop_produces_failure_all_subgates_pass': gate15_all,
    f'{SCENARIO}_h1_nva_surrogate_drop_produces_failure_sub_gates': {
        'a_h1_secret_set_failed_with_classifier_signature': subgate_15a,
        'b_silence_gate_holds_revision_unchanged_ingress_200_secret_absent': subgate_15b,
        'c_h1_nva_drop_rule_present_for_service_tag_prefixes': subgate_15c,
        'd_h1_workload_probes_to_both_entra_hosts_failed': subgate_15d,
        'e_h1_topology_anchors_stayed_constant': subgate_15e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'The H1 secret-set attempt failed with the classifier signature: (managed-identity clue OR OIDC clue) AND a network/timeout/connection clue, without Key Vault-permission, missing-secret, or revision-failure markers.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('07-h1-secret-set-outcome.json')],
            'observed_values': {'exit_code': d07.get('exit_code'), 'classifier': h1_classifier},
            'predicate': '07.exit_code != 0 AND stderr classifier passes.',
            'result': 'pass' if subgate_15a else 'fail',
            'sub_gate': 'a_h1_secret_set_failed_with_classifier_signature',
        },
        {
            'claim': 'H1 left the running revision untouched: revision unchanged, ingress HTTP 200, and kvref-h1 absent.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('08-h1-app-state.json')],
            'observed_values': {
                'latest_revision_unchanged_vs_baseline': d08.get('latest_revision_unchanged_vs_baseline'),
                'ingress_probe_http_code': d08.get('ingress_probe_http_code'),
                'observed_secret_present': d08.get('observed_secret_present'),
            },
            'predicate': '08.latest_revision_unchanged_vs_baseline == True AND 08.ingress_probe_http_code == "200" AND 08.observed_secret_present == False.',
            'result': 'pass' if subgate_15b else 'fail',
            'sub_gate': 'b_silence_gate_holds_revision_unchanged_ingress_200_secret_absent',
        },
        {
            'claim': f'H1 installed a single nftables forwarding-plane DROP rule (comment {DROP_RULE_COMMENT!r}) targeting at least one AzureActiveDirectory service-tag IPv4 prefix on tcp/443.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-nva-drop-rule-installed.json')],
            'observed_values': {
                'nva_rule_installation': {
                    'rule_present': h1_rule_install.get('rule_present'),
                    'rule_comment': h1_rule_install.get('rule_comment'),
                    'dest_prefix_count': h1_rule_install.get('dest_prefix_count'),
                },
                'azure_active_directory_service_tag_prefix_count': h1_service_tag.get('prefix_count'),
            },
            'predicate': '06.nva_rule_installation.rule_present == True AND rule_comment == "h4f-drop-entra-443" AND dest_prefix_count >= 1 AND 06.azure_active_directory_service_tag.prefix_count >= 1.',
            'result': 'pass' if subgate_15c else 'fail',
            'sub_gate': 'c_h1_nva_drop_rule_present_for_service_tag_prefixes',
        },
        {
            'claim': 'The H1 workload-replica probes to login.microsoftonline.com and login.microsoft.com both failed while the NVA-local DROP rule was present.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('09-h1-nva-rule-state-and-workload-probe.json')],
            'observed_values': {
                'workload_probe': d09.get('workload_probe'),
                'nva_rule_state_rule_present': nva_rule_state_present(d09),
            },
            'predicate': '09.workload_probe[both hosts].outcome == "failure" AND 09.nva_rule_state.rule_present == True.',
            'result': 'pass' if subgate_15d else 'fail',
            'sub_gate': 'd_h1_workload_probes_to_both_entra_hosts_failed',
        },
        {
            'claim': 'H1 retained the H4f topology anchors: the default route still points 0.0.0.0/0 to the same NVA-surrogate private IP and the same NVA VM name.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-nva-drop-rule-installed.json')],
            'observed_values': {
                'route_table_default_route': d06.get('route_table_default_route'),
                'nva_private_ip': d06.get('nva_private_ip'),
                'nva_vm_name': d06.get('nva_vm_name'),
            },
            'predicate': '06 preserves route 0.0.0.0/0 -> nva_private_ip and the same nva_vm_name; only the NVA drop rule changed.',
            'result': 'pass' if subgate_15e else 'fail',
            'sub_gate': 'e_h1_topology_anchors_stayed_constant',
        },
    ],
    'thresholds': {'h1_exit_code_expected_nonzero': True, 'h1_nva_drop_rule_expected_present': True},
    'utc_captured': utc_now,
}

h2_rule_removal = (d10.get('nva_rule_removal') or {})

subgate_16a = h2_rule_removal.get('rule_removed') is True and h2_rule_removal.get('rule_present_after_remove') is False
subgate_16b = isinstance(d11.get('exit_code'), int) and d11.get('exit_code') == 0 and d11.get('outcome') == 'success'
subgate_16c = (
    d12.get('latest_revision_unchanged_vs_baseline') is True
    and d12.get('ingress_probe_http_code') == '200'
    and d12.get('secret_presence_expectation_met') is True
    and d12.get('observed_secret_present') is True
)
subgate_16d = workload_probes_all_outcome(d13, 'success') and nva_rule_state_present(d13) is False
subgate_16e = all(route_anchor_consistency.values()) and route_points_to_nva(d10, nva_private_ip)
gate16_all = all([subgate_16a, subgate_16b, subgate_16c, subgate_16d, subgate_16e])

gate16 = {
    'claim': (
        f'H2 proves the fix is sufficient for recovery: after the same NVA surrogate {nva_vm_name!r} removes the single nftables DROP rule, '
        f'a NEW secret-set attempt succeeded on {app_name}, kvref-h2 appeared, ingress stayed HTTP 200 on {baseline_revision_name!r}, '
        f'and workload-replica probes to both Entra authority hosts succeeded again.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H2 NVA-surrogate allow-remediation gate.',
    'hypothesis': 'H2_nva_surrogate_allow_restores_success',
    'path_used': 'single',
    'predicate_inputs': {
        'h2_rule_removal': repo_rel('10-h2-nva-drop-rule-removed.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_rule_state_and_workload_probe': repo_rel('13-h2-nva-rule-state-and-workload-probe.json'),
    },
    f'{SCENARIO}_h2_nva_surrogate_allow_restores_success_all_subgates_pass': gate16_all,
    f'{SCENARIO}_h2_nva_surrogate_allow_restores_success_sub_gates': {
        'a_h2_nva_drop_rule_removed': subgate_16a,
        'b_h2_secret_set_succeeded_zero_exit': subgate_16b,
        'c_h2_success_gate_holds_revision_unchanged_ingress_200_secret_present': subgate_16c,
        'd_h2_workload_probes_to_both_entra_hosts_succeeded': subgate_16d,
        'e_route_table_to_nva_stayed_constant': subgate_16e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': f'H2 removed the single nftables DROP rule (comment {DROP_RULE_COMMENT!r}) from the same NVA surrogate.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-nva-drop-rule-removed.json')],
            'observed_values': {'nva_rule_removal': h2_rule_removal},
            'predicate': '10.nva_rule_removal.rule_removed == True AND 10.nva_rule_removal.rule_present_after_remove == False.',
            'result': 'pass' if subgate_16a else 'fail',
            'sub_gate': 'a_h2_nva_drop_rule_removed',
        },
        {
            'claim': 'The new H2 secret-set attempt succeeded with exit code 0.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('11-h2-secret-set-outcome.json')],
            'observed_values': {'exit_code': d11.get('exit_code'), 'outcome': d11.get('outcome')},
            'predicate': '11.exit_code == 0 AND 11.outcome == "success".',
            'result': 'pass' if subgate_16b else 'fail',
            'sub_gate': 'b_h2_secret_set_succeeded_zero_exit',
        },
        {
            'claim': 'H2 still leaves the running revision untouched while kvref-h2 appears: revision unchanged, ingress HTTP 200, and kvref-h2 present.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('12-h2-app-state.json')],
            'observed_values': {
                'latest_revision_unchanged_vs_baseline': d12.get('latest_revision_unchanged_vs_baseline'),
                'ingress_probe_http_code': d12.get('ingress_probe_http_code'),
                'observed_secret_present': d12.get('observed_secret_present'),
            },
            'predicate': '12.latest_revision_unchanged_vs_baseline == True AND 12.ingress_probe_http_code == "200" AND 12.observed_secret_present == True.',
            'result': 'pass' if subgate_16c else 'fail',
            'sub_gate': 'c_h2_success_gate_holds_revision_unchanged_ingress_200_secret_present',
        },
        {
            'claim': 'The H2 workload-replica probes to login.microsoftonline.com and login.microsoft.com both succeeded once the NVA-local DROP rule was removed.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('13-h2-nva-rule-state-and-workload-probe.json')],
            'observed_values': {
                'workload_probe': d13.get('workload_probe'),
                'nva_rule_state_rule_present': nva_rule_state_present(d13),
            },
            'predicate': '13.workload_probe[both hosts].outcome == "success" AND 13.nva_rule_state.rule_present == False.',
            'result': 'pass' if subgate_16d else 'fail',
            'sub_gate': 'd_h2_workload_probes_to_both_entra_hosts_succeeded',
        },
        {
            'claim': 'The route table stayed attached with 0.0.0.0/0 to the same NVA-surrogate private IP across H0/H1/H2 while only the NVA drop rule was removed.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-nva-drop-rule-installed.json', '10-h2-nva-drop-rule-removed.json']],
            'observed_values': {
                'h0_default_route': d01.get('route_table_default_route'),
                'h1_default_route': d06.get('route_table_default_route'),
                'h2_default_route': d10.get('route_table_default_route'),
                'route_anchor_consistency': route_anchor_consistency,
            },
            'predicate': 'Route table stays attached with 0.0.0.0/0 to the same NVA private IP across H0/H1/H2.',
            'result': 'pass' if subgate_16e else 'fail',
            'sub_gate': 'e_route_table_to_nva_stayed_constant',
        },
    ],
    'thresholds': {'h2_exit_code_expected': 0, 'h2_nva_drop_rule_expected_present': False},
    'utc_captured': utc_now,
}

held_constant_checks = {
    'resource_group_same_across_h0_h1_h2': all(doc['resource_group'] == anchor_reference['resource_group'] for doc in [*h0_anchor_docs.values(), *h1_anchor_docs.values(), *h2_anchor_docs.values()]),
    'environment_name_same_across_h0_h1_h2': all(doc['environment_name'] == anchor_reference['environment_name'] for doc in [*h0_anchor_docs.values(), *h1_anchor_docs.values(), *h2_anchor_docs.values()]),
    'app_name_same_across_h0_h1_h2': all(doc['app_name'] == anchor_reference['app_name'] for doc in [*h0_anchor_docs.values(), *h1_anchor_docs.values(), *h2_anchor_docs.values()]),
    'app_principal_id_same_across_h0_h1_h2': all(doc['app_principal_id'] == anchor_reference['app_principal_id'] for doc in [*h0_anchor_docs.values(), *h1_anchor_docs.values(), *h2_anchor_docs.values()]),
    'key_vault_name_same_across_h0_h1_h2': all(doc['key_vault_name'] == anchor_reference['key_vault_name'] for doc in [*h0_anchor_docs.values(), *h1_anchor_docs.values(), *h2_anchor_docs.values()]),
    'tenant_id_same_across_h0_h1_h2': all(doc['tenant_id'] == anchor_reference['tenant_id'] for doc in [*h0_anchor_docs.values(), *h1_anchor_docs.values(), *h2_anchor_docs.values()]),
    'baseline_revision_name_same_across_h0_h1_h2': all(doc['baseline_revision_name'] == anchor_reference['baseline_revision_name'] for doc in [*h0_anchor_docs.values(), *h1_anchor_docs.values(), *h2_anchor_docs.values()]),
    'route_default_next_hop_same_across_h0_h1_h2': all(route_doc == route_anchor_reference for route_doc in route_anchor_docs.values()),
    'nva_vm_name_same_across_h0_h1_h2': all(value == nva_vm_name for value in nva_vm_name_refs.values()),
    'nva_private_ip_same_across_h0_h1_h2': all(route_doc['nva_private_ip'] == nva_private_ip for route_doc in route_anchor_docs.values()),
    'nva_drop_rule_present_in_h1_absent_in_h2': (
        h1_rule_install.get('rule_present') is True
        and nva_rule_state_present(d09) is True
        and h2_rule_removal.get('rule_present_after_remove') is False
        and nva_rule_state_present(d13) is False
    ),
    'only_variable_between_h1_and_h2_is_the_nva_drop_rule': (
        h1_rule_install.get('rule_comment') == DROP_RULE_COMMENT
        and h2_rule_removal.get('rule_removed') is True
    ),
}

DOCUMENTED_EXPLICIT_DROPS = [
    'Does NOT prove Palo Alto, Check Point, Fortinet, or any vendor-specific NVA policy or logging behavior.',
    'Does NOT provide a direct ACA control-plane packet capture.',
    'Does NOT prove workload and ACA control-plane egress are identical.',
    'Does NOT claim an Azure Firewall was bypassed, because the H4f topology intentionally has no Azure Firewall.',
    'Does NOT prove behavior beyond the exercised Entra authority hosts login.microsoftonline.com and login.microsoft.com.',
    'Does NOT prove Key Vault data-plane failure (Key Vault, identity, and RBAC stay constant while only the NVA forwarding-plane drop rule flips).',
]

subgate_17a = d04.get('exit_code') == 0 and d04.get('outcome') == 'success' and d01.get('azure_firewall_present') is False and d01.get('nva_surrogate_present') is True
subgate_17b = gate15_all
subgate_17c = gate16_all
subgate_17d = subgate_14d
subgate_17e = all(held_constant_checks.values())
gate17_all = all([subgate_17a, subgate_17b, subgate_17c, subgate_17d, subgate_17e])

gate17 = {
    'claim': (
        f'This evidence pack falsifies the H4f Linux NVA-surrogate hypothesis within a bounded scope on {app_name} in {resource_group} ({location}). '
        f'Non-vacuous proof requires four observations together: (a) H0 baseline success with the route table pointing 0.0.0.0/0 to the NVA surrogate, forwarding and NAT enabled, no Azure Firewall, and no drop rule; '
        f'(b) H1 trigger-presence: the same NVA surrogate installed one nftables forwarding-plane DROP rule for AzureActiveDirectory service-tag prefixes on tcp/443 and the secret set failed with the classifier signature while both workload probes failed; '
        f'(c) H2 fix: the same NVA surrogate removed that rule and a NEW secret-set attempt succeeded while both workload probes recovered; '
        f'(d) the silence invariant held on baseline revision {baseline_revision_name!r}. The bounded conclusion is only that the NVA-surrogate forwarding-plane block of the Entra authority is necessary and sufficient to reproduce this lab\'s secret-resolution failure while all other captured anchors stayed constant.'
    ),
    'claim_level': 'Observed',
    'cohort_binding_note': {
        'claim_ceiling': 'The pack proves a bounded NVA-surrogate forwarding-plane drop inversion only. It does not generalize beyond the explicit drops listed below.',
        'explicit_drops': DOCUMENTED_EXPLICIT_DROPS,
    },
    'gate_classification': 'Bounded falsification gate.',
    'hypothesis': 'H3_bounded_falsification',
    'path_used': 'bounded',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_rule_install': repo_rel('06-h1-nva-drop-rule-installed.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_rule_state_and_workload_probe': repo_rel('09-h1-nva-rule-state-and-workload-probe.json'),
        'h2_rule_removal': repo_rel('10-h2-nva-drop-rule-removed.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_rule_state_and_workload_probe': repo_rel('13-h2-nva-rule-state-and-workload-probe.json'),
    },
    f'{SCENARIO}_h3_bounded_falsification_all_subgates_pass': gate17_all,
    f'{SCENARIO}_h3_bounded_falsification_sub_gates': {
        'a_baseline_presence_h0_succeeded_with_no_drop_rule_and_no_firewall': subgate_17a,
        'b_trigger_presence_h1_failed_with_nva_drop_rule': subgate_17b,
        'c_fix_additive_h2_succeeded_after_nva_drop_rule_removed': subgate_17c,
        'd_silence_invariant_holds_same_revision_across_h0_h1_h2': subgate_17d,
        'e_only_the_documented_nva_drop_rule_changed_between_h1_and_h2': subgate_17e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'Non-vacuous baseline: H0 succeeded with the route table to the NVA surrogate, no Azure Firewall, and no NVA drop rule.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('01-deployment-outputs.json'), repo_rel('04-h0-secret-set-outcome.json')],
            'observed_values': {
                'h0_exit_code': d04.get('exit_code'),
                'azure_firewall_present': d01.get('azure_firewall_present'),
                'nva_surrogate_present': d01.get('nva_surrogate_present'),
            },
            'predicate': '04.exit_code == 0 AND 01.azure_firewall_present == False AND 01.nva_surrogate_present == True.',
            'result': 'pass' if subgate_17a else 'fail',
            'sub_gate': 'a_baseline_presence_h0_succeeded_with_no_drop_rule_and_no_firewall',
        },
        {
            'claim': 'H1 trigger-presence: the NVA surrogate installed the forwarding-plane DROP rule, secret set failed with the classifier signature, and both workload probes failed.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-nva-drop-rule-installed.json'), repo_rel('07-h1-secret-set-outcome.json'), repo_rel('09-h1-nva-rule-state-and-workload-probe.json')],
            'observed_values': {
                'h1_exit_code': d07.get('exit_code'),
                'h1_classifier': h1_classifier,
                'h1_rule_present': h1_rule_install.get('rule_present'),
            },
            'predicate': '06.nva_rule_installation.rule_present == True AND 07.exit_code != 0 AND classifier passes AND 09 both workload probes failed.',
            'result': 'pass' if subgate_17b else 'fail',
            'sub_gate': 'b_trigger_presence_h1_failed_with_nva_drop_rule',
        },
        {
            'claim': 'H2 fix-addition: the NVA surrogate removed the drop rule, the new secret-set attempt succeeded, and both workload probes recovered.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-nva-drop-rule-removed.json'), repo_rel('11-h2-secret-set-outcome.json'), repo_rel('13-h2-nva-rule-state-and-workload-probe.json')],
            'observed_values': {
                'h2_exit_code': d11.get('exit_code'),
                'h2_rule_removed': h2_rule_removal.get('rule_removed'),
                'h2_rule_present_after_remove': h2_rule_removal.get('rule_present_after_remove'),
            },
            'predicate': '10.nva_rule_removal.rule_removed == True AND 11.exit_code == 0 AND 13 both workload probes succeeded.',
            'result': 'pass' if subgate_17c else 'fail',
            'sub_gate': 'c_fix_additive_h2_succeeded_after_nva_drop_rule_removed',
        },
        {
            'claim': 'Silence invariant: the same baseline revision stayed active across H0, H1, and H2.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['02-h0-app-state-before.json', '05-h0-app-state-after.json', '08-h1-app-state.json', '12-h2-app-state.json']],
            'observed_values': {'02': baseline_revision_name, '05': rev_h0_after, '08': rev_h1, '12': rev_h2},
            'predicate': '02 == 05 == 08 == 12 latest_ready_revision_name.',
            'result': 'pass' if subgate_17d else 'fail',
            'sub_gate': 'd_silence_invariant_holds_same_revision_across_h0_h1_h2',
        },
        {
            'claim': 'Between H1 and H2, every non-NVA-rule anchor stayed constant; only the single nftables forwarding-plane DROP rule changed from present to removed.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-nva-drop-rule-installed.json', '09-h1-nva-rule-state-and-workload-probe.json', '10-h2-nva-drop-rule-removed.json', '13-h2-nva-rule-state-and-workload-probe.json']],
            'observed_values': {'held_constant_checks': held_constant_checks},
            'predicate': 'All entries in held_constant_checks are True.',
            'result': 'pass' if subgate_17e else 'fail',
            'sub_gate': 'e_only_the_documented_nva_drop_rule_changed_between_h1_and_h2',
        },
    ],
    'thresholds': {
        'h0_exit_code_expected': 0,
        'h1_exit_code_expected_nonzero': True,
        'h2_exit_code_expected': 0,
        'h1_nva_drop_rule_expected_present': True,
        'h2_nva_drop_rule_expected_present': False,
    },
    'utc_captured': utc_now,
}

gate_payloads = {
    14: gate14,
    15: gate15,
    16: gate16,
    17: gate17,
}
gate_output_map = {
    14: evidence_dir / '14-cohort-integrity-gate.json',
    15: evidence_dir / '15-h1-nva-surrogate-drop-produces-failure-gate.json',
    16: evidence_dir / '16-h2-nva-surrogate-allow-restores-success-gate.json',
    17: evidence_dir / '17-bounded-falsification-gate.json',
}
gate_success_messages = {
    14: 'cohort integrity verified',
    15: 'H1 NVA-surrogate drop produces failure verified',
    16: 'H2 NVA-surrogate allow restores success verified',
    17: 'bounded falsification verified',
}

for number, payload in gate_payloads.items():
    gate_output_map[number].write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')

failures = []
for number, payload in gate_payloads.items():
    sub_gate_map = next(value for key, value in payload.items() if key.endswith('_sub_gates'))
    if all(sub_gate_map.values()):
        print(f'[Gate {number}/17] PASS {gate_success_messages[number]}')
    else:
        failures.append((number, [key for key, value in sub_gate_map.items() if not value]))

if failures:
    for number, failed in failures:
        print(f'[Gate {number}/17] FAIL {gate_success_messages[number]}; failed sub-gates: {", ".join(failed)}')
    sys.exit(1)

print('')
print('=== verify.sh complete ===')
print('All 17 gates PASSED.')
print('Wrote:')
for name in GATE_OUTPUTS:
    print(f'  evidence/{name}')
PY
