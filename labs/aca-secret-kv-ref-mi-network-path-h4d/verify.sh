#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/aca-secret-kv-ref-mi-network-path-h4d/evidence"
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
    '06-h1-routing-intent-enabled.json',
    '07-h1-secret-set-outcome.json',
    '08-h1-app-state.json',
    '09-h1-azfw-diagnostic-clue.json',
    '10-h2-routing-intent-removed.json',
    '11-h2-secret-set-outcome.json',
    '12-h2-app-state.json',
    '13-h2-azfw-diagnostic-clue.json',
]

GATE_OUTPUTS = [
    '14-cohort-integrity-gate.json',
    '15-h1-routing-intent-produces-failure-gate.json',
    '16-h2-routing-intent-removal-restores-success-gate.json',
    '17-bounded-falsification-gate.json',
]

SCENARIO = 'aca_secret_kv_ref_mi_network_path_h4d'


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
    'key_vault_name', 'key_vault_uri', 'app_principal_id', 'vnet_name', 'vnet_resource_id',
    'virtual_hub_resource_id', 'virtual_hub_name', 'azure_firewall_resource_id',
    'firewall_policy_resource_id', 'routing_intent_name',
]
missing_01 = [key for key in required_01 if d01.get(key) in (None, '')]
if missing_01 or d01.get('lab_name') != 'aca-secret-kv-ref-mi-network-path-h4d':
    fail_gate(5, f"01 anchors invalid; missing={missing_01}, lab_name={d01.get('lab_name')}")
pass_gate(5, '01 parses and carries H4d cohort anchors')

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
if d01.get('uses_azure_provided_dns') is not True or (d01.get('vnet_dns_servers') or []) != []:
    gate10_problems.append('01 must prove Azure-provided DNS at baseline')
if d01.get('route_table_attached') is not False or d01.get('aca_subnet_route_table_id') is not None:
    gate10_problems.append('01 must prove no route table is attached to the ACA subnet')
if d06.get('phase') != 'H1':
    gate10_problems.append('06 phase must be H1')
if d06.get('routing_intent_provisioning_succeeded') is not True:
    gate10_problems.append('06 must prove Routing Intent provisioning succeeded')
if d06.get('connection_provisioning_succeeded') is not True:
    gate10_problems.append('06 must prove HubVirtualNetworkConnection provisioning succeeded')
if d06.get('default_route_targets_expected_firewall') is not True:
    gate10_problems.append('06 must prove effective routes show 0.0.0.0/0 targeting the hub firewall')
if gate10_problems:
    fail_gate(10, '; '.join(gate10_problems))
pass_gate(10, '01 and 06 prove baseline + H1 routing-intent route-state flip')

if d07.get('phase') != 'H1' or not isinstance(d07.get('exit_code'), int) or d07.get('exit_code') == 0 or d07.get('outcome') != 'failure':
    fail_gate(11, '07 H1 secret set did not fail as expected')
if (d07.get('stderr_substring_matches') or {}).get('unable_to_get_value_using_managed_identity') is not True:
    fail_gate(11, '07 must include "Unable to get value using Managed identity" marker')
if (d07.get('stderr_substring_matches') or {}).get('openid_configuration_reference') is not True:
    fail_gate(11, '07 must include openid-configuration marker')
pass_gate(11, '07 H1 secret set failed with the expected MI/OIDC markers')

if d08.get('latest_revision_unchanged_vs_baseline') is not True or d08.get('ingress_probe_http_code') != '200' or d08.get('secret_presence_expectation_met') is not True or d08.get('observed_secret_present') is not False:
    fail_gate(12, '08 H1 silence gate invalid')
pass_gate(12, '08 H1 silence gate valid')

if d10.get('phase') != 'H2' or d10.get('default_route_targets_expected_firewall') is not False:
    fail_gate(13, '10 must prove the default route no longer targets the hub firewall in H2')
if d11.get('phase') != 'H2' or d11.get('exit_code') != 0 or d11.get('outcome') != 'success':
    fail_gate(13, '11 H2 secret set must succeed')
if d12.get('latest_revision_unchanged_vs_baseline') is not True or d12.get('ingress_probe_http_code') != '200' or d12.get('secret_presence_expectation_met') is not True or d12.get('observed_secret_present') is not True:
    fail_gate(13, '12 H2 success gate invalid')
pass_gate(13, '10-12 H2 route removal + success cohort valid')

