#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/aca-secret-kv-ref-mi-network-path-h4e/evidence"
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
    '06-h1-dns-override-created.json',
    '07-h1-secret-set-outcome.json',
    '08-h1-app-state.json',
    '09-h1-replica-dns-view.json',
    '10-h2-dns-override-removed.json',
    '11-h2-secret-set-outcome.json',
    '12-h2-app-state.json',
    '13-h2-replica-dns-view.json',
]

GATE_OUTPUTS = [
    '14-cohort-integrity-gate.json',
    '15-h1-dns-override-produces-failure-gate.json',
    '16-h2-override-removal-restores-success-gate.json',
    '17-bounded-falsification-gate.json',
]

SCENARIO = 'aca_secret_kv_ref_mi_network_path_h4e'


def repo_rel(name: str) -> str:
    return f'{repo_rel_dir}/{name}'


def load_json(name: str):
    return json.loads((evidence_dir / name).read_text(encoding='utf-8'))


def pass_gate(number: int, detail: str):
    print(f'[Gate {number}/17] PASS {detail}')


def fail_gate(number: int, detail: str):
    print(f'[Gate {number}/17] FAIL {detail}')
    sys.exit(1)


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
]
missing_01 = [key for key in required_01 if d01.get(key) in (None, '')]
if missing_01 or d01.get('lab_name') != 'aca-secret-kv-ref-mi-network-path-h4e':
    fail_gate(5, f"01 anchors invalid; missing={missing_01}, lab_name={d01.get('lab_name')}")
pass_gate(5, '01 parses and carries H4e cohort anchors')

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

gate10_problems = []
if d01.get('azure_firewall_present') is not False or int(d01.get('azure_firewall_count_in_rg') or -1) != 0:
    gate10_problems.append('01 must prove no Azure Firewall exists in the resource group')
if d01.get('route_table_attached') is not False or d01.get('aca_subnet_route_table_id') is not None:
    gate10_problems.append('01 must prove no route table is attached to the ACA subnet')
if d01.get('uses_azure_provided_dns') is not True or (d01.get('vnet_dns_servers') or []) != []:
    gate10_problems.append('01 must prove the VNet uses Azure-provided DNS (no custom dnsServers)')
if d06.get('phase') != 'H1' or d06.get('sink_ip') != '192.0.2.1' or int(d06.get('ttl_seconds') or -1) != 10:
    gate10_problems.append('06 must prove the H1 custom override uses sink 192.0.2.1 with TTL 10')
zone_names = set(d06.get('private_dns_zones_in_rg') or [])
if not {'login.microsoftonline.com', 'login.microsoft.com'}.issubset(zone_names):
    gate10_problems.append('06 must prove both custom Private DNS zones exist in H1')
if gate10_problems:
    fail_gate(10, '; '.join(gate10_problems))
pass_gate(10, '01 and 06 prove the non-H4a topology plus H1 DNS override')

if d07.get('phase') != 'H1' or not isinstance(d07.get('exit_code'), int) or d07.get('exit_code') == 0 or d07.get('outcome') != 'failure':
    fail_gate(11, '07 H1 secret set did not fail as expected')
pass_gate(11, '07 H1 secret set failed')

if d08.get('latest_revision_unchanged_vs_baseline') is not True or d08.get('ingress_probe_http_code') != '200' or d08.get('secret_presence_expectation_met') is not True or d08.get('observed_secret_present') is not False:
    fail_gate(12, '08 H1 silence gate invalid')
pass_gate(12, '08 H1 silence gate valid')

if d09.get('phase') != 'H1' or d09.get('observed_sink_presence') is not True:
    fail_gate(13, '09 H1 replica DNS view must show the sink IP')
if d11.get('phase') != 'H2' or d11.get('exit_code') != 0 or d11.get('outcome') != 'success':
    fail_gate(13, '11 H2 secret set must succeed')
if d12.get('latest_revision_unchanged_vs_baseline') is not True or d12.get('ingress_probe_http_code') != '200' or d12.get('secret_presence_expectation_met') is not True or d12.get('observed_secret_present') is not True:
    fail_gate(13, '12 H2 success gate invalid')
if d13.get('phase') != 'H2' or d13.get('observed_sink_presence') is not False:
    fail_gate(13, '13 H2 replica DNS view must stop showing the sink IP')
