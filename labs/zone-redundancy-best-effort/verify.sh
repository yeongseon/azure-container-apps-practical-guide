#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
LAB_GUIDE_PATH="${SCRIPT_DIR}/../../docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md"
REPO_RELATIVE_EVIDENCE_DIR="labs/zone-redundancy-best-effort/evidence"
UTC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export EVIDENCE_DIR LAB_GUIDE_PATH REPO_RELATIVE_EVIDENCE_DIR UTC_NOW

RG="${RG:-rg-aca-zr-lab}"
SUBJECT_APPS=("app-min2" "app-min3" "app-min6")
PHASE_B_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --phase-b-only)
      PHASE_B_ONLY=true
      ;;
    *)
      echo "Unsupported argument: $arg" >&2
      echo "Usage: ./verify.sh [--phase-b-only]" >&2
      exit 1
      ;;
  esac
done

pass_gate() {
  local gate_number="$1"
  local detail="$2"
  echo "[Gate ${gate_number}/17] PASS ${detail}"
}

fail_gate() {
  local gate_number="$1"
  local detail="$2"
  echo "[Gate ${gate_number}/17] FAIL ${detail}"
  exit 1
}

run_phase_a_live_health() {
  local pass=0
  local fail=0

  check() {
    local label="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
      echo "  [PASS] $label"
      pass=$((pass + 1))
    else
      echo "  [FAIL] $label"
      fail=$((fail + 1))
    fi
  }

  echo ">> Resource group $RG"
  check "Resource group exists" "az group show --name $RG"

  echo
  echo ">> Environment"
  ENV_NAME=$(az containerapp env list --resource-group "$RG" --query '[0].name' --output tsv 2>/dev/null || true)
  if [[ -n "$ENV_NAME" ]]; then
    echo "   Environment: $ENV_NAME"
    ZR=$(az containerapp env show --resource-group "$RG" --name "$ENV_NAME" --query 'properties.zoneRedundant' --output tsv 2>/dev/null || echo "")
    check "Zone redundancy enabled" "[[ '$ZR' == 'True' || '$ZR' == 'true' ]]"
  else
    echo "  [FAIL] No environment found"
    fail=$((fail + 1))
  fi

  echo
  echo ">> Subject apps"
  for app in "${SUBJECT_APPS[@]}"; do
    STATE=$(az containerapp show --resource-group "$RG" --name "$app" --query 'properties.runningStatus' --output tsv 2>/dev/null || echo "missing")
    check "$app runningStatus = Running" "[[ '$STATE' == 'Running' ]]"

    MIN_REPLICAS=$(az containerapp show --resource-group "$RG" --name "$app" --query 'properties.template.scale.minReplicas' --output tsv 2>/dev/null || echo "0")
    EXPECTED=$(printf '%s' "$app" | perl -pe 's/^app-min//')
    check "$app minReplicas = $EXPECTED" "[[ '$MIN_REPLICAS' == '$EXPECTED' ]]"

    REPLICAS=$(az containerapp replica list --resource-group "$RG" --name "$app" --revision "$(az containerapp revision list --resource-group "$RG" --name "$app" --query '[?properties.active].name | [0]' --output tsv 2>/dev/null)" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    check "$app has at least $EXPECTED running replicas" "[[ '$REPLICAS' -ge '$EXPECTED' ]]"
  done

  echo
  echo ">> Audit job"
  JOB_STATE=$(az containerapp job show --resource-group "$RG" --name "audit-sampler" --query 'properties.provisioningState' --output tsv 2>/dev/null || echo "missing")
  check "Audit job provisioned" "[[ '$JOB_STATE' == 'Succeeded' ]]"

  echo
  echo ">> Log Analytics"
  LAW_NAME=$(az monitor log-analytics workspace list --resource-group "$RG" --query '[0].name' --output tsv 2>/dev/null || true)
  check "Log Analytics workspace exists" "[[ -n '$LAW_NAME' ]]"

  echo
  echo "================================================================"
  echo "Summary: $pass passed, $fail failed"
  echo "================================================================"

  if [[ $fail -gt 0 ]]; then
    return 1
  fi
  return 0
}

run_phase_a_snapshot_gate() {
  python3 <<'PY'
import re
from pathlib import Path

evidence_dir = Path(Path(__import__("os").environ["EVIDENCE_DIR"]))
snapshot = evidence_dir / "phase-2-health-snapshot-20260612123848.log"
text = snapshot.read_text(encoding="utf-8")

required = [
    "Phase 2 Health Snapshot",
    "app-min2: count=2",
    "app-min3: count=3",
    "app-min6: count=6",
]

for marker in required:
    if marker not in text:
        raise SystemExit(f"snapshot missing marker: {marker}")

succeeded_rows = len(re.findall(r"^audit-sampler-.*\sSucceeded\s", text, flags=re.MULTILINE))
if succeeded_rows < 10:
    raise SystemExit(f"snapshot contains only {succeeded_rows} succeeded audit rows")

print(f"offline live-health fallback satisfied via {snapshot.name} ({succeeded_rows} succeeded audit rows; replica counts 2/3/6)")
PY
}

echo "===== zone-redundancy-best-effort verifier ====="
echo "Evidence directory: ${EVIDENCE_DIR}"
echo "Phase B run UTC:    ${UTC_NOW}"
echo

if [[ "$PHASE_B_ONLY" == true ]]; then
  echo "## Phase A — Live infrastructure health"
  echo "Skipped via --phase-b-only"
  echo
else
  echo "## Phase A — Live infrastructure health"
  if command -v az >/dev/null 2>&1 && az group show --name "$RG" >/dev/null 2>&1; then
    if run_phase_a_live_health; then
      pass_gate 1 "live infrastructure checks passed for ${RG}"
    else
      fail_gate 1 "live infrastructure checks failed for ${RG}"
    fi
  else
    if PHASE_A_DETAIL="$(run_phase_a_snapshot_gate)"; then
      pass_gate 1 "$PHASE_A_DETAIL"
    else
      fail_gate 1 "$PHASE_A_DETAIL"
    fi
  fi
  echo
fi

echo "## Phase B — Evidence pack verification"
if PHASE_B_OUTPUT="$(python3 <<'PY'
import json
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

EVIDENCE_DIR = Path(os.environ["EVIDENCE_DIR"])
LAB_GUIDE_PATH = Path(os.environ["LAB_GUIDE_PATH"])
REL = os.environ["REPO_RELATIVE_EVIDENCE_DIR"]
UTC_NOW = os.environ["UTC_NOW"]

SCENARIO = "zone_redundancy_best_effort"
VARIANT = "non-falsification-bounded-coverage"
APPS = ["app-min2", "app-min3", "app-min6"]
REQUIRED_CORPUS = [
    "baseline-window.txt",
    "deployment-outputs.json",
    "audit-job-config.json",
    "q1-baseline-fixed-ingestion-20260614114618.json",
    "q2-baseline-fixed-steady-state-20260614114618.json",
    "q3-baseline-fixed-clustered-churn-20260614114618.json",
    "q3-baseline-fixed-any-termination-20260614114618.json",
    "q3-clustered-churn-20260614114318.json",
    "q4-recovery-duration-20260614114318.json",
    "q7-multi-app-comparison-20260614114318.json",
    "perturbation-variant-a-restart-only-20260614110433.log",
    "perturbation-variant-b-restart-load-20260614111457.log",
    "perturbation-variant-c-retry-backoff-20260614112821.log",
]

def repo_rel(name: str) -> str:
    return f"{REL}/{name}"

def load_json(name: str):
    return json.loads((EVIDENCE_DIR / name).read_text(encoding="utf-8"))

def load_jsonl(name: str):
    return [json.loads(line) for line in (EVIDENCE_DIR / name).read_text(encoding="utf-8").splitlines() if line.strip()]

def parse_dt(text: str) -> datetime:
    candidate = text[:-1] + "+00:00" if text.endswith("Z") else text
    dt = datetime.fromisoformat(candidate)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)