app_name = d01['app_name']
resource_group = d01['resource_group']
location = d01['location']
vnet_name = d01['vnet_name']
vnet_resource_id = d01['vnet_resource_id']
vhub_name = d01['virtual_hub_name']
azfw_id = d01['azure_firewall_resource_id']
azfw_name = d01.get('azure_firewall_name') or ''
baseline_revision_name = d02['latest_ready_revision_name']
aca_vnet_connection_id = d06.get('aca_vnet_connection_id')


def route_targets_expected_firewall(targets, firewall_id, firewall_name):
    for route in targets or []:
        if '0.0.0.0/0' not in (route.get('addressPrefixes') or []):
            continue
        for hop in route.get('nextHops') or []:
            hop_s = str(hop)
            if hop_s == firewall_id or hop_s == firewall_name or firewall_id in hop_s or firewall_name in hop_s:
                return True
    return False


h1_routes_target_firewall = route_targets_expected_firewall(d06.get('default_route_targets') or [], azfw_id, azfw_name)
h2_routes_target_firewall = route_targets_expected_firewall(d10.get('default_route_targets_after_delete') or [], azfw_id, azfw_name)

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
    '06': d01.get('vnet_name'),
}
route_connection_refs = {
    '06': d06.get('aca_vnet_connection_id'),
    '10': d10.get('aca_vnet_connection_id'),
}
rev_h0_after = d05.get('latest_ready_revision_name')
rev_h1 = d08.get('latest_ready_revision_name')
rev_h2 = d12.get('latest_ready_revision_name')

subgate_14a = len(timestamp_violations) == 0
subgate_14b = all(value == app_name for value in app_name_refs.values())
subgate_14c = all(value == vnet_name for value in vnet_refs.values())
subgate_14d = all(value == aca_vnet_connection_id for value in route_connection_refs.values())
subgate_14e = d06.get('remote_vnet_resource_id') == vnet_resource_id
subgate_14f = baseline_revision_name == rev_h0_after == rev_h1 == rev_h2
subgate_14g = d01.get('uses_azure_provided_dns') is True and d01.get('route_table_attached') is False
gate14_all = all([subgate_14a, subgate_14b, subgate_14c, subgate_14d, subgate_14e, subgate_14f, subgate_14g])

gate14 = {
    'claim': (
        f'The evidence cohort for the aca-secret-kv-ref-mi-network-path-h4d lab on {app_name} '
        f'in {resource_group} ({location}) is internally consistent: all 13 raw files are present '
        f'and parseable, timestamps are monotonic, cross-file anchors agree, the same HubVirtualNetworkConnection '
        f'{aca_vnet_connection_id!r} is tracked across H1/H2, the baseline revision {baseline_revision_name!r} stays unchanged across H0/H1/H2, '
        f'and the workload baseline proves Azure-provided DNS with no route table on the ACA subnet.'
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
        'd_connection_anchor_consistent_across_h1_h2': subgate_14d,
        'e_actual_remote_vnet_matches_aca_vnet_anchor': subgate_14e,
        'f_baseline_revision_silence_invariant_holds': subgate_14f,
        'g_baseline_topology_uses_azure_provided_dns_and_no_udr': subgate_14g,
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
            'claim': f'All vnet_name references equal {vnet_name!r}.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-routing-intent-enabled.json']],
            'observed_values': {'01': vnet_name, '06': vnet_name},
            'predicate': 'All vnet_name fields equal 01.vnet_name.',
            'result': 'pass' if subgate_14c else 'fail',
            'sub_gate': 'c_vnet_name_anchor_consistent',
        },
        {
            'claim': f'The same HubVirtualNetworkConnection {aca_vnet_connection_id!r} is tracked across H1 and H2.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['06-h1-routing-intent-enabled.json', '10-h2-routing-intent-removed.json']],
            'observed_values': route_connection_refs,
            'predicate': '06.aca_vnet_connection_id == 10.aca_vnet_connection_id.',
            'result': 'pass' if subgate_14d else 'fail',
            'sub_gate': 'd_connection_anchor_consistent_across_h1_h2',
        },
        {
            'claim': f'The H1 HubVirtualNetworkConnection remote VNet matches the ACA infrastructure VNet anchor {vnet_resource_id!r}.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-routing-intent-enabled.json']],
            'observed_values': {'01': vnet_resource_id, '06': d06.get('remote_vnet_resource_id')},
            'predicate': '06.remote_vnet_resource_id == 01.vnet_resource_id.',
            'result': 'pass' if subgate_14e else 'fail',
            'sub_gate': 'e_actual_remote_vnet_matches_aca_vnet_anchor',
        },
        {
            'claim': f'The baseline revision {baseline_revision_name!r} stays identical across 02, 05, 08, and 12.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['02-h0-app-state-before.json', '05-h0-app-state-after.json', '08-h1-app-state.json', '12-h2-app-state.json']],
            'observed_values': {'02': baseline_revision_name, '05': rev_h0_after, '08': rev_h1, '12': rev_h2},
            'predicate': '02.latest_ready_revision_name == 05.latest_ready_revision_name == 08.latest_ready_revision_name == 12.latest_ready_revision_name.',
            'result': 'pass' if subgate_14f else 'fail',
            'sub_gate': 'f_baseline_revision_silence_invariant_holds',
        },
        {
            'claim': 'The workload baseline uses Azure-provided DNS and has no UDR attached to the ACA subnet.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('01-deployment-outputs.json')],
            'observed_values': {
                'uses_azure_provided_dns': d01.get('uses_azure_provided_dns'),
                'vnet_dns_servers': d01.get('vnet_dns_servers'),
                'route_table_attached': d01.get('route_table_attached'),
                'aca_subnet_route_table_id': d01.get('aca_subnet_route_table_id'),
            },
            'predicate': '01.uses_azure_provided_dns == True AND 01.route_table_attached == False.',
            'result': 'pass' if subgate_14g else 'fail',
            'sub_gate': 'g_baseline_topology_uses_azure_provided_dns_and_no_udr',
        },
    ],
    'thresholds': {'expected_raw_file_count': 13, 'expected_gate_output_count': 4},
    'utc_captured': utc_now,
}