pass_gate(13, '09-13 H1 sink view + H2 recovery cohort valid')

app_name = d01['app_name']
resource_group = d01['resource_group']
location = d01['location']
vnet_name = d01['vnet_name']
baseline_revision_name = d02['latest_ready_revision_name']

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
    '01': d01.get('app_name'),
    '02': d02.get('app_name'),
    '05': d05.get('app_name'),
    '08': d08.get('app_name'),
    '12': d12.get('app_name'),
}
vnet_refs = {
    '01': d01.get('vnet_name'),
    '06': d06.get('vnet_name'),
}
rev_h0_after = d05.get('latest_ready_revision_name')
rev_h1 = d08.get('latest_ready_revision_name')
rev_h2 = d12.get('latest_ready_revision_name')

subgate_14a = len(timestamp_violations) == 0
subgate_14b = all(value == app_name for value in app_name_refs.values())
subgate_14c = all(value == vnet_name for value in vnet_refs.values())
subgate_14d = baseline_revision_name == rev_h0_after == rev_h1 == rev_h2
subgate_14e = d01.get('azure_firewall_present') is False and d01.get('route_table_attached') is False and d01.get('uses_azure_provided_dns') is True
gate14_all = all([subgate_14a, subgate_14b, subgate_14c, subgate_14d, subgate_14e])

gate14 = {
    'claim': (
        f'The evidence cohort for the aca-secret-kv-ref-mi-network-path-h4e lab on {app_name} '
        f'in {resource_group} ({location}) is internally consistent: all 13 raw files are present '
        f'and parseable, timestamps are monotonic, cross-file anchors agree, the baseline revision '
        f'{baseline_revision_name!r} stays unchanged across H0/H1/H2, and the deployed topology proves '
        f'no Azure Firewall, no UDR, and Azure-provided DNS at baseline.'
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
        'c_vnet_name_anchor_consistent': subgate_14c,
        'd_baseline_revision_silence_invariant_holds': subgate_14d,
        'e_not_h4a_topology_anchored': subgate_14e,
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
            'claim': f'All VNet references equal {vnet_name!r}.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-dns-override-created.json']],
            'observed_values': vnet_refs,
            'predicate': 'All vnet_name fields equal 01.vnet_name.',
            'result': 'pass' if subgate_14c else 'fail',
            'sub_gate': 'c_vnet_name_anchor_consistent',
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
            'claim': 'The baseline topology is explicitly not H4a: no Azure Firewall, no route table on the ACA subnet, and Azure-provided DNS at baseline.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('01-deployment-outputs.json')],
            'observed_values': {
                'azure_firewall_present': d01.get('azure_firewall_present'),
                'azure_firewall_count_in_rg': d01.get('azure_firewall_count_in_rg'),
                'route_table_attached': d01.get('route_table_attached'),
                'aca_subnet_route_table_id': d01.get('aca_subnet_route_table_id'),
                'vnet_dns_servers': d01.get('vnet_dns_servers'),
            },
            'predicate': '01.azure_firewall_present == False AND 01.route_table_attached == False AND 01.vnet_dns_servers == [].',
            'result': 'pass' if subgate_14e else 'fail',
            'sub_gate': 'e_not_h4a_topology_anchored',
        },
    ],
    'thresholds': {'expected_raw_file_count': 13, 'expected_gate_output_count': 4},
    'utc_captured': utc_now,
}

subgate_15a = d04.get('exit_code') == 0 and d04.get('outcome') == 'success'
subgate_15b = (
    d06.get('sink_ip') == '192.0.2.1'
    and int(d06.get('ttl_seconds') or -1) == 10
    and {'login.microsoftonline.com', 'login.microsoft.com'}.issubset(set(d06.get('private_dns_zones_in_rg') or []))
)
subgate_15c = isinstance(d07.get('exit_code'), int) and d07.get('exit_code') != 0 and d07.get('outcome') == 'failure'
subgate_15d = (
    d08.get('latest_revision_unchanged_vs_baseline') is True
    and d08.get('ingress_probe_http_code') == '200'
    and d08.get('secret_presence_expectation_met') is True
    and d08.get('observed_secret_present') is False
)
subgate_15e = d09.get('observed_sink_presence') is True
gate15_all = all([subgate_15a, subgate_15b, subgate_15c, subgate_15d, subgate_15e])

