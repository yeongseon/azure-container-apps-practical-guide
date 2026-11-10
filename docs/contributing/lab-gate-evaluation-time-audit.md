---
description: Audit of offline lab verifiers that still label replay evaluation time as evidence capture time, pinned to a specific repository revision.
---
# Lab Gate Evaluation-Time Audit

This inventory is pinned to `origin/main` commit `de59e3e27aaa8c78714a23704f8f123d0830fd3d` on 2026-11-07. It classifies only top-level timestamps on derived gate JSON emitted by offline `verify.sh` replay; timestamps embedded in the committed raw evidence remain capture evidence and are not rename candidates.

## Audit Rule

- **Raw evidence time** belongs to the Azure or HTTP observation and stays unchanged in its source field, such as `TimeStamp`, `createdTime`, `lastModifiedAt`, an HTTP `Date` header, or a capture-script `utc_captured` value.
- **Derived gate time** belongs to the offline verifier invocation. A generated gate must call this `evaluated_at_utc`, and a clean replay must set it to the current invocation time.
- A verifier is affected when it emits top-level `utc_captured` into a derived gate, even when it pins that value to an already committed gate for byte-identical replay.

## Remaining Matrix at the Pinned SHA

The matrix lists every audited verifier with its current status; rows marked Fixed or Deferred are distinguished in the Status column, and the measured remaining counts are in the Batch F section. Seven verifier families have no committed derived gate JSON yet. Already converted work from #394, #410, #411, and #417 is excluded.

