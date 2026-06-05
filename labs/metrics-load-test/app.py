from __future__ import annotations

import os
import time
from flask import Flask, jsonify, request, Response

app = Flask(__name__)
MEM_HOLD: list[bytearray] = []


@app.get("/")
def index() -> Response:
    return jsonify(
        app="metrics-load-test",
        endpoints=[
            "/health",
            "/cpu?ms=500",
            "/mem?mb=64",
            "/mem/release",
            "/slow?ms=2000",
            "/error?code=500",
            "/payload?kb=128",
        ],
    )


@app.get("/health")
def health() -> Response:
    return jsonify(status="healthy")


@app.get("/cpu")
def burn_cpu_for_milliseconds() -> Response:
    ms = int(request.args.get("ms", "500"))
    deadline = time.perf_counter() + ms / 1000.0
    sentinel = 0.0
    while time.perf_counter() < deadline:
        sentinel += sum(i * i for i in range(2000))
    return jsonify(burned_ms=ms, sentinel=sentinel)


@app.get("/mem")
def allocate_and_hold_memory() -> Response:
    mb = int(request.args.get("mb", "64"))
    block = bytearray(mb * 1024 * 1024)
    # Force RSS growth: Linux demand-pages bytearray lazily, so touch one byte per 4KiB page.
    for i in range(0, len(block), 4096):
        block[i] = 1
    MEM_HOLD.append(block)
    held_mb = sum(len(b) for b in MEM_HOLD) // (1024 * 1024)
    return jsonify(allocated_mb=mb, total_held_mb=held_mb)


@app.post("/mem/release")
@app.get("/mem/release")
def release_held_memory() -> Response:
    MEM_HOLD.clear()
    return jsonify(released=True)


@app.get("/slow")
def sleep_then_respond() -> Response:
    ms = int(request.args.get("ms", "2000"))
    time.sleep(ms / 1000.0)
    return jsonify(slept_ms=ms)


@app.get("/error")
def return_intentional_error() -> Response:
    code = int(request.args.get("code", "500"))
    return Response(f"intentional {code}\n", status=code, mimetype="text/plain")


@app.get("/payload")
def return_large_payload() -> Response:
    kb = int(request.args.get("kb", "128"))
    return Response("x" * (kb * 1024), mimetype="text/plain")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    app.run(host="0.0.0.0", port=port)
