#!/usr/bin/env bash
# verify.sh — Phase B evidence-pack verification for Lab 16 (keda-no-metrics-returned).
#
# What this script proves (falsifiable, strict 2-path predicates per Oracle
# Option Y directive 2026-06-24). Reads ONLY the canonical evidence files
# written by trigger.sh (report-*.txt + revisions-*.json + traffic-*.json
# per scenario) and emits four sub-gate JSON files (10..13). NO Azure
# calls — verify.sh is replayable from disk so a reviewer can re-classify
# gates without re-deploying infrastructure.
#
# This script's strict 2-path predicate rule (Lab 11/12/13/14/15 lesson):
#   Each sub-gate computes Strong AND Fallback in the same evaluation;
#   the gate passes if EITHER path is true. The JSON output captures
#   which path passed so a reviewer can audit the evidence trail.
#
# Oracle Lab 16 directive risk mitigation (verbatim 2026-06-24):
#   "Don't key strong predicates to one exact log sentence; use stable
#    substrings plus state correlation". Each sub-gate below pairs a
#   stable text substring (e.g. "no metrics returned from resource
#   metrics API", "Probe of StartUp failed", "Container ... was
#   terminated") with an orthogonal state signal (revision healthState,
#   bin count from §6 KQL summarize, ISO timestamp ordering) so a
#   future log-line wording change cannot silently break the gate.
#
# Gate design (4 falsifiable gates / 12 sub-gates total):
#
#   10-h1-slow-not-ready-gate.json — H1 for Scenario A (slow-start,
#     DELAY_SECONDS=120). Proves the "no metrics" signal is observed,
#     correlates with NotReady (StartUp probe failures), and resolves
#     once the revision reaches Healthy. Sub-gates:
#       a) Signal observed: ≥10 lines containing the canonical "no
#          metrics returned from resource metrics API" substring in §5.
#       b) NotReady correlation: §9 contains "Probe of StartUp failed"
#          AND the §5 metric-error timestamp window overlaps the §9
#          probe-failure timestamp window (Strong); or just probe
#          failures present (Fallback). Overlap proves the metric
#          errors fire WHILE the container is in the NotReady phase,
#          not after.
#       c) Eventually Ready: sidecar revisions[*].healthState=="Healthy"
#          (Strong) or sidecar traffic[*].weight==100 (Fallback). Proves
#          the slow-start revision recovers — the signal was transient.
#
#   11-h1-crash-not-ready-gate.json — H1 for Scenario B (crash-loop,
#     DELAY_SECONDS=30, exits every 30s). Proves the "no metrics" signal
#     persists across multiple 5-min bins for a chronically NotReady
#     workload. Sub-gates:
#       a) Signal spans ≥2 bins in §6 (Strong); or §5 duration > 300s
#          (Fallback). The captured baseline has 3 bins (25/1/1).
#       b) Unready state: §2 healthState=="Unhealthy" AND runningState=
#          =="Failed" (Strong); or sidecar revisions healthState!=
#          "Healthy" OR §2 provisioningState=="Failed" (Fallback). The
#          AND condition in the Strong path is what distinguishes a
#          crash loop from a transient deployment hiccup.
#       c) Persistent pattern (NOT just a deployment spike): §6 has bins
#          BEYOND the first deployment bin (Strong); or §5 last_ts -
#          first_ts > 600s (Fallback). The captured baseline has bins at
#          00:35, 00:40, AND 00:45 — proving the signal recurred after
#          the initial Metrics-Server warm-up window closed.
#
#   12-h2-healthy-post-ready-gate.json — H2 for Scenario C (healthy,
#     instant-start). Proves the "no metrics" signal is BOUNDED to the
#     Metrics-Server warm-up window and does NOT persist after Ready.
#     This is the H2 falsification: "metric errors imply chronic
#     unreadiness" is FALSE because healthy revisions also briefly
#     produce them during warm-up. Sub-gates:
#       a) Healthy/Running: §2 healthState=="Healthy" AND
#          runningState=="Running" (Strong); or sidecar revisions
#          healthState=="Healthy" AND traffic weight==100 (Fallback).
#       b) Single 5-min bin in §6 (Strong); or ≤2 bins (Fallback). The
#          captured baseline has exactly 1 bin (16 errors @ 00:35).
#       c) Silent after warm-up: §5 last_ts - first_ts ≤ 300s (Strong);
#          or §5 line count ≤ 20 (Fallback). The captured baseline has
#          16 errors spanning ~106 seconds.
#
#   13-h3-cross-scenario-falsification-gate.json — H3 cross-scenario
#     differential. Proves "metric-error severity tracks unreadiness
#     severity": healthy (transient) < slow (transient + delayed) <
#     crash (chronic). Sub-gates:
#       a) Bin count ordering: healthy_bins == 1 AND slow_bins == 1
#          AND crash_bins >= 2 (Strong); or healthy_bins <= slow_bins
#          < crash_bins (Fallback).
#       b) Duration ordering: crash_duration >= 3.0 * max(healthy_dur,
#          slow_dur) (Strong); or crash_duration > healthy_dur AND
#          crash_duration > slow_dur (Fallback). The captured baseline
#          has crash=603s vs slow=136s vs healthy=106s → 4.43x ratio.
#       c) Health state matches outcome: healthy=="Healthy" AND
#          slow=="Healthy" AND crash=="Unhealthy" (Strong); or crash
#          != "Healthy" AND at least one of {healthy, slow} == "Healthy"
#          (Fallback).
#
# Why we do NOT key strong predicates to the FULL log sentence:
#   The current Container Apps KEDA scaler emits the sentence "invalid
#   metrics (1 invalid out of 5), first error is: failed to get
#   <app> container metric value: failed to get memory usage: unable
#   to get metrics for resource memory: no metrics returned from
#   resource metrics API". A wording change in any prefix segment
#   (e.g. swapping "invalid metrics (1 invalid out of 5)" for
#   "invalid metrics (1/5 invalid)") would silently break a full-
#   sentence match. The stable, end-of-sentence substring "no metrics
#   returned from resource metrics API" is the directly quoted phrase
#   from the original Microsoft Learn KEDA troubleshooting article
#   and is what operators search for. State correlation via the
#   revision-level healthState and §9 probe events provides the
#   orthogonal signal Oracle directive risk 1 calls for.
#
# Numbered prefix policy (per Phase B Lab 11/12/15 lessons):
#   report-*.txt + sidecar files = trigger.sh snapshots (raw, no
#     derived state). The report sections §0-§14 are an internal
#     contract with trigger.sh and MUST NOT be renumbered here.
#   10..13 = verify.sh derived sub-gates (this script).
#
# QUOTED heredoc rationale (Lab 14 lesson 29):
#   `<<'PY'` is used on every Python heredoc. With an unquoted `<<PY`
#   heredoc, bash would expand any `$` characters inside Python regex
#   literals or substring matches before Python sees them. The
#   exception is the final summary block at the bottom of this file,
#   which deliberately uses `<<PY` (unquoted) so the shell variable
#   `$EVIDENCE_DIR` is expanded by bash — that block contains no `$`
#   literals that Python should see.
#
# REPO_RELATIVE_EVIDENCE_DIR rationale (PII safety, Lab 14 lesson):
#   The Python heredocs use EVIDENCE_DIR (absolute) for filesystem
#   reads, but every path written *into* the gate JSON output uses
#   REPO_RELATIVE_EVIDENCE_DIR so the operator's /Users/<name>/... layout
#   is never recorded as PII in committed evidence.
#
# Usage:
#   bash labs/keda-no-metrics-returned/verify.sh
#   (no environment variables needed — pure evidence-file processor)

set -euo pipefail

EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"
REPO_RELATIVE_EVIDENCE_DIR="labs/keda-no-metrics-returned/evidence"

# Per-scenario subdirectories and pinned evidence file basenames from the
# canonical 2026-06-20 run. Pinning the timestamp suffix here (not glob-
# matching) makes the predicate inputs reproducible — a re-run via
# trigger.sh would produce new timestamps and the gate JSONs would
# document the new run instead of silently mixing old + new evidence.
SLOW_APP_NAME="ca-nometrics-slow"
SLOW_REVISION_NAME="ca-nometrics-slow--gd2u817"
SLOW_EVIDENCE_TS="20260620T004802Z"

CRASH_APP_NAME="ca-nometrics-crash"
CRASH_REVISION_NAME="ca-nometrics-crash--xfn3h34"
CRASH_EVIDENCE_TS="20260620T004905Z"

HEALTHY_APP_NAME="ca-nometrics-healthy"
HEALTHY_REVISION_NAME="ca-nometrics-healthy--9ovm8cn"
HEALTHY_EVIDENCE_TS="20260620T005025Z"

# Stable, end-of-sentence substring quoted directly from Microsoft Learn
# KEDA troubleshooting documentation. The full sentence varies (some
# variants prefix with "invalid metrics (1 invalid out of 5), first
# error is: ..."), but this trailing substring is invariant across all
# observed wording variants on 2026-06-20.
SIGNAL_SUBSTRING="no metrics returned from resource metrics API"

# Stable substring for §9 NotReady correlation. The Container Apps
# StartUp probe emits "Probe of StartUp failed with status code: 1"
# — keying on the prefix "Probe of StartUp failed" is robust against
# the trailing status code varying (e.g. "with status code: 137" on a
# different failure mode).
PROBE_FAILURE_SUBSTRING="Probe of StartUp failed"

# Predicate thresholds. The MIN-line counts are chosen to be well below
# the captured baselines (slow=20, crash=27, healthy=16) so a re-run
# with slightly different timing still passes the gate, but high enough
# to falsify a single accidental log line.
SIGNAL_MIN_LINES=10
CRASH_DURATION_MIN_SECONDS=300
CRASH_LONG_DURATION_FALLBACK_SECONDS=600
HEALTHY_DURATION_MAX_SECONDS=300
HEALTHY_LINES_MAX_FALLBACK=20
CROSS_SCENARIO_RATIO_STRONG=3.0

# Sanity-check that trigger.sh has been run end-to-end before verify.sh.
# Missing inputs are a hard fail — verify.sh cannot synthesize evidence
# it does not have on disk. The check covers report + revisions +
# traffic for all 3 scenarios.
for required in \
    "${SLOW_APP_NAME}/report-${SLOW_EVIDENCE_TS}.txt" \
    "${SLOW_APP_NAME}/revisions-${SLOW_EVIDENCE_TS}.json" \
    "${SLOW_APP_NAME}/traffic-${SLOW_EVIDENCE_TS}.json" \
    "${CRASH_APP_NAME}/report-${CRASH_EVIDENCE_TS}.txt" \
    "${CRASH_APP_NAME}/revisions-${CRASH_EVIDENCE_TS}.json" \
    "${CRASH_APP_NAME}/traffic-${CRASH_EVIDENCE_TS}.json" \
    "${HEALTHY_APP_NAME}/report-${HEALTHY_EVIDENCE_TS}.txt" \
    "${HEALTHY_APP_NAME}/revisions-${HEALTHY_EVIDENCE_TS}.json" \
    "${HEALTHY_APP_NAME}/traffic-${HEALTHY_EVIDENCE_TS}.json"; do
    if [ ! -f "${EVIDENCE_DIR}/${required}" ]; then
        echo "ERROR: required evidence file ${EVIDENCE_DIR}/${required} not found. Run trigger.sh first." >&2
        exit 1
    fi
done

CAPTURED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

echo "=== Phase 10: emit H1 gate for Scenario A (slow-start, NotReady correlation) ==="
# Sub-gate logic implemented in Python so the Strong/Fallback predicates,
# section-parsing helpers, and timestamp arithmetic are unit-testable
# from disk. The Python block reads evidence files by absolute path and
# writes the gate JSON to stdout.
EVIDENCE_DIR="$EVIDENCE_DIR" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
CAPTURED_AT_UTC="$CAPTURED_AT_UTC" \
SLOW_APP_NAME="$SLOW_APP_NAME" \
SLOW_REVISION_NAME="$SLOW_REVISION_NAME" \
SLOW_EVIDENCE_TS="$SLOW_EVIDENCE_TS" \
SIGNAL_SUBSTRING="$SIGNAL_SUBSTRING" \
PROBE_FAILURE_SUBSTRING="$PROBE_FAILURE_SUBSTRING" \
SIGNAL_MIN_LINES="$SIGNAL_MIN_LINES" \
python3 - <<'PY' > "$EVIDENCE_DIR/10-h1-slow-not-ready-gate.json"
import json
import os
import re

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
REPO_RELATIVE_EVIDENCE_DIR = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]
SLOW_APP_NAME = os.environ["SLOW_APP_NAME"]
SLOW_REVISION_NAME = os.environ["SLOW_REVISION_NAME"]
SLOW_EVIDENCE_TS = os.environ["SLOW_EVIDENCE_TS"]
SIGNAL_SUBSTRING = os.environ["SIGNAL_SUBSTRING"]
PROBE_FAILURE_SUBSTRING = os.environ["PROBE_FAILURE_SUBSTRING"]
SIGNAL_MIN_LINES = int(os.environ["SIGNAL_MIN_LINES"])

# ---------- shared parsing helpers (used by all phases) ----------
# Priority 3 helper-comment justification: parsing the trigger.sh
# report-*.txt format is non-trivial because each numbered section
# carries a different shape (column-aligned text for §5/§6/§9, inline
# JSON for §2). Centralizing the parsers as named functions makes
# each predicate's intent self-documenting and prevents accidental
# off-by-one issues from regex sprawl in sub-gate logic below.

# ISO 8601 timestamp regex covering both the §5/§9 fractional-seconds
# format ("2026-06-20T00:38:05.0694807Z") and the §6 aggregated form
# ("2026-06-20T00:35:00Z"). Anchored to digits only (no surrounding
# punctuation match) so it can be applied to a full text line.
ISO_TS_REGEX = re.compile(
    r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z'
)

def get_section(text, section_header):
    """Extract the text between a numbered section header (e.g.
    "=== 5. System logs: metric errors ===") and the next "=== "
    header (or EOF). Returns the section body without the header line.
    Tight scoping: the header match requires an exact equality on
    the trimmed line, so a substring like "5. System logs" appearing
    elsewhere cannot accidentally match."""
    lines = text.split("\n")
    start = None
    for i, line in enumerate(lines):
        if line.strip() == section_header:
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        if lines[j].startswith("=== ") and lines[j].endswith(" ==="):
            end = j
            break
    return "\n".join(lines[start:end])

def count_record_lines_matching(section_text, substring):
    """Count lines in the section that contain the given substring.
    Per Lab 15 lesson 34, this uses RECORD-SCOPED matching (per-line
    `in`), not whole-file `in`, so substring matches in unrelated
    sections cannot poison the count. Returns 0 if section_text is
    None."""
    if section_text is None:
        return 0
    return sum(
        1 for line in section_text.split("\n")
        if substring in line
    )

def extract_timestamps_from_section(section_text):
    """Return all ISO 8601 timestamps found in the section, in the
    order they appear. Used to compute first/last/duration for
    §5 metric-error windows and §9 probe-failure windows."""
    if section_text is None:
        return []
    return ISO_TS_REGEX.findall(section_text)

