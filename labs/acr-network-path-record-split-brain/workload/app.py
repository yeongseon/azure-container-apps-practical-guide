"""HTTP probe app for the ACR Record-Level Split-Brain (Scenario D) lab.

Scenario D is the *record-level* DNS failure class: the resolver path is
correct (the VNet sends queries to Azure DNS, Azure DNS sees the VNet
link to privatelink.azurecr.io), but the zone CONTENT is incomplete --
specifically, the `<registry>.<region>.data` A record is missing.

Empirical finding from this lab: when the data A record is deleted from
the linked privatelink.azurecr.io zone, Azure DNS (the default VNet
resolver) treats the zone as AUTHORITATIVE and returns NXDOMAIN, NOT a
public-IP fallthrough. The application sees a DNS resolution failure
(socket.gaierror) on the data endpoint while the registry endpoint
keeps resolving privately. True "registry private, data public"
split-brain only occurs when a custom DNS server (BIND with views,
systemd-resolved with multi-domain fallback, etc.) is wired to fall
back to public DNS on NXDOMAIN -- a separate, more complex topology
that this lab intentionally does not reproduce.

This probe surfaces the asymmetry at four layers, for BOTH FQDNs:

  1. DNS  -- socket.getaddrinfo() first answer + RFC1918 classification
  2. TCP  -- socket.create_connection() success / refused / timeout
  3. TLS  -- ssl.wrap_socket() handshake success / error
  4. HTTP -- GET /v2/ status code (401 from registry backend; 403 from
            data backend or ACR firewall on public path)

The 4 layers together discriminate Scenario D from Scenarios B and E:
   both_private    -> Scenario B happy path: both FQDNs resolve to PE NIC
   data_nxdomain   -> Scenario D (default Azure DNS): data record missing
                      from zone => Azure DNS returns NXDOMAIN
   split_brain     -> Scenario D (custom DNS with public fallback): data
                      record missing AND resolver falls back to public
                      DNS => data resolves to public ACR IP
   both_public     -> Scenario E or no zone link at all
   any_dns_error   -> resolver-path failure on registry (different class)

Endpoints:

- GET /        -> identity banner
- GET /health  -> "ok"
- GET /info    -> build tag (from BUILD_TAG env var)
- GET /probe   -> JSON: 4-layer probe of both FQDNs + topology_class
"""

from __future__ import annotations

import http.server
import ipaddress
import json
import os
import socket
import socketserver
import ssl

PORT = int(os.environ.get("PORT", "80"))
BUILD_TAG = os.environ.get("BUILD_TAG", "v1")
ACR_FQDN = os.environ.get("ACR_FQDN", "")
ACR_DATA_FQDN = os.environ.get("ACR_DATA_FQDN", "")

_TCP_TIMEOUT_SECONDS = 5.0
_TLS_TIMEOUT_SECONDS = 5.0
_HTTP_TIMEOUT_SECONDS = 5.0


def _classify_ip(addr: str) -> str:
    try:
        return "private" if ipaddress.ip_address(addr).is_private else "public"
    except ValueError:
        return "invalid"


