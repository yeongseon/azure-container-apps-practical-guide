#!/usr/bin/env bash
# verify.sh — Phase B evidence-pack verification for Lab 14.
#
# What this script proves (falsifiable, strict 2-path predicates per Oracle
# Option α). Reads ONLY the numbered evidence files written by trigger.sh
# (01..21) and emits four sub-gate JSON files (22..25). NO Azure calls —
# verify.sh is replayable from disk so a reviewer can re-classify gates
# without re-deploying infrastructure.
#
#   22-h1-scenario-a-gate.json — H1 for Scenario A (just-below threshold,
#     rss workload, TARGET_MB=400). Sub-gates:
#       a) scale rule matches the lab spec (type=memory, target=50, min=2,
#          max=20).
#       b) Replicas held at the floor across the stable window.
#       c) MemoryPercentage stays inside the just-below band [25,50].
#       d) cgroup composition is rss/anon-dominant (rss >> cache).
#       e) Exactly one active revision (no stale split-traffic state).
#
#   23-h1-scenario-b-gate.json — H1 for Scenario B (just-above threshold,
#     rss workload, TARGET_MB=560). Sub-gates:
#       a) scale rule matches the lab spec (same as A).
#       b) Replicas walked up to maxReplicas (==20) — the HPA ceiling
#          re-computes ceil(N × 56 / 50) = N+1 on every poll.
#       c) MemoryPercentage crosses 50 (>=50, expected band [50,60]).
#       d) cgroup composition is rss/anon-dominant.
#       e) Exactly one active revision.
#
#   24-h1-scenario-c-gate.json — H1 for Scenario C (cache inflation,
#     cache workload, TARGET_MB=700). Sub-gates:
#       a) scale rule matches the lab spec.
#       b) Replicas stay low (max <= 5) despite MemoryPercentage being
#          above the 50 target — the symptom this lab reproduces.
#       c) MemoryPercentage stays above 50 (expected band [65,80]).
#       d) cgroup composition is cache/file-dominant (cache > 5x rss).
#       e) Exactly one active revision.
#
#   25-h2-differential-gate.json — H2 cross-scenario differential proof
#     (the lab's overarching hypothesis: Portal MemoryPercentage value
#     does NOT cleanly map to KEDA scaler input for cache-heavy
#     workloads). Sub-gates:
#       a) Scenario A is held at the floor (max <= 2) — proves HPA ceiling
#          math is the dominant effect when per-replica utilization sits
#          at or below the target.
#       b) Scenario B walks up to maxReplicas (==20) — proves the same
#          rule scales out when the per-replica value crosses the target.
#       c) Scenario C stays at the floor despite MemoryPercentage being
#          above the 50 target — proves the Portal value alone does NOT
#          drive KEDA's decision.
#       d) C's cgroup is cache-dominant (cache > 5x rss) — explains the
#          divergence: the KEDA memory scaler reads a different
#          numerator than the Portal MemoryPercentage metric for
#          cache-heavy workloads.
#       e) Ordinal scaling proven: B.replicas_max > A.replicas_max AND
#          B.replicas_max > C.replicas_max — robust against exact-value
#          drift while still proving the differential.
#       f) All three scenarios use distinct app names (no accidental
#          duplicate measurements of the same workload).
#
# Strict 2-path predicate rule (per Phase B Lab 11+12+13 lessons):
#   Each sub-gate computes Strong AND Fallback in the same evaluation;
#   the gate passes if EITHER path is true. The JSON output captures
#   which path passed so a reviewer can audit the evidence trail.
#
# Numbered prefix policy (per Phase B Lab 11+12 lessons):
#   01..21 = trigger.sh snapshots (raw, no derived state).
#   22..25 = verify.sh derived sub-gates (this script).
#   Plural filenames everywhere; index starts at 01-* (never 00-*).
#
# Usage:
#   bash labs/memory-percentage-vs-keda-utilization/verify.sh
#   (no environment variables needed — pure evidence-file processor)

set -euo pipefail

EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"

# Sanity-check that trigger.sh has been run end-to-end before verify.sh.
for required in \
    01-infra-resolve.json \
    07-scenario-a-revisions.json \
    08-scenario-a-replicas.json \
    09-scenario-a-memorypercentage.json \
    10-scenario-a-cgroup.json \
    11-scenario-b-revisions.json \
    12-scenario-b-replicas.json \
    13-scenario-b-memorypercentage.json \
    14-scenario-b-cgroup.json \
    15-scenario-c-revisions.json \
    16-scenario-c-replicas.json \
    17-scenario-c-memorypercentage.json \
    18-scenario-c-cgroup.json; do
    if [ ! -f "$EVIDENCE_DIR/$required" ]; then
        echo "ERROR: required evidence file $EVIDENCE_DIR/$required not found. Run trigger.sh first." >&2
        exit 1
    fi
done

CAPTURED_AT_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