| Lab | Verifier and committed derived gates | Emitted field | Raw capture time vs generated evaluation time | Status | Owner |
|---|---|---|---|---|---|
| `aca-secret-kv-ref-mi-network-path` | `labs/aca-secret-kv-ref-mi-network-path/verify.sh`; no committed derived gates | `utc_captured` from `UTC_NOW` | Preserve timestamps in the verifier's declared raw inputs; generate `evaluated_at_utc` when gates are first committed. | Deferred; source-only defect | Unassigned / #409 |
| `aca-secret-kv-ref-mi-network-path-h4b` | `labs/aca-secret-kv-ref-mi-network-path-h4b/verify.sh`; no committed derived gates | `utc_captured` from `UTC_NOW` | Preserve timestamps in the verifier's declared raw inputs; generate `evaluated_at_utc` when gates are first committed. | Deferred; source-only defect | Unassigned / #409 |
| `aca-secret-kv-ref-mi-network-path-h4c` | `labs/aca-secret-kv-ref-mi-network-path-h4c/verify.sh`; no committed derived gates | `utc_captured` from `UTC_NOW` | Preserve timestamps in the verifier's declared raw inputs; generate `evaluated_at_utc` when gates are first committed. | Deferred; source-only defect | Unassigned / #409 |
| `aca-secret-kv-ref-mi-network-path-h4d` | `labs/aca-secret-kv-ref-mi-network-path-h4d/verify.sh`; no committed derived gates | `utc_captured` from `UTC_NOW` | Preserve timestamps in the verifier's declared raw inputs; generate `evaluated_at_utc` when gates are first committed. | Deferred; source-only defect | Unassigned / #409 |
| `aca-secret-kv-ref-mi-network-path-h4e` | `labs/aca-secret-kv-ref-mi-network-path-h4e/verify.sh`; no committed derived gates | `utc_captured` from `UTC_NOW` | Preserve timestamps in the verifier's declared raw inputs; generate `evaluated_at_utc` when gates are first committed. | Deferred; source-only defect | Unassigned / #409 |
| `aca-secret-kv-ref-mi-network-path-h4f` | `labs/aca-secret-kv-ref-mi-network-path-h4f/verify.sh`; no committed derived gates | `utc_captured` from `UTC_NOW` | Preserve timestamps in the verifier's declared raw inputs; generate `evaluated_at_utc` when gates are first committed. | Deferred; source-only defect | Unassigned / #409 |
| `aca-secret-kv-ref-mi-network-path-h4g` | `labs/aca-secret-kv-ref-mi-network-path-h4g/verify.sh`; no committed derived gates | `utc_captured` from `UTC_NOW` | Preserve timestamps in the verifier's declared raw inputs; generate `evaluated_at_utc` when gates are first committed. | Deferred; source-only defect | Unassigned / #409 |
| `acr-network-path-dns-forwarder-bypass` | `labs/acr-network-path-dns-forwarder-bypass/verify.sh`; `labs/acr-network-path-dns-forwarder-bypass/evidence/14-cohort-integrity-gate.json`; `labs/acr-network-path-dns-forwarder-bypass/evidence/15-h1-trigger-produces-failure-gate.json`; `labs/acr-network-path-dns-forwarder-bypass/evidence/16-h2-fix-restores-recovery-gate.json`; `labs/acr-network-path-dns-forwarder-bypass/evidence/17-bounded-falsification-gate.json` | `evaluated_at_utc` from the replay invocation | Raw timestamps remain authoritative capture evidence; `scripts/check_gate_replay.py` may supply historical file-system anchors only after its raw-bytes guard passes. | Fixed in Batch B | #409 batch B |
| `acr-network-path-firewall-allowlist` | `labs/acr-network-path-firewall-allowlist/verify.sh`; `labs/acr-network-path-firewall-allowlist/evidence/14-cohort-integrity-gate.json`; `labs/acr-network-path-firewall-allowlist/evidence/15-h1-trigger-produces-failure-gate.json`; `labs/acr-network-path-firewall-allowlist/evidence/16-h2-fix-restores-recovery-gate.json`; `labs/acr-network-path-firewall-allowlist/evidence/17-bounded-falsification-gate.json` | `evaluated_at_utc` from the replay invocation | Raw timestamps remain capture evidence; only the four derived gate replay stamps changed. | Fixed in this PR | #409 batch A |
| `acr-network-path-pe-direct` | `labs/acr-network-path-pe-direct/verify.sh`; `labs/acr-network-path-pe-direct/evidence/14-cohort-integrity-gate.json`; `labs/acr-network-path-pe-direct/evidence/15-h1-trigger-produces-failure-gate.json`; `labs/acr-network-path-pe-direct/evidence/16-h2-fix-restores-recovery-gate.json`; `labs/acr-network-path-pe-direct/evidence/17-bounded-falsification-gate.json` | `evaluated_at_utc` from the replay invocation | Raw timestamps remain capture evidence; only the four derived gate replay stamps changed. | Fixed in this PR | #409 batch A |
| `acr-network-path-pe-forced-inspection` | `labs/acr-network-path-pe-forced-inspection/verify.sh`; `labs/acr-network-path-pe-forced-inspection/evidence/14-cohort-integrity-gate.json`; `labs/acr-network-path-pe-forced-inspection/evidence/15-h1-trigger-produces-failure-gate.json`; `labs/acr-network-path-pe-forced-inspection/evidence/16-h2-fix-restores-recovery-gate.json`; `labs/acr-network-path-pe-forced-inspection/evidence/17-bounded-falsification-gate.json` | `evaluated_at_utc` from the replay invocation | Raw timestamps remain authoritative capture evidence; `scripts/check_gate_replay.py` may supply historical file-system anchors only after its raw-bytes guard passes. | Fixed in Batch C | #409 batch C |
| `acr-network-path-record-split-brain` | `labs/acr-network-path-record-split-brain/verify.sh`; `labs/acr-network-path-record-split-brain/evidence/14-cohort-integrity-gate.json`; `labs/acr-network-path-record-split-brain/evidence/15-h1-trigger-produces-failure-gate.json`; `labs/acr-network-path-record-split-brain/evidence/16-h2-fix-restores-recovery-gate.json`; `labs/acr-network-path-record-split-brain/evidence/17-bounded-falsification-gate.json` | `evaluated_at_utc` from the replay invocation | Raw timestamps remain authoritative capture evidence; `scripts/check_gate_replay.py` may supply historical file-system anchors only after its raw-bytes guard passes. | Fixed in Batch B | #409 batch B |
| `cd-reconnect-rbac-conflict` | `labs/cd-reconnect-rbac-conflict/verify.sh`; `labs/cd-reconnect-rbac-conflict/evidence/07-h1-gate.json`; `labs/cd-reconnect-rbac-conflict/evidence/14-h2-gate.json` | `evaluated_at_utc` from verifier replay time | Capture-script timestamps and raw Azure observation times remain unchanged; only Gates 07 and 14 receive evaluation time. | Fixed in Batch E | #409 batch E |
| `dapr-integration` | `labs/dapr-integration/verify.sh`; `labs/dapr-integration/evidence/14-cohort-integrity-gate.json`; `labs/dapr-integration/evidence/15-h1-trigger-produces-failure-gate.json`; `labs/dapr-integration/evidence/16-h2-fix-restores-recovery-gate.json`; `labs/dapr-integration/evidence/17-bounded-falsification-gate.json` | `utc_captured` from `UTC_NOW`, pinned to the earliest existing gate | Preserve raw `createdTime`, `TimeStamp`, `systemData.lastModifiedAt`, and HTTP `Date` values; generate fresh `evaluated_at_utc` for Gates 14-17. | Fixed in this PR | #577 PR |
| `ingress-target-port-mismatch` | `labs/ingress-target-port-mismatch/verify.sh`; `labs/ingress-target-port-mismatch/evidence/14-cohort-integrity-gate.json`; `labs/ingress-target-port-mismatch/evidence/15-h1-trigger-produces-failure-gate.json`; `labs/ingress-target-port-mismatch/evidence/16-h2-fix-restores-recovery-gate.json`; `labs/ingress-target-port-mismatch/evidence/17-single-variable-falsification-gate.json` | `evaluated_at_utc` from the replay invocation | Raw timestamps remain capture evidence; only the four derived gate replay stamps changed. | Fixed in Batch C | #409 batch C |
| `managed-identity-key-vault-failure` | `labs/managed-identity-key-vault-failure/verify.sh`; `labs/managed-identity-key-vault-failure/evidence/14-cohort-integrity-gate.json`; `labs/managed-identity-key-vault-failure/evidence/15-h1-trigger-produces-failure-gate.json`; `labs/managed-identity-key-vault-failure/evidence/16-h2-fix-restores-recovery-gate.json`; `labs/managed-identity-key-vault-failure/evidence/17-bounded-falsification-gate.json` | `evaluated_at_utc` from the replay invocation | Raw timestamps remain capture evidence in embedded fields (e.g., HTTP `Date`, `roleAssignment.createdOn`, `revision.createdTime`). Gate 14 intentionally replaced filesystem birthtime anchors with raw-content anchors and phase proxies (direct_payload and phase_proxy types). | Fixed in Batch D | #409 batch D |
| `observability-tracing` | `labs/observability-tracing/verify.sh`; `labs/observability-tracing/evidence/12-h1-gate.json`; `labs/observability-tracing/evidence/24-h2-gate.json` | `evaluated_at_utc` from verifier replay time | Capture-script and telemetry event times remain unchanged; only Gates 12 and 24 receive evaluation time. | Fixed in Batch E | #409 batch E |
| `probe-and-port-mismatch` | `labs/probe-and-port-mismatch/verify.sh`; `labs/probe-and-port-mismatch/evidence/11-h1-gate.json`; `labs/probe-and-port-mismatch/evidence/22-h2-gate.json` | `evaluated_at_utc` from verifier replay time | Capture-script and raw revision/log timestamps remain unchanged; only Gates 11 and 22 receive evaluation time. | Fixed in Batch E | #409 batch E |
| `revision-failover` | `labs/revision-failover/verify.sh`; `labs/revision-failover/evidence/11-h1-gate.json`; `labs/revision-failover/evidence/17-h2-gate.json` | `evaluated_at_utc` from the replay invocation | Capture-script and raw revision/traffic timestamps remain capture evidence; only Gates 11 and 17 carry replay evaluation time. | Fixed in Batch F | #409 batch F |
| `revision-provisioning-failure` | `labs/revision-provisioning-failure/verify.sh`; `labs/revision-provisioning-failure/evidence/14-cohort-integrity-gate.json`; `labs/revision-provisioning-failure/evidence/15-h1-trigger-produces-failure-gate.json`; `labs/revision-provisioning-failure/evidence/16-h2-fix-restores-recovery-gate.json`; `labs/revision-provisioning-failure/evidence/17-bounded-falsification-gate.json` | `evaluated_at_utc` from the replay invocation | Raw timestamps remain capture evidence in embedded fields. All four derived gates changed only their replay stamp (`utc_captured` to `evaluated_at_utc`); a normalized comparison against `origin/main` with the stamp key removed shows no other difference. | Fixed in Batch D | #409 batch D |
| `scale-rule-mismatch` | `labs/scale-rule-mismatch/verify.sh`; `labs/scale-rule-mismatch/evidence/10-h1-gate.json`; `labs/scale-rule-mismatch/evidence/19-h2-gate.json` | `evaluated_at_utc` from the replay invocation | Capture-script and raw scaler/log timestamps remain capture evidence; only Gates 10 and 19 carry replay evaluation time. | Fixed in Batch F | #409 batch F |
| `traffic-routing-canary` | `labs/traffic-routing-canary/verify.sh`; `labs/traffic-routing-canary/evidence/12-h1-gate.json`; `labs/traffic-routing-canary/evidence/22-h2-gate.json` | `evaluated_at_utc` from the replay invocation | Capture-script and raw revision/traffic timestamps remain capture evidence; only Gates 12 and 22 carry replay evaluation time. | Fixed in Batch F | #409 batch F |

