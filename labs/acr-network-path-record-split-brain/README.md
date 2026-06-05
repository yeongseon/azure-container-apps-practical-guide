# Lab: ACR Network Path D — Record-Level Zone Authority

Reproduce **Scenario D** from
[ACR Network Path Selection](../../docs/platform/networking/acr-network-path-selection.md):
the resolver path is correct (the Container Apps VNet uses Azure DNS at
`168.63.129.16` by default, Azure DNS sees the VNet link to
`privatelink.azurecr.io`), but the zone CONTENT is incomplete — the
`<registry>.<region>.data` A record is missing.

**Empirical finding (this lab, see Observed Evidence in the lab guide):**
with default Azure DNS in the VNet (no custom DNS forwarder), deleting
the data A record from the linked `privatelink.azurecr.io` zone
produces **NXDOMAIN** (`socket.gaierror: [Errno -2] Name or service not
known`) for the data FQDN, NOT a public-IP fallthrough. Azure Private
DNS treats the linked zone as **authoritative** for that namespace.
The registry FQDN keeps resolving to the PE NIC private IP, and the
already-running revision stays `Healthy` on cached image layers.

True **"registry private, data public" split-brain** in this lab's
sense only occurs if a custom DNS server (BIND with views,
`systemd-resolved` with multi-domain fallback, etc.) is wired to fall
back to public DNS when the conditional forward to Azure DNS returns
NXDOMAIN — a more complex topology that this lab intentionally does
NOT reproduce. See the lab guide §1 for why the simpler NXDOMAIN
result is the more accurate and operationally useful Scenario D
reproduction in the ACA + default-Azure-DNS topology that most
production environments actually run.