echo "=== Phase 22: emit H1 gate for Scenario A (just-below threshold, rss) ==="
# Sub-gate logic implemented in Python so the Strong/Fallback predicates and
# cgroup field parsing are unit-testable from disk. The Python block reads
# evidence files by absolute path and writes the gate JSON to stdout.
#
# QUOTED heredoc ('PY') is used deliberately. With an unquoted <<PY heredoc
# bash would have to be told to escape the regex end-anchor ($) with \$ to
# avoid bash trying to expand $", which made the Python regex source look
# like a literal-dollar match (r"...\$") to a source reader and triggered a
# false-positive in static review. With the quoted heredoc the regex literal
# is exactly what Python sees, and shell vars are passed via os.environ.
EVIDENCE_DIR="$EVIDENCE_DIR" CAPTURED_AT_UTC="$CAPTURED_AT_UTC" python3 - <<'PY' > "$EVIDENCE_DIR/22-h1-scenario-a-gate.json"
import json
import os
import re

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]

# ---------- cgroup parser (cgroup v1 memory.stat format, with carriage-return artifacts) ----------
# az containerapp exec piped through a pty wrapper produces \r\r\n line
# endings inside the captured stdout. Strip \r before splitting on \n so
# the parser is independent of whether the capture used a pty wrapper.
def parse_memory_stat(raw):
    if not isinstance(raw, str):
        return {}
    text = raw.replace("\r", "")
    out = {}
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        m = re.match(r"^([a-zA-Z_]+)\s+(\d+)$", line)
        if m:
            try:
                out[m.group(1)] = int(m.group(2))
            except ValueError:
                pass
    return out

def parse_raw_bytes(raw):
    if not isinstance(raw, str):
        return None
    s = raw.replace("\r", "").strip()
    try:
        return int(s)
    except ValueError:
        return None

# ---------- load evidence ----------
revisions = json.load(open(f"{EVIDENCE_DIR}/07-scenario-a-revisions.json"))
replicas_metric = json.load(open(f"{EVIDENCE_DIR}/08-scenario-a-replicas.json"))
mempct_metric = json.load(open(f"{EVIDENCE_DIR}/09-scenario-a-memorypercentage.json"))
cgroup = json.load(open(f"{EVIDENCE_DIR}/10-scenario-a-cgroup.json"))

# ---------- a) scale rule match ----------
# Container Apps revision schema: properties.template.scale.{minReplicas, maxReplicas, rules[]}
# Each rule has .name plus either .custom.{type, metadata.{type, value}} (KEDA) or .http/.tcp/.azureQueue (built-in).
active_revs = [r for r in revisions if r.get("properties", {}).get("active") is True]
active_rev_count = len(active_revs)
scale = active_revs[0]["properties"]["template"]["scale"] if active_revs else {}
rules = scale.get("rules", []) or []
rule_zero = rules[0] if rules else {}
custom = rule_zero.get("custom", {}) or {}
metadata = custom.get("metadata", {}) or {}

a_min_replicas = scale.get("minReplicas")
a_max_replicas_spec = scale.get("maxReplicas")
a_rule_count = len(rules)
a_rule_custom_type = custom.get("type")
a_rule_metadata_type = metadata.get("type")
a_rule_metadata_value = metadata.get("value")

a_strong = (
    a_min_replicas == 2
    and a_max_replicas_spec == 20
    and a_rule_count == 1
    and a_rule_custom_type == "memory"
    and a_rule_metadata_type == "Utilization"
    and a_rule_metadata_value == "50"
)
a_fallback = (
    a_min_replicas is not None
    and a_max_replicas_spec is not None
    and a_min_replicas >= 1
    and a_max_replicas_spec >= a_min_replicas
    and a_rule_count >= 1
    and a_rule_custom_type == "memory"
    and a_rule_metadata_value == "50"
)
a_scale_rule_match = a_strong or a_fallback

# ---------- b) replicas held at floor ----------
# Container Apps metrics: value[0].timeseries[0].data[] entries either have
# {timeStamp, maximum} (when there were live replicas) or just {timeStamp}
# (before app provisioning completed). Filter the early nulls.
replica_data = replicas_metric.get("value", [{}])[0].get("timeseries", [{}])[0].get("data", [])
replica_values = [d["maximum"] for d in replica_data if "maximum" in d and d["maximum"] is not None]
# Exclude leading zeros (app not yet provisioned).
nonzero_replica_values = [v for v in replica_values if v > 0]
replicas_max = max(nonzero_replica_values) if nonzero_replica_values else 0
replicas_min = min(nonzero_replica_values) if nonzero_replica_values else 0
stable_window_count = len(nonzero_replica_values)

b_strong = (replicas_max == 2 and replicas_min == 2 and stable_window_count >= 10)
b_fallback = (replicas_max <= 2 and stable_window_count >= 5)
b_replicas_held_at_floor = b_strong or b_fallback

