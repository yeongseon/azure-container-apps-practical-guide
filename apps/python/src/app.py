# pyright: reportMissingImports=false
import os
import logging
import json
from datetime import datetime, timezone
from flask import Flask, jsonify

from config.telemetry import configure_telemetry
from routes.health import health_bp
from routes.info import info_bp
from routes.requests import requests_bp
from routes.dependencies import dependencies_bp
from routes.exceptions import exceptions_bp

# Configure telemetry before Flask app
configure_telemetry()

app = Flask(__name__)

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO").upper()


class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info and record.exc_info[0]:
            log_record["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_record)


handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.basicConfig(level=getattr(logging, log_level), handlers=[handler])
logger = logging.getLogger(__name__)

# Register blueprints
app.register_blueprint(health_bp)
app.register_blueprint(info_bp)
app.register_blueprint(requests_bp, url_prefix="/api/requests")
app.register_blueprint(dependencies_bp, url_prefix="/api/dependencies")
app.register_blueprint(exceptions_bp, url_prefix="/api/exceptions")


@app.route("/")
def index():
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Azure Container Apps Python Guide</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
            h1 { color: #0078d4; }
            .endpoint { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 8px; }
            .method { background: #0078d4; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; }
            code { background: #e8e8e8; padding: 2px 6px; border-radius: 4px; }
        </style>
    </head>
    <body>
        <h1>🐳 Azure Container Apps Python Guide</h1>
        <p>Guide implementation for Flask on Azure Container Apps.</p>
        
        <h2>Endpoints</h2>
        <div class="endpoint"><span class="method">GET</span> <code>/health</code> - Health check</div>
        <div class="endpoint"><span class="method">GET</span> <code>/info</code> - Application info</div>
        <div class="endpoint"><span class="method">GET</span> <code>/api/requests/log-levels</code> - Generate logs at all severity levels</div>
        <div class="endpoint"><span class="method">GET</span> <code>/api/dependencies/external</code> - External API call demo</div>
        <div class="endpoint"><span class="method">GET</span> <code>/api/exceptions/test-error</code> - Error handling demo</div>
    </body>
    </html>
    """


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    app.run(host="0.0.0.0", port=port, debug=True)
