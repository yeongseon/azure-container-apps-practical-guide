#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/aca-secret-kv-ref-mi-network-path-h4b/evidence"
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
    '06-h1-firewall-rule-removed.json',
    '07-h1-secret-set-outcome.json',
    '08-h1-app-state.json',
    '09-h1-firewall-deny-log-absent.json',
    '10-h2-firewall-diagnostics-enabled.json',
    '11-h2-secret-set-outcome.json',
    '12-h2-app-state.json',
    '13-h2-firewall-deny-log.json',
]

GATE_OUTPUTS = [
    '14-cohort-integrity-gate.json',
    '15-h1-trigger-produces-failure-gate.json',
    '16-h2-observability-restored-gate.json',
    '17-bounded-falsification-gate.json',
]

SCENARIO = 'aca_secret_kv_ref_mi_network_path_h4b'


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
    'key_vault_name', 'key_vault_uri', 'app_principal_id', 'firewall_name',
    'firewall_resource_id', 'firewall_policy_name', 'firewall_public_ip',
    'log_analytics_name', 'log_analytics_customer_id',
    'entra_rule_collection_name', 'entra_rule_name',
]
missing_01 = [key for key in required_01 if not d01.get(key)]
if missing_01 or d01.get('lab_name') != 'aca-secret-kv-ref-mi-network-path-h4b':
    fail_gate(5, f"01 anchors invalid; missing={missing_01}, lab_name={d01.get('lab_name')}")
pass_gate(5, '01 parses and carries H4b cohort anchors')

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
pass_gate(9, '05 H0 silence gate valid')

if (
    d06.get('phase') != 'H1'
    or d06.get('controlled_variable_absent_after_remove') is not True
    or d06.get('controlled_variable_observability_disabled') is not True
    or d06.get('azure_firewall_application_rule_logging_enabled') is not False
    or int(d06.get('remove_exit_code') or 1) != 0
    or int(d06.get('diagnostic_update_exit_code') or 1) != 0
):
    fail_gate(10, '06 H1 remove+disable evidence invalid')
if d06.get('rule_collection_name') in (d06.get('post_remove_collections_in_group') or []):
    fail_gate(10, '06 rule collection still present after remove')
pass_gate(10, '06 firewall rule removed and application-rule logging disabled')

if (
    d07.get('phase') != 'H1'
    or not isinstance(d07.get('exit_code'), int)
    or d07.get('exit_code') == 0
    or d07.get('outcome') != 'failure'
    or not d07.get('h1_start_iso')
):
    fail_gate(11, '07 H1 secret set did not fail as expected')
pass_gate(11, '07 H1 secret set failed')

if (
    d08.get('latest_revision_unchanged_vs_baseline') is not True
    or d08.get('ingress_probe_http_code') != '200'
    or d08.get('secret_presence_expectation_met') is not True
    or d08.get('observed_secret_present') is not False
):
    fail_gate(12, '08 H1 silence gate invalid')
pass_gate(12, '08 H1 silence gate valid')

gate13_problems = []
if int(d09.get('final_deny_row_count') or -1) != 0:
    gate13_problems.append('09 final_deny_row_count must equal 0 for the logging gap')
if d10.get('azure_firewall_application_rule_logging_enabled') is not True:
    gate13_problems.append('10 application-rule logging not enabled in H2')
if d10.get('rule_collection_name') in (d10.get('post_enable_collections_in_group') or []):
    gate13_problems.append('10 Entra rule collection unexpectedly present in H2')
if int(d10.get('pre_h2_guard_deny_row_count') or -1) != 0:
    gate13_problems.append('10 pre-H2 guard row count must equal 0')
if d11.get('exit_code') == 0 or d11.get('outcome') != 'failure':
    gate13_problems.append('11 H2 secret set must still fail')
if d12.get('observed_secret_present') is not False or d12.get('secret_presence_expectation_met') is not True or d12.get('ingress_probe_http_code') != '200':
    gate13_problems.append('12 H2 app state must show kvref-h2 absent and ingress 200')
if int(d13.get('final_deny_row_count') or 0) < 1:
    gate13_problems.append('13 final_deny_row_count must be >= 1')
