---
content_sources:
  diagrams:
    - id: use-container-apps-built-in-authentication-easy
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication-entra
---
# Recipe: Easy Auth in Node.js Apps on Azure Container Apps

Use Container Apps built-in authentication (Easy Auth) and parse the authenticated principal inside Express middleware.

<!-- diagram-id: use-container-apps-built-in-authentication-easy -->
```mermaid
flowchart TD
    accTitle: Easy Auth server-directed sign-in for an Express app
    accDescr: A browser reaches an external ingress-enabled app. The per-replica authentication module redirects the browser to the configured identity provider, handles the callback and session, then forwards the authenticated request with identity headers to Express.
    BROWSER1[Browser<br/>initial request]
    INGRESS1[External ingress]
    AUTH1[Authentication module<br/>per replica]
    IDP[Microsoft Entra ID]
    BROWSER2[Browser<br/>follows sign-in redirect]
    BROWSER3[Browser<br/>returns provider callback]
    INGRESS2[External ingress<br/>callback route]
    AUTH2[Authentication module<br/>validate callback]
    APP[Express app]
    SESSION[Container Apps session cookie]
    BROWSER4[Browser<br/>authenticated request]
    INGRESS3[External ingress]
    AUTH3[Authentication module<br/>session validation]
    RESPONSE[Browser receives<br/>HTTPS response]

    BROWSER1 ==>|"HTTPS GET /protected"| INGRESS1
    INGRESS1 ==>|"Route request"| AUTH1
    AUTH1 ==>|"Return sign-in redirect"| BROWSER2
    BROWSER2 ==>|"Sign in and consent"| IDP
    IDP ==>|"Redirect with provider response"| BROWSER3
    BROWSER3 ==>|"GET /.auth/login/&lt;provider&gt;/callback"| INGRESS2
    INGRESS2 ==>|"Route callback"| AUTH2
    AUTH2 ==>|"Validate provider response"| IDP
    IDP ==>|"Identity and claims"| AUTH2
    AUTH2 ==>|"Set session cookie"| SESSION
    SESSION ==>|"Cookie stored by browser"| BROWSER4
    BROWSER4 ==>|"GET /protected + cookie"| INGRESS3
    INGRESS3 ==>|"Route authenticated request"| AUTH3
    AUTH3 ==>|"Request + X-MS-* headers"| APP
    APP ==>|"Application response"| AUTH3
    AUTH3 ==>|"Return response"| INGRESS3
    INGRESS3 ==>|"HTTPS response"| RESPONSE
```

*Figure: Easy Auth authenticates the caller before the request reaches Express and supplies identity headers. Application code still enforces role, tenant, and resource authorization.*

## Prerequisites

- Container App with ingress enabled (`$APP_NAME`, `$RG`)
- Identity provider registration (for example Microsoft Entra ID)
- Azure CLI with Container Apps extension

```bash
az extension add --name containerapp --upgrade
```

| Command | Why it is used |
|---|---|
| `az extension add ...` | Installs or updates the Container Apps Azure CLI extension. |

## Enable Easy Auth

```bash
az containerapp auth update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --enabled true \
  --runtime-version "~1" \
  --unauthenticated-client-action RedirectToLoginPage \
  --redirect-provider azureactivedirectory \
  --require-https true
```

| Command | Why it is used |
|---|---|
| `az containerapp auth update` | Enables server-directed Microsoft Entra sign-in for `$APP_NAME`. |
| `--name` | Selects the Express Container App `$APP_NAME`. |
| `--resource-group` | Locates the app in `$RG`. |
| `--enabled` | Turns the Container Apps authentication module on. |
| `--runtime-version` | Uses authentication runtime version `~1`. |
| `--unauthenticated-client-action` | Redirects unauthenticated browser requests to sign-in. |
| `--redirect-provider` | Chooses `azureactivedirectory` for that redirect. |
| `--require-https` | Requires HTTPS for the authentication flow. |

## Express middleware for principal parsing

```javascript
const express = require("express");

const app = express();

function parsePrincipal(headerValue) {
  const json = Buffer.from(headerValue, "base64").toString("utf8");
  return JSON.parse(json);
}

app.use((req, _res, next) => {
  const header = req.header("x-ms-client-principal");
  if (!header) {
    req.userContext = null;
    return next();
  }

  const principal = parsePrincipal(header);
  const claims = Object.fromEntries((principal.claims || []).map((c) => [c.typ, c.val]));
  req.userContext = {
    userId: principal.userId,
    identityProvider: principal.identityProvider,
    claims,
  };
  next();
});

app.get("/me", (req, res) => {
  if (!req.userContext) {
    return res.status(401).json({ error: "unauthenticated" });
  }
  return res.status(200).json(req.userContext);
});
```

## Authorization pattern

- Let Easy Auth handle identity verification and token/session mechanics.
- Enforce route-level authorization using claim values such as `roles` or `groups`.
- Return `403` when identity exists but required claims are missing.

## Advanced Topics

- Use separate app registrations per environment to avoid cross-environment trust issues.
- Add custom authorization middleware for tenant boundary checks.
- For service-to-service access, prefer managed identity over user session tokens.

## See Also

- [Managed Identity](managed-identity.md)
- [Key Vault Reference](key-vault-reference.md)
- [Identity and Secrets](../../../platform/identity-and-secrets/managed-identity.md)

## Sources

- [Authentication in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [Configure authentication providers in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [Configure Microsoft Entra authentication](https://learn.microsoft.com/en-us/azure/container-apps/authentication-entra)
