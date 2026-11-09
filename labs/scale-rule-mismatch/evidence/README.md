# Evidence Pack Provenance

This evidence pack records the live `scale-rule-mismatch` reproduction captured on 2026-06-22. The raw revision, scaler, replica, log, command-output, and capture-script timestamps remain the original observation times.

`10-h1-gate.json` and `19-h2-gate.json` are derived outputs. They were originally emitted during the live run and later re-evaluated offline from the unchanged raw files. Every replay writes its own invocation time as top-level `evaluated_at_utc`; that field is not an evidence-capture time and establishes no current replay or Azure validation date. Replays reproduce every non-time gate field from the raw cohort.

## Gate Files

- `10-h1-gate.json` evaluates the mismatched-threshold H1 predicates.
- `19-h2-gate.json` evaluates the corrected-scaling H2 predicates.

## Raw Time Sources

The capture-script start times in `00-trigger-run.txt` and `00-verify-run.txt`, strict load windows, revision timestamps, and KQL `TimeGenerated` values remain raw provenance and are not renamed during offline evaluation.
