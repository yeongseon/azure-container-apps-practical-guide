#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/aca-secret-kv-ref-mi-network-path-h4c/evidence"
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
    '06-h1-nsg-deny-created.json',
    '07-h1-secret-set-outcome.json',
    '08-h1-app-state.json',
    '09-h1-nsg-effective-rules.json',
    '10-h2-nsg-allow-created.json',
    '11-h2-secret-set-outcome.json',
    '12-h2-app-state.json',
    '13-h2-nsg-effective-rules.json',
]

GATE_OUTPUTS = [
    '14-cohort-integrity-gate.json',
    '15-h1-nsg-deny-produces-failure-gate.json',
    '16-h2-allow-remediation-restores-success-gate.json',
    '17-bounded-falsification-gate.json',
]

SCENARIO = 'aca_secret_kv_ref_mi_network_path_h4c'


def repo_rel(name: str) -> str:
    return f'{repo_rel_dir}/{name}'


def load_json(name: str):
    return json.loads((evidence_dir / name).read_text(encoding='utf-8'))


def pass_gate(number: int, detail: str):
    print(f'[Gate {number}/17] PASS {detail}')


def fail_gate(number: int, detail: str):
    print(f'[Gate {number}/17] FAIL {detail}')
    sys.exit(1)


def rule_matches_aad_443(rule: dict, access: str | None = None):
    if not isinstance(rule, dict):
        return False
    if rule.get('direction') != 'Outbound':
        return False
    if access is not None and rule.get('access') != access:
        return False
    if rule.get('protocol') != 'Tcp':
        return False
    dest_port_range = rule.get('destinationPortRange')
    dest_port_ranges = rule.get('destinationPortRanges') or []
    if dest_port_range != '443' and '443' not in dest_port_ranges:
        return False
    dest_prefix = rule.get('destinationAddressPrefix')
    dest_prefixes = rule.get('destinationAddressPrefixes') or []
    if dest_prefix != 'AzureActiveDirectory' and 'AzureActiveDirectory' not in dest_prefixes:
        return False
    return True


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
    'nsg_name',
]
missing_01 = [key for key in required_01 if d01.get(key) in (None, '')]
if missing_01 or d01.get('lab_name') != 'aca-secret-kv-ref-mi-network-path-h4c':
    fail_gate(5, f"01 anchors invalid; missing={missing_01}, lab_name={d01.get('lab_name')}")
pass_gate(5, '01 parses and carries H4c cohort anchors')

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
if d01.get('nsg_attached') is not True or not d01.get('nsg_name'):
    gate10_problems.append('01 must prove an NSG is attached to the ACA subnet')
if d01.get('baseline_deny_aad_443_h4c_present') is not False or d01.get('baseline_allow_aad_443_h4c_present') is not False:
    gate10_problems.append('01 must prove no custom H4c AAD deny/allow rule exists at baseline')
if contains_forbidden_storage_or_flowlog_artifact([d01, d06, d09, d10, d13]):
    gate10_problems.append('The cohort must not reference storage-account, flow-log, or Traffic Analytics artifacts')
if gate10_problems:
    fail_gate(10, '; '.join(gate10_problems))
pass_gate(10, '01 proves the non-H4a topology with baseline NSG-only anchoring')

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
pass_gate(13, '09-13 H1 NSG denial + H2 allow recovery cohort valid')

app_name = d01['app_name']
resource_group = d01['resource_group']
location = d01['location']
nsg_name = d01['nsg_name']
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
nsg_refs = {
    '01': d01.get('nsg_name'),
    '06': d06.get('nsg_name'),
    '09': d09.get('nsg_name'),
    '10': d10.get('nsg_name'),
    '13': d13.get('nsg_name'),
}
rev_h0_after = d05.get('latest_ready_revision_name')
rev_h1 = d08.get('latest_ready_revision_name')
rev_h2 = d12.get('latest_ready_revision_name')

subgate_14a = len(timestamp_violations) == 0
subgate_14b = all(value == app_name for value in app_name_refs.values())
subgate_14c = all(value == nsg_name for value in nsg_refs.values())
subgate_14d = baseline_revision_name == rev_h0_after == rev_h1 == rev_h2
subgate_14e = (
    d01.get('nsg_attached') is True
    and d01.get('azure_firewall_present') is False
    and d01.get('route_table_attached') is False
    and d01.get('uses_azure_provided_dns') is True
    and not contains_forbidden_storage_or_flowlog_artifact([d01, d06, d07, d08, d09, d10, d11, d12, d13])
)
gate14_all = all([subgate_14a, subgate_14b, subgate_14c, subgate_14d, subgate_14e])