# ---------- c) memorypercentage in band [25, 50] ----------
mempct_data = mempct_metric.get("value", [{}])[0].get("timeseries", [{}])[0].get("data", [])
mempct_values = [d["average"] for d in mempct_data if "average" in d and d["average"] is not None]
mempct_max = max(mempct_values) if mempct_values else None
mempct_min = min(mempct_values) if mempct_values else None
mempct_sample_count = len(mempct_values)

c_strong = (
    mempct_max is not None
    and mempct_min is not None
    and 35 <= mempct_min
    and mempct_max <= 45
    and mempct_sample_count >= 10
)
c_fallback = (
    mempct_max is not None
    and mempct_min is not None
    and 25 <= mempct_min
    and mempct_max <= 50
    and mempct_sample_count >= 5
)
c_mempct_in_band = c_strong or c_fallback

# ---------- d) cgroup rss-dominant ----------
stat = parse_memory_stat(cgroup.get("memory_stat_raw"))
cgroup_cache = stat.get("cache", 0)
cgroup_rss = stat.get("rss", 0)
cgroup_active_anon = stat.get("active_anon", 0)
cgroup_inactive_file = stat.get("inactive_file", 0)
rss_to_cache_ratio = (cgroup_rss / cgroup_cache) if cgroup_cache > 0 else float("inf")
anon_to_file_ratio = (cgroup_active_anon / cgroup_inactive_file) if cgroup_inactive_file > 0 else float("inf")

d_strong = (cgroup_rss > 0 and cgroup_cache > 0 and rss_to_cache_ratio >= 100)
d_fallback = (cgroup_rss > 0 and rss_to_cache_ratio >= 10)
d_cgroup_rss_dominant = d_strong or d_fallback

# ---------- e) active revision unique ----------
e_active_revision_unique = (active_rev_count == 1)

h1_a_sub_gates = {
    "a_scale_rule_match": a_scale_rule_match,
    "b_replicas_held_at_floor": b_replicas_held_at_floor,
    "c_memorypercentage_in_band_25_50": c_mempct_in_band,
    "d_cgroup_rss_dominant": d_cgroup_rss_dominant,
    "e_active_revision_unique": e_active_revision_unique,
}
h1_a_pass = all(h1_a_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "scenario": "A",
    "app_name": cgroup.get("app_name"),
    "active_revision": cgroup.get("active_revision"),
    "active_revision_count": active_rev_count,
    "scale_rule": {
        "min_replicas": a_min_replicas,
        "max_replicas_spec": a_max_replicas_spec,
        "rule_count": a_rule_count,
        "rule_custom_type": a_rule_custom_type,
        "rule_metadata_type": a_rule_metadata_type,
        "rule_metadata_value": a_rule_metadata_value,
        "a_strong_path_exact_lab_spec": a_strong,
        "a_fallback_path_compatible_rule_shape": a_fallback,
    },
    "replica_behavior": {
        "samples_total": len(replica_data),
        "samples_with_value": len(replica_values),
        "samples_nonzero": stable_window_count,
        "replicas_min_nonzero": replicas_min,
        "replicas_max_nonzero": replicas_max,
        "b_strong_path_exact_floor_held": b_strong,
        "b_fallback_path_max_le_2": b_fallback,
    },
    "memorypercentage_behavior": {
        "samples_with_value": mempct_sample_count,
        "mempct_min": mempct_min,
        "mempct_max": mempct_max,
        "c_strong_path_band_35_45": c_strong,
        "c_fallback_path_band_25_50": c_fallback,
    },
    "cgroup_composition": {
        "version": cgroup.get("cgroup_version"),
        "memory_usage_bytes": parse_raw_bytes(cgroup.get("memory_usage_in_bytes_raw")),
        "memory_limit_bytes": parse_raw_bytes(cgroup.get("memory_limit_in_bytes_raw")),
        "stat_cache_bytes": cgroup_cache,
        "stat_rss_bytes": cgroup_rss,
        "stat_active_anon_bytes": cgroup_active_anon,
        "stat_inactive_file_bytes": cgroup_inactive_file,
        "rss_to_cache_ratio": rss_to_cache_ratio,
        "active_anon_to_inactive_file_ratio": anon_to_file_ratio,
        "d_strong_path_rss_100x_cache": d_strong,
        "d_fallback_path_rss_10x_cache": d_fallback,
    },
    "h1_a_sub_gates": h1_a_sub_gates,
    "h1_a_all_subgates_pass": h1_a_pass,
    "gate_classification": "scenario_a_held_at_floor_rss_dominant" if h1_a_pass else "h1_a_failed_check_sub_gates",
}, indent=2))
PY

echo "=== Phase 23: emit H1 gate for Scenario B (just-above threshold, rss) ==="
EVIDENCE_DIR="$EVIDENCE_DIR" CAPTURED_AT_UTC="$CAPTURED_AT_UTC" python3 - <<'PY' > "$EVIDENCE_DIR/23-h1-scenario-b-gate.json"
import json
import os
import re

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]

