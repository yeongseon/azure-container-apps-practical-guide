"""Minimal HTTP app for the ACR Private Endpoint direct pull lab.

The app is deliberately tiny so the lab focuses on the network path
(image pull from ACR through the Private Endpoint), not on the
application itself. It exposes:

- GET /       → 200 with a one-line identity banner
- GET /health → 200 with body "ok"
- GET /info   → 200 with build tag (from BUILD_TAG env var)

Use BUILD_TAG to distinguish revisions when validating that the
Container App actually pulled a new image through the PE path.
"""

from __future__ import annotations

import http.server
import os
import socketserver

PORT = int(os.environ.get("PORT", "80"))
BUILD_TAG = os.environ.get("BUILD_TAG", "v1")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._respond(200, "ok\n")
            return
        if self.path == "/info":
            self._respond(200, f"build_tag={BUILD_TAG} pid={os.getpid()}\n")
            return
        if self.path == "/":
            self._respond(
                200,
                f"acr-network-path-pe-direct lab — build_tag={BUILD_TAG}\n",
            )
            return
        self._respond(404, "not found\n")

    def _respond(self, status: int, body: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        return


def main() -> None:
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"[app] listening on :{PORT} build_tag={BUILD_TAG}", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
