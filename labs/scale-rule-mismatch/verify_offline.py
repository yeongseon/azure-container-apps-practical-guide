#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

LAB = Path(__file__).resolve().parent
EVIDENCE = LAB / "evidence"
STAMP = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load(name: str):
    return json.loads((EVIDENCE / name).read_text())


def replica_count(name: str) -> int:
    return len(load(name))


def captured(pattern: str, text: str) -> str:
    match = re.search(pattern, text)
    if not match:
        raise ValueError(f"missing replay input matching {pattern!r}")
    return match.group(1)


trigger_log = (EVIDENCE / "00-trigger-run.txt").read_text()
verify_log = (EVIDENCE / "00-verify-run.txt").read_text()
before = load("03-containerapp-show-baseline.json")
after = load("12-containerapp-show-after-fix.json")
pre_counts = [replica_count(name) for name in (
    "05-replicas-load-15s.json", "06-replicas-load-30s.json",
    "07-replicas-load-60s.json", "08-replicas-load-90s.json",
)]
post_counts = [replica_count(name) for name in (
    "14-replicas-load-15s-after-fix.json", "15-replicas-load-30s-after-fix.json",
    "16-replicas-load-60s-after-fix.json", "17-replicas-load-90s-after-fix.json",
)]
pre_event_count = len(load("09-system-logs-scale-events-pre-fix.json"))
post_event_count = len(load("18-system-logs-scale-events-after-fix.json"))

h1_sub = {
    "a_baseline_one_replica": replica_count("04-replicas-pre-load.json") == 1,
    "b_replicas_did_not_scale_under_load": max(pre_counts) <= 1,
    "c_no_scaleup_events_observed": pre_event_count == 0,
}
h1_all = all(h1_sub.values())
h1 = {
    "evaluated_at_utc": STAMP,
    "app_name": before["name"],
    "rg": load("22-region.json")["name"],
    "active_revision": before["latestRevisionName"],
    "load_window": {
        "start_utc": captured(r"Load start UTC: (\S+)", trigger_log),
        "end_utc": captured(r"Load end UTC \(strict, \+90s\): (\S+)", trigger_log),
        "duration_seconds": 90,
        "concurrent_requests_generated": 60,
        "scale_rule_threshold_configured": 500,
    },
    "replicas_observed": {
        "pre_load": replica_count("04-replicas-pre-load.json"),
        "at_15s": pre_counts[0], "at_30s": pre_counts[1],
        "at_60s": pre_counts[2], "at_90s": pre_counts[3],
        "max_during_load": max(pre_counts),
    },
    "scale_events_count": pre_event_count,
    "h1_sub_gates": h1_sub,
    "h1_all_subgates_pass": h1_all,
    "gate_classification": "scale_rule_mismatch_replicas_capped" if h1_all else "partial_observation_some_subgates_failed",
}

h2_sub = {
    "a_post_fix_revision_healthy": captured(r"Final healthState after polling: (\S+)", verify_log) == "Healthy",
    "b_replicas_increased_after_fix": max(post_counts) >= 2,
    "c_scaleup_events_observed_after_fix": post_event_count >= 1,
}
h2_all = all(h2_sub.values())
h2_classification = (
    "scale_rule_fixed_replicas_scaled_events_observed" if h2_all
    else "scale_rule_fixed_replicas_scaled_no_events" if h2_sub["a_post_fix_revision_healthy"] and h2_sub["b_replicas_increased_after_fix"]
    else "scale_rule_fixed_replicas_did_not_scale"
)
h2 = {
    "evaluated_at_utc": STAMP,
    "fix_utc": captured(r"Fix UTC: (\S+)", verify_log),
    "app_name": after["name"],
    "rg": load("22-region.json")["name"],
    "post_fix_revision": after["latestRevisionName"],
    "post_fix_fqdn": after["fqdn"],
    "final_revision_health": captured(r"Final healthState after polling: (\S+)", verify_log),
    "seconds_to_healthy": int(captured(r"New revision Healthy after (\d+)s", verify_log)),
    "post_fix_load_window": {
        "start_utc": captured(r"Load start UTC \(post-fix\): (\S+)", verify_log),
        "end_utc": captured(r"Load end UTC \(strict, \+90s\): (\S+)", verify_log),
        "duration_seconds": 90, "concurrent_requests_generated": 60,
        "scale_rule_threshold_configured_after_fix": 10,
        "max_replicas_configured_after_fix": after["scaleConfig"]["maxReplicas"],
    },
    "replicas_observed_after_fix": {
        "pre_load": replica_count("13-replicas-pre-load-after-fix.json"),
        "at_15s": post_counts[0], "at_30s": post_counts[1],
        "at_60s": post_counts[2], "at_90s": post_counts[3],
        "max_during_load": max(post_counts),
    },
    "scale_events_count_after_fix": post_event_count,
    "h2_sub_gates": h2_sub,
    "h2_all_subgates_pass": h2_all,
    "gate_classification": h2_classification,
}

for name, document in (("10-h1-gate.json", h1), ("19-h2-gate.json", h2)):
    (EVIDENCE / name).write_text(json.dumps(document, indent=2))

print("scale-rule-mismatch: re-evaluated Gates 10 and 19 from unchanged raw evidence")