gate14 = {
    'claim': (
        f'The evidence cohort for the aca-secret-kv-ref-mi-network-path-h4c lab on {app_name} '
        f'in {resource_group} ({location}) is internally consistent: all 13 raw files are present '
        f'and parseable, timestamps are monotonic, cross-file anchors agree, the baseline revision '
        f'{baseline_revision_name!r} stays unchanged across H0/H1/H2, and the deployed topology proves '
        f'an NSG is attached, no Azure Firewall, no UDR, Azure-provided DNS, and no storage-account or flow-log artifact participates in the cohort.'
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
        'c_nsg_name_anchor_consistent': subgate_14c,
        'd_baseline_revision_silence_invariant_holds': subgate_14d,
        'e_not_h4a_topology_anchored_and_no_flowlog_artifacts': subgate_14e,
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
            'claim': f'All NSG references equal {nsg_name!r}.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-nsg-deny-created.json', '09-h1-nsg-effective-rules.json', '10-h2-nsg-allow-created.json', '13-h2-nsg-effective-rules.json']],
            'observed_values': nsg_refs,
            'predicate': 'All nsg_name fields equal 01.nsg_name.',
            'result': 'pass' if subgate_14c else 'fail',
            'sub_gate': 'c_nsg_name_anchor_consistent',
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
            'claim': 'The baseline topology is explicitly not H4a: NSG attached, no Azure Firewall, no route table on the ACA subnet, Azure-provided DNS, and no flow-log/storage-account artifact referenced anywhere in the cohort.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in RAW_FILES],
            'observed_values': {
                'nsg_attached': d01.get('nsg_attached'),
                'azure_firewall_present': d01.get('azure_firewall_present'),
                'route_table_attached': d01.get('route_table_attached'),
                'vnet_dns_servers': d01.get('vnet_dns_servers'),
                'forbidden_artifact_reference_found': contains_forbidden_storage_or_flowlog_artifact([d01, d06, d07, d08, d09, d10, d11, d12, d13]),
            },
            'predicate': '01.nsg_attached == True AND 01.azure_firewall_present == False AND 01.route_table_attached == False AND 01.vnet_dns_servers == [] AND no flow-log/storage-account markers appear in the raw cohort.',
            'result': 'pass' if subgate_14e else 'fail',
            'sub_gate': 'e_not_h4a_topology_anchored_and_no_flowlog_artifacts',
        },
    ],
    'thresholds': {'expected_raw_file_count': 13, 'expected_gate_output_count': 4},
    'utc_captured': utc_now,
}

deny_rule_h1 = d06.get('deny_rule')
allow_rule_h1 = d09.get('allow_rule')
h1_stderr_matches = d07.get('stderr_substring_matches') or {}
subgate_15a = (
    isinstance(d07.get('exit_code'), int)
    and d07.get('exit_code') != 0
    and h1_stderr_matches.get('unable_to_get_value_using_managed_identity') is True
    and h1_stderr_matches.get('openid_configuration_reference') is True
    and h1_stderr_matches.get('login_microsoft_host_reference') is True
    and h1_stderr_matches.get('eof_reference') is True
)
subgate_15b = (
    d08.get('latest_revision_unchanged_vs_baseline') is True
    and d08.get('ingress_probe_http_code') == '200'
    and d08.get('secret_presence_expectation_met') is True
    and d08.get('observed_secret_present') is False
)
subgate_15c = rule_matches_aad_443(deny_rule_h1, access='Deny') and (deny_rule_h1 or {}).get('priority') == 200
subgate_15d = int(d06.get('higher_priority_matching_allow_count') or -1) == 0 and int(d09.get('higher_priority_matching_allow_count') or -1) == 0 and not rule_matches_aad_443(allow_rule_h1, access='Allow')
subgate_15e = d09.get('governing_rule_name') == 'deny-aad-443-h4c' and rule_matches_aad_443(d09.get('deny_rule'), access='Deny')
gate15_all = all([subgate_15a, subgate_15b, subgate_15c, subgate_15d, subgate_15e])

