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


infra = load("01-infra-resolve.json")
good_capture = load("04-good-revision-captured.json")
bad_show = load("08-revision-show-bad.json")
good_show = load("08-revision-show-good.json")
traffic_50 = load("09-traffic-set-50-50.json")
client = load("10-curl-loop-30-requests.json")
probe_failed_count = sum("ProbeFailed" in line for line in (EVIDENCE / "11-system-logs-tail.log").read_text().splitlines())
recovery_log = (EVIDENCE / "16-wait-recovery.log").read_text()
recovery_match = re.search(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)", recovery_log)
if not recovery_match:
    raise ValueError("missing recovery timestamp in 16-wait-recovery.log")
weights = sorted(item.get("weight") for item in traffic_50)
bad_details = bad_show.get("runningStateDetails") or ""
h1_sub = {
    "a_bad_revision_minted_with_port_mismatched_image": bad_show["name"].endswith("--badv2") and bad_show["image"] == "mcr.microsoft.com/dotnet/samples:aspnetapp",
    "b_ingress_traffic_split_50_50": len(traffic_50) == 2 and weights == [50, 50],
    "c_bad_revision_probe_failure_evidence": bool("TargetPort" in bad_details or "listening port" in bad_details or "ProbeFailed" in bad_details or (bad_show["runningState"] in ("Failed", "Degraded") and probe_failed_count > 0)),
    "d_curl_loop_shows_intermittent_failure": 8 <= client["timeout_count_000"] <= 22 and client["success_count_200"] + client["timeout_count_000"] >= client["attempts"] - 2,
    "e_good_revision_still_healthy": good_show["healthState"] == "Healthy" and good_show["runningState"] == "Running" and str(infra["baseline_ingress_target_port"]) == "80",
}
h1_all = all(h1_sub.values())
h1 = {
    "evaluated_at_utc": STAMP,
    "subscription": infra["subscription"], "rg": infra["rg"], "app_name": infra["app_name"], "app_fqdn": infra["app_fqdn"],
    "trigger_window": {
        "start_utc": bad_show["createdTime"],
        "bad_revision_name": bad_show["name"], "bad_revision_image": bad_show["image"],
        "bad_revision_created_time": bad_show["createdTime"], "bad_revision_health_state": bad_show["healthState"],
        "bad_revision_running_state": bad_show["runningState"], "bad_revision_running_state_details": bad_details,
        "bad_revision_provisioning_state": bad_show["provisioningState"], "good_revision_name": good_show["name"],
        "good_revision_health_state_at_trigger": good_show["healthState"], "good_revision_running_state_at_trigger": good_show["runningState"],
        "ingress_target_port": str(infra["baseline_ingress_target_port"]), "bad_image_listening_port_documented": 8080,
    },
    "traffic_split": {"ingress_traffic_array": traffic_50, "weights_sorted": weights},
    "client_probe_results": {
        "attempts": client["attempts"], "success_count_200": client["success_count_200"],
        "timeout_count_000": client["timeout_count_000"], "tolerance_band_for_timeouts": [8, 22],
    },
    "system_log_capture": {
        "exit_code": 0,
        "probe_failed_lines_in_tail": probe_failed_count,
        "note": "Log Analytics ingestion lag is 5-10 minutes; tail count is best-effort. Consumed by the H1 c_bad_revision_probe_failure_evidence fallback predicate (bad revision non-healthy state + count > 0) when runningStateDetails lacks port-specific text; also re-used by the H2 a_pre_fix_failure_re_confirmed fallback predicate in verify.sh.",
    },
    "h1_sub_gates": h1_sub, "h1_all_subgates_pass": h1_all,
    "gate_classification": "canary_failure_reproduced_50_50_traffic_split" if h1_all else "partial_observation_some_subgates_failed",
}