if gate13_problems:
    fail_gate(13, '; '.join(gate13_problems))
pass_gate(13, '09-13 H1 gap + H2 observability cohort valid')

app_name = d01['app_name']
resource_group = d01['resource_group']
location = d01['location']
firewall_policy_name = d01['firewall_policy_name']
firewall_resource_id = d01['firewall_resource_id']
log_analytics_customer_id = d01['log_analytics_customer_id']
entra_rule_collection_name = d01['entra_rule_collection_name']
baseline_revision_name = d02['latest_ready_revision_name']
h1_start = d07.get('h1_start_iso')
h2_diag_enable = d10.get('h2_diag_enable_iso')
h2_start = d11.get('h2_secret_set_start_iso')
h1_deny_count = int(d09.get('final_deny_row_count') or 0)
h2_deny_count = int(d13.get('final_deny_row_count') or 0)

app_name_refs = {
    '01': d01.get('app_name'),
    '02': d02.get('app_name'),
    '05': d05.get('app_name'),
    '08': d08.get('app_name'),
    '12': d12.get('app_name'),
}
fw_refs = {
    '01': d01.get('firewall_policy_name'),
    '06': d06.get('firewall_policy_name'),
    '10': d10.get('firewall_policy_name'),
}
law_refs = {
    '01': d01.get('log_analytics_customer_id'),
    '09': d09.get('log_analytics_customer_id'),
    '13': d13.get('log_analytics_customer_id'),
}
rev_h0_after = d05.get('latest_ready_revision_name')
rev_h1 = d08.get('latest_ready_revision_name')
rev_h2 = d12.get('latest_ready_revision_name')

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

subgate_14a = len(timestamp_violations) == 0
subgate_14b = all(value == app_name for value in app_name_refs.values())
subgate_14c = all(value == firewall_policy_name for value in fw_refs.values())
subgate_14d = all(value == log_analytics_customer_id for value in law_refs.values())
subgate_14e = bool(h1_start and h2_diag_enable and h2_start) and h1_start < h2_diag_enable < h2_start
subgate_14f = d06.get('rule_collection_name') == d10.get('rule_collection_name') == entra_rule_collection_name
subgate_14g = baseline_revision_name == rev_h0_after == rev_h1 == rev_h2
gate14_all = all([subgate_14a, subgate_14b, subgate_14c, subgate_14d, subgate_14e, subgate_14f, subgate_14g])

