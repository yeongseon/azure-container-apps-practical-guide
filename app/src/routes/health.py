from datetime import datetime, timezone
from flask import Blueprint, jsonify

health_bp = Blueprint("health", __name__)


@health_bp.route("/health")
def health():
    return jsonify(
        {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}
    )