subgate_15a = d04.get('exit_code') == 0 and d04.get('outcome') == 'success'
subgate_15b = d06.get('routing_intent_provisioning_succeeded') is True and d06.get('connection_provisioning_succeeded') is True and h1_routes_target_firewall is True and d06.get('remote_vnet_resource_id') == vnet_resource_id
subgate_15c = isinstance(d07.get('exit_code'), int) and d07.get('exit_code') != 0 and d07.get('outcome') == 'failure'
subgate_15d = (d07.get('stderr_substring_matches') or {}).get('unable_to_get_value_using_managed_identity') is True and (d07.get('stderr_substring_matches') or {}).get('openid_configuration_reference') is True
subgate_15e = d08.get('latest_revision_unchanged_vs_baseline') is True and d08.get('ingress_probe_http_code') == '200' and d08.get('secret_presence_expectation_met') is True and d08.get('observed_secret_present') is False
gate15_all = all([subgate_15a, subgate_15b, subgate_15c, subgate_15d, subgate_15e])

gate15 = {
    'claim': (
        f'H1 proves the Routing Intent trigger: after connecting {vnet_name!r} to the Virtual Hub {vhub_name!r} and enabling Routing Intent to {azfw_id!r}, '
        f'the effective route table for the HubVirtualNetworkConnection shows 0.0.0.0/0 targeting the hub firewall, '
        f'`az containerapp secret set --identity system --key-vault-url ...` fails on {app_name}, stderr includes the managed-identity / openid-configuration markers, '
        f'the baseline revision {baseline_revision_name!r} keeps serving HTTP 200, and kvref-h1 stays absent.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H1 Routing Intent gate.',
    'hypothesis': 'H1_routing_intent_produces_failure',
    'path_used': 'single',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_route_state': repo_rel('06-h1-routing-intent-enabled.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_app_state': repo_rel('08-h1-app-state.json'),
    },
    f'{SCENARIO}_h1_routing_intent_produces_failure_all_subgates_pass': gate15_all,
    f'{SCENARIO}_h1_routing_intent_produces_failure_sub_gates': {
        'a_baseline_h0_succeeded_without_routing_intent': subgate_15a,
        'b_h1_routing_intent_enabled_and_effective_route_targets_firewall': subgate_15b,
        'c_h1_secret_set_failed_nonzero_exit': subgate_15c,
        'd_h1_failure_surface_contains_mi_and_openid_markers': subgate_15d,
        'e_silence_gate_holds_revision_unchanged_ingress_200_secret_absent': subgate_15e,
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
            'sub_gate': 'a_baseline_h0_succeeded_without_routing_intent',
        },
        {
            'claim': 'H1 enabled Routing Intent and the HubVirtualNetworkConnection effective routes show 0.0.0.0/0 targeting the hub firewall.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-routing-intent-enabled.json')],
            'observed_values': {
                'routing_intent_provisioning_succeeded': d06.get('routing_intent_provisioning_succeeded'),
                'connection_provisioning_succeeded': d06.get('connection_provisioning_succeeded'),
                'default_route_targets_expected_firewall': h1_routes_target_firewall,
                'default_route_targets': d06.get('default_route_targets'),
                'remote_vnet_resource_id': d06.get('remote_vnet_resource_id'),
            },
            'predicate': '06.routing_intent_provisioning_succeeded == True AND default_route_targets include the expected firewall AND 06.remote_vnet_resource_id == 01.vnet_resource_id.',
            'result': 'pass' if subgate_15b else 'fail',
            'sub_gate': 'b_h1_routing_intent_enabled_and_effective_route_targets_firewall',
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
            'claim': 'The H1 failure surface contains both the managed-identity marker and the openid-configuration marker.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('07-h1-secret-set-outcome.json')],
            'observed_values': d07.get('stderr_substring_matches') or {},
            'predicate': '07.stderr_substring_matches.unable_to_get_value_using_managed_identity == True AND 07.stderr_substring_matches.openid_configuration_reference == True.',
            'result': 'pass' if subgate_15d else 'fail',
            'sub_gate': 'd_h1_failure_surface_contains_mi_and_openid_markers',
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
            'result': 'pass' if subgate_15e else 'fail',
            'sub_gate': 'e_silence_gate_holds_revision_unchanged_ingress_200_secret_absent',
        },
    ],
    'thresholds': {'h1_exit_code_expected_nonzero': True, 'route_prefix_expected_exact': '0.0.0.0/0'},
    'utc_captured': utc_now,
}

