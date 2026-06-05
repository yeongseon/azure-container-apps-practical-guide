"""HTTP probe app for the ACR DNS Forwarder Bypass (Scenario E) lab.

The app exposes a workload-layer DNS probe so the lab can directly
observe what an application running inside Container Apps sees when
the VNet's custom DNS forwarder is healthy vs. when it forwards to a
public resolver.

In this Azure Container Apps reproduction, breaking the VNet custom
DNS forwarder produces no immediate revision-health impact on the
already-running revision. The clearly observable failure surface
lives at the workload (application) layer. This probe makes that
distinction visible.

Endpoints:

- GET /        → identity banner
- GET /health  → "ok"
- GET /info    → build tag (from BUILD_TAG env var)
- GET /probe   → JSON: socket.getaddrinfo() for the ACR FQDN from
                 inside this replica, plus a classifier indicating
                 whether the first answer is RFC1918 (private =
                 PE NIC) or not (public = forwarder upstream is not
                 Azure DNS).

The classifier is what changes when dnsmasq's upstream is swapped
from Azure DNS (168.63.129.16) to a public resolver (8.8.8.8):
healthy → private/PE NIC IP, broken → public registry IP.
"""

from __future__ import annotations

import http.server
import ipaddress
import json
import os
import socket
import socketserver

PORT = int(os.environ.get("PORT", "80"))
BUILD_TAG = os.environ.get("BUILD_TAG", "v1")
ACR_FQDN = os.environ.get("ACR_FQDN", "")


def _classify(addr: str) -> str:
    try:
        return "private" if ipaddress.ip_address(addr).is_private else "public"
    except ValueError:
        return "invalid"


def _resolve(fqdn: str) -> dict:
    if not fqdn:
        return {"error": "ACR_FQDN env var not set"}
    try:
        infos = socket.getaddrinfo(fqdn, 443, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        return {"fqdn": fqdn, "error": f"gaierror: {exc}"}
    addrs = []
    seen: set[str] = set()
    for info in infos:
        addr = info[4][0]
        if addr in seen:
            continue
        seen.add(addr)
        addrs.append({"ip": addr, "class": _classify(addr)})
    first = addrs[0]["class"] if addrs else "none"
    return {"fqdn": fqdn, "addresses": addrs, "first_class": first}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._respond(200, "ok\n", "text/plain")
            return
        if self.path == "/info":
            self._respond(
                200,
                f"build_tag={BUILD_TAG} pid={os.getpid()} acr_fqdn={ACR_FQDN}\n",
                "text/plain",
            )
            return
        if self.path == "/probe":
            payload = _resolve(ACR_FQDN)
            self._respond(200, json.dumps(payload) + "\n", "application/json")
            return
        if self.path == "/":
            self._respond(
                200,
                f"acr-network-path-dns-forwarder-bypass lab build_tag={BUILD_TAG}\n",
                "text/plain",
            )
            return
        self._respond(404, "not found\n", "text/plain")

    def _respond(self, status: int, body: str, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        return


def main() -> None:
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(
            f"[app] listening on :{PORT} build_tag={BUILD_TAG} acr_fqdn={ACR_FQDN}",
            flush=True,
        )
        httpd.serve_forever()


if __name__ == "__main__":
    main()