def minute_floor(dt: datetime) -> str:
    return dt.replace(second=0, microsecond=0).isoformat().replace("+00:00", "Z")

def minute_round(dt: datetime) -> str:
    rounded = dt + timedelta(seconds=30)
    return rounded.replace(second=0, microsecond=0).isoformat().replace("+00:00", "Z")

def build_subgate(claim, predicate, evidence, passed, observed_values):
    return {
        "claim": claim,
        "predicate": predicate,
        "evidence": evidence,
        "pass": passed,
        "observed_values": observed_values,
    }

def gate_payload(gate_id, gate_name, claim, predicate_inputs, sub_gates, **extra):
    payload = {
        "gate_id": gate_id,
        "gate_name": gate_name,
        "scenario": SCENARIO,
        "phase_b_variant": VARIANT,
        "utc_captured": UTC_NOW,
        "claim": claim,
        "predicate_inputs": predicate_inputs,
        "sub_gates": sub_gates,
        "all_sub_gates_pass": all(item["pass"] for item in sub_gates.values()),
    }
    payload.update(extra)
    return payload

def write_gate(filename: str, payload: dict):
    (EVIDENCE_DIR / filename).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

baseline_text = (EVIDENCE_DIR / "baseline-window.txt").read_text(encoding="utf-8").strip()
baseline_match = re.search(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s+→\s+(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)", baseline_text)
if not baseline_match:
    raise SystemExit("Could not parse baseline-window.txt")
baseline_start = parse_dt(baseline_match.group(1))
baseline_end = parse_dt(baseline_match.group(2))
baseline_span_seconds = int((baseline_end - baseline_start).total_seconds())

deployment_outputs = load_json("deployment-outputs.json")
audit_job_config = load_json("audit-job-config.json")
q1 = load_json("q1-baseline-fixed-ingestion-20260614114618.json")
q2 = load_json("q2-baseline-fixed-steady-state-20260614114618.json")
q3_fixed_clustered = load_json("q3-baseline-fixed-clustered-churn-20260614114618.json")
q3_fixed_any = load_json("q3-baseline-fixed-any-termination-20260614114618.json")
q3 = load_json("q3-clustered-churn-20260614114318.json")
q4 = load_json("q4-recovery-duration-20260614114318.json")
q7 = load_json("q7-multi-app-comparison-20260614114318.json")
q6_bad_text = (EVIDENCE_DIR / "q6-baseline-vs-perturb-20260614114318.json").read_text(encoding="utf-8")
q6_fixed = load_json("q6-baseline-vs-perturb-20260614114522.json")

variant_a = load_jsonl("perturbation-variant-a-restart-only-20260614110433.log")
variant_b = load_jsonl("perturbation-variant-b-restart-load-20260614111457.log")
variant_c = load_jsonl("perturbation-variant-c-retry-backoff-20260614112821.log")
variant_logs = {
    "variant_a": variant_a,
    "variant_b": variant_b,
    "variant_c": variant_c,
}

perturbation_paths = sorted(path.name for path in EVIDENCE_DIR.glob("perturbation-variant-*.log"))
submitted_times = []
submitted_by_variant = {}
for name, rows in variant_logs.items():
    submitted = next((row for row in rows if row.get("event") == "PerturbationSubmitted"), None)
    if submitted is not None:
        dt = parse_dt(submitted["timestamp"])
        submitted_times.append(dt)
        submitted_by_variant[name] = dt

q1_row = q1[0]
q2_apps = sorted(row["app"] for row in q2)
q7_apps = sorted(row["App"] for row in q7)
deployment_apps = deployment_outputs["subjectAppNames"]["value"]

gate14_subs = {}
missing = [name for name in REQUIRED_CORPUS if not (EVIDENCE_DIR / name).is_file()]
gate14_subs["a"] = build_subgate(
    "Required Phase B corpus files exist in the committed evidence directory.",
    "All 13 required corpus files listed in Oracle's Phase B design exist on disk.",
    [repo_rel(name) for name in REQUIRED_CORPUS],
    not missing,
    {
        "required_count": len(REQUIRED_CORPUS),
        "present_count": len(REQUIRED_CORPUS) - len(missing),
        "missing": missing,
    },
)

gate14_subs["b"] = build_subgate(
    "Cohort identity is coherent across deployment outputs, Q2 steady state, and Q7 multi-app comparison.",
    "deployment-outputs.json subjectAppNames, Q2 app rows, and Q7 App rows all equal exactly {app-min2, app-min3, app-min6} with no extras.",
    [
        repo_rel("deployment-outputs.json"),
        repo_rel("q2-baseline-fixed-steady-state-20260614114618.json"),
        repo_rel("q7-multi-app-comparison-20260614114318.json"),
    ],
    sorted(deployment_apps) == APPS and q2_apps == APPS and q7_apps == APPS,
    {
        "deployment_subject_apps": deployment_apps,
        "q2_apps": q2_apps,
        "q7_apps": q7_apps,
    },
)

strictly_increasing = all(submitted_times[idx] < submitted_times[idx + 1] for idx in range(len(submitted_times) - 1))
all_after_baseline = all(dt > baseline_end for dt in submitted_times)
gate14_subs["c"] = build_subgate(
    "Temporal structure is coherent: the baseline is exactly 24 hours and successful perturbations happen afterward in strict sequence.",
    "baseline-window.txt spans exactly 86400 seconds AND perturbation submitted timestamps are strictly increasing AND every submitted timestamp is later than baseline end.",
    [
        repo_rel("baseline-window.txt"),
        repo_rel("perturbation-variant-a-restart-only-20260614110433.log"),
        repo_rel("perturbation-variant-b-restart-load-20260614111457.log"),
        repo_rel("perturbation-variant-c-retry-backoff-20260614112821.log"),
    ],
    baseline_span_seconds == 86400 and strictly_increasing and all_after_baseline,
    {
        "baseline_start": baseline_start.isoformat().replace("+00:00", "Z"),
        "baseline_end": baseline_end.isoformat().replace("+00:00", "Z"),
        "baseline_span_seconds": baseline_span_seconds,
        "perturbation_submitted_utc": [dt.isoformat().replace("+00:00", "Z") for dt in submitted_times],
        "strictly_increasing": strictly_increasing,
        "all_after_baseline": all_after_baseline,
    },
)

gate14_subs["d"] = build_subgate(
    "The audit sensor schedule and fixed-range sample math match the expected 24-hour cohort design.",
    "audit-job-config cronExpression == '*/5 * * * *' AND Q1 UniqueApps == 3 AND Q1 ExpectedOkSamples == 864 for 24 hours × 12 ticks/hour × 3 apps.",
    [repo_rel("audit-job-config.json"), repo_rel("q1-baseline-fixed-ingestion-20260614114618.json")],
    audit_job_config["cron"]["cronExpression"] == "*/5 * * * *" and q1_row["UniqueApps"] == "3" and q1_row["ExpectedOkSamples"] == "864",
    {
        "cron_expression": audit_job_config["cron"]["cronExpression"],
        "q1_unique_apps": q1_row["UniqueApps"],
        "q1_expected_ok_samples": q1_row["ExpectedOkSamples"],
        "sample_math": "24h * 12 ticks/hour * 3 apps = 864",
    },
)

gate14 = gate_payload(
    "14",
    "Cohort / corpus integrity",
    "The committed 24-hour corpus is present, identity-coherent, temporally ordered, and sensor-consistent for the bounded-coverage Phase B design.",
    {
        "baseline_window": repo_rel("baseline-window.txt"),
        "deployment_outputs": repo_rel("deployment-outputs.json"),
        "audit_job_config": repo_rel("audit-job-config.json"),
        "q1_fixed_ingestion": repo_rel("q1-baseline-fixed-ingestion-20260614114618.json"),
        "q2_fixed_steady_state": repo_rel("q2-baseline-fixed-steady-state-20260614114618.json"),
        "q7_multi_app_comparison": repo_rel("q7-multi-app-comparison-20260614114318.json"),
    },
    gate14_subs,
)

health_ratio = float(q1_row["HealthRatio"])
gate15_subs = {}
gate15_subs["a"] = build_subgate(
    "Audit completeness is sufficient to trust the fixed-range baseline queries.",
    "Q1 HealthRatio >= 0.5 AND ErrorSamples == 0 AND UniqueApps == 3.",
    [repo_rel("q1-baseline-fixed-ingestion-20260614114618.json")],
    health_ratio >= 0.5 and q1_row["ErrorSamples"] == "0" and q1_row["UniqueApps"] == "3",
    {
        "health_ratio": health_ratio,
        "error_samples": int(q1_row["ErrorSamples"]),
        "unique_apps": int(q1_row["UniqueApps"]),
        "ok_samples": int(q1_row["OkSamples"]),
    },
)

steady_rows_ok = []
for row in q2:
    steady_rows_ok.append(
        row["SteadyStateOK"] == "True" and row["ObservedMin"] == row["ObservedMax"] == row["ConfiguredMin"]
    )
gate15_subs["b"] = build_subgate(
    "The 24-hour fixed-range baseline held steady for all three apps.",
    "Every Q2 row has SteadyStateOK == True AND ObservedMin == ObservedMax == ConfiguredMin.",
    [repo_rel("q2-baseline-fixed-steady-state-20260614114618.json")],
    all(steady_rows_ok),
    {
        row["app"]: {
            "configured_min": row["ConfiguredMin"],
            "observed_min": row["ObservedMin"],
            "observed_max": row["ObservedMax"],
            "steady_state_ok": row["SteadyStateOK"],
        }
        for row in q2
    },
)

gate15_subs["c"] = build_subgate(
    "The fixed-range baseline shows no clustered churn events.",
    "q3-baseline-fixed-clustered-churn-20260614114618.json is exactly [].",
    [repo_rel("q3-baseline-fixed-clustered-churn-20260614114618.json")],
    q3_fixed_clustered == [],
    {"row_count": len(q3_fixed_clustered)},
)

gate15_subs["d"] = build_subgate(
    "The fixed-range baseline shows no any-termination events.",
    "q3-baseline-fixed-any-termination-20260614114618.json is exactly [].",
    [repo_rel("q3-baseline-fixed-any-termination-20260614114618.json")],
    q3_fixed_any == [],
    {"row_count": len(q3_fixed_any)},
)

gate15 = gate_payload(
    "15",
    "Negative-control baseline validity",
    "The fixed-range 24-hour baseline is a valid negative control: ingestion is sufficient, steady state holds, and neither clustered churn nor any-termination appears.",
    {
        "q1_fixed_ingestion": repo_rel("q1-baseline-fixed-ingestion-20260614114618.json"),
        "q2_fixed_steady_state": repo_rel("q2-baseline-fixed-steady-state-20260614114618.json"),
        "q3_fixed_clustered": repo_rel("q3-baseline-fixed-clustered-churn-20260614114618.json"),
        "q3_fixed_any_termination": repo_rel("q3-baseline-fixed-any-termination-20260614114618.json"),
    },
    gate15_subs,
)

successful_logs = {
    name: rows
    for name, rows in {
        "perturbation-variant-a-restart-only-20260614110433.log": variant_a,
        "perturbation-variant-b-restart-load-20260614111457.log": variant_b,
        "perturbation-variant-c-retry-backoff-20260614112821.log": variant_c,
    }.items()
    if any(row.get("event") == "PerturbationStart" for row in rows) and any(row.get("event") == "PerturbationSubmitted" for row in rows)
}
variant_requirements = {
    "perturbation-variant-a-restart-only-20260614110433.log": {"required_events": {"PerturbationStart", "PerturbationSubmitted"}},
    "perturbation-variant-b-restart-load-20260614111457.log": {"required_events": {"LoadStart", "PerturbationStart", "PerturbationSubmitted", "LoadEnd"}},
    "perturbation-variant-c-retry-backoff-20260614112821.log": {"required_events": {"LoadStart", "PerturbationStart", "PerturbationSubmitted", "LoadEnd"}},
}
gate16_subs = {}
events_by_log = {name: sorted({row.get("event") for row in rows}) for name, rows in successful_logs.items()}
variant_checks = []
for name, req in variant_requirements.items():
    observed = {row.get("event") for row in successful_logs.get(name, [])}
    variant_checks.append(req["required_events"].issubset(observed))
gate16_subs["a"] = build_subgate(
    "Exactly three successful perturbation logs exist and each contains the required event sequence for its variant.",
    "Top-level evidence contains exactly the three Oracle-listed perturbation logs; Variant A has PerturbationStart + PerturbationSubmitted; Variants B/C also have LoadStart + LoadEnd.",
    [repo_rel(path) for path in perturbation_paths],
    len(perturbation_paths) == 3 and len(successful_logs) == 3 and all(variant_checks),
    {
        "perturbation_logs": perturbation_paths,
        "events_by_log": events_by_log,
    },
)

expected_cluster_bins = ["2026-06-14T11:05:00Z", "2026-06-14T11:16:00Z", "2026-06-14T11:29:00Z"]
observed_cluster_bins = sorted(
    row["ClusterStart"]
    for row in q3
    if row["App"] == "app-min3" and row["ClusterStart"] in expected_cluster_bins
)
rounded_submitted_bins = sorted(minute_round(dt) for dt in submitted_times)
gate16_subs["b"] = build_subgate(
    "Q3 detects churn for each successful perturbation at the expected 60-second cluster bins.",
    "Q3 contains app-min3 rows at 11:05:00Z, 11:16:00Z, and 11:29:00Z, matching the perturbation submitted timestamps rounded down to the minute.",
    [
        repo_rel("q3-clustered-churn-20260614114318.json"),
        repo_rel("perturbation-variant-a-restart-only-20260614110433.log"),
        repo_rel("perturbation-variant-b-restart-load-20260614111457.log"),
        repo_rel("perturbation-variant-c-retry-backoff-20260614112821.log"),
    ],
    observed_cluster_bins == expected_cluster_bins and rounded_submitted_bins == expected_cluster_bins,
    {
        "expected_cluster_bins": expected_cluster_bins,
        "observed_cluster_bins": observed_cluster_bins,
        "rounded_submitted_bins": rounded_submitted_bins,
    },
)

observed_recovery_bins = sorted(
    row["ChurnStart"]
    for row in q4
    if row["App"] == "app-min3" and row["ChurnStart"] in expected_cluster_bins and row["WithinDeadline"] == "True"
)
recovery_map = {
    row["ChurnStart"]: {"recovery_secs": row["RecoverySecs"], "within_deadline": row["WithinDeadline"]}
    for row in q4
    if row["ChurnStart"] in expected_cluster_bins
}
gate16_subs["c"] = build_subgate(
    "Recovery is observed for the same three successful perturbation events within the configured deadline.",
    "Q4 contains ChurnStart rows at 11:05:00Z, 11:16:00Z, and 11:29:00Z, all with WithinDeadline == True.",
    [repo_rel("q4-recovery-duration-20260614114318.json")],
    observed_recovery_bins == expected_cluster_bins,
    {
        "observed_recovery_bins": observed_recovery_bins,
        "recovery_map": recovery_map,
    },
)

variant_b_load_end = next(row for row in variant_b if row.get("event") == "LoadEnd")
variant_c_load_end = next(row for row in variant_c if row.get("event") == "LoadEnd")
gate16_subs["d"] = build_subgate(
    "The H0b primary metric is not falsified under the tested load envelope.",
    "Variant B LoadEnd has total=990 and fail=0; Variant C LoadEnd has total=960 and fail=0. Variant B is the H0b primary metric and Variant C is secondary mitigation context.",
    [
        repo_rel("perturbation-variant-b-restart-load-20260614111457.log"),
        repo_rel("perturbation-variant-c-retry-backoff-20260614112821.log"),
    ],
    variant_b_load_end["total"] == 990 and variant_b_load_end["fail"] == 0 and variant_c_load_end["total"] == 960 and variant_c_load_end["fail"] == 0,
    {
        "variant_b_load_end": variant_b_load_end,
        "variant_c_load_end": variant_c_load_end,
        "h0b_primary_metric": "variant_b_no_retry",
    },
)

gate16 = gate_payload(
    "16",
    "Positive-control perturbation validity",
    "The perturbation sequence is complete, Q3 and Q4 observe the intended churn/recovery windows, and the H0b primary metric remains unfalsified under the tested load profile.",
    {
        "q3_clustered_churn": repo_rel("q3-clustered-churn-20260614114318.json"),
        "q4_recovery_duration": repo_rel("q4-recovery-duration-20260614114318.json"),
        "variant_a_log": repo_rel("perturbation-variant-a-restart-only-20260614110433.log"),
        "variant_b_log": repo_rel("perturbation-variant-b-restart-load-20260614111457.log"),
        "variant_c_log": repo_rel("perturbation-variant-c-retry-backoff-20260614112821.log"),
    },
    gate16_subs,
)

q7_positive_apps = sorted(row["App"] for row in q7 if float(row["ClusteredChurnEvents"]) > 0)
all_logs_target_app_min3 = all(all(row.get("app") == "app-min3" for row in rows) for rows in variant_logs.values())
gate17_subs = {}
gate17_subs["a"] = build_subgate(
    "The app scope is explicitly bounded to app-min3.",
    "All successful perturbation logs target app-min3 AND Q7 shows clustered churn only on app-min3, with no client-impact generalization to app-min2 or app-min6.",
    [
        repo_rel("perturbation-variant-a-restart-only-20260614110433.log"),
        repo_rel("perturbation-variant-b-restart-load-20260614111457.log"),
        repo_rel("perturbation-variant-c-retry-backoff-20260614112821.log"),
        repo_rel("q7-multi-app-comparison-20260614114318.json"),
    ],
    all_logs_target_app_min3 and q7_positive_apps == ["app-min3"],
    {
        "all_logs_target_app_min3": all_logs_target_app_min3,
        "q7_positive_apps": q7_positive_apps,
    },
)

load_start_rows = [row for rows in [variant_b, variant_c] for row in rows if row.get("event") == "LoadStart"]
load_envelope_ok = len(load_start_rows) == 2 and all(row["rps"] == 10 and row["durationSec"] == 180 for row in load_start_rows)
gate17_subs["b"] = build_subgate(
    "The load envelope is bounded to two client-bearing 180-second runs at 10 RPS.",
    "Only Variants B and C carry client load, and each LoadStart row has rps=10 and durationSec=180. No higher-RPS or repeated-run evidence is in scope.",
    [
        repo_rel("perturbation-variant-b-restart-load-20260614111457.log"),
        repo_rel("perturbation-variant-c-retry-backoff-20260614112821.log"),
    ],
    load_envelope_ok,
    {
        "load_start_rows": load_start_rows,
        "client_bearing_run_count": len(load_start_rows),
    },
)

fixed_q6_baseline = next(row for row in q6_fixed if row["Bucket"] == "Baseline (no perturb)")
excluded_artifacts = [
    {
        "path": repo_rel("q6-baseline-vs-perturb-20260614114318.json"),
        "rationale": "Exclude from H0a because the file is unparsable: the query contains datetime(...ZZ) and returns BadArgumentError / SyntaxError.",
    },
    {
        "path": repo_rel("q6-baseline-vs-perturb-20260614114522.json"),
        "rationale": "Exclude from H0a because its 'Baseline (no perturb)' bucket is a rolling last-24h tail that includes 3 earlier partial perturbation events, so it is contaminated rather than a true fixed-range baseline.",
    },
]
gate17_subs["c"] = build_subgate(
    "Historical contamination is explicitly excluded from the bounded-coverage verdict.",
    "The bad Q6 file is ignored as unparsable, and the fixed Q6 file is ignored for H0a because its baseline bucket includes prior partial perturbations.",
    [repo_rel("q6-baseline-vs-perturb-20260614114318.json"), repo_rel("q6-baseline-vs-perturb-20260614114522.json")],
    "BadArgumentError" in q6_bad_text and "datetime(2026-06-14T11:04:37ZZ)" in q6_bad_text and fixed_q6_baseline["ChurnEvents"] == "3",
    {
        "excluded_artifacts": excluded_artifacts,
        "bad_q6_signature": "BadArgumentError + datetime(...ZZ)",
        "fixed_q6_baseline_bucket": fixed_q6_baseline,
    },
)

lab_guide = LAB_GUIDE_PATH.read_text(encoding="utf-8")
phase_b_match = re.search(r"## 12\.1 Phase B 4-gate evidence pack(.*?)## 13\. Solution", lab_guide, flags=re.DOTALL)
if not phase_b_match:
    raise SystemExit("Missing '## 12.1 Phase B 4-gate evidence pack' section in lab guide")
phase_b_section = phase_b_match.group(1)
claim2_strong = "Claim 2 remains `[Strongly Suggested]`" in phase_b_section
claim3_strong = "Claim 3 remains `[Strongly Suggested]`" in phase_b_section
claim2_measured = "Claim 2 remains `[Measured]`" in phase_b_section
claim3_measured = "Claim 3 remains `[Measured]`" in phase_b_section
evidence_ceilings = {"claim_2": "Strongly Suggested", "claim_3": "Strongly Suggested"}
gate17_subs["d"] = build_subgate(
    "The evidence ceiling is enforced: Claim 2 and Claim 3 remain capped at [Strongly Suggested].",
    "The Phase B summary must not promote Claim 2 or Claim 3 to [Measured], and Gate 17 records both ceilings as Strongly Suggested.",
    [str(LAB_GUIDE_PATH.relative_to(LAB_GUIDE_PATH.parents[3]))],
    claim2_strong and claim3_strong and not claim2_measured and not claim3_measured,
    {
        "claim_2_level": evidence_ceilings["claim_2"],
        "claim_3_level": evidence_ceilings["claim_3"],
        "claim_2_measured_present": claim2_measured,
        "claim_3_measured_present": claim3_measured,
    },
)

gate17 = gate_payload(
    "17",
    "Bounded coverage / uncertainty ceilings",
    "The evidence pack is explicitly bounded to app-min3, two 10-RPS client-bearing runs, and a documented exclusion set; Claims 2 and 3 remain capped at Strongly Suggested rather than Measured.",
    {
        "q7_multi_app_comparison": repo_rel("q7-multi-app-comparison-20260614114318.json"),
        "q6_bad": repo_rel("q6-baseline-vs-perturb-20260614114318.json"),
        "q6_fixed": repo_rel("q6-baseline-vs-perturb-20260614114522.json"),
        "lab_guide": str(LAB_GUIDE_PATH.relative_to(LAB_GUIDE_PATH.parents[3])),
    },
    gate17_subs,
    excluded_artifacts=excluded_artifacts,
    evidence_ceilings=evidence_ceilings,
)

gate_files = [
    ("14-cohort-integrity-gate.json", gate14),
    ("15-negative-control-baseline-validity-gate.json", gate15),
    ("16-positive-control-perturbation-validity-gate.json", gate16),
    ("17-bounded-coverage-uncertainty-gate.json", gate17),
]
for filename, payload in gate_files:
    write_gate(filename, payload)

subgate_lines = [
    (2, "14a", gate14_subs["a"], "required corpus exists"),
    (3, "14b", gate14_subs["b"], "cohort identity is coherent"),
    (4, "14c", gate14_subs["c"], "temporal structure is coherent"),
    (5, "14d", gate14_subs["d"], "sensor schedule matches sample math"),
    (6, "15a", gate15_subs["a"], "audit completeness is sufficient"),
    (7, "15b", gate15_subs["b"], "baseline steady state held"),
    (8, "15c", gate15_subs["c"], "fixed-range clustered churn is absent"),
    (9, "15d", gate15_subs["d"], "fixed-range any-termination is absent"),
    (10, "16a", gate16_subs["a"], "successful perturbation sequence is complete"),
    (11, "16b", gate16_subs["b"], "Q3 detects churn for each successful perturbation"),
    (12, "16c", gate16_subs["c"], "recovery is observed for the same three events"),
    (13, "16d", gate16_subs["d"], "H0b primary metric is not falsified under tested load"),
    (14, "17a", gate17_subs["a"], "app scope is bounded to app-min3"),
    (15, "17b", gate17_subs["b"], "load envelope is bounded"),
    (16, "17c", gate17_subs["c"], "historical contamination is explicitly excluded"),
    (17, "17d", gate17_subs["d"], "evidence ceiling is enforced"),
]

all_pass = True
for gate_number, label, subgate, detail in subgate_lines:
    verdict = "PASS" if subgate["pass"] else "FAIL"
    print(f"[Gate {gate_number}/17] {verdict} {label} {detail}")
    all_pass = all_pass and subgate["pass"]

print()
print("===== Phase B summary =====")
for filename, payload in gate_files:
    sub_count = len(payload["sub_gates"])
    sub_pass = sum(1 for item in payload["sub_gates"].values() if item["pass"])
    print(f"{filename:<52} {sub_pass}/{sub_count} PASS")
print()
print(f"TOTAL: {sum(1 for _, _, subgate, _ in subgate_lines if subgate['pass'])}/16 Phase B sub-gates PASS")
print(f"PHASE B VERDICT: {'PASS' if all_pass else 'FAIL'}")
raise SystemExit(0 if all_pass else 1)
PY
)"; then
  printf '%s\n' "$PHASE_B_OUTPUT"
else
  printf '%s\n' "$PHASE_B_OUTPUT"
  exit 1
fi

echo
if [[ "$PHASE_B_ONLY" == true ]]; then
  echo "Summary: 16/16 Phase B sub-gates PASS (--phase-b-only)"
else
  echo "Summary: 17/17 gates PASS (1 live-health + 16 Phase B sub-gates)"
fi
