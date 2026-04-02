# Azure Cache for Redis Integration (Managed Identity)

Use this recipe to connect Azure Container Apps to Azure Cache for Redis with Microsoft Entra authentication and managed identity.

## Prerequisites

- Existing Container App: `$APP_NAME` in `$RG`
- Existing Azure Cache for Redis instance
- TLS-enabled Redis access (default)

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

## Step 2: Assign Redis data access policy

Get the object ID used as Redis username:

```bash
export OBJECT_ID=$(az ad sp show \
  --id "$PRINCIPAL_ID" \
  --query "id" \
  --output tsv)
```

Create an access policy assignment (for example, Data Owner):

```bash
az redis access-policy-assignment create \
  --name "$REDIS_NAME" \
  --resource-group "$RG" \
  --access-policy-name "Data Owner" \
  --object-id "$OBJECT_ID" \
  --object-id-alias "$APP_NAME"
```

## Step 3: Configure Redis endpoint for the app

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars REDIS_HOST="$REDIS_NAME.redis.cache.windows.net" REDIS_PORT="10000"
```

## Step 4: Python code (Entra token auth)

Install dependencies:

```bash
pip install azure-identity redis
```

Use managed identity token as Redis password:

```python
import os
import redis
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
access_token = credential.get_token("https://redis.azure.com/.default").token

host = os.environ["REDIS_HOST"]
port = int(os.environ.get("REDIS_PORT", "10000"))

# Username is the Entra object ID of the managed identity
username = os.environ["REDIS_OBJECT_ID"]

client = redis.Redis(
    host=host,
    port=port,
    username=username,
    password=access_token,
    ssl=True,
    decode_responses=True,
)

client.set("health", "ok", ex=60)
print(client.get("health"))
```

Store `REDIS_OBJECT_ID` as a non-secret environment variable:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars REDIS_OBJECT_ID="$OBJECT_ID"
```

## Container Apps specifics

- Keep Redis host, port, and object ID in environment variables.
- Avoid access keys and connection strings when using managed identity.
- If using private networking, pair this setup with private endpoints and VNet integration.

## Verification steps

1. Confirm access policy assignment:

```bash
az redis access-policy-assignment list \
  --name "$REDIS_NAME" \
  --resource-group "$RG" \
  --output table
```

2. Confirm app logs show successful Redis `SET`/`GET`:

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --follow false
```

## See Also

- [Managed Identity](./managed-identity.md)
- [Private Endpoints](./networking-private-endpoint.md)
- [Azure Cache for Redis + Microsoft Entra auth](https://learn.microsoft.com/azure/azure-cache-for-redis/cache-azure-active-directory-for-authentication)