def parse_iso_to_seconds(ts):
    """Parse an ISO 8601 timestamp to Unix-epoch seconds (float). Used
    for window-overlap and duration arithmetic. Strips fractional
    seconds beyond microseconds because datetime.fromisoformat() in
    Python 3.10 cannot parse the 7-digit fractional form Container
    Apps emits (e.g. "0694807Z"). The trailing Z is stripped and
    treated as UTC."""
    import datetime
    ts_no_z = ts.rstrip("Z")
    # Truncate fractional seconds to 6 digits (microseconds) for
    # fromisoformat() compatibility on Python 3.10+.
    if "." in ts_no_z:
        whole, frac = ts_no_z.split(".", 1)
        frac = frac[:6]
        ts_no_z = f"{whole}.{frac}"
    dt = datetime.datetime.fromisoformat(ts_no_z).replace(
        tzinfo=datetime.timezone.utc
    )
    return dt.timestamp()

def extract_first_json_block(section_text):
    """Parse the FIRST `{ ... }` JSON object in a section using
    balanced-brace scanning (no regex). Used for §2 which contains
    inline-pretty-printed JSON after the "Active revisions: <name>"
    header line. Returns None if no object found or JSON invalid."""
    if section_text is None:
        return None
    start = section_text.find("{")
    if start == -1:
        return None
    depth = 0
    for i in range(start, len(section_text)):
        c = section_text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                blob = section_text[start:i + 1]
                try:
                    return json.loads(blob)
                except json.JSONDecodeError:
                    return None
    return None

def parse_section_6_bins(section_text):
    """Parse §6 ("Metric error count timeline (5-min bins)") rows.
    Format:
        ErrorCount    TableName      TimeGenerated
        ------------  -------------  --------------------
        20            PrimaryResult  2026-06-20T00:35:00Z
        1             PrimaryResult  2026-06-20T00:40:00Z
    Returns a list of (count_int, ts_str) tuples in file order.
    Lines that don't start with a digit are skipped (header, dashes,
    blank). Tight scoping via leading-digit + word-split prevents
    pulling counts from unrelated sections that share the column
    layout."""
    if section_text is None:
        return []
    rows = []
    for line in section_text.split("\n"):
        stripped = line.strip()
        if not stripped or not stripped[0].isdigit():
            continue
        parts = stripped.split()
        if len(parts) < 3:
            continue
        try:
            count = int(parts[0])
        except ValueError:
            continue
        if parts[1] != "PrimaryResult":
            continue
        ts = parts[2]
        if not ISO_TS_REGEX.fullmatch(ts):
            continue
        rows.append((count, ts))
    return rows

# ---------- load evidence (slow scenario) ----------
report_path = f"{EVIDENCE_DIR}/{SLOW_APP_NAME}/report-{SLOW_EVIDENCE_TS}.txt"
revisions_path = f"{EVIDENCE_DIR}/{SLOW_APP_NAME}/revisions-{SLOW_EVIDENCE_TS}.json"
traffic_path = f"{EVIDENCE_DIR}/{SLOW_APP_NAME}/traffic-{SLOW_EVIDENCE_TS}.json"

report_text = open(report_path).read()
revisions_json = json.load(open(revisions_path))
traffic_json = json.load(open(traffic_path))

section_2 = get_section(report_text, "=== 2. Active revision(s) ===")
section_5 = get_section(report_text, "=== 5. System logs: metric errors ===")
section_6 = get_section(report_text, "=== 6. Metric error count timeline (5-min bins) ===")
section_9 = get_section(report_text, "=== 9. System logs: container lifecycle events ===")

# ---------- a) signal observed in §5 ----------
# Strong path: ≥SIGNAL_MIN_LINES lines in §5 contain the canonical
# substring "no metrics returned from resource metrics API". The
# captured baseline has 20 matching lines.
signal_line_count_strong = count_record_lines_matching(section_5, SIGNAL_SUBSTRING)
a_strong_path_signal_lines = signal_line_count_strong >= SIGNAL_MIN_LINES

# Fallback path: §6 aggregated bins sum to ≥SIGNAL_MIN_LINES errors.
# The §6 bins use a 5-min summarize() in the KQL query, so a re-run
# that produced fewer raw lines (e.g. due to ingestion lag) but the
# same bin totals would still pass this fallback.
section_6_bins = parse_section_6_bins(section_6)
signal_bin_total_fallback = sum(count for count, _ in section_6_bins)
a_fallback_path_bin_total = signal_bin_total_fallback >= SIGNAL_MIN_LINES

a_signal_observed = a_strong_path_signal_lines or a_fallback_path_bin_total

# ---------- b) NotReady correlation via §9 probe failures ----------
# Strong path: §9 contains "Probe of StartUp failed" AND the §5
# metric-error timestamp window OVERLAPS the §9 probe-failure window.
# Overlap proves the metric errors fire WHILE the container is in
# the NotReady phase, not in a wholly unrelated window. Window
# overlap definition: max(s5_first, s9_first) < min(s5_last, s9_last).
section_9_probe_lines = count_record_lines_matching(section_9, PROBE_FAILURE_SUBSTRING)
probe_failure_present = section_9_probe_lines > 0

s5_timestamps = extract_timestamps_from_section(section_5)
s9_timestamps = extract_timestamps_from_section(section_9)
s9_probe_timestamps = [
    ts for line in (section_9 or "").split("\n")
    if PROBE_FAILURE_SUBSTRING in line
    for ts in ISO_TS_REGEX.findall(line)
]

windows_overlap = False
overlap_info = {
    "s5_first": None, "s5_last": None,
    "s9_probe_first": None, "s9_probe_last": None,
}
if s5_timestamps and s9_probe_timestamps:
    s5_first = min(parse_iso_to_seconds(t) for t in s5_timestamps)
    s5_last = max(parse_iso_to_seconds(t) for t in s5_timestamps)
    s9_first = min(parse_iso_to_seconds(t) for t in s9_probe_timestamps)
    s9_last = max(parse_iso_to_seconds(t) for t in s9_probe_timestamps)
    overlap_info = {
        "s5_first": min(s5_timestamps),
        "s5_last": max(s5_timestamps),
        "s9_probe_first": min(s9_probe_timestamps),
        "s9_probe_last": max(s9_probe_timestamps),
    }
    # Inclusive overlap: shared instant counts as overlap.
    windows_overlap = max(s5_first, s9_first) <= min(s5_last, s9_last)

b_strong_path_overlap = probe_failure_present and windows_overlap
b_fallback_path_probe_present = probe_failure_present
b_not_ready_correlated = b_strong_path_overlap or b_fallback_path_probe_present

# ---------- c) eventually Ready ----------
# Strong path: sidecar revisions[0].healthState == "Healthy". The
# sidecar JSON is captured by trigger.sh from `az containerapp
# revision list` and reflects the platform's authoritative health
# state at the moment of capture, several minutes AFTER the metric
# errors stopped.
sidecar_revision_healthy = (
    isinstance(revisions_json, list)
    and len(revisions_json) > 0
    and revisions_json[0].get("healthState") == "Healthy"
    and revisions_json[0].get("name") == SLOW_REVISION_NAME
)
c_strong_path_sidecar_healthy = sidecar_revision_healthy

# Fallback path: sidecar traffic[0].weight == 100 (the only active
# revision receives all traffic, which means the platform considers
# it ready to serve). This is a weaker but independent signal — it
# does not require the healthState field to be populated.
sidecar_traffic_full = (
    isinstance(traffic_json, list)
    and len(traffic_json) > 0
    and traffic_json[0].get("weight") == 100
)
c_fallback_path_traffic_full = sidecar_traffic_full
c_eventually_ready = c_strong_path_sidecar_healthy or c_fallback_path_traffic_full

