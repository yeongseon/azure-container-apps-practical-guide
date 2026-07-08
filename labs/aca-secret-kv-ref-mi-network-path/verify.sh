#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# verify.sh — Hermetic offline gate verifier for the
#             aca-secret-kv-ref-mi-network-path lab.
# -----------------------------------------------------------------------------
#
# What this script does:
#     Re-parses the committed raw evidence cohort (01-13) produced by
#     trigger.sh + falsify.sh, runs 13 prerequisite/schema gates, and then
#     deterministically writes the four Phase B gate JSON files (14-17).
#     Exits 0 only when every gate passes.
#
# What this script DOES NOT do:
#     - It never calls Azure. It reads only local files under evidence/.
#     - It never mutates the raw cohort (files 01-13). It only writes 14-17.
#     - It never runs `mkdocs build` or the doc-side content validator.
#
# Why hermetic:
#     The lab's claim is that a specific Path (Container App -> UDR -> Azure
#     Firewall Application Rule for the Entra authority -> Key Vault OIDC
#     discovery) is provably required for `az containerapp secret set
#     --identity system --key-vault-url ...` to succeed. That claim is
#     defended by an evidence cohort captured during ONE live run. Anyone
#     later reading this pack must be able to re-derive the same PASS/FAIL
#     verdicts from the committed evidence alone — otherwise the pack does
#     not defend itself.
#
# Gate map (all 17):
#     1  — evidence directory present
#     2  — raw files 01-05 present (H0 cohort from trigger.sh)
#     3  — raw files 06-09 present (H1 cohort from falsify.sh)
#     4  — raw files 10-13 present (H2 cohort from falsify.sh)
#     5  — 01-deployment-outputs.json parses + has required anchors
#     6  — 02-h0-app-state-before.json parses + has baseline surface fields
#     7  — 03-h0-kv-secret-created.json parses + has versionless KV URL
#     8  — 04-h0-secret-set-outcome.json parses + exit_code == 0
#     9  — 05-h0-app-state-after.json parses + revision unchanged + secret present
#     10 — 06-h1-firewall-rule-removed.json parses + rule collection absent
#     11 — 07-h1-secret-set-outcome.json parses + exit_code != 0
#     12 — 08-h1-app-state.json parses + all 3 silence-gate fields correct
#     13 — 09/10/11/12/13 parse + H1 deny + H2 restore + H2 success + H2 allow
#     14 — Cohort integrity gate output (evidence/14-cohort-integrity-gate.json)
#     15 — H1 trigger produces failure gate output (evidence/15-...)
#     16 — H2 fix restores success gate output (evidence/16-...)
#     17 — Bounded falsification gate output (evidence/17-...)
#
# Required tools: python3 (3.8+ for typing; stdlib only, no PyYAML needed)
# Required inputs:
#     evidence/01-13 (produced by trigger.sh + falsify.sh)
#
# Outputs:
#     evidence/14-cohort-integrity-gate.json          (rewritten every run)
#     evidence/15-h1-trigger-produces-failure-gate.json
#     evidence/16-h2-fix-restores-success-gate.json
#     evidence/17-bounded-falsification-gate.json
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/aca-secret-kv-ref-mi-network-path/evidence"
LAB_README_PATH="${SCRIPT_DIR}/README.md"
UTC_NOW="${UTC_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

export EVIDENCE_DIR REPO_RELATIVE_EVIDENCE_DIR LAB_README_PATH UTC_NOW

# -----------------------------------------------------------------------------
# Canonical file inventory — MUST match trigger.sh + falsify.sh output names.
# Any drift here is a hard failure at Gate 2/3/4.
# -----------------------------------------------------------------------------
declare -a CANONICAL_RAW_FILES=(
    "01-deployment-outputs.json"
    "02-h0-app-state-before.json"
    "03-h0-kv-secret-created.json"
    "04-h0-secret-set-outcome.json"
    "05-h0-app-state-after.json"
    "06-h1-firewall-rule-removed.json"
    "07-h1-secret-set-outcome.json"
    "08-h1-app-state.json"
    "09-h1-firewall-deny-log.json"
    "10-h2-firewall-rule-restored.json"
    "11-h2-secret-set-outcome.json"
    "12-h2-app-state.json"
    "13-h2-firewall-allow-log.json"
)

