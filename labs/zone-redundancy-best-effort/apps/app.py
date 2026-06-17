# pyright: reportMissingImports=false

import json
import logging
import os
import socket
import sys
import time
import uuid
from datetime import datetime, timezone
from typing import Any

from azure.monitor.opentelemetry import configure_azure_monitor
from flask import Flask, Response, g, has_request_context, jsonify, request
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.trace import Status, StatusCode, get_current_span


APP_NAME = os.environ.get("CONTAINER_APP_NAME", "subject-app")
REVISION = os.environ.get("CONTAINER_APP_REVISION", "unknown")
REPLICA = socket.gethostname()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def configure_logging() -> logging.Logger:
    logging.basicConfig(level=logging.INFO, format="%(message)s", stream=sys.stdout)
    logger = logging.getLogger("subject-app")
    logger.setLevel(logging.INFO)
    return logger


LOGGER = configure_logging()


def emit_log(level: int, event: str, **fields: object) -> None:
    payload: dict[str, Any] = {
        "timestamp": utc_now(),
        "event": event,
        "service": APP_NAME,
        "replica": REPLICA,
        "revision": REVISION,
    }
    if has_request_context():
        payload.update(
            {
                "request_id": getattr(g, "request_id", None),
                "method": request.method,
                "path": request.path,
            }
        )
    payload.update(fields)
    LOGGER.log(level, json.dumps(payload, sort_keys=True))


def configure_telemetry() -> None:
    connection_string = os.environ.get(
        "APPLICATIONINSIGHTS_CONNECTION_STRING", ""
    ).strip()
    if not connection_string:
        print(
            "WARNING: APPLICATIONINSIGHTS_CONNECTION_STRING is missing; Azure Monitor telemetry disabled.",
            file=sys.stderr,
            flush=True,
        )
        return

    configure_azure_monitor(
        connection_string=connection_string,
        instrumentation_options={"flask": {"enabled": False}},
        logger_name="subject-app",
        resource=Resource.create({"service.name": APP_NAME}),
    )


configure_telemetry()

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)


@app.before_request
def before_request() -> None:
    g.request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
    g.request_started = time.perf_counter()


@app.after_request
def after_request(response: Response) -> Response:
    duration_ms = round(
        (time.perf_counter() - getattr(g, "request_started", time.perf_counter()))
        * 1000,
        2,
    )
    response.headers["X-Request-ID"] = g.request_id
    emit_log(
        logging.INFO,
        "request.completed",
        status_code=response.status_code,
        duration_ms=duration_ms,
        user_agent=request.headers.get("User-Agent", ""),
    )
    return response


@app.route("/", methods=["GET"])
def index():
    return jsonify({"status": "ok", "replica": REPLICA, "revision": REVISION}), 200


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/load", methods=["GET"])
def load():
    try:
        workload_ms = int(request.args.get("ms", "100"))
    except ValueError:
        workload_ms = 100

    workload_ms = max(0, min(workload_ms, 5000))
    deadline = time.perf_counter() + (workload_ms / 1000)
    while time.perf_counter() < deadline:
        pass

    return jsonify({"workload_ms": workload_ms, "replica": REPLICA}), 200


@app.route("/error", methods=["GET"])
def error():
    try:
        raise RuntimeError("intentional error for testing Q5")
    except RuntimeError as exc:
        span = get_current_span()
        if span is not None and span.is_recording():
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)))
        emit_log(
            logging.ERROR, "request.intentional_error", error=str(exc), status_code=500
        )
        return jsonify({"error": "intentional error for testing Q5"}), 500
