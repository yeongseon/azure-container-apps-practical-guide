import os
import sys
from flask import Blueprint, jsonify

info_bp = Blueprint("info", __name__)


@info_bp.route("/info")
def info():
    return jsonify(
        {
            "name": "azure-container-apps-reference",
            "version": "1.0.0",
            "python": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
            "environment": os.environ.get("FLASK_ENV", "development"),
            "telemetryMode": os.environ.get("TELEMETRY_MODE", "basic"),
            "containerApp": os.environ.get("CONTAINER_APP_NAME", "local"),
            "revision": os.environ.get("CONTAINER_APP_REVISION", "local"),
        }
    )
