"""Minimal Flask app for the App Insights connection string missing lab.

The app guards ``configure_azure_monitor()`` behind an explicit presence
check of ``APPLICATIONINSIGHTS_CONNECTION_STRING``. This is the realistic
production pattern: apps that defensively wrap SDK init so a missing env
var degrades observability without taking down availability.

Behavior matrix:

* ``APPLICATIONINSIGHTS_CONNECTION_STRING`` ABSENT
    - The guard skips ``configure_azure_monitor()`` entirely.
    - HTTP 200 to every request, but the App Insights ``requests`` and
      ``traces`` tables stay empty because the OpenTelemetry SDK is never
      wired to an exporter. This is the failure mode the lab demonstrates:
      availability is fine, observability is silently broken.

* ``APPLICATIONINSIGHTS_CONNECTION_STRING`` PRESENT
    - ``configure_azure_monitor()`` wires the OpenTelemetry SDK to export
      request, trace, and log telemetry to Application Insights.
    - HTTP 200 plus visible rows in ``requests`` and ``traces``.

Important caveat on SDK behavior: if ``configure_azure_monitor()`` is
called WITHOUT the guard while the env var is unset,
``azure-monitor-opentelemetry==1.6.4`` raises
``ValueError: Instrumentation key cannot be none or empty.`` at import
time, the gunicorn worker exits with code 3, and the container goes into
CrashLoopBackOff. That is a DIFFERENT failure mode (availability loss,
not silent observability gap) and is captured separately in this lab's
evidence pack under ``A1-v1-unguarded-sdk-crash-logs.json``. The lab's
canonical scenario uses the guarded path because the silent observability
failure is the one most commonly seen in production escalations.
"""

import logging
import os

from azure.monitor.opentelemetry import configure_azure_monitor

# CRITICAL: import flask as a module (NOT `from flask import Flask`) so the
# Flask class lookup happens AFTER configure_azure_monitor() wires the
# OpenTelemetry Flask auto-instrumentation. If Flask is fully imported before
# configure_azure_monitor() runs, the instrumentation hook cannot wrap the
# Flask app and AppRequests stays empty even with a valid connection string.
import flask

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONN_STR = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
CONN_STR_PRESENT = bool(CONN_STR)

# Realistic production pattern: only wire the SDK when the env var is set.
# When unset, the app stays healthy but emits no telemetry — this is the
# silent observability gap the lab demonstrates.
if CONN_STR_PRESENT:
    # logger_name=__name__ routes this module's logger.info(...) calls into
    # AppTraces. Without it, only auto-instrumented telemetry (AppRequests,
    # AppDependencies) is exported and module-level logs stay invisible.
    configure_azure_monitor(connection_string=CONN_STR, logger_name=__name__)
    logger.info("Azure Monitor configured: telemetry export enabled")
else:
    logger.info("Azure Monitor skipped: APPLICATIONINSIGHTS_CONNECTION_STRING absent")

app = flask.Flask(__name__)


@app.route("/")
def hello():
    logger.info("/ endpoint hit (conn_str_present=%s)", CONN_STR_PRESENT)
    return (
        f"hello from telemetry-demo "
        f"(APPLICATIONINSIGHTS_CONNECTION_STRING present: {CONN_STR_PRESENT})\n"
    )


@app.route("/healthz")
def healthz():
    return "ok\n"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