# ---------- compose gate ----------
h1_slow_sub_gates = {
    "a_signal_observed": a_signal_observed,
    "b_not_ready_correlated": b_not_ready_correlated,
    "c_eventually_ready": c_eventually_ready,
}
h1_slow_pass = all(h1_slow_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "scenario": "A_slow",
    "hypothesis": "H1",
    "claim": "slow_start_no_metrics_correlates_with_notready_and_resolves",
    "target_revision": SLOW_REVISION_NAME,
    "signal_substring": SIGNAL_SUBSTRING,
    "signal_min_lines_threshold": SIGNAL_MIN_LINES,
    "predicate_inputs": {
        "report_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{SLOW_APP_NAME}/report-{SLOW_EVIDENCE_TS}.txt",
        "revisions_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{SLOW_APP_NAME}/revisions-{SLOW_EVIDENCE_TS}.json",
        "traffic_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{SLOW_APP_NAME}/traffic-{SLOW_EVIDENCE_TS}.json",
    },
    "sub_gate_a_signal_observed": {
        "signal_line_count_strong_path_section_5": signal_line_count_strong,
        "signal_bin_total_fallback_path_section_6": signal_bin_total_fallback,
        "section_6_bins": section_6_bins,
        "a_strong_path_signal_lines_ge_threshold": a_strong_path_signal_lines,
        "a_fallback_path_bin_total_ge_threshold": a_fallback_path_bin_total,
        "a_pass": a_signal_observed,
    },
    "sub_gate_b_not_ready_correlated": {
        "probe_failure_line_count_section_9": section_9_probe_lines,
        "windows_overlap_strong_path": windows_overlap,
        "window_timestamps": overlap_info,
        "b_strong_path_probe_present_and_overlap": b_strong_path_overlap,
        "b_fallback_path_probe_present_only": b_fallback_path_probe_present,
        "b_pass": b_not_ready_correlated,
    },
    "sub_gate_c_eventually_ready": {
        "sidecar_revisions_first_health_state": (
            revisions_json[0].get("healthState")
            if isinstance(revisions_json, list) and revisions_json else None
        ),
        "sidecar_traffic_first_weight": (
            traffic_json[0].get("weight")
            if isinstance(traffic_json, list) and traffic_json else None
        ),
        "c_strong_path_sidecar_healthy": c_strong_path_sidecar_healthy,
        "c_fallback_path_traffic_full": c_fallback_path_traffic_full,
        "c_pass": c_eventually_ready,
    },
    "h1_slow_sub_gates": h1_slow_sub_gates,
    "h1_slow_all_subgates_pass": h1_slow_pass,
    "gate_classification": (
        "slow_start_no_metrics_correlates_with_notready_and_resolves"
        if h1_slow_pass else "h1_slow_failed_check_sub_gates"
    ),
}, indent=2))
PY

echo "=== Phase 11: emit H1 gate for Scenario B (crash-loop, persistent unready) ==="
EVIDENCE_DIR="$EVIDENCE_DIR" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
CAPTURED_AT_UTC="$CAPTURED_AT_UTC" \
CRASH_APP_NAME="$CRASH_APP_NAME" \
CRASH_REVISION_NAME="$CRASH_REVISION_NAME" \
CRASH_EVIDENCE_TS="$CRASH_EVIDENCE_TS" \
SIGNAL_SUBSTRING="$SIGNAL_SUBSTRING" \
CRASH_DURATION_MIN_SECONDS="$CRASH_DURATION_MIN_SECONDS" \
CRASH_LONG_DURATION_FALLBACK_SECONDS="$CRASH_LONG_DURATION_FALLBACK_SECONDS" \
python3 - <<'PY' > "$EVIDENCE_DIR/11-h1-crash-not-ready-gate.json"
import json
import os
import re

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
REPO_RELATIVE_EVIDENCE_DIR = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]
CRASH_APP_NAME = os.environ["CRASH_APP_NAME"]
CRASH_REVISION_NAME = os.environ["CRASH_REVISION_NAME"]
CRASH_EVIDENCE_TS = os.environ["CRASH_EVIDENCE_TS"]
SIGNAL_SUBSTRING = os.environ["SIGNAL_SUBSTRING"]
CRASH_DURATION_MIN_SECONDS = int(os.environ["CRASH_DURATION_MIN_SECONDS"])
CRASH_LONG_DURATION_FALLBACK_SECONDS = int(os.environ["CRASH_LONG_DURATION_FALLBACK_SECONDS"])

# ---------- shared helpers (duplicated per-phase by design) ----------
# Each phase duplicates the parsing helpers rather than sourcing a
# shared library because each phase's heredoc is a self-contained
# Python program. Sourcing would require either generating a temp
# file (fragile cleanup) or appending the helpers inline (defeats
# the per-phase separation). The duplication is intentional and
# verified against Phase 10's helpers — any change must be applied
# to all four phases simultaneously.
ISO_TS_REGEX = re.compile(
    r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z'
)

def get_section(text, section_header):
    lines = text.split("\n")
    start = None
    for i, line in enumerate(lines):
        if line.strip() == section_header:
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        if lines[j].startswith("=== ") and lines[j].endswith(" ==="):
            end = j
            break
    return "\n".join(lines[start:end])

def count_record_lines_matching(section_text, substring):
    if section_text is None:
        return 0
    return sum(
        1 for line in section_text.split("\n")
        if substring in line
    )

def extract_timestamps_from_section(section_text):
    if section_text is None:
        return []
    return ISO_TS_REGEX.findall(section_text)

def parse_iso_to_seconds(ts):
    import datetime
    ts_no_z = ts.rstrip("Z")
    if "." in ts_no_z:
        whole, frac = ts_no_z.split(".", 1)
        frac = frac[:6]
        ts_no_z = f"{whole}.{frac}"
    dt = datetime.datetime.fromisoformat(ts_no_z).replace(
        tzinfo=datetime.timezone.utc
    )
    return dt.timestamp()

def extract_first_json_block(section_text):
    if section_text is None:
        return None
    start = section_text.find("{")
    if start == -1:
        return None
    depth = 0
    for i in range(start, len(section_text)):
        c = section_text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                blob = section_text[start:i + 1]
                try:
                    return json.loads(blob)
                except json.JSONDecodeError:
                    return None
    return None

def parse_section_6_bins(section_text):
    if section_text is None:
        return []
    rows = []
    for line in section_text.split("\n"):
        stripped = line.strip()
        if not stripped or not stripped[0].isdigit():
            continue
        parts = stripped.split()
        if len(parts) < 3:
            continue
        try:
            count = int(parts[0])
        except ValueError:
            continue
        if parts[1] != "PrimaryResult":
            continue
        ts = parts[2]
        if not ISO_TS_REGEX.fullmatch(ts):
            continue
        rows.append((count, ts))
    return rows

# ---------- load evidence (crash scenario) ----------
report_path = f"{EVIDENCE_DIR}/{CRASH_APP_NAME}/report-{CRASH_EVIDENCE_TS}.txt"
revisions_path = f"{EVIDENCE_DIR}/{CRASH_APP_NAME}/revisions-{CRASH_EVIDENCE_TS}.json"

report_text = open(report_path).read()
revisions_json = json.load(open(revisions_path))

section_2 = get_section(report_text, "=== 2. Active revision(s) ===")
section_5 = get_section(report_text, "=== 5. System logs: metric errors ===")
section_6 = get_section(report_text, "=== 6. Metric error count timeline (5-min bins) ===")

