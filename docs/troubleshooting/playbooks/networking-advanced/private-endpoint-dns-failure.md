---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
  diagrams:
    - id: private-endpoint-dns-failure-flow
      type: flowchart
      source: self-generated
      justification: Diagnostic decision flow synthesized from the documented service-specific private DNS zone, VNet link, record, and private endpoint requirements.
      based_on:
        - https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
content_validation:
  status: verified
  last_reviewed: 2026-07-18
  reviewer: ai-agent
  core_claims:
    - claim: Private endpoint connectivity depends on correct private DNS zone configuration for the target service.
      source: https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
      verified: true
    - claim: Using an existing virtual network allows Azure Container Apps to access resources behind private endpoints in the virtual network.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
---
# Private Endpoint DNS Failure

<!-- diagram-id: private-endpoint-dns-failure-flow -->
```mermaid
flowchart TD
    accTitle: Diagnose private endpoint DNS resolution
    accDescr: Check the target service's documented private DNS zone, the Container Apps VNet link or forwarding path, and the endpoint record before testing transport.

    APP[Container app replica]
    QUERY[Query the service public FQDN]
    ZONE{Correct service-specific private DNS zone exists?}
    LINK{Container Apps VNet can resolve the zone?}
    RECORD{Record resolves to the intended private endpoint IP?}
    TRANSPORT{Private endpoint transport succeeds?}
    ZONE_FIX[Create or correct the documented private DNS zone]
    LINK_FIX[Add the VNet link or correct custom DNS forwarding]
    RECORD_FIX[Correct the private endpoint record or zone group]
    PATH_FIX[Inspect endpoint connection, NSG, and route]
    SUCCESS[Private dependency call can proceed]

    APP ==>|DNS query| QUERY
    QUERY --> ZONE
    ZONE -->|No| ZONE_FIX
    ZONE -->|Yes| LINK
    LINK -->|No| LINK_FIX
    LINK -->|Yes| RECORD
    RECORD -->|No| RECORD_FIX
    RECORD -->|Yes| TRANSPORT
    TRANSPORT -->|No| PATH_FIX
    TRANSPORT -->|Yes| SUCCESS

    LEGEND["Arrow key<br/>thick = DNS transport<br/>solid = diagnostic progression"]
```

*Figure: Correct private DNS is necessary but does not by itself prove the private endpoint transport path.*

## Symptom

- Container Apps can reach public internet targets, but a dependency behind a private endpoint fails with `NXDOMAIN`, `Name or service not known`, or timeout.
- A private endpoint exists, yet the app still resolves the public FQDN or nothing at all.
- The failure often appears right after a private endpoint or custom DNS rollout.

Typical evidence:

- [Observed] `<account>.blob.core.windows.net` or `<registry>.azurecr.io` does not resolve to a private IP from the app context.
- [Observed] A private DNS zone exists, but the Container Apps VNet is not linked.
- [Correlated] The incident starts after DNS zone, VNet link, or DNS forwarder changes.

## Possible Causes

| Cause | Why it breaks |
|---|---|
| Private DNS zone missing | The public name never resolves to the private endpoint IP. |
| VNet link missing | The zone exists, but the Container Apps subnet cannot use it. |
| Private endpoint DNS records are stale or incomplete | The hostname resolves, but to the wrong target. |
| Custom DNS server does not forward private zones correctly | Resolution fails even though Azure-side objects exist. |

## Diagnosis Steps

1. Inventory the private endpoint and the related private DNS zones.
2. Confirm the Container Apps VNet is linked to the right zone.
3. Test name resolution from the running app context.

```bash
az network private-endpoint show \
  --name "pe-storage" \
  --resource-group "$RG" \
  --output json

az network private-dns link vnet list \
  --resource-group "$RG" \
  --zone-name "privatelink.blob.core.windows.net" \
  --output table

az containerapp exec \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --command "python -c 'import socket; print(socket.getaddrinfo(\"mystorage.blob.core.windows.net\", 443))'"
```