declare -a PHASE_B_GATE_OUTPUTS=(
    "14-cohort-integrity-gate.json"
    "15-h1-trigger-produces-failure-gate.json"
    "16-h2-fix-restores-success-gate.json"
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

# -----------------------------------------------------------------------------
# run_python_gate — wraps an inline Python check for a single prerequisite gate.
# Args: $1 = gate number (1-13), $2 = short description printed on pass.
# The inline Python block below is dispatched by GATE_NUMBER; each branch is a
# small, self-contained check that raises SystemExit(0) on pass / SystemExit(1)
# on fail. All schema knowledge lives in that inline block so the bash side
# stays a thin dispatcher.
# -----------------------------------------------------------------------------
run_python_gate() {
    local gate_number="$1"
    local detail="$2"
    local output
    if output="$(GATE_NUMBER="$gate_number" python3 <<'PY'
import json
import os
from pathlib import Path

gate_number = int(os.environ['GATE_NUMBER'])
evidence_dir = Path(os.environ['EVIDENCE_DIR'])

RAW_FILES = [
    '01-deployment-outputs.json',
    '02-h0-app-state-before.json',
    '03-h0-kv-secret-created.json',
    '04-h0-secret-set-outcome.json',
    '05-h0-app-state-after.json',
    '06-h1-firewall-rule-removed.json',
    '07-h1-secret-set-outcome.json',
    '08-h1-app-state.json',
    '09-h1-firewall-deny-log.json',
    '10-h2-firewall-rule-restored.json',
    '11-h2-secret-set-outcome.json',
    '12-h2-app-state.json',
    '13-h2-firewall-allow-log.json',
]

def load_json(name: str):
    path = evidence_dir / name
    return json.loads(path.read_text(encoding='utf-8'))

if gate_number == 1:
    if evidence_dir.is_dir():
        print(f'evidence directory present at {evidence_dir}')
        raise SystemExit(0)
    print(f'evidence directory missing at {evidence_dir}')
    raise SystemExit(1)

if gate_number == 2:
    expected = RAW_FILES[0:5]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print('missing H0 cohort files: ' + ', '.join(missing))
        raise SystemExit(1)
    print('H0 raw files 01-05 present')
    raise SystemExit(0)

if gate_number == 3:
    expected = RAW_FILES[5:9]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print('missing H1 cohort files: ' + ', '.join(missing))
        raise SystemExit(1)
    print('H1 raw files 06-09 present')
    raise SystemExit(0)

if gate_number == 4:
    expected = RAW_FILES[9:13]
    missing = [name for name in expected if not (evidence_dir / name).is_file()]
    if missing:
        print('missing H2 cohort files: ' + ', '.join(missing))
        raise SystemExit(1)
    print('H2 raw files 10-13 present')
    raise SystemExit(0)

if gate_number == 5:
    try:
        payload = load_json(RAW_FILES[0])
    except Exception as exc:
        print(f'01 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    required = [
        'lab_name', 'resource_group', 'location', 'app_name',
        'environment_name', 'key_vault_name', 'key_vault_uri',
        'app_principal_id', 'firewall_name', 'firewall_policy_name',
        'firewall_public_ip', 'log_analytics_name',
        'log_analytics_customer_id', 'entra_rule_collection_name',
        'entra_rule_name',
    ]
    missing = [key for key in required if not payload.get(key)]
    if missing:
        print('01 missing anchors: ' + ', '.join(missing))
        raise SystemExit(1)
    if payload['lab_name'] != 'aca-secret-kv-ref-mi-network-path':
        print(f"01 lab_name mismatch: {payload['lab_name']}")
        raise SystemExit(1)
    print('01 parses and carries all cohort anchors')
    raise SystemExit(0)

if gate_number == 6:
    try:
        payload = load_json(RAW_FILES[1])
    except Exception as exc:
        print(f'02 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    if payload.get('phase') != 'H0-before':
        print(f"02 phase mismatch: {payload.get('phase')}")
        raise SystemExit(1)
    for key in ('app_name', 'latest_ready_revision_name', 'ingress_fqdn'):
        value = payload.get(key)
        if not value or value == 'null':
            print(f'02 missing/null field: {key}')
            raise SystemExit(1)
    print('02 parses and captures the H0-before surface')
    raise SystemExit(0)

if gate_number == 7:
    try:
        payload = load_json(RAW_FILES[2])
    except Exception as exc:
        print(f'03 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    if payload.get('phase') != 'H0':
        print(f"03 phase mismatch: {payload.get('phase')}")
        raise SystemExit(1)
    url = payload.get('secret_url_versionless', '')
    if not url or 'secrets/' not in url:
        print(f'03 secret_url_versionless missing or malformed: {url}')
        raise SystemExit(1)
    print('03 parses and captures the versionless KV URL used by H0')
    raise SystemExit(0)

if gate_number == 8:
    try:
        payload = load_json(RAW_FILES[3])
    except Exception as exc:
        print(f'04 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    if payload.get('phase') != 'H0':
        print(f"04 phase mismatch: {payload.get('phase')}")
        raise SystemExit(1)
    exit_code = payload.get('exit_code')
    if exit_code != 0:
        print(f'04 H0 baseline did NOT succeed (exit={exit_code}). Lab requires H0 SUCCESS.')
        raise SystemExit(1)
    if payload.get('outcome') != 'success':
        print(f"04 outcome inconsistent with exit=0: outcome={payload.get('outcome')}")
        raise SystemExit(1)
    print('04 confirms H0 baseline succeeded (exit_code=0)')
    raise SystemExit(0)

if gate_number == 9:
    try:
        payload = load_json(RAW_FILES[4])
    except Exception as exc:
        print(f'05 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    if payload.get('phase') != 'H0-after':
        print(f"05 phase mismatch: {payload.get('phase')}")
        raise SystemExit(1)
    if payload.get('latest_revision_unchanged_vs_before') is not True:
        print('05 revision CHANGED after H0 secret set (secret updates should not create revisions)')
        raise SystemExit(1)
    if int(payload.get('baseline_secret_present_in_config_count') or 0) < 1:
        print("05 baseline secret 'kvref-h0' NOT present in configuration.secrets after H0 success")
        raise SystemExit(1)
    print('05 confirms H0 silence gate: revision unchanged + baseline secret present')
    raise SystemExit(0)

if gate_number == 10:
    try:
        payload = load_json(RAW_FILES[5])
    except Exception as exc:
        print(f'06 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    if payload.get('phase') != 'H1':
        print(f"06 phase mismatch: {payload.get('phase')}")
        raise SystemExit(1)
    if payload.get('controlled_variable_absent_after_remove') is not True:
        print('06 controlled variable flag not True after remove call')
        raise SystemExit(1)
    if int(payload.get('remove_exit_code') or 1) != 0:
        print(f"06 rule-collection-group remove exit_code={payload.get('remove_exit_code')}")
        raise SystemExit(1)
    rule_name = payload.get('rule_collection_name')
    post_list = payload.get('post_remove_collections_in_group') or []
    if rule_name and rule_name in post_list:
        print(f"06 rule collection '{rule_name}' STILL present in group after remove")
        raise SystemExit(1)
    print(f"06 confirms rule collection '{rule_name}' removed from firewall policy")
    raise SystemExit(0)

if gate_number == 11:
    try:
        payload = load_json(RAW_FILES[6])
    except Exception as exc:
        print(f'07 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    if payload.get('phase') != 'H1':
        print(f"07 phase mismatch: {payload.get('phase')}")
        raise SystemExit(1)
    exit_code = payload.get('exit_code')
    if not isinstance(exit_code, int) or exit_code == 0:
        print(f'07 H1 secret set did NOT fail as expected (exit={exit_code})')
        raise SystemExit(1)
    if payload.get('outcome') != 'failure':
        print(f"07 outcome inconsistent with exit != 0: outcome={payload.get('outcome')}")
        raise SystemExit(1)
    if not payload.get('h1_start_iso'):
        print('07 h1_start_iso not captured (needed for KQL window)')
        raise SystemExit(1)
    print(f'07 confirms H1 secret set failed as expected (exit_code={exit_code})')
    raise SystemExit(0)

if gate_number == 12:
    try:
        payload = load_json(RAW_FILES[7])
    except Exception as exc:
        print(f'08 parse failure: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    checks = {
        'revision_unchanged': payload.get('latest_revision_unchanged_vs_baseline') is True,
        'ingress_200': payload.get('ingress_probe_http_code') == '200',
        'secret_absent_as_expected': payload.get('secret_presence_expectation_met') is True and payload.get('observed_secret_present') is False,
    }
    failed = [name for name, ok in checks.items() if not ok]
    if failed:
        print('08 silence gate FAILED: ' + ', '.join(failed))
        print(f"    observed: rev_unchanged={payload.get('latest_revision_unchanged_vs_baseline')}, http={payload.get('ingress_probe_http_code')}, secret_present={payload.get('observed_secret_present')}, expected_present={payload.get('expected_secret_present')}")
        raise SystemExit(1)
    print('08 silence gate passed: revision unchanged + ingress 200 + kvref-h1 absent')
    raise SystemExit(0)

if gate_number == 13:
    problems = []
    try:
        payload_09 = load_json(RAW_FILES[8])
        payload_10 = load_json(RAW_FILES[9])
        payload_11 = load_json(RAW_FILES[10])
        payload_12 = load_json(RAW_FILES[11])
        payload_13 = load_json(RAW_FILES[12])
    except Exception as exc:
        print(f'13 parse failure across 09-13: {type(exc).__name__}: {exc}')
        raise SystemExit(1)
    if int(payload_09.get('final_deny_row_count') or 0) < 1:
        problems.append('09 final_deny_row_count < 1 (no firewall Deny row for Entra authority in H1 window)')
    if payload_10.get('controlled_variable_present_after_restore') is not True:
        problems.append('10 controlled variable flag not True after restore')
    rule_name = payload_10.get('rule_collection_name')
    if rule_name and rule_name not in (payload_10.get('post_restore_collections_in_group') or []):
        problems.append(f"10 rule collection '{rule_name}' NOT present after restore")
    restored_fqdns = payload_10.get('restored_target_fqdns') or []
    if 'login.microsoftonline.com' not in restored_fqdns or 'login.microsoft.com' not in restored_fqdns:
        problems.append(f'10 restored FQDNs missing one of login.microsoftonline.com / login.microsoft.com: {restored_fqdns}')
    if payload_11.get('exit_code') != 0:
        problems.append(f"11 H2 secret set exit_code != 0: {payload_11.get('exit_code')}")
    if payload_11.get('outcome') != 'success':
        problems.append(f"11 H2 outcome inconsistent with exit=0: {payload_11.get('outcome')}")
    if payload_12.get('observed_secret_present') is not True:
        problems.append('12 kvref-h2 secret NOT present after H2 success')
    if payload_12.get('ingress_probe_http_code') != '200':
        problems.append(f"12 ingress HTTP != 200 after H2: {payload_12.get('ingress_probe_http_code')}")
    if int(payload_13.get('final_allow_row_count') or 0) < 1:
        problems.append('13 final_allow_row_count < 1 (no firewall Allow row for Entra authority in H2 window)')
    if problems:
        print('13 schema/expectation failures across 09-13:')
        for msg in problems:
            print(f'    - {msg}')
        raise SystemExit(1)
    print('13 confirms H1 firewall Deny + H2 restore + H2 success + H2 Allow schema')
    raise SystemExit(0)

print(f'unknown gate number: {gate_number}')
raise SystemExit(1)
PY
)"; then
        pass_gate "$gate_number" "$output"
    else
        fail_gate "$gate_number" "$output"
    fi
}

# -----------------------------------------------------------------------------
# Run gates 1-13 sequentially. Each is a self-contained prerequisite check.
# -----------------------------------------------------------------------------
run_python_gate 1  "evidence directory present"
run_python_gate 2  "H0 raw files 01-05 present"
run_python_gate 3  "H1 raw files 06-09 present"
run_python_gate 4  "H2 raw files 10-13 present"
run_python_gate 5  "01 anchors valid"
run_python_gate 6  "02 H0-before surface valid"
run_python_gate 7  "03 KV secret URL valid"
run_python_gate 8  "04 H0 baseline succeeded"
run_python_gate 9  "05 H0 silence gate valid"
run_python_gate 10 "06 firewall rule removed"
run_python_gate 11 "07 H1 secret set failed"
run_python_gate 12 "08 H1 silence gate valid"
run_python_gate 13 "09-13 H1 log + H2 cohort valid"

# =============================================================================
# Phase B — Gates 14-17 write the four derived JSON outputs.
# Gates 14-17 depend on the same parsed evidence and cross-file predicates
# (revision-silence invariant, firewall rule presence, HTTP surface). Computing
# them in one Python block guarantees identical view of the cohort across all
# four JSON outputs and identical UTC capture timestamp.
# =============================================================================
if PHASE_B_OUTPUT="$(python3 <<'PY'
import json
import os
from pathlib import Path

evidence_dir = Path(os.environ['EVIDENCE_DIR'])
repo_rel_dir = os.environ['REPO_RELATIVE_EVIDENCE_DIR']
utc_now = os.environ['UTC_NOW']

def repo_rel(name: str) -> str:
    return f"{repo_rel_dir}/{name}"

def load(name: str):
    return json.loads((evidence_dir / name).read_text(encoding='utf-8'))

# -----------------------------------------------------------------------------
# Load every raw file once.
# -----------------------------------------------------------------------------
d01 = load('01-deployment-outputs.json')                       # Bicep outputs
d02 = load('02-h0-app-state-before.json')                      # H0 pre-baseline
d03 = load('03-h0-kv-secret-created.json')                     # KV secret create
d04 = load('04-h0-secret-set-outcome.json')                    # H0 outcome (must be success)
d05 = load('05-h0-app-state-after.json')                       # H0 post-baseline
d06 = load('06-h1-firewall-rule-removed.json')                 # H1 rule remove receipt
d07 = load('07-h1-secret-set-outcome.json')                    # H1 outcome (must be failure)
d08 = load('08-h1-app-state.json')                             # H1 silence gate
d09 = load('09-h1-firewall-deny-log.json')                     # H1 firewall Deny row(s)
d10 = load('10-h2-firewall-rule-restored.json')                # H2 rule restore receipt
d11 = load('11-h2-secret-set-outcome.json')                    # H2 outcome (must be success)
d12 = load('12-h2-app-state.json')                             # H2 post-restore
d13 = load('13-h2-firewall-allow-log.json')                    # H2 firewall Allow row(s)

# -----------------------------------------------------------------------------
# Cohort-wide anchors read from 01.
# -----------------------------------------------------------------------------
app_name = d01['app_name']
resource_group = d01['resource_group']
location = d01['location']
kv_name = d01['key_vault_name']
firewall_policy_name = d01['firewall_policy_name']
firewall_public_ip = d01['firewall_public_ip']
log_analytics_customer_id = d01['log_analytics_customer_id']
entra_rule_collection_name = d01['entra_rule_collection_name']
entra_rule_name = d01['entra_rule_name']

# -----------------------------------------------------------------------------
# Baseline revision anchor from 02 — the silence-invariant reference.
# -----------------------------------------------------------------------------
baseline_revision_name = d02['latest_ready_revision_name']

# =============================================================================
# GATE 14 — Cohort integrity
# =============================================================================
timestamps_ordered_pairs = [
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
timestamp_violations = []
for left_id, left_ts, right_id, right_ts in timestamps_ordered_pairs:
    if not left_ts or not right_ts or left_ts > right_ts:
        timestamp_violations.append(f"{left_id}({left_ts}) > {right_id}({right_ts})")
subgate_14a_pass = len(timestamp_violations) == 0

# Same app_name across all files that reference one
app_name_refs = {
    '01': d01.get('app_name'),
    '02': d02.get('app_name'),
    '05': d05.get('app_name'),
    '08': d08.get('app_name'),
    '12': d12.get('app_name'),
}
app_name_mismatches = {k: v for k, v in app_name_refs.items() if v and v != app_name}
subgate_14b_pass = len(app_name_mismatches) == 0

# Same firewall_policy_name across 01, 06, 10
fw_policy_refs = {
    '01': d01.get('firewall_policy_name'),
    '06': d06.get('firewall_policy_name'),
    '10': d10.get('firewall_policy_name'),
}
fw_policy_mismatches = {k: v for k, v in fw_policy_refs.items() if v and v != firewall_policy_name}
subgate_14c_pass = len(fw_policy_mismatches) == 0

# Same log_analytics_customer_id across 01, 09, 13
law_refs = {
    '01': d01.get('log_analytics_customer_id'),
    '09': d09.get('log_analytics_customer_id'),
    '13': d13.get('log_analytics_customer_id'),
}
law_mismatches = {k: v for k, v in law_refs.items() if v and v != log_analytics_customer_id}
subgate_14d_pass = len(law_mismatches) == 0

# H1 window strictly precedes H2 window
h1_start = d07.get('h1_start_iso')
h2_start = d11.get('h2_start_iso')
subgate_14e_pass = bool(h1_start) and bool(h2_start) and h1_start < h2_start

# Same rule_collection_name across 06 and 10
rc_pre = d06.get('rule_collection_name')
rc_post = d10.get('rule_collection_name')
subgate_14f_pass = bool(rc_pre) and rc_pre == rc_post == entra_rule_collection_name

# Baseline revision is stable across H0-after / H1 / H2 snapshots
rev_baseline = d02.get('latest_ready_revision_name')
rev_h0_after = d05.get('latest_ready_revision_name')
rev_h1 = d08.get('latest_ready_revision_name')
rev_h2 = d12.get('latest_ready_revision_name')
subgate_14g_pass = (
    bool(rev_baseline)
    and rev_baseline == rev_h0_after == rev_h1 == rev_h2
)

gate_14_all_subgates_pass = all([
    subgate_14a_pass, subgate_14b_pass, subgate_14c_pass,
    subgate_14d_pass, subgate_14e_pass, subgate_14f_pass,
    subgate_14g_pass,
])

gate14 = {
    'claim': (
        f"The evidence cohort for the aca-secret-kv-ref-mi-network-path lab on "
        f"{app_name} in {resource_group} ({location}) is internally consistent: "
        f"all 13 raw files present and parseable, timestamps monotonically ordered "
        f"across H0/H1/H2, and every cross-file anchor (app_name, firewall policy, "
        f"Log Analytics workspace, rule collection name, and baseline revision) "
        f"agrees. The baseline revision '{baseline_revision_name}' is the same in "
        f"the H0-after, H1, and H2 snapshots, which is the silence invariant this "
        f"lab depends on: secret updates must not create new revisions."
    ),
    'claim_level': 'Observed',
    'gate_classification': 'Cohort integrity gate: verifies raw file presence, parseability, temporal ordering, cross-file anchor consistency, and revision-silence invariant.',
    'hypothesis': 'H0_cohort_integrity',
    'path_used': 'single',
    'predicate_inputs': {f'file_{i:02d}': repo_rel(name) for i, name in enumerate([
        '01-deployment-outputs.json', '02-h0-app-state-before.json',
        '03-h0-kv-secret-created.json', '04-h0-secret-set-outcome.json',
        '05-h0-app-state-after.json', '06-h1-firewall-rule-removed.json',
        '07-h1-secret-set-outcome.json', '08-h1-app-state.json',
        '09-h1-firewall-deny-log.json', '10-h2-firewall-rule-restored.json',
        '11-h2-secret-set-outcome.json', '12-h2-app-state.json',
        '13-h2-firewall-allow-log.json',
    ], start=1)},
    'aca_secret_kv_ref_mi_network_path_h0_cohort_integrity_all_subgates_pass': gate_14_all_subgates_pass,
    'aca_secret_kv_ref_mi_network_path_h0_cohort_integrity_sub_gates': {
        'a_timestamps_monotonically_ordered_across_h0_h1_h2': subgate_14a_pass,
        'b_app_name_anchor_consistent_across_all_files': subgate_14b_pass,
        'c_firewall_policy_name_anchor_consistent': subgate_14c_pass,
        'd_log_analytics_workspace_anchor_consistent': subgate_14d_pass,
        'e_h1_window_strictly_precedes_h2_window': subgate_14e_pass,
        'f_rule_collection_name_anchor_consistent': subgate_14f_pass,
        'g_baseline_revision_silence_invariant_holds': subgate_14g_pass,
    },
    'scenario': 'aca_secret_kv_ref_mi_network_path',
    'sub_gates': [
        {
            'claim': 'Every consecutive pair of raw files has non-decreasing captured_at_utc timestamps.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(f) for f in [
                '01-deployment-outputs.json', '02-h0-app-state-before.json',
                '03-h0-kv-secret-created.json', '04-h0-secret-set-outcome.json',
                '05-h0-app-state-after.json', '06-h1-firewall-rule-removed.json',
                '07-h1-secret-set-outcome.json', '08-h1-app-state.json',
                '09-h1-firewall-deny-log.json', '10-h2-firewall-rule-restored.json',
                '11-h2-secret-set-outcome.json', '12-h2-app-state.json',
                '13-h2-firewall-allow-log.json',
            ]],
            'observed_values': {'violations': timestamp_violations},
            'predicate': 'For every adjacent pair (i, i+1) with i in 01..12, i.captured_at_utc <= (i+1).captured_at_utc.',
            'result': 'pass' if subgate_14a_pass else 'fail',
            'sub_gate': 'a_timestamps_monotonically_ordered_across_h0_h1_h2',
        },
        {
            'claim': f"All app_name references equal '{app_name}'.",
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(f) for f in [
                '01-deployment-outputs.json', '02-h0-app-state-before.json',
                '05-h0-app-state-after.json', '08-h1-app-state.json',
                '12-h2-app-state.json',
            ]],
            'observed_values': {'expected': app_name, 'refs': app_name_refs, 'mismatches': app_name_mismatches},
            'predicate': 'All non-null app_name fields equal 01.app_name.',
            'result': 'pass' if subgate_14b_pass else 'fail',
            'sub_gate': 'b_app_name_anchor_consistent_across_all_files',
        },
        {
            'claim': f"All firewall_policy_name references equal '{firewall_policy_name}'.",
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(f) for f in [
                '01-deployment-outputs.json', '06-h1-firewall-rule-removed.json',
                '10-h2-firewall-rule-restored.json',
            ]],
            'observed_values': {'expected': firewall_policy_name, 'refs': fw_policy_refs, 'mismatches': fw_policy_mismatches},
            'predicate': 'All non-null firewall_policy_name fields equal 01.firewall_policy_name.',
            'result': 'pass' if subgate_14c_pass else 'fail',
            'sub_gate': 'c_firewall_policy_name_anchor_consistent',
        },
        {
            'claim': f"All log_analytics_customer_id references equal '{log_analytics_customer_id}'.",
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(f) for f in [
                '01-deployment-outputs.json', '09-h1-firewall-deny-log.json',
                '13-h2-firewall-allow-log.json',
            ]],
            'observed_values': {'expected': log_analytics_customer_id, 'refs': law_refs, 'mismatches': law_mismatches},
            'predicate': 'All non-null log_analytics_customer_id fields equal 01.log_analytics_customer_id.',
            'result': 'pass' if subgate_14d_pass else 'fail',
            'sub_gate': 'd_log_analytics_workspace_anchor_consistent',
        },
        {
            'claim': 'The H1 KQL window opens strictly before the H2 KQL window.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(f) for f in [
                '07-h1-secret-set-outcome.json',
                '11-h2-secret-set-outcome.json',
            ]],
            'observed_values': {'h1_start_iso': h1_start, 'h2_start_iso': h2_start},
            'predicate': 'h1_start_iso and h2_start_iso are both present and h1_start_iso < h2_start_iso.',
            'result': 'pass' if subgate_14e_pass else 'fail',
            'sub_gate': 'e_h1_window_strictly_precedes_h2_window',
        },
        {
            'claim': (
                f"The controlled variable name '{entra_rule_collection_name}' is the "
                f"same in the remove receipt (06) and the restore receipt (10) and "
                f"matches the value declared by the Bicep deployment (01)."
            ),
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(f) for f in [
                '01-deployment-outputs.json',
                '06-h1-firewall-rule-removed.json',
                '10-h2-firewall-rule-restored.json',
            ]],
            'observed_values': {
                'expected': entra_rule_collection_name,
                'rule_collection_name_in_06': rc_pre,
                'rule_collection_name_in_10': rc_post,
            },
            'predicate': "06.rule_collection_name == 10.rule_collection_name == 01.entra_rule_collection_name.",
            'result': 'pass' if subgate_14f_pass else 'fail',
            'sub_gate': 'f_rule_collection_name_anchor_consistent',
        },
        {
            'claim': (
                f"The baseline revision '{baseline_revision_name}' is the "
                f"latestReadyRevisionName in the H0-after, H1, and H2 snapshots. "
                f"This is the silence invariant: secret updates never create new "
                f"revisions, so the app's data-plane surface must stay bound to "
                f"the same revision across all three windows."
            ),
            'claim_level': 'Observed',
            'evidence_files': [repo_rel(f) for f in [
                '02-h0-app-state-before.json', '05-h0-app-state-after.json',
                '08-h1-app-state.json', '12-h2-app-state.json',
            ]],
            'observed_values': {
                'baseline_revision_02': rev_baseline,
                'revision_h0_after_05': rev_h0_after,
                'revision_h1_08': rev_h1,
                'revision_h2_12': rev_h2,
            },
            'predicate': '02.latest_ready_revision_name == 05.latest_ready_revision_name == 08.latest_ready_revision_name == 12.latest_ready_revision_name.',
            'result': 'pass' if subgate_14g_pass else 'fail',
            'sub_gate': 'g_baseline_revision_silence_invariant_holds',
        },
    ],
    'thresholds': {
        'expected_raw_file_count': 13,
        'expected_gate_output_count': 4,
    },
    'utc_captured': utc_now,
}

