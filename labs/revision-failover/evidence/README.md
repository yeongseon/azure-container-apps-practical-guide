# Evidence Pack Provenance

This evidence pack records the live `revision-failover` reproduction captured on 2026-06-22. The raw revision, traffic, scaler, log, command-output, and capture-script timestamps remain the original observation times.

`11-h1-gate.json` and `17-h2-gate.json` are derived outputs. They were originally emitted during the live run and later re-evaluated offline from the unchanged raw files. Every replay writes its own invocation time as top-level `evaluated_at_utc`; that field is not an evidence-capture time and establishes no current replay or Azure validation date. Replays reproduce every non-time gate field from the raw cohort.

## Gate Files

- `11-h1-gate.json` evaluates the broken-revision H1 predicates.
- `17-h2-gate.json` evaluates the in-place recovery H2 predicates.

## Raw Time Sources

The capture-script start times in `00-trigger-run.txt` and `00-verify-run.txt`, revision `createdTime` values, KQL `TimeGenerated` values, and the gate's break/fix windows remain raw provenance and are not renamed during offline evaluation.