## Selected Batch

This batch selects only `acr-network-path-firewall-allowlist` and `acr-network-path-pe-direct`. Each verifier has four committed derived gates and separates its 12-file raw cohort from Phase B outputs. The conversion proves raw capture bytes remain unchanged while each gate changes only the top-level timestamp key and value.

Before this batch, **21 verifiers and 44 committed derived gates** remained after the Dapr conversion. Removing these two verifiers and their eight gates leaves **19 verifiers and 36 committed derived gates** out of scope. The three remaining ACR network-path labs stay deferred, while the seven `aca-secret-kv-ref-mi-network-path*` sources need classification again when derived gates are committed.

## Batch B

Batch B selects only `acr-network-path-dns-forwarder-bypass` and `acr-network-path-record-split-brain`. Both verifiers retain originally emitted file-system anchors only through `GATE_REPLAY_BASELINE_DIR`; `scripts/check_gate_replay.py` first proves every current tracked non-gate evidence file is byte-identical to `HEAD`. Values parsed from the current raw payloads are always authoritative and are never replaced with committed-gate values.

Starting from the **19 verifiers and 36 committed derived gates** remaining after Batch A, the matrix has four other four-gate verifiers, five two-gate verifiers, and seven source-only verifiers with no committed gates. Removing these two verifiers and their eight gates therefore leaves **17 verifiers and 28 committed derived gates**. The remaining affected ACR network-path verifier is `acr-network-path-pe-forced-inspection`; the seven `aca-secret-kv-ref-mi-network-path*` sources still have no committed derived gates.

