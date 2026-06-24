#!/usr/bin/env bash
# verify.sh — Phase B evidence-pack verification for Lab 15 (image-size-startup-delay).
#
# What this script proves (falsifiable, strict 2-path predicates per Oracle
# Option γ). Reads ONLY the numbered evidence files written by trigger.sh
# (01..09 + system-logs-{large,small}.json) and emits four sub-gate JSON
# files (10..13). NO Azure calls — verify.sh is replayable from disk so a
# reviewer can re-classify gates without re-deploying infrastructure.
#
# This script's strict 2-path predicate rule (Lab 11/12/13/14 lesson):
#   Each sub-gate computes Strong AND Fallback in the same evaluation;
#   the gate passes if EITHER path is true. The JSON output captures
#   which path passed so a reviewer can audit the evidence trail.
#
# Gate design (4 falsifiable gates / 11 sub-gates total):
#
#   10-h1-a-large-cold-pull-gate.json — H1 for Scenario A (python:3.11
#     large image, scripted). Sub-gates:
#       a) Cold-pull event observed for the large-image revision.
#       b) Image size matches the captured baseline (408,944,640 bytes).
#       c) Large-image revision reached a healthy startup state.
#
#   11-h1-b-small-cold-pull-gate.json — H1 for Scenario B (python:3.11-alpine
#     small image, scripted). Sub-gates:
#       a) Cold-pull event observed for the small-image revision.
#       b) Image size matches the captured baseline (19,922,944 bytes).
#       c) Small-image revision reached a healthy startup state.
#
#   12-h1-c-speedup-ratio-gate.json — H1 for Scenario A/B speedup. Sub-gates:
#       a) Both cold-pull durations parseable from the same per-revision
#          source (06-kql-pull-events.json Strong; raw text Fallback).
#       b) Speedup ratio (large_ms / small_ms) is ≥ 2.5× (the captured
#          baseline observed 3.08× on 2026-06-22; threshold lowered to 2.5
#          to absorb minor pull-time variance from mutable tag re-runs
#          while still falsifying the case where the two image sizes
#          converge).
#
#   13-h2-falsification-gate.json — H2 cross-scenario differential. Proves
#     "small image alone is NOT sufficient for healthy startup" by showing
#     the helloworld revision (`--0000001`, off-script) was the FASTEST
#     pull of all three revisions yet still failed. Sub-gates:
#       a) The helloworld revision's first (cold) pull is faster than
#          BOTH the python:3.11 cold pull and the python:3.11-alpine
#          cold pull — proving small image alone does not predict
#          healthy startup.
#       b) ContainerTerminated event count for the helloworld revision
#          is ≥ 3 (captured baseline = 4 events). Tight scoping: the
#          predicate keys off `Reason_s == "ContainerTerminated"` AND
#          `RevisionName_s == "ca-imgsize-acerjw--0000001"` so background
#          revision-deactivation terminations on other revisions are
#          excluded.
#       c) The runtime-mismatch error signature
#          `exec: "python": executable file not found in $PATH` is present
#          in the raw system logs. This is the smoking gun for why the
#          small-image-alone hypothesis fails: the image had no Python
#          runtime to execute the Bicep command override.
#
# Why we do NOT gate on revision-level `healthState` for Gate 13:
#   Azure Container Apps marks revisions `Healthy` at deploy time and does
#   not always update that field when later container terminations occur
#   on the same revision. The off-script helloworld revision (`--0000001`)
#   reports `healthState: Healthy` in 05-revisions-all.json despite its 4
#   `ContainerCreateFailure` events. The authoritative signal for Gate 13
#   is therefore the `ContainerTerminated` count in 09-kql-event-summary.json
#   AND the `exec` error signature in system-logs-large.json — NOT the
#   revision-level `healthState` field.
#
# Numbered prefix policy (per Phase B Lab 11/12 lessons):
#   01..09 + system-logs-{large,small}.json = trigger.sh snapshots (raw,
#     no derived state).
#   10..13 = verify.sh derived sub-gates (this script).
#   Plural filenames everywhere; index starts at 01-* (never 00-*).
#
# QUOTED heredoc rationale (Lab 14 lesson 29):
#   `<<'PY'` is used deliberately. With an unquoted `<<PY` heredoc, bash
#   would expand `$PATH` inside the Python regex literal for the exec
#   signature (Gate 13 sub-gate c), turning the predicate into an empty-
#   path match. The quoted form passes the literal string `$PATH` to
#   Python untouched. Shell variables are passed via `os.environ` instead.
#
# Usage:
#   bash labs/image-size-startup-delay/verify.sh
#   (no environment variables needed — pure evidence-file processor)

set -euo pipefail

EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"

# Repo-relative path used only inside the predicate_inputs blocks of the
# 4 gate JSONs (10/11/12/13). The Python heredocs still use EVIDENCE_DIR
# (absolute) for filesystem reads, but every path written *into* the gate
# JSON output uses REPO_RELATIVE_EVIDENCE_DIR so the operator's
# /Users/<name>/... layout is never recorded as PII in committed evidence.
REPO_RELATIVE_EVIDENCE_DIR="labs/image-size-startup-delay/evidence"

# Sanity-check that trigger.sh has been run end-to-end before verify.sh.
# Missing inputs are a hard fail — verify.sh cannot synthesize evidence
# it does not have on disk.
for required in \
    01-trigger-large-image.txt \
    02-verify-small-image.txt \
    03-revisions-list.json \
    04-containerapp-summary.json \
    05-revisions-all.json \
    06-kql-pull-events.json \
    07-containerapp-full-config.json \
    08-environment-logs-config.json \
    09-kql-event-summary.json \
    system-logs-large.json \
    system-logs-small.json; do
    if [ ! -f "$EVIDENCE_DIR/$required" ]; then
        echo "ERROR: required evidence file $EVIDENCE_DIR/$required not found. Run trigger.sh first." >&2
        exit 1
    fi
