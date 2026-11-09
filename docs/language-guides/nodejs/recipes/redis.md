---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-azure-active-directory-for-authentication
        - https://learn.microsoft.com/en-us/azure/redis/nodejs-get-started
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
---
# Azure Cache for Redis Integration (Microsoft Entra Authentication)

Use this recipe to connect Azure Container Apps to Azure Cache for Redis with Microsoft Entra authentication first and access keys only as a fallback.

## Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Microsoft Entra authenticated Redis request from an Express app
    accDescr: A client request reaches Express through managed ingress. DefaultAzureCredential obtains a Redis token through the app's managed identity, then the Redis client opens a TLS connection on port 6380. The cache separately evaluates its data access policy. A required production extension, not implemented by the short-lived sample, refreshes the token and sends AUTH again on the existing connection. Reconnect only if the connection drops or the client cannot reauthenticate in place.
    CLIENT[Client]
    INGRESS[Managed ingress]
    APP1[Express app<br/>node-redis client]
    ENDPOINT1[Container Apps identity endpoint]
    ENTRA[Microsoft Entra ID]
    REDIS[Azure Cache for Redis<br/>TLS port 6380]
    AUTHZ[Redis authorization result]
    RESULT[Cache operation result]
    DENIED[Authorization failure]
    APP2[Express app<br/>response stage]
    REFRESH[Required production extension<br/>not implemented below]
    REFRESH_ENDPOINT[Container Apps identity endpoint]
    REFRESH_ENTRA[Microsoft Entra ID]
    REAUTH[Redis client<br/>AUTH with new token]

    CLIENT ==>|"HTTPS request"| INGRESS
    INGRESS ==>|"Routed request"| APP1
    APP1 ==>|"Request Redis token"| ENDPOINT1
    ENDPOINT1 ==>|"Token request"| ENTRA
    ENTRA ==>|"Access token response"| ENDPOINT1
    ENDPOINT1 ==>|"Return access token"| APP1
    APP1 ==>|"TLS Redis connection + token"| REDIS
    REDIS -->|"Evaluate data access policy"| AUTHZ
    AUTHZ -->|"Allowed"| RESULT
    AUTHZ -.->|"Denied"| DENIED
    RESULT ==>|"Cache response"| APP2
    DENIED -.->|"Authorization error"| APP2
    APP2 ==>|"Application response"| INGRESS
    INGRESS ==>|"HTTPS response"| CLIENT
    APP2 -->|"Token nearing expiry"| REFRESH
    REFRESH ==>|"Request replacement token"| REFRESH_ENDPOINT
    REFRESH_ENDPOINT ==>|"Token request"| REFRESH_ENTRA
    REFRESH_ENTRA ==>|"Access token response"| REFRESH_ENDPOINT
    REFRESH_ENDPOINT ==>|"Replacement token"| REAUTH
    REAUTH ==>|"AUTH on existing connection"| REDIS
```

*Figure: Token acquisition, TLS transport on port `6380`, and Redis data authorization are implemented by the short-lived sample. The refresh branch is a required production extension, not implemented below; long-lived clients must refresh the Microsoft Entra token and reauthenticate with `AUTH` on the existing connection. Reconnect only after a dropped connection or when the client library cannot reauthenticate in place.*

## Prerequisites

- Existing Container App: `$APP_NAME` in `$RG`
- Existing Azure Cache for Redis instance with Microsoft Entra authentication enabled
- TLS access enabled on port `6380`

## Step 1: Enable managed identity on the Container App

```bash
az containerapp identity assign \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --system-assigned

export PRINCIPAL_ID=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "identity.principalId" \
  --output tsv)
```

| Command | Why it is used |
|---|---|
| `az containerapp identity assign ...` | Assigns or inspects managed identity configuration for the Container App. |

## Step 2: Assign Redis data access

```bash
az redis access-policy-assignment create \
  --name "$REDIS_NAME" \
  --resource-group "$RG" \
  --policy-assignment-name "$APP_NAME-data-owner" \
  --access-policy-name "Data Owner" \
  --object-id "$PRINCIPAL_ID" \
  --object-id-alias "$APP_NAME"