gate15 = {
    'claim': (
        f'H1 proves the NSG-deny trigger: after creating outbound rule deny-aad-443-h4c on {nsg_name!r} with priority 200, '
        f'`az containerapp secret set --identity system --key-vault-url ...` fails on {app_name}, stderr contains the managed-identity '
        f'+ OIDC discovery signature, the baseline revision {baseline_revision_name!r} keeps serving HTTP 200, kvref-h1 stays absent, '
        f'and no higher-priority matching Allow existed for AzureActiveDirectory:443.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H1 NSG-deny gate.',
    'hypothesis': 'H1_nsg_deny_produces_failure',
    'path_used': 'single',
    'predicate_inputs': {
        'h1_nsg_deny_created': repo_rel('06-h1-nsg-deny-created.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_app_state': repo_rel('08-h1-app-state.json'),
        'h1_nsg_effective_rules': repo_rel('09-h1-nsg-effective-rules.json'),
    },
    f'{SCENARIO}_h1_nsg_deny_produces_failure_all_subgates_pass': gate15_all,
    f'{SCENARIO}_h1_nsg_deny_produces_failure_sub_gates': {
        'a_h1_secret_set_failed_with_managed_identity_oidc_signature': subgate_15a,
        'b_silence_gate_holds_revision_unchanged_ingress_200_secret_absent': subgate_15b,
        'c_h1_deny_rule_exists_for_azureactivedirectory_443': subgate_15c,
        'd_no_higher_priority_matching_allow_existed_at_h1': subgate_15d,
        'e_h1_snapshot_shows_the_deny_rule_governs': subgate_15e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'The H1 secret-set attempt failed with the managed-identity + OIDC discovery signature.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('07-h1-secret-set-outcome.json')],
            'observed_values': {'exit_code': d07.get('exit_code'), 'stderr_substring_matches': h1_stderr_matches},
            'predicate': '07.exit_code != 0 AND stderr matches include managed identity, openid-configuration, login.microsoft*, and EOF.',
            'result': 'pass' if subgate_15a else 'fail',
            'sub_gate': 'a_h1_secret_set_failed_with_managed_identity_oidc_signature',
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
            'claim': 'H1 created an outbound Deny rule for AzureActiveDirectory:443 with priority 200.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-nsg-deny-created.json')],
            'observed_values': {'deny_rule': deny_rule_h1},
            'predicate': '06.deny_rule matches outbound deny tcp AzureActiveDirectory port 443 with priority 200.',
            'result': 'pass' if subgate_15c else 'fail',
            'sub_gate': 'c_h1_deny_rule_exists_for_azureactivedirectory_443',
        },
        {
            'claim': 'No higher-priority matching Allow rule existed at H1 for AzureActiveDirectory:443.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-nsg-deny-created.json'), repo_rel('09-h1-nsg-effective-rules.json')],
            'observed_values': {
                'h1_higher_priority_matching_allow_count_from_06': d06.get('higher_priority_matching_allow_count'),
                'h1_higher_priority_matching_allow_count_from_09': d09.get('higher_priority_matching_allow_count'),
                'h1_allow_rule_snapshot': allow_rule_h1,
            },
            'predicate': '06.higher_priority_matching_allow_count == 0 AND 09.higher_priority_matching_allow_count == 0 AND 09.allow_rule is null for the H4c allow rule.',
            'result': 'pass' if subgate_15d else 'fail',
            'sub_gate': 'd_no_higher_priority_matching_allow_existed_at_h1',
        },
        {
            'claim': 'The H1 NSG snapshot shows the Deny rule is the governing rule for AzureActiveDirectory:443.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('09-h1-nsg-effective-rules.json')],
            'observed_values': {'governing_rule_name': d09.get('governing_rule_name'), 'deny_rule': d09.get('deny_rule')},
            'predicate': '09.governing_rule_name == "deny-aad-443-h4c" and the deny rule matches outbound deny tcp AzureActiveDirectory port 443.',
            'result': 'pass' if subgate_15e else 'fail',
            'sub_gate': 'e_h1_snapshot_shows_the_deny_rule_governs',
        },
    ],
    'thresholds': {'h1_exit_code_expected_nonzero': True, 'deny_priority_expected_exact': 200, 'aad_service_tag_expected_exact': 'AzureActiveDirectory'},
    'utc_captured': utc_now,
}