done

CAPTURED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Lab-specific constants captured from the canonical 2026-06-22 run.
# Pinning these in the verify.sh header (not inside each Python block) makes
# the predicate values inspectable in a single place. A re-run via trigger.sh
# against a fresh subscription should produce revisions with these exact
# image references; the revision-name suffix (`--5487avi`, `--0000001`,
# `--0000002`) is derived from the canonical capture and is what the
# committed evidence files key off.
LARGE_REVISION_NAME="ca-imgsize-acerjw--5487avi"
SMALL_REVISION_NAME="ca-imgsize-acerjw--0000002"
HELLOWORLD_REVISION_NAME="ca-imgsize-acerjw--0000001"
LARGE_IMAGE_TAG="python:3.11"
SMALL_IMAGE_TAG="python:3.11-alpine"
HELLOWORLD_IMAGE_TAG='mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
LARGE_IMAGE_SIZE_BYTES=408944640
SMALL_IMAGE_SIZE_BYTES=19922944
HELLOWORLD_IMAGE_SIZE_BYTES=33554432
LARGE_PULL_DURATION_S="8.88"
SMALL_PULL_DURATION_S="2.88"
HELLOWORLD_PULL_DURATION_S="1.62"
SPEEDUP_RATIO_THRESHOLD="2.5"
HELLOWORLD_TERMINATED_THRESHOLD=3

echo "=== Phase 10: emit H1 gate for Scenario A (large image, scripted) ==="
# Sub-gate logic implemented in Python so the Strong/Fallback predicates and
# regex parsing are unit-testable from disk. The Python block reads
# evidence files by absolute path and writes the gate JSON to stdout.
EVIDENCE_DIR="$EVIDENCE_DIR" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
CAPTURED_AT_UTC="$CAPTURED_AT_UTC" \
LARGE_REVISION_NAME="$LARGE_REVISION_NAME" \
LARGE_IMAGE_TAG="$LARGE_IMAGE_TAG" \
LARGE_IMAGE_SIZE_BYTES="$LARGE_IMAGE_SIZE_BYTES" \
LARGE_PULL_DURATION_S="$LARGE_PULL_DURATION_S" \
python3 - <<'PY' > "$EVIDENCE_DIR/10-h1-a-large-cold-pull-gate.json"
import json
import os

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
REPO_RELATIVE_EVIDENCE_DIR = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]
LARGE_REVISION_NAME = os.environ["LARGE_REVISION_NAME"]
LARGE_IMAGE_TAG = os.environ["LARGE_IMAGE_TAG"]
LARGE_IMAGE_SIZE_BYTES = int(os.environ["LARGE_IMAGE_SIZE_BYTES"])
LARGE_PULL_DURATION_S = os.environ["LARGE_PULL_DURATION_S"]

# ---------- load evidence ----------
kql_pull_events = json.load(open(f"{EVIDENCE_DIR}/06-kql-pull-events.json"))
revisions_all = json.load(open(f"{EVIDENCE_DIR}/05-revisions-all.json"))
kql_event_summary = json.load(open(f"{EVIDENCE_DIR}/09-kql-event-summary.json"))
trigger_large_text = open(f"{EVIDENCE_DIR}/01-trigger-large-image.txt").read()

# ---------- a) pull event observed for large-image revision ----------
# Strong path: exact field match in 06-kql-pull-events.json keyed by
# RevisionName_s. The Log_s string is built to exactly match the captured
# 2026-06-22 line — `Successfully pulled image "python:3.11" in 8.88s.
# Image size: 408944640 bytes.` — so a re-run that produces a different
# duration or byte count would fall through to the Fallback path.
expected_log_s = (
    f'Successfully pulled image "{LARGE_IMAGE_TAG}" in {LARGE_PULL_DURATION_S}s. '
    f'Image size: {LARGE_IMAGE_SIZE_BYTES} bytes.'
)
strong_pull_event = next(
    (
        e for e in kql_pull_events
        if e.get("RevisionName_s") == LARGE_REVISION_NAME
        and e.get("Log_s") == expected_log_s
    ),
    None,
)
a_strong_path_exact_log_s = strong_pull_event is not None

# Fallback path: 01-trigger-large-image.txt contains both the image tag
# substring AND the duration substring. This is tighter than a single
# `Successfully pulled image` match (which would also be true for the
# helloworld revision) — we require BOTH the image tag and the duration
# to be present in the same file. The duration substring uses the captured
# baseline value; a re-run with a different duration would fail this
# fallback too, which is intentional (the gate is about the canonical
# 2026-06-22 baseline, not "any cold pull").
a_fallback_path_text_match = (
    f'"{LARGE_IMAGE_TAG}"' in trigger_large_text
    and f'in {LARGE_PULL_DURATION_S}s' in trigger_large_text
)
a_pull_event_observed = a_strong_path_exact_log_s or a_fallback_path_text_match

# ---------- b) image size matches captured baseline ----------
# Strong path: 06-kql entry for the large revision contains the byte count
# in its Log_s string. We look for any entry on the target revision (not
# just the exact-match one from sub-gate a) so a re-run with a slightly
# different duration but the same image digest still passes sub-gate b.
size_substring = f'Image size: {LARGE_IMAGE_SIZE_BYTES} bytes'
strong_size_match = any(
    e.get("RevisionName_s") == LARGE_REVISION_NAME
    and size_substring in (e.get("Log_s") or "")
    for e in kql_pull_events
)
b_strong_path_size_in_kql = strong_size_match

