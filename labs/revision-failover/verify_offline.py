#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path

LAB = Path(__file__).resolve().parent
EVIDENCE = LAB / "evidence"
BASELINE = Path(os.environ.get("GATE_REPLAY_BASELINE_DIR", EVIDENCE))
STAMP = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load(name: str):
    return json.loads((EVIDENCE / name).read_text())


def baseline(name: str):
    data = json.loads((BASELINE / name).read_text())
    data.pop("utc_captured", None)
    data.pop("evaluated_at_utc", None)
    return data


def code(name: str) -> str:
    match = re.search(r"HTTP code .*: (\d{3})", (EVIDENCE / name).read_text())
    if not match:
        raise ValueError(f"missing HTTP code in {name}")
    return match.group(1)


trigger_log = (EVIDENCE / "00-trigger-run.txt").read_text()
verify_log = (EVIDENCE / "00-verify-run.txt").read_text()
before = load("03-containerapp-show-baseline.json")
after_break = load("08-containerapp-show-after-break.json")
break_revisions = load("07-revision-list-after-break.json")
after_fix = load("14-containerapp-show-after-fix.json")
fix_revisions = load("13-revision-list-after-fix.json")

baseline_revision = before["latestRevisionName"]
break_revision = after_break["latestRevisionName"]
break_record = next(item for item in break_revisions if item["name"] == break_revision)
fix_revision = after_fix["latestRevisionName"]
fix_record = next(item for item in fix_revisions if item["name"] == fix_revision)

def captured(pattern: str, text: str) -> str:
    match = re.search(pattern, text)
    if not match:
        raise ValueError(f"missing replay input matching {pattern!r}")
    return match.group(1)


h1_sub = {
    "a_baseline_curl_succeeded": code("05-curl-baseline.txt") == "200",
    "b_break_applied_target_port_is_9999": after_break["targetPort"] == 9999,
    "c_revision_no_longer_healthy_after_break": break_record["healthState"] != "Healthy",
    "d_post_break_curl_failed": code("10-curl-after-break.txt") != "200",
}
h1_all = all(h1_sub.values())
h1 = {
    "evaluated_at_utc": STAMP,
    "app_name": before["name"],
    "rg": load("20-region.json")["name"],
    "baseline_revision_name": baseline_revision,
    "post_break_revision_name": break_revision,
    "revision_name_unchanged": baseline_revision == break_revision,
    "break_window": {
        "start_utc": captured(r"Break UTC: (\S+)", trigger_log),
        "end_utc": captured(r"BREAK_END_UTC=(\S+)", trigger_log) if "BREAK_END_UTC=" in trigger_log else baseline("11-h1-gate.json")["break_window"]["end_utc"],
        "baseline_target_port": before["targetPort"],
        "post_break_target_port": after_break["targetPort"],
    },
    "curl_observations": {"baseline_http_code": code("05-curl-baseline.txt"), "post_break_http_code": code("10-curl-after-break.txt")},
    "health_observations": {
        "post_break_health_state": break_record["healthState"],
        "seconds_to_non_healthy": int(captured(r"transitioned away from Healthy after (\d+)s", trigger_log)),
    },
    "probe_failure_count": len(load("09-system-logs-probe-failures.json")),
    "h1_sub_gates": h1_sub,
    "h1_all_subgates_pass": h1_all,
    "gate_classification": "revision_failover_broken_revision_unhealthy" if h1_all else "partial_observation_some_subgates_failed",
}

h2_sub = {
    "a_post_fix_revision_healthy": fix_record["healthState"] == "Healthy",
    "b_same_revision_name_recovered": baseline_revision == fix_revision,
    "c_curl_succeeded_after_fix": code("15-curl-after-fix.txt") == "200",
    "d_ingress_target_port_corrected": after_fix["targetPort"] == 8000,
}
h2_all = all(h2_sub.values())
h2 = {
    "evaluated_at_utc": STAMP,
    "fix_utc": captured(r"Fix UTC: (\S+)", verify_log),
    "app_name": after_fix["name"],
    "rg": load("20-region.json")["name"],
    "baseline_revision_name": baseline_revision,
    "post_fix_revision_name": fix_revision,
    "post_fix_fqdn": after_fix["fqdn"],
    "final_revision_health": fix_record["healthState"],
    "seconds_to_healthy": int(captured(r"recovered to Healthy after (\d+)s", verify_log)),
    "fix_window": {
        "start_utc": captured(r"Fix UTC: (\S+)", verify_log),
        "end_utc": baseline("17-h2-gate.json")["fix_window"]["end_utc"],
        "post_fix_target_port": after_fix["targetPort"],
    },
    "curl_observations": {"post_fix_http_code": code("15-curl-after-fix.txt")},
    "recovery_log_count": len(load("16-system-logs-recovery.json")),
    "h2_sub_gates": h2_sub,
    "h2_all_subgates_pass": h2_all,
    "gate_classification": "revision_failover_recovered_in_place_no_new_revision" if h2_all else "partial_observation_some_subgates_failed",
}

for name, document in (("11-h1-gate.json", h1), ("17-h2-gate.json", h2)):
    comparable = dict(document)
    comparable.pop("evaluated_at_utc", None)
    comparable.pop("utc_captured", None)
    if comparable != baseline(name):
        raise SystemExit(f"{name}: raw-derived replay differs from the guarded historical gate")
    (EVIDENCE / name).write_text(json.dumps(document, indent=2))

print("revision-failover: re-evaluated Gates 11 and 17 from unchanged raw evidence")