# =============================================================================
# GATE 15 — H1 trigger produces failure
# =============================================================================
# a) Baseline validity: H0 succeeded with rule PRESENT
subgate_15a_pass = d04.get('exit_code') == 0 and d04.get('outcome') == 'success'

# b) Rule was actually removed (controlled variable ABSENT during H1)
rc_absent_in_group = (
    entra_rule_collection_name not in (d06.get('post_remove_collections_in_group') or [])
)
subgate_15b_pass = (
    d06.get('controlled_variable_absent_after_remove') is True
    and rc_absent_in_group
)

# c) H1 secret set failed
h1_exit = d07.get('exit_code')
subgate_15c_pass = isinstance(h1_exit, int) and h1_exit != 0 and d07.get('outcome') == 'failure'

# d) Silence gate: revision unchanged + ingress 200 + kvref-h1 absent
subgate_15d_pass = (
    d08.get('latest_revision_unchanged_vs_baseline') is True
    and d08.get('ingress_probe_http_code') == '200'
    and d08.get('secret_presence_expectation_met') is True
    and d08.get('observed_secret_present') is False
)

# e) Firewall Deny row observed for login.microsoftonline.com in H1 window
h1_deny_count = int(d09.get('final_deny_row_count') or 0)
subgate_15e_pass = h1_deny_count >= 1