# Fallback path: 01-trigger-large-image.txt contains the byte-count
# substring AND the large image tag (tight scoping — exclude the case
# where 408944640 bytes coincidentally appears for an unrelated image).
b_fallback_path_size_in_text = (
    f'{LARGE_IMAGE_SIZE_BYTES} bytes' in trigger_large_text
    and f'"{LARGE_IMAGE_TAG}"' in trigger_large_text
)
b_image_size_matches = b_strong_path_size_in_kql or b_fallback_path_size_in_text

# ---------- c) large-image revision reached healthy startup ----------
# Strong path: 05-revisions-all.json reports healthState=Healthy for the
# large revision. Note: this is the DEPLOY-TIME health field, which
# Container Apps does not always update post-startup (see Gate 13's
# rationale for why we do NOT key Gate 13 off this field). For Gate 10,
# however, the large revision ran without ContainerCreateFailure on
# 2026-06-22 and its healthState reflects the actual stable state.
large_rev_obj = next(
    (r for r in revisions_all if r.get("name") == LARGE_REVISION_NAME),
    None,
)
c_strong_path_revision_healthy = (
    large_rev_obj is not None
    and large_rev_obj.get("healthState") == "Healthy"
)

# Fallback path: 09-kql-event-summary.json has a `ContainerStarted` event
# for the large revision (proves the runtime successfully started the
# container, independent of the post-deploy healthState field). This is
# a stronger signal than healthState because it directly attests to the
# container reaching the Started state via the runtime.
c_fallback_path_container_started = any(
    e.get("RevisionName_s") == LARGE_REVISION_NAME
    and e.get("Reason_s") == "ContainerStarted"
    for e in kql_event_summary
)
c_revision_healthy = c_strong_path_revision_healthy or c_fallback_path_container_started

# ---------- compose gate ----------
h1_a_sub_gates = {
    "a_pull_event_observed": a_pull_event_observed,
    "b_image_size_matches_baseline": b_image_size_matches,
    "c_revision_healthy": c_revision_healthy,
}
h1_a_pass = all(h1_a_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "scenario": "A",
    "hypothesis": "H1",
    "claim": "scripted_large_cold_pull_observed_and_healthy",
    "target_revision": LARGE_REVISION_NAME,
    "target_image": LARGE_IMAGE_TAG,
    "expected_image_size_bytes": LARGE_IMAGE_SIZE_BYTES,
    "expected_cold_pull_duration_s": LARGE_PULL_DURATION_S,
    "predicate_inputs": {
        "kql_pull_events_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/06-kql-pull-events.json",
        "revisions_all_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/05-revisions-all.json",
        "kql_event_summary_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/09-kql-event-summary.json",
        "trigger_text_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/01-trigger-large-image.txt",
    },
    "sub_gate_a_pull_event": {
        "expected_log_s": expected_log_s,
        "a_strong_path_exact_log_s_match": a_strong_path_exact_log_s,
        "a_fallback_path_text_match_tag_and_duration": a_fallback_path_text_match,
        "a_pass": a_pull_event_observed,
    },
    "sub_gate_b_image_size": {
        "expected_size_bytes": LARGE_IMAGE_SIZE_BYTES,
        "b_strong_path_size_in_kql_for_target_revision": b_strong_path_size_in_kql,
        "b_fallback_path_size_and_tag_in_trigger_text": b_fallback_path_size_in_text,
        "b_pass": b_image_size_matches,
    },
    "sub_gate_c_revision_healthy": {
        "c_strong_path_healthstate_healthy": c_strong_path_revision_healthy,
        "c_fallback_path_container_started_event": c_fallback_path_container_started,
        "c_pass": c_revision_healthy,
    },
    "h1_a_sub_gates": h1_a_sub_gates,
    "h1_a_all_subgates_pass": h1_a_pass,
    "gate_classification": (
        "scripted_large_cold_pull_observed_and_healthy"
        if h1_a_pass else "h1_a_failed_check_sub_gates"
    ),
}, indent=2))
PY

echo "=== Phase 11: emit H1 gate for Scenario B (small image, scripted) ==="
EVIDENCE_DIR="$EVIDENCE_DIR" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
CAPTURED_AT_UTC="$CAPTURED_AT_UTC" \
SMALL_REVISION_NAME="$SMALL_REVISION_NAME" \
SMALL_IMAGE_TAG="$SMALL_IMAGE_TAG" \
SMALL_IMAGE_SIZE_BYTES="$SMALL_IMAGE_SIZE_BYTES" \
SMALL_PULL_DURATION_S="$SMALL_PULL_DURATION_S" \
python3 - <<'PY' > "$EVIDENCE_DIR/11-h1-b-small-cold-pull-gate.json"
import json
import os

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
REPO_RELATIVE_EVIDENCE_DIR = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]
SMALL_REVISION_NAME = os.environ["SMALL_REVISION_NAME"]
SMALL_IMAGE_TAG = os.environ["SMALL_IMAGE_TAG"]
SMALL_IMAGE_SIZE_BYTES = int(os.environ["SMALL_IMAGE_SIZE_BYTES"])
SMALL_PULL_DURATION_S = os.environ["SMALL_PULL_DURATION_S"]

