---
content_sources:
  diagrams:
    - id: custom-domain-request-flow
      type: flowchart
      source: self-generated
      justification: Runtime custom-domain request path synthesized from documented DNS records, TLS termination, hostname certificate binding, managed ingress, revisions, and replicas; DNS lookup is kept separate from TCP and TLS transport.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
content_validation:
  status: verified
  last_reviewed: 2026-11-07
  reviewer: agent
  core_claims:
    - claim: Every custom domain must be associated with a TLS certificate, using either a free managed certificate or an existing certificate.
      source: https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates
      verified: true
    - claim: Apex domains use an A record and HTTP validation, while subdomains use a direct CNAME record and CNAME validation; both workflows use a TXT domain-verification record.
      source: https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates
      verified: true
    - claim: Container Apps HTTP ingress terminates TLS at the ingress point before routing the request to an app revision.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      verified: true
---
# Custom Domains and TLS

This runbook covers the operational steps for binding custom hostnames and TLS certificates to Azure Container Apps.

## Prerequisites

- External ingress enabled for the target app
- Control of the DNS zone for the hostname
- A certificate strategy chosen before production cutover

```bash
export RG="rg-aca-prod"
export APP_NAME="app-python-api-prod"
export HOSTNAME="api.contoso.com"
```

## When to Use

- When you need a customer-facing hostname instead of the default Azure domain
- When you need an operational runbook for certificate renewal or replacement
- When you need to verify DNS, SNI, and certificate binding together

## Procedure

1. Verify the app uses external ingress.
2. Add the hostname to the app.
3. Bind either a managed certificate or an uploaded certificate.
4. Validate DNS resolution and TLS negotiation.

The two main certificate paths are:

- **Managed certificate** for a lower-operations experience
- **Bring your own certificate** when you need your own CA, packaging, or domain support path

Microsoft Learn documents the current domain-type split: Container Apps supports apex domains and subdomains, uses **A record + HTTP validation** for apex domains, and **a direct CNAME + CNAME validation** for subdomains. Both managed-certificate and uploaded-certificate workflows also use the matching TXT ownership record: `asuid` for an apex domain or `asuid.<subdomain>` for a subdomain. With an environment private endpoint, an apex-domain A record resolves privately to the private endpoint IP while the ownership TXT record remains in public DNS.

<!-- diagram-id: custom-domain-request-flow -->
```mermaid
flowchart TD
    accTitle: Custom domain DNS, TCP, TLS, and app routing path
    accDescr: A client first resolves an apex A record or subdomain CNAME. It then opens TCP port 443, negotiates TLS by using the hostname and its SNI certificate binding, and sends the HTTPS request through managed ingress to an active revision and replica.

    CLIENT["Client"]
    DNS["Authoritative DNS<br/>A or direct CNAME"]

    subgraph ENV["Managed Container Apps environment"]
        direction TB
        ADDRESS["Destination address<br/>environment inbound IP<br/>or private endpoint IP"]
        INGRESS["Managed ingress proxy<br/>TLS and request routing"]
        CERT["Hostname binding<br/>SNI certificate"]
        REV_ACTIVE["Active revision<br/>immutable app version"]
        REPLICAS["Revision replicas<br/>running instances"]
    end

    CLIENT -.->|"1  DNS query"| DNS
    DNS -.->|"2  A or CNAME answer"| CLIENT
    ADDRESS -.->|"Ingress address"| INGRESS
    CLIENT ==>|"3  TCP 443 to destination<br/>4  TLS ClientHello with SNI"| INGRESS
    CERT -.->|"Certificate selection"| INGRESS
    INGRESS ==>|"5  Route request by traffic rule<br/>after TLS termination"| REV_ACTIVE
    REV_ACTIVE ==>|"6  Select ready replica"| REPLICAS

    LEGEND["Arrow key<br/>thick = client transport or runtime request path<br/>dotted = DNS or certificate-selection relationship"]
```

*Figure: DNS resolution, TCP establishment, TLS/SNI certificate selection, and application routing are separate stages. The runtime portion consumes the reviewed `ENV` → `INGRESS` → `REV_ACTIVE` → `REPLICAS` base path without presenting an IP address, DNS answer, or certificate selection as a transport hop.*

## Verification

Check the hostname binding on the app:

```bash
az containerapp hostname list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp hostname list` | Lists custom hostname bindings for the container app. |
| `--name` | Identifies the container app. |
| `--resource-group` | Identifies the resource group that contains the app. |
| `--output` | Formats the result as a table for operator review. |

Validate that the expected hostname serves TLS:

```bash
curl --head "https://$HOSTNAME"
openssl s_client -connect "$HOSTNAME:443" -servername "$HOSTNAME"
```

## Rollback / Troubleshooting

- If DNS validation fails, wait for propagation and re-check the exact record value.
- If TLS fails, verify the certificate is bound to the same hostname.
- If the app is internal-only, change ingress mode before troubleshooting certificates.

## See Also

- [Managed Certificates](managed-certificates.md)
- [Bring Your Own Certificates](byo-certificates.md)
- [Deployment Networking](../deployment/networking.md)

## Sources

- [Custom domains and managed certificates in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates)
- [Custom domains and certificates in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates)