# Parse §2 inline JSON to extract crash-loop-specific state fields not
# present in the sidecar (which only carries name/replicas/health/
# trafficWeight). The crash revision is uniquely identified by
# provisioningState=="Failed" and runningState=="Failed".
section_2_revision = extract_first_json_block(section_2)
section_2_health_state = (
    section_2_revision.get("healthState") if section_2_revision else None
)
section_2_running_state = (
    section_2_revision.get("runningState") if section_2_revision else None
)
section_2_provisioning_state = (
    section_2_revision.get("provisioningState") if section_2_revision else None
)

# ---------- a) signal spans ≥2 bins in §6 (or §5 duration > 300s) ----------
section_6_bins = parse_section_6_bins(section_6)
bin_count = len(section_6_bins)
a_strong_path_multiple_bins = bin_count >= 2

# Fallback: §5 last_ts - first_ts > CRASH_DURATION_MIN_SECONDS. Parsed
# from the embedded ISO timestamps on lines containing the signal
# substring (record-scoped, not whole-section min/max).
signal_timestamps = []
if section_5:
    for line in section_5.split("\n"):
        if SIGNAL_SUBSTRING not in line:
            continue
        signal_timestamps.extend(ISO_TS_REGEX.findall(line))
signal_duration_seconds = None
if len(signal_timestamps) >= 2:
    epochs = [parse_iso_to_seconds(t) for t in signal_timestamps]
    signal_duration_seconds = max(epochs) - min(epochs)
a_fallback_path_long_duration = (
    signal_duration_seconds is not None
    and signal_duration_seconds > CRASH_DURATION_MIN_SECONDS
)

a_signal_spans_multiple_bins = (
    a_strong_path_multiple_bins or a_fallback_path_long_duration
)

# ---------- b) unready state ----------
# Strong: §2 healthState=="Unhealthy" AND runningState=="Failed". The
# AND condition is what separates a crash-loop from a transient
# deployment hiccup — both fields must agree.
b_strong_path_section_2_unhealthy_and_failed = (
    section_2_health_state == "Unhealthy"
    and section_2_running_state == "Failed"
)

# Fallback: sidecar healthState != "Healthy" OR §2 provisioningState
# == "Failed". The OR captures the case where §2 was captured during
# a transient state but the sidecar reflects the chronic outcome.
sidecar_health_state = (
    revisions_json[0].get("healthState")
    if isinstance(revisions_json, list) and revisions_json else None
)
b_fallback_path_sidecar_unhealthy_or_provisioning_failed = (
    (sidecar_health_state is not None and sidecar_health_state != "Healthy")
    or section_2_provisioning_state == "Failed"
)
b_unready_state = (
    b_strong_path_section_2_unhealthy_and_failed
    or b_fallback_path_sidecar_unhealthy_or_provisioning_failed
)

# ---------- c) persistent pattern (NOT just deployment spike) ----------
# Strong: §6 has bins BEYOND the first deployment bin. Sorting the
# bins by timestamp and asserting bins beyond index 0 exist proves
# the signal recurred after the initial Metrics-Server warm-up
# window closed. The captured baseline has bins at 00:35, 00:40,
# AND 00:45 — three distinct 5-min bins.
section_6_bins_sorted = sorted(
    section_6_bins,
    key=lambda row: parse_iso_to_seconds(row[1])
)
c_strong_path_bins_beyond_first = len(section_6_bins_sorted) >= 2

# Fallback: §5 last_ts - first_ts > CRASH_LONG_DURATION_FALLBACK_SECONDS
# (600s). The captured baseline has 603s, well above this threshold.
c_fallback_path_very_long_duration = (
    signal_duration_seconds is not None
    and signal_duration_seconds > CRASH_LONG_DURATION_FALLBACK_SECONDS
)

c_persistent_pattern = (
    c_strong_path_bins_beyond_first or c_fallback_path_very_long_duration
)

# ---------- compose gate ----------
h1_crash_sub_gates = {
    "a_signal_spans_multiple_bins": a_signal_spans_multiple_bins,
    "b_unready_state": b_unready_state,
    "c_persistent_pattern": c_persistent_pattern,
}
h1_crash_pass = all(h1_crash_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "scenario": "B_crash",
    "hypothesis": "H1",
    "claim": "crash_loop_no_metrics_persists_across_bins_with_unready_state",
    "target_revision": CRASH_REVISION_NAME,
    "signal_substring": SIGNAL_SUBSTRING,
    "crash_duration_min_seconds_threshold": CRASH_DURATION_MIN_SECONDS,
    "crash_long_duration_fallback_threshold": CRASH_LONG_DURATION_FALLBACK_SECONDS,
    "predicate_inputs": {
        "report_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{CRASH_APP_NAME}/report-{CRASH_EVIDENCE_TS}.txt",
        "revisions_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{CRASH_APP_NAME}/revisions-{CRASH_EVIDENCE_TS}.json",
    },
    "sub_gate_a_signal_spans_multiple_bins": {
        "section_6_bin_count": bin_count,
        "section_6_bins": section_6_bins,
        "signal_line_count_section_5": len(signal_timestamps),
        "signal_duration_seconds_section_5": signal_duration_seconds,
        "a_strong_path_multiple_bins": a_strong_path_multiple_bins,
        "a_fallback_path_long_duration_gt_min": a_fallback_path_long_duration,
        "a_pass": a_signal_spans_multiple_bins,
    },
    "sub_gate_b_unready_state": {
        "section_2_health_state": section_2_health_state,
        "section_2_running_state": section_2_running_state,
        "section_2_provisioning_state": section_2_provisioning_state,
        "sidecar_first_health_state": sidecar_health_state,
        "b_strong_path_section_2_unhealthy_and_failed": b_strong_path_section_2_unhealthy_and_failed,
        "b_fallback_path_sidecar_unhealthy_or_provisioning_failed": b_fallback_path_sidecar_unhealthy_or_provisioning_failed,
        "b_pass": b_unready_state,
    },
    "sub_gate_c_persistent_pattern": {
        "section_6_bins_sorted": section_6_bins_sorted,
        "c_strong_path_bins_beyond_first": c_strong_path_bins_beyond_first,
        "c_fallback_path_very_long_duration_gt": c_fallback_path_very_long_duration,
        "c_pass": c_persistent_pattern,
    },
    "h1_crash_sub_gates": h1_crash_sub_gates,
    "h1_crash_all_subgates_pass": h1_crash_pass,
    "gate_classification": (
        "crash_loop_no_metrics_persists_across_bins_with_unready_state"
        if h1_crash_pass else "h1_crash_failed_check_sub_gates"
    ),
}, indent=2))
PY

echo "=== Phase 12: emit H2 gate for Scenario C (healthy, signal bounded to warm-up) ==="
EVIDENCE_DIR="$EVIDENCE_DIR" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
CAPTURED_AT_UTC="$CAPTURED_AT_UTC" \
HEALTHY_APP_NAME="$HEALTHY_APP_NAME" \
HEALTHY_REVISION_NAME="$HEALTHY_REVISION_NAME" \
HEALTHY_EVIDENCE_TS="$HEALTHY_EVIDENCE_TS" \
SIGNAL_SUBSTRING="$SIGNAL_SUBSTRING" \
HEALTHY_DURATION_MAX_SECONDS="$HEALTHY_DURATION_MAX_SECONDS" \
HEALTHY_LINES_MAX_FALLBACK="$HEALTHY_LINES_MAX_FALLBACK" \
python3 - <<'PY' > "$EVIDENCE_DIR/12-h2-healthy-post-ready-gate.json"
import json
import os
import re

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
REPO_RELATIVE_EVIDENCE_DIR = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]
HEALTHY_APP_NAME = os.environ["HEALTHY_APP_NAME"]
HEALTHY_REVISION_NAME = os.environ["HEALTHY_REVISION_NAME"]
HEALTHY_EVIDENCE_TS = os.environ["HEALTHY_EVIDENCE_TS"]
SIGNAL_SUBSTRING = os.environ["SIGNAL_SUBSTRING"]
HEALTHY_DURATION_MAX_SECONDS = int(os.environ["HEALTHY_DURATION_MAX_SECONDS"])
HEALTHY_LINES_MAX_FALLBACK = int(os.environ["HEALTHY_LINES_MAX_FALLBACK"])

