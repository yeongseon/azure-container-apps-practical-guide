# Language Guides: Step-by-Step Implementation

Language Guides provide a tailored experience for developers working with specific runtimes on Azure Container Apps. Each guide is a complete learning path from local development to production operations.

## Purpose

These guides are designed to help you build applications that are "platform-native." Instead of just showing how to "deploy an app," they explain how to implement patterns that make your application resilient, observable, and easy to manage.

## Currently Available

-   **[Python (Flask)](python/01-local-development.md)**: A comprehensive guide covering Flask with Gunicorn, health endpoints, structured logging, and common integration recipes.

## Coming Soon

-   **Node.js (Express)**: Best practices for async performance, memory management, and package optimization.
-   **Java (Spring Boot / Quarkus)**: Guides for optimizing startup times with Native Image, JVM tuning, and Dapr SDK.
-   **C# (.NET 8+)**: Minimal APIs, health check middleware, and managed identity integration.

## What Each Language Guide Includes

Every language-specific path is structured the same way:

1. **Tutorial Steps**: A numbered sequence from `01-local-run` to `07-revisions-traffic`.
2. **Runtime Guide**: Details on specific runtime settings (e.g., Gunicorn workers, memory limits, port binding).
3. **Recipes**: "Copy-pasteable" patterns for connecting to Cosmos DB, Redis, Key Vault, and more.

## Common Patterns Across All Languages

While the implementation details vary, every application in this hub follows these core patterns:

-   **Health Endpoints**: Exposing `/health` for liveness and readiness probes.
-   **Structured Logging**: Writing logs in JSON format for Azure Log Analytics.
-   **Managed Identity**: Authenticating to Azure services without passwords or connection strings.
-   **Revision-Safe Behavior**: Handling SIGTERM for graceful shutdown and stateful handoffs.
-   **Port Binding**: Listening on the port specified by the platform (defaulting to 8000).

## See Also

- [Python Guide](python/01-local-development.md)
- [Start Here - Learning Paths](../start-here/learning-paths.md)
- [Platform - Architecture](../platform/index.md)