def _dns_layer(fqdn: str) -> dict:
    if not fqdn:
        return {"ip": None, "class": None, "error": "fqdn env var not set"}
    try:
        infos = socket.getaddrinfo(fqdn, 443, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        return {"ip": None, "class": None, "error": f"gaierror: {exc}"}
    if not infos:
        return {"ip": None, "class": None, "error": "no addresses returned"}
    first_ip = infos[0][4][0]
    return {"ip": first_ip, "class": _classify_ip(first_ip), "error": None}


def _tcp_layer(ip: str) -> dict:
    try:
        sock = socket.create_connection((ip, 443), timeout=_TCP_TIMEOUT_SECONDS)
        sock.close()
        return {"connected": True, "error": None}
    except (OSError, socket.timeout) as exc:
        return {"connected": False, "error": f"{type(exc).__name__}: {exc}"}


def _tls_layer(ip: str, sni: str) -> dict:
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((ip, 443), timeout=_TLS_TIMEOUT_SECONDS) as raw:
            with ctx.wrap_socket(raw, server_hostname=sni) as _tls:
                return {"handshake": "ok", "error": None}
    except (ssl.SSLError, OSError, socket.timeout) as exc:
        return {"handshake": "fail", "error": f"{type(exc).__name__}: {exc}"}


def _http_layer(ip: str, sni: str) -> dict:
    """GET https://{ip}/v2/ with Host: {sni}. ACR returns:
    - 401 with WWW-Authenticate when the request reached the backend
      (this is what we want to see for both registry and data on the
      private path).
    - 403 with DENIED body when the ACR firewall rejected the public
      request (publicNetworkAccess=Disabled).
    """
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((ip, 443), timeout=_HTTP_TIMEOUT_SECONDS) as raw:
            with ctx.wrap_socket(raw, server_hostname=sni) as tls:
                tls.settimeout(_HTTP_TIMEOUT_SECONDS)
                request = (
                    f"GET /v2/ HTTP/1.1\r\n"
                    f"Host: {sni}\r\n"
                    f"User-Agent: scenario-d-probe/{BUILD_TAG}\r\n"
                    f"Connection: close\r\n"
                    f"\r\n"
                ).encode("ascii")
                tls.sendall(request)
                buf = b""
                while True:
                    chunk = tls.recv(4096)
                    if not chunk:
                        break
                    buf += chunk
                    if len(buf) >= 512:
                        break
                status_line = buf.split(b"\r\n", 1)[0].decode("ascii", errors="replace")
                status_code = None
                parts = status_line.split(" ", 2)
                if len(parts) >= 2 and parts[1].isdigit():
                    status_code = int(parts[1])
                return {
                    "status": status_code,
                    "status_line": status_line,
                    "error": None,
                }
    except (ssl.SSLError, OSError, socket.timeout) as exc:
        return {
            "status": None,
            "status_line": None,
            "error": f"{type(exc).__name__}: {exc}",
        }


def _probe_fqdn(fqdn: str) -> dict:
    """Run a 4-layer probe (DNS, TCP, TLS, HTTP) against `fqdn` and stop
    as soon as a layer fails so downstream layers don't run on stale data.
    """
    out = {"fqdn": fqdn}
    dns = _dns_layer(fqdn)
    out["dns"] = dns
    if not dns["ip"]:
        out["tcp"] = {"connected": None, "error": "skipped (no DNS)"}
        out["tls"] = {"handshake": None, "error": "skipped (no DNS)"}
        out["http"] = {"status": None, "status_line": None, "error": "skipped (no DNS)"}
        return out
    out["tcp"] = _tcp_layer(dns["ip"])
    if not out["tcp"]["connected"]:
        out["tls"] = {"handshake": None, "error": "skipped (TCP failed)"}
        out["http"] = {
            "status": None,
            "status_line": None,
            "error": "skipped (TCP failed)",
        }
        return out
    out["tls"] = _tls_layer(dns["ip"], fqdn)
    if out["tls"]["handshake"] != "ok":
        out["http"] = {
            "status": None,
            "status_line": None,
            "error": "skipped (TLS failed)",
        }
        return out
    out["http"] = _http_layer(dns["ip"], fqdn)
    return out


def _topology_class(registry: dict, data: dict) -> str:
    rc = registry.get("dns", {}).get("class")
    dc = data.get("dns", {}).get("class")
    r_err = registry.get("dns", {}).get("error")
    d_err = data.get("dns", {}).get("error")
    if rc == "private" and dc == "private":
        return "both_private"
    if rc == "private" and dc == "public":
        return "split_brain"
    if rc == "public" and dc == "public":
        return "both_public"
    if rc == "public" and dc == "private":
        return "inverted_split_brain"
    if rc == "private" and dc is None and d_err:
        return "data_nxdomain"
    if rc is None and dc == "private" and r_err:
        return "registry_nxdomain"
    if rc is None and dc is None and r_err and d_err:
        return "both_nxdomain"
    return f"unclassified (registry={rc}, data={dc})"


class Handler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, status: int, body: dict) -> None:
        payload = json.dumps(body, indent=2, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _send_text(self, status: int, body: str) -> None:
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:  # noqa: N802 -- BaseHTTPRequestHandler API
        if self.path == "/health":
            self._send_text(200, "ok")
            return
        if self.path == "/info":
            self._send_text(200, f"build={BUILD_TAG}\n")
            return
        if self.path == "/probe":
            registry = _probe_fqdn(ACR_FQDN)
            data = _probe_fqdn(ACR_DATA_FQDN)
            body = {
                "build": BUILD_TAG,
                "registry": registry,
                "data": data,
                "topology_class": _topology_class(registry, data),
            }
            self._send_json(200, body)
            return
        self._send_text(
            200,
            f"Scenario D probe app (build={BUILD_TAG}). Endpoints: /health, /info, /probe.\n",
        )

    def log_message(self, format: str, *args) -> None:  # noqa: A002 -- match BaseHTTPRequestHandler
        # Silence default per-request access log; container logs are noisy enough.
        return


def main() -> None:
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