gate_15_all_subgates_pass = all([
    subgate_15a_pass, subgate_15b_pass, subgate_15c_pass,
    subgate_15d_pass, subgate_15e_pass,
])

# Stderr substring signals from 07 (informational — NOT gated).
stderr_signals = d07.get('stderr_substring_matches') or {}

gate15 = {
    'claim': (
        f"Removing the Azure Firewall Application Rule collection "
        f"'{entra_rule_collection_name}' from policy '{firewall_policy_name}' "
        f"forced `az containerapp secret set --identity system --key-vault-url ...` "
        f"to fail on {app_name}. The failure is scoped to the control-plane KV "
        f"secret-reference validation: the baseline revision "
        f"'{baseline_revision_name}' stayed serving on ingress with HTTP 200, "
        f"the H1 secret 'kvref-h1' never landed in configuration.secrets, and "
        f"the firewall diagnostic log recorded a Deny row for the Entra authority "
        f"FQDN in the H1 window."
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H1 gate: confirms that removing the Entra Application Rule triggers the OIDC-discovery failure while leaving the data plane untouched.',
    'hypothesis': 'H1_trigger_produces_failure',
    'path_used': 'single',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_rule_removed': repo_rel('06-h1-firewall-rule-removed.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_app_state': repo_rel('08-h1-app-state.json'),
        'h1_firewall_deny_log': repo_rel('09-h1-firewall-deny-log.json'),
    },
    'aca_secret_kv_ref_mi_network_path_h1_trigger_produces_failure_all_subgates_pass': gate_15_all_subgates_pass,
    'aca_secret_kv_ref_mi_network_path_h1_trigger_produces_failure_sub_gates': {
        'a_baseline_h0_succeeded_when_entra_rule_was_present': subgate_15a_pass,
        'b_entra_rule_collection_absent_after_remove': subgate_15b_pass,
        'c_h1_secret_set_failed_nonzero_exit': subgate_15c_pass,
        'd_silence_gate_holds_revision_unchanged_ingress_200_secret_absent': subgate_15d_pass,
        'e_firewall_deny_row_observed_for_entra_authority_in_h1_window': subgate_15e_pass,
    },
    'scenario': 'aca_secret_kv_ref_mi_network_path',
    'sub_gates': [
        {
            'claim': 'The H0 baseline succeeded with the Entra Application Rule PRESENT, establishing non-vacuous baseline before H1.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('04-h0-secret-set-outcome.json')],
            'observed_values': {
                'exit_code': d04.get('exit_code'),
                'outcome': d04.get('outcome'),
                'command': d04.get('command'),
            },
            'predicate': '04.exit_code == 0 AND 04.outcome == "success".',
            'result': 'pass' if subgate_15a_pass else 'fail',
            'sub_gate': 'a_baseline_h0_succeeded_when_entra_rule_was_present',
        },
        {
            'claim': f"The rule collection '{entra_rule_collection_name}' is absent from the firewall policy after the H1 remove call.",
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-firewall-rule-removed.json')],
            'observed_values': {
                'expected_absent': entra_rule_collection_name,
                'post_remove_collections_in_group': d06.get('post_remove_collections_in_group') or [],
                'controlled_variable_absent_after_remove': d06.get('controlled_variable_absent_after_remove'),
                'remove_exit_code': d06.get('remove_exit_code'),
            },
            'predicate': '06.controlled_variable_absent_after_remove == True AND entra_rule_collection_name NOT IN 06.post_remove_collections_in_group.',
            'result': 'pass' if subgate_15b_pass else 'fail',
            'sub_gate': 'b_entra_rule_collection_absent_after_remove',
        },
        {
            'claim': "The H1 `az containerapp secret set` call failed with a non-zero exit code.",
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('07-h1-secret-set-outcome.json')],
            'observed_values': {
                'exit_code': d07.get('exit_code'),
                'outcome': d07.get('outcome'),
                'h1_start_iso': h1_start,
                'stderr_substring_matches_informational': stderr_signals,
            },
            'predicate': '07.exit_code != 0 AND 07.outcome == "failure".',
            'result': 'pass' if subgate_15c_pass else 'fail',
            'sub_gate': 'c_h1_secret_set_failed_nonzero_exit',
        },
        {
            'claim': (
                f"During H1, the baseline revision '{baseline_revision_name}' kept "
                f"the latestReadyRevisionName slot unchanged, the ingress probe "
                f"returned HTTP 200, and the H1 secret name was NOT present in "
                f"configuration.secrets. Together these three observations prove "
                f"the H1 failure was scoped to the control-plane KV secret-reference "
                f"validation and never disrupted the running data plane."
            ),
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('08-h1-app-state.json')],
            'observed_values': {
                'baseline_revision': baseline_revision_name,
                'revision_after_h1_attempt': d08.get('latest_ready_revision_name'),
                'latest_revision_unchanged_vs_baseline': d08.get('latest_revision_unchanged_vs_baseline'),
                'ingress_probe_http_code': d08.get('ingress_probe_http_code'),
                'expected_secret_name': d08.get('expected_secret_name'),
                'expected_secret_present': d08.get('expected_secret_present'),
                'observed_secret_present': d08.get('observed_secret_present'),
                'secret_presence_expectation_met': d08.get('secret_presence_expectation_met'),
            },
            'predicate': (
                '08.latest_revision_unchanged_vs_baseline == True '
                'AND 08.ingress_probe_http_code == "200" '
                'AND 08.secret_presence_expectation_met == True '
                'AND 08.observed_secret_present == False.'
            ),
            'result': 'pass' if subgate_15d_pass else 'fail',
            'sub_gate': 'd_silence_gate_holds_revision_unchanged_ingress_200_secret_absent',
        },
        {
            'claim': (
                f"The Azure Firewall diagnostic log recorded at least one Deny row "
                f"for the Entra authority FQDN (login.microsoftonline.com or "
                f"login.microsoft.com) during the H1 window (since {h1_start}). "
                f"This is the smoking gun proving the control-plane OIDC discovery "
                f"call was denied by the firewall — not by DNS, not by NSG, not by "
                f"a KV RBAC failure."
            ),
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('09-h1-firewall-deny-log.json')],
            'observed_values': {
                'final_deny_row_count': h1_deny_count,
                'denied_fqdn_primary': d09.get('denied_fqdn_primary'),
                'denied_fqdn_secondary': d09.get('denied_fqdn_secondary'),
                'attempts': d09.get('attempts') or [],
                'first_deny_row_preview': ((d09.get('deny_rows') or {}).get('tables', [{}])[0].get('rows', [])[:1] if isinstance(d09.get('deny_rows'), dict) else (d09.get('deny_rows') or [])[:1]),
            },
            'predicate': '09.final_deny_row_count >= 1.',
            'result': 'pass' if subgate_15e_pass else 'fail',
            'sub_gate': 'e_firewall_deny_row_observed_for_entra_authority_in_h1_window',
        },
    ],
    'thresholds': {
        'h1_deny_row_expected_min': 1,
        'h1_exit_code_expected_nonzero': True,
        'h0_exit_code_expected': 0,
    },
    'utc_captured': utc_now,
}