gate14 = {
    'claim': (
        f'The evidence cohort for the aca-secret-kv-ref-mi-network-path-h4b lab on {app_name} '
        f'in {resource_group} ({location}) is internally consistent: all 13 raw files are present '
        f'and parseable, timestamps are monotonic, cross-file anchors agree, H1 precedes H2, and '
        f'the baseline revision {baseline_revision_name!r} stays unchanged across H0/H1/H2.'
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
        'c_firewall_policy_name_anchor_consistent': subgate_14c,
        'd_log_analytics_workspace_anchor_consistent': subgate_14d,
        'e_h1_start_precedes_h2_diag_enable_and_h2_attempt': subgate_14e,
        'f_rule_collection_name_anchor_consistent': subgate_14f,
        'g_baseline_revision_silence_invariant_holds': subgate_14g,
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
            'claim': f'All firewall_policy_name references equal {firewall_policy_name!r}.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-firewall-rule-removed.json', '10-h2-firewall-diagnostics-enabled.json']],
            'observed_values': fw_refs,
            'predicate': 'All firewall_policy_name fields equal 01.firewall_policy_name.',
            'result': 'pass' if subgate_14c else 'fail',
            'sub_gate': 'c_firewall_policy_name_anchor_consistent',
        },
        {
            'claim': f'All log_analytics_customer_id references equal {log_analytics_customer_id!r}.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '09-h1-firewall-deny-log-absent.json', '13-h2-firewall-deny-log.json']],
            'observed_values': law_refs,
            'predicate': 'All log_analytics_customer_id fields equal 01.log_analytics_customer_id.',
            'result': 'pass' if subgate_14d else 'fail',
            'sub_gate': 'd_log_analytics_workspace_anchor_consistent',
        },
        {
            'claim': 'H1 starts before H2 diagnostics are re-enabled, and H2 diagnostics are re-enabled before the new H2 secret-set attempt begins.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['07-h1-secret-set-outcome.json', '10-h2-firewall-diagnostics-enabled.json', '11-h2-secret-set-outcome.json']],
            'observed_values': {'h1_start_iso': h1_start, 'h2_diag_enable_iso': h2_diag_enable, 'h2_secret_set_start_iso': h2_start},
            'predicate': '07.h1_start_iso < 10.h2_diag_enable_iso < 11.h2_secret_set_start_iso.',
            'result': 'pass' if subgate_14e else 'fail',
            'sub_gate': 'e_h1_start_precedes_h2_diag_enable_and_h2_attempt',
        },
        {
            'claim': f'The controlled rule collection name {entra_rule_collection_name!r} matches across 01, 06, and 10.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-firewall-rule-removed.json', '10-h2-firewall-diagnostics-enabled.json']],
            'observed_values': {'01': entra_rule_collection_name, '06': d06.get('rule_collection_name'), '10': d10.get('rule_collection_name')},
            'predicate': '01.entra_rule_collection_name == 06.rule_collection_name == 10.rule_collection_name.',
            'result': 'pass' if subgate_14f else 'fail',
            'sub_gate': 'f_rule_collection_name_anchor_consistent',
        },
        {
            'claim': f'The baseline revision {baseline_revision_name!r} stays identical across 02, 05, 08, and 12.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['02-h0-app-state-before.json', '05-h0-app-state-after.json', '08-h1-app-state.json', '12-h2-app-state.json']],
            'observed_values': {'02': baseline_revision_name, '05': rev_h0_after, '08': rev_h1, '12': rev_h2},
            'predicate': '02.latest_ready_revision_name == 05.latest_ready_revision_name == 08.latest_ready_revision_name == 12.latest_ready_revision_name.',
            'result': 'pass' if subgate_14g else 'fail',
            'sub_gate': 'g_baseline_revision_silence_invariant_holds',
        },
    ],
    'thresholds': {'expected_raw_file_count': 13, 'expected_gate_output_count': 4},
    'utc_captured': utc_now,
}

subgate_15a = d04.get('exit_code') == 0 and d04.get('outcome') == 'success'
subgate_15b = (
    d06.get('controlled_variable_absent_after_remove') is True
    and d06.get('controlled_variable_observability_disabled') is True
    and d06.get('azure_firewall_application_rule_logging_enabled') is False
    and entra_rule_collection_name not in (d06.get('post_remove_collections_in_group') or [])
)
subgate_15c = isinstance(d07.get('exit_code'), int) and d07.get('exit_code') != 0 and d07.get('outcome') == 'failure'
subgate_15d = (
    d08.get('latest_revision_unchanged_vs_baseline') is True
    and d08.get('ingress_probe_http_code') == '200'
    and d08.get('secret_presence_expectation_met') is True
    and d08.get('observed_secret_present') is False
)
subgate_15e = h1_deny_count == 0
gate15_all = all([subgate_15a, subgate_15b, subgate_15c, subgate_15d, subgate_15e])