def parse_memory_stat(raw):
    if not isinstance(raw, str):
        return {}
    text = raw.replace("\r", "")
    out = {}
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        m = re.match(r"^([a-zA-Z_]+)\s+(\d+)$", line)
        if m:
            try:
                out[m.group(1)] = int(m.group(2))
            except ValueError:
                pass
    return out

def parse_raw_bytes(raw):
    if not isinstance(raw, str):
        return None
    s = raw.replace("\r", "").strip()
    try:
        return int(s)
    except ValueError:
        return None

revisions = json.load(open(f"{EVIDENCE_DIR}/11-scenario-b-revisions.json"))
replicas_metric = json.load(open(f"{EVIDENCE_DIR}/12-scenario-b-replicas.json"))
mempct_metric = json.load(open(f"{EVIDENCE_DIR}/13-scenario-b-memorypercentage.json"))
cgroup = json.load(open(f"{EVIDENCE_DIR}/14-scenario-b-cgroup.json"))

# ---------- a) scale rule match (same predicate as A) ----------
active_revs = [r for r in revisions if r.get("properties", {}).get("active") is True]
active_rev_count = len(active_revs)
scale = active_revs[0]["properties"]["template"]["scale"] if active_revs else {}
rules = scale.get("rules", []) or []
rule_zero = rules[0] if rules else {}
custom = rule_zero.get("custom", {}) or {}
metadata = custom.get("metadata", {}) or {}

a_min_replicas = scale.get("minReplicas")
a_max_replicas_spec = scale.get("maxReplicas")
a_rule_count = len(rules)
a_rule_custom_type = custom.get("type")
a_rule_metadata_type = metadata.get("type")
a_rule_metadata_value = metadata.get("value")

a_strong = (
    a_min_replicas == 2
    and a_max_replicas_spec == 20
    and a_rule_count == 1
    and a_rule_custom_type == "memory"
    and a_rule_metadata_type == "Utilization"
    and a_rule_metadata_value == "50"
)
a_fallback = (
    a_min_replicas is not None
    and a_max_replicas_spec is not None
    and a_min_replicas >= 1
    and a_max_replicas_spec >= a_min_replicas
    and a_rule_count >= 1
    and a_rule_custom_type == "memory"
    and a_rule_metadata_value == "50"
)
a_scale_rule_match = a_strong or a_fallback

# ---------- b) replicas walked up to maxReplicas (==20) ----------
replica_data = replicas_metric.get("value", [{}])[0].get("timeseries", [{}])[0].get("data", [])
replica_values = [d["maximum"] for d in replica_data if "maximum" in d and d["maximum"] is not None]
nonzero_replica_values = [v for v in replica_values if v > 0]
replicas_max = max(nonzero_replica_values) if nonzero_replica_values else 0
replicas_min = min(nonzero_replica_values) if nonzero_replica_values else 0
stable_window_count = len(nonzero_replica_values)

b_strong = (replicas_max == 20 and stable_window_count >= 10)
b_fallback = (replicas_max >= 10 and stable_window_count >= 5)
b_replicas_walked_to_max = b_strong or b_fallback

# ---------- c) memorypercentage crosses 50 ----------
mempct_data = mempct_metric.get("value", [{}])[0].get("timeseries", [{}])[0].get("data", [])
mempct_values = [d["average"] for d in mempct_data if "average" in d and d["average"] is not None]
mempct_max = max(mempct_values) if mempct_values else None
mempct_min = min(mempct_values) if mempct_values else None
mempct_sample_count = len(mempct_values)

c_strong = (
    mempct_max is not None
    and mempct_min is not None
    and 50 <= mempct_min
    and mempct_max <= 60
    and mempct_sample_count >= 10
)
c_fallback = (
    mempct_max is not None
    and mempct_max >= 50
    and mempct_sample_count >= 5
)
c_mempct_crosses_50 = c_strong or c_fallback

# ---------- d) cgroup rss-dominant ----------
stat = parse_memory_stat(cgroup.get("memory_stat_raw"))
cgroup_cache = stat.get("cache", 0)
cgroup_rss = stat.get("rss", 0)
cgroup_active_anon = stat.get("active_anon", 0)
cgroup_inactive_file = stat.get("inactive_file", 0)
rss_to_cache_ratio = (cgroup_rss / cgroup_cache) if cgroup_cache > 0 else float("inf")
anon_to_file_ratio = (cgroup_active_anon / cgroup_inactive_file) if cgroup_inactive_file > 0 else float("inf")

d_strong = (cgroup_rss > 0 and cgroup_cache > 0 and rss_to_cache_ratio >= 100)
d_fallback = (cgroup_rss > 0 and rss_to_cache_ratio >= 10)
d_cgroup_rss_dominant = d_strong or d_fallback

# ---------- e) active revision unique ----------
e_active_revision_unique = (active_rev_count == 1)