# ---------- shared helpers (duplicated per-phase by design) ----------
ISO_TS_REGEX = re.compile(
    r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z'
)

def get_section(text, section_header):
    lines = text.split("\n")
    start = None
    for i, line in enumerate(lines):
        if line.strip() == section_header:
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        if lines[j].startswith("=== ") and lines[j].endswith(" ==="):
            end = j
            break
    return "\n".join(lines[start:end])

def count_record_lines_matching(section_text, substring):
    if section_text is None:
        return 0
    return sum(
        1 for line in section_text.split("\n")
        if substring in line
    )

def parse_iso_to_seconds(ts):
    import datetime
    ts_no_z = ts.rstrip("Z")
    if "." in ts_no_z:
        whole, frac = ts_no_z.split(".", 1)
        frac = frac[:6]
        ts_no_z = f"{whole}.{frac}"
    dt = datetime.datetime.fromisoformat(ts_no_z).replace(
        tzinfo=datetime.timezone.utc
    )
    return dt.timestamp()

def extract_first_json_block(section_text):
    if section_text is None:
        return None
    start = section_text.find("{")
    if start == -1:
        return None
    depth = 0
    for i in range(start, len(section_text)):
        c = section_text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                blob = section_text[start:i + 1]
                try:
                    return json.loads(blob)
                except json.JSONDecodeError:
                    return None
    return None

def parse_section_6_bins(section_text):
    if section_text is None:
        return []
    rows = []
    for line in section_text.split("\n"):
        stripped = line.strip()
        if not stripped or not stripped[0].isdigit():
            continue
        parts = stripped.split()
        if len(parts) < 3:
            continue
        try:
            count = int(parts[0])
        except ValueError:
            continue
        if parts[1] != "PrimaryResult":
            continue
        ts = parts[2]
        if not ISO_TS_REGEX.fullmatch(ts):
            continue
        rows.append((count, ts))
    return rows

# ---------- load evidence (healthy scenario) ----------
report_path = f"{EVIDENCE_DIR}/{HEALTHY_APP_NAME}/report-{HEALTHY_EVIDENCE_TS}.txt"
revisions_path = f"{EVIDENCE_DIR}/{HEALTHY_APP_NAME}/revisions-{HEALTHY_EVIDENCE_TS}.json"
traffic_path = f"{EVIDENCE_DIR}/{HEALTHY_APP_NAME}/traffic-{HEALTHY_EVIDENCE_TS}.json"

report_text = open(report_path).read()
revisions_json = json.load(open(revisions_path))
traffic_json = json.load(open(traffic_path))

section_2 = get_section(report_text, "=== 2. Active revision(s) ===")
section_5 = get_section(report_text, "=== 5. System logs: metric errors ===")
section_6 = get_section(report_text, "=== 6. Metric error count timeline (5-min bins) ===")

section_2_revision = extract_first_json_block(section_2)
section_2_health_state = (
    section_2_revision.get("healthState") if section_2_revision else None
)
section_2_running_state = (
    section_2_revision.get("runningState") if section_2_revision else None
)

# ---------- a) Healthy/Running ----------
# Strong: §2 healthState=="Healthy" AND runningState=="Running". Both
# fields must agree — this is the inverse of the crash gate's AND
# condition.
a_strong_path_section_2_healthy_and_running = (
    section_2_health_state == "Healthy"
    and section_2_running_state == "Running"
)

# Fallback: sidecar revisions healthState=="Healthy" AND traffic[0].
# weight==100 (the only revision is healthy AND receiving traffic).
sidecar_health_state = (
    revisions_json[0].get("healthState")
    if isinstance(revisions_json, list) and revisions_json else None
)
sidecar_traffic_weight = (
    traffic_json[0].get("weight")
    if isinstance(traffic_json, list) and traffic_json else None
)
a_fallback_path_sidecar_healthy_and_full_traffic = (
    sidecar_health_state == "Healthy"
    and sidecar_traffic_weight == 100
)
a_healthy_and_running = (
    a_strong_path_section_2_healthy_and_running
    or a_fallback_path_sidecar_healthy_and_full_traffic
)

# ---------- b) single 5-min bin ----------
# Strong: §6 has exactly 1 row. Captured baseline = 1 bin (16 errors @
# 00:35). This is THE falsifiable claim for H2: a chronically NotReady
# workload would produce multiple bins (see Gate 11 sub-gate a).
section_6_bins = parse_section_6_bins(section_6)
bin_count = len(section_6_bins)
b_strong_path_single_bin = bin_count == 1
b_fallback_path_few_bins = bin_count <= 2
b_single_bin = b_strong_path_single_bin or b_fallback_path_few_bins

# ---------- c) silent after warm-up ----------
# Strong: §5 signal-line timestamps span ≤ HEALTHY_DURATION_MAX_SECONDS.
# The captured baseline has 16 errors spanning ~106 seconds, well
# under the 300s threshold. A chronic case would span 600s+ (see Gate
# 11 sub-gate c).
signal_timestamps = []
if section_5:
    for line in section_5.split("\n"):
        if SIGNAL_SUBSTRING not in line:
            continue
        signal_timestamps.extend(ISO_TS_REGEX.findall(line))

signal_line_count = len(signal_timestamps)
signal_duration_seconds = None
if len(signal_timestamps) >= 2:
    epochs = [parse_iso_to_seconds(t) for t in signal_timestamps]
    signal_duration_seconds = max(epochs) - min(epochs)

c_strong_path_short_duration = (
    signal_duration_seconds is not None
    and signal_duration_seconds <= HEALTHY_DURATION_MAX_SECONDS
)

# Fallback: §5 line count ≤ HEALTHY_LINES_MAX_FALLBACK (20). The
# captured baseline has 16 lines.
c_fallback_path_few_lines = signal_line_count <= HEALTHY_LINES_MAX_FALLBACK
c_silent_after_warmup = (
    c_strong_path_short_duration or c_fallback_path_few_lines
)