gate15 = {
    'claim': (
        f'H1 proves the logging-gap trap: after removing the Entra rule collection {entra_rule_collection_name!r} '
        f'and disabling the AzureFirewallApplicationRule diagnostic category, `az containerapp secret set --identity system --key-vault-url ...` '
        f'fails on {app_name}, the baseline revision {baseline_revision_name!r} keeps serving HTTP 200, kvref-h1 stays absent, and the H1 firewall log shows 0 Deny rows.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H1 logging-gap gate.',
    'hypothesis': 'H1_trigger_produces_failure',
    'path_used': 'single',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_remove_and_disable': repo_rel('06-h1-firewall-rule-removed.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_app_state': repo_rel('08-h1-app-state.json'),
        'h1_firewall_log_gap': repo_rel('09-h1-firewall-deny-log-absent.json'),
    },
    f'{SCENARIO}_h1_trigger_produces_failure_all_subgates_pass': gate15_all,
    f'{SCENARIO}_h1_trigger_produces_failure_sub_gates': {
        'a_baseline_h0_succeeded_when_entra_rule_was_present': subgate_15a,
        'b_entra_rule_absent_and_applicationrule_logging_disabled': subgate_15b,
        'c_h1_secret_set_failed_nonzero_exit': subgate_15c,
        'd_silence_gate_holds_revision_unchanged_ingress_200_secret_absent': subgate_15d,
        'e_h1_logging_gap_zero_deny_rows_while_failure_occurred': subgate_15e,
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
            'sub_gate': 'a_baseline_h0_succeeded_when_entra_rule_was_present',
        },
        {
            'claim': 'H1 removed the Entra rule collection and disabled AzureFirewallApplicationRule logging.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-firewall-rule-removed.json')],
            'observed_values': {
                'post_remove_collections_in_group': d06.get('post_remove_collections_in_group'),
                'azure_firewall_application_rule_logging_enabled': d06.get('azure_firewall_application_rule_logging_enabled'),
                'diagnostic_setting_name': d06.get('diagnostic_setting_name'),
                'firewall_resource_id': firewall_resource_id,
            },
            'predicate': '06.controlled_variable_absent_after_remove == True AND 06.azure_firewall_application_rule_logging_enabled == False.',
            'result': 'pass' if subgate_15b else 'fail',
            'sub_gate': 'b_entra_rule_absent_and_applicationrule_logging_disabled',
        },
        {
            'claim': 'The H1 secret-set attempt failed with a non-zero exit code.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('07-h1-secret-set-outcome.json')],
            'observed_values': {'exit_code': d07.get('exit_code'), 'outcome': d07.get('outcome'), 'h1_start_iso': h1_start},
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
            'claim': 'H1 shows the logging gap: the denial happened, but the firewall query returns zero Deny rows because the category was disabled.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('09-h1-firewall-deny-log-absent.json')],
            'observed_values': {'final_deny_row_count': h1_deny_count, 'attempts': d09.get('attempts') or []},
            'predicate': '09.final_deny_row_count == 0.',
            'result': 'pass' if subgate_15e else 'fail',
            'sub_gate': 'e_h1_logging_gap_zero_deny_rows_while_failure_occurred',
        },
    ],
    'thresholds': {'h1_deny_row_expected_exact': 0, 'h1_exit_code_expected_nonzero': True, 'h0_exit_code_expected': 0},
    'utc_captured': utc_now,
}

subgate_16a = (
    d10.get('azure_firewall_application_rule_logging_enabled') is True
    and entra_rule_collection_name not in (d10.get('post_enable_collections_in_group') or [])
    and d10.get('controlled_variable_absent_after_h2_observability_fix') is True
)
subgate_16b = int(d10.get('pre_h2_guard_deny_row_count') or -1) == 0
subgate_16c = isinstance(d11.get('exit_code'), int) and d11.get('exit_code') != 0 and d11.get('outcome') == 'failure'
subgate_16d = (
    d12.get('latest_revision_unchanged_vs_baseline') is True
    and d12.get('ingress_probe_http_code') == '200'
    and d12.get('secret_presence_expectation_met') is True
    and d12.get('observed_secret_present') is False
)
subgate_16e = h2_deny_count >= 1
gate16_all = all([subgate_16a, subgate_16b, subgate_16c, subgate_16d, subgate_16e])