## Batch C

Batch C selects only `acr-network-path-pe-forced-inspection` and `ingress-target-port-mismatch`. The ACR verifier retains originally emitted file-system anchors only through `GATE_REPLAY_BASELINE_DIR`; `scripts/check_gate_replay.py` first proves every current tracked non-gate evidence file is byte-identical to `HEAD`. Values parsed from current raw payloads remain authoritative. The ingress verifier derives all anchors directly from raw payload fields and needs no historical baseline anchors.

Inventory counts after Batch C were superseded by later batches; the measured counts on the merged tree are in the Batch F section.

`acr-pull-failure` appears in a literal `grep -l utc_captured labs/*/verify.sh` only as a Phase-A-only hit: the verifier references legitimate Phase A `utc_captured` fields from raw evidence, and its current Phase B Gates 30-33 already emit top-level `evaluated_at_utc`. Its older committed Gates 06 and 14 retain historical top-level `utc_captured`, but they are not outputs of the current offline verifier.

## Batch D

Batch D converts `managed-identity-key-vault-failure` and `revision-provisioning-failure`. Each verifier has four committed derived gates and keeps capture timestamps in the 12-file raw cohort unchanged. A normalized comparison against `origin/main` (stamp key removed) shows all four `revision-provisioning-failure` gates changed only their replay stamp. Only `managed-identity-key-vault-failure` Gate 14 has an additional, justified anchor change: raw-content anchors and phase proxies (`direct_payload` and `phase_proxy`) replace filesystem birthtime. Remaining-work counts after Batch D are measured in the Batch F section.

