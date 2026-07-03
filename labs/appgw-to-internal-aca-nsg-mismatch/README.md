# Lab: AppGW to Internal ACA — NSG Destination Pinned to staticIp

Reproduce **H1** from the [AppGW to Internal ACA: NSG Destination Pinned to
staticIp Fails](../../docs/troubleshooting/playbooks/ingress-and-networking/appgw-to-internal-aca-nsg-destination.md)
playbook: an Application Gateway backend health goes `Unhealthy` against an
internal Container Apps environment because the container app subnet NSG
inbound rule uses `Destination = staticIp` (a single IP) instead of the
container app's subnet CIDR. NSGs behind an internal load balancer evaluate
the destination NIC, not the load balancer frontend, so `staticIp` as a
destination is by-design broken on workload profiles environments.

## Architecture

```text
Operator workstation (public internet)
        │  HTTP :80
        ▼
Application Gateway Standard_v2 (public IP)
   snet-appgw  10.0.1.0/24
        │  backend pool = <app-fqdn> (resolved via Private DNS Zone)
        │  HTTPS :443 with pickHostNameFromBackendAddress = true
        ▼
Internal Container Apps environment ILB frontend = staticIp
        │  ILB forwards to edge-proxy NIC in snet-cae
        ▼
Container app edge-proxy NIC (some IP inside snet-cae)
   snet-cae   10.0.2.0/23   NSG = nsg-snet-cae-<suffix>
        │  Inbound rule 100 Allow (BROKEN)
        │    Source      = 10.0.1.0/24
        │    Destination = <staticIp>/32   <-- misconfiguration
        │    Ports       = 443, 31443
        │  Inbound rule 200 Allow: AzureLoadBalancer -> snet-cae, 30000-32767
        │  Inbound rule 4096 Deny: * * *
        ▼
Container App replica (mcr.microsoft.com/azuredocs/containerapps-helloworld)
```

The lab is designed so **rule 100's Destination is the sole controlled
variable**. Rule 200 and rule 4096 make the NSG a realistically locked-down
production shape (otherwise the default `AllowVnetInBound` at priority 65000
would let packets through and mask the failure). Rule 100 keeps the ports
list correct (`443, 31443`) so the ONLY failure driver is the Destination
address — this isolates H1 from H2 (missing edge-proxy ports).

## Structure

```text
labs/appgw-to-internal-aca-nsg-mismatch/
├── README.md
├── cleanup.sh
├── evidence/
│   └── README.md
├── infra/
│   ├── main.bicep
│   └── dns-and-appgw.bicep
├── fix.sh
├── trigger.sh
├── verify.sh
└── workload/
    └── README.md
```

## Quick Start

```bash
export RG="rg-appgw-aca-nsg-lab"
export LOCATION="koreacentral"
export BASE_NAME="appgwnsg"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" --name appgw-aca-nsg-mismatch \
    --template-file labs/appgw-to-internal-aca-nsg-mismatch/infra/main.bicep \
    --parameters baseName="$BASE_NAME" location="$LOCATION"

bash labs/appgw-to-internal-aca-nsg-mismatch/trigger.sh
bash labs/appgw-to-internal-aca-nsg-mismatch/verify.sh
bash labs/appgw-to-internal-aca-nsg-mismatch/fix.sh
bash labs/appgw-to-internal-aca-nsg-mismatch/verify.sh
bash labs/appgw-to-internal-aca-nsg-mismatch/cleanup.sh
```

The initial Bicep deployment takes roughly 8-12 minutes (Application Gateway
Standard_v2 dominates). `trigger.sh` adds another ~5 minutes (probe wait
cycles). `fix.sh` adds another ~3 minutes. Total wall-clock: ~20 minutes.

## What "Success" Looks Like

The lab is reproduced when `verify.sh` reports:

| Gate | Meaning | Expected |
|---|---|---|
| A | Baseline backend health = `Healthy` | `true` |
| B | Broken backend health contains `Unhealthy` | `true` |
| C | Broken rule 100 Destination = `<staticIp>/32` | `true` |
| D | Fixed backend health = `Healthy` (after `fix.sh`) | `true` |
| E | Fixed rule 100 Destination = `10.0.2.0/23` (CAE CIDR) | `true` |

Verdict transitions: `HYPOTHESIS_NOT_CONFIRMED` (before `trigger.sh` completes)
→ `HYPOTHESIS_CONFIRMED` (after `trigger.sh`) → `HYPOTHESIS_CONFIRMED` + `falsification = FIX_VERIFIED` (after `fix.sh`).

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| Application Gateway Standard_v2 (autoscale 1-2 instances) | ~$0.36 / hour + ~$0.008 / capacity-unit-hour |
| Container Apps environment (workload profiles, 1 Consumption replica) | <$0.03 / hour |
| Log Analytics workspace (PerGB2018) | negligible for a 30-minute run |
| Public IP (Standard) | ~$0.004 / hour |
| **Total for a 20-30 minute run** | **~$0.20 - $0.50** |

Application Gateway dominates the cost. Always run `cleanup.sh` immediately
after capturing evidence.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/appgw-to-internal-aca-nsg-mismatch.md`
- Playbook: `docs/troubleshooting/playbooks/ingress-and-networking/appgw-to-internal-aca-nsg-destination.md`
- Platform: `docs/platform/networking/application-gateway-integration.md`