gate15 = {
    'claim': (
        f'H1 proves the DNS-override trigger: after linking custom Private DNS zones for the Entra authority to {vnet_name!r} '
        f'with apex A records pointing to 192.0.2.1, `az containerapp secret set --identity system --key-vault-url ...` '
        f'fails on {app_name}, the baseline revision {baseline_revision_name!r} keeps serving HTTP 200, kvref-h1 stays absent, '
        f'and a replica nslookup of login.microsoftonline.com resolves to the sink IP.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H1 DNS-override gate.',
    'hypothesis': 'H1_dns_override_produces_failure',
    'path_used': 'single',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_override_created': repo_rel('06-h1-dns-override-created.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_app_state': repo_rel('08-h1-app-state.json'),
        'h1_replica_dns_view': repo_rel('09-h1-replica-dns-view.json'),
    },
    f'{SCENARIO}_h1_dns_override_produces_failure_all_subgates_pass': gate15_all,
    f'{SCENARIO}_h1_dns_override_produces_failure_sub_gates': {
        'a_baseline_h0_succeeded_without_override': subgate_15a,
        'b_custom_private_dns_override_present_for_both_entra_hosts': subgate_15b,
        'c_h1_secret_set_failed_nonzero_exit': subgate_15c,
        'd_silence_gate_holds_revision_unchanged_ingress_200_secret_absent': subgate_15d,
        'e_replica_dns_view_resolves_entra_authority_to_sink_ip': subgate_15e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'The H0 baseline succeeded before H1.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('04-h0-secret-set-outcome.json')],
            'observed_values': {'exit_code': d04.get('exit_code'), 'outcome': d04.get('outcome')},
            'predicate': '04.exit_code == 0 AND 04.outcome == "success".',
            'result': 'pass' if subgate_15a else 'fail',
            'sub_gate': 'a_baseline_h0_succeeded_without_override',
        },
        {
            'claim': 'H1 created custom Private DNS overrides for both Entra authority zones, with apex A records pointed at 192.0.2.1.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-dns-override-created.json')],
            'observed_values': {
                'private_dns_zones_in_rg': d06.get('private_dns_zones_in_rg'),
                'sink_ip': d06.get('sink_ip'),
                'ttl_seconds': d06.get('ttl_seconds'),
            },
            'predicate': '06 proves both zones exist and point to 192.0.2.1 with TTL 10.',
            'result': 'pass' if subgate_15b else 'fail',
            'sub_gate': 'b_custom_private_dns_override_present_for_both_entra_hosts',
        },
        {
            'claim': 'The H1 secret-set attempt failed with a non-zero exit code.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('07-h1-secret-set-outcome.json')],
            'observed_values': {'exit_code': d07.get('exit_code'), 'outcome': d07.get('outcome')},
            'predicate': '07.exit_code != 0 AND 07.outcome == "failure".',
            'result': 'pass' if subgate_15c else 'fail',
            'sub_gate': 'c_h1_secret_set_failed_nonzero_exit',
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
            'result': 'pass' if subgate_15d else 'fail',
            'sub_gate': 'd_silence_gate_holds_revision_unchanged_ingress_200_secret_absent',
        },
        {
            'claim': 'The data-plane DNS view inside a running replica resolves login.microsoftonline.com to the TEST-NET-1 sink address 192.0.2.1.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('09-h1-replica-dns-view.json')],
            'observed_values': {'observed_sink_presence': d09.get('observed_sink_presence'), 'parsed_ips': (d09.get('parsed') or {}).get('ips', [])},
            'predicate': '09.observed_sink_presence == True.',
            'result': 'pass' if subgate_15e else 'fail',
            'sub_gate': 'e_replica_dns_view_resolves_entra_authority_to_sink_ip',
        },
    ],
    'thresholds': {'h1_exit_code_expected_nonzero': True, 'ttl_seconds_expected_exact': 10, 'sink_ip_expected_exact': '192.0.2.1'},
    'utc_captured': utc_now,
}