gate16 = {
    'claim': (
        f'H2 restores observability, not connectivity: AzureFirewallApplicationRule logging is re-enabled on {firewall_resource_id}, '
        f'the Entra rule collection {entra_rule_collection_name!r} stays absent, the pre-H2 guard proves zero Deny rows existed before the new attempt, '
        f'the new H2 secret-set call still fails, kvref-h2 stays absent, ingress stays HTTP 200 on {baseline_revision_name!r}, and the H2 firewall query now shows Deny rows.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H2 observability-restored gate.',
    'hypothesis': 'H2_observability_restored',
    'path_used': 'single',
    'predicate_inputs': {
        'h2_diagnostics_enabled': repo_rel('10-h2-firewall-diagnostics-enabled.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_firewall_deny_log': repo_rel('13-h2-firewall-deny-log.json'),
    },
    f'{SCENARIO}_h2_observability_restored_all_subgates_pass': gate16_all,
    f'{SCENARIO}_h2_observability_restored_sub_gates': {
        'a_applicationrule_logging_enabled_while_entra_rule_stays_absent': subgate_16a,
        'b_pre_h2_guard_confirms_no_retroactive_deny_rows': subgate_16b,
        'c_h2_secret_set_still_failed_nonzero_exit': subgate_16c,
        'd_h2_silence_gate_holds_revision_unchanged_ingress_200_secret_absent': subgate_16d,
        'e_h2_firewall_deny_row_visible_after_new_attempt': subgate_16e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'H2 re-enabled AzureFirewallApplicationRule logging while keeping the Entra rule collection absent.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-firewall-diagnostics-enabled.json')],
            'observed_values': {
                'azure_firewall_application_rule_logging_enabled': d10.get('azure_firewall_application_rule_logging_enabled'),
                'post_enable_collections_in_group': d10.get('post_enable_collections_in_group'),
                'diagnostic_setting_name': d10.get('diagnostic_setting_name'),
            },
            'predicate': '10.azure_firewall_application_rule_logging_enabled == True AND entra_rule_collection_name NOT IN 10.post_enable_collections_in_group.',
            'result': 'pass' if subgate_16a else 'fail',
            'sub_gate': 'a_applicationrule_logging_enabled_while_entra_rule_stays_absent',
        },
        {
            'claim': 'The pre-H2 guard proves logging is not retroactive: zero Deny rows exist between diagnostic re-enable and the new H2 attempt start.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-firewall-diagnostics-enabled.json')],
            'observed_values': {
                'pre_h2_guard_window_start_iso': d10.get('pre_h2_guard_window_start_iso'),
                'pre_h2_guard_window_end_iso': d10.get('pre_h2_guard_window_end_iso'),
                'pre_h2_guard_deny_row_count': d10.get('pre_h2_guard_deny_row_count'),
            },
            'predicate': '10.pre_h2_guard_deny_row_count == 0.',
            'result': 'pass' if subgate_16b else 'fail',
            'sub_gate': 'b_pre_h2_guard_confirms_no_retroactive_deny_rows',
        },
        {
            'claim': 'The new H2 secret-set attempt still failed with a non-zero exit code.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('11-h2-secret-set-outcome.json')],
            'observed_values': {'exit_code': d11.get('exit_code'), 'outcome': d11.get('outcome'), 'h2_secret_set_start_iso': h2_start},
            'predicate': '11.exit_code != 0 AND 11.outcome == "failure".',
            'result': 'pass' if subgate_16c else 'fail',
            'sub_gate': 'c_h2_secret_set_still_failed_nonzero_exit',
        },
        {
            'claim': 'H2 still leaves the running revision untouched: revision unchanged, ingress HTTP 200, and kvref-h2 absent.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('12-h2-app-state.json')],
            'observed_values': {
                'latest_revision_unchanged_vs_baseline': d12.get('latest_revision_unchanged_vs_baseline'),
                'ingress_probe_http_code': d12.get('ingress_probe_http_code'),
                'observed_secret_present': d12.get('observed_secret_present'),
            },
            'predicate': '12.latest_revision_unchanged_vs_baseline == True AND 12.ingress_probe_http_code == "200" AND 12.observed_secret_present == False.',
            'result': 'pass' if subgate_16d else 'fail',
            'sub_gate': 'd_h2_silence_gate_holds_revision_unchanged_ingress_200_secret_absent',
        },
        {
            'claim': 'After the new H2 attempt, the denial becomes visible: the firewall query returns at least one Deny row.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('13-h2-firewall-deny-log.json')],
            'observed_values': {'final_deny_row_count': h2_deny_count, 'attempts': d13.get('attempts') or []},
            'predicate': '13.final_deny_row_count >= 1.',
            'result': 'pass' if subgate_16e else 'fail',
            'sub_gate': 'e_h2_firewall_deny_row_visible_after_new_attempt',
        },
    ],
    'thresholds': {'h2_deny_row_expected_min': 1, 'h2_exit_code_expected_nonzero': True, 'pre_h2_guard_expected_exact': 0},
    'utc_captured': utc_now,
}