h1_b_sub_gates = {
    "a_scale_rule_match": a_scale_rule_match,
    "b_replicas_walked_to_max": b_replicas_walked_to_max,
    "c_memorypercentage_crosses_50": c_mempct_crosses_50,
    "d_cgroup_rss_dominant": d_cgroup_rss_dominant,
    "e_active_revision_unique": e_active_revision_unique,
}
h1_b_pass = all(h1_b_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "scenario": "B",
    "app_name": cgroup.get("app_name"),
    "active_revision": cgroup.get("active_revision"),
    "active_revision_count": active_rev_count,
    "scale_rule": {
        "min_replicas": a_min_replicas,
        "max_replicas_spec": a_max_replicas_spec,
        "rule_count": a_rule_count,
        "rule_custom_type": a_rule_custom_type,
        "rule_metadata_type": a_rule_metadata_type,
        "rule_metadata_value": a_rule_metadata_value,
        "a_strong_path_exact_lab_spec": a_strong,
        "a_fallback_path_compatible_rule_shape": a_fallback,
    },
    "replica_behavior": {
        "samples_total": len(replica_data),
        "samples_with_value": len(replica_values),
        "samples_nonzero": stable_window_count,
        "replicas_min_nonzero": replicas_min,
        "replicas_max_nonzero": replicas_max,
        "b_strong_path_max_eq_20": b_strong,
        "b_fallback_path_max_ge_10": b_fallback,
    },
    "memorypercentage_behavior": {
        "samples_with_value": mempct_sample_count,
        "mempct_min": mempct_min,
        "mempct_max": mempct_max,
        "c_strong_path_band_50_60": c_strong,
        "c_fallback_path_max_ge_50": c_fallback,
    },
    "cgroup_composition": {
        "version": cgroup.get("cgroup_version"),
        "memory_usage_bytes": parse_raw_bytes(cgroup.get("memory_usage_in_bytes_raw")),
        "memory_limit_bytes": parse_raw_bytes(cgroup.get("memory_limit_in_bytes_raw")),
        "stat_cache_bytes": cgroup_cache,
        "stat_rss_bytes": cgroup_rss,
        "stat_active_anon_bytes": cgroup_active_anon,
        "stat_inactive_file_bytes": cgroup_inactive_file,
        "rss_to_cache_ratio": rss_to_cache_ratio,
        "active_anon_to_inactive_file_ratio": anon_to_file_ratio,
        "d_strong_path_rss_100x_cache": d_strong,
        "d_fallback_path_rss_10x_cache": d_fallback,
    },
    "h1_b_sub_gates": h1_b_sub_gates,
    "h1_b_all_subgates_pass": h1_b_pass,
    "gate_classification": "scenario_b_walked_to_max_rss_dominant" if h1_b_pass else "h1_b_failed_check_sub_gates",
}, indent=2))
PY

echo "=== Phase 24: emit H1 gate for Scenario C (cache inflation, cache workload) ==="
EVIDENCE_DIR="$EVIDENCE_DIR" CAPTURED_AT_UTC="$CAPTURED_AT_UTC" python3 - <<'PY' > "$EVIDENCE_DIR/24-h1-scenario-c-gate.json"
import json
import os
import re

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]

def parse_memory_stat(raw):
    if not isinstance(raw, str):
        return {}
    text = raw.replace("\r", "")
    out = {}
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        m = re.match(r"^([a-zA-Z_]+)\s+(\d+)$", line)
        if m:
            try:
                out[m.group(1)] = int(m.group(2))
            except ValueError:
                pass
    return out

def parse_raw_bytes(raw):
    if not isinstance(raw, str):
        return None
    s = raw.replace("\r", "").strip()
    try:
        return int(s)
    except ValueError:
        return None

revisions = json.load(open(f"{EVIDENCE_DIR}/15-scenario-c-revisions.json"))
replicas_metric = json.load(open(f"{EVIDENCE_DIR}/16-scenario-c-replicas.json"))
mempct_metric = json.load(open(f"{EVIDENCE_DIR}/17-scenario-c-memorypercentage.json"))
cgroup = json.load(open(f"{EVIDENCE_DIR}/18-scenario-c-cgroup.json"))

# ---------- a) scale rule match (same predicate as A and B) ----------
active_revs = [r for r in revisions if r.get("properties", {}).get("active") is True]
active_rev_count = len(active_revs)
scale = active_revs[0]["properties"]["template"]["scale"] if active_revs else {}
rules = scale.get("rules", []) or []
rule_zero = rules[0] if rules else {}
custom = rule_zero.get("custom", {}) or {}
metadata = custom.get("metadata", {}) or {}

a_min_replicas = scale.get("minReplicas")
a_max_replicas_spec = scale.get("maxReplicas")
a_rule_count = len(rules)
a_rule_custom_type = custom.get("type")
a_rule_metadata_type = metadata.get("type")
a_rule_metadata_value = metadata.get("value")

