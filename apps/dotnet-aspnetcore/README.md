# .NET Reference App (ASP.NET Core)

Minimal ASP.NET Core application that backs the [.NET language guide](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/dotnet/). It demonstrates the Container Apps runtime contract for a .NET workload: listen on `$PORT` (default `8000`), log to stdout, handle graceful shutdown via `ApplicationStopping`, and export telemetry to Azure Monitor / Application Insights when a connection string is present.

## Stack

- **ASP.NET Core** on **.NET 8** (`net8.0`), minimal hosting model plus MVC controllers.
- **Azure.Monitor.OpenTelemetry.AspNetCore** — Azure Monitor exporter, activated only when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set (`Program.cs`).
- Multi-stage `Dockerfile`: `dotnet/sdk:8.0-alpine` build → `dotnet/aspnet:8.0-alpine` runtime, runs as non-root UID `1000`.

## Layout

```text
apps/dotnet-aspnetcore/
├── Dockerfile                    # Multi-stage build, EXPOSE 8000, USER 1000:1000
├── AzureContainerApps.csproj     # net8.0, Azure.Monitor.OpenTelemetry.AspNetCore
├── Program.cs                    # Host bootstrap, Azure Monitor, graceful shutdown, PORT binding
├── appsettings.json
└── Controllers/
    ├── HealthController.cs
    └── InfoController.cs
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | HTML landing page listing the endpoints |
| GET | `/health` | Health check (`{status, timestamp}`) |
| GET | `/info` | Application and runtime info (framework, OS, revision, replica) |

## Run locally

```bash
cd apps/dotnet-aspnetcore

# Restore + run
dotnet run                        # listens on http://0.0.0.0:8000
```

Then:

```bash
curl http://localhost:8000/health
```

## Run in a container

```bash
cd apps/dotnet-aspnetcore
docker build --tag aca-dotnet-guide:local .
docker run --rm --publish 8000:8000 aca-dotnet-guide:local
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8000` | Ingress target port (`Program.cs` binds `http://0.0.0.0:$PORT`) |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | *(unset)* | Enables Azure Monitor export when present |
| `CONTAINER_APP_NAME` | `local` | Surfaced in `/info` (set by the platform) |
| `CONTAINER_APP_REVISION` | `local` | Surfaced in `/info` (set by the platform) |

The `ApplicationStopping` hook logs a graceful-shutdown message when the platform sends the stop signal.

## See Also

- [.NET language guide](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/dotnet/) — local development through revisions and traffic splitting.