allow_rule_h2 = d10.get('allow_rule')
deny_rule_h2 = d10.get('deny_rule')
highest_allow_h2 = d13.get('highest_priority_matching_allow') or {}
subgate_16a = rule_matches_aad_443(allow_rule_h2, access='Allow') and (allow_rule_h2 or {}).get('priority') == 100
subgate_16b = isinstance(d11.get('exit_code'), int) and d11.get('exit_code') == 0 and d11.get('outcome') == 'success'
subgate_16c = (
    d12.get('latest_revision_unchanged_vs_baseline') is True
    and d12.get('ingress_probe_http_code') == '200'
    and d12.get('secret_presence_expectation_met') is True
    and d12.get('observed_secret_present') is True
)
subgate_16d = (allow_rule_h2 or {}).get('priority') is not None and (deny_rule_h2 or {}).get('priority') is not None and int((allow_rule_h2 or {}).get('priority')) < int((deny_rule_h2 or {}).get('priority'))
subgate_16e = d13.get('governing_rule_name') == 'allow-aad-443-h4c' and rule_matches_aad_443(highest_allow_h2, access='Allow') and highest_allow_h2.get('name') == 'allow-aad-443-h4c'
gate16_all = all([subgate_16a, subgate_16b, subgate_16c, subgate_16d, subgate_16e])

gate16 = {
    'claim': (
        f'H2 proves the documented remediation is sufficient for recovery: a higher-priority outbound Allow rule '
        f'allow-aad-443-h4c with priority 100 was added on {nsg_name!r}, a NEW secret-set attempt succeeded on {app_name}, '
        f'kvref-h2 appeared, ingress stayed HTTP 200 on {baseline_revision_name!r}, and the Allow priority is numerically lower '
        f'than the Deny priority, proving the Allow now governs AzureActiveDirectory:443.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H2 allow-remediation gate.',
    'hypothesis': 'H2_allow_remediation_restores_success',
    'path_used': 'single',
    'predicate_inputs': {
        'h2_allow_created': repo_rel('10-h2-nsg-allow-created.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_nsg_effective_rules': repo_rel('13-h2-nsg-effective-rules.json'),
    },
    f'{SCENARIO}_h2_allow_remediation_restores_success_all_subgates_pass': gate16_all,
    f'{SCENARIO}_h2_allow_remediation_restores_success_sub_gates': {
        'a_h2_allow_rule_exists_for_azureactivedirectory_443': subgate_16a,
        'b_h2_secret_set_succeeded_zero_exit': subgate_16b,
        'c_h2_success_gate_holds_revision_unchanged_ingress_200_secret_present': subgate_16c,
        'd_allow_priority_is_lower_than_deny_priority': subgate_16d,
        'e_h2_snapshot_shows_the_allow_rule_governs': subgate_16e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'H2 created an outbound Allow rule for AzureActiveDirectory:443 with priority 100.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-nsg-allow-created.json')],
            'observed_values': {'allow_rule': allow_rule_h2},
            'predicate': '10.allow_rule matches outbound allow tcp AzureActiveDirectory port 443 with priority 100.',
            'result': 'pass' if subgate_16a else 'fail',
            'sub_gate': 'a_h2_allow_rule_exists_for_azureactivedirectory_443',
        },
        {
            'claim': 'The new H2 secret-set attempt succeeded with exit code 0.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('11-h2-secret-set-outcome.json')],
            'observed_values': {'exit_code': d11.get('exit_code'), 'outcome': d11.get('outcome'), 'retry_attempts_used': d11.get('retry_attempts_used')},
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
            'claim': 'The Allow priority is numerically lower than the Deny priority, so the Allow must govern.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-nsg-allow-created.json')],
            'observed_values': {'allow_priority': (allow_rule_h2 or {}).get('priority'), 'deny_priority': (deny_rule_h2 or {}).get('priority')},
            'predicate': '10.allow_rule.priority < 10.deny_rule.priority.',
            'result': 'pass' if subgate_16d else 'fail',
            'sub_gate': 'd_allow_priority_is_lower_than_deny_priority',
        },
        {
            'claim': 'The H2 NSG snapshot shows the Allow rule is the governing rule for AzureActiveDirectory:443.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('13-h2-nsg-effective-rules.json')],
            'observed_values': {'governing_rule_name': d13.get('governing_rule_name'), 'highest_priority_matching_allow': highest_allow_h2},
            'predicate': '13.governing_rule_name == "allow-aad-443-h4c" AND 13.highest_priority_matching_allow.name == "allow-aad-443-h4c".',
            'result': 'pass' if subgate_16e else 'fail',
            'sub_gate': 'e_h2_snapshot_shows_the_allow_rule_governs',
        },
    ],
    'thresholds': {'h2_exit_code_expected': 0, 'allow_priority_expected_exact': 100, 'deny_priority_expected_exact': 200},
    'utc_captured': utc_now,
}