# =============================================================================
# GATE 16 — H2 fix restores success
# =============================================================================
# a) Rule was actually restored with the correct FQDNs
rc_present_in_group = (
    entra_rule_collection_name in (d10.get('post_restore_collections_in_group') or [])
)
restored_fqdns = d10.get('restored_target_fqdns') or []
subgate_16a_pass = (
    d10.get('controlled_variable_present_after_restore') is True
    and rc_present_in_group
    and 'login.microsoftonline.com' in restored_fqdns
    and 'login.microsoft.com' in restored_fqdns
)

# b) H2 secret set succeeded
subgate_16b_pass = d11.get('exit_code') == 0 and d11.get('outcome') == 'success'

# c) Recovery state: kvref-h2 present, ingress still 200
subgate_16c_pass = (
    d12.get('observed_secret_present') is True
    and d12.get('secret_presence_expectation_met') is True
    and d12.get('ingress_probe_http_code') == '200'
)

# d) Firewall Allow row observed for login.microsoftonline.com in H2 window
h2_allow_count = int(d13.get('final_allow_row_count') or 0)
subgate_16d_pass = h2_allow_count >= 1

gate_16_all_subgates_pass = all([
    subgate_16a_pass, subgate_16b_pass, subgate_16c_pass, subgate_16d_pass,
])

