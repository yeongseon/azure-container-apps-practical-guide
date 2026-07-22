#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/aca-secret-kv-ref-mi-network-path-h4g/evidence"
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
    '06-h1-entra-rule-updated.json',
    '07-h1-secret-set-outcome.json',
    '08-h1-app-state.json',
    '09-h1-rule-state-and-openssl.json',
    '10-h2-entra-rule-updated.json',
    '11-h2-secret-set-outcome.json',
    '12-h2-app-state.json',
    '13-h2-rule-state-and-openssl.json',
]

GATE_OUTPUTS = [
    '14-cohort-integrity-gate.json',
    '15-h1-tls-inspection-produces-failure-gate.json',
    '16-h2-exemption-restores-success-gate.json',
    '17-bounded-falsification-gate.json',
]

SCENARIO = 'aca_secret_kv_ref_mi_network_path_h4g'


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


def get_entra_rule(doc: dict) -> dict:
    return doc.get('entra_rule') or {}


def rule_matches_entra_authority_https(rule: dict, expected_terminate_tls=None) -> bool:
    if not isinstance(rule, dict):
        return False
    if rule.get('ruleType') != 'ApplicationRule':
        return False
    protocols = rule.get('protocols') or []
    https_443 = any((p or {}).get('protocolType') == 'Https' and (p or {}).get('port') == 443 for p in protocols)
    if not https_443:
        return False
    target_fqdns = set(rule.get('targetFqdns') or [])
    if {'login.microsoftonline.com', 'login.microsoft.com'} - target_fqdns:
        return False
    if expected_terminate_tls is not None and rule.get('terminateTLS') is not expected_terminate_tls:
        return False
    return True


def route_points_to_firewall(doc: dict, expected_ip: str) -> bool:
    route = doc.get('route_table_default_route') or {}
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
    if (doc.get('firewall_private_ip') or '') in ('', None):
        fail_gate(14, f'{file_name} missing required firewall_private_ip anchor')
    return {
        'firewall_private_ip': doc.get('firewall_private_ip'),
        'addressPrefix': route.get('addressPrefix'),
        'nextHopType': route.get('nextHopType'),
        'nextHopIpAddress': route.get('nextHopIpAddress'),
    }


def classify_h1_stderr(stderr_text: str):
    # NOTE: the exact production stderr string is PENDING a real Azure Firewall
    # Premium run and must not be asserted verbatim. This classifier intentionally
    # accepts (managed-identity clue OR OIDC clue) AND a TLS/certificate clue.
    text = (stderr_text or '').lower()
    managed_identity_or_oidc_clues = [
        'failed to update secrets',
        'unable to get value using managed identity',
        'openid-configuration',
        'openid connect',
        'login.microsoftonline.com',
    ]
    tls_or_certificate_clues = [
        'x509: certificate signed by unknown authority',
        'certificate verify failed',
        'unable to get local issuer certificate',
        'self-signed certificate in certificate chain',
        'tls handshake',
    ]
    forbidden_non_h4g_clues = [
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
    found_tls_or_cert = [c for c in tls_or_certificate_clues if c in text]
    forbidden_found = [c for c in forbidden_non_h4g_clues if c in text]
    return {
        'managed_or_oidc_clues_found': found_managed_or_oidc,
        'tls_or_certificate_clues_found': found_tls_or_cert,
        'forbidden_non_h4g_clues_found': forbidden_found,
        'passes_classifier': bool(found_managed_or_oidc) and bool(found_tls_or_cert) and not forbidden_found,
    }


def openssl_capture_matches(doc: dict, expected_contains_lab_ca: bool):
    capture = (doc or {}).get('workload_openssl_capture') or {}
    return (
        capture.get('status') == 'completed'
        and capture.get('reader_asserted_contains_lab_intermediate_ca') is expected_contains_lab_ca
    )


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
    'firewall_policy_name', 'firewall_rule_collection_group_name', 'entra_rule_collection_name',
    'entra_rule_name', 'firewall_private_ip',
]
missing_01 = [key for key in required_01 if d01.get(key) in (None, '')]
if missing_01 or d01.get('lab_name') != 'aca-secret-kv-ref-mi-network-path-h4g':
    fail_gate(5, f"01 anchors invalid; missing={missing_01}, lab_name={d01.get('lab_name')}")
