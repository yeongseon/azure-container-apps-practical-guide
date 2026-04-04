#!/usr/bin/env bash
set -euo pipefail

# Trap SIGTERM for graceful shutdown (Container Apps sends SIGTERM before SIGKILL)
trap 'echo "SIGTERM received, shutting down..."; kill -TERM "$PID"; wait "$PID"' TERM

echo "Starting application..."
echo "PORT=${PORT:-8000}"
echo "Workers=${WEB_CONCURRENCY:-auto}"

# Start Gunicorn with config file
gunicorn --config gunicorn.conf.py --chdir src "app:app" &
PID=$!

# Wait for Gunicorn process
wait "$PID"