held_constant_checks = {
    'app_name_same': d08.get('app_name') == d12.get('app_name') == app_name,
    'key_vault_same': d01.get('key_vault_name') == d03.get('key_vault_name'),
    'nsg_name_same': d06.get('nsg_name') == d10.get('nsg_name') == d13.get('nsg_name') == nsg_name,
    'baseline_revision_same': d08.get('latest_ready_revision_name') == d12.get('latest_ready_revision_name') == baseline_revision_name,
    'no_firewall_no_udr_both_phases': d06.get('azure_firewall_present') is False and d06.get('route_table_attached') is False and d10.get('azure_firewall_present') is False and d10.get('route_table_attached') is False,
    'azure_provided_dns_both_phases': d06.get('uses_azure_provided_dns') is True and d10.get('uses_azure_provided_dns') is True,
    'nsg_attached_both_phases': d06.get('nsg_attached') is True and d10.get('nsg_attached') is True,
    'only_intended_rule_change_between_h1_and_h2': (d09.get('deny_rule') or {}).get('name') == 'deny-aad-443-h4c' and (d13.get('deny_rule') or {}).get('name') == 'deny-aad-443-h4c' and (d13.get('highest_priority_matching_allow') or {}).get('name') == 'allow-aad-443-h4c',
}

DOCUMENTED_EXPLICIT_DROPS = [
    'Does NOT prove NSG-before-Azure-Firewall ordering (no Azure Firewall is deployed in this lab).',
    'Does NOT prove NSG flow-log behavior (flow logs and storage accounts are intentionally out of scope).',
    'Does NOT prove all ACA control-plane calls use the same subnet-governed egress path.',
    'Does NOT prove exact Entra IP resolution at failure time (it proves the NSG rule targets the Microsoft-managed `AzureActiveDirectory` service tag).',
    'Does NOT prove Key Vault firewall/RBAC failure (KV, identity, RBAC, revision, ingress held constant).',
]

subgate_17a = d04.get('exit_code') == 0 and d04.get('outcome') == 'success'
subgate_17b = gate15_all
subgate_17c = gate16_all
subgate_17d = subgate_14d
subgate_17e = all(held_constant_checks.values())
gate17_all = all([subgate_17a, subgate_17b, subgate_17c, subgate_17d, subgate_17e])