pass_gate(5, '01 parses and carries H4g cohort anchors')

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
if d01.get('azure_firewall_present') is not True or d01.get('azure_firewall_sku') != 'Premium':
    gate10_problems.append('01 must prove Azure Firewall Premium is present')
if d01.get('firewall_policy_present') is not True or d01.get('firewall_policy_sku') != 'Premium':
    gate10_problems.append('01 must prove Firewall Policy Premium is present')
if d01.get('tls_inspection_configured') is not True:
    gate10_problems.append('01 must prove TLS inspection is configured')
if d01.get('route_table_attached') is not True or d01.get('aca_subnet_route_table_id') in (None, ''):
    gate10_problems.append('01 must prove a route table is attached to the ACA subnet')
if not route_points_to_firewall(d01, d01.get('firewall_private_ip') or ''):
    gate10_problems.append('01 must prove the default route points to the Azure Firewall private IP')
if d01.get('uses_azure_provided_dns') is not True or (d01.get('vnet_dns_servers') or []) != []:
    gate10_problems.append('01 must prove the VNet uses Azure-provided DNS (no custom dnsServers)')
if d01.get('nsg_deny_present') is not False:
    gate10_problems.append('01 must prove no NSG deny trigger is present')
if d01.get('dns_override_present') is not False:
    gate10_problems.append('01 must prove no custom DNS override exists')
if d01.get('vwan_routing_intent_present') is not False:
    gate10_problems.append('01 must prove no Virtual WAN routing intent exists')
if not rule_matches_entra_authority_https(get_entra_rule(d01), expected_terminate_tls=False):
    gate10_problems.append('01 must prove the Entra-authority application rule exists with terminateTLS=false')
if contains_forbidden_storage_or_flowlog_artifact([d01, d06, d09, d10, d13]):
    gate10_problems.append('The cohort must not reference storage-account, flow-log, or Traffic Analytics artifacts')
if gate10_problems:
    fail_gate(10, '; '.join(gate10_problems))
pass_gate(10, '01 proves the H4g topology anchors: Firewall Premium + TLS inspection + route table + no DNS/NSG/Virtual WAN confounder')

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
pass_gate(13, '09-13 H1 TLS-inspection failure + H2 exemption recovery cohort valid')

app_name = d01['app_name']
resource_group = d01['resource_group']
location = d01['location']
baseline_revision_name = d02['latest_ready_revision_name']
firewall_policy_name = d01['firewall_policy_name']
firewall_private_ip = d01['firewall_private_ip']