subgate_16a = 'login.microsoftonline.com' not in (d10.get('remaining_private_dns_zones_in_rg') or []) and 'login.microsoft.com' not in (d10.get('remaining_private_dns_zones_in_rg') or [])
subgate_16b = int(d10.get('post_removal_wait_seconds') or 0) > int(d10.get('ttl_seconds') or 0)
subgate_16c = isinstance(d11.get('exit_code'), int) and d11.get('exit_code') == 0 and d11.get('outcome') == 'success'
subgate_16d = (
    d12.get('latest_revision_unchanged_vs_baseline') is True
    and d12.get('ingress_probe_http_code') == '200'
    and d12.get('secret_presence_expectation_met') is True
    and d12.get('observed_secret_present') is True
)
subgate_16e = d13.get('observed_sink_presence') is False
gate16_all = all([subgate_16a, subgate_16b, subgate_16c, subgate_16d, subgate_16e])

gate16 = {
    'claim': (
        f'H2 proves the override removal is sufficient for recovery: both custom Private DNS zones are gone, the post-removal wait exceeds the TTL, '
        f'a NEW secret-set attempt succeeds on {app_name}, kvref-h2 appears, ingress stays HTTP 200 on {baseline_revision_name!r}, '
        f'and a replica nslookup of login.microsoftonline.com no longer returns 192.0.2.1.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H2 override-removal gate.',
    'hypothesis': 'H2_override_removal_restores_success',
    'path_used': 'single',
    'predicate_inputs': {
        'h2_override_removed': repo_rel('10-h2-dns-override-removed.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_replica_dns_view': repo_rel('13-h2-replica-dns-view.json'),
    },
    f'{SCENARIO}_h2_override_removal_restores_success_all_subgates_pass': gate16_all,
    f'{SCENARIO}_h2_override_removal_restores_success_sub_gates': {
        'a_private_dns_override_removed_for_both_entra_hosts': subgate_16a,
        'b_post_removal_wait_exceeded_record_ttl': subgate_16b,
        'c_h2_secret_set_succeeded_zero_exit': subgate_16c,
        'd_h2_success_gate_holds_revision_unchanged_ingress_200_secret_present': subgate_16d,
        'e_replica_dns_view_no_longer_resolves_to_sink_ip': subgate_16e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'H2 removed both custom Private DNS zones or their VNet links, so the override no longer exists.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-dns-override-removed.json')],
            'observed_values': {'remaining_private_dns_zones_in_rg': d10.get('remaining_private_dns_zones_in_rg')},
            'predicate': '10.remaining_private_dns_zones_in_rg contains neither login.microsoftonline.com nor login.microsoft.com.',
            'result': 'pass' if subgate_16a else 'fail',
            'sub_gate': 'a_private_dns_override_removed_for_both_entra_hosts',
        },
        {
            'claim': 'The post-removal wait exceeded the record TTL, bounding the DNS-cache confounder.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-dns-override-removed.json')],
            'observed_values': {'ttl_seconds': d10.get('ttl_seconds'), 'post_removal_wait_seconds': d10.get('post_removal_wait_seconds')},
            'predicate': '10.post_removal_wait_seconds > 10.ttl_seconds.',
            'result': 'pass' if subgate_16b else 'fail',
            'sub_gate': 'b_post_removal_wait_exceeded_record_ttl',
        },
        {
            'claim': 'The new H2 secret-set attempt succeeded with exit code 0.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('11-h2-secret-set-outcome.json')],
            'observed_values': {'exit_code': d11.get('exit_code'), 'outcome': d11.get('outcome')},
            'predicate': '11.exit_code == 0 AND 11.outcome == "success".',
            'result': 'pass' if subgate_16c else 'fail',
            'sub_gate': 'c_h2_secret_set_succeeded_zero_exit',
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
            'result': 'pass' if subgate_16d else 'fail',
            'sub_gate': 'd_h2_success_gate_holds_revision_unchanged_ingress_200_secret_present',
        },
        {
            'claim': 'After the override removal, the data-plane DNS view no longer resolves login.microsoftonline.com to 192.0.2.1.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('13-h2-replica-dns-view.json')],
            'observed_values': {'observed_sink_presence': d13.get('observed_sink_presence'), 'parsed_ips': (d13.get('parsed') or {}).get('ips', [])},
            'predicate': '13.observed_sink_presence == False.',
            'result': 'pass' if subgate_16e else 'fail',
            'sub_gate': 'e_replica_dns_view_no_longer_resolves_to_sink_ip',
        },
    ],
    'thresholds': {'h2_exit_code_expected': 0, 'post_removal_wait_seconds_expected_gt_ttl': True, 'sink_ip_expected_absent': '192.0.2.1'},
    'utc_captured': utc_now,
}