Scenario D is the **record-level** DNS failure class. It is distinct
from Scenario E (DNS-topology failure, covered by the sibling
[`acr-network-path-dns-forwarder-bypass`](../acr-network-path-dns-forwarder-bypass/)
lab): Scenario E breaks the resolver path so the entire ACR namespace
resolves publicly (`topology_class=both_public`); Scenario D leaves
the resolver path correct but breaks a single record so only the
affected name fails to resolve (`topology_class=data_nxdomain` in
this lab's topology). Both can produce workload-layer failures
without revision-health impact, but they require different fixes —
fix the forwarder for E, fix the zone record for D — so a lab that
distinguishes them on the wire is operationally useful.

## Why this is a workload-path lab (read before running)

In this Azure Container Apps reproduction, deleting the data A record
produces **no immediate revision-health impact** on the already-running
revision. Empirically, the already-running revision stays `Healthy`
and continues to serve traffic unchanged. What clearly does change is
**what application code sees**: a four-layer probe (DNS → TCP → TLS →
HTTP) run for the data FQDN from inside the replica returns
`gaierror NXDOMAIN` (the DNS layer fails before any TCP/TLS/HTTP layer
runs), while the same probe for the registry login FQDN keeps returning
the PE NIC's RFC1918 IP and reaches the ACR backend.

The lab makes this observable through a `/probe` HTTP endpoint
(`workload/app.py`) that runs the 4-layer probe against **both** the
registry FQDN and the data FQDN and reports `topology_class`:

| `topology_class` | Registry DNS class | Data DNS class | Interpretation |
|---|---|---|---|
| `both_private` | private | private | Scenario B baseline (both records present) |
| `data_nxdomain` | private | NXDOMAIN | **Scenario D in default Azure DNS** (data record missing, Azure DNS returns NXDOMAIN) |
| `split_brain` | private | public | Scenario D in custom-DNS-with-public-fallback topology (NOT reproduced by this lab) |
| `both_public` | public | public | Scenario E or no zone link at all |
| `inverted_split_brain` | public | private | Unusual; resolver-side caching anomaly |
| `registry_nxdomain` | NXDOMAIN | private | Unusual; registry record deleted (not the lab path) |
| `both_nxdomain` | NXDOMAIN | NXDOMAIN | Both records deleted or zone unlinked |

The falsification deletes the data A record, watches `topology_class`
flip from `both_private` to `data_nxdomain`, asserts the already-running
revision stays `Healthy`, then re-creates the record and watches the
class flip back to `both_private`.

The discriminator is the **DNS resolution class on the data endpoint**:
`private` in baseline (PE NIC IP) → `NXDOMAIN` after record deletion →
`private` again after restoration. This single signal is unambiguous,
ACR-specific in context (the data endpoint is the one with the regional
data-record requirement), and impossible to attribute to any other
component in the topology. HTTP status differences are NOT used as the
primary discriminator because the ACR data endpoint returns HTTP 403
on the private path even in baseline (this is the data endpoint's
default response to an unauthenticated `/v2/` probe and is independent
of the zone record state).

This finding matters operationally: in ACA, a missing
`<registry>.<region>.data` record surfaces as workload-layer DNS errors
(failed image-layer downloads, failed application-code calls to the
data endpoint) rather than as `ImagePullBackOff` on existing revisions.
Pull-path observability is therefore not a reliable early-warning
signal for record-level zone-authority failures in this platform.

> **Scope note**: this lab intentionally does not script a "broken-window
> fresh pull" test. With ACR configured for `publicNetworkAccess=Disabled`
> (the realistic production posture this lab models), Container Apps'
> control-plane ACR token exchange is blocked at the ACR firewall for
> reasons unrelated to the missing data record, which would confound the
> variable under test. The layer-3 probe (NXDOMAIN on the data endpoint)
> replaces the broken-window fresh pull as the falsification proof and
> is the strongest, single-component-attribution signal available. See
> the lab guide §"Why we do not script a broken-window fresh pull" for
> details.

## Architecture

```text
Container App replica
       │  app code: 4-layer probe of BOTH ACR_FQDN and ACR_DATA_FQDN
       │           ↓ uses VNet DNS = Azure DNS (default 168.63.129.16)
       ▼
   Azure DNS (168.63.129.16)
       │  sees VNet link to privatelink.azurecr.io
       │  treats the linked zone as AUTHORITATIVE for that namespace
       ▼
   privatelink.azurecr.io (linked Private DNS Zone)
       │
       ├── A <registry>            -> PE NIC IP (registry, 10.70.4.x)   [HELD CONSTANT]
       │                                                                  │
       │                                                                  ▼
       │                                                              ACR registry backend
       │                                                              HTTP 401 (auth challenge)
       │
       └── A <registry>.<region>.data -> PE NIC IP (data, 10.70.4.x)
            HEALTHY: record present  ──────────────────────────────►  ACR data backend
                                                                       HTTP 403 (data endpoint
                                                                       default for unauth /v2/)
            BROKEN:  record DELETED  ──► Azure DNS returns NXDOMAIN
                                          │  (zone is authoritative;
                                          │  no fallthrough to public)
                                          ▼
                                     socket.gaierror in the replica
                                     data endpoint is UNADDRESSABLE
                                     from the application code's POV

Already-running revision behavior during the broken window:
   Already-cached image layers continue to serve traffic. The replica
   does not re-pull or restart during this lab, so revision healthState
   stays Healthy. See lab guide §"Why we do not script a broken-window
   fresh pull" for the scope boundary.
```

The PE NIC is healthy and the resolver path is correct; only the
`<registry>.<region>.data` A record is missing — and Azure DNS faithfully
reports that as NXDOMAIN because the zone is authoritative.

## Structure

```text
labs/acr-network-path-record-split-brain/
├── infra/main.bicep            # RG-scoped: VNet (default Azure DNS) + LAW + ACR Premium + PE + DNS zone + CAE + App + AcrPull
├── workload/
│   ├── app.py                  # /probe returns JSON {registry, data, topology_class} — 4-layer probe per FQDN
│   └── Dockerfile
├── trigger.sh                  # build image in ACR, switch app to private image (sets BUILD_TAG)
├── verify.sh                   # confirm Healthy + /probe returns topology_class=both_private (registry+data both PE NIC)
├── falsify.sh                  # delete data A record → topology_class=data_nxdomain (data NXDOMAIN) → restore → topology_class=both_private
├── cleanup.sh                  # az group delete --no-wait
└── README.md                   # this file
```

`ACR_FQDN` (the registry login FQDN) and `ACR_DATA_FQDN` (the regional
data FQDN, computed in Bicep as `${registryName}.${location}.data.azurecr.io`)
are both injected into the container template by `main.bicep`, so the
`/probe` endpoint knows which two FQDNs to address without recomputing
the region name.

Scenario D does NOT require a custom DNS forwarder VM (unlike Scenario
E), which is why this lab is simpler than the sibling lab — the VNet
just uses default Azure DNS. The NXDOMAIN result on data-record deletion
is a direct consequence of that simplicity: Azure DNS is the only
resolver in the path, the linked zone is authoritative, no fallback
logic exists to convert NXDOMAIN into a public-IP answer.

## Quick Start

```bash
export RG="rg-acr-record-split-brain-lab"
export LOCATION="koreacentral"
export BASE_NAME="acrrecsplitbrain"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" --name acr-record-split-brain \
    --template-file labs/acr-network-path-record-split-brain/infra/main.bicep \
    --parameters baseName="$BASE_NAME"

bash labs/acr-network-path-record-split-brain/trigger.sh
bash labs/acr-network-path-record-split-brain/verify.sh
bash labs/acr-network-path-record-split-brain/falsify.sh
bash labs/acr-network-path-record-split-brain/cleanup.sh
```

No VM, no SSH, no `vmAdminPassword`. The failure is injected through
`az network private-dns record-set a delete` against the lab's own
Private DNS Zone — pure Azure-RBAC, no in-guest commands.

## What "Success" Looks Like

The lab is reproduced when **all** of the following hold:

1. `verify.sh` exits `PASS` — latest revision is `Healthy`, and the
   `/probe` endpoint on the Container App's ingress returns JSON with
   `topology_class=both_private`, the registry IP matches the PE NIC's
   registry-group IP, the data IP matches the PE NIC's data-group IP.
   HTTP status is `401` on registry (auth challenge from ACR backend)
   and `403` on data (default data-endpoint response to unauthenticated
   `/v2/` — both prove the PE path is alive end-to-end).
2. `falsify.sh` baseline step → `topology_class=both_private`.
3. `falsify.sh` broken step (after `az network private-dns record-set a delete`
   on `<registry>.<region>.data`) → `topology_class=data_nxdomain`,
   data DNS class is `null` with `gaierror: [Errno -2] Name or service
   not known`, and the already-running revision is still `Healthy`.
4. `falsify.sh` recovery step (after re-creating the data A record with
   the captured PE NIC IP) → `topology_class=both_private` again.

Steps 2-4 together prove the **zone CONTENT** controls **workload DNS
reachability** while leaving the already-running revision's health
unaffected during the broken window. The `private` → `NXDOMAIN` →
`private` transition on the data endpoint is the strongest single
signal — unambiguous, ACR-specific in context, and impossible to
attribute to any other component in the topology.

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| ACR Premium | $1.67 / day |
| Log Analytics | <$0.10 for the lab window |
| Private Endpoint | $0.01 / hour |
| Container Apps (1 replica, Consumption profile) | <$0.10 / hour |
| **Total for a 2-3 hour run** | **~$1-2** |

No VM cost in this lab (vs. ~$0.05/hour B1s + disk in the sibling
Scenario E lab). Tear down with `cleanup.sh` immediately after capturing
evidence.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/acr-network-path-record-split-brain.md`
- Platform: `docs/platform/networking/acr-network-path-selection.md`
- Related lab: `labs/acr-network-path-pe-direct/` (covers Scenario B —
  the happy-path PE topology this lab silently degrades from at the
  zone-record layer)
- Related lab: `labs/acr-network-path-dns-forwarder-bypass/` (covers
  Scenario E — the resolver-topology variant of the same outcome class;
  same operator-facing silence, different root cause and fix)