| Command/Parameter | Purpose |
|---|---|
| `az network private-endpoint show` | Reads the selected network private endpoint so the operator can evaluate resource configuration record. |
| `--name` (`az network private-endpoint show`) | Inspects `pe-storage`, the private endpoint expected to serve the storage account. |
| `--resource-group` (`az network private-endpoint show`) | Locates `pe-storage` in `$RG` before checking its connection and subnet state. |
| `--output` (`az network private-endpoint show`) | Returns the full endpoint record as JSON for connection and NIC inspection. |
| `az network private-dns link vnet list` | Enumerates private DNS link records to assemble private-zone link inventory for comparison. |
| `--resource-group` (`az network private-dns link vnet list`) | Reads VNet links for the storage private zone in `$RG`. |
| `--zone-name` (`az network private-dns link vnet list`) | Chooses the private DNS zone evaluated by `privatelink.blob.core.windows.net`, anchoring private-zone link inventory to the exact value used by this operation. |
| `--output` (`az network private-dns link vnet list`) | Displays link state as a table so an absent or disconnected VNet is visible. |
| `az containerapp exec` | Resolves the storage hostname from inside a running replica, using the same DNS path as the application. |
| `--name` (`az containerapp exec`) | Runs the lookup in `$APP_NAME`. |
| `--resource-group` (`az containerapp exec`) | Connects to the app deployed in `$RG`. |
| `--command` (`az containerapp exec`) | Runs the quoted probe inside the workload to observe diagnosis steps from the replica network namespace. |


Diagnostic interpretation:

- [Observed] Public IP resolution or no resolution at all points to DNS, not the target service.
- [Observed] Correct private IP resolution with continued timeouts shifts suspicion to NSG or route path.
- [Strongly Suggested] If one private service fails and another private service works, compare their zone names and link scopes first.

## Resolution

1. Create or correct the service-specific private DNS zone.
2. Link the zone to the Container Apps VNet.
3. Ensure the expected A records exist for the private endpoint.
4. If custom DNS is in use, forward the relevant `privatelink` zones correctly.

```bash
az network private-dns zone create \
  --resource-group "$RG" \
  --name "privatelink.blob.core.windows.net"

az network private-dns link vnet create \
  --resource-group "$RG" \
  --zone-name "privatelink.blob.core.windows.net" \
  --name "link-aca-vnet" \
  --virtual-network "/subscriptions/<subscription-id>/resourceGroups/$RG/providers/Microsoft.Network/virtualNetworks/vnet-myapp" \
  --registration-enabled false
```

| Command/Parameter | Purpose |
|---|---|
| `az network private-dns zone create` | Creates the network private dns zone that implements the documented correction and returns its provisioning result. |
| `--resource-group` (`az network private-dns zone create`) | Creates the storage private zone in `$RG`. |
| `--name` (`az network private-dns zone create`) | Names the authoritative zone `privatelink.blob.core.windows.net`. |
| `az network private-dns link vnet create` | Creates the private DNS link that implements the documented correction and returns its provisioning result. |
| `--resource-group` (`az network private-dns link vnet create`) | Adds the VNet link to the zone held in `$RG`. |
| `--zone-name` (`az network private-dns link vnet create`) | Chooses the private DNS zone evaluated by `privatelink.blob.core.windows.net`, anchoring resource creation result to the exact value used by this operation. |
| `--name` (`az network private-dns link vnet create`) | Creates the link named `link-aca-vnet`. |
| `--virtual-network` (`az network private-dns link vnet create`) | Links the zone to the full ARM ID of `vnet-myapp`, where Container Apps DNS queries originate. |
| `--registration-enabled` (`az network private-dns link vnet create`) | Disables automatic VM record registration because this link is for resolving private endpoint records. |


## Prevention

- Treat private endpoint creation and DNS zone linkage as one deployment unit.
- Validate private name resolution from the same VNet path as the app.
- Document required `privatelink` zones for every private dependency.
- Re-test DNS whenever hub-spoke links, custom resolvers, or private endpoint records change.

## See Also

- [Private Endpoint DNS Failure Lab](../../lab-guides/private-endpoint-dns-failure.md)
- [Private Endpoints](../../../platform/networking/private-endpoints.md)
- [Internal DNS and Private Endpoint Failure](../ingress-and-networking/internal-dns-and-private-endpoint-failure.md)
- [Deployment Networking Operations](../../../operations/deployment/networking.md)

## Sources

- [Azure private endpoint DNS configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Networking in Azure Container Apps environment](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [What is Azure Private DNS?](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)
