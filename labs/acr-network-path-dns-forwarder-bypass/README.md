# Lab: ACR Network Path E — DNS Forwarder Bypass

Reproduce **Scenario E** from
[ACR Network Path Selection](../../docs/platform/networking/acr-network-path-selection.md):
the Container Apps environment uses a custom DNS server (here, dnsmasq on
an Ubuntu B1s VM) whose default upstream is **public DNS (8.8.8.8)**
instead of **Azure DNS (168.63.129.16)**, so the ACR FQDN resolves to
the **public** registry IP even though a Private Endpoint and a
correctly-populated Private DNS Zone both exist.

Scenario E is the **DNS-topology failure class**: the PE plumbing is
healthy, the Private DNS zone has the right records, the VNet link is in
place — but the resolver path simply never asks Azure DNS, so the
Private DNS Zone substitution that turns the public CNAME chain into a
PE NIC RFC1918 IP never happens. Scenario D (a separate lab) covers the
**record-level** split-brain variant where part of the ACR namespace
resolves privately and part does not.

## Why this is a workload-path lab (read before running)

In this Azure Container Apps reproduction, breaking the VNet custom DNS
forwarder produces **no immediate revision-health impact** on the
already-running revision. Empirically (see Observed Evidence in the lab guide), the
already-running revision stays `Healthy` and continues to serve traffic
unchanged. What clearly does change is **what application code sees**:
a `socket.getaddrinfo()` call from inside the replica returns the
public registry IP instead of the PE NIC's RFC1918 IP.

The lab makes this observable through a `/probe` HTTP endpoint
(`workload/app.py`) that performs `getaddrinfo(ACR_FQDN)` from inside
the running container and reports `first_class=private` (PE NIC, RFC1918)
or `first_class=public` (forwarder upstream is not Azure DNS). The
falsification swaps dnsmasq's upstream, watches `first_class` flip, and
verifies the already-running revision stays `Healthy` throughout.

This finding matters operationally: in ACA, a misconfigured custom DNS
forwarder may surface first as application traffic resolving publicly
(failing TLS handshake to a private endpoint, leaking outbound to the
internet, etc.) rather than as an `ImagePullBackOff`. Pull-path
observability is therefore not a reliable early warning for DNS-topology
failures in this platform.

> **Scope note**: this lab intentionally does not script a "broken-window
> fresh pull" test. With ACR configured for `publicNetworkAccess=Disabled`
> (the realistic production posture this lab models), Container Apps'
> control-plane ACR token exchange is blocked at the ACR firewall for
> reasons unrelated to dnsmasq, which would confound the variable under
> test. See the lab guide §"Why we do not script a broken-window fresh
> pull" for details.

## Architecture

```text
Container App replica
       │  app code: socket.getaddrinfo("<acr>.azurecr.io")
       │           ↓ uses VNet custom DNS = 10.60.5.4
       ▼
   dnsmasq VM ─── HEALTHY: server=168.63.129.16 (Azure DNS)
                  BROKEN:  server=8.8.8.8       (public DNS)
       │                                            │
       ▼                                            ▼
   Azure DNS                                    Public DNS
   (sees VNet link to                           (no view of Private DNS Zone)
    privatelink.azurecr.io)                          │
       │                                            ▼
       ▼                                       public ACR IP (e.g. 20.41.69.142)
   PE NIC RFC1918 IP                                │
   (10.60.4.5)                                     /probe → first_class=public
       │
       ▼
   /probe → first_class=private


Already-running revision behavior during the broken window:
   Already-cached image layers continue to serve traffic. The replica
   does not re-pull or restart during this lab, so revision healthState
   stays Healthy. See lab guide §"Why we do not script a broken-window
   fresh pull" for the scope boundary.
```

The PE NIC is healthy and the Private DNS Zone has the right records;
the dnsmasq VM just sends queries to the wrong upstream — but only the
workload sees that.

## Structure

```text
labs/acr-network-path-dns-forwarder-bypass/
├── infra/main.bicep            # RG-scoped: VNet + dnsmasq VM + LAW + ACR Premium + PE + DNS zone + CAE + App + AcrPull
├── workload/
│   ├── app.py                  # /probe returns JSON {addresses, first_class} from inside the replica
│   └── Dockerfile
├── trigger.sh                  # build image in ACR, switch app to private image (sets BUILD_TAG)
├── verify.sh                   # confirm Healthy + /probe returns first_class=private (PE NIC IP)
├── falsify.sh                  # swap dnsmasq upstream to 8.8.8.8 → /probe flips to public → restore → /probe back to private
├── cleanup.sh                  # az group delete --no-wait
└── README.md                   # this file
```

`ACR_FQDN` is injected into the container template by `main.bicep`
(`containerRegistry.properties.loginServer`), so the `/probe` endpoint
knows which FQDN to resolve.

## Quick Start

```bash
export RG="rg-acr-dns-fwd-lab"
export LOCATION="koreacentral"
export BASE_NAME="acrdnsfwd"
export VM_ADMIN_PASSWORD="$(openssl rand -base64 24)Aa1!"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" --name acr-dns-forwarder-bypass \
    --template-file labs/acr-network-path-dns-forwarder-bypass/infra/main.bicep \
    --parameters baseName="$BASE_NAME" vmAdminPassword="$VM_ADMIN_PASSWORD"

bash labs/acr-network-path-dns-forwarder-bypass/trigger.sh
bash labs/acr-network-path-dns-forwarder-bypass/verify.sh
bash labs/acr-network-path-dns-forwarder-bypass/falsify.sh
bash labs/acr-network-path-dns-forwarder-bypass/cleanup.sh
```

The lab uses `az vm run-command invoke` for every dnsmasq operation
(via Azure RBAC on the VM resource), so no SSH key, no SSH inbound, and
no public IP on the VM are required. `VM_ADMIN_PASSWORD` is still
required by Azure VM provisioning, but it is discarded after deploy.

## What "Success" Looks Like

The lab is reproduced when **all** of the following hold:

1. `verify.sh` exits `PASS` — latest revision is `Healthy`, and the
   `/probe` endpoint on the Container App's ingress returns JSON with
   `first_class=private` and `addresses[0].ip` equal to the PE NIC's
   `privateIPAddress`.
2. `falsify.sh` baseline step → `first_class=private`.
3. `falsify.sh` broken step (after upstream swap to `8.8.8.8`) →
   `first_class=public`, and revision health is still `Healthy`.
4. `falsify.sh` recovery step (after upstream restore to
   `168.63.129.16`) → `first_class=private` again.

Steps 2-4 together prove the dnsmasq upstream controls **workload DNS
resolution** while leaving the already-running revision's health
unaffected during the broken window.

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| ACR Premium | $1.67 / day |
| Log Analytics | <$0.10 for the lab window |
| Private Endpoint | $0.01 / hour |
| Container Apps (1 replica, Consumption profile) | <$0.10 / hour |
| VM B1s + Standard_LRS disk | <$0.05 / hour |
| **Total for a 2-3 hour run** | **~$1-3** |

Tear down with `cleanup.sh` immediately after capturing evidence.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/acr-network-path-dns-forwarder-bypass.md`
- Platform: `docs/platform/networking/acr-network-path-selection.md`
- Related lab: `labs/acr-network-path-pe-direct/` (covers Scenario B —
  the happy-path PE topology this lab silently degrades from at the
  workload layer)