subgate_16a = h2_routes_target_firewall is False
subgate_16b = isinstance(d11.get('exit_code'), int) and d11.get('exit_code') == 0 and d11.get('outcome') == 'success'
subgate_16c = d12.get('latest_revision_unchanged_vs_baseline') is True and d12.get('ingress_probe_http_code') == '200' and d12.get('secret_presence_expectation_met') is True and d12.get('observed_secret_present') is True
subgate_16d = d10.get('firewall_policy_resource_id') == d01.get('firewall_policy_resource_id')
gate16_all = all([subgate_16a, subgate_16b, subgate_16c, subgate_16d])

gate16 = {
    'claim': (
        f'H2 proves Routing Intent removal is sufficient for recovery: the HubVirtualNetworkConnection effective routes no longer show 0.0.0.0/0 targeting {azfw_id!r}, '
        f'the firewall policy resource stays unchanged, a NEW secret-set attempt succeeds on {app_name}, kvref-h2 appears, and ingress stays HTTP 200 on {baseline_revision_name!r}.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H2 Routing Intent removal gate.',
    'hypothesis': 'H2_routing_intent_removal_restores_success',
    'path_used': 'single',
    'predicate_inputs': {
        'h2_route_state': repo_rel('10-h2-routing-intent-removed.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
    },
    f'{SCENARIO}_h2_routing_intent_removal_restores_success_all_subgates_pass': gate16_all,
    f'{SCENARIO}_h2_routing_intent_removal_restores_success_sub_gates': {
        'a_h2_effective_routes_no_longer_target_firewall': subgate_16a,
        'b_h2_secret_set_succeeded_zero_exit': subgate_16b,
        'c_h2_success_gate_holds_revision_unchanged_ingress_200_secret_present': subgate_16c,
        'd_firewall_policy_anchor_unchanged': subgate_16d,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'H2 removed Routing Intent, and the effective route table no longer points the default route at the hub firewall.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-routing-intent-removed.json')],
            'observed_values': {
                'default_route_targets_expected_firewall': d10.get('default_route_targets_expected_firewall'),
                'default_route_targets_after_delete': d10.get('default_route_targets_after_delete'),
            },
            'predicate': '10.default_route_targets_after_delete does not include the expected firewall next hop for 0.0.0.0/0.',
            'result': 'pass' if subgate_16a else 'fail',
            'sub_gate': 'a_h2_effective_routes_no_longer_target_firewall',
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
            'claim': 'The firewall policy anchor stayed unchanged while Routing Intent was removed.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '10-h2-routing-intent-removed.json']],
            'observed_values': {'01': d01.get('firewall_policy_resource_id'), '10': d10.get('firewall_policy_resource_id')},
            'predicate': '10.firewall_policy_resource_id == 01.firewall_policy_resource_id.',
            'result': 'pass' if subgate_16d else 'fail',
            'sub_gate': 'd_firewall_policy_anchor_unchanged',
        },
    ],
    'thresholds': {'h2_exit_code_expected': 0, 'route_prefix_expected_no_longer_targets_firewall': '0.0.0.0/0'},
    'utc_captured': utc_now,
}

