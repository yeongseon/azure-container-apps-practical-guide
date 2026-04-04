# pyright: reportMissingImports=false
from __future__ import annotations

import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobClient


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def configure_logging() -> logging.Logger:
    """Configure stdout JSON logs using LOG_LEVEL."""
    log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(
        level=getattr(logging, log_level, logging.INFO), handlers=[handler]
    )
    return logging.getLogger("aca-python-job")


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"Required environment variable is missing: {name}")
    return value


def read_blob_preview(
    account_url: str, container_name: str, blob_name: str
) -> dict[str, str | int]:
    credential = DefaultAzureCredential()
    blob_client = BlobClient(
        account_url=account_url,
        container_name=container_name,
        blob_name=blob_name,
        credential=credential,
    )
    raw_bytes = blob_client.download_blob().readall()
    return {
        "container": container_name,
        "blob": blob_name,
        "size_bytes": len(raw_bytes),
        "preview": raw_bytes[:200].decode("utf-8", errors="replace"),
    }


def main() -> int:
    """Execute a single job run and return exit code."""
    logger = configure_logging()
    started_at = datetime.now(timezone.utc)
    started = time.monotonic()
    execution_name = os.environ.get(
        "CONTAINER_APP_JOB_EXECUTION_NAME", "local-execution"
    )

    logger.info(
        "Job execution started",
        extra={"execution_name": execution_name, "started_at": started_at.isoformat()},
    )
    status = "Failed"
    exit_code = 1

    try:
        account_url = require_env("STORAGE_ACCOUNT_URL")
        container_name = require_env("STORAGE_CONTAINER_NAME")
        blob_name = require_env("STORAGE_BLOB_NAME")
        result = read_blob_preview(account_url, container_name, blob_name)
        logger.info(
            "Blob read succeeded",
            extra={
                "execution_name": execution_name,
                "container": result["container"],
                "blob": result["blob"],
                "size_bytes": result["size_bytes"],
                "preview": result["preview"],
            },
        )
        status = "Succeeded"
        exit_code = 0
    except ValueError:
        status = "InvalidConfiguration"
        exit_code = 2
        logger.exception("Job configuration error")
    except Exception:
        logger.exception("Unhandled error during job execution")

    duration_ms = int((time.monotonic() - started) * 1000)
    logger.info(
        "Job execution completed",
        extra={
            "execution_name": execution_name,
            "status": status,
            "duration_ms": duration_ms,
            "completed_at": datetime.now(timezone.utc).isoformat(),
            "exit_code": exit_code,
        },
    )
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
