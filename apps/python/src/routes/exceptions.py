import logging
from flask import Blueprint, jsonify

exceptions_bp = Blueprint("exceptions", __name__)
logger = logging.getLogger(__name__)


@exceptions_bp.route("/test-error")
def test_error():
    logger.error("Test error endpoint called - simulating application error")
    return jsonify(
        {
            "error": "TestError",
            "message": "This is a simulated error for testing error handling and logging",
            "note": "Check ContainerAppConsoleLogs in Log Analytics for error details",
        }
    ), 500
