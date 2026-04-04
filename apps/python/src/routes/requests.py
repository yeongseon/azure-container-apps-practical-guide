import logging
from flask import Blueprint, jsonify

requests_bp = Blueprint("requests", __name__)
logger = logging.getLogger(__name__)


@requests_bp.route("/log-levels")
def log_levels():
    logger.debug("Debug level log - Detailed diagnostic information")
    logger.info("Info level log - Normal operational messages")
    logger.warning("Warning level log - Potential issues")
    logger.error("Error level log - Application errors")

    return jsonify(
        {
            "message": "Log level examples generated",
            "logLevels": {
                "debug": "Verbose (0) - Detailed diagnostic info",
                "info": "Information (1) - Normal operational messages",
                "warn": "Warning (2) - Potential issues",
                "error": "Error (3) - Application errors",
            },
            "note": "Check Container Apps logs via Azure Portal or CLI",
            "query": {
                "portalLogs": 'ContainerAppConsoleLogs_CL | where ContainerAppName_s == "<app-name>" | order by TimeGenerated desc',
                "cliCommand": "az containerapp logs show --name <app-name> --resource-group <rg-name>",
            },
        }
    )
