#!/usr/bin/env python3
import argparse
import json
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path


def load_jsonl(path: Path):
    rows = []
    with path.open() as fh:
        for line_no, raw in enumerate(fh, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                rows.append(json.loads(raw))
            except json.JSONDecodeError as exc:
                print(
                    f"WARN {path.name}:{line_no} skipped malformed JSON: {exc}",
                    file=sys.stderr,
                )
    return rows


def samples_only(rows):
    return [r for r in rows if r.get("event") == "ReplicaDiagSample"]


def boot_time_estimate(row):
    try:
        ts_s = float(row["local_sample_ts_ms"]) / 1000.0
        up = float(row["uptime_seconds"])
        return ts_s - up
    except (KeyError, TypeError, ValueError):
        return None


def cluster_boot_times(values, tolerance_s=5.0):
    if not values:
        return []
    ordered = sorted(values)
    clusters = [[ordered[0]]]
    for v in ordered[1:]:
        if abs(v - clusters[-1][-1]) <= tolerance_s:
            clusters[-1].append(v)
        else:
            clusters.append([v])
    return clusters


def summarize_run(rows):
    summary = {
        "replicas_sampled": len(rows),
        "unique_boot_ids": 0,
        "boot_id_histogram": {},
        "unique_machine_ids": 0,
        "unique_kernels": 0,
        "unique_microcodes": 0,
        "boot_time_clusters": [],
        "boot_time_cluster_count": 0,
        "uptime_range": [None, None],
    }
    if not rows:
        return summary

    boot_ids = [r.get("boot_id", "?") for r in rows]
    machine_ids = [r.get("machine_id", "") for r in rows if r.get("machine_id")]
    kernels = [r.get("kernel_release", "?") for r in rows]
    microcodes = [r.get("microcode", "?") for r in rows]
    uptimes = [float(r.get("uptime_seconds", 0.0)) for r in rows]
    boot_time_estimates = [
        bt for r in rows if (bt := boot_time_estimate(r)) is not None
    ]

    summary["unique_boot_ids"] = len(set(boot_ids))
    summary["boot_id_histogram"] = dict(Counter(boot_ids).most_common())
    summary["unique_machine_ids"] = len(set(machine_ids))
    summary["unique_kernels"] = len(set(kernels))
    summary["unique_microcodes"] = len(set(microcodes))

    clusters = cluster_boot_times(boot_time_estimates, tolerance_s=5.0)
    summary["boot_time_cluster_count"] = len(clusters)
    summary["boot_time_clusters"] = [
        {
            "size": len(c),
            "center_epoch": round(statistics.mean(c), 3),
            "spread_seconds": round(max(c) - min(c), 3),
        }
        for c in clusters
    ]

    if uptimes:
        summary["uptime_range"] = [min(uptimes), max(uptimes)]

    return summary


def by_run_label(rows):
    grouped = defaultdict(list)
    for r in rows:
        grouped[r.get("run_label", "unknown")].append(r)
    return grouped


def h3_check_part_a(rows):
    grouped = defaultdict(list)
    for r in rows:
        grouped[r.get("replica", "?")].append(r)
    findings = []
    pass_count = 0
    fail_count = 0
    for replica, samples in grouped.items():
        if len(samples) < 2:
            continue
        samples = sorted(samples, key=lambda x: x.get("local_sample_ts_ms", 0))
        first, second = samples[0], samples[-1]
        boot_id_ok = first.get("boot_id") == second.get("boot_id")
        up_first = float(first.get("uptime_seconds", 0.0))
        up_second = float(second.get("uptime_seconds", 0.0))
        ts_first = float(first.get("local_sample_ts_ms", 0)) / 1000.0
        ts_second = float(second.get("local_sample_ts_ms", 0)) / 1000.0
        wall_delta = ts_second - ts_first
        uptime_delta = up_second - up_first
        monotonic_ok = uptime_delta > 0
        delta_ok = abs(uptime_delta - wall_delta) < 5.0
        if boot_id_ok and monotonic_ok and delta_ok:
            pass_count += 1
        else:
            fail_count += 1
        findings.append(
            {
                "replica": replica,
                "boot_id_stable": boot_id_ok,
                "uptime_monotonic": monotonic_ok,
                "uptime_delta_seconds": round(uptime_delta, 3),
                "wall_delta_seconds": round(wall_delta, 3),
                "delta_within_5s": delta_ok,
                "verdict": "PASS"
                if (boot_id_ok and monotonic_ok and delta_ok)
                else "FAIL",
            }
        )
    return {"pass": pass_count, "fail": fail_count, "findings": findings}


def h3_check_part_b(rows):
    pre = {}
    post = {}
    for r in rows:
        label = r.get("run_label", "")
        if label.startswith("h3b-pre-"):
            pre[r.get("replica", "?")] = r
        elif label.startswith("h3b-post-"):
            post[r.get("replica", "?")] = r

    pre_replicas = set(pre.keys())
    post_replicas = set(post.keys())
    new_replicas = post_replicas - pre_replicas
    persisted_replicas = post_replicas & pre_replicas

    pre_boot_ids = {r.get("boot_id") for r in pre.values()}

    new_with_fresh_boot = []
    new_with_recycled_boot = []
    for name in new_replicas:
        b = post[name].get("boot_id")
        entry = {"replica": name, "boot_id": b}
        if b in pre_boot_ids:
            new_with_recycled_boot.append(entry)
        else:
            new_with_fresh_boot.append(entry)

    return {
        "pre_replica_count": len(pre_replicas),
        "post_replica_count": len(post_replicas),
        "new_replica_count": len(new_replicas),
        "persisted_replica_count": len(persisted_replicas),
        "new_with_fresh_boot_id": new_with_fresh_boot,
        "new_with_recycled_boot_id": new_with_recycled_boot,
        "verdict": (
            "PASS"
            if (len(new_replicas) > 0 and not new_with_recycled_boot)
            else (
                "INCONCLUSIVE — no new replica observed"
                if len(new_replicas) == 0
                else "FAIL — some new replica reused a pre-existing boot_id"
            )
        ),
    }


def render_run_summary(profile, run_label, rows, summary):
    lines = []
    lines.append(
        f"### {profile} — `{run_label}` (replicas sampled: {summary['replicas_sampled']})"
    )
    lines.append("")
    lines.append(f"- Unique `boot_id`: **{summary['unique_boot_ids']}**")
    lines.append(f"- Unique `machine_id`: {summary['unique_machine_ids']}")
    lines.append(f"- Unique kernel release: {summary['unique_kernels']}")
    lines.append(f"- Unique microcode: {summary['unique_microcodes']}")
    lines.append(
        f"- `boot_time_estimate` clusters (±5s): **{summary['boot_time_cluster_count']}**"
    )
    if summary["uptime_range"][0] is not None:
        lo, hi = summary["uptime_range"]
        lines.append(f"- Uptime range: {lo:.1f}s - {hi:.1f}s (spread {hi - lo:.1f}s)")
    if summary["boot_id_histogram"]:
        lines.append("")
        lines.append("| boot_id (truncated) | count |")
        lines.append("|---|---|")
        for bid, n in summary["boot_id_histogram"].items():
            short = (bid[:8] + "...") if len(bid) > 8 else bid
            lines.append(f"| `{short}` | {n} |")
    if summary["boot_time_clusters"]:
        lines.append("")
        lines.append("| cluster | size | center epoch | internal spread (s) |")
        lines.append("|---|---|---|---|")
        for i, c in enumerate(summary["boot_time_clusters"], 1):
            lines.append(
                f"| {i} | {c['size']} | {c['center_epoch']} | {c['spread_seconds']} |"
            )
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Analyze replica-node-spread JSONL evidence."
    )
    parser.add_argument(
        "files", nargs="+", type=Path, help="One or more JSONL files to analyze."
    )
    parser.add_argument(
        "--mode",
        choices=["scale", "h3a", "h3b"],
        default="scale",
        help="scale = ladder analysis, h3a = idempotence check, h3b = restart check",
    )
    parser.add_argument(
        "--output", type=Path, help="Optional markdown output path (default: stdout)"
    )
    args = parser.parse_args()

    all_rows = []
    for fp in args.files:
        if not fp.exists():
            print(f"ERROR: file not found: {fp}", file=sys.stderr)
            return 2
        all_rows.extend(load_jsonl(fp))

    rows = samples_only(all_rows)
    if not rows:
        print("ERROR: no ReplicaDiagSample rows found in input.", file=sys.stderr)
        return 3

    lines = []
    lines.append("# replica-node-spread evidence analysis")
    lines.append("")
    lines.append(f"- Input files: {', '.join(str(f) for f in args.files)}")
    lines.append(f"- Total raw rows: {len(all_rows)}")
    lines.append(f"- Sample rows: {len(rows)}")
    lines.append(f"- Mode: `{args.mode}`")
    lines.append("")

    if args.mode == "scale":
        per_profile = defaultdict(list)
        for r in rows:
            per_profile[r.get("profile", "unknown")].append(r)
        for profile, prows in per_profile.items():
            lines.append(f"## Profile: {profile}")
            lines.append("")
            runs = by_run_label(prows)
            for run_label, run_rows in sorted(runs.items()):
                summary = summarize_run(run_rows)
                lines.append(render_run_summary(profile, run_label, run_rows, summary))
    elif args.mode == "h3a":
        lines.append("## H3 Part A — same-replica idempotence")
        lines.append("")
        result = h3_check_part_a(rows)
        lines.append(f"- Replicas verified: {result['pass'] + result['fail']}")
        lines.append(f"- PASS: **{result['pass']}**, FAIL: **{result['fail']}**")
        lines.append("")
        lines.append(
            "| replica | boot_id stable | uptime monotonic | uptime delta (s) | wall delta (s) | within 5s | verdict |"
        )
        lines.append("|---|---|---|---|---|---|---|")
        for f in result["findings"]:
            lines.append(
                "| `{replica}` | {bs} | {um} | {ud} | {wd} | {dok} | **{verdict}** |".format(
                    replica=f["replica"],
                    bs=f["boot_id_stable"],
                    um=f["uptime_monotonic"],
                    ud=f["uptime_delta_seconds"],
                    wd=f["wall_delta_seconds"],
                    dok=f["delta_within_5s"],
                    verdict=f["verdict"],
                )
            )
    elif args.mode == "h3b":
        lines.append("## H3 Part B — single-replica restart, new boot_id expected")
        lines.append("")
        result = h3_check_part_b(rows)
        lines.append(f"- Pre-restart replicas: {result['pre_replica_count']}")
        lines.append(f"- Post-restart replicas: {result['post_replica_count']}")
        lines.append(
            f"- NEW replicas (name not in pre-set): **{result['new_replica_count']}**"
        )
        lines.append(
            f"- New replicas with **fresh** boot_id: {len(result['new_with_fresh_boot_id'])}"
        )
        lines.append(
            f"- New replicas with **recycled** boot_id: {len(result['new_with_recycled_boot_id'])}"
        )
        lines.append(f"- Verdict: **{result['verdict']}**")

    out_text = "\n".join(lines) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(out_text)
        print(f"Wrote: {args.output}")
    else:
        print(out_text)

    return 0


if __name__ == "__main__":
    sys.exit(main())