gate16 = {
    'claim': (
        f"Restoring the Azure Firewall Application Rule collection "
        f"'{entra_rule_collection_name}' with target FQDNs "
        f"login.microsoftonline.com and login.microsoft.com allowed "
        f"`az containerapp secret set --identity system --key-vault-url ...` "
        f"to succeed again on {app_name}. The recovery secret 'kvref-h2' is "
        f"present in configuration.secrets, ingress still returns HTTP 200 on "
        f"the baseline revision '{baseline_revision_name}', and the firewall "
        f"diagnostic log recorded an Allow row for the Entra authority FQDN "
        f"in the H2 window."
    ),
    'claim_level': 'Observed',
    'gate_classification': 'H2 gate: confirms that restoring the Entra Application Rule collection recovers `az containerapp secret set` without changing any other trigger field.',
    'hypothesis': 'H2_fix_restores_success',
    'path_used': 'single',
    'predicate_inputs': {
        'h2_rule_restored': repo_rel('10-h2-firewall-rule-restored.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_firewall_allow_log': repo_rel('13-h2-firewall-allow-log.json'),
    },
    'aca_secret_kv_ref_mi_network_path_h2_fix_restores_success_all_subgates_pass': gate_16_all_subgates_pass,
    'aca_secret_kv_ref_mi_network_path_h2_fix_restores_success_sub_gates': {
        'a_entra_rule_collection_restored_with_both_fqdns': subgate_16a_pass,
        'b_h2_secret_set_succeeded_exit_zero': subgate_16b_pass,
        'c_h2_recovery_secret_present_and_ingress_200': subgate_16c_pass,
        'd_firewall_allow_row_observed_for_entra_authority_in_h2_window': subgate_16d_pass,
    },
    'scenario': 'aca_secret_kv_ref_mi_network_path',
    'sub_gates': [
        {
            'claim': (
                f"The rule collection '{entra_rule_collection_name}' is present "
                f"in the firewall policy after the H2 restore call, and its target "
                f"FQDNs include BOTH login.microsoftonline.com and "
                f"login.microsoft.com in a single Application Rule (one atomic "
                f"remove restores the exact controlled variable)."
            ),
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('10-h2-firewall-rule-restored.json')],
            'observed_values': {
                'expected_present': entra_rule_collection_name,
                'post_restore_collections_in_group': d10.get('post_restore_collections_in_group') or [],
                'controlled_variable_present_after_restore': d10.get('controlled_variable_present_after_restore'),
                'restored_target_fqdns': restored_fqdns,
                'restore_exit_code': d10.get('restore_exit_code'),
            },
            'predicate': (
                '10.controlled_variable_present_after_restore == True '
                'AND entra_rule_collection_name IN 10.post_restore_collections_in_group '
                'AND "login.microsoftonline.com" IN 10.restored_target_fqdns '
                'AND "login.microsoft.com" IN 10.restored_target_fqdns.'
            ),
            'result': 'pass' if subgate_16a_pass else 'fail',
            'sub_gate': 'a_entra_rule_collection_restored_with_both_fqdns',
        },
        {
            'claim': "The H2 `az containerapp secret set` call succeeded with exit code 0.",
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('11-h2-secret-set-outcome.json')],
            'observed_values': {
                'exit_code': d11.get('exit_code'),
                'outcome': d11.get('outcome'),
                'h2_start_iso': h2_start,
            },
            'predicate': '11.exit_code == 0 AND 11.outcome == "success".',
            'result': 'pass' if subgate_16b_pass else 'fail',
            'sub_gate': 'b_h2_secret_set_succeeded_exit_zero',
        },
        {
            'claim': (
                f"After H2, the recovery secret 'kvref-h2' is present in "
                f"configuration.secrets and the ingress probe still returns "
                f"HTTP 200 on the baseline revision '{baseline_revision_name}'. "
                f"The data plane was never disrupted across H0/H1/H2."
            ),
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('12-h2-app-state.json')],
            'observed_values': {
                'baseline_revision': baseline_revision_name,
                'revision_after_h2_success': d12.get('latest_ready_revision_name'),
                'latest_revision_unchanged_vs_baseline': d12.get('latest_revision_unchanged_vs_baseline'),
                'ingress_probe_http_code': d12.get('ingress_probe_http_code'),
                'expected_secret_name': d12.get('expected_secret_name'),
                'expected_secret_present': d12.get('expected_secret_present'),
                'observed_secret_present': d12.get('observed_secret_present'),
                'secret_presence_expectation_met': d12.get('secret_presence_expectation_met'),
            },
            'predicate': (
                '12.observed_secret_present == True '
                'AND 12.secret_presence_expectation_met == True '
                'AND 12.ingress_probe_http_code == "200".'
            ),
            'result': 'pass' if subgate_16c_pass else 'fail',
            'sub_gate': 'c_h2_recovery_secret_present_and_ingress_200',
        },
        {
            'claim': (
                f"The Azure Firewall diagnostic log recorded at least one Allow row "
                f"for the Entra authority FQDN (login.microsoftonline.com or "
                f"login.microsoft.com) during the H2 window (since {h2_start}). "
                f"This is the recovery smoking gun: the OIDC discovery call now "
                f"traverses the restored Application Rule."
            ),
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('13-h2-firewall-allow-log.json')],
            'observed_values': {
                'final_allow_row_count': h2_allow_count,
                'allowed_fqdn_primary': d13.get('allowed_fqdn_primary'),
                'allowed_fqdn_secondary': d13.get('allowed_fqdn_secondary'),
                'attempts': d13.get('attempts') or [],
                'first_allow_row_preview': ((d13.get('allow_rows') or {}).get('tables', [{}])[0].get('rows', [])[:1] if isinstance(d13.get('allow_rows'), dict) else (d13.get('allow_rows') or [])[:1]),
            },
            'predicate': '13.final_allow_row_count >= 1.',
            'result': 'pass' if subgate_16d_pass else 'fail',
            'sub_gate': 'd_firewall_allow_row_observed_for_entra_authority_in_h2_window',
        },
    ],
    'thresholds': {
        'h2_allow_row_expected_min': 1,
        'h2_exit_code_expected': 0,
        'expected_restored_fqdns': ['login.microsoftonline.com', 'login.microsoft.com'],
    },
    'utc_captured': utc_now,
}

