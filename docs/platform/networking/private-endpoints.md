---
content_sources:
  diagrams:
    - id: overview
      type: flowchart
      source: self-generated
      justification: Comparison of inbound environment Private Link and outbound private-dependency access synthesized from Microsoft Learn; it keeps the two private endpoint purposes and internal ingress distinct.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks
        - https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview
    - id: architecture
      type: flowchart
      source: self-generated
      justification: Downstream Storage private endpoint topology synthesized from Microsoft Learn; the ACA environment subnet relationship, target-side private endpoint NIC, external Private DNS zone, DNS lookup, and HTTPS transport are shown as separate concepts.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks
        - https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview
        - https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
    - id: privatelink-region-data-microsoft-com-for-the-data-endpoint-layer
      type: flowchart
      source: self-generated
      justification: ACR private endpoint DNS and image-layer sequence synthesized from current Microsoft Learn; one private endpoint resource supplies private IP configurations for registry and regional data endpoints, while authentication/discovery, redirect, DNS, and layer transport remain distinct.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints
        - https://learn.microsoft.com/en-us/azure/container-registry/container-registry-dedicated-data-endpoints
        - https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: agent
  core_claims:
    - claim: Workload profiles environments support creating private endpoints on the Container Apps environment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Using an existing virtual network allows Container Apps to access resources behind private endpoints in the virtual network.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Internal environments have no public endpoints and are deployed with an internal load balancer IP from the virtual network's private address space.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Public network access must be disabled to create private endpoints on a Container Apps environment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
    - claim: Container app ingress can be limited to traffic from within the same Container Apps environment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
---
# Private Endpoints

Connect Container Apps to Azure services using Private Endpoints.

## Overview

**Takeaway:** An inbound private endpoint publishes the Container Apps environment privately, while an outbound call to a dependency uses that dependency's private endpoint. Neither pattern is app-level internal ingress.

<!-- diagram-id: overview -->
```mermaid
flowchart TD
    accTitle: Inbound and outbound private endpoint purposes in Azure Container Apps
    accDescr: A private client can enter a workload profiles Container Apps environment through an inbound environment private endpoint when public network access is disabled. Separately, a logical app replica can connect outbound through a dependency private endpoint in a target-side subnet. Internal app ingress is a third, environment-scoped setting.

    REQUIREMENTS["Inbound environment PE requirements<br/>workload profiles environment<br/>public network access disabled"]
    CLIENT["Private client"]

    subgraph VNET["Customer-managed virtual network"]
        subgraph INBOUND_SUBNET["Inbound endpoint subnet"]
            ACA_PE["INBOUND private endpoint NIC<br/>target: managed environment"]
        end
        ENV_SUBNET["Dedicated environment subnet<br/>ACA environment relationship<br/>not an app integration NIC"]
        TARGET_SUBNET["Target-side PE subnet<br/>dependency private endpoint NIC"]
    end

    subgraph ENV["Managed ACA environment (logical)"]
        INGRESS["Managed ingress proxy"]
        REV_ACTIVE["Active revision"]
        REPLICAS["Revision replicas"]
    end

    DEPENDENCY["Downstream Azure service<br/>Storage, Key Vault, or ACR"]
    INTERNAL["Separate setting<br/>app-level internal ingress"]

    REQUIREMENTS -.-> ACA_PE
    CLIENT ==>|"Inbound HTTPS"| ACA_PE
    ACA_PE ==>|"Private Link to environment"| INGRESS
    INGRESS ==>|"Route accepted request"| REV_ACTIVE
    REV_ACTIVE ==>|"Continue request to replica"| REPLICAS
    ENV_SUBNET -.-> ENV
    REPLICAS ==>|"Outbound HTTPS"| TARGET_SUBNET
    TARGET_SUBNET ==>|"Private Link to dependency"| DEPENDENCY
    INTERNAL -.->|"Separate ingress visibility setting"| INGRESS

    LEGEND["Arrow key<br/>thick = HTTPS transport<br/>dotted = logical relationship or requirement"]
```

*Figure: The inbound environment private endpoint, dedicated environment subnet relationship, and downstream dependency private endpoint are separate resources and purposes. The managed environment remains a logical boundary rather than a customer-owned subnet workload.*

