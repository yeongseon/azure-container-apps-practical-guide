#!/usr/bin/env python3
"""Analyze replica-node-spread evidence and emit analysis-summary.md.

Reads every JSONL file under labs/replica-node-spread/evidence/ (except
the H3 falsification files) and computes:

    - unique boot_id count per (profile, scale_target, run)
    - unique replica_name count (= replicas actually hit by /diag)
    - boot_time_estimate cluster centers using a simple
      sort-then-gap-threshold algorithm (5s gap = different boot,
      i.e. different node)
    - hit ratio = unique_replicas / scale_target  (sanity for sampling
      coverage; if this is < 0.7, conclusions are weakened)

H1 evidence ceiling: unique_boot_id > 1 at scale=top is "consistent with
multi-node placement"; [Strongly Suggested] only if all 3 top-scale
repeats concur.

H2 evidence ceiling: unique_boot_id == 1 at scale=top is "consistent
with single-node placement"; never "proven single node".

Outputs:
    evidence/analysis-summary.md  — human-readable analysis
    evidence/analysis-summary.json — machine-readable counts

Usage:
    python3 analyze.py
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from statistics import mean

LAB_DIR = Path(__file__).resolve().parent
EVIDENCE_DIR = LAB_DIR / "evidence"
SUMMARY_MD = EVIDENCE_DIR / "analysis-summary.md"
SUMMARY_JSON = EVIDENCE_DIR / "analysis-summary.json"

# Boot-time gap (ms) above which two replicas are inferred to be on
# distinct hosts. Set to 5 seconds — generous enough to absorb local
# clock skew between hosts, tight enough that two containers on the same
# host (which share boot_time exactly) never appear as distinct.
BOOT_TIME_CLUSTER_GAP_MS = 5_000


@dataclass
class RunStats:
    profile: str
    scale_target: int
    run_id: str
    file: str
    samples: int = 0
    unique_replicas: int = 0
    unique_boot_ids: int = 0
    boot_time_clusters: int = 0
    cluster_centers_ms: list[int] = field(default_factory=list)
    hit_ratio: float = 0.0


def load_run_files() -> list[Path]:
    """Return all per-run JSONL files, excluding H3 falsification output."""
    return sorted(
        p for p in EVIDENCE_DIR.glob("*.jsonl") if not p.name.startswith("h3-")
    )


def cluster_boot_times(values: list[int], gap_ms: int) -> list[int]:
    """Return cluster centers for sorted boot_time_estimate_ms values.

    Linear sweep: a new cluster opens whenever the gap to the previous
    value exceeds gap_ms. The center is the integer mean of values in
    the cluster. This is intentionally simple — the per-host
    boot_time_estimate values cluster tightly enough that DBSCAN-style
    methods add complexity without changing the cluster count.
    """
    if not values:
        return []
    ordered = sorted(values)
    clusters: list[list[int]] = [[ordered[0]]]
    for v in ordered[1:]:
        if v - clusters[-1][-1] <= gap_ms:
            clusters[-1].append(v)
        else:
            clusters.append([v])
    return [int(mean(c)) for c in clusters]


def analyze_run(path: Path) -> RunStats:
    samples = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                samples.append(json.loads(line))
            except json.JSONDecodeError as exc:
                print(
                    f"WARN: {path.name}: bad JSON line skipped: {exc}", file=sys.stderr
                )

    if not samples:
        return RunStats(profile="?", scale_target=0, run_id="?", file=path.name)

    first = samples[0]
    profile = first.get("profile", "?")
    scale_target = int(first.get("scale_target", 0))
    run_id = first.get("run_id", "?")

    replica_names = {s.get("replica_name") for s in samples if s.get("replica_name")}
    boot_ids = {s.get("boot_id") for s in samples if s.get("boot_id")}
    boot_times = [
        s["boot_time_estimate_ms"] for s in samples if s.get("boot_time_estimate_ms")
    ]

    centers = cluster_boot_times(boot_times, BOOT_TIME_CLUSTER_GAP_MS)
    hit_ratio = len(replica_names) / scale_target if scale_target else 0.0

    return RunStats(
        profile=profile,
        scale_target=scale_target,
        run_id=run_id,
        file=path.name,
        samples=len(samples),
        unique_replicas=len(replica_names),
        unique_boot_ids=len(boot_ids),
        boot_time_clusters=len(centers),
        cluster_centers_ms=centers,
        hit_ratio=round(hit_ratio, 3),
    )


def verdict_for(stats: RunStats) -> str:
    """Map raw counts to an evidence-ceiling-aware verdict string.

    Only kernel-context wording is allowed here. Node-placement
    interpretation is reserved for `[Strongly Suggested]` prose in the
    lab guide; the ACA management plane does not expose per-replica
    Microsoft.Compute node identity, so this function MUST NOT emit
    "node" / "nodes" claims.
    """
    if stats.unique_replicas == 0:
        return "no-data"
    if stats.unique_boot_ids <= 1:
        return "single kernel context"
    if stats.boot_time_clusters >= 2:
        return f"{stats.boot_time_clusters} distinct kernel contexts"
    return f"{stats.unique_boot_ids} boot_ids in 1 boot_time cluster (ambiguous)"


def render_markdown(runs: list[RunStats]) -> str:
    lines: list[str] = []
    lines.append("# Replica-node-spread — analysis summary")
    lines.append("")
    lines.append(
        "Generated by `analyze.py`. Boot-time cluster gap threshold: "
        f"{BOOT_TIME_CLUSTER_GAP_MS} ms."
    )
    lines.append("")
    lines.append("## Per-run counts")
    lines.append("")
    lines.append(
        "| profile | scale_target | run_id | samples | unique_replicas | hit_ratio | unique_boot_ids | boot_time_clusters | verdict |"
    )
    lines.append("|---|---:|---|---:|---:|---:|---:|---:|---|")
    for r in runs:
        lines.append(
            f"| {r.profile} | {r.scale_target} | {r.run_id} | {r.samples} "
            f"| {r.unique_replicas} | {r.hit_ratio} | {r.unique_boot_ids} "
            f"| {r.boot_time_clusters} | {verdict_for(r)} |"
        )

    # Concurrence rollup at top scale per profile.
    by_profile_top: dict[str, list[RunStats]] = defaultdict(list)
    for r in runs:
        by_profile_top[r.profile].append(r)

    lines.append("")
    lines.append("## Top-scale concurrence")
    lines.append("")
    lines.append(
        "Concurrence = all top-scale repeats for the profile agree on the "
        "same boot_time cluster count. Required for `[Strongly Suggested]` "
        "claims."
    )
    lines.append("")
    lines.append("| profile | top_target | repeats | cluster_counts | concur |")
    lines.append("|---|---:|---:|---|---|")
    for profile, profile_runs in sorted(by_profile_top.items()):
        if not profile_runs:
            continue
        top = max(r.scale_target for r in profile_runs)
        top_runs = [r for r in profile_runs if r.scale_target == top]
        counts = [r.boot_time_clusters for r in top_runs]
        concur = "yes" if len(set(counts)) == 1 else "NO"
        lines.append(f"| {profile} | {top} | {len(top_runs)} | {counts} | {concur} |")

    lines.append("")
    lines.append("## Evidence ceiling")
    lines.append("")
    lines.append(
        "- `[Strongly Suggested]` is the maximum claim level for node "
        "placement in this lab. We never claim `[Observed]` because /diag "
        "exposes only kernel-context proxies (boot_id, uptime, "
        "boot_time_estimate), not the underlying Microsoft.Compute node id."
    )
    lines.append(
        "- A `single-kernel-context` verdict at Dedicated-D8 top scale is "
        "**consistent with** single-node placement; it is not a proof that "
        "ACA cannot place D8 replicas on multiple nodes in any configuration."
    )
    lines.append(
        "- A multi-cluster verdict at Consumption top scale is **consistent "
        "with** multi-node placement; ACA's scheduler may still co-locate "
        "replicas on the same node when load permits."
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    files = load_run_files()
    if not files:
        print("ERROR: no evidence files found in evidence/*.jsonl", file=sys.stderr)
        return 1

    runs = [analyze_run(p) for p in files]
    md = render_markdown(runs)
    SUMMARY_MD.write_text(md, encoding="utf-8")
    SUMMARY_JSON.write_text(
        json.dumps([r.__dict__ for r in runs], indent=2),
        encoding="utf-8",
    )
    print(f"wrote {SUMMARY_MD.relative_to(LAB_DIR)}")
    print(f"wrote {SUMMARY_JSON.relative_to(LAB_DIR)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
