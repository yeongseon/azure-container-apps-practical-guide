---
content_sources:
  diagrams:
    - id: use-easy-auth-to-handle-identity
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication-entra
---
# Recipe: Easy Auth in .NET Apps on Azure Container Apps

Use Easy Auth to handle identity at the edge, then map claims inside ASP.NET Core middleware.

<!-- diagram-id: use-easy-auth-to-handle-identity -->
```mermaid
flowchart TD
    accTitle: Easy Auth server-directed sign-in for an ASP.NET Core app
    accDescr: A browser reaches an external ingress-enabled app. The per-replica authentication module redirects the browser to the configured identity provider, handles the callback and session, then forwards the authenticated request with identity headers to ASP.NET Core.
    B[Browser]
    INGRESS[External ingress]
    AUTH[Authentication module<br/>per replica]
    IDP[Microsoft Entra ID]
    APP[ASP.NET Core app]
    REDIRECT[Sign-in redirect]
    CALLBACK[Authentication callback]
    SESSION[Container Apps session cookie]

    B ==>|"HTTPS GET /protected"| INGRESS
    INGRESS ==>|"Route request"| AUTH
    AUTH ==>|"Return redirect"| REDIRECT
    REDIRECT ==>|"Browser follows redirect"| B
    B ==>|"Sign in and consent"| IDP
    IDP ==>|"Redirect with provider response"| CALLBACK
    CALLBACK ==>|"HTTPS callback"| INGRESS
    INGRESS ==>|"Route callback"| AUTH
    AUTH ==>|"Validate provider response"| IDP
    IDP ==>|"Identity and claims"| AUTH
    AUTH ==>|"Set cookie"| SESSION
    SESSION ==>|"Session cookie"| B
    B ==>|"HTTPS GET /protected + cookie"| INGRESS
    INGRESS ==>|"Route authenticated request"| AUTH
    AUTH ==>|"Request + X-MS-* identity headers"| APP
    APP ==>|"Application response"| AUTH
    AUTH ==>|"Return response"| INGRESS
    INGRESS ==>|"HTTPS response"| B
```

*Figure: Easy Auth authenticates the caller before the request reaches ASP.NET Core and supplies identity headers. Application code still enforces role, tenant, and resource authorization.*

## Prerequisites

- Container App (`$APP_NAME`) with ingress enabled
- Resource group (`$RG`) and identity provider registration
- Azure CLI with Container Apps extension

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

| Command / Parameter | Purpose |
|---|---|
| `az containerapp auth update` | Configures Easy Auth for the selected Container App. |
| `--enabled` | Turns on the authentication feature for this app. |
| `--name` | Selects the app, job, deployment, registry, identity, or service used by this command. |
| `--redirect-provider` | Chooses Microsoft Entra ID for unauthenticated redirects. |
| `--require-https` | Requires HTTPS for authentication responses and callbacks. |
| `--resource-group` | Selects the resource group containing the resources in this step. |
| `--runtime-version` | Selects the Easy Auth runtime version used by the app. |
| `--unauthenticated-client-action` | Redirects callers without an authenticated session. |

## ASP.NET Core middleware for claims mapping

```csharp
using System.Security.Claims;
using System.Text;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.Use(async (context, next) =>
{
    if (context.Request.Headers.TryGetValue("x-ms-client-principal", out var headerValue))
    {
        var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(headerValue!));
        using var doc = JsonDocument.Parse(decoded);
        var claims = new List<Claim>();
        foreach (var claim in doc.RootElement.GetProperty("claims").EnumerateArray())
        {
            claims.Add(new Claim(claim.GetProperty("typ").GetString()!, claim.GetProperty("val").GetString()!));
        }

        var identity = new ClaimsIdentity(claims, "EasyAuth");
        context.User = new ClaimsPrincipal(identity);
    }

    await next();
});

app.MapGet("/me", (HttpContext context) =>
{
    if (context.User.Identity?.IsAuthenticated != true)
    {
        return Results.Unauthorized();
    }
    return Results.Ok(context.User.Claims.Select(c => new { c.Type, c.Value }));
});

app.Run();
```

## Advanced Topics

- Normalize external claim names to internal policy names in one middleware stage.
- Use `RequireAuthorization` policies for role and tenant checks.
- Keep service-to-service authorization on managed identity, not user cookies.

## See Also

- [Managed Identity](managed-identity.md)
- [Key Vault Reference](key-vault-reference.md)
- [Identity and Secrets](../../../platform/identity-and-secrets/managed-identity.md)

## Sources

- [Authentication in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [Configure Microsoft Entra ID authentication](https://learn.microsoft.com/en-us/azure/container-apps/authentication-entra)