!!! info "What are Private Endpoints?"
    Private Endpoints provide private IP addresses for supported Azure services. Traffic to the private endpoint traverses the virtual network and Azure Private Link on the Microsoft backbone. A private endpoint does not by itself disable the service's public endpoint; configure public network access separately when the design requires it. Benefits include:

    - Private IP addresses for Azure services
    - Traffic stays on Microsoft backbone
    - A private network path that can be combined with public-access controls

## Portal view: non-integrated starting point before the private-endpoint setup

This screenshot is used here as a visual starting point for the [Quick Start: Deploy Test Environment](#quick-start-deploy-test-environment) recipe and the [Architecture](#architecture) flow that depend on a VNet-integrated environment.

![Networking blade showing "General" selected; "Public Network Access" with "Enable: Allows incoming traffic from the public internet." selected; "Virtual network" section reading "This environment isn't integrated"; tab strip lists "General", "Ingress settings", "Request Routing", "Encryption", "Custom DNS Suffix"](../../assets/platform/environments/03-networking.png)

[Observed] "Public Network Access" shows "Enable: Allows incoming traffic from the public internet." selected. "Virtual network" reads "This environment isn't integrated". The visible tabs are "General", "Ingress settings", "Request Routing", "Encryption", and "Custom DNS Suffix".

[Inferred] The visible "This environment isn't integrated" text is consistent with this page using the screenshot as a before-state for the VNet-integrated path in [Quick Start: Deploy Test Environment](#quick-start-deploy-test-environment) and [Architecture](#architecture). The selected "Enable: Allows incoming traffic from the public internet." option appears to map to a networking context discussed separately from the `--internal-only true` example in [Verify Connectivity](#verify-connectivity).

[Not Proven] This image does not show a private endpoint resource name. It does not show the private DNS zone label `privatelink.blob.core.windows.net` from [Architecture](#architecture). It does not show the `privatelink.azurecr.io` records from [ACR Private Endpoint Flow](#acr-private-endpoint-flow). It does not show the `--internal-only true` flag from [Verify Connectivity](#verify-connectivity). It does not show the managed identity RBAC role names from [Using Private Endpoints in Code](#using-private-endpoints-in-code).

## Quick Start: Deploy Test Environment

We provide a complete private endpoint test environment with Key Vault and Storage Account.

```bash
cd infra
./deploy-private.sh
```

| Command | Purpose |
|---------|---------|
| `cd infra` | Moves to the infrastructure script directory. |
| `./deploy-private.sh` | Deploys the sample VNet, private endpoints, DNS, and identity resources. |

This deploys:

| Resource | Purpose |
|----------|---------|
| VNet with 2 subnets | Network isolation |
| Key Vault + Private Endpoint | Secret management |
| Storage Account + Private Endpoint | Blob storage |
| ACR + one `registry` Private Endpoint | Private container image pull; verify that its NIC has registry and regional data IP configurations |
| Private DNS Zones | Name resolution |
| Managed Identity | Passwordless authentication |

## Supported Services

| Service | Private DNS Zone | Private Link group ID | Additional NIC IP configurations |
|---------|------------------|-----------------------|----------------------------------|
| Azure SQL | `privatelink.database.windows.net` | `sqlServer` | Service-specific |
| Blob Storage | `privatelink.blob.core.windows.net` | `blob` | Service-specific |
| Key Vault | `privatelink.vaultcore.azure.net` | `vault` | Service-specific |
| Cosmos DB | `privatelink.documents.azure.com` | `Sql` | Service-specific |
| Service Bus | `privatelink.servicebus.windows.net` | `namespace` | Service-specific |
| Redis Cache | `privatelink.redis.cache.windows.net` | `redisCache` | Service-specific |
| Container Registry | `privatelink.azurecr.io` | `registry` | `registry_data_<region>` for each regional dedicated data endpoint |

!!! tip "Validate DNS before transport troubleshooting"
    Confirm that the service FQDN resolves to the intended private endpoint IP, then test transport and inspect NSG and route behavior. A successful DNS answer alone does not prove connectivity or authorization.

!!! note "ACR private endpoints expose multiple private IP configurations"
    One ACR private endpoint resource uses the `registry` group ID and receives a private IP for the registry endpoint plus a private IP configuration named `registry_data_<region>` for each regional dedicated data endpoint. Current Microsoft Learn states that configuring an ACR private endpoint automatically enables dedicated data endpoints. The checked-in quick-start template creates the single `registry` private endpoint; after deployment, verify the NIC IP configurations and DNS records rather than expecting a second private endpoint. See [Private Container Registry](../../language-guides/python/recipes/container-registry.md) for the full setup.

## Architecture

**Takeaway:** For a downstream Storage dependency, the environment uses its dedicated subnet while the Storage private endpoint NIC sits in a separate target-side subnet; DNS supplies the private IP before a distinct HTTPS connection begins.

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    accTitle: Container Apps outbound access to a Storage private endpoint
    accDescr: A logical Container Apps replica uses a dedicated environment subnet relationship. A linked Private DNS zone outside the virtual network resolves the Storage Blob name to the private endpoint IP. The replica then opens a separate HTTPS connection to the Storage private endpoint NIC in a target-side subnet, which connects by Private Link to the Storage account outside the virtual network.

    BLOB_NAME["Storage Blob service name<br/>account.blob.core.windows.net"]
    DNS["DNS resolver"]
    ZONE["Private DNS zone<br/>privatelink.blob.core.windows.net<br/>linked to customer VNet"]

    subgraph ENV["Managed Container Apps environment — logical boundary"]
        APP["Container app — logical grouping"]
        REV_ACTIVE["Active revision"]
        REPLICAS["Revision replicas"]
        APP -.-> REV_ACTIVE
        REV_ACTIVE -.-> REPLICAS
    end

    subgraph VNET["Customer-managed virtual network"]
        subgraph ENV_SUBNET["Dedicated environment subnet"]
            ADAPTER["ACA environment subnet relationship<br/>not an app integration NIC"]
        end
        subgraph PE_SUBNET["Target-side private endpoint subnet"]
            STORAGE_PE["Storage private endpoint NIC<br/>Blob private IP"]
        end
    end

    STORAGE["Storage account<br/>outside customer VNet"]

    ADAPTER -.-> ENV
    REPLICAS -.->|"1  Resolve service name"| BLOB_NAME
    BLOB_NAME -.->|"2  DNS query"| DNS
    DNS -.->|"3  Consult linked zone"| ZONE
    ZONE -.->|"4  Return private endpoint IP"| REPLICAS
    REPLICAS ==>|"5  HTTPS to private IP"| STORAGE_PE
    STORAGE_PE ==>|"6  Private Link"| STORAGE

    LEGEND["Arrow key<br/>thick = HTTPS/data transport<br/>dotted = DNS or logical relationship"]
```

*Figure: Downstream private-dependency topology. DNS resolution identifies the private endpoint IP; it does not prove that HTTPS connectivity or service authorization succeeds.*

### ACR Private Endpoint Flow

For ACR Private Link in Azure public cloud, the recommended private DNS configuration uses `privatelink.azurecr.io`. ACR adds records for the registry endpoint and regional data endpoints to that zone; do not create the regional data name as a second private DNS zone.

The public/private name chain distinguishes two endpoint roles:

1. `<registry>.azurecr.io`: registry authentication and content discovery.
2. `<registry>.<region>.data.azurecr.io`: dedicated image-layer downloads; its private-link record is represented under `privatelink.azurecr.io` as documented by Azure Private Link DNS guidance.

<!-- diagram-id: privatelink-region-data-microsoft-com-for-the-data-endpoint-layer -->
```mermaid
flowchart TD
    accTitle: ACR private endpoint registry and data endpoint flow
    accDescr: A logical Container Apps image-pull client resolves the registry login name through the linked privatelink.azurecr.io zone and connects to the registry private IP for authentication and content discovery. A 307 redirect identifies the regional data endpoint. The client separately resolves that name and downloads layer bytes through the data private IP configuration on the same ACR private endpoint resource.

    PULLER_LOGIN["ACA image-pull client<br/>registry request"]
    LOGIN_DNS["1  Resolve registry.azurecr.io<br/>through privatelink.azurecr.io"]
    LOGIN_IP["2  Registry private IP"]
    REGISTRY_PE["3  Registry IP configuration<br/>on ACR private endpoint"]
    DISCOVERY["4  ACR authentication and<br/>content discovery"]
    REDIRECT["5  Manifest and 307 redirect<br/>names regional data endpoint"]
    DATA_DNS["6  Resolve registry.region.data.azurecr.io<br/>through privatelink.azurecr.io"]
    DATA_IP["7  Regional data private IP"]
    PULLER_DATA["ACA image-pull client<br/>layer request"]
    DATA_PE["8  Regional data IP configuration<br/>on the same ACR private endpoint"]
    LAYERS["9  Image layer bytes"]

    PULLER_LOGIN -.-> LOGIN_DNS
    LOGIN_DNS -.-> LOGIN_IP
    LOGIN_IP -.-> PULLER_LOGIN
    PULLER_LOGIN ==>|"Registry HTTPS"| REGISTRY_PE
    REGISTRY_PE ==>|"Private Link"| DISCOVERY
    DISCOVERY -->|"Authorization and discovery result"| REDIRECT
    REDIRECT -.-> DATA_DNS
    DATA_DNS -.-> DATA_IP
    DATA_IP -.-> PULLER_DATA
    PULLER_DATA ==>|"Layer HTTPS"| DATA_PE
    DATA_PE ==>|"Private Link layer download"| LAYERS

    LEGEND["Arrow key<br/>thick = HTTPS or layer-data transport<br/>solid = authorization/discovery result<br/>dotted = DNS or redirect metadata"]
```

*Figure: The ACR private endpoint resource can expose multiple private IP configurations. The registry request performs authentication and discovery; the regional data endpoint carries layer downloads after the redirect. DNS answers are not authorization or transport results.*

## Infrastructure Components

### 1. Network Module

The network module creates a VNet with two subnets:

Source template: `infra/modules/network.bicep`

| Subnet | CIDR | Purpose |
|--------|------|---------|
| `snet-container-apps` | `<container-apps-subnet-cidr>` | Container Apps Environment |
| `snet-private-endpoints` | `<private-endpoints-subnet-cidr>` | Private Endpoints |

!!! warning "Size the subnet for the environment type"
    Workload profiles environments and legacy Consumption-only environments have different minimum subnet sizes. Follow the current Microsoft Learn sizing table instead of applying one prefix universally.

### 2. Key Vault with Private Endpoint

Source template: `infra/modules/keyvault-private.bicep`

Features:

- Public network access disabled
- RBAC authorization enabled
- Sample secrets for testing
- Automatic DNS registration

### 3. Storage Account with Private Endpoint

Source template: `infra/modules/storage-private.bicep`

Features:

- Blob endpoint with private endpoint
- Public access disabled
- Test container created
- Managed Identity access configured

## Using Private Endpoints in Code

### Key Vault Access

```python
import os
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

vault_url = os.environ['KEY_VAULT_URL']
credential = DefaultAzureCredential()
client = SecretClient(vault_url=vault_url, credential=credential)

secret = client.get_secret("database-password")
print(f"Secret value: {secret.value}")
```

### Storage Account Access

```python
import os
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

account_url = os.environ['STORAGE_BLOB_ENDPOINT']
credential = DefaultAzureCredential()
client = BlobServiceClient(account_url=account_url, credential=credential)

container = client.get_container_client("test-container")
for blob in container.list_blobs():
    print(f"Blob: {blob.name}")
```

!!! tip "Managed Identity"
    The deployment automatically configures the Managed Identity with appropriate RBAC roles:
    
    - **Key Vault**: `Key Vault Secrets User`
    - **Storage**: `Storage Blob Data Contributor`

## Verify Connectivity

### Testing Internal Environments vs Internal App Ingress

Microsoft Learn separates **environment-level ingress scope** from **app-level ingress scope**:

- **Environment**: create the Container Apps environment with `internal: true` by using `az containerapp env create --internal-only true`.
- **App**: configure the individual app ingress as internal-only (`external: false` in ARM/Bicep/YAML).

An **internal environment** provides a VNet-scoped environment entry point. To let VNet clients reach an app through that entry point, configure the app with external ingress; in an internal environment, "external" means external to the app but still within the environment's VNet boundary. App-level internal ingress (`external: false`) is for same-environment callers by default and is not an inbound environment private endpoint. An environment-level HTTP route can explicitly target an internal-ingress app, so do not treat the default outside-environment `404` as an absolute isolation guarantee.

Reference this guidance in Microsoft Learn:

- [Integrate a virtual network with an Azure Container Apps environment](https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom)
- [Ingress in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Communicate between container apps in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/connect-apps)

!!! warning "Internal ingress validation requires an internal environment"
    VM, Bastion, VPN, or ExpressRoute tests validate **internal environments** because those environments are exposed through the VNet. They do **not** validate app-level `.internal.` ingress, which Microsoft Learn scopes to callers inside the same Container Apps environment. Use one of these paths to reach the VNet:

    - Jump box VM in the VNet + Azure Bastion
    - VPN or ExpressRoute connection
    - Container console (`az containerapp exec`) for outbound dependency tests only

#### Create the environment as internal

The following Microsoft Learn-based command creates a Container Apps environment without a public static IP.

```bash
az containerapp env create \
  --name "$CONTAINERAPPS_ENVIRONMENT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --infrastructure-subnet-resource-id "$INFRASTRUCTURE_SUBNET" \
  --internal-only true
```

| Command/Parameter | Purpose |
|-------------------|---------|
| `az containerapp env create` | Creates the Container Apps environment. |
| `--infrastructure-subnet-resource-id` | Supplies the dedicated environment subnet. Delegate it to `Microsoft.App/environments` for a workload profiles environment; a legacy Consumption-only environment must use an undelegated subnet. |
| `--internal-only true` | Makes the environment internal so inbound traffic stays on the VNet-connected path. |

#### Environment scope vs app scope

| Scope | Setting | Result |
|-------|---------|--------|
| Environment | `--internal-only true` / `internal: true` | Removes the public environment entry point and makes the environment VNet-only. |
| App ingress | `external: false` | Restricts that app to callers in the same Container Apps environment; by itself it does not make the environment VNet-only. |

#### Case 1: Validate an internal environment from a VM or Bastion host

After the environment is internal, validate the **environment-scoped endpoint** from a host that can resolve the private DNS zone for the environment default domain.

#### Option A: Deploy Jump Box VM with Bastion

```bash
# Set variables (adjust CIDR if needed)
export BASTION_SUBNET_PREFIX="<bastion-subnet-cidr>"

# Create Bastion subnet (required: /26 or larger)
az network vnet subnet create \
  --resource-group $RG \
  --vnet-name $VNET_NAME \
  --name "AzureBastionSubnet" \
  --address-prefixes $BASTION_SUBNET_PREFIX

# Create public IP for Bastion
az network public-ip create \
  --resource-group $RG \
  --name "pip-bastion" \
  --sku "Standard" \
  --location $LOCATION

# Create Bastion host (takes 5-10 minutes)
az network bastion create \
  --resource-group $RG \
  --name "bastion-$BASENAME" \
  --vnet-name $VNET_NAME \
  --public-ip-address "pip-bastion" \
  --location $LOCATION \
  --sku "Basic"

# Create jump box VM in private endpoint subnet (no public IP)
az vm create \
  --resource-group $RG \
  --name "vm-jumpbox" \
  --image "Ubuntu2404" \
  --size "Standard_B1s" \
  --vnet-name $VNET_NAME \
  --subnet "snet-private-endpoints" \
  --admin-username "azureuser" \
  --generate-ssh-keys \
  --public-ip-address ""
```

| Command/Parameter | Purpose |
|-------------------|---------|
| `AzureBastionSubnet` | Required subnet name for Bastion (must be exactly this name) |
| `--address-prefixes "<bastion-subnet-cidr>"` | Supplies the Bastion subnet CIDR; use `/26` or larger. |
| `--sku "Basic"` | Basic Bastion SKU (~$0.19/hour) |
| `--public-ip-address ""` | VM has no public IP - only accessible via Bastion |

#### Connect to VM via Bastion

```bash
# Connect via Azure Portal: VM > Connect > Bastion
# Or use Azure CLI:
az network bastion ssh \
  --resource-group $RG \
  --name "bastion-$BASENAME" \
  --target-resource-id $(az vm show --resource-group $RG --name "vm-jumpbox" --query "id" --output tsv) \
  --auth-type "ssh-key" \
  --username "azureuser" \
  --ssh-key "~/.ssh/id_rsa"
```

| Command/Parameter | Purpose |
|-------------------|---------|
| `az network bastion ssh` | Opens an SSH session to the jump box through Azure Bastion. |
| `--target-resource-id` | Resolves the VM resource ID dynamically for the SSH target. |
| `--ssh-key` | Uses your local SSH private key for authentication. |

#### Test internal-environment reachability from Jump Box

Once connected to the VM, test the app FQDN that uses the environment default domain.

```bash
# Get the app FQDN in the internal environment
# Format: <app-name>.<environment-default-domain>

# Test DNS resolution - should return the environment private IP
nslookup <your-app>.<environment-default-domain>
```

| Command | Purpose |
|---------|---------|
| `nslookup <your-app>.<environment-default-domain>` | Confirms that the app FQDN in the internal environment resolves from inside the VNet-connected host. |

Expected output:
```
Server:         127.0.0.53
Address:        127.0.0.53#53

Non-authoritative answer:
Name:   myapp.<environment-default-domain>
Address: <private-ip>
```

```bash
# Test app endpoint
curl https://<your-app>.<environment-default-domain>/health
```

| Command | Purpose |
|---------|---------|
| `curl https://<your-app>.<environment-default-domain>/health` | Sends an HTTPS request to the app through the VNet-scoped endpoint of the internal environment. |

#### Option B: Minimal Test VM (No Bastion)

For quick testing, create a VM with public IP:

```bash
az vm create \
  --resource-group $RG \
  --name "vm-test" \
  --image "Ubuntu2404" \
  --size "Standard_B1s" \
  --vnet-name $VNET_NAME \
  --subnet "snet-private-endpoints" \
  --admin-username "azureuser" \
  --generate-ssh-keys

# SSH to VM (use the public IP from output)
ssh azureuser@<public-ip>

# Test from inside VM
nslookup <your-app>.<environment-default-domain>
curl https://<your-app>.<environment-default-domain>/health
```

| Command | Purpose |
|---------|---------|
| `az vm create ...` | Creates a temporary VM inside the VNet for validation. |
| `ssh azureuser@<public-ip>` | Connects to the temporary VM when you use the public-IP shortcut. |
| `nslookup ...` / `curl ...` | Verifies DNS resolution and HTTPS connectivity to the internal environment endpoint from the VM. |

#### Case 2: Validate app-level internal ingress from the same Container Apps environment

Use this test when the app is configured with `external: false`. Microsoft Learn states that the `.internal.` FQDN is reachable from **other apps in the same environment**, not from a VM in the VNet.

```bash
az containerapp exec --name <source-app> --resource-group <resource-group> --command /bin/bash

# Inside the source app container
curl https://<target-app>.internal.<unique-id>.<region>.azurecontainerapps.io/health
```

| Command | Purpose |
|---------|---------|
| `az containerapp exec --name <source-app> --resource-group <resource-group> --command /bin/bash` | Opens a shell in another app that runs in the same Container Apps environment. |
| `curl https://<target-app>.internal.<unique-id>.<region>.azurecontainerapps.io/health` | Validates app-level internal ingress from a supported same-environment caller. |

!!! tip "Cost Optimization"
    Delete test resources after verification:
    ```bash
    az vm delete --resource-group $RG --name "vm-jumpbox" --yes
    az network bastion delete --resource-group $RG --name "bastion-$BASENAME"
    az network public-ip delete --resource-group $RG --name "pip-bastion"
    ```

    | Command | Purpose |
    |---------|---------|
    | `az vm delete` | Removes the temporary jump box VM. |
    | `az network bastion delete` | Removes the Bastion host after testing. |
    | `az network public-ip delete` | Removes the Bastion public IP resource. |
    
    - VM (B1s): ~$0.01/hour
    - Bastion (Basic): ~$0.19/hour

### From Container Console (Outbound Tests)

```bash
az containerapp exec --name <app-name> --resource-group <resource-group> --command /bin/bash
```

| Command/Parameter | Purpose |
|-------------------|---------|
| `az containerapp exec` | Opens a shell into the running container for outbound-only validation. |
| `--name` | Specifies the Container App to connect to. |
| `--resource-group` | Specifies the resource group that contains the app. |
| `--command /bin/bash` | Starts a Bash shell when the image includes Bash. |

### Check DNS Resolution

```bash
nslookup <keyvault-name>.vault.azure.net
```

| Command | Purpose |
|---------|---------|
| `nslookup <keyvault-name>.vault.azure.net` | Verifies that the public service name resolves through the linked private DNS zone. |

Expected output (private IP):
```
Server:    168.63.129.16
Address:   168.63.129.16#53

Non-authoritative answer:
<keyvault-name>.vault.azure.net  canonical name = <keyvault-name>.privatelink.vaultcore.azure.net.
Name:   <keyvault-name>.privatelink.vaultcore.azure.net
Address: <private-ip>
```

!!! warning "Public IP Response"
    If you see a public IP address, the Private DNS Zone is not correctly linked to your VNet.

### Test Connectivity

```bash
nc -zv <keyvault-name>.vault.azure.net 443
```

| Command | Purpose |
|---------|---------|
| `nc -zv <keyvault-name>.vault.azure.net 443` | Confirms that TCP port 443 is reachable over the private endpoint path. |

## Troubleshooting

### DNS Resolution Returns Public IP

1. Verify Private DNS Zone exists
2. Check VNet link is configured
3. Ensure Private Endpoint is in `Succeeded` state

```bash
az network private-endpoint show \
  --name pe-kv-<basename> \
  --resource-group <resource-group> \
  --query 'provisioningState'
```

| Command/Parameter | Purpose |
|-------------------|---------|
| `az network private-endpoint show` | Displays the private endpoint resource during troubleshooting. |
| `--query 'provisioningState'` | Returns only the provisioning state value. |

### Connection Timeout

1. Check NSG rules on the private endpoint subnet
2. Verify the service's firewall allows the private endpoint
3. Ensure the Container Apps environment has a routed path to the private endpoint, such as the same VNet, a peered VNet, or a connected on-premises network

### Authentication Errors

1. Verify Managed Identity is assigned to Container App
2. Check RBAC roles are correctly assigned
3. Ensure `AZURE_CLIENT_ID` environment variable is set

```bash
az containerapp show --name <app-name> --resource-group <resource-group> --query 'identity'
```

| Command/Parameter | Purpose |
|-------------------|---------|
| `az containerapp show` | Displays the Container App resource definition. |
| `--query 'identity'` | Filters the output to the managed identity configuration. |

## Private DNS Resolver Placement in Hub-Spoke Topologies

When connecting on-premises networks to Azure private endpoints through Site-to-Site VPN or ExpressRoute, clients need a DNS forwarding path to the linked Azure Private DNS zones. Azure DNS Private Resolver is a supported managed option; an existing custom DNS forwarder can also provide that path.

### Resolver in Hub vs Spoke

For Azure DNS Private Resolver, a hub VNet is a common placement. If the hub lacks address space for the required dedicated `/28` or larger endpoint subnet, a connected spoke can host the resolver when routing and return paths are configured correctly.

| Placement | When to Use | Consideration |
|---|---|---|
| Hub VNet | Hub has available `/28` subnet | Simplest routing — on-prem traffic stays in Hub for DNS |
| Spoke VNet | Hub address space exhausted | Requires UDR for return traffic via Hub Firewall |

!!! note "Validated Pattern"
    Deploying Private DNS Resolver in Spoke VNet with on-premises Conditional Forwarder pointing to the Inbound Endpoint IP has been validated to work correctly. See [On-Premises DNS to Container Apps Internal Environment](../../operations/deployment/internal-ingress-on-prem-dns.md) for the full procedure.

## Clean Up

```bash
az group delete --name rg-container-apps-private --yes --no-wait
```

| Command/Parameter | Purpose |
|-------------------|---------|
| `az group delete` | Deletes the test resource group and all contained resources. |
| `--yes` | Skips the interactive confirmation prompt. |
| `--no-wait` | Starts the delete operation asynchronously. |

!!! note "Soft Delete"
    Key Vault uses soft delete by default. Deleted vaults are retained for 7 days before permanent deletion.

## See Also
- [VNet Integration](vnet-integration.md)
- [Egress Control](egress-control.md)
- [ACR Network Path Selection](acr-network-path-selection.md)
- [Application Gateway Integration with an Internal Container Apps Environment](application-gateway-integration.md)
- [Key Vault](../identity-and-secrets/key-vault.md)
- [Blob Storage and File Mounts](../../language-guides/python/recipes/storage.md)
- [Private Container Registry](../../language-guides/python/recipes/container-registry.md)

## Sources
- [Internal ingress with VNet integration in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/vnet-custom-internal)
- [Networking in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Use a private endpoint with a Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint)
- [What is a private endpoint? (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Azure Private Endpoint DNS zone values (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [ACR dedicated data endpoints (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-dedicated-data-endpoints)
- [ACR Private Link (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints)
- [Azure DNS Private Resolver overview (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview)
