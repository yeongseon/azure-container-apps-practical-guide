---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/networking
  diagrams:
    - id: egress-ip-change-flow
      type: flowchart
      source: self-generated
      justification: Diagnostic decision flow synthesized from the documented Container Apps outbound networking and workload profiles NAT Gateway behavior.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
content_validation:
  status: verified
  last_reviewed: 2026-07-18
  reviewer: ai-agent
  core_claims:
    - claim: Using a NAT Gateway or other outbound proxy for outbound traffic from a Container Apps environment is supported only in a workload profiles environment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Workload profiles environments support user-defined routes and egress through NAT Gateway.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
---
# Egress IP Change

<!-- diagram-id: egress-ip-change-flow -->
```mermaid
flowchart TD
    accTitle: Diagnose an outbound source IP change
    accDescr: Measure the source IP from the running app, determine whether a customer-controlled NAT or firewall path exists, and compare the result with the downstream allowlist.

    FAILURE[Downstream service rejects or times out]
    OBSERVE[Measure public source IP from a running replica]
    CONTROLLED{Workload profiles environment uses NAT Gateway or controlled firewall egress?}
    EXPECTED[Read the customer-owned public IP configuration]
    DEFAULT[Review the environment's current outbound addresses and recent network changes]
    MATCH{Observed source is allowed downstream?}
    UPDATE[Update the downstream allowlist]
    DESIGN[Add a supported customer-controlled egress design if stable identity is required]
    RETEST[Retest from the running replica]

    FAILURE --> OBSERVE
    OBSERVE --> CONTROLLED
    CONTROLLED -->|Yes| EXPECTED
    CONTROLLED -->|No| DEFAULT
    EXPECTED --> MATCH
    DEFAULT --> MATCH
    MATCH -->|No| UPDATE
    MATCH -->|Yes| RETEST
    UPDATE --> RETEST
    DEFAULT --> DESIGN
    DESIGN --> RETEST

    LEGEND["Arrow key<br/>solid = diagnostic progression"]
```

*Figure: Measure the actual egress path before changing an allowlist; stable outbound identity requires a supported customer-controlled design.*

## Symptom

- A downstream firewall or partner allow-list starts rejecting traffic after environment recreation, subnet migration, or egress-path changes.
- The application remains healthy, but outbound calls fail with `403`, timeout, or connection reset from the remote side.
- The remote team reports a new source IP even though the application code did not change.

Common indicators:

- [Observed] Rejections begin immediately after environment recreation or network cutover.
- [Observed] Public egress observed from a running replica differs from the previously allow-listed address.
- [Inferred] The app relied on platform-default outbound identity instead of a dedicated egress design.

## Possible Causes

| Cause | Why it breaks |
|---|---|
| Environment recreated without updating downstream allow-lists | The remote system still trusts the previous source IP. |
| NAT Gateway was never attached | Outbound identity is not governed by a customer-managed static egress design. |
| Route or subnet changed | Traffic now leaves through a different egress path. |
| Firewall policy updated out of sequence | The new path is valid, but the downstream side still trusts the old source. |

## Diagnosis Steps

1. Measure the current public egress observed from a running replica.
2. Inspect the subnet for NAT Gateway and route table associations.
3. Compare the measured IP with the downstream allow-list currently in use.

```bash
az containerapp exec \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --command "sh -c 'curl --silent https://api.ipify.org && printf \"\\n\"'"

az network vnet subnet show \
  --name "snet-aca" \
  --vnet-name "vnet-myapp" \
  --resource-group "$RG" \
  --query "{natGateway:natGateway.id, routeTable:routeTable.id, addressPrefix:addressPrefix}" \
  --output json
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp exec` | Measures the public IP seen by an external service from within the app replica. |
| `--name` (`az containerapp exec`) | Runs the egress measurement in `$APP_NAME`. |
| `--resource-group` (`az containerapp exec`) | Connects to the app hosted in `$RG`. |
| `--command` (`az containerapp exec`) | Runs `curl --silent https://api.ipify.org` inside the app and prints a newline after the measured public IP. |
| `az network vnet subnet show` | Returns the subnet's NAT gateway and route-table associations to explain which component controls outbound addressing. |
| `--name` (`az network vnet subnet show`) | Inspects `snet-aca`, the environment subnet whose outbound identity may have changed. |
| `--vnet-name` (`az network vnet subnet show`) | Looks up the Container Apps infrastructure subnet within `vnet-myapp`. |
| `--resource-group` (`az network vnet subnet show`) | Finds `vnet-myapp` and its subnet in `$RG`. |
| `--query` (`az network vnet subnet show`) | Summarizes the subnet's NAT gateway, route table, and address prefix to identify which component can change outbound addressing. |
| `--output` (`az network vnet subnet show`) | Returns NAT, route-table, and prefix fields as JSON for the egress-path comparison. |


Interpretation:

- [Observed] If the measured IP changed and the dependency allow-list did not, the outage is explained.
- [Observed] If the subnet has no NAT Gateway, expect egress identity to follow the current network design rather than a documented customer-owned static contract.
- [Strongly Suggested] If only partner-protected destinations fail while general internet calls succeed, allow-list drift is the highest-probability root cause.

## Resolution

1. Update the downstream allow-list to include the currently observed egress IP or the NAT Gateway public IP.
2. If a stable outbound identity is required, attach a NAT Gateway to the environment subnet in a workload profiles environment.
3. Re-test the dependency from the running replica after the allow-list or NAT change.

```bash
az network nat gateway create \
  --name "nat-aca" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --public-ip-addresses "pip-aca-egress"

az network vnet subnet update \
  --name "snet-aca" \
  --vnet-name "vnet-myapp" \
  --resource-group "$RG" \
  --nat-gateway "nat-aca"
```

| Command/Parameter | Purpose |
|---|---|
| `az network nat gateway create` | Provisions the NAT gateway that will provide a stable public egress address for the subnet. |
| `--name` (`az network nat gateway create`) | Creates the stable egress resource `nat-aca`. |
| `--resource-group` (`az network nat gateway create`) | Places the NAT gateway in `$RG` with the app network. |
| `--location` (`az network nat gateway create`) | Deploys the gateway in `$LOCATION`, matching the VNet region. |
| `--public-ip-addresses` (`az network nat gateway create`) | Attaches `pip-aca-egress`, the public IP downstream systems should allow-list. |
| `az network vnet subnet update` | Changes the selected subnet configuration to apply the remediation established by configuration mutation. |
| `--name` (`az network vnet subnet update`) | Updates `snet-aca`, the Container Apps environment subnet. |
| `--vnet-name` (`az network vnet subnet update`) | Locates the delegated subnet in `vnet-myapp` before attaching the new NAT gateway. |
| `--resource-group` (`az network vnet subnet update`) | Locates `vnet-myapp` in `$RG` for the subnet change. |
| `--nat-gateway` (`az network vnet subnet update`) | Associates `nat-aca` so replicas use its stable public IP for outbound connections. |


## Prevention

- Do not treat observed default outbound IPs as a permanent contract.
- Use NAT Gateway when partner allow-lists require stable egress identity.
- Include downstream allow-list updates in every environment recreation or network migration runbook.
- Capture pre-cutover and post-cutover egress measurements from the running app path.

## See Also

- [Egress IP Change Lab](../../lab-guides/egress-ip-change.md)
- [Egress Control](../../../platform/networking/egress-control.md)
- [Networking in Azure Container Apps](../../../platform/networking/index.md)
- [UDR and NSG Egress Blocked](udr-nsg-egress-blocked.md)

## Sources

- [Networking in Azure Container Apps environment](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [User-defined routes in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes)
