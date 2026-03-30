import logging
import time
import uuid
import requests
from flask import Blueprint, jsonify

dependencies_bp = Blueprint("dependencies", __name__)
logger = logging.getLogger(__name__)


@dependencies_bp.route("/external")
def external_call():
    correlation_id = str(uuid.uuid4())
    start_time = time.time()

    try:
        response = requests.get(
            "https://jsonplaceholder.typicode.com/posts/1",
            timeout=10,
            headers={"X-Correlation-ID": correlation_id},
        )
        response.raise_for_status()
        duration = (time.time() - start_time) * 1000

        logger.info(
            f"External API call successful",
            extra={
                "correlationId": correlation_id,
                "duration": duration,
                "statusCode": response.status_code,
            },
        )

        return jsonify(
            {
                "message": "External dependency call successful",
                "data": response.json(),
                "metadata": {
                    "correlationId": correlation_id,
                    "duration": round(duration, 2),
                    "statusCode": response.status_code,
                },
            }
        )
    except Exception as e:
        logger.error(
            f"External API call failed: {e}", extra={"correlationId": correlation_id}
        )
        return jsonify(
            {
                "error": "External dependency call failed",
                "message": str(e),
                "correlationId": correlation_id,
            }
        ), 500