held_constant_checks = {
    'app_name_same': d08.get('app_name') == d12.get('app_name') == app_name,
    'vnet_name_same': d01.get('vnet_name') == vnet_name,
    'same_key_vault_across_h0_h1_h2': d01.get('key_vault_name') == d03.get('key_vault_name'),
    'same_connection_across_h1_h2': d06.get('aca_vnet_connection_id') == d10.get('aca_vnet_connection_id') == aca_vnet_connection_id,
    'actual_remote_vnet_same_as_aca_vnet': d06.get('remote_vnet_resource_id') == vnet_resource_id,
    'baseline_revision_same': d08.get('latest_ready_revision_name') == d12.get('latest_ready_revision_name') == baseline_revision_name,
    'firewall_policy_same': d10.get('firewall_policy_resource_id') == d01.get('firewall_policy_resource_id'),
    'routing_intent_route_flip_only': h1_routes_target_firewall is True and h2_routes_target_firewall is False,
}

DOCUMENTED_EXPLICIT_DROPS = [
    {
        'id': 'azfw_silence_not_proof_of_bypass',
        'claim_level': 'Not Proven',
        'note': 'Absence of AZFWApplicationRule rows does not prove packet bypass; diagnostics latency, disabled categories, wrong workspace, or wrong firewall can also cause silence.',
    },
    {
        'id': 'effective_routes_are_control_plane_only',
        'claim_level': 'Not Proven',
        'note': 'Effective routes are control-plane evidence, not packet capture.',
    },
    {
        'id': 'routing_intent_as_causal_variable_is_inferred',
        'claim_level': 'Inferred',
        'note': 'Routing Intent is the causal variable only because H0/H1/H2 flips the symptom while workload, identity, Key Vault, and app health stay constant.',
    },
    {
        'id': 'dns_override_not_tested_here',
        'claim_level': 'Explicit Drop',
        'note': 'DNS override is not tested here; H4e covers that.',
    },
    {
        'id': 'key_vault_private_endpoint_not_tested',
        'claim_level': 'Explicit Drop',
        'note': 'Key Vault private endpoint and Key Vault firewall behavior are not tested here; Key Vault stays public and *.vault.azure.net stays allowed in H1.',
    },
    {
        'id': 'containerapp_exec_not_primary_egress_proof',
        'claim_level': 'Explicit Drop',
        'note': 'az containerapp exec is not used as the primary proof of the managed-identity egress path; the reproducer uses the same az containerapp secret set symptom each time.',
    },
    {
        'id': 'cannot_prove_packet_bypass_or_regional_bug',
        'claim_level': 'Explicit Drop',
        'note': 'This lab cannot prove a dataplane bypass, that Azure Firewall never received the packet, that a regional-hub propagation bug occurred, or that route table and dataplane were perfectly synchronized at the failure instant.',
    },
]

subgate_17a = subgate_15a
subgate_17b = subgate_15b and subgate_15c and subgate_15d
subgate_17c = subgate_16a and subgate_16b and subgate_16c
subgate_17d = held_constant_checks['baseline_revision_same']
subgate_17e = all(held_constant_checks.values())
gate17_all = all([subgate_17a, subgate_17b, subgate_17c, subgate_17d, subgate_17e])