h0_anchor_docs = {
    '01': required_anchor_map(d01, '01-deployment-outputs.json'),
    '02': required_anchor_map(d02, '02-h0-app-state-before.json'),
    '03': required_anchor_map(d03, '03-h0-kv-secret-created.json'),
    '04': required_anchor_map(d04, '04-h0-secret-set-outcome.json'),
    '05': required_anchor_map(d05, '05-h0-app-state-after.json'),
}
h1_anchor_docs = {
    '06': required_anchor_map(d06, '06-h1-entra-rule-updated.json'),
    '07': required_anchor_map(d07, '07-h1-secret-set-outcome.json'),
    '08': required_anchor_map(d08, '08-h1-app-state.json'),
    '09': required_anchor_map(d09, '09-h1-rule-state-and-openssl.json'),
}
h2_anchor_docs = {
    '10': required_anchor_map(d10, '10-h2-entra-rule-updated.json'),
    '11': required_anchor_map(d11, '11-h2-secret-set-outcome.json'),
    '12': required_anchor_map(d12, '12-h2-app-state.json'),
    '13': required_anchor_map(d13, '13-h2-rule-state-and-openssl.json'),
}
anchor_reference = h0_anchor_docs['01']
anchor_consistency = {
    phase_file: anchor_values == anchor_reference
    for phase_file, anchor_values in {**h0_anchor_docs, **h1_anchor_docs, **h2_anchor_docs}.items()
}
route_anchor_docs = {
    '01': route_anchor_map(d01, '01-deployment-outputs.json'),
    '06': route_anchor_map(d06, '06-h1-entra-rule-updated.json'),
    '09': route_anchor_map(d09, '09-h1-rule-state-and-openssl.json'),
    '10': route_anchor_map(d10, '10-h2-entra-rule-updated.json'),
    '13': route_anchor_map(d13, '13-h2-rule-state-and-openssl.json'),
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
firewall_policy_refs = {
    '01': d01.get('firewall_policy_name'),
    '06': d06.get('firewall_policy_name'),
    '09': d09.get('firewall_policy_name'),
    '10': d10.get('firewall_policy_name'),
    '13': d13.get('firewall_policy_name'),
}
rev_h0_after = d05.get('latest_ready_revision_name')
rev_h1 = d08.get('latest_ready_revision_name')
rev_h2 = d12.get('latest_ready_revision_name')

subgate_14a = len(timestamp_violations) == 0
subgate_14b = all(value == app_name for value in app_name_refs.values())
subgate_14c = all(value == firewall_policy_name for value in firewall_policy_refs.values())
subgate_14d = baseline_revision_name == rev_h0_after == rev_h1 == rev_h2
subgate_14e = (
    all(anchor_consistency.values())
    and all(route_anchor_consistency.values())
    and
    d01.get('azure_firewall_present') is True
    and d01.get('azure_firewall_sku') == 'Premium'
    and d01.get('firewall_policy_present') is True
    and d01.get('tls_inspection_configured') is True
    and d01.get('route_table_attached') is True
    and route_points_to_firewall(d01, firewall_private_ip)
    and d01.get('nsg_deny_present') is False
    and d01.get('dns_override_present') is False
    and d01.get('vwan_routing_intent_present') is False
    and rule_matches_entra_authority_https(get_entra_rule(d01), expected_terminate_tls=False)
    and not contains_forbidden_storage_or_flowlog_artifact([d01, d06, d07, d08, d09, d10, d11, d12, d13])
)
gate14_all = all([subgate_14a, subgate_14b, subgate_14c, subgate_14d, subgate_14e])

gate14 = {
    'claim': (
        f'The evidence cohort for the aca-secret-kv-ref-mi-network-path-h4g lab on {app_name} '
        f'in {resource_group} ({location}) is internally consistent: all 13 raw files are present '
        f'and parseable, timestamps are monotonic, cross-file anchors agree, the baseline revision '
        f'{baseline_revision_name!r} stays unchanged across H0/H1/H2, and the deployed topology proves '
        f'Azure Firewall Premium, Firewall Policy Premium, TLS inspection, a route table with 0.0.0.0/0 to {firewall_private_ip!r}, '
        f'no NSG-deny trigger, no DNS override, and no Virtual WAN routing intent.'
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
        'c_firewall_policy_anchor_consistent': subgate_14c,
        'd_baseline_revision_silence_invariant_holds': subgate_14d,
        'e_full_cohort_anchor_contract_and_h4g_topology_hold': subgate_14e,
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
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-entra-rule-updated.json', '09-h1-rule-state-and-openssl.json', '10-h2-entra-rule-updated.json', '13-h2-rule-state-and-openssl.json']],
            'observed_values': firewall_policy_refs,
            'predicate': 'All firewall_policy_name fields equal 01.firewall_policy_name.',
            'result': 'pass' if subgate_14c else 'fail',
            'sub_gate': 'c_firewall_policy_anchor_consistent',
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
            'claim': 'The full cohort-consistency contract and H4g topology both hold: resource group, environment name, app principal ID, Key Vault, tenant ID, and baseline revision are byte-equal across H0/H1/H2, and the route-table default next hop stays byte-equal across H0/H1/H2 while NSG / DNS / Virtual WAN confounders remain absent.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in RAW_FILES],
            'observed_values': {
                'anchor_reference': anchor_reference,
                'anchor_consistency': anchor_consistency,
                'route_anchor_reference': route_anchor_reference,
                'route_anchor_consistency': route_anchor_consistency,
                'azure_firewall_present': d01.get('azure_firewall_present'),
                'azure_firewall_sku': d01.get('azure_firewall_sku'),
                'firewall_policy_present': d01.get('firewall_policy_present'),
                'tls_inspection_configured': d01.get('tls_inspection_configured'),
                'route_table_attached': d01.get('route_table_attached'),
                'default_route_next_hop': (d01.get('route_table_default_route') or {}).get('nextHopIpAddress'),
                'nsg_deny_present': d01.get('nsg_deny_present'),
                'dns_override_present': d01.get('dns_override_present'),
                'vwan_routing_intent_present': d01.get('vwan_routing_intent_present'),
            },
            'predicate': 'All required anchor fields are present and byte-equal across H0/H1/H2, all route default-route anchors are present and byte-equal across H0/H1/H2, and 01 proves Firewall Premium + Policy Premium + TLS inspection + route-table-to-firewall with no NSG deny / DNS override / Virtual WAN routing intent confounder.',
            'result': 'pass' if subgate_14e else 'fail',
            'sub_gate': 'e_full_cohort_anchor_contract_and_h4g_topology_hold',
        },
    ],
    'thresholds': {'expected_raw_file_count': 13, 'expected_gate_output_count': 4},
    'utc_captured': utc_now,
}