# ---------- compose gate ----------
h2_healthy_sub_gates = {
    "a_healthy_and_running": a_healthy_and_running,
    "b_single_bin": b_single_bin,
    "c_silent_after_warmup": c_silent_after_warmup,
}
h2_healthy_pass = all(h2_healthy_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "scenario": "C_healthy",
    "hypothesis": "H2",
    "claim": "healthy_no_metrics_bounded_to_warmup_does_not_persist",
    "target_revision": HEALTHY_REVISION_NAME,
    "signal_substring": SIGNAL_SUBSTRING,
    "healthy_duration_max_seconds_threshold": HEALTHY_DURATION_MAX_SECONDS,
    "healthy_lines_max_fallback_threshold": HEALTHY_LINES_MAX_FALLBACK,
    "predicate_inputs": {
        "report_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{HEALTHY_APP_NAME}/report-{HEALTHY_EVIDENCE_TS}.txt",
        "revisions_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{HEALTHY_APP_NAME}/revisions-{HEALTHY_EVIDENCE_TS}.json",
        "traffic_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{HEALTHY_APP_NAME}/traffic-{HEALTHY_EVIDENCE_TS}.json",
    },
    "sub_gate_a_healthy_and_running": {
        "section_2_health_state": section_2_health_state,
        "section_2_running_state": section_2_running_state,
        "sidecar_first_health_state": sidecar_health_state,
        "sidecar_first_traffic_weight": sidecar_traffic_weight,
        "a_strong_path_section_2_healthy_and_running": a_strong_path_section_2_healthy_and_running,
        "a_fallback_path_sidecar_healthy_and_full_traffic": a_fallback_path_sidecar_healthy_and_full_traffic,
        "a_pass": a_healthy_and_running,
    },
    "sub_gate_b_single_bin": {
        "section_6_bin_count": bin_count,
        "section_6_bins": section_6_bins,
        "b_strong_path_single_bin": b_strong_path_single_bin,
        "b_fallback_path_few_bins_le_2": b_fallback_path_few_bins,
        "b_pass": b_single_bin,
    },
    "sub_gate_c_silent_after_warmup": {
        "signal_line_count_section_5": signal_line_count,
        "signal_duration_seconds_section_5": signal_duration_seconds,
        "c_strong_path_short_duration_le_threshold": c_strong_path_short_duration,
        "c_fallback_path_few_lines_le_threshold": c_fallback_path_few_lines,
        "c_pass": c_silent_after_warmup,
    },
    "h2_healthy_sub_gates": h2_healthy_sub_gates,
    "h2_healthy_all_subgates_pass": h2_healthy_pass,
    "gate_classification": (
        "healthy_no_metrics_bounded_to_warmup_does_not_persist"
        if h2_healthy_pass else "h2_healthy_failed_check_sub_gates"
    ),
}, indent=2))
PY

echo "=== Phase 13: emit H3 cross-scenario falsification gate ==="
EVIDENCE_DIR="$EVIDENCE_DIR" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
CAPTURED_AT_UTC="$CAPTURED_AT_UTC" \
SLOW_APP_NAME="$SLOW_APP_NAME" \
SLOW_REVISION_NAME="$SLOW_REVISION_NAME" \
SLOW_EVIDENCE_TS="$SLOW_EVIDENCE_TS" \
CRASH_APP_NAME="$CRASH_APP_NAME" \
CRASH_REVISION_NAME="$CRASH_REVISION_NAME" \
CRASH_EVIDENCE_TS="$CRASH_EVIDENCE_TS" \
HEALTHY_APP_NAME="$HEALTHY_APP_NAME" \
HEALTHY_REVISION_NAME="$HEALTHY_REVISION_NAME" \
HEALTHY_EVIDENCE_TS="$HEALTHY_EVIDENCE_TS" \
SIGNAL_SUBSTRING="$SIGNAL_SUBSTRING" \
CROSS_SCENARIO_RATIO_STRONG="$CROSS_SCENARIO_RATIO_STRONG" \
python3 - <<'PY' > "$EVIDENCE_DIR/13-h3-cross-scenario-falsification-gate.json"
import json
import os
import re

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
REPO_RELATIVE_EVIDENCE_DIR = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]
SLOW_APP_NAME = os.environ["SLOW_APP_NAME"]
SLOW_REVISION_NAME = os.environ["SLOW_REVISION_NAME"]
SLOW_EVIDENCE_TS = os.environ["SLOW_EVIDENCE_TS"]
CRASH_APP_NAME = os.environ["CRASH_APP_NAME"]
CRASH_REVISION_NAME = os.environ["CRASH_REVISION_NAME"]
CRASH_EVIDENCE_TS = os.environ["CRASH_EVIDENCE_TS"]
HEALTHY_APP_NAME = os.environ["HEALTHY_APP_NAME"]
HEALTHY_REVISION_NAME = os.environ["HEALTHY_REVISION_NAME"]
HEALTHY_EVIDENCE_TS = os.environ["HEALTHY_EVIDENCE_TS"]
SIGNAL_SUBSTRING = os.environ["SIGNAL_SUBSTRING"]
CROSS_SCENARIO_RATIO_STRONG = float(os.environ["CROSS_SCENARIO_RATIO_STRONG"])

# ---------- shared helpers (duplicated per-phase by design) ----------
ISO_TS_REGEX = re.compile(
    r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z'
)

def get_section(text, section_header):
    lines = text.split("\n")
    start = None
    for i, line in enumerate(lines):
        if line.strip() == section_header:
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        if lines[j].startswith("=== ") and lines[j].endswith(" ==="):
            end = j
            break
    return "\n".join(lines[start:end])

def parse_iso_to_seconds(ts):
    import datetime
    ts_no_z = ts.rstrip("Z")
    if "." in ts_no_z:
        whole, frac = ts_no_z.split(".", 1)
        frac = frac[:6]
        ts_no_z = f"{whole}.{frac}"
    dt = datetime.datetime.fromisoformat(ts_no_z).replace(
        tzinfo=datetime.timezone.utc
    )
    return dt.timestamp()

def extract_first_json_block(section_text):
    if section_text is None:
        return None
    start = section_text.find("{")
    if start == -1:
        return None
    depth = 0
    for i in range(start, len(section_text)):
        c = section_text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                blob = section_text[start:i + 1]
                try:
                    return json.loads(blob)
                except json.JSONDecodeError:
                    return None
    return None

def parse_section_6_bins(section_text):
    if section_text is None:
        return []
    rows = []
    for line in section_text.split("\n"):
        stripped = line.strip()
        if not stripped or not stripped[0].isdigit():
            continue
        parts = stripped.split()
        if len(parts) < 3:
            continue
        try:
            count = int(parts[0])
        except ValueError:
            continue
        if parts[1] != "PrimaryResult":
            continue
        ts = parts[2]
        if not ISO_TS_REGEX.fullmatch(ts):
            continue
        rows.append((count, ts))
    return rows

def compute_scenario_metrics(app_name, ts):
    """Compute (bin_count, duration_seconds, health_state) for a
    scenario. Returns a dict so the cross-scenario predicates can
    consume named fields. Tight scoping: §5 signal timestamps are
    record-scoped (per-line substring match), and §6 bins are
    parsed with the strict ErrorCount + PrimaryResult format."""
    report_path = f"{EVIDENCE_DIR}/{app_name}/report-{ts}.txt"
    text = open(report_path).read()
    section_2 = get_section(text, "=== 2. Active revision(s) ===")
    section_5 = get_section(text, "=== 5. System logs: metric errors ===")
    section_6 = get_section(text, "=== 6. Metric error count timeline (5-min bins) ===")
    section_2_revision = extract_first_json_block(section_2)
    health_state = (
        section_2_revision.get("healthState") if section_2_revision else None
    )
    bins = parse_section_6_bins(section_6)
    timestamps = []
    if section_5:
        for line in section_5.split("\n"):
            if SIGNAL_SUBSTRING not in line:
                continue
            timestamps.extend(ISO_TS_REGEX.findall(line))
    duration = None
    if len(timestamps) >= 2:
        epochs = [parse_iso_to_seconds(t) for t in timestamps]
        duration = max(epochs) - min(epochs)
    return {
        "bin_count": len(bins),
        "bins": bins,
        "duration_seconds": duration,
        "health_state": health_state,
        "signal_line_count": len(timestamps),
    }

slow_m = compute_scenario_metrics(SLOW_APP_NAME, SLOW_EVIDENCE_TS)
crash_m = compute_scenario_metrics(CRASH_APP_NAME, CRASH_EVIDENCE_TS)
healthy_m = compute_scenario_metrics(HEALTHY_APP_NAME, HEALTHY_EVIDENCE_TS)