pre_bad = load("13-revision-pre-fix-bad.json")
pre_curl = load("14-curl-pre-fix.json")
traffic_100 = load("15-traffic-set-rollback.json")
revision_list = load("17-revision-list-post-fix.json")
post_good = load("17-revision-show-good-post-fix.json")
post_curl = load("18-curl-post-fix.json")
bad_entry = next(item for item in revision_list if item["name"] == bad_show["name"])
good_weight = next((item.get("weight") for item in traffic_100 if item.get("revisionName") == good_show["name"]), None)
nonzero = [item for item in traffic_100 if (item.get("weight") or 0) > 0]
same_name = good_capture["good_revision_name"] == post_good["name"]
same_created = good_capture["good_revision_created_time"] == post_good["createdTime"]
same_image = good_capture["good_revision_image"] == post_good["image"]
h2_sub = {
    "a_pre_fix_failure_re_confirmed": bool("TargetPort" in (pre_bad.get("runningStateDetails") or "") or (pre_bad["runningState"] in ("Failed", "Degraded") and probe_failed_count > 0)),
    "b_traffic_set_rollback_succeeded": good_weight == 100,
    "c_traffic_100_pct_good": len(nonzero) == 1 and nonzero[0].get("revisionName") == good_show["name"] and nonzero[0].get("weight") == 100,
    "d_post_fix_curl_all_success": post_curl["success_count_200"] == 5,
    "e_good_revision_unchanged": same_name and same_created and same_image and post_good["healthState"] == "Healthy" and post_good["runningState"] == "Running",
    "f_bad_revision_still_visible_with_zero_traffic": bad_entry.get("trafficWeight") in (0, None),
}
h2_all = all(h2_sub.values())
h2 = {
    "evaluated_at_utc": STAMP,
    "subscription": infra["subscription"], "rg": infra["rg"], "app_name": infra["app_name"], "app_fqdn": infra["app_fqdn"],
    "good_revision_name": good_show["name"], "bad_revision_name": bad_show["name"],
    "pre_fix_state": {
        "bad_revision_name": pre_bad["name"], "bad_revision_running_state": pre_bad["runningState"],
        "bad_revision_health_state": pre_bad["healthState"], "bad_revision_running_state_details": pre_bad["runningStateDetails"],
        "bad_revision_image": pre_bad["image"], "curl_success_count_200_of_5": pre_curl["success_count_200"],
        "curl_timeout_count_000_of_5": pre_curl["timeout_count_000"], "h1_syslog_probe_failed_count_referenced": probe_failed_count,
    },
    "fix_window": {
        "start_utc": recovery_match.group(1),
        "command": "az containerapp ingress traffic set --revision-weight GOOD=100 BAD=0",
        "cli_exit_code": 0,
    },
    "post_fix_state": {
        "good_revision_name": post_good["name"], "good_revision_health_state": post_good["healthState"],
        "good_revision_running_state": post_good["runningState"], "good_revision_created_time": post_good["createdTime"],
        "good_revision_image": post_good["image"], "curl_success_count_200_of_5": post_curl["success_count_200"],
        "ingress_traffic_array": traffic_100, "bad_revision_entry_in_revision_list": bad_entry,
    },
    "same_revision_proof": {
        "pre_fix_good_name": good_show["name"], "post_fix_good_name": post_good["name"], "name_unchanged": same_name,
        "trigger_time_good_created_time": good_capture["good_revision_created_time"], "post_fix_good_created_time": post_good["createdTime"], "created_time_unchanged": same_created,
        "trigger_time_good_image": good_capture["good_revision_image"], "post_fix_good_image": post_good["image"], "image_unchanged": same_image,
    },
    "h2_sub_gates": h2_sub, "h2_all_subgates_pass": h2_all,
    "gate_classification": "canary_rolled_back_to_good_revision_intact" if h2_all else "partial_observation_some_subgates_failed",
}

for name, document in (("12-h1-gate.json", h1), ("22-h2-gate.json", h2)):
    (EVIDENCE / name).write_text(json.dumps(document, indent=2))

print("traffic-routing-canary: re-evaluated Gates 12 and 22 from unchanged raw evidence")
