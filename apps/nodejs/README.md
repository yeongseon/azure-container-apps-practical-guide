# Node.js Reference App (Express)

Minimal Express application that backs the [Node.js language guide](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/nodejs/). It demonstrates the Container Apps runtime contract for a Node.js workload: listen on `$PORT` (default `8000`), emit structured JSON logs to stdout, handle `SIGTERM`/`SIGINT` for graceful shutdown, and export telemetry to Application Insights when a connection string is present.

## Stack

- **Express 4** (Node.js `>=20`).
- **applicationinsights** SDK, initialized before other imports and activated only when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set (`src/app.js`).
- JSON request-logging middleware (`src/middleware/logging.js`).
- Base image `node:20-slim`, runs as the non-root `node` user (see `Dockerfile`).

## Layout

```text
apps/nodejs/
├── Dockerfile            # node:20-slim, EXPOSE 8000, USER node
├── package.json          # express, applicationinsights, dotenv; engines node>=20
└── src/
    ├── app.js            # Express app, App Insights bootstrap, graceful shutdown
    ├── middleware/
    │   └── logging.js    # JSON access logger
    └── routes/
        ├── health.js
        └── info.js
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | HTML landing page listing the endpoints |
| GET | `/health` | Health check |
| GET | `/info` | Application and runtime info |

## Run locally

```bash
cd apps/nodejs

npm install

# Start
npm start                 # listens on http://0.0.0.0:8000

# Or with file watching
npm run dev
```

Then:

```bash
curl http://localhost:8000/health
```

## Run in a container

```bash
cd apps/nodejs
docker build --tag aca-nodejs-guide:local .
docker run --rm --publish 8000:8000 aca-nodejs-guide:local
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8000` | Ingress target port |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | *(unset)* | Enables Application Insights export when present |

The graceful-shutdown handler closes the HTTP server on `SIGTERM`/`SIGINT` and force-exits after a 30-second timeout.

## See Also

- [Node.js language guide](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/nodejs/) — local development through revisions and traffic splitting.