gate17 = {
    'claim': (
        f'This evidence pack falsifies the H4c NSG-deny hypothesis within a bounded scope on {app_name} in {resource_group} ({location}). '
        f'Non-vacuous proof requires four observations together: (a) H0 baseline success with the NSG attached but no custom AAD deny/allow rule; '
        f'(b) H1 trigger-presence: deny-aad-443-h4c existed, no higher-priority matching Allow existed, and secret set failed with the OIDC-discovery signature; '
        f'(c) H2 fix: allow-aad-443-h4c was added at higher priority, a NEW secret-set attempt succeeded, and the deny remained in place; '
        f'(d) the silence invariant held on baseline revision {baseline_revision_name!r}. The bounded H1↔H2 claim is only that the added higher-priority Allow rule is the intended remediation while DNS, route tables, firewall presence, Key Vault, identity, RBAC, app, revision, and ingress stayed constant.'
    ),
    'claim_level': 'Observed',
    'cohort_binding_note': {
        'claim_ceiling': 'The pack proves a bounded NSG-rule inversion only. It does not generalize beyond the explicit drops listed below.',
        'explicit_drops': DOCUMENTED_EXPLICIT_DROPS,
    },
    'gate_classification': 'Bounded falsification gate.',
    'hypothesis': 'H3_bounded_falsification',
    'path_used': 'bounded',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_nsg_deny_created': repo_rel('06-h1-nsg-deny-created.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_nsg_effective_rules': repo_rel('09-h1-nsg-effective-rules.json'),
        'h2_allow_created': repo_rel('10-h2-nsg-allow-created.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_nsg_effective_rules': repo_rel('13-h2-nsg-effective-rules.json'),
    },
    f'{SCENARIO}_h3_bounded_falsification_all_subgates_pass': gate17_all,
    f'{SCENARIO}_h3_bounded_falsification_sub_gates': {
        'a_baseline_presence_h0_succeeded_without_custom_aad_rule': subgate_17a,
        'b_trigger_presence_h1_failed_with_nsg_deny_present': subgate_17b,
        'c_fix_additive_h2_succeeded_with_higher_priority_allow_present': subgate_17c,
        'd_silence_invariant_holds_same_revision_across_h0_h1_h2': subgate_17d,
        'e_only_the_documented_allow_rule_changed_between_h1_and_h2': subgate_17e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'Non-vacuous baseline: H0 succeeded with the NSG attached but no custom AzureActiveDirectory deny/allow rule.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('01-deployment-outputs.json'), repo_rel('04-h0-secret-set-outcome.json')],
            'observed_values': {
                'h0_exit_code': d04.get('exit_code'),
                'baseline_deny_aad_443_h4c_present': d01.get('baseline_deny_aad_443_h4c_present'),
                'baseline_allow_aad_443_h4c_present': d01.get('baseline_allow_aad_443_h4c_present'),
            },
            'predicate': '04.exit_code == 0 AND 01 baseline deny/allow booleans are both False.',
            'result': 'pass' if subgate_17a else 'fail',
            'sub_gate': 'a_baseline_presence_h0_succeeded_without_custom_aad_rule',
        },
        {
            'claim': 'H1 trigger-presence: the Deny existed, no higher-priority matching Allow existed, and secret set failed with the OIDC-discovery signature.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-nsg-deny-created.json'), repo_rel('07-h1-secret-set-outcome.json'), repo_rel('09-h1-nsg-effective-rules.json')],
            'observed_values': {
                'h1_exit_code': d07.get('exit_code'),
                'h1_higher_priority_matching_allow_count': d09.get('higher_priority_matching_allow_count'),
                'h1_governing_rule_name': d09.get('governing_rule_name'),
            },
            'predicate': '06 creates the deny rule AND 07.exit_code != 0 AND 09.higher_priority_matching_allow_count == 0 AND 09.governing_rule_name == "deny-aad-443-h4c".',
            'result': 'pass' if subgate_17b else 'fail',
            'sub_gate': 'b_trigger_presence_h1_failed_with_nsg_deny_present',
        },
        {
            'claim': 'H2 fix-addition: a higher-priority Allow was added while the Deny remained, and the new secret-set attempt succeeded.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-nsg-allow-created.json'), repo_rel('11-h2-secret-set-outcome.json'), repo_rel('13-h2-nsg-effective-rules.json')],
            'observed_values': {
                'h2_exit_code': d11.get('exit_code'),
                'allow_priority': (allow_rule_h2 or {}).get('priority'),
                'deny_priority': (deny_rule_h2 or {}).get('priority'),
                'h2_governing_rule_name': d13.get('governing_rule_name'),
            },
            'predicate': '10.allow_rule.priority < 10.deny_rule.priority AND 11.exit_code == 0 AND 13.governing_rule_name == "allow-aad-443-h4c".',
            'result': 'pass' if subgate_17c else 'fail',
            'sub_gate': 'c_fix_additive_h2_succeeded_with_higher_priority_allow_present',
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
            'claim': 'Between H1 and H2, every non-NSG-remediation anchor stayed constant; only the intended higher-priority Allow rule was added while the Deny remained in place.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['06-h1-nsg-deny-created.json', '08-h1-app-state.json', '10-h2-nsg-allow-created.json', '12-h2-app-state.json', '13-h2-nsg-effective-rules.json']],
            'observed_values': {'held_constant_checks': held_constant_checks},
            'predicate': 'All entries in held_constant_checks are True.',
            'result': 'pass' if subgate_17e else 'fail',
            'sub_gate': 'e_only_the_documented_allow_rule_changed_between_h1_and_h2',
        },
    ],
    'thresholds': {
        'h0_exit_code_expected': 0,
        'h1_exit_code_expected_nonzero': True,
        'h2_exit_code_expected': 0,
        'h1_deny_priority_expected_exact': 200,
        'h2_allow_priority_expected_exact': 100,
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
    15: evidence_dir / '15-h1-nsg-deny-produces-failure-gate.json',
    16: evidence_dir / '16-h2-allow-remediation-restores-success-gate.json',
    17: evidence_dir / '17-bounded-falsification-gate.json',
}
gate_success_messages = {
    14: 'cohort integrity verified',
    15: 'H1 NSG deny produces failure verified',
    16: 'H2 allow remediation restores success verified',
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