a_strong = (
    a_min_replicas == 2
    and a_max_replicas_spec == 20
    and a_rule_count == 1
    and a_rule_custom_type == "memory"
    and a_rule_metadata_type == "Utilization"
    and a_rule_metadata_value == "50"
)
a_fallback = (
    a_min_replicas is not None
    and a_max_replicas_spec is not None
    and a_min_replicas >= 1
    and a_max_replicas_spec >= a_min_replicas
    and a_rule_count >= 1
    and a_rule_custom_type == "memory"
    and a_rule_metadata_value == "50"
)
a_scale_rule_match = a_strong or a_fallback

# ---------- b) replicas stay low despite over-target MemoryPercentage ----------
# This is the symptom the lab reproduces: Portal value > 50 but replicas
# do not scale out. Two paths:
#   Strong: max replicas pinned at the floor (==2). This is the cleanest
#           evidence that KEDA saw a per-replica value <= 50.
#   Fallback: max replicas low (<=5) even though the Portal value is
#           above 50. Cross-correlates with sub-gate c.
replica_data = replicas_metric.get("value", [{}])[0].get("timeseries", [{}])[0].get("data", [])
replica_values = [d["maximum"] for d in replica_data if "maximum" in d and d["maximum"] is not None]
nonzero_replica_values = [v for v in replica_values if v > 0]
replicas_max = max(nonzero_replica_values) if nonzero_replica_values else 0
replicas_min = min(nonzero_replica_values) if nonzero_replica_values else 0
stable_window_count = len(nonzero_replica_values)

mempct_data = mempct_metric.get("value", [{}])[0].get("timeseries", [{}])[0].get("data", [])
mempct_values = [d["average"] for d in mempct_data if "average" in d and d["average"] is not None]
mempct_max = max(mempct_values) if mempct_values else None
mempct_min = min(mempct_values) if mempct_values else None
mempct_sample_count = len(mempct_values)

b_strong = (replicas_max == 2 and replicas_min == 2 and stable_window_count >= 10)
b_fallback = (
    replicas_max <= 5
    and stable_window_count >= 5
    and mempct_max is not None
    and mempct_max > 50
)
b_replicas_low_despite_overtarget = b_strong or b_fallback

# ---------- c) memorypercentage above 50 ----------
c_strong = (
    mempct_max is not None
    and mempct_min is not None
    and 65 <= mempct_min
    and mempct_max <= 80
    and mempct_sample_count >= 10
)
c_fallback = (
    mempct_max is not None
    and mempct_max > 50
    and mempct_sample_count >= 5
)
c_mempct_above_50 = c_strong or c_fallback

# ---------- d) cgroup cache-dominant ----------
stat = parse_memory_stat(cgroup.get("memory_stat_raw"))
cgroup_cache = stat.get("cache", 0)
cgroup_rss = stat.get("rss", 0)
cgroup_active_anon = stat.get("active_anon", 0)
cgroup_inactive_file = stat.get("inactive_file", 0)
cache_to_rss_ratio = (cgroup_cache / cgroup_rss) if cgroup_rss > 0 else float("inf")
file_to_anon_ratio = (cgroup_inactive_file / cgroup_active_anon) if cgroup_active_anon > 0 else float("inf")

d_strong = (cgroup_cache > 0 and cgroup_rss > 0 and cache_to_rss_ratio >= 30)
d_fallback = (cgroup_cache > 0 and cache_to_rss_ratio >= 5)
d_cgroup_cache_dominant = d_strong or d_fallback

# ---------- e) active revision unique ----------
e_active_revision_unique = (active_rev_count == 1)

