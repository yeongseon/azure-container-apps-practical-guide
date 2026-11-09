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

Azure Container Apps supports custom hostnames and TLS certificates so you can serve Express applications on your own domain instead of the default `azurecontainerapps.io` address.

## Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Custom hostname validation and HTTPS request flow
    accDescr: DNS ownership and routing records permit Container Apps to validate and bind the hostname and managed certificate. After binding succeeds, a client resolves the hostname and sends an HTTPS request to managed ingress, which terminates TLS and routes the request to Express.
    DNS[Public DNS zone]
    TXT[TXT asuid record<br/>ownership verification]
    ROUTE[CNAME or apex A record<br/>traffic routing]
    VALIDATE[Container Apps<br/>hostname validation]
    BIND[Custom hostname +<br/>managed certificate binding]
    CLIENT[Client]
    INGRESS[Managed ingress<br/>TLS termination]
    APP[Express app]

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
    APP ==>|"Application response"| INGRESS
    INGRESS ==>|"HTTPS response"| CLIENT
```

*Figure: DNS validation and certificate binding are control-plane prerequisites. Only after the hostname is bound does the runtime HTTPS request flow through managed ingress to Express.*

## Prerequisites

- Existing Container App: `$APP_NAME` in `$RG`
- Existing Container Apps environment: `$ACA_ENV_NAME`
- Public DNS zone you control for the target domain
- Azure CLI with the Container Apps extension

```bash
az extension add --name containerapp --upgrade
```

| Command | Why it is used |
|---|---|
| `az extension add ...` | Installs or updates the Container Apps Azure CLI extension. |

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

| Command | Purpose |
|---|---|
| `export ENV_STATIC_IP=$(az containerapp env show --name "$ACA_ENV_NAME" --resource-group "$RG" --query "properties.staticIp" --output tsv)` | Captures the environment static IP used by the apex-domain `A` record for a custom-domain binding. |
| `export APP_FQDN=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress.fqdn" --output tsv)` | Captures the app's current ingress hostname so you can create the matching `CNAME` or verify the default endpoint before cutover. |
| `export CUSTOM_DOMAIN_VERIFICATION_ID=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.customDomainVerificationId" --output tsv)` | Extracts the verification token that must be published as the `asuid` record before Container Apps will accept the custom hostname. |

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

| Command | Why it is used |
|---|---|
| `az network dns record-set ...` | Creates or inspects networking resources such as VNets, DNS zones, routes, or private endpoints. |

For apex domains, point an `A` record to `$ENV_STATIC_IP` instead of using a `CNAME`.

## Step 3: Add the hostname to the Container App

```bash
az containerapp hostname add \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --hostname "www.contoso.com"
```

| Command | Why it is used |
|---|---|
| `az containerapp hostname add ...` | Manages custom hostname bindings for ingress. |

## Step 4: Bind a certificate

Use a managed certificate when public DNS validation is available:

```bash
az containerapp hostname bind \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --hostname "www.contoso.com" \
  --environment "$ACA_ENV_NAME" \
  --validation-method CNAME
```

| Command | Why it is used |
|---|---|
| `az containerapp hostname bind ...` | Manages custom hostname bindings for ingress. |

Use a bring-your-own certificate when you already manage certificate lifecycle outside Container Apps:

```bash
az containerapp env certificate upload \
  --name "$ACA_ENV_NAME" \
  --resource-group "$RG" \
  --certificate-file "./www-contoso-com.pfx" \
  --password "<pfx-password>"

az containerapp hostname bind \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --hostname "www.contoso.com" \
  --environment "$ACA_ENV_NAME" \
  --certificate "www-contoso-com"
```

| Command | Why it is used |
|---|---|
| `az containerapp env certificate ...` | Manages certificates bound to Container Apps environment or hostnames. |

## Step 5: Configure Express for forwarded headers

Container Apps terminates TLS before traffic reaches Express. Trust the upstream proxy so Express generates the correct scheme and host information.

```javascript
const express = require("express");

const app = express();
app.set("trust proxy", true);

app.get("/debug/host", (req, res) => {
  res.json({
    protocol: req.protocol,
    host: req.get("host"),
    forwardedProto: req.get("x-forwarded-proto"),
  });
});
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

| Command | Why it is used |
|---|---|
| `az containerapp hostname list ...` | Manages custom hostname bindings for ingress. |

## See Also

- [Easy Auth](easy-auth.md)
- [Networking](../../../platform/networking/vnet-integration.md)
- [Private Endpoints](../../../platform/networking/private-endpoints.md)

## Sources

- [Custom domains and managed certificates in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates)
- [Custom domain names and certificates in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates)