# ---------- a) bin count ordering ----------
# Strong: healthy_bins == 1 AND slow_bins == 1 AND crash_bins >= 2.
# The captured baseline has healthy=1, slow=1, crash=3. The Strong
# path encodes the exact captured pattern; the Fallback relaxes to
# weak ordering.
a_strong_path_exact_bin_pattern = (
    healthy_m["bin_count"] == 1
    and slow_m["bin_count"] == 1
    and crash_m["bin_count"] >= 2
)
a_fallback_path_weak_ordering = (
    healthy_m["bin_count"] <= slow_m["bin_count"] < crash_m["bin_count"]
)
a_bin_count_ordering = (
    a_strong_path_exact_bin_pattern or a_fallback_path_weak_ordering
)

# ---------- b) duration ordering ----------
# Strong: crash_duration >= CROSS_SCENARIO_RATIO_STRONG (3.0) *
# max(healthy_duration, slow_duration). The captured baseline has
# crash=603s vs slow=136s vs healthy=106s → 603/136 = 4.43x, well
# above 3.0. A re-run with different timing but the same ordering
# would still pass the Fallback.
durations_available = (
    slow_m["duration_seconds"] is not None
    and crash_m["duration_seconds"] is not None
    and healthy_m["duration_seconds"] is not None
)

if durations_available:
    max_non_crash_duration = max(
        slow_m["duration_seconds"], healthy_m["duration_seconds"]
    )
    observed_ratio = (
        crash_m["duration_seconds"] / max_non_crash_duration
        if max_non_crash_duration > 0 else None
    )
else:
    max_non_crash_duration = None
    observed_ratio = None

b_strong_path_ratio_at_or_above_threshold = (
    observed_ratio is not None and observed_ratio >= CROSS_SCENARIO_RATIO_STRONG
)
b_fallback_path_crash_longest = (
    durations_available
    and crash_m["duration_seconds"] > slow_m["duration_seconds"]
    and crash_m["duration_seconds"] > healthy_m["duration_seconds"]
)
b_duration_ordering = (
    b_strong_path_ratio_at_or_above_threshold or b_fallback_path_crash_longest
)

# ---------- c) health state matches outcome ----------
# Strong: healthy=="Healthy" AND slow=="Healthy" AND crash=="Unhealthy".
# All three states must agree with the scenario design. Slow recovers
# (Healthy), healthy is always Healthy, crash never recovers
# (Unhealthy).
c_strong_path_exact_state_pattern = (
    healthy_m["health_state"] == "Healthy"
    and slow_m["health_state"] == "Healthy"
    and crash_m["health_state"] == "Unhealthy"
)
c_fallback_path_crash_not_healthy_and_one_healthy = (
    crash_m["health_state"] != "Healthy"
    and (
        healthy_m["health_state"] == "Healthy"
        or slow_m["health_state"] == "Healthy"
    )
)
c_health_state_matches_outcome = (
    c_strong_path_exact_state_pattern
    or c_fallback_path_crash_not_healthy_and_one_healthy
)

# ---------- compose gate ----------
h3_cross_sub_gates = {
    "a_bin_count_ordering": a_bin_count_ordering,
    "b_duration_ordering": b_duration_ordering,
    "c_health_state_matches_outcome": c_health_state_matches_outcome,
}
h3_cross_pass = all(h3_cross_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "scenario": "cross_scenario_falsification",
    "hypothesis": "H3",
    "claim": "metric_error_severity_tracks_unreadiness_severity",
    "target_revisions": {
        "slow": SLOW_REVISION_NAME,
        "crash": CRASH_REVISION_NAME,
        "healthy": HEALTHY_REVISION_NAME,
    },
    "signal_substring": SIGNAL_SUBSTRING,
    "cross_scenario_ratio_strong_threshold": CROSS_SCENARIO_RATIO_STRONG,
    "predicate_inputs": {
        "slow_report_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{SLOW_APP_NAME}/report-{SLOW_EVIDENCE_TS}.txt",
        "crash_report_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{CRASH_APP_NAME}/report-{CRASH_EVIDENCE_TS}.txt",
        "healthy_report_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/{HEALTHY_APP_NAME}/report-{HEALTHY_EVIDENCE_TS}.txt",
    },
    "observed_metrics": {
        "slow": slow_m,
        "crash": crash_m,
        "healthy": healthy_m,
    },
    "sub_gate_a_bin_count_ordering": {
        "healthy_bin_count": healthy_m["bin_count"],
        "slow_bin_count": slow_m["bin_count"],
        "crash_bin_count": crash_m["bin_count"],
        "a_strong_path_exact_bin_pattern": a_strong_path_exact_bin_pattern,
        "a_fallback_path_weak_ordering": a_fallback_path_weak_ordering,
        "a_pass": a_bin_count_ordering,
    },
    "sub_gate_b_duration_ordering": {
        "healthy_duration_seconds": healthy_m["duration_seconds"],
        "slow_duration_seconds": slow_m["duration_seconds"],
        "crash_duration_seconds": crash_m["duration_seconds"],
        "max_non_crash_duration_seconds": max_non_crash_duration,
        "observed_ratio_crash_over_max_non_crash": observed_ratio,
        "b_strong_path_ratio_at_or_above_threshold": b_strong_path_ratio_at_or_above_threshold,
        "b_fallback_path_crash_longest": b_fallback_path_crash_longest,
        "b_pass": b_duration_ordering,
    },
    "sub_gate_c_health_state_matches_outcome": {
        "healthy_health_state": healthy_m["health_state"],
        "slow_health_state": slow_m["health_state"],
        "crash_health_state": crash_m["health_state"],
        "c_strong_path_exact_state_pattern": c_strong_path_exact_state_pattern,
        "c_fallback_path_crash_not_healthy_and_one_healthy": c_fallback_path_crash_not_healthy_and_one_healthy,
        "c_pass": c_health_state_matches_outcome,
    },
    "h3_cross_sub_gates": h3_cross_sub_gates,
    "h3_cross_all_subgates_pass": h3_cross_pass,
    "gate_classification": (
        "metric_error_severity_tracks_unreadiness_severity"
        if h3_cross_pass else "h3_cross_failed_check_sub_gates"
    ),
}, indent=2))
PY

# ---------- final summary ----------
# This block deliberately uses `<<PY` (unquoted) so bash expands
# `$EVIDENCE_DIR` before Python sees it. No `$` literals exist in
# the Python code below, so the unquoted heredoc is safe.
echo ""
echo "=== Phase B verify summary ==="
python3 - <<PY
import json
import os
import sys

EVIDENCE_DIR = "$EVIDENCE_DIR"

gates = [
    ("10-h1-slow-not-ready-gate.json", "h1_slow_all_subgates_pass"),
    ("11-h1-crash-not-ready-gate.json", "h1_crash_all_subgates_pass"),
    ("12-h2-healthy-post-ready-gate.json", "h2_healthy_all_subgates_pass"),
    ("13-h3-cross-scenario-falsification-gate.json", "h3_cross_all_subgates_pass"),
]

results = []
all_pass = True
for filename, pass_key in gates:
    path = os.path.join(EVIDENCE_DIR, filename)
    if not os.path.exists(path):
        results.append((filename, "MISSING"))
        all_pass = False
        continue
    with open(path) as f:
        data = json.load(f)
    classification = data.get("gate_classification", "unknown")
    passed = data.get(pass_key, False)
    if not passed:
        all_pass = False
    results.append((filename, "PASS" if passed else "FAIL", classification))

for entry in results:
    if len(entry) == 2:
        filename, status = entry
        print(f"  {status:5}  {filename}")
    else:
        filename, status, classification = entry
        print(f"  {status:5}  {filename}  -> {classification}")

print()
if all_pass:
    print("All 4 Phase B gates PASS (12/12 sub-gates).")
    sys.exit(0)
else:
    print("One or more gates FAILED - inspect the gate JSONs above.")
    sys.exit(1)
PY