held_constant_checks = {
    'app_name_same': d08.get('app_name') == d12.get('app_name') == app_name,
    'vnet_name_same': d06.get('vnet_name') == d01.get('vnet_name') == vnet_name,
    'same_key_vault_across_h0_h1_h2': d01.get('key_vault_name') == d03.get('key_vault_name'),
    'baseline_revision_same': d08.get('latest_ready_revision_name') == d12.get('latest_ready_revision_name') == baseline_revision_name,
    'no_firewall_no_udr_both_phases': d06.get('azure_firewall_present') is False and d06.get('route_table_attached') is False and d10.get('azure_firewall_present') is False and d10.get('route_table_attached') is False,
    'azure_provided_dns_both_phases': d06.get('uses_azure_provided_dns') is True and d10.get('uses_azure_provided_dns') is True,
    'dns_override_flipped_only': d09.get('observed_sink_presence') is True and d13.get('observed_sink_presence') is False,
}

DOCUMENTED_EXPLICIT_DROPS = [
    {
        'id': 'control_plane_vs_data_plane_dns_view_equivalence',
        'note': 'The pack proves the replica data-plane DNS view directly, but it does not prove that the ACA control-plane secret resolver shares an identical DNS view. The control-plane implication is inferred from the H0/H1/H2 secret-set outcomes only.',
    },
    {
        'id': 'exact_stderr_wording',
        'note': 'The pack does not gate on exact CLI stderr wording because Azure CLI wrapping varies by version.',
    },
    {
        'id': 'dns_cache_and_ttl_propagation_timing',
        'note': 'The pack proves only that the configured wait exceeded TTL and the H2 outcome recovered; it does not prove exact propagation or cache-expiry timing inside every ACA component.',
    },
    {
        'id': 'no_supported_privatelink_zone_for_entra_authority',
        'note': 'Microsoft does not publish a supported privatelink.microsoftonline.com zone for the Entra authority; this lab covers a custom DNS override only, not a productized Private Endpoint DNS pattern.',
    },
    {
        'id': 'aca_control_plane_component_identity',
        'note': 'The pack does not identify the specific internal ACA component that performed the Entra discovery call.',
    },
    {
        'id': 'token_caching_and_retry_behavior',
        'note': 'The pack does not prove all ACA token-caching or retry internals around the failed and recovered secret-set attempts.',
    },
    {
        'id': 'region_generality',
        'note': 'The pack covers one regional cohort only and does not generalize across regions.',
    },
]

subgate_17a = subgate_15a
subgate_17b = subgate_15b and subgate_15c and subgate_15e
subgate_17c = subgate_16a and subgate_16b and subgate_16c and subgate_16e
subgate_17d = subgate_14d
subgate_17e = all(held_constant_checks.values())
gate17_all = all([subgate_17a, subgate_17b, subgate_17c, subgate_17d, subgate_17e])

