---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates
---
# Custom Domains and Certificates

Azure Container Apps supports custom hostnames and TLS certificates so you can serve ASP.NET Core applications on your own domain instead of the default `azurecontainerapps.io` address.

## Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Custom hostname validation and HTTPS request flow
    accDescr: DNS ownership and routing records permit Container Apps to validate and bind the hostname and managed certificate. After binding succeeds, a client resolves the hostname and sends an HTTPS request to managed ingress, which terminates TLS and routes the request to ASP.NET Core.
    DNS[Public DNS zone]
    TXT[TXT asuid record<br/>ownership verification]
    ROUTE[CNAME or apex A record<br/>traffic routing]
    VALIDATE[Container Apps<br/>hostname validation]
    BIND[Custom hostname +<br/>managed certificate binding]
    CLIENT[Client]
    INGRESS[Managed ingress<br/>TLS termination]
    APP[ASP.NET Core app]

    DNS --> TXT
    DNS --> ROUTE
    TXT -.->|"Proves domain ownership"| VALIDATE
    ROUTE -.->|"Resolves hostname to ingress"| VALIDATE
    VALIDATE -->|"Validation succeeds"| BIND
    BIND -.->|"Configures hostname and certificate"| INGRESS
    CLIENT ==>|"DNS query"| DNS
    DNS ==>|"Address or canonical name"| CLIENT
    CLIENT ==>|"HTTPS request with SNI"| INGRESS
    INGRESS ==>|"Routed request after TLS termination"| APP
    APP ==> INGRESS
    INGRESS ==>|"HTTPS response"| CLIENT
```

*Figure: DNS validation and certificate binding are control-plane prerequisites. Only after the hostname is bound does the runtime HTTPS request flow through managed ingress to the app.*

## Prerequisites

- Existing Container App: `$APP_NAME` in `$RG`
- Existing Container Apps environment: `$ACA_ENV_NAME`
- Public DNS zone you control for the target domain
- Azure CLI with the Container Apps extension

```bash
az extension add --name containerapp --upgrade
```

| Command / Parameter | Purpose |
|---|---|
| `az extension add` | For custom-domain configuration, installs or upgrades the Container Apps CLI extension used by this procedure. |
| `--name` | Selects the `containerapp` extension that provides hostname and certificate commands. |
| `--upgrade` | For custom-domain configuration, upgrades the Container Apps extension when an older release is installed. |

## Step 1: Get the app and environment values

```bash
export ENV_STATIC_IP=$(az containerapp env show \
  --name "$ACA_ENV_NAME" \
  --resource-group "$RG" \
  --query "properties.staticIp" \
  --output tsv)

export APP_FQDN=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv)

export CUSTOM_DOMAIN_VERIFICATION_ID=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.customDomainVerificationId" \
  --output tsv)
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp env show` | For custom-domain configuration, reads the Container Apps environment static IP used for the custom-domain DNS record. |
| `--name` | Selects environment `$ACA_ENV_NAME` for its static IP and app `$APP_NAME` for ingress and verification values. |
| `--output` | Returns each DNS input as unquoted `tsv` for assignment to a shell variable. |
| `--query` | For custom-domain configuration, extracts `properties.staticIp`, `properties.configuration.ingress.fqdn`, `properties.customDomainVerificationId` from the command response for the next operation. |
| `--resource-group` | Locates the Container Apps environment and app in `$RG`. |
| `az containerapp show` | Reads the ingress FQDN for the CNAME and the ownership token for the TXT record. |

## Step 2: Create DNS records

```bash
az network dns record-set cname set-record \
  --resource-group "$DNS_RG" \
  --zone-name "contoso.com" \
  --record-set-name "www" \
  --cname "$APP_FQDN"

az network dns record-set txt add-record \
  --resource-group "$DNS_RG" \
  --zone-name "contoso.com" \
  --record-set-name "asuid.www" \
  --value "$CUSTOM_DOMAIN_VERIFICATION_ID"
```

| Command / Parameter | Purpose |
|---|---|
| `az network dns record-set cname set-record` | For custom-domain configuration, points the custom hostname CNAME record at the Container App ingress FQDN. |
| `--cname` | For custom-domain configuration, sets the DNS CNAME target to Container App FQDN `$APP_FQDN`. |
| `--record-set-name` | For custom-domain configuration, updates DNS record set `www`, `asuid.www`. |
| `--resource-group` | For custom-domain configuration, limits the operations in this block to resource group `$DNS_RG`. |
| `--zone-name` | For custom-domain configuration, updates records in public DNS zone `contoso.com`. |
| `az network dns record-set txt add-record` | For custom-domain configuration, publishes the `asuid` TXT value that proves custom-domain ownership. |
| `--value` | For custom-domain configuration, publishes domain-verification value `$CUSTOM_DOMAIN_VERIFICATION_ID`. |

## Step 3: Add the hostname to the Container App

```bash
az containerapp hostname add \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --hostname "www.contoso.com"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp hostname add` | For custom-domain configuration, adds the verified custom hostname to the Container App. |
| `--hostname` | For custom-domain configuration, targets custom hostname `www.contoso.com` for validation or certificate binding. |
| `--name` | Adds the hostname to Container App `$APP_NAME`. |
| `--resource-group` | Finds the app receiving `www.contoso.com` in `$RG`. |

## Step 4: Bind a certificate

```bash
az containerapp hostname bind \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --hostname "www.contoso.com" \
  --environment "$ACA_ENV_NAME" \
  --validation-method CNAME
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp hostname bind` | For custom-domain configuration, binds the custom hostname to a managed TLS certificate. |
| `--environment` | Uses `$ACA_ENV_NAME` when creating and attaching the managed certificate. |
| `--hostname` | For custom-domain configuration, targets custom hostname `www.contoso.com` for validation or certificate binding. |
| `--name` | Binds the managed certificate to `$APP_NAME`. |
| `--resource-group` | Locates the hostname-bearing app in `$RG`. |
| `--validation-method` | For custom-domain configuration, validates the managed certificate with method `CNAME`. |

## Step 5: Configure ASP.NET Core for forwarded headers

Container Apps terminates TLS before traffic reaches ASP.NET Core. Honor forwarded headers so redirects, links, and scheme detection stay correct.

```csharp
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto | ForwardedHeaders.XForwardedHost
});

app.MapGet("/debug/host", (HttpContext context) => Results.Ok(new
{
    scheme = context.Request.Scheme,
    host = context.Request.Host.Value,
    forwardedProto = context.Request.Headers["X-Forwarded-Proto"].ToString()
}));
```

## Verification

```bash
az containerapp hostname list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table

az containerapp env certificate list \
  --name "$ACA_ENV_NAME" \
  --resource-group "$RG" \
  --output table

curl --verbose https://www.contoso.com/
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp hostname list` | For custom-domain configuration, lists the Container App hostname binding to verify its certificate state. |
| `--name` | Selects `$APP_NAME` for hostname verification and `$ACA_ENV_NAME` for certificate inventory. |
| `--output` | Displays hostnames and certificates in tables for visual confirmation. |
| `--resource-group` | Looks up both verification targets in `$RG`. |
| `az containerapp env certificate list` | For custom-domain configuration, lists environment certificates to verify the managed certificate resource. |

## See Also

- [Easy Auth](easy-auth.md)
- [Networking](../../../platform/networking/vnet-integration.md)
- [Private Endpoints](../../../platform/networking/private-endpoints.md)

## Sources

- [Custom domains and managed certificates in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates)
- [Custom domains and certificates in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates)
