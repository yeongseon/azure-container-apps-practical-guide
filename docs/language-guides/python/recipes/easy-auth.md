---
content_sources:
  diagrams:
    - id: use-container-apps-authentication-easy-auth
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication
---
# Recipe: Easy Auth (Built-in Authentication) for Python Apps

Use Container Apps authentication (Easy Auth) to offload sign-in and token handling, then apply app-level authorization in Flask.

<!-- diagram-id: use-container-apps-authentication-easy-auth -->
```mermaid
flowchart TD
    accTitle: Authenticate users before requests reach Flask
    accDescr: Built-in authentication intercepts the request outside the application code. It redirects unauthenticated users to the configured identity provider, validates the returned identity, and forwards authenticated requests with identity headers for app-level authorization.

    CLIENT[Client]
    AUTH[Container Apps<br/>built-in authentication]
    IDP[Configured identity provider]
    APP[Python app]
    AUTHORIZE[Check required role or scope]
    ALLOW[Serve protected route]
    DENY[Return 403]

    CLIENT ==>|Request| AUTH
    AUTH ==>|Sign-in redirect| IDP
    IDP ==>|Authentication response| AUTH
    AUTH ==>|Request with identity headers| APP
    APP --> AUTHORIZE
    AUTHORIZE -->|Present| ALLOW
    AUTHORIZE -->|Missing| DENY
```

Thick arrows show browser and application requests. The decision remains in Flask because built-in authentication establishes identity but does not replace app-specific authorization.

## Prerequisites

- Container App with ingress enabled
- An identity provider app registration (for example Microsoft Entra ID)
- Azure CLI with Container Apps extension

```bash
az extension add --name containerapp --upgrade
```

| Command | Why it is used |
|---|---|
| `az extension add` | Installs or upgrades the Azure CLI extension required by this procedure. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--upgrade` | Updates an existing extension so current command flags are available. |



## Supported identity providers

Container Apps authentication supports providers such as:

- Microsoft Entra ID
- Google
- GitHub
- X (Twitter)
- Apple
- OpenID Connect-compatible providers

## Enable Easy Auth via CLI

```bash
az containerapp auth update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --enabled true \
  --runtime-version "~1" \
  --unauthenticated-client-action RedirectToLoginPage
```

| Command | Why it is used |
|---|---|
| `az containerapp auth update` | Enables and configures built-in authentication for the Container App. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--enabled` | Turns on the built-in authentication middleware. |
| `--runtime-version` | Selects the built-in authentication middleware runtime version. |
| `--unauthenticated-client-action` | Redirects unauthenticated browser requests to sign-in. |



Provider configuration can then be added with provider-specific settings:

```bash
az containerapp auth microsoft update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --client-id "$ENTRA_CLIENT_ID" \
  --client-secret-name "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET" \
  --tenant-id "$TENANT_ID"
```

| Command | Why it is used |
|---|---|
| `az containerapp auth microsoft update` | Configures Microsoft Entra ID as the app's built-in authentication provider. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--client-id` | Sets the app registration client ID used for Microsoft sign-in. |
| `--client-secret-name` | References the Container Apps secret that stores the provider client secret. |
| `--tenant-id` | Restricts Microsoft sign-in to the intended Entra tenant. |



## Enable Easy Auth via Bicep

```bicep
resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  properties: {
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
      }
    }
  }
}

resource authConfig 'Microsoft.App/containerApps/authConfigs@2023-05-01' = {
  name: 'current'
  parent: app
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      unauthenticatedClientAction: 'RedirectToLoginPage'
    }
  }
}
```

## Access auth claims in Python (`X-MS-CLIENT-PRINCIPAL`)

```python
import base64
import json
from flask import Flask, request, g, jsonify

app = Flask(__name__)

def decode_client_principal(header_value: str) -> dict:
    decoded = base64.b64decode(header_value)
    return json.loads(decoded)

@app.before_request
def load_user_context():
    principal_header = request.headers.get("X-MS-CLIENT-PRINCIPAL")
    if principal_header:
        principal = decode_client_principal(principal_header)
        g.user_id = principal.get("userId")
        g.identity_provider = principal.get("identityProvider")
        g.claims = {claim["typ"]: claim["val"] for claim in principal.get("claims", [])}
    else:
        g.user_id = None
        g.identity_provider = None
        g.claims = {}

@app.get("/me")
def me():
    if not g.user_id:
        return jsonify(error="unauthenticated"), 401
    return jsonify(userId=g.user_id, identityProvider=g.identity_provider, claims=g.claims), 200
```

## Token validation patterns

- Rely on Easy Auth for primary token validation and session management.
- Enforce fine-grained authorization in app code (roles, groups, scopes).
- Restrict privileged routes with explicit checks on claim values.

```python
from functools import wraps
from flask import g, jsonify

def require_role(required_role: str):
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            roles = g.claims.get("roles", "")
            role_values = roles.split(",") if roles else []
            if required_role not in role_values:
                return jsonify(error="forbidden"), 403
            return fn(*args, **kwargs)
        return wrapper
    return decorator
```

## Combining Easy Auth with app-level authorization

1. Easy Auth verifies identity and injects principal headers.
2. Flask middleware extracts identity and claims.
3. Route decorators enforce domain authorization (for example, `admin`, `reader`, tenant boundary checks).

## Advanced Topics

- Use separate app registrations for production and non-production environments.
- Add custom claims transformation in an API gateway when needed.
- For service-to-service calls, use managed identity and OAuth client credential flows instead of user sessions.

## See Also

- [Managed Identity](managed-identity.md)
- [Key Vault Reference](key-vault-reference.md)
- [Identity and Secrets](../../../platform/identity-and-secrets/managed-identity.md)
- [Microsoft Learn: Authentication in Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/authentication)

## Sources

- [Microsoft Learn source 1](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [Microsoft Learn source 2](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