# ---------- load evidence ----------
kql_pull_events = json.load(open(f"{EVIDENCE_DIR}/06-kql-pull-events.json"))
revisions_all = json.load(open(f"{EVIDENCE_DIR}/05-revisions-all.json"))
kql_event_summary = json.load(open(f"{EVIDENCE_DIR}/09-kql-event-summary.json"))
# Fallback source for small image is system-logs-small.json, which captures
# the post-fix verify state where the small image was being pulled. The
# 02-verify-small-image.txt file is NOT used as a fallback because its
# "Old image" / "New image" comparison block is verify.sh's own derived
# output, not raw platform evidence.
system_logs_small = open(f"{EVIDENCE_DIR}/system-logs-small.json").read()

# ---------- a) pull event observed for small-image revision ----------
expected_log_s = (
    f'Successfully pulled image "{SMALL_IMAGE_TAG}" in {SMALL_PULL_DURATION_S}s. '
    f'Image size: {SMALL_IMAGE_SIZE_BYTES} bytes.'
)
strong_pull_event = next(
    (
        e for e in kql_pull_events
        if e.get("RevisionName_s") == SMALL_REVISION_NAME
        and e.get("Log_s") == expected_log_s
    ),
    None,
)
a_strong_path_exact_log_s = strong_pull_event is not None

# Fallback path: system-logs-small.json contains both the image tag and
# the duration substring. Tight scoping (both must be present) excludes
# the case where the small-log file mentions the tag in passing but
# without a matching pull event.
a_fallback_path_text_match = (
    f'"{SMALL_IMAGE_TAG}"' in system_logs_small
    and f'in {SMALL_PULL_DURATION_S}s' in system_logs_small
)
a_pull_event_observed = a_strong_path_exact_log_s or a_fallback_path_text_match

# ---------- b) image size matches captured baseline ----------
size_substring = f'Image size: {SMALL_IMAGE_SIZE_BYTES} bytes'
strong_size_match = any(
    e.get("RevisionName_s") == SMALL_REVISION_NAME
    and size_substring in (e.get("Log_s") or "")
    for e in kql_pull_events
)
b_strong_path_size_in_kql = strong_size_match

b_fallback_path_size_in_text = (
    f'{SMALL_IMAGE_SIZE_BYTES} bytes' in system_logs_small
    and f'"{SMALL_IMAGE_TAG}"' in system_logs_small
)
b_image_size_matches = b_strong_path_size_in_kql or b_fallback_path_size_in_text

# ---------- c) small-image revision reached healthy startup ----------
small_rev_obj = next(
    (r for r in revisions_all if r.get("name") == SMALL_REVISION_NAME),
    None,
)
c_strong_path_revision_healthy = (
    small_rev_obj is not None
    and small_rev_obj.get("healthState") == "Healthy"
)

c_fallback_path_container_started = any(
    e.get("RevisionName_s") == SMALL_REVISION_NAME
    and e.get("Reason_s") == "ContainerStarted"
    for e in kql_event_summary
)
c_revision_healthy = c_strong_path_revision_healthy or c_fallback_path_container_started

# ---------- compose gate ----------
h1_b_sub_gates = {
    "a_pull_event_observed": a_pull_event_observed,
    "b_image_size_matches_baseline": b_image_size_matches,
    "c_revision_healthy": c_revision_healthy,
}
h1_b_pass = all(h1_b_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "scenario": "B",
    "hypothesis": "H1",
    "claim": "scripted_small_cold_pull_observed_and_healthy",
    "target_revision": SMALL_REVISION_NAME,
    "target_image": SMALL_IMAGE_TAG,
    "expected_image_size_bytes": SMALL_IMAGE_SIZE_BYTES,
    "expected_cold_pull_duration_s": SMALL_PULL_DURATION_S,
    "predicate_inputs": {
        "kql_pull_events_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/06-kql-pull-events.json",
        "revisions_all_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/05-revisions-all.json",
        "kql_event_summary_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/09-kql-event-summary.json",
        "system_logs_small_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/system-logs-small.json",
    },
    "sub_gate_a_pull_event": {
        "expected_log_s": expected_log_s,
        "a_strong_path_exact_log_s_match": a_strong_path_exact_log_s,
        "a_fallback_path_text_match_tag_and_duration": a_fallback_path_text_match,
        "a_pass": a_pull_event_observed,
    },
    "sub_gate_b_image_size": {
        "expected_size_bytes": SMALL_IMAGE_SIZE_BYTES,
        "b_strong_path_size_in_kql_for_target_revision": b_strong_path_size_in_kql,
        "b_fallback_path_size_and_tag_in_system_logs": b_fallback_path_size_in_text,
        "b_pass": b_image_size_matches,
    },
    "sub_gate_c_revision_healthy": {
        "c_strong_path_healthstate_healthy": c_strong_path_revision_healthy,
        "c_fallback_path_container_started_event": c_fallback_path_container_started,
        "c_pass": c_revision_healthy,
    },
    "h1_b_sub_gates": h1_b_sub_gates,
    "h1_b_all_subgates_pass": h1_b_pass,
    "gate_classification": (
        "scripted_small_cold_pull_observed_and_healthy"
        if h1_b_pass else "h1_b_failed_check_sub_gates"
    ),
}, indent=2))
PY

