from __future__ import annotations

import http.server
import os
import socketserver
import sys
import threading
import time

PORT = int(os.environ.get("PORT", "8000"))
MODE = os.environ.get("MODE", "healthy").lower()
HARD_OOM_MB = int(os.environ.get("HARD_OOM_MB", "600"))
LEAK_MB_PER_TICK = int(os.environ.get("LEAK_MB_PER_TICK", "30"))
LEAK_INTERVAL_SECONDS = int(os.environ.get("LEAK_INTERVAL_SECONDS", "20"))

_RETAINED: list[bytearray] = []


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
            info = (
                f"mode={MODE} "
                f"hard_oom_mb={HARD_OOM_MB} "
                f"leak_mb_per_tick={LEAK_MB_PER_TICK} "
                f"leak_interval_seconds={LEAK_INTERVAL_SECONDS} "
                f"retained_chunks={len(_RETAINED)} "
                f"pid={os.getpid()}\n"
            )
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
    serve()


def mode_hard_oom() -> None:
    print(
        f"[hard-oom] allocating {HARD_OOM_MB} MiB at startup (will exceed cgroup limit)",
        flush=True,
    )
    for i in range(HARD_OOM_MB):
        _RETAINED.append(bytearray(1024 * 1024))
        if (i + 1) % 50 == 0:
            print(f"[hard-oom] allocated {i + 1}/{HARD_OOM_MB} MiB", flush=True)
    print(
        "[hard-oom] allocation complete (did not OOM — raise HARD_OOM_MB)",
        flush=True,
    )
    serve()


def _leak_loop() -> None:
    tick = 0
    while True:
        tick += 1
        for _ in range(LEAK_MB_PER_TICK):
            _RETAINED.append(bytearray(1024 * 1024))
        total_mb = len(_RETAINED)
        print(
            f"[leak] tick {tick}: +{LEAK_MB_PER_TICK} MiB, total retained {total_mb} MiB",
            flush=True,
        )
        time.sleep(LEAK_INTERVAL_SECONDS)


def mode_leak() -> None:
    threading.Thread(target=_leak_loop, daemon=True).start()
    serve()


MODES = {
    "healthy": mode_healthy,
    "hard-oom": mode_hard_oom,
    "leak": mode_leak,
}


def main() -> None:
    handler = MODES.get(MODE)
    if handler is None:
        print(
            f"[app] unknown MODE={MODE}, expected one of {list(MODES)}",
            flush=True,
        )
        sys.exit(1)
    handler()


if __name__ == "__main__":
    main()
