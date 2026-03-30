import os
import logging

logger = logging.getLogger(__name__)


def configure_telemetry():
    """Configure OpenTelemetry with Azure Monitor."""
    connection_string = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
    telemetry_mode = os.environ.get("TELEMETRY_MODE", "basic")

    if telemetry_mode == "advanced" and connection_string:
        try:
            from azure.monitor.opentelemetry import configure_azure_monitor

            configure_azure_monitor(
                connection_string=connection_string,
                disable_offline_storage=True,
            )
            logger.info("Azure Monitor OpenTelemetry configured successfully")
        except Exception as e:
            logger.warning(f"Failed to configure Azure Monitor: {e}")
    else:
        logger.info(f"Running in {telemetry_mode} telemetry mode")