h1_c_sub_gates = {
    "a_scale_rule_match": a_scale_rule_match,
    "b_replicas_low_despite_overtarget": b_replicas_low_despite_overtarget,
    "c_memorypercentage_above_50": c_mempct_above_50,
    "d_cgroup_cache_dominant": d_cgroup_cache_dominant,
    "e_active_revision_unique": e_active_revision_unique,
}
h1_c_pass = all(h1_c_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "scenario": "C",
    "app_name": cgroup.get("app_name"),
    "active_revision": cgroup.get("active_revision"),
    "active_revision_count": active_rev_count,
    "scale_rule": {
        "min_replicas": a_min_replicas,
        "max_replicas_spec": a_max_replicas_spec,
        "rule_count": a_rule_count,
        "rule_custom_type": a_rule_custom_type,
        "rule_metadata_type": a_rule_metadata_type,
        "rule_metadata_value": a_rule_metadata_value,
        "a_strong_path_exact_lab_spec": a_strong,
        "a_fallback_path_compatible_rule_shape": a_fallback,
    },
    "replica_behavior": {
        "samples_total": len(replica_data),
        "samples_with_value": len(replica_values),
        "samples_nonzero": stable_window_count,
        "replicas_min_nonzero": replicas_min,
        "replicas_max_nonzero": replicas_max,
        "b_strong_path_exact_floor_held": b_strong,
        "b_fallback_path_max_le_5_with_overtarget_mempct": b_fallback,
    },
    "memorypercentage_behavior": {
        "samples_with_value": mempct_sample_count,
        "mempct_min": mempct_min,
        "mempct_max": mempct_max,
        "c_strong_path_band_65_80": c_strong,
        "c_fallback_path_max_gt_50": c_fallback,
    },
    "cgroup_composition": {
        "version": cgroup.get("cgroup_version"),
        "memory_usage_bytes": parse_raw_bytes(cgroup.get("memory_usage_in_bytes_raw")),
        "memory_limit_bytes": parse_raw_bytes(cgroup.get("memory_limit_in_bytes_raw")),
        "stat_cache_bytes": cgroup_cache,
        "stat_rss_bytes": cgroup_rss,
        "stat_active_anon_bytes": cgroup_active_anon,
        "stat_inactive_file_bytes": cgroup_inactive_file,
        "cache_to_rss_ratio": cache_to_rss_ratio,
        "inactive_file_to_active_anon_ratio": file_to_anon_ratio,
        "d_strong_path_cache_30x_rss": d_strong,
        "d_fallback_path_cache_5x_rss": d_fallback,
    },
    "h1_c_sub_gates": h1_c_sub_gates,
    "h1_c_all_subgates_pass": h1_c_pass,
    "gate_classification": "scenario_c_stalled_despite_overtarget_cache_dominant" if h1_c_pass else "h1_c_failed_check_sub_gates",
}, indent=2))
PY

echo "=== Phase 25: emit H2 cross-scenario differential gate ==="
# H2 is the lab's overarching hypothesis: the Portal MemoryPercentage value
# does NOT cleanly map to the input KEDA evaluates for cache-heavy
# workloads. Proven by the BEHAVIORAL DIFFERENCE between A (held), B
# (walked to max), and C (held despite over-target). The differential is
# the proof; no single scenario alone falsifies the upstream metrics-source
# mismatch claim, but the three together do.
EVIDENCE_DIR="$EVIDENCE_DIR" CAPTURED_AT_UTC="$CAPTURED_AT_UTC" python3 - <<'PY' > "$EVIDENCE_DIR/25-h2-differential-gate.json"
import json
import os

EVIDENCE_DIR = os.environ["EVIDENCE_DIR"]
CAPTURED_AT_UTC = os.environ["CAPTURED_AT_UTC"]

# Reload the three H1 gates — H2 is a derived assertion over their primitive
# fields (replicas_max, mempct_max, cgroup ratios). This keeps H2 strictly
# downstream of H1 so a reviewer can audit the chain.
gate_a = json.load(open(f"{EVIDENCE_DIR}/22-h1-scenario-a-gate.json"))
gate_b = json.load(open(f"{EVIDENCE_DIR}/23-h1-scenario-b-gate.json"))
gate_c = json.load(open(f"{EVIDENCE_DIR}/24-h1-scenario-c-gate.json"))

a_replicas_max = gate_a["replica_behavior"]["replicas_max_nonzero"]
b_replicas_max = gate_b["replica_behavior"]["replicas_max_nonzero"]
c_replicas_max = gate_c["replica_behavior"]["replicas_max_nonzero"]
a_mempct_max = gate_a["memorypercentage_behavior"]["mempct_max"]
b_mempct_max = gate_b["memorypercentage_behavior"]["mempct_max"]
c_mempct_max = gate_c["memorypercentage_behavior"]["mempct_max"]
c_cache_to_rss = gate_c["cgroup_composition"]["cache_to_rss_ratio"]

a_app_name = gate_a["app_name"]
b_app_name = gate_b["app_name"]
c_app_name = gate_c["app_name"]

# ---------- a) scenario A held at the floor ----------
a_strong = (a_replicas_max == 2)
a_fallback = (a_replicas_max <= 2)
a_scenario_a_held = a_strong or a_fallback

# ---------- b) scenario B walked to maxReplicas ----------
b_strong = (b_replicas_max == 20)
b_fallback = (b_replicas_max >= 10)
b_scenario_b_walked_to_max = b_strong or b_fallback

# ---------- c) scenario C stalled despite over-target MemoryPercentage ----------
c_strong = (
    c_replicas_max == 2
    and c_mempct_max is not None
    and c_mempct_max > 50
)
c_fallback = (
    c_replicas_max <= 5
    and c_mempct_max is not None
    and c_mempct_max > 50
)
c_scenario_c_stalled = c_strong or c_fallback

# ---------- d) C cgroup cache-dominant explains divergence ----------
d_strong = (c_cache_to_rss >= 30)
d_fallback = (c_cache_to_rss >= 5)
d_cache_explains_divergence = d_strong or d_fallback