gate17 = {
    'claim': (
        f'This evidence pack falsifies the H4e DNS-override hypothesis within a bounded scope on {app_name} in {resource_group} ({location}). '
        f'Non-vacuous proof requires four observations together: (a) H0 baseline success without any override; '
        f'(b) H1 trigger-presence: custom Private DNS overrides for both Entra authority hosts existed, secret set failed, and the replica DNS view resolved to 192.0.2.1; '
        f'(c) H2 fix: the override was removed, the wait exceeded TTL, a NEW secret-set attempt succeeded, and the replica DNS view no longer resolved to 192.0.2.1; '
        f'(d) the silence invariant held on baseline revision {baseline_revision_name!r}. The bounded H1↔H2 claim is only that the custom DNS override is the controlled variable while Key Vault, identity, RBAC, and topology stayed constant.'
    ),
    'claim_level': 'Observed',
    'cohort_binding_note': {
        'claim_ceiling': 'The pack proves a bounded DNS-override inversion only. It does not generalize beyond the explicit drops listed below.',
        'explicit_drops': DOCUMENTED_EXPLICIT_DROPS,
    },
    'gate_classification': 'Bounded falsification gate.',
    'hypothesis': 'H3_bounded_falsification',
    'path_used': 'bounded',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_override_created': repo_rel('06-h1-dns-override-created.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_replica_dns_view': repo_rel('09-h1-replica-dns-view.json'),
        'h2_override_removed': repo_rel('10-h2-dns-override-removed.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_replica_dns_view': repo_rel('13-h2-replica-dns-view.json'),
    },
    f'{SCENARIO}_h3_bounded_falsification_all_subgates_pass': gate17_all,
    f'{SCENARIO}_h3_bounded_falsification_sub_gates': {
        'a_baseline_presence_h0_succeeded_without_override': subgate_17a,
        'b_trigger_presence_h1_failed_with_dns_override_present': subgate_17b,
        'c_fix_removal_h2_succeeded_with_dns_override_removed': subgate_17c,
        'd_silence_invariant_holds_same_revision_across_h0_h1_h2': subgate_17d,
        'e_only_the_documented_dns_override_variable_changed_between_h1_and_h2': subgate_17e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'Non-vacuous baseline: H0 succeeded without the custom DNS override.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('04-h0-secret-set-outcome.json')],
            'observed_values': {'h0_exit_code': d04.get('exit_code'), 'h0_outcome': d04.get('outcome')},
            'predicate': '04.exit_code == 0.',
            'result': 'pass' if subgate_17a else 'fail',
            'sub_gate': 'a_baseline_presence_h0_succeeded_without_override',
        },
        {
            'claim': 'H1 trigger-presence: the override existed, secret set failed, and the replica DNS view resolved to the sink IP.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-dns-override-created.json'), repo_rel('07-h1-secret-set-outcome.json'), repo_rel('09-h1-replica-dns-view.json')],
            'observed_values': {'h1_exit_code': d07.get('exit_code'), 'h1_sink_present': d09.get('observed_sink_presence')},
            'predicate': '06 creates the override AND 07.exit_code != 0 AND 09.observed_sink_presence == True.',
            'result': 'pass' if subgate_17b else 'fail',
            'sub_gate': 'b_trigger_presence_h1_failed_with_dns_override_present',
        },
        {
            'claim': 'H2 fix-removal: the override was removed, the wait exceeded TTL, secret set succeeded, and the replica DNS view stopped resolving to the sink IP.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-dns-override-removed.json'), repo_rel('11-h2-secret-set-outcome.json'), repo_rel('13-h2-replica-dns-view.json')],
            'observed_values': {'h2_exit_code': d11.get('exit_code'), 'h2_sink_present': d13.get('observed_sink_presence')},
            'predicate': '10 removes the override AND 10.post_removal_wait_seconds > 10.ttl_seconds AND 11.exit_code == 0 AND 13.observed_sink_presence == False.',
            'result': 'pass' if subgate_17c else 'fail',
            'sub_gate': 'c_fix_removal_h2_succeeded_with_dns_override_removed',
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
            'claim': 'Between H1 and H2, every non-DNS anchor stayed constant; only the documented DNS override flipped from present to removed while the topology remained no-firewall/no-UDR.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['06-h1-dns-override-created.json', '08-h1-app-state.json', '10-h2-dns-override-removed.json', '12-h2-app-state.json']],
            'observed_values': {'held_constant_checks': held_constant_checks},
            'predicate': 'All entries in held_constant_checks are True.',
            'result': 'pass' if subgate_17e else 'fail',
            'sub_gate': 'e_only_the_documented_dns_override_variable_changed_between_h1_and_h2',
        },
    ],
    'thresholds': {
        'h0_exit_code_expected': 0,
        'h1_exit_code_expected_nonzero': True,
        'h2_exit_code_expected': 0,
        'dns_ttl_seconds_expected_exact': 10,
        'sink_ip_expected_exact': '192.0.2.1',
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
    15: evidence_dir / '15-h1-dns-override-produces-failure-gate.json',
    16: evidence_dir / '16-h2-override-removal-restores-success-gate.json',
    17: evidence_dir / '17-bounded-falsification-gate.json',
}
gate_success_messages = {
    14: 'cohort integrity verified',
    15: 'H1 DNS override produces failure verified',
    16: 'H2 override removal restores success verified',
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