# =============================================================================
# GATE 17 — Bounded falsification
# =============================================================================
# a) Non-vacuous baseline: H0 succeeded when rule PRESENT
subgate_17a_pass = subgate_15a_pass

# b) Trigger-absence: H1 failed AND firewall recorded Deny (rule ABSENT)
subgate_17b_pass = subgate_15c_pass and subgate_15e_pass

# c) Recovery-presence: H2 succeeded AND firewall recorded Allow (rule RESTORED)
subgate_17c_pass = subgate_16b_pass and subgate_16d_pass

# d) Silence invariant: same revision across H0/H1/H2
subgate_17d_pass = subgate_14g_pass

# e) Only the documented controlled variable changed across H1 and H2
held_constant_checks = {
    'app_name_same': app_name_refs.get('08') == app_name_refs.get('12') == app_name,
    'firewall_policy_same': d06.get('firewall_policy_name') == d10.get('firewall_policy_name') == firewall_policy_name,
    'rule_collection_name_same': d06.get('rule_collection_name') == d10.get('rule_collection_name') == entra_rule_collection_name,
    'log_analytics_workspace_same': d09.get('log_analytics_customer_id') == d13.get('log_analytics_customer_id') == log_analytics_customer_id,
    'baseline_revision_same': d08.get('latest_ready_revision_name') == d12.get('latest_ready_revision_name') == baseline_revision_name,
}
subgate_17e_pass = all(held_constant_checks.values())

gate_17_all_subgates_pass = all([
    subgate_17a_pass, subgate_17b_pass, subgate_17c_pass,
    subgate_17d_pass, subgate_17e_pass,
])

# Explicit claim ceiling — what this pack does NOT prove.
# Each entry is a piece of behavior that IS interesting to the customer
# scenario but that this single-cohort evidence pack cannot defend. Listing
# them here bounds the claim so downstream readers do not over-generalize.
DOCUMENTED_EXPLICIT_DROPS = [
    {
        'id': 'stderr_substring_wording',
        'note': (
            'The pack confirms that H1 exit_code != 0 and that the firewall '
            'denied the Entra FQDN, but does not gate on the exact stderr '
            'wording ("Failed to update secrets", "Unable to get value using '
            'Managed identity", "Get https://login.microsoftonline.com/... '
            'EOF"). CLI wrapping changes those strings between versions.'
        ),
    },
    {
        'id': 'firewall_log_ingestion_latency_seconds',
        'note': (
            'The pack proves a Deny row appears within 10 minutes of the H1 '
            'attempt and an Allow row appears within 10 minutes of the H2 '
            'attempt, but does not gate on the exact ingestion latency for '
            'Azure Firewall Basic diagnostic settings.'
        ),
    },
    {
        'id': 'aca_control_plane_retry_schedule',
        'note': (
            'The pack proves H1 fails and H2 succeeds, but does not gate on '
            'how many times the ACA control plane retried OIDC discovery '
            'before surfacing the error, nor on the specific retry backoff.'
        ),
    },
    {
        'id': 'aca_control_plane_component_identity',
        'note': (
            'The pack proves the failing call went to login.microsoftonline.com '
            'from the customer subnet CIDR, but does not name the specific '
            'internal ACA control-plane component that made the call.'
        ),
    },
    {
        'id': 'oidc_discovery_response_body_shape',
        'note': (
            'The pack proves the request was DENIED by the firewall, but does '
            'not capture the specific HTTP response body (or the absence of '
            'one) that login.microsoftonline.com would have returned had the '
            'firewall allowed the call through.'
        ),
    },
    {
        'id': 'token_caching_behavior',
        'note': (
            'The pack proves H2 succeeds after H1 fails, but does not gate on '
            'whether the H2 success used a freshly discovered OIDC document '
            'or a cached one from a pre-H1 attempt. Distinct KV secret names '
            'per phase (kvref-h0 / kvref-h1 / kvref-h2) sidestep this by '
            'making the presence/absence check unambiguous.'
        ),
    },
    {
        'id': 'firewall_sku_generality',
        'note': (
            'The pack was captured on Azure Firewall Basic. Standard and '
            'Premium SKUs offer additional features (Threat Intel, TLS '
            'inspection) not exercised here. The controlled variable '
            'behavior is expected to generalize, but this pack does not '
            'prove it.'
        ),
    },
    {
        'id': 'region_generality',
        'note': (
            'The pack was captured in one region. Cross-region behavior '
            '(e.g. different Entra token endpoints, different firewall '
            'ingestion pipelines) is not covered.'
        ),
    },
]

