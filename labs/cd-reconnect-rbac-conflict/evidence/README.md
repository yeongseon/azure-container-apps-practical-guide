# Evidence Pack Provenance

This evidence pack records the live Azure experiment captured on **2026-06-23**. The raw Azure timestamps and capture-script fields remain the authoritative record of that original run.

`07-h1-gate.json` and `14-h2-gate.json` are derived decisions. They were originally emitted during the live run and were later re-evaluated offline from the unchanged raw evidence. Each replay writes its invocation time to top-level `evaluated_at_utc`; that value is not a capture date and does not establish a current Azure replay or validation date.

The direct offline evaluator does not read either committed gate as a decision baseline. Several original shell-local start times and the reconnect attempt's generated GUID were never written to raw evidence, so the regenerated gates use the nearest authoritative raw event times instead: deployment completion timestamps for the initial, reconnect, and recovery operations, the pre-delete assignment `createdOn` timestamp for the reverify/delete boundary, and `not_recorded_in_raw_evidence` for the unavailable reconnect GUID. These non-stamp changes preserve every predicate because none of those historical display fields participates in a sub-gate decision.

## File Index

- `01-*` through `06-*`: trigger inputs and raw conflict evidence.
- `07-h1-gate.json`: derived H1 decision.
- `08-*` through `13-*`: verify inputs and raw recovery evidence.
- `14-h2-gate.json`: derived H2 decision.
- `18-*` through `21-*`: CLI, extension, region, and deployment metadata.

## See Also

- [Lab README](../README.md)
- [Lab guide](../../../docs/troubleshooting/lab-guides/cd-reconnect-rbac-conflict.md)