h1_classifier = classify_h1_stderr(d07.get('stderr') or '')
subgate_15a = isinstance(d07.get('exit_code'), int) and d07.get('exit_code') != 0 and h1_classifier['passes_classifier']
subgate_15b = (
    d08.get('latest_revision_unchanged_vs_baseline') is True
    and d08.get('ingress_probe_http_code') == '200'
    and d08.get('secret_presence_expectation_met') is True
    and d08.get('observed_secret_present') is False
)
subgate_15c = rule_matches_entra_authority_https(get_entra_rule(d06), expected_terminate_tls=True) and d06.get('entra_authority_terminate_tls') is True
subgate_15d = openssl_capture_matches(d09, expected_contains_lab_ca=True)
subgate_15e = route_points_to_firewall(d06, firewall_private_ip) and d06.get('azure_firewall_present') is True and d06.get('nsg_deny_present') is False and d06.get('dns_override_present') is False and d06.get('vwan_routing_intent_present') is False
gate15_all = all([subgate_15a, subgate_15b, subgate_15c, subgate_15d, subgate_15e])

gate15 = {
    'claim': (
        f'H1 proves the TLS-inspection trigger: after setting terminateTLS=true on the Entra-authority application rule in {firewall_policy_name!r}, '
        f'`az containerapp secret set --secrets <name>=keyvaultref:<url>,identityref:system` fails on {app_name}, stderr matches a managed-identity / OIDC clue plus a TLS / certificate clue, '
        f'the baseline revision {baseline_revision_name!r} keeps serving HTTP 200, kvref-h1 stays absent, and the workload-replica openssl capture shows the unexpected lab interception CA chain.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H1 TLS-inspection gate.',
    'hypothesis': 'H1_tls_inspection_produces_failure',
    'path_used': 'single',
    'predicate_inputs': {
        'h1_rule_update': repo_rel('06-h1-entra-rule-updated.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_app_state': repo_rel('08-h1-app-state.json'),
        'h1_rule_state_and_openssl': repo_rel('09-h1-rule-state-and-openssl.json'),
    },
    f'{SCENARIO}_h1_tls_inspection_produces_failure_all_subgates_pass': gate15_all,
    f'{SCENARIO}_h1_tls_inspection_produces_failure_sub_gates': {
        'a_h1_secret_set_failed_with_classifier_signature': subgate_15a,
        'b_silence_gate_holds_revision_unchanged_ingress_200_secret_absent': subgate_15b,
        'c_h1_entra_rule_exists_with_terminate_tls_true': subgate_15c,
        'd_h1_workload_openssl_shows_lab_ca': subgate_15d,
        'e_h1_topology_anchors_stayed_constant': subgate_15e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'The H1 secret-set attempt failed with the classifier signature: (managed-identity clue OR OIDC clue) AND a TLS/certificate clue, without Key Vault-permission, missing-secret, or revision-failure markers.',
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
            'claim': 'H1 set the Entra-authority application rule to terminateTLS=true while keeping the rest of the route/firewall topology present.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-entra-rule-updated.json')],
            'observed_values': {'entra_rule': get_entra_rule(d06)},
            'predicate': '06.entra_rule matches https login.microsoftonline.com + login.microsoft.com with terminateTLS=true.',
            'result': 'pass' if subgate_15c else 'fail',
            'sub_gate': 'c_h1_entra_rule_exists_with_terminate_tls_true',
        },
        {
            'claim': 'The H1 workload-replica openssl capture shows the lab interception CA chain on the workload data plane.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('09-h1-rule-state-and-openssl.json')],
            'observed_values': {'workload_openssl_capture': d09.get('workload_openssl_capture')},
            'predicate': '09.workload_openssl_capture.status == "completed" AND reader_asserted_contains_lab_intermediate_ca == true.',
            'result': 'pass' if subgate_15d else 'fail',
            'sub_gate': 'd_h1_workload_openssl_shows_lab_ca',
        },
        {
            'claim': 'H1 retained the H4g topology anchors: Firewall Premium, route table to the firewall private IP, no NSG-deny trigger, no DNS override, and no Virtual WAN routing intent.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-entra-rule-updated.json')],
            'observed_values': {
                'route_table_default_route': d06.get('route_table_default_route'),
                'azure_firewall_present': d06.get('azure_firewall_present'),
                'nsg_deny_present': d06.get('nsg_deny_present'),
                'dns_override_present': d06.get('dns_override_present'),
                'vwan_routing_intent_present': d06.get('vwan_routing_intent_present'),
            },
            'predicate': '06 preserves the H4g topology anchors and only changes terminateTLS on the Entra-authority rule.',
            'result': 'pass' if subgate_15e else 'fail',
            'sub_gate': 'e_h1_topology_anchors_stayed_constant',
        },
    ],
    'thresholds': {'h1_exit_code_expected_nonzero': True, 'h1_entra_rule_terminate_tls_expected': True},
    'utc_captured': utc_now,
}