## Batch E

Batch E converts `cd-reconnect-rbac-conflict`, `observability-tracing`, and `probe-and-port-mismatch`. Their offline Phase B paths validate current raw payloads and derive gate decisions without Azure access. Direct live-capture paths preserve capture-script timestamps plus Azure, revision, log, and telemetry event times.

Literal `utc_captured` occurrences that remain in the converted observability verifier belong to raw curl and secret-store capture artifacts, not to Gates 12 or 24. Remaining-work counts are measured in the Batch F section.

## Batch F

Batch F converts `revision-failover`, `scale-rule-mismatch`, and `traffic-routing-canary`. Their offline replay paths derive Gates 11/17, 10/19, and 12/22 respectively from the current raw payloads. Direct replay is independent of existing gates; `GATE_REPLAY_BASELINE_DIR` is an explicit opt-in comparison source used only after `scripts/check_gate_replay.py` proves the raw cohort byte-identical to `HEAD`. Capture-script start times and raw revision, traffic, scaler, replica, and log timestamps remain unchanged.

Measured on the merged tree after Batches D and F: `grep -l utc_captured labs/*/verify.sh` reports **9** textual hits. Seven are actual emitters of a top-level `utc_captured` in derived output: the seven source-only `aca-secret-kv-ref-mi-network-path*` verifiers, which have no committed gates. The other two hits are not remaining emitters: `acr-pull-failure` is a Phase-A-only hit (comments and references to raw capture fields; its Phase B gates emit `evaluated_at_utc`, and historical Gates 06 and 14 are not current offline-verifier outputs), and `observability-tracing` matches only raw curl and secret-store capture artifacts, not Gates 12 or 24. No committed Phase B gate still carries a top-level `utc_captured` from a remaining emitter (**0**). A scan of all tracked JSON for a top-level `utc_captured` key returns **11** hits: 2 historical `acr-pull-failure` gates (Gates 06 and 14), 8 raw-evidence files in `observability-tracing`, and 1 raw-evidence file in `diagnostic-settings-missing`.

## Fail-Open Gate Replay Audit

Issue #579 audited the checked items in #398 at `origin/main` commit `9cbf725392ae262dadf3553005172d7eda88c6a0` on 2026-11-07. The exact already-merged implementation slices are:

| #398 item | Merged implementation |
|---|---|
| 1. Reject a missing or incomplete healthy memory report | PR #418 (`ed2f834feec8af361807ad040a588216e3f9bed3`) added structural rejection and negative fixtures; PR #421 (`3862fa214213fbd5cb64fc1931fb83a9a94ee8b8`) made every evaluator consume the validated rows. |
| 2. Scope KEDA correlation to signal rows | PR #418 (`ed2f834feec8af361807ad040a588216e3f9bed3`) restricted correlation to the declared timestamp columns of selected signal and probe rows and added the disjoint-window fixture. |
| 3. Declare the replica-summary tolerance and preserve raw primacy | PR #416 (`e56ee7e29abb522a00ea4621b74b6cbb3db39f46`) documented the two-entry advisory tolerance, added the two-pass/three-fail boundary fixture, and retained raw JSONL as authoritative. |
| 4. Validate consumed scale-record fields | PR #416 (`e56ee7e29abb522a00ea4621b74b6cbb3db39f46`) added the scale boundary checks in `labs/replica-node-spread/verify_helpers.py` and their structured gate output and negative fixtures. |
| 5. Harden serialization, recursive input handling, numeric bounds, and clean replay | PR #416 (`e56ee7e29abb522a00ea4621b74b6cbb3db39f46`) added the input and serialization boundaries; PR #417 (`3d56d18bce04b9294bd3485390820472f63179a1`) added `scripts/check_gate_replay.py`, delete-first replay, and replay-runner negatives. |
| 6. Correct stale comments and evidence descriptions | PR #416 (`e56ee7e29abb522a00ea4621b74b6cbb3db39f46`) corrected the replica comments and measured size cells; PR #418 (`ed2f834feec8af361807ad040a588216e3f9bed3`) corrected the memory, KEDA, and revision-history comments, including the byte-identity overclaim. |

The current negative coverage includes:

| #398 item | Current regression coverage |
|---|---|
| Missing or incomplete healthy memory report | `scripts/test_memory_keda_gates.py::MemoryReportTests::test_incomplete_healthy_report_fails` |
| KEDA correlation scoped to declared signal rows | `scripts/test_memory_keda_gates.py::KedaSignalWindowTests::test_unrelated_timestamp_cannot_correlate_disjoint_signal_rows` |
| Documented replica-summary tolerance | `labs/replica-node-spread/test_verify.py::SummaryBoundaryTests::test_two_advisory_discrepancies_pass_but_three_fail` |
| Malformed replica scale fields | `labs/replica-node-spread/test_verify.py::ScaleBoundaryTests::test_each_supplied_malformed_scale_field_is_unusable` |
| Non-finite serialization, recursive JSON, decoded numeric bound, and clean replay | `StrictSerializationTests::test_real_gate_serializer_rejects_nonfinite_values`, `RecursiveJsonBoundaryTests`, `BoundedAnchorNumberTests::test_decimal_token_rounded_to_decoded_bound_is_accepted`, and `CleanReplayTests` in `labs/replica-node-spread/test_verify.py`; replay-runner negatives in `scripts/test_check_gate_replay.py` |

A scratch clone replayed the current verifiers against unchanged committed raw evidence for these derived outputs:

- `memory-leak-oomkilled`: Gates 10-13
- `keda-no-metrics-returned`: Gates 10-13
- `replica-node-spread`: Gates 10-13
- `revision-history-limit`: Gates 20-23

All 16 outputs matched the committed JSON exactly after removing only the top-level `evaluated_at_utc` field. The stale-output list is therefore **empty**: #579 regenerates no gate JSON, changes no raw evidence, and defers no #398 artifact. Startup Gates 10-13 were also replayed and were current, but they are not counted in the 16-output #579 scope because PRs #432 and #433 implement separately tracked #413 work. The 21 verifier conversions remaining in #409 and the other predicate changes tracked by #413 remain separate work.

Two pre-existing local checks remain visible rather than being presented as #579 results. `labs/replica-node-spread/test_verify.py` has five `RecursiveJsonBoundaryTests` failures at this pinned SHA under local Python 3.11 and 3.14: four expected parse-failure counts differ and `test_invalid_summary_json_returns_named_boundary_reason` does not observe the expected `RecursionError`. The Application Tests workflow is configured to run this suite on hosted Python 3.11 when its lab, script, or workflow paths change, but this documentation-only PR does not trigger that workflow. Full ShellCheck also reports pre-existing advisory `SC2155` at `labs/replica-node-spread/verify.sh:258`; CI blocks ShellCheck errors and reports warnings as advisory. Neither baseline finding changes the successful clean replays above.

## See Also

- [Contributing Guide](index.md)
- [Lab Portal Capture Briefs](lab-portal-capture-briefs.md)
- [Dapr Integration Lab Guide](../troubleshooting/lab-guides/dapr-integration.md)