gate17 = {
    'claim': (
        f"This evidence pack falsifies the aca-secret-kv-ref-mi-network-path "
        f"hypothesis within a bounded scope on {app_name} in {resource_group} "
        f"({location}). Non-vacuous proof requires four observations together: "
        f"(a) baseline-presence — H0 succeeded when the Entra Application Rule "
        f"was PRESENT; (b) trigger-absence — removing the rule caused "
        f"`az containerapp secret set --identity system --key-vault-url ...` to "
        f"fail with exit code != 0 AND the firewall recorded a Deny row for "
        f"the Entra authority FQDN in the H1 window; (c) recovery-presence — "
        f"restoring the rule with the same two FQDNs allowed the same command "
        f"to succeed AND the firewall recorded an Allow row in the H2 window; "
        f"(d) silence invariant — the baseline revision "
        f"'{baseline_revision_name}' stayed serving on ingress with HTTP 200 "
        f"throughout, proving the control-plane failure never touched the data "
        f"plane. The bounded claim is only that the presence/absence of the "
        f"'{entra_rule_collection_name}' rule collection is the mechanically "
        f"observable trigger field for this cohort."
    ),
    'claim_level': 'Observed',
    'cohort_binding_note': {
        'claim_ceiling': (
            f"The bounded claim is that the presence/absence of the "
            f"'{entra_rule_collection_name}' Azure Firewall Application Rule "
            f"collection (targeting login.microsoftonline.com and "
            f"login.microsoft.com from the ACA subnet CIDR) is the "
            f"mechanically observable trigger field controlling "
            f"`az containerapp secret set --identity system --key-vault-url ...` "
            f"success in this single koreacentral cohort. The pack does NOT "
            f"prove exact CLI stderr wording, exact firewall log ingestion "
            f"latency, ACA control-plane retry cadence, ACA control-plane "
            f"component identity, OIDC response body shape, token caching "
            f"behavior, generalization across firewall SKUs, or generalization "
            f"across regions. Each explicit drop is enumerated below."
        ),
        'explicit_drops': DOCUMENTED_EXPLICIT_DROPS,
    },
    'gate_classification': 'Bounded falsification gate: isolates the Entra Application Rule collection as the single trigger field while explicitly listing what the pack cannot generalize to.',
    'hypothesis': 'H3_bounded_falsification',
    'path_used': 'bounded',
    'predicate_inputs': {
        'h0_outcome': repo_rel('04-h0-secret-set-outcome.json'),
        'h1_outcome': repo_rel('07-h1-secret-set-outcome.json'),
        'h1_app_state': repo_rel('08-h1-app-state.json'),
        'h1_firewall_deny_log': repo_rel('09-h1-firewall-deny-log.json'),
        'h2_rule_restored': repo_rel('10-h2-firewall-rule-restored.json'),
        'h2_outcome': repo_rel('11-h2-secret-set-outcome.json'),
        'h2_app_state': repo_rel('12-h2-app-state.json'),
        'h2_firewall_allow_log': repo_rel('13-h2-firewall-allow-log.json'),
    },
    'aca_secret_kv_ref_mi_network_path_h3_bounded_falsification_all_subgates_pass': gate_17_all_subgates_pass,
    'aca_secret_kv_ref_mi_network_path_h3_bounded_falsification_sub_gates': {
        'a_baseline_presence_h0_succeeded_with_rule_present': subgate_17a_pass,
        'b_trigger_absence_h1_failed_with_rule_absent_and_firewall_denied': subgate_17b_pass,
        'c_recovery_presence_h2_succeeded_with_rule_restored_and_firewall_allowed': subgate_17c_pass,
        'd_silence_invariant_holds_same_revision_across_h0_h1_h2': subgate_17d_pass,
        'e_only_the_documented_controlled_variable_changed': subgate_17e_pass,
    },
    'scenario': 'aca_secret_kv_ref_mi_network_path',
    'sub_gates': [
        {
            'claim': 'Non-vacuous baseline: H0 succeeded when the Entra Application Rule was PRESENT.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('04-h0-secret-set-outcome.json')],
            'observed_values': {'h0_exit_code': d04.get('exit_code'), 'h0_outcome': d04.get('outcome')},
            'predicate': '04.exit_code == 0 (aliased from Gate 15 sub-gate a).',
            'result': 'pass' if subgate_17a_pass else 'fail',
            'sub_gate': 'a_baseline_presence_h0_succeeded_with_rule_present',
        },
        {
            'claim': 'Trigger-absence: removing the rule caused secret set to fail AND the firewall recorded Deny.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('07-h1-secret-set-outcome.json'), repo_rel('09-h1-firewall-deny-log.json')],
            'observed_values': {
                'h1_exit_code': d07.get('exit_code'),
                'h1_final_deny_row_count': h1_deny_count,
            },
            'predicate': '07.exit_code != 0 AND 09.final_deny_row_count >= 1.',
            'result': 'pass' if subgate_17b_pass else 'fail',
            'sub_gate': 'b_trigger_absence_h1_failed_with_rule_absent_and_firewall_denied',
        },
        {
            'claim': 'Recovery-presence: restoring the rule caused secret set to succeed AND the firewall recorded Allow.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('11-h2-secret-set-outcome.json'), repo_rel('13-h2-firewall-allow-log.json')],
            'observed_values': {
                'h2_exit_code': d11.get('exit_code'),
                'h2_final_allow_row_count': h2_allow_count,
            },
            'predicate': '11.exit_code == 0 AND 13.final_allow_row_count >= 1.',
            'result': 'pass' if subgate_17c_pass else 'fail',
            'sub_gate': 'c_recovery_presence_h2_succeeded_with_rule_restored_and_firewall_allowed',
        },
        {
            'claim': (
                f"Silence invariant: the baseline revision "
                f"'{baseline_revision_name}' was the latestReadyRevisionName "
                f"across the H0-after, H1, and H2 snapshots. Secret updates "
                f"never create new revisions, so this invariant proves the "
                f"control-plane failure was scoped strictly to the KV "
                f"secret-reference validation path."
            ),
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('02-h0-app-state-before.json'), repo_rel('05-h0-app-state-after.json'), repo_rel('08-h1-app-state.json'), repo_rel('12-h2-app-state.json')],
            'observed_values': {
                'baseline_revision': baseline_revision_name,
                'revision_h0_after': rev_h0_after,
                'revision_h1': rev_h1,
                'revision_h2': rev_h2,
                'ingress_h1_http_code': d08.get('ingress_probe_http_code'),
                'ingress_h2_http_code': d12.get('ingress_probe_http_code'),
            },
            'predicate': '02.latest_ready_revision_name == 05.latest_ready_revision_name == 08.latest_ready_revision_name == 12.latest_ready_revision_name (aliased from Gate 14 sub-gate g).',
            'result': 'pass' if subgate_17d_pass else 'fail',
            'sub_gate': 'd_silence_invariant_holds_same_revision_across_h0_h1_h2',
        },
        {
            'claim': 'Every non-controlled anchor (app_name, firewall policy name, rule collection name, Log Analytics workspace, baseline revision) was held constant across H1 and H2. The only field that flipped between H1 and H2 is the presence/absence of the controlled rule collection.',
            'claim_level': 'Observed',
            'evidence_files': [repo_rel('06-h1-firewall-rule-removed.json'), repo_rel('08-h1-app-state.json'), repo_rel('10-h2-firewall-rule-restored.json'), repo_rel('12-h2-app-state.json')],
            'observed_values': {'held_constant_checks': held_constant_checks},
            'predicate': 'All entries in held_constant_checks are True.',
            'result': 'pass' if subgate_17e_pass else 'fail',
            'sub_gate': 'e_only_the_documented_controlled_variable_changed',
        },
    ],
    'thresholds': {
        'h0_exit_code_expected': 0,
        'h1_exit_code_expected_nonzero': True,
        'h1_deny_row_expected_min': 1,
        'h2_exit_code_expected': 0,
        'h2_allow_row_expected_min': 1,
    },
    'utc_captured': utc_now,
}

# -----------------------------------------------------------------------------
# Write all four gate JSONs deterministically, then evaluate PASS/FAIL.
# -----------------------------------------------------------------------------
gates = [
    (14, gate14, 'cohort integrity verified'),
    (15, gate15, 'H1 trigger produces failure verified'),
    (16, gate16, 'H2 fix restores success verified'),
    (17, gate17, 'bounded falsification verified'),
]

output_map = {
    14: evidence_dir / '14-cohort-integrity-gate.json',
    15: evidence_dir / '15-h1-trigger-produces-failure-gate.json',
    16: evidence_dir / '16-h2-fix-restores-success-gate.json',
    17: evidence_dir / '17-bounded-falsification-gate.json',
}

for gate_number, gate_data, _ in gates:
    output_map[gate_number].write_text(
        json.dumps(gate_data, indent=2) + '\n', encoding='utf-8'
    )

failures = []
for gate_number, gate_data, detail in gates:
    sub_gate_map = next(
        value for key, value in gate_data.items() if key.endswith('_sub_gates')
    )
    if not all(sub_gate_map.values()):
        failed = [key for key, value in sub_gate_map.items() if not value]
        failures.append((gate_number, detail, failed))

for gate_number, gate_data, detail in gates:
    sub_gate_map = next(
        value for key, value in gate_data.items() if key.endswith('_sub_gates')
    )
    if all(sub_gate_map.values()):
        print(f'[Gate {gate_number}/17] PASS {detail}')

if failures:
    for gate_number, detail, failed in failures:
        print(f"[Gate {gate_number}/17] FAIL {detail}; failed sub-gates: {', '.join(failed)}")
    raise SystemExit(1)
PY
)"; then
    printf '%s\n' "$PHASE_B_OUTPUT"
else
    printf '%s\n' "$PHASE_B_OUTPUT"
    exit 1
fi

echo ""
echo "=== verify.sh complete ==="
echo "All 17 gates PASSED."
echo "Wrote:"
for name in "${PHASE_B_GATE_OUTPUTS[@]}"; do
    echo "  evidence/$name"
done
