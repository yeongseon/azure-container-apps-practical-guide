# Python Reference App (Flask + Gunicorn)

Minimal Flask application that backs the [Python language guide](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/python/). It demonstrates the Container Apps runtime contract for a Python workload: listen on `$PORT` (default `8000`), emit structured JSON logs to stdout, handle `SIGTERM` for graceful shutdown, and export telemetry to Application Insights when a connection string is present.

## Stack

- **Flask 3** served by **Gunicorn** (`gthread` worker class, config in `gunicorn.conf.py`).
- **azure-monitor-opentelemetry** for Application Insights export (activated only when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set — see `src/config/telemetry.py`).
- Base image `python:3.11-slim` (see `Dockerfile`).

## Layout

```text
apps/python/
├── Dockerfile            # python:3.11-slim, EXPOSE 8000, entrypoint.sh
├── entrypoint.sh         # Traps SIGTERM, launches Gunicorn with graceful shutdown
├── gunicorn.conf.py      # Workers, threads, timeouts, graceful_timeout=30s
├── requirements.txt      # flask, gunicorn, requests, azure-monitor-opentelemetry, python-dotenv
├── infra/                # Bicep for provisioning the app on Container Apps
└── src/
    ├── app.py            # Flask app factory, JSON log formatter, blueprint registration
    ├── config/           # telemetry configuration
    └── routes/           # health, info, requests, dependencies, exceptions blueprints
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | HTML landing page listing the endpoints |
| GET | `/health` | Health check |
| GET | `/info` | Application and runtime info |
| GET | `/api/requests/log-levels` | Generate logs at all severity levels |
| GET | `/api/dependencies/external` | External API call demo |
| GET | `/api/exceptions/test-error` | Error handling demo |

## Run locally

```bash
cd apps/python

python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Development server (Flask, debug on)
python src/app.py                 # listens on http://0.0.0.0:8000

# Or the production entrypoint (Gunicorn, matches the container)
./entrypoint.sh
```

Then:

```bash
curl http://localhost:8000/health
```

## Run in a container

```bash
cd apps/python
docker build --tag aca-python-guide:local .
docker run --rm --publish 8000:8000 aca-python-guide:local
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8000` | Ingress target port |
| `LOG_LEVEL` | `INFO` | Log verbosity |
| `WEB_CONCURRENCY` | `cpu*2+1` | Gunicorn worker count |
| `GUNICORN_THREADS` | `4` | Threads per worker |
| `GUNICORN_GRACEFUL_TIMEOUT` | `30` | Graceful shutdown window (seconds) |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | *(unset)* | Enables Application Insights export when present |

## See Also

- [Python language guide](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/python/) — local development through revisions and traffic splitting.
