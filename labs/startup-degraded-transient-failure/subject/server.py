#!/usr/bin/env python3
"""
Subject application for the startup-degraded-transient-failure lab.

Behavior:
  1. On process start, prints `startup-delay-begin` and sleeps for
     STARTUP_DELAY_SECONDS (default 25 seconds) BEFORE binding to the port.
     During this window the TCP listener does not exist, so platform health
     probes against the listener path will fail closed.
  2. After the delay, prints `listening` and starts a threaded HTTP server.
  3. Serves two endpoints:
       /healthz  -> 200 OK, body "ok" (lightweight, no artificial work)
       /         -> 200 OK, body "served", with optional artificial
                    REQUEST_DELAY_MS sleep per request (default 0 ms)
                    to simulate per-request work.
  4. All other paths -> 404.

Environment variables:
  STARTUP_DELAY_SECONDS   Integer seconds to sleep before binding. Default 25.
  REQUEST_DELAY_MS        Integer ms to sleep per `/` request. Default 0.
  PORT                    TCP port to bind. Default 8080.

This module deliberately uses only the standard library to keep the image
small and the behavior deterministic. The intent is to reproduce the
"degraded startup / probe-masked transient failure" claim from issue #205.
"""

from __future__ import annotations

import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STARTUP_DELAY_SECONDS = int(os.environ.get("STARTUP_DELAY_SECONDS", "25"))
REQUEST_DELAY_MS = int(os.environ.get("REQUEST_DELAY_MS", "0"))
PORT = int(os.environ.get("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    # Override default logging to write a compact, machine-parsable line
    # to stdout. Container Apps ships stdout to Log Analytics
    # (ContainerAppConsoleLogs_CL), which we use later for correlation.
    def log_message(self, format: str, *args) -> None:  # noqa: A002 - parent signature
        sys.stdout.write(
            "subject-request "
            f"path={self.path} "
            f"code={args[1] if len(args) > 1 else '-'} "
            f"client={self.client_address[0]}\n"
        )
        sys.stdout.flush()

    def do_GET(self) -> None:  # noqa: N802 - http.server contract
        if self.path == "/healthz":
            self._respond(200, b"ok")
            return
        if self.path == "/" or self.path.startswith("/?"):
            if REQUEST_DELAY_MS > 0:
                time.sleep(REQUEST_DELAY_MS / 1000.0)
            self._respond(200, b"served")
            return
        self._respond(404, b"not found")

    def _respond(self, code: int, body: bytes) -> None:
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        # Disable keep-alive so each client request opens a fresh TCP
        # connection. This matches the k6 load profile (connection reuse
        # disabled) and surfaces transient unavailability faster.
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    # Marker 1: emitted BEFORE the sleep, so KQL can correlate the
    # start-of-delay moment with platform replica state transitions.
    sys.stdout.write(
        f"startup-delay-begin seconds={STARTUP_DELAY_SECONDS} port={PORT}\n"
    )
    sys.stdout.flush()

    if STARTUP_DELAY_SECONDS > 0:
        time.sleep(STARTUP_DELAY_SECONDS)

    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)

    # Marker 2: emitted AFTER the bind succeeds. The interval between
    # marker 1 and marker 2 is the deterministic startup window.
    sys.stdout.write(f"listening port={PORT} request_delay_ms={REQUEST_DELAY_MS}\n")
    sys.stdout.flush()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