subgate_16a = rule_matches_entra_authority_https(get_entra_rule(d10), expected_terminate_tls=False) and d10.get('entra_authority_terminate_tls') is False
subgate_16b = isinstance(d11.get('exit_code'), int) and d11.get('exit_code') == 0 and d11.get('outcome') == 'success'
subgate_16c = (
    d12.get('latest_revision_unchanged_vs_baseline') is True
    and d12.get('ingress_probe_http_code') == '200'
    and d12.get('secret_presence_expectation_met') is True
    and d12.get('observed_secret_present') is True
)
subgate_16d = openssl_capture_matches(d13, expected_contains_lab_ca=False)
subgate_16e = all(route_anchor_consistency.values()) and d10.get('azure_firewall_present') is True and d10.get('route_table_attached') is True
gate16_all = all([subgate_16a, subgate_16b, subgate_16c, subgate_16d, subgate_16e])

gate16 = {
    'claim': (
        f'H2 proves the documented exemption is sufficient for recovery: the Entra-authority application rule in {firewall_policy_name!r} '
        f'was restored to terminateTLS=false, a NEW secret-set attempt succeeded on {app_name}, kvref-h2 appeared, ingress stayed HTTP 200 on {baseline_revision_name!r}, '
        f'and the workload-replica openssl capture no longer showed the lab interception CA chain.'
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H2 exemption-remediation gate.',
    'hypothesis': 'H2_exemption_restores_success',
    'path_used': 'single',
    'predicate_inputs': {
        'h2_rule_update': repo_rel('10-h2-entra-rule-updated.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_rule_state_and_openssl': repo_rel('13-h2-rule-state-and-openssl.json'),
    },
    f'{SCENARIO}_h2_exemption_restores_success_all_subgates_pass': gate16_all,
    f'{SCENARIO}_h2_exemption_restores_success_sub_gates': {
        'a_h2_entra_rule_exists_with_terminate_tls_false': subgate_16a,
        'b_h2_secret_set_succeeded_zero_exit': subgate_16b,
        'c_h2_success_gate_holds_revision_unchanged_ingress_200_secret_present': subgate_16c,
        'd_h2_workload_openssl_no_longer_shows_lab_ca': subgate_16d,
        'e_firewall_and_route_table_presence_stayed_constant': subgate_16e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'H2 restored the Entra-authority application rule to terminateTLS=false.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-entra-rule-updated.json')],
            'observed_values': {'entra_rule': get_entra_rule(d10)},
            'predicate': '10.entra_rule matches https login.microsoftonline.com + login.microsoft.com with terminateTLS=false.',
            'result': 'pass' if subgate_16a else 'fail',
            'sub_gate': 'a_h2_entra_rule_exists_with_terminate_tls_false',
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
            'claim': 'The H2 workload-replica openssl capture no longer shows the lab interception CA chain on the workload data plane.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('13-h2-rule-state-and-openssl.json')],
            'observed_values': {'workload_openssl_capture': d13.get('workload_openssl_capture')},
            'predicate': '13.workload_openssl_capture.status == "completed" AND reader_asserted_contains_lab_intermediate_ca == false.',
            'result': 'pass' if subgate_16d else 'fail',
            'sub_gate': 'd_h2_workload_openssl_no_longer_shows_lab_ca',
        },
        {
            'claim': 'Firewall presence and route-table presence stayed constant while the Entra-authority rule was restored to the exemption state.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-entra-rule-updated.json', '10-h2-entra-rule-updated.json']],
            'observed_values': {
                'h0_default_route': d01.get('route_table_default_route'),
                'h1_default_route': d06.get('route_table_default_route'),
                'h2_default_route': d10.get('route_table_default_route'),
                'route_anchor_consistency': route_anchor_consistency,
                'h2_firewall_present': d10.get('azure_firewall_present'),
                'h2_route_table_attached': d10.get('route_table_attached'),
            },
            'predicate': 'Route table stays attached with 0.0.0.0/0 to the same firewall private IP across H0/H1/H2 and firewall presence remains true across H0/H1/H2.',
            'result': 'pass' if subgate_16e else 'fail',
            'sub_gate': 'e_firewall_and_route_table_presence_stayed_constant',
        },
    ],
    'thresholds': {'h2_exit_code_expected': 0, 'h2_entra_rule_terminate_tls_expected': False},
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
    'firewall_policy_same_across_h1_h2': d06.get('firewall_policy_name') == d09.get('firewall_policy_name') == d10.get('firewall_policy_name') == d13.get('firewall_policy_name') == firewall_policy_name,
    'firewall_present_both_phases': d06.get('azure_firewall_present') is True and d10.get('azure_firewall_present') is True,
    'route_table_present_both_phases': d06.get('route_table_attached') is True and d10.get('route_table_attached') is True,
    'dns_nsg_vwan_constant': d06.get('nsg_deny_present') is False and d10.get('nsg_deny_present') is False and d06.get('dns_override_present') is False and d10.get('dns_override_present') is False and d06.get('vwan_routing_intent_present') is False and d10.get('vwan_routing_intent_present') is False,
    'tls_inspection_identity_same_across_h0_h1_h2': d01.get('tls_inspection_identity_resource_id') == d06.get('tls_inspection_identity_resource_id') == d10.get('tls_inspection_identity_resource_id'),
    'tls_inspection_ca_secret_same_across_h0_h1_h2': d01.get('tls_inspection_ca_key_vault_secret_id') == d06.get('tls_inspection_ca_key_vault_secret_id') == d10.get('tls_inspection_ca_key_vault_secret_id'),
    'only_variable_between_h1_and_h2_is_terminate_tls': rule_matches_entra_authority_https(get_entra_rule(d06), expected_terminate_tls=True) and rule_matches_entra_authority_https(get_entra_rule(d10), expected_terminate_tls=False),
}

