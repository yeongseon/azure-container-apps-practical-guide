"""Minimal HTTP app with configurable startup delay and crash modes.

Used to reproduce KEDA "no metrics returned from resource metrics API" by
simulating conditions where the Kubernetes Metrics Server cannot collect
CPU/memory data from a container:

MODE=healthy:
    Starts immediately and responds to /health. Baseline control.

MODE=slow-start:
    Sleeps DELAY_SECONDS before starting the HTTP server. During this
    window the readiness probe fails and the pod stays Not Ready, so the
    Metrics Server returns no data for it.

MODE=crash-loop:
    Starts, allocates memory, then exits after DELAY_SECONDS. The
    container restarts repeatedly (CrashLoopBackOff), creating windows
    where metrics are unavailable.

MODE=oom:
    Allocates memory exceeding the container limit to trigger an OOMKill.
    The resulting restart creates a metrics gap.
"""

from __future__ import annotations

import http.server
import os
import socketserver
import sys
import threading
import time

PORT = int(os.environ.get("PORT", "8000"))
MODE = os.environ.get("MODE", "healthy").lower()
DELAY_SECONDS = int(os.environ.get("DELAY_SECONDS", "120"))
OOM_MB = int(os.environ.get("OOM_MB", "2048"))


class Health(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok\n")
            return
        if self.path == "/info":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            info = f"mode={MODE} delay={DELAY_SECONDS} pid={os.getpid()}\n"
            self.wfile.write(info.encode())
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        return


def serve() -> None:
    with socketserver.TCPServer(("", PORT), Health) as httpd:
        print(f"[app] listening on :{PORT}", flush=True)
        httpd.serve_forever()


def mode_healthy() -> None:
    """Start immediately — baseline control."""
    serve()


def mode_slow_start() -> None:
    """Delay startup so readiness probe fails and metrics are unavailable."""
    print(f"[slow-start] sleeping {DELAY_SECONDS}s before starting server", flush=True)
    time.sleep(DELAY_SECONDS)
    print("[slow-start] delay complete, starting server", flush=True)
    serve()


def mode_crash_loop() -> None:
    """Start, run briefly, then exit to trigger CrashLoopBackOff."""
    threading.Thread(target=serve, daemon=True).start()
    print(f"[crash-loop] will exit in {DELAY_SECONDS}s", flush=True)
    time.sleep(DELAY_SECONDS)
    print("[crash-loop] exiting intentionally", flush=True)
    sys.exit(1)


def mode_oom() -> None:
    """Allocate memory beyond container limit to trigger OOMKill."""
    threading.Thread(target=serve, daemon=True).start()
    print(f"[oom] allocating {OOM_MB} MiB to trigger OOMKill", flush=True)
    chunks = []
    for i in range(OOM_MB):
        chunks.append(bytearray(1024 * 1024))
        if (i + 1) % 100 == 0:
            print(f"[oom] allocated {i + 1} MiB", flush=True)
    # Should not reach here if OOM_MB > container limit
    print("[oom] allocation complete (did not OOM — increase OOM_MB)", flush=True)
    while True:
        time.sleep(3600)


MODES = {
    "healthy": mode_healthy,
    "slow-start": mode_slow_start,
    "crash-loop": mode_crash_loop,
    "oom": mode_oom,
}


def main() -> None:
    handler = MODES.get(MODE)
    if handler is None:
        print(f"[app] unknown MODE={MODE}, expected one of {list(MODES)}", flush=True)
        sys.exit(1)
    handler()


if __name__ == "__main__":
    main()
