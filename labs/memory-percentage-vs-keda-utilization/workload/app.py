"""Minimal HTTP app that exposes /health and intentionally exercises memory.

MODE=cache (default):
    Allocates a large file on disk and continuously reads it into the page
    cache. The container working set (page cache) inflates close to the
    memory limit, but the Python process RSS stays small.

MODE=rss:
    Allocates a large anonymous bytearray and holds it in process memory.
    Both RSS and working set inflate together.

The lab uses these two modes to demonstrate that Azure Monitor
``Memory Percentage`` (Portal value, includes reclaimable page cache for
cache-heavy workloads in this lab's observations) can read materially
higher than the value KEDA's memory scaler consumes from the Kubernetes
metrics API. The exact metrics-server numerator is not measured directly;
the lab demonstrates the divergence behaviorally via replica counts.
"""

from __future__ import annotations

import http.server
import os
import socketserver
import threading
import time
from pathlib import Path

PORT = int(os.environ.get("PORT", "8000"))
MODE = os.environ.get("MODE", "cache").lower()
TARGET_MB = int(os.environ.get("TARGET_MB", "700"))
CACHE_FILE = Path(os.environ.get("CACHE_FILE", "/tmp/bigfile.bin"))


class Health(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - stdlib signature
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok\n")
            return
        if self.path == "/mode":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(f"mode={MODE} target_mb={TARGET_MB}\n".encode())
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, format: str, *args) -> None:  # noqa: A002,D401
        # Silence default access log noise.
        return


def serve() -> None:
    handler = Health
    with socketserver.TCPServer(("", PORT), handler) as httpd:
        print(f"[app] listening on :{PORT}", flush=True)
        httpd.serve_forever()


def cache_burner() -> None:
    """Fill page cache without inflating the Python process RSS."""
    size_bytes = TARGET_MB * 1024 * 1024
    if not CACHE_FILE.exists() or CACHE_FILE.stat().st_size < size_bytes:
        print(f"[cache] creating {TARGET_MB} MiB file at {CACHE_FILE}", flush=True)
        with CACHE_FILE.open("wb") as f:
            chunk = os.urandom(1024 * 1024)
            for _ in range(TARGET_MB):
                f.write(chunk)
    print("[cache] entering read loop (page cache filler)", flush=True)
    while True:
        with CACHE_FILE.open("rb") as f:
            while f.read(4 * 1024 * 1024):
                pass
        time.sleep(15)


def rss_burner() -> None:
    """Allocate anonymous memory that shows up as RSS / working set."""
    size_bytes = TARGET_MB * 1024 * 1024
    print(f"[rss] allocating {TARGET_MB} MiB anonymous memory", flush=True)
    blob = bytearray(size_bytes)
    # Touch every page so the kernel actually backs it with physical memory.
    step = 4096
    for i in range(0, size_bytes, step):
        blob[i] = 1
    print("[rss] allocation complete, sleeping forever", flush=True)
    while True:
        time.sleep(3600)


def main() -> None:
    threading.Thread(target=serve, daemon=True).start()
    if MODE == "rss":
        rss_burner()
    else:
        cache_burner()


if __name__ == "__main__":
    main()