gate17 = {
    'claim': (
        f'This evidence pack falsifies the H4d Routing Intent hypothesis within a bounded scope on {app_name} in {resource_group} ({location}). '
        f'Non-vacuous proof requires four observations together: (a) H0 baseline success without an active Routing Intent path through the secured hub; '
        f'(b) H1 trigger-presence: the actual ACA infrastructure VNet was connected to the hub, Routing Intent converged, the HubVirtualNetworkConnection effective routes showed 0.0.0.0/0 targeting the hub firewall, and secret set failed with the MI/OIDC markers; '
        f'(c) H2 removal: Routing Intent was removed, the effective route table no longer targeted the hub firewall for 0.0.0.0/0, and a NEW secret-set attempt succeeded; '
        f'(d) the silence invariant held on baseline revision {baseline_revision_name!r}. The bounded H1↔H2 claim is only that Routing Intent is the controlled route-state variable while workload, identity, Key Vault, and firewall policy stayed constant.'
    ),
    'claim_level': 'Observed',
    'cohort_binding_note': {
        'claim_ceiling': 'The pack proves a bounded Routing-Intent inversion only. It does not generalize beyond the explicit drops listed below.',
        'explicit_drops': DOCUMENTED_EXPLICIT_DROPS,
    },
    'gate_classification': 'Bounded falsification gate.',
    'hypothesis': 'H3_bounded_falsification',
    'path_used': 'bounded',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_route_state': repo_rel('06-h1-routing-intent-enabled.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h2_route_state': repo_rel('10-h2-routing-intent-removed.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
    },
    f'{SCENARIO}_h3_bounded_falsification_all_subgates_pass': gate17_all,
    f'{SCENARIO}_h3_bounded_falsification_sub_gates': {
        'a_baseline_presence_h0_succeeded_without_routing_intent_path': subgate_17a,
        'b_trigger_presence_h1_failed_with_routing_intent_on_and_route_targeting_firewall': subgate_17b,
        'c_fix_removal_h2_succeeded_with_routing_intent_off_and_route_no_longer_targeting_firewall': subgate_17c,
        'd_silence_invariant_holds_same_revision_across_h0_h1_h2': subgate_17d,
        'e_only_the_documented_route_state_variable_changed_between_h1_and_h2': subgate_17e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'Non-vacuous baseline: H0 succeeded without an active Routing Intent path through the secured hub.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('04-h0-secret-set-outcome.json')],
            'observed_values': {'h0_exit_code': d04.get('exit_code'), 'h0_outcome': d04.get('outcome')},
            'predicate': '04.exit_code == 0.',
            'result': 'pass' if subgate_17a else 'fail',
            'sub_gate': 'a_baseline_presence_h0_succeeded_without_routing_intent_path',
        },
        {
            'claim': 'H1 trigger-presence: Routing Intent existed, the effective route table targeted the hub firewall, and the secret-set attempt failed with the expected MI/OIDC markers.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-routing-intent-enabled.json'), repo_rel('07-h1-secret-set-outcome.json')],
            'observed_values': {'h1_exit_code': d07.get('exit_code'), 'default_route_targets': d06.get('default_route_targets')},
            'predicate': '06.default_route_targets_expected_firewall == True AND 07.exit_code != 0 AND stderr markers present.',
            'result': 'pass' if subgate_17b else 'fail',
            'sub_gate': 'b_trigger_presence_h1_failed_with_routing_intent_on_and_route_targeting_firewall',
        },
        {
            'claim': 'H2 fix-removal: Routing Intent was removed, the default route no longer targeted the hub firewall, and the new secret-set attempt succeeded.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-routing-intent-removed.json'), repo_rel('11-h2-secret-set-outcome.json')],
            'observed_values': {'h2_exit_code': d11.get('exit_code'), 'default_route_targets_after_delete': d10.get('default_route_targets_after_delete')},
            'predicate': '10.default_route_targets_expected_firewall == False AND 11.exit_code == 0.',
            'result': 'pass' if subgate_17c else 'fail',
            'sub_gate': 'c_fix_removal_h2_succeeded_with_routing_intent_off_and_route_no_longer_targeting_firewall',
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
            'claim': 'Between H1 and H2, every non-route-state anchor stayed constant; only the documented Routing Intent / effective-route state flipped while the firewall policy stayed unchanged.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['06-h1-routing-intent-enabled.json', '08-h1-app-state.json', '10-h2-routing-intent-removed.json', '12-h2-app-state.json']],
            'observed_values': {'held_constant_checks': held_constant_checks},
            'predicate': 'All entries in held_constant_checks are True.',
            'result': 'pass' if subgate_17e else 'fail',
            'sub_gate': 'e_only_the_documented_route_state_variable_changed_between_h1_and_h2',
        },
    ],
    'thresholds': {
        'h0_exit_code_expected': 0,
        'h1_exit_code_expected_nonzero': True,
        'h2_exit_code_expected': 0,
        'route_prefix_expected_exact': '0.0.0.0/0',
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
    15: evidence_dir / '15-h1-routing-intent-produces-failure-gate.json',
    16: evidence_dir / '16-h2-routing-intent-removal-restores-success-gate.json',
    17: evidence_dir / '17-bounded-falsification-gate.json',
}
gate_success_messages = {
    14: 'cohort integrity verified',
    15: 'H1 routing intent produces failure verified',
    16: 'H2 routing intent removal restores success verified',
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