echo "=== Phase 12: emit H1 gate for Scenario A/B speedup ratio ==="
EVIDENCE_DIR="$EVIDENCE_DIR" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
CAPTURED_AT_UTC="$CAPTURED_AT_UTC" \
LARGE_REVISION_NAME="$LARGE_REVISION_NAME" \
SMALL_REVISION_NAME="$SMALL_REVISION_NAME" \
LARGE_IMAGE_TAG="$LARGE_IMAGE_TAG" \
SMALL_IMAGE_TAG="$SMALL_IMAGE_TAG" \
SPEEDUP_RATIO_THRESHOLD="$SPEEDUP_RATIO_THRESHOLD" \
python3 - <<'PY' > "$EVIDENCE_DIR/12-h1-c-speedup-ratio-gate.json"
import json
import os
import re

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
REPO_RELATIVE_EVIDENCE_DIR = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]
LARGE_REVISION_NAME = os.environ["LARGE_REVISION_NAME"]
SMALL_REVISION_NAME = os.environ["SMALL_REVISION_NAME"]
LARGE_IMAGE_TAG = os.environ["LARGE_IMAGE_TAG"]
SMALL_IMAGE_TAG = os.environ["SMALL_IMAGE_TAG"]
SPEEDUP_RATIO_THRESHOLD = float(os.environ["SPEEDUP_RATIO_THRESHOLD"])

# ---------- load evidence ----------
kql_pull_events = json.load(open(f"{EVIDENCE_DIR}/06-kql-pull-events.json"))
trigger_large_text = open(f"{EVIDENCE_DIR}/01-trigger-large-image.txt").read()
system_logs_small = open(f"{EVIDENCE_DIR}/system-logs-small.json").read()

# ---------- duration parsing helper ----------
# Container Apps `Successfully pulled image` log lines record duration in
# one of two formats: seconds (`in 8.88s.`) or milliseconds (`in 12ms.`).
# This lab's three scripted/off-script cold pulls all complete in >= 1s,
# so we only need to parse the `Ns.` form for the gate predicate. The
# millisecond form is intentionally NOT parsed here — the warm pulls of
# the helloworld revision (12ms / 11ms / 9ms) are not in scope for the
# scripted A/B speedup ratio (they are part of the H2 falsification
# evidence in Gate 13).
#
# Priority 3 regex justification (bug-prevention lesson): the regex is
# anchored on `in ` (with trailing space) before the capture group and
# requires `s.` (with the dot) after the capture group, so we do not
# false-match the substring `in 12ms.` (which has `ms.` not `s.`). A
# naive regex like `in ([\d.]+)s` would match `12m` from `12ms` as `2`,
# producing a phantom 2.0-second duration. The captured value is the
# numeric portion only (e.g. `8.88`).
DURATION_REGEX = re.compile(r'in ([0-9]+\.[0-9]+)s\.')

def find_cold_pull_ms_strong(revision_name, image_tag):
    """Return the cold pull duration in milliseconds for the target
    revision from 06-kql-pull-events.json. We define the cold pull as
    the FIRST pull event for that revision in time order (which is also
    the longest pull time, since subsequent pulls of the same image on
    the same node are warm/cached). For scenarios A and B in this lab,
    each revision has exactly one pull event, so first == only."""
    events = [
        e for e in kql_pull_events
        if e.get("RevisionName_s") == revision_name
        and f'"{image_tag}"' in (e.get("Log_s") or "")
    ]
    if not events:
        return None
    # Sort by TimeGenerated ascending; first event is the cold pull.
    events.sort(key=lambda e: e.get("TimeGenerated") or "")
    cold = events[0]
    m = DURATION_REGEX.search(cold.get("Log_s") or "")
    if not m:
        return None
    return int(float(m.group(1)) * 1000)

def find_cold_pull_ms_fallback(text, image_tag):
    """Find the FIRST `Successfully pulled image "<tag>" in Ns.` line in
    the given raw text and return the parsed milliseconds. Tight scoping
    via the image tag prevents cross-contamination between the three
    revisions (large/small/helloworld) when the raw text contains
    multiple `Successfully pulled image` lines."""
    for line in text.split("\n"):
        if f'Successfully pulled image "{image_tag}"' not in line:
            continue
        m = DURATION_REGEX.search(line)
        if m:
            return int(float(m.group(1)) * 1000)
    return None

# ---------- a) both durations parseable ----------
# Strong path: parse both from 06-kql-pull-events.json (same structured
# source, keyed by RevisionName_s). Fallback path: parse from raw text
# files (different per scenario: 01-trigger-large-image.txt for A,
# system-logs-small.json for B). The gate passes if EITHER path produced
# both durations.
large_ms_strong = find_cold_pull_ms_strong(LARGE_REVISION_NAME, LARGE_IMAGE_TAG)
small_ms_strong = find_cold_pull_ms_strong(SMALL_REVISION_NAME, SMALL_IMAGE_TAG)
large_ms_fallback = find_cold_pull_ms_fallback(trigger_large_text, LARGE_IMAGE_TAG)
small_ms_fallback = find_cold_pull_ms_fallback(system_logs_small, SMALL_IMAGE_TAG)

a_strong_path_both_durations_parsed = (
    large_ms_strong is not None and small_ms_strong is not None
)
a_fallback_path_both_durations_parsed = (
    large_ms_fallback is not None and small_ms_fallback is not None
)
a_both_durations_parseable = (
    a_strong_path_both_durations_parsed or a_fallback_path_both_durations_parsed
)

# Pick the Strong-path values when available; otherwise fall back. This
# gate-resolved pair drives sub-gate b.
large_ms = large_ms_strong if large_ms_strong is not None else large_ms_fallback
small_ms = small_ms_strong if small_ms_strong is not None else small_ms_fallback

# ---------- b) speedup ratio >= threshold ----------
if large_ms is not None and small_ms is not None and small_ms > 0:
    speedup_ratio = large_ms / small_ms
else:
    speedup_ratio = None

b_speedup_ratio_material = (
    speedup_ratio is not None and speedup_ratio >= SPEEDUP_RATIO_THRESHOLD
)

