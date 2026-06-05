from __future__ import annotations

import os
import threading
import time
import urllib.error
import urllib.request

TARGETS = [
    ("http://ca-res-503/error?code=503", 0.05, 4.0),
    ("http://ca-res-503/error?code=500", 0.05, 4.0),
    ("http://ca-res-slow/slow?ms=4000", 0.1, 1.5),
    ("http://ca-res-pool/slow?ms=5000", 0.02, 6.0),
    ("http://ca-res-blackhole/", 0.05, 5.0),
]

CONCURRENCY_PER_TARGET = int(os.environ.get("CONCURRENCY_PER_TARGET", "20"))


def hit(url: str, timeout: float) -> None:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            r.read(64)
    except (
        urllib.error.URLError,
        urllib.error.HTTPError,
        TimeoutError,
        ConnectionError,
        OSError,
    ):
        pass


def loop(url: str, interval: float, timeout: float) -> None:
    while True:
        hit(url, timeout)
        time.sleep(interval)


if __name__ == "__main__":
    threads = []
    for url, interval, timeout in TARGETS:
        for _ in range(CONCURRENCY_PER_TARGET):
            t = threading.Thread(
                target=loop, args=(url, interval, timeout), daemon=True
            )
            t.start()
            threads.append(t)
    print(f"caller: launched {len(threads)} threads across {len(TARGETS)} targets")
    while True:
        time.sleep(60)