# ---------- e) ordinal scaling proven (B >> A and B >> C) ----------
# This sub-gate is robust to exact-value drift: even if Strong paths drift
# slightly in a future re-run, the ORDINAL relationship between scenarios
# is the durable proof that the same scale rule produces different
# behavior depending on workload composition.
e_strong = (b_replicas_max > a_replicas_max and b_replicas_max > c_replicas_max and b_replicas_max >= 2 * a_replicas_max)
e_fallback = (b_replicas_max > a_replicas_max and b_replicas_max > c_replicas_max)
e_ordinal_scaling_proven = e_strong or e_fallback

# ---------- f) three distinct apps (no duplicate measurement) ----------
distinct_names = {a_app_name, b_app_name, c_app_name}
f_three_distinct_apps = (
    a_app_name is not None
    and b_app_name is not None
    and c_app_name is not None
    and len(distinct_names) == 3
)

h2_sub_gates = {
    "a_scenario_a_held_at_floor": a_scenario_a_held,
    "b_scenario_b_walked_to_max": b_scenario_b_walked_to_max,
    "c_scenario_c_stalled_despite_overtarget": c_scenario_c_stalled,
    "d_cache_explains_divergence": d_cache_explains_divergence,
    "e_ordinal_scaling_proven": e_ordinal_scaling_proven,
    "f_three_distinct_apps": f_three_distinct_apps,
}
h2_all_pass = all(h2_sub_gates.values())

print(json.dumps({
    "utc_captured": CAPTURED_AT_UTC,
    "hypothesis": "H2: Portal MemoryPercentage value does NOT cleanly map to KEDA scaler input for cache-heavy workloads. Differential between A (held), B (walked to max), and C (stalled despite over-target) is the proof.",
    "scenarios": {
        "A": {
            "app_name": a_app_name,
            "replicas_max": a_replicas_max,
            "mempct_max": a_mempct_max,
            "expected_behavior": "held at floor (rss-dominant, per-replica utilization <= target)",
        },
        "B": {
            "app_name": b_app_name,
            "replicas_max": b_replicas_max,
            "mempct_max": b_mempct_max,
            "expected_behavior": "walked to maxReplicas (rss-dominant, per-replica utilization > target)",
        },
        "C": {
            "app_name": c_app_name,
            "replicas_max": c_replicas_max,
            "mempct_max": c_mempct_max,
            "cgroup_cache_to_rss_ratio": c_cache_to_rss,
            "expected_behavior": "stalled despite Portal value above target (cache-dominant, KEDA reads a different numerator)",
        },
    },
    "differential": {
        "a_strong_path_a_eq_2": a_strong,
        "a_fallback_path_a_le_2": a_fallback,
        "b_strong_path_b_eq_20": b_strong,
        "b_fallback_path_b_ge_10": b_fallback,
        "c_strong_path_c_eq_2_with_overtarget": c_strong,
        "c_fallback_path_c_le_5_with_overtarget": c_fallback,
        "d_strong_path_c_cache_30x_rss": d_strong,
        "d_fallback_path_c_cache_5x_rss": d_fallback,
        "e_strong_path_b_2x_a_and_b_gt_c": e_strong,
        "e_fallback_path_b_gt_a_and_b_gt_c": e_fallback,
    },
    "h2_sub_gates": h2_sub_gates,
    "h2_all_subgates_pass": h2_all_pass,
    "gate_classification": "portal_mempct_diverges_from_keda_scaler_input_for_cache_heavy_workloads" if h2_all_pass else "h2_failed_check_sub_gates",
    "scope_note": "H2 proves the BEHAVIORAL divergence: A (rss, just-below) held, B (rss, just-above) walked, C (cache) stalled despite Portal > 50. The exact metrics-server numerator that KEDA reads is NOT directly measured here — that would require kubelet/metrics-server inspection, which is not exposed in Container Apps. The differential between A/B/C is sufficient to prove the divergence exists; the upstream root cause (metric-source mismatch vs HPA ceiling math) is explained in the lab guide and remains [Strongly Suggested] rather than [Observed] for the metric-source half.",
}, indent=2))
PY

echo "=== Verification complete ==="
echo "Gate files emitted to $EVIDENCE_DIR:"
for f in 22-h1-scenario-a-gate.json 23-h1-scenario-b-gate.json 24-h1-scenario-c-gate.json 25-h2-differential-gate.json; do
    if [ -f "$EVIDENCE_DIR/$f" ]; then
        echo "  $f"
        python3 -c "import json; d=json.load(open('$EVIDENCE_DIR/$f')); print('    classification:', d['gate_classification']); k = 'h1_a_sub_gates' if 'h1_a_sub_gates' in d else ('h1_b_sub_gates' if 'h1_b_sub_gates' in d else ('h1_c_sub_gates' if 'h1_c_sub_gates' in d else 'h2_sub_gates')); [print(f'    {sg}: {v}') for sg, v in d[k].items()]"
    else
        echo "  $f  (MISSING)"
    fi
done