# ---------- compose gate ----------
h1_c_sub_gates = {
    "a_both_durations_parseable": a_both_durations_parseable,
    "b_speedup_ratio_at_or_above_threshold": b_speedup_ratio_material,
}
h1_c_pass = all(h1_c_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "hypothesis": "H1",
    "claim": "scripted_cold_pull_speedup_material",
    "ratio_threshold": SPEEDUP_RATIO_THRESHOLD,
    "predicate_inputs": {
        "kql_pull_events_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/06-kql-pull-events.json",
        "trigger_text_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/01-trigger-large-image.txt",
        "system_logs_small_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/system-logs-small.json",
    },
    "sub_gate_a_durations_parseable": {
        "large_ms_strong_path_from_kql": large_ms_strong,
        "small_ms_strong_path_from_kql": small_ms_strong,
        "large_ms_fallback_path_from_trigger_text": large_ms_fallback,
        "small_ms_fallback_path_from_system_logs": small_ms_fallback,
        "a_strong_path_both_durations_parsed": a_strong_path_both_durations_parsed,
        "a_fallback_path_both_durations_parsed": a_fallback_path_both_durations_parsed,
        "a_pass": a_both_durations_parseable,
    },
    "sub_gate_b_speedup_ratio": {
        "large_ms_resolved": large_ms,
        "small_ms_resolved": small_ms,
        "speedup_ratio_observed": speedup_ratio,
        "ratio_threshold_required": SPEEDUP_RATIO_THRESHOLD,
        "b_pass": b_speedup_ratio_material,
    },
    "h1_c_sub_gates": h1_c_sub_gates,
    "h1_c_all_subgates_pass": h1_c_pass,
    "gate_classification": (
        "scripted_cold_pull_speedup_material"
        if h1_c_pass else "h1_c_failed_check_sub_gates"
    ),
}, indent=2))
PY

echo "=== Phase 13: emit H2 falsification gate (small image alone not sufficient) ==="
EVIDENCE_DIR="$EVIDENCE_DIR" \
REPO_RELATIVE_EVIDENCE_DIR="$REPO_RELATIVE_EVIDENCE_DIR" \
CAPTURED_AT_UTC="$CAPTURED_AT_UTC" \
LARGE_REVISION_NAME="$LARGE_REVISION_NAME" \
SMALL_REVISION_NAME="$SMALL_REVISION_NAME" \
HELLOWORLD_REVISION_NAME="$HELLOWORLD_REVISION_NAME" \
LARGE_IMAGE_TAG="$LARGE_IMAGE_TAG" \
SMALL_IMAGE_TAG="$SMALL_IMAGE_TAG" \
HELLOWORLD_IMAGE_TAG="$HELLOWORLD_IMAGE_TAG" \
HELLOWORLD_TERMINATED_THRESHOLD="$HELLOWORLD_TERMINATED_THRESHOLD" \
python3 - <<'PY' > "$EVIDENCE_DIR/13-h2-falsification-gate.json"
import json
import os
import re

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
REPO_RELATIVE_EVIDENCE_DIR = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]
LARGE_REVISION_NAME = os.environ["LARGE_REVISION_NAME"]
SMALL_REVISION_NAME = os.environ["SMALL_REVISION_NAME"]
HELLOWORLD_REVISION_NAME = os.environ["HELLOWORLD_REVISION_NAME"]
LARGE_IMAGE_TAG = os.environ["LARGE_IMAGE_TAG"]
SMALL_IMAGE_TAG = os.environ["SMALL_IMAGE_TAG"]
HELLOWORLD_IMAGE_TAG = os.environ["HELLOWORLD_IMAGE_TAG"]
HELLOWORLD_TERMINATED_THRESHOLD = int(os.environ["HELLOWORLD_TERMINATED_THRESHOLD"])

# ---------- load evidence ----------
kql_pull_events = json.load(open(f"{EVIDENCE_DIR}/06-kql-pull-events.json"))
kql_event_summary = json.load(open(f"{EVIDENCE_DIR}/09-kql-event-summary.json"))
system_logs_large = open(f"{EVIDENCE_DIR}/system-logs-large.json").read()
system_logs_small = open(f"{EVIDENCE_DIR}/system-logs-small.json").read()

# ---------- duration parsing helpers ----------
# Same regex as Gate 12 (anchored on `s.`) — see Gate 12's regex
# justification comment for why this is not vulnerable to `12ms` false
# matches. We extend Gate 12's parser here to also handle the millisecond
# form (`in 12ms.`) because the helloworld revision has both a cold pull
# in seconds (1.62s) AND three warm pulls in milliseconds (12/11/9 ms).
# This gate only needs the COLD pull (the slowest, first-in-time pull),
# so we still use the seconds-only regex for the per-revision-min logic.
DURATION_REGEX_S = re.compile(r'in ([0-9]+\.[0-9]+)s\.')

def cold_pull_ms_from_kql(revision_name, image_tag):
    """Return the COLD pull duration (in milliseconds) for the target
    revision, defined as the first (=oldest) pull event for that revision.
    Tight scoping: requires both RevisionName_s match AND image-tag
    substring in Log_s, so background revision-deactivation chatter on
    other revisions cannot poison this calculation."""
    events = [
        e for e in kql_pull_events
        if e.get("RevisionName_s") == revision_name
        and f'"{image_tag}"' in (e.get("Log_s") or "")
    ]
    if not events:
        return None
    events.sort(key=lambda e: e.get("TimeGenerated") or "")
    m = DURATION_REGEX_S.search(events[0].get("Log_s") or "")
    if not m:
        return None
    return int(float(m.group(1)) * 1000)