held_constant_checks = {
    'app_name_same': d08.get('app_name') == d12.get('app_name') == app_name,
    'firewall_policy_same': d06.get('firewall_policy_name') == d10.get('firewall_policy_name') == firewall_policy_name,
    'firewall_resource_id_same': d06.get('firewall_resource_id') == d10.get('firewall_resource_id') == firewall_resource_id,
    'rule_collection_name_same': d06.get('rule_collection_name') == d10.get('rule_collection_name') == entra_rule_collection_name,
    'log_analytics_workspace_same': d09.get('log_analytics_customer_id') == d13.get('log_analytics_customer_id') == log_analytics_customer_id,
    'baseline_revision_same': d08.get('latest_ready_revision_name') == d12.get('latest_ready_revision_name') == baseline_revision_name,
    'rule_absent_both_h1_and_h2': entra_rule_collection_name not in (d06.get('post_remove_collections_in_group') or []) and entra_rule_collection_name not in (d10.get('post_enable_collections_in_group') or []),
    'logging_flipped_only': d06.get('azure_firewall_application_rule_logging_enabled') is False and d10.get('azure_firewall_application_rule_logging_enabled') is True,
}

subgate_17a = subgate_15a
subgate_17b = subgate_15b and subgate_15c and subgate_15e
subgate_17c = subgate_16a and subgate_16b and subgate_16c and subgate_16e
subgate_17d = subgate_14g
subgate_17e = all(held_constant_checks.values())
gate17_all = all([subgate_17a, subgate_17b, subgate_17c, subgate_17d, subgate_17e])

DOCUMENTED_EXPLICIT_DROPS = [
    {
        'id': 'stderr_substring_wording',
        'note': 'The pack does not gate on exact CLI stderr wording because Azure CLI wrapping varies by version.',
    },
    {
        'id': 'firewall_log_ingestion_latency_seconds',
        'note': 'The pack proves only the bounded row-count predicates, not the exact ingestion latency of Azure Firewall diagnostics.',
    },
    {
        'id': 'aca_control_plane_retry_schedule',
        'note': 'The pack does not prove how many internal ACA retries occurred before the error surfaced.',
    },
    {
        'id': 'aca_control_plane_component_identity',
        'note': 'The pack does not identify the specific internal ACA component that performed the Entra discovery call.',
    },
    {
        'id': 'oidc_discovery_response_body_shape',
        'note': 'The pack proves firewall denial visibility, not the exact HTTP response body that Entra would have returned absent the denial.',
    },
    {
        'id': 'token_caching_and_late_retry_behavior',
        'note': 'The pre-H2 guard bounds misattribution, but the pack does not prove all ACA token-caching or delayed retry internals.',
    },
    {
        'id': 'firewall_sku_generality',
        'note': 'The pack was designed for Azure Firewall Basic and does not prove identical behavior across other firewall SKUs.',
    },
    {
        'id': 'region_generality',
        'note': 'The pack covers one regional cohort only and does not generalize across regions.',
    },
]

