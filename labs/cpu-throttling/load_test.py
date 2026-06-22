#!/usr/bin/env python3
"""Concurrent load generator for the cpu-throttling lab.

Usage:
    python3 load_test.py <url> <total_requests> <concurrency> <output_json>

Emits a JSON summary (p50/p95/p99/max/avg + error counts) to <output_json> and
also prints it to stdout for live trigger.sh / verify.sh tee logs. The same
file is used by both trigger.sh and verify.sh so the cpu=0.25 baseline and
cpu=1.0 post-fix runs are measured by byte-identical client code — the only
variable between the two runs is the per-replica CPU allocation on the server.
"""

import json
import math
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor


def fetch_one(url: str) -> tuple[str, float | str]:
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            response.read()
        return ("ok", (time.perf_counter() - t0) * 1000)
    except Exception as exc:  # noqa: BLE001 - we want to capture any failure
        return ("err", f"{type(exc).__name__}: {exc}")


def percentile(sorted_samples: list[float], p: float) -> float:
    if not sorted_samples:
        return 0.0
    # Nearest-rank percentile: rank = ceil(p * n), 1-indexed.
    rank = max(1, math.ceil(p * len(sorted_samples)))
    return sorted_samples[min(rank, len(sorted_samples)) - 1]


def main() -> int:
    if len(sys.argv) != 5:
        sys.stderr.write(
            "usage: load_test.py <url> <total_requests> <concurrency> <output_json>\n"
        )
        return 2

    url = sys.argv[1]
    total = int(sys.argv[2])
    concurrency = int(sys.argv[3])
    out_path = sys.argv[4]

    started_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    started_epoch = time.time()

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        results = list(executor.map(fetch_one, [url] * total))

    finished_epoch = time.time()
    finished_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    samples = sorted(r[1] for r in results if r[0] == "ok")
    errors = [r[1] for r in results if r[0] == "err"]
    n_ok = len(samples)

    summary = {
        "url": url,
        "started_utc": started_iso,
        "finished_utc": finished_iso,
        "wall_clock_seconds": round(finished_epoch - started_epoch, 2),
        "requests_total": total,
        "concurrency": concurrency,
        "requests_ok": n_ok,
        "requests_err": len(errors),
        "latency_ms": {
            "p50": round(percentile(samples, 0.50), 1),
            "p95": round(percentile(samples, 0.95), 1),
            "p99": round(percentile(samples, 0.99), 1),
            "max": round(samples[-1], 1) if samples else 0.0,
            "avg": round(sum(samples) / n_ok, 1) if n_ok else 0.0,
        },
        "errors_sample": errors[:5],
    }

    with open(out_path, "w") as fh:
        json.dump(summary, fh, indent=2)
        fh.write("\n")

    json.dump(summary, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