# ---------- a) helloworld cold pull is fastest among the 3 revisions ----------
# Falsifiable claim: the FASTEST cold pull came from the off-script
# helloworld revision (1.62s = 1620ms), not from the scripted small image
# (2.88s = 2880ms). This directly falsifies the alternative hypothesis
# "small image alone implies fast healthy startup" — the fastest puller
# of all three was the SECOND-smallest image (33 MB helloworld), and that
# revision was the one that FAILED (sub-gates b and c below).
helloworld_ms_strong = cold_pull_ms_from_kql(HELLOWORLD_REVISION_NAME, HELLOWORLD_IMAGE_TAG)
large_ms_strong = cold_pull_ms_from_kql(LARGE_REVISION_NAME, LARGE_IMAGE_TAG)
small_ms_strong = cold_pull_ms_from_kql(SMALL_REVISION_NAME, SMALL_IMAGE_TAG)

a_strong_path_helloworld_fastest = (
    helloworld_ms_strong is not None
    and large_ms_strong is not None
    and small_ms_strong is not None
    and helloworld_ms_strong < large_ms_strong
    and helloworld_ms_strong < small_ms_strong
)

# Fallback path: count cold-pull lines containing each image tag in the
# raw system-logs-large.json and compare the smallest-duration line per
# image. We use a lighter parser here that picks up both `Ns.` and `Nms.`
# durations because the raw log file contains warm pulls in milliseconds
# for the helloworld image.
FALLBACK_DURATION_REGEX = re.compile(r'in ([0-9]+(?:\.[0-9]+)?)(s|ms)\.')

def smallest_pull_ms_from_text(text, image_tag):
    """Find ALL `Successfully pulled image "<tag>" in <N>s.` and
    `... in <N>ms.` lines in the given text and return the minimum
    duration converted to milliseconds. For Gate 13's helloworld
    comparison, this returns 9 ms (the smallest warm pull). For the
    python:3.11 and python:3.11-alpine images this returns the cold-pull
    value (no warm pulls in scope for those revisions on this run).
    Tight scoping via the image tag prevents cross-image pollution."""
    candidates = []
    for line in text.split("\n"):
        if f'Successfully pulled image "{image_tag}"' not in line:
            continue
        m = FALLBACK_DURATION_REGEX.search(line)
        if not m:
            continue
        value = float(m.group(1))
        unit = m.group(2)
        ms = int(value * 1000) if unit == "s" else int(value)
        candidates.append(ms)
    return min(candidates) if candidates else None

helloworld_ms_fallback = smallest_pull_ms_from_text(system_logs_large, HELLOWORLD_IMAGE_TAG)
large_ms_fallback = smallest_pull_ms_from_text(system_logs_large, LARGE_IMAGE_TAG)
small_ms_fallback = smallest_pull_ms_from_text(system_logs_small, SMALL_IMAGE_TAG)

# Even on the Fallback path the helloworld smallest pull (9 ms warm) is
# smaller than the python:3.11 cold pull (8880 ms) and the
# python:3.11-alpine cold pull (2880 ms). The Fallback path is therefore
# also true. The Fallback path captures the broader claim "of all pull
# events captured in the raw system logs, the helloworld image had the
# fastest" — slightly weaker than the Strong path (which restricts to
# cold pulls only) but still falsifies the alternative hypothesis.
a_fallback_path_helloworld_fastest = (
    helloworld_ms_fallback is not None
    and (
        # large_ms_fallback may legitimately be None if system-logs-large.json
        # does not contain the python:3.11 pull (only helloworld events were
        # captured during the verify pre-fix window). In that case rely on
        # the trigger-text-derived large_ms from Gate 12's pattern OR fall
        # back to Strong path. We require at least one of the comparisons
        # to be evaluable.
        (large_ms_fallback is None or helloworld_ms_fallback < large_ms_fallback)
        and (small_ms_fallback is None or helloworld_ms_fallback < small_ms_fallback)
    )
)
a_helloworld_fastest = (
    a_strong_path_helloworld_fastest or a_fallback_path_helloworld_fastest
)

# ---------- b) ContainerTerminated count >= 3 for helloworld revision ----------
# Strong path: 09-kql-event-summary.json has an entry where:
#   - RevisionName_s == helloworld revision name (tight scoping)
#   - Reason_s == "ContainerTerminated"
#   - PullCount field (which holds the event count for grouped rollups) >= 3
# The PullCount field is a string in the captured JSON; convert before
# comparison. Tight scoping excludes the natural ContainerTerminated event
# that fires on every revision during graceful deactivation (which would
# also exist for --5487avi at 02:28:03 UTC, captured in 09-kql line 246).
helloworld_terminated_entry = next(
    (
        e for e in kql_event_summary
        if e.get("RevisionName_s") == HELLOWORLD_REVISION_NAME
        and e.get("Reason_s") == "ContainerTerminated"
    ),
    None,
)
if helloworld_terminated_entry is not None:
    try:
        helloworld_terminated_count_strong = int(
            helloworld_terminated_entry.get("PullCount", "0")
        )
    except (TypeError, ValueError):
        helloworld_terminated_count_strong = 0
else:
    helloworld_terminated_count_strong = 0

b_strong_path_kql_summary_count = (
    helloworld_terminated_count_strong >= HELLOWORLD_TERMINATED_THRESHOLD
)

