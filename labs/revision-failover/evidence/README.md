# Evidence Pack Provenance

This evidence pack records the live `revision-failover` reproduction captured on 2026-06-22. The raw revision, traffic, scaler, log, command-output, and capture-script timestamps remain the original observation times.

`11-h1-gate.json` and `17-h2-gate.json` are derived outputs. They were originally emitted during the live run and later re-evaluated offline from the unchanged raw files. Every replay writes its own invocation time as top-level `evaluated_at_utc`; that field is not an evidence-capture time and establishes no current replay or Azure validation date.

Direct replay is hermetic: it does not read an existing gate. The original scripts did not persist their exact KQL query end times outside the gates, so replay now uses the latest raw `TimeGenerated` value in `09-system-logs-probe-failures.json` and `16-system-logs-recovery.json` as deterministic break/fix end proxies. This changes `break_window.end_utc` from `2026-06-22T16:15:45Z` to `2026-06-22T16:13:08.3102116Z` and `fix_window.end_utc` from `2026-06-22T16:16:42Z` to `2026-06-22T16:16:25.8760192Z`; raw evidence bytes and gate predicates are unchanged. Guarded replay may compare the result with a baseline only when `GATE_REPLAY_BASELINE_DIR` is explicitly supplied after the replay runner's raw-byte check.

## Gate Files

- `11-h1-gate.json` evaluates the broken-revision H1 predicates.
- `17-h2-gate.json` evaluates the in-place recovery H2 predicates.

## Raw Time Sources

The capture-script start times in `00-trigger-run.txt` and `00-verify-run.txt`, revision `createdTime` values, and KQL `TimeGenerated` values remain raw provenance and are not renamed during offline evaluation. The gate break/fix end fields are deterministic phase proxies derived from those raw KQL timestamps.
