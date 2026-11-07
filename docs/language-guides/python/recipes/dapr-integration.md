---
content_sources:
  diagrams:
    - id: azure-container-apps-aca-provides-native
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
---
# Dapr Integration (Distributed Application Runtime)

Azure Container Apps provides native Dapr integration, allowing your Python application to easily interact with other services and manage state, publish/subscribe messaging, and secrets.

<!-- diagram-id: azure-container-apps-aca-provides-native -->
```mermaid
flowchart TD
    accTitle: Use Dapr APIs from a Python container app
    accDescr: A client request reaches the Python app through managed ingress. The app calls its local Dapr sidecar, which invokes configured state, publish and subscribe, secret, or service-invocation components.

    CLIENT[Client]
    INGRESS[Managed ingress]

    subgraph APP_BOUNDARY[Container app replica]
        APP[Python app]
        DAPR[Dapr sidecar]
    end

    STATE[State store component]
    BROKER[Publish and subscribe component]
    SECRET[Secret store component]
    SERVICE[Target Dapr-enabled app]

    CLIENT ==>|HTTPS request| INGRESS
    INGRESS ==>|Routed request| APP
    APP ==>|HTTP or gRPC on localhost| DAPR
    DAPR ==>|State API| STATE
    DAPR ==>|Publish or subscribe API| BROKER
    DAPR ==>|Secrets API| SECRET
    DAPR ==>|Service invocation| SERVICE
```

Thick arrows show application and Dapr API transport. The component resources remain outside the app replica boundary.

## Enabling Dapr

To enable Dapr for your container app:

```bash
az containerapp dapr enable \
  --name my-python-app \
  --resource-group my-aca-rg \
  --dapr-app-id my-python-service \
  --dapr-app-port 8000
```

| Command | Why it is used |
|---|---|
| `az containerapp dapr enable ...` | Configures Dapr sidecar settings for the Container App. |

## How Dapr Works

Dapr runs as a sidecar container alongside your application. Your application interacts with Dapr using HTTP or gRPC on `localhost`.

## Python Implementation

Use the `dapr` library in your Python code to interact with Dapr.

### State Management

```python
from dapr.clients import DaprClient

with DaprClient() as d:
    # Save state
    d.save_state(store_name='statestore', key='order_1', value='{"item": "laptop"}')

    # Get state
    state = d.get_state(store_name='statestore', key='order_1')
    print(state.data)
```

### Publish/Subscribe Messaging

```python
from dapr.clients import DaprClient

with DaprClient() as d:
    # Publish a message
    d.publish_event(
        pubsub_name='messagebus',
        topic_name='orders',
        data='{"orderId": 123}',
        data_content_type='application/json'
    )
```

## Dapr Components

Configure Dapr components (like state stores or pub/sub brokers) as separate resources in your Bicep/ARM templates. Container Apps then maps these components to your application at runtime.

## Why use Dapr?

- **Abstracted Infrastructure:** Switch from Redis to Service Bus without changing your application code.
- **Configurable resiliency:** Dapr service invocation can use explicit resiliency policies for retries, timeouts, and circuit breakers. Circuit breakers are not automatic; define and test the policy before relying on it in production.
- **Enhanced Observability:** Dapr automatically collects telemetry for all cross-service communication.

## See Also
- [Service-to-Service Communication](../../../platform/networking/service-to-service.md)
- [Managed Identity](../../../platform/identity-and-secrets/managed-identity.md)
- [Operations: Observability](../../../operations/monitoring/index.md)

## Sources
- [Dapr overview for Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview)
- [Dapr component schema in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/dapr-components)