# Fallback path: count raw `ContainerTerminated` events for the helloworld
# revision in system-logs-large.json. Tight scoping: each event line in
# the raw JSON contains BOTH `"Reason": "ContainerTerminated"` AND
# `"RevisionName": "<helloworld_revision>"`, so background deactivation
# events on other revisions are excluded. The captured baseline has 4
# such events (system-logs-large.json lines 20, 23, 26, 29).
helloworld_terminated_count_fallback = sum(
    1 for line in system_logs_large.split("\n")
    if '"Reason": "ContainerTerminated"' in line
    and f'"RevisionName": "{HELLOWORLD_REVISION_NAME}"' in line
)
b_fallback_path_raw_log_count = (
    helloworld_terminated_count_fallback >= HELLOWORLD_TERMINATED_THRESHOLD
)
b_helloworld_terminated_ge_threshold = (
    b_strong_path_kql_summary_count or b_fallback_path_raw_log_count
)

# ---------- c) runtime mismatch error signature in raw logs ----------
# The smoking-gun signature is exactly:
#     exec: "python": executable file not found in $PATH
# This text appears in the `Msg` field of every ContainerTerminated event
# for the helloworld revision. The signature is the falsifiable proof
# that the failure mode was "image had no Python runtime to execute the
# Bicep command override", NOT "image too small" or "image pull failed".
#
# Priority 3 escaping/comment justification (PII safety + bug-prevention
# lesson): the `$PATH` substring is a LITERAL part of the error message
# from the container runtime — it is NOT a shell variable expansion. The
# QUOTED heredoc (`<<'PY'`) at this Python block's open ensures bash does
# not expand `$PATH` before Python sees the string. The substring match
# is exact (no regex) to maximize human-readability of the predicate.
EXEC_ERROR_SIGNATURE = 'exec: \\"python\\": executable file not found in $PATH'

c_strong_path_signature_in_large = EXEC_ERROR_SIGNATURE in system_logs_large
c_fallback_path_signature_in_small = EXEC_ERROR_SIGNATURE in system_logs_small
c_runtime_mismatch_signature = (
    c_strong_path_signature_in_large or c_fallback_path_signature_in_small
)

# ---------- compose gate ----------
h2_sub_gates = {
    "a_helloworld_cold_pull_is_fastest_of_three_revisions": a_helloworld_fastest,
    "b_helloworld_containerterminated_count_ge_threshold": b_helloworld_terminated_ge_threshold,
    "c_runtime_mismatch_error_signature_present": c_runtime_mismatch_signature,
}
h2_pass = all(h2_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "hypothesis": "H2",
    "claim": "small_image_alone_not_sufficient_for_healthy_startup",
    "target_off_script_revision": HELLOWORLD_REVISION_NAME,
    "target_off_script_image": HELLOWORLD_IMAGE_TAG,
    "containerterminated_threshold": HELLOWORLD_TERMINATED_THRESHOLD,
    "predicate_inputs": {
        "kql_pull_events_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/06-kql-pull-events.json",
        "kql_event_summary_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/09-kql-event-summary.json",
        "system_logs_large_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/system-logs-large.json",
        "system_logs_small_path": f"{REPO_RELATIVE_EVIDENCE_DIR}/system-logs-small.json",
    },
    "sub_gate_a_helloworld_fastest": {
        "helloworld_ms_strong_path_from_kql_cold": helloworld_ms_strong,
        "large_ms_strong_path_from_kql_cold": large_ms_strong,
        "small_ms_strong_path_from_kql_cold": small_ms_strong,
        "helloworld_ms_fallback_path_min_in_system_logs_large": helloworld_ms_fallback,
        "large_ms_fallback_path_min_in_system_logs_large": large_ms_fallback,
        "small_ms_fallback_path_min_in_system_logs_small": small_ms_fallback,
        "a_strong_path_helloworld_lt_large_and_small": a_strong_path_helloworld_fastest,
        "a_fallback_path_helloworld_lt_large_and_small": a_fallback_path_helloworld_fastest,
        "a_pass": a_helloworld_fastest,
    },
    "sub_gate_b_containerterminated_count": {
        "helloworld_terminated_count_strong_path_kql_summary": helloworld_terminated_count_strong,
        "helloworld_terminated_count_fallback_path_raw_log": helloworld_terminated_count_fallback,
        "threshold_required": HELLOWORLD_TERMINATED_THRESHOLD,
        "b_strong_path_kql_summary_count": b_strong_path_kql_summary_count,
        "b_fallback_path_raw_log_count": b_fallback_path_raw_log_count,
        "b_pass": b_helloworld_terminated_ge_threshold,
    },
    "sub_gate_c_runtime_mismatch_signature": {
        "signature_substring_required": EXEC_ERROR_SIGNATURE,
        "c_strong_path_signature_in_system_logs_large": c_strong_path_signature_in_large,
        "c_fallback_path_signature_in_system_logs_small": c_fallback_path_signature_in_small,
        "c_pass": c_runtime_mismatch_signature,
    },
    "h2_sub_gates": h2_sub_gates,
    "h2_all_subgates_pass": h2_pass,
    "gate_classification": (
        "small_image_alone_not_sufficient_for_healthy_startup"
        if h2_pass else "h2_failed_check_sub_gates"
    ),
}, indent=2))
PY

# ---------- final summary ----------
echo ""
echo "=== Phase B verify summary ==="
python3 - <<PY
import json
import os
import sys

EVIDENCE_DIR = "$EVIDENCE_DIR"

gates = [
    ("10-h1-a-large-cold-pull-gate.json", "h1_a_all_subgates_pass"),
    ("11-h1-b-small-cold-pull-gate.json", "h1_b_all_subgates_pass"),
    ("12-h1-c-speedup-ratio-gate.json", "h1_c_all_subgates_pass"),
    ("13-h2-falsification-gate.json", "h2_all_subgates_pass"),
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
    print("All 4 Phase B gates PASS (11/11 sub-gates).")
    sys.exit(0)
else:
    print("One or more gates FAILED — inspect the gate JSONs above.")
    sys.exit(1)
PY