```

| Command | Why it is used |
|---|---|
| `az redis access-policy-assignment create` | Creates the Redis Data Owner assignment for the Express app identity. |
| `--name` | Selects cache `$REDIS_NAME`. |
| `--resource-group` | Locates the cache in `$RG`. |
| `--policy-assignment-name` | Names the assignment `$APP_NAME-data-owner`. |
| `--access-policy-name` | Grants the built-in Redis `Data Owner` policy. |
| `--object-id` | Authorizes managed-identity object ID `$PRINCIPAL_ID`. |
| `--object-id-alias` | Labels the Redis assignment with `$APP_NAME`. |

## Step 3: Configure non-secret Redis settings

Azure Container Apps does **not** inject Redis host names, usernames, or tokens automatically.

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars REDIS_HOST="$REDIS_NAME.redis.cache.windows.net" REDIS_PORT="6380" REDIS_USERNAME="$PRINCIPAL_ID"
```

| Command | Why it is used |
|---|---|
| `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

## Step 4: Node.js code (Microsoft Entra token authentication)

Install dependencies:

```bash
npm install @azure/identity redis
```

Use `DefaultAzureCredential` to fetch the Redis access token:

```javascript
const { DefaultAzureCredential } = require("@azure/identity");
const { createClient } = require("redis");

async function createRedisClient() {
  if (process.env.REDIS_ACCESS_KEY) {
    return createClient({
      username: process.env.REDIS_USERNAME || "default",
      password: process.env.REDIS_ACCESS_KEY,
      socket: {
        host: process.env.REDIS_HOST,
        port: Number(process.env.REDIS_PORT || "6380"),
        tls: true,
      },
    });
  }

  const credential = new DefaultAzureCredential();
  const token = await credential.getToken("https://redis.azure.com/.default");

  return createClient({
    username: process.env.REDIS_USERNAME,
    password: token.token,
    socket: {
      host: process.env.REDIS_HOST,
      port: Number(process.env.REDIS_PORT || "6380"),
      tls: true,
    },
  });
}

async function run() {
  const client = await createRedisClient();
  await client.connect();
  await client.set("health", "ok", { EX: 60 });
  console.log(await client.get("health"));
  await client.quit();
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

!!! warning
    The Entra token used for Redis expires. For long-lived connections, refresh the token and reauthenticate by sending `AUTH` with the replacement token on the existing connection. Reconnect only if the connection drops or the Redis client library cannot reauthenticate in place.

## Step 5: Access key fallback

```bash
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets redis-access-key="<redis-primary-key>"

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars REDIS_HOST="$REDIS_NAME.redis.cache.windows.net" REDIS_PORT="6380" REDIS_ACCESS_KEY=secretref:redis-access-key
```

| Command | Why it is used |
|---|---|
| `az containerapp secret set ...` | Manages Container Apps secrets without exposing secret values in plain configuration. |

## Verification

1. Confirm the access policy assignment exists:

```bash
az redis access-policy-assignment list \
  --name "$REDIS_NAME" \
  --resource-group "$RG" \
  --output table
```

| Command | Why it is used |
|---|---|
| `az redis access-policy-assignment ...` | Creates or inspects Azure Cache for Redis resources used by the sample app. |

2. Confirm app logs show successful Redis `SET` and `GET` operations:

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --follow false
```

| Command | Why it is used |
|---|---|
| `az containerapp logs show ...` | Runs the Azure CLI operation required by the documented step. |

3. Confirm clients are using TLS on port `6380`.

## See Also

- [Managed Identity](managed-identity.md)
- [Private Endpoints](../../../platform/networking/private-endpoints.md)
- [Networking](../../../platform/networking/vnet-integration.md)

## Sources

- [Use Microsoft Entra for cache authentication](https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-azure-active-directory-for-authentication)
- [Use Azure Cache for Redis with Node.js](https://learn.microsoft.com/en-us/azure/redis/nodejs-get-started)
- [Managed identities in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