gate17 = {
    'claim': (
        f'This evidence pack falsifies the H4b logging-gap hypothesis within a bounded scope on {app_name} in {resource_group} ({location}). '
        f'Non-vacuous proof requires four observations together: (a) H0 baseline success with the Entra rule present; '
        f'(b) H1 trigger-absence: the rule stayed absent, logging was disabled, secret set failed, and zero Deny rows were visible; '
        f'(c) H2 observability-restoration: the rule still stayed absent, logging was re-enabled, a NEW secret-set attempt still failed, and Deny rows became visible; '
        f'(d) the silence invariant held on baseline revision {baseline_revision_name!r}. The bounded H1↔H2 claim is only that the AzureFirewallApplicationRule diagnostic category enable flag is the controlled observability variable while connectivity remains broken.'
    ),
    'claim_level': 'Observed',
    'cohort_binding_note': {
        'claim_ceiling': 'The pack proves a bounded observability inversion only. It does not generalize beyond the explicit drops listed below.',
        'explicit_drops': DOCUMENTED_EXPLICIT_DROPS,
    },
    'gate_classification': 'Bounded falsification gate.',
    'hypothesis': 'H3_bounded_falsification',
    'path_used': 'bounded',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_remove_and_disable': repo_rel('06-h1-firewall-rule-removed.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_firewall_log_gap': repo_rel('09-h1-firewall-deny-log-absent.json'),
        'h2_diagnostics_enabled': repo_rel('10-h2-firewall-diagnostics-enabled.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_firewall_deny_log': repo_rel('13-h2-firewall-deny-log.json'),
    },
    f'{SCENARIO}_h3_bounded_falsification_all_subgates_pass': gate17_all,
    f'{SCENARIO}_h3_bounded_falsification_sub_gates': {
        'a_baseline_presence_h0_succeeded_with_rule_present': subgate_17a,
        'b_trigger_absence_h1_failed_with_rule_absent_and_logging_gap': subgate_17b,
        'c_observability_restoration_h2_failed_with_rule_absent_and_deny_visible': subgate_17c,
        'd_silence_invariant_holds_same_revision_across_h0_h1_h2': subgate_17d,
        'e_only_the_documented_observability_variable_changed_between_h1_and_h2': subgate_17e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'Non-vacuous baseline: H0 succeeded when the Entra rule was present.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('04-h0-secret-set-outcome.json')],
            'observed_values': {'h0_exit_code': d04.get('exit_code'), 'h0_outcome': d04.get('outcome')},
            'predicate': '04.exit_code == 0.',
            'result': 'pass' if subgate_17a else 'fail',
            'sub_gate': 'a_baseline_presence_h0_succeeded_with_rule_present',
        },
        {
            'claim': 'H1 trigger-absence: the rule was absent, logging was disabled, secret set failed, and zero Deny rows were visible.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-firewall-rule-removed.json'), repo_rel('07-h1-secret-set-outcome.json'), repo_rel('09-h1-firewall-deny-log-absent.json')],
            'observed_values': {'h1_exit_code': d07.get('exit_code'), 'h1_final_deny_row_count': h1_deny_count},
            'predicate': '06 removes rule + disables logging AND 07.exit_code != 0 AND 09.final_deny_row_count == 0.',
            'result': 'pass' if subgate_17b else 'fail',
            'sub_gate': 'b_trigger_absence_h1_failed_with_rule_absent_and_logging_gap',
        },
        {
            'claim': 'H2 observability-restoration: the rule remained absent, logging was re-enabled, secret set still failed, and Deny rows became visible.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-firewall-diagnostics-enabled.json'), repo_rel('11-h2-secret-set-outcome.json'), repo_rel('13-h2-firewall-deny-log.json')],
            'observed_values': {'h2_exit_code': d11.get('exit_code'), 'h2_final_deny_row_count': h2_deny_count},
            'predicate': '10 enables logging with rule absent AND 11.exit_code != 0 AND 13.final_deny_row_count >= 1.',
            'result': 'pass' if subgate_17c else 'fail',
            'sub_gate': 'c_observability_restoration_h2_failed_with_rule_absent_and_deny_visible',
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
            'claim': 'Between H1 and H2, every non-observability anchor stayed constant; only the AzureFirewallApplicationRule diagnostic category flipped from disabled to enabled while the Entra rule stayed absent in both phases.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['06-h1-firewall-rule-removed.json', '08-h1-app-state.json', '10-h2-firewall-diagnostics-enabled.json', '12-h2-app-state.json']],
            'observed_values': {'held_constant_checks': held_constant_checks},
            'predicate': 'All entries in held_constant_checks are True.',
            'result': 'pass' if subgate_17e else 'fail',
            'sub_gate': 'e_only_the_documented_observability_variable_changed_between_h1_and_h2',
        },
    ],
    'thresholds': {
        'h0_exit_code_expected': 0,
        'h1_exit_code_expected_nonzero': True,
        'h1_deny_row_expected_exact': 0,
        'h2_exit_code_expected_nonzero': True,
        'h2_deny_row_expected_min': 1,
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
    15: evidence_dir / '15-h1-trigger-produces-failure-gate.json',
    16: evidence_dir / '16-h2-observability-restored-gate.json',
    17: evidence_dir / '17-bounded-falsification-gate.json',
}
gate_success_messages = {
    14: 'cohort integrity verified',
    15: 'H1 trigger produces failure verified',
    16: 'H2 observability restored verified',
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
