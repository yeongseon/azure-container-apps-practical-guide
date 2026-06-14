"""Diag app for the replica-node-spread lab.

Exposes /diag, which returns kernel-level signals that act as a proxy
for underlying node identity. The signals are intentionally read
fresh on every request so that the response reflects the actual
container at request time, not a cached value from import time.

Fields returned (Oracle-modified design per Issue #202):

| Field               | Source                                          | Purpose                                    |
|---------------------|-------------------------------------------------|--------------------------------------------|
| boot_id             | /proc/sys/kernel/random/boot_id                 | Primary kernel-context signal              |
| uptime_seconds      | /proc/uptime field 0                            | Monotonicity + boot-time estimation        |
| boot_time_estimate  | sample_timestamp - uptime_seconds (server side) | Derived clustering signal                  |
| machine_id          | /etc/machine-id if present                      | Secondary signal (often missing)           |
| kernel_release      | uname -r                                        | Kernel version (host-shared)               |
| microcode           | /proc/cpuinfo "microcode" field if present      | CPU microcode revision (host-shared)       |
| cpu_model           | /proc/cpuinfo "model name" field if present     | Host CPU model (host-shared)               |
| replica_name        | $CONTAINER_APP_REPLICA_NAME / hostname fallback | Replica identity (ACA-injected)            |
| revision            | $CONTAINER_APP_REVISION / "" fallback           | Revision identity (ACA-injected)           |
| sample_timestamp    | Server-side UTC epoch ms                        | Anchor for boot_time_estimate              |

Sources:
- /proc semantics: https://man7.org/linux/man-pages/man5/proc.5.html
- ACA environment variables:
  https://learn.microsoft.com/en-us/azure/container-apps/environment-variables
"""

from __future__ import annotations

import os
import platform
import socket
import time
from typing import Optional

from flask import Flask, jsonify

app = Flask(__name__)


def _read_text(path: str) -> Optional[str]:
    """Read a small text file; return None if missing or unreadable."""
    try:
        with open(path, "rt", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return None


def _read_uptime_seconds() -> Optional[float]:
    """Parse /proc/uptime; the first field is seconds since kernel boot."""
    raw = _read_text("/proc/uptime")
    if raw is None:
        return None
    parts = raw.split()
    if not parts:
        return None
    try:
        return float(parts[0])
    except ValueError:
        return None


def _read_cpuinfo_field(field: str) -> Optional[str]:
    """Return the first matching value of a /proc/cpuinfo key (e.g. 'microcode')."""
    raw = _read_text("/proc/cpuinfo")
    if raw is None:
        return None
    for line in raw.splitlines():
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        if key.strip() == field:
            return value.strip()
    return None


@app.route("/")
def root():
    """Probe target — kept tiny so Startup/Readiness probes are cheap."""
    return "ok\n", 200


@app.route("/diag")
def diag():
    """Return one kernel-signal snapshot for this replica."""
    # Capture sample_timestamp FIRST so boot_time_estimate is computed
    # against the request-receipt instant, not a later moment.
    sample_timestamp_ms = int(time.time() * 1000)

    uptime_seconds = _read_uptime_seconds()
    boot_time_estimate_ms: Optional[int] = None
    if uptime_seconds is not None:
        boot_time_estimate_ms = sample_timestamp_ms - int(uptime_seconds * 1000)

    payload = {
        "event": "DiagSample",
        "sample_timestamp_ms": sample_timestamp_ms,
        "boot_id": _read_text("/proc/sys/kernel/random/boot_id"),
        "uptime_seconds": uptime_seconds,
        "boot_time_estimate_ms": boot_time_estimate_ms,
        "machine_id": _read_text("/etc/machine-id"),
        "kernel_release": platform.release(),
        "microcode": _read_cpuinfo_field("microcode"),
        "cpu_model": _read_cpuinfo_field("model name"),
        "replica_name": os.environ.get(
            "CONTAINER_APP_REPLICA_NAME", socket.gethostname()
        ),
        "revision": os.environ.get("CONTAINER_APP_REVISION", ""),
        "app_name": os.environ.get("CONTAINER_APP_NAME", ""),
        "hostname": socket.gethostname(),
    }
    return jsonify(payload), 200


if __name__ == "__main__":
    # Standalone dev mode only; production runs under gunicorn (see Dockerfile).
    app.run(host="0.0.0.0", port=8080)