DOCUMENTED_EXPLICIT_DROPS = [
    'Does NOT prove a control-plane packet capture.',
    'Does NOT prove a direct control-plane TLS-chain observation.',
    'Does NOT prove workload and control-plane egress are identical.',
    'Does NOT prove behavior beyond the exercised Entra authority FQDNs login.microsoftonline.com and login.microsoft.com.',
    'Does NOT prove anything about third-party NVAs or non-Azure proxies.',
    'Does NOT prove Key Vault data-plane failure (Key Vault, identity, and RBAC stay constant while only the Entra-authority TLS-inspection flag flips).',
]

subgate_17a = d04.get('exit_code') == 0 and d04.get('outcome') == 'success'
subgate_17b = gate15_all
subgate_17c = gate16_all
subgate_17d = subgate_14d
subgate_17e = all(held_constant_checks.values())
gate17_all = all([subgate_17a, subgate_17b, subgate_17c, subgate_17d, subgate_17e])

gate17 = {
    'claim': (
        f'This evidence pack falsifies the H4g Azure Firewall Premium TLS-inspection hypothesis within a bounded scope on {app_name} in {resource_group} ({location}). '
        f'Non-vacuous proof requires four observations together: (a) H0 baseline success with Firewall Premium, Policy Premium, TLS inspection, and the Entra-authority rule present with terminateTLS=false; '
        f'(b) H1 trigger-presence: the same Entra-authority rule existed with terminateTLS=true and secret set failed with the classifier signature; '
        f'(c) H2 fix: the same Entra-authority rule returned to terminateTLS=false and a NEW secret-set attempt succeeded; '
        f'(d) the silence invariant held on baseline revision {baseline_revision_name!r}. The bounded conclusion is only that TLS inspection of the Entra authority FQDNs is necessary and sufficient to reproduce this lab\'s secret-resolution failure while all other captured anchors stayed constant.'
    ),
    'claim_level': 'Observed',
    'cohort_binding_note': {
        'claim_ceiling': 'The pack proves a bounded Entra-authority TLS-inspection inversion only. It does not generalize beyond the explicit drops listed below.',
        'explicit_drops': DOCUMENTED_EXPLICIT_DROPS,
    },
    'gate_classification': 'Bounded falsification gate.',
    'hypothesis': 'H3_bounded_falsification',
    'path_used': 'bounded',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_rule_update': repo_rel('06-h1-entra-rule-updated.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_rule_state_and_openssl': repo_rel('09-h1-rule-state-and-openssl.json'),
        'h2_rule_update': repo_rel('10-h2-entra-rule-updated.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_rule_state_and_openssl': repo_rel('13-h2-rule-state-and-openssl.json'),
    },
    f'{SCENARIO}_h3_bounded_falsification_all_subgates_pass': gate17_all,
    f'{SCENARIO}_h3_bounded_falsification_sub_gates': {
        'a_baseline_presence_h0_succeeded_with_terminate_tls_false': subgate_17a,
        'b_trigger_presence_h1_failed_with_terminate_tls_true': subgate_17b,
        'c_fix_additive_h2_succeeded_with_terminate_tls_false': subgate_17c,
        'd_silence_invariant_holds_same_revision_across_h0_h1_h2': subgate_17d,
        'e_only_the_documented_terminate_tls_flag_changed_between_h1_and_h2': subgate_17e,
    },
    'scenario': SCENARIO,
    'sub_gates': [
        {
            'claim': 'Non-vacuous baseline: H0 succeeded with Firewall Premium, TLS inspection configured, and the Entra-authority rule present with terminateTLS=false.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('01-deployment-outputs.json'), repo_rel('04-h0-secret-set-outcome.json')],
            'observed_values': {
                'h0_exit_code': d04.get('exit_code'),
                'h0_entra_rule': get_entra_rule(d01),
            },
            'predicate': '04.exit_code == 0 AND 01.entra_rule.terminateTLS == false.',
            'result': 'pass' if subgate_17a else 'fail',
            'sub_gate': 'a_baseline_presence_h0_succeeded_with_terminate_tls_false',
        },
        {
            'claim': 'H1 trigger-presence: the Entra-authority rule existed with terminateTLS=true, secret set failed with the classifier signature, and the workload openssl capture showed the lab interception CA.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-entra-rule-updated.json'), repo_rel('07-h1-secret-set-outcome.json'), repo_rel('09-h1-rule-state-and-openssl.json')],
            'observed_values': {
                'h1_exit_code': d07.get('exit_code'),
                'h1_classifier': h1_classifier,
                'h1_entra_rule': get_entra_rule(d06),
            },
            'predicate': '06.entra_rule.terminateTLS == true AND 07.exit_code != 0 AND 09.workload_openssl_capture asserts lab CA present.',
            'result': 'pass' if subgate_17b else 'fail',
            'sub_gate': 'b_trigger_presence_h1_failed_with_terminate_tls_true',
        },
        {
            'claim': 'H2 fix-addition: the Entra-authority exemption was restored with terminateTLS=false, the new secret-set attempt succeeded, and the workload openssl capture no longer showed the lab interception CA.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-entra-rule-updated.json'), repo_rel('11-h2-secret-set-outcome.json'), repo_rel('13-h2-rule-state-and-openssl.json')],
            'observed_values': {
                'h2_exit_code': d11.get('exit_code'),
                'h2_entra_rule': get_entra_rule(d10),
                'h2_workload_openssl_capture': d13.get('workload_openssl_capture'),
            },
            'predicate': '10.entra_rule.terminateTLS == false AND 11.exit_code == 0 AND 13.workload_openssl_capture asserts lab CA absent.',
            'result': 'pass' if subgate_17c else 'fail',
            'sub_gate': 'c_fix_additive_h2_succeeded_with_terminate_tls_false',
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
            'claim': 'Between H1 and H2, every non-TLS-exemption anchor stayed constant; only the Entra-authority terminateTLS flag changed from true back to false.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(name) for name in ['01-deployment-outputs.json', '06-h1-entra-rule-updated.json', '08-h1-app-state.json', '10-h2-entra-rule-updated.json', '12-h2-app-state.json', '13-h2-rule-state-and-openssl.json']],
            'observed_values': {'held_constant_checks': held_constant_checks},
            'predicate': 'All entries in held_constant_checks are True.',
            'result': 'pass' if subgate_17e else 'fail',
            'sub_gate': 'e_only_the_documented_terminate_tls_flag_changed_between_h1_and_h2',
        },
    ],
    'thresholds': {
        'h0_exit_code_expected': 0,
        'h1_exit_code_expected_nonzero': True,
        'h2_exit_code_expected': 0,
        'h1_entra_rule_terminate_tls_expected': True,
        'h2_entra_rule_terminate_tls_expected': False,
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
    15: evidence_dir / '15-h1-tls-inspection-produces-failure-gate.json',
    16: evidence_dir / '16-h2-exemption-restores-success-gate.json',
    17: evidence_dir / '17-bounded-falsification-gate.json',
}
gate_success_messages = {
    14: 'cohort integrity verified',
    15: 'H1 TLS inspection produces failure verified',
    16: 'H2 exemption restores success verified',
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
