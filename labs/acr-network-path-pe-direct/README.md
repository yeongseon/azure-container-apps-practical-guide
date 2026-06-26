# Lab: ACR Network Path B — Private Endpoint Direct

Reproduce **Scenario B** from
[ACR Network Path Selection](../../docs/platform/networking/acr-network-path-selection.md):
a Container App pulls from an ACR Private Endpoint over the Azure
backbone, with the firewall **not** on the data path.

This is the recommended default for production Container Apps that pull
from ACR. The lab proves the path is real by:

1. Deploying ACR with **public access disabled** so the only working
   path is the Private Endpoint.
2. Verifying that `<registry>.azurecr.io` resolves to a private IP from
   the workload VNet (PE NIC IP, RFC1918).
3. Confirming the new revision becomes `Healthy` after the image switch.
4. **Falsifying**: removing the VNet link to `privatelink.azurecr.io`,
   pushing a new tag, and watching the pull fail; then restoring the
   link and watching the pull recover.

## Architecture

```text
Container App replica  ──►  privatelink.azurecr.io  ──►  ACR PE NIC (RFC1918)
       │                          (Private DNS Zone)            │
       │                                                        │
       └──►  Microsoft Entra ID (managed identity token)        │
                                                                ▼
                                              Azure Container Registry (Premium, public=Disabled)
```

The firewall is **not** on this diagram on purpose. Path B is what you
get when the PE record resolves privately and no UDR forces inspection.

## Structure

```text
labs/acr-network-path-pe-direct/
├── infra/main.bicep            # RG-scoped: VNet + LAW + ACR Premium + PE + DNS zone + CAE + App + AcrPull
├── workload/
│   ├── app.py                  # tiny HTTP server, returns BUILD_TAG
│   └── Dockerfile
├── trigger.sh                  # build image in ACR, switch app to private image
├── verify.sh                   # confirm Healthy + PE NIC resolves to private IP
├── falsify.sh                  # break private DNS, push new tag → must fail, then recover
├── cleanup.sh                  # az group delete --no-wait
└── README.md                   # this file
```

## Quick Start

```bash
export RG="rg-acr-pe-direct-lab"
export LOCATION="koreacentral"
export BASE_NAME="acrpedir"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" --name acr-pe-direct \
    --template-file labs/acr-network-path-pe-direct/infra/main.bicep \
    --parameters baseName="$BASE_NAME"

# Build the private image in ACR and switch the app to it
bash labs/acr-network-path-pe-direct/trigger.sh

# Confirm the PE path is live (Healthy + private IP for ACR FQDN)
bash labs/acr-network-path-pe-direct/verify.sh

# (Optional) Falsify: break the private DNS link, see the pull fail, restore.
bash labs/acr-network-path-pe-direct/falsify.sh

# Tear down
bash labs/acr-network-path-pe-direct/cleanup.sh
```

## What "Success" Looks Like

The lab is reproduced when **all** of the following hold:

1. `verify.sh` exits `PASS` — latest revision is `Healthy` and the ACR
   login FQDN resolves to an RFC1918 IP (PE NIC).
2. `ContainerAppSystemLogs_CL` shows `Reason_s == "PullingImage"` and
   `"PulledImage"` for the private ACR FQDN, with no `ImagePullBackOff`.
3. `falsify.sh` step 3 produces an `ImagePullBackOff` (or unhealthy
   revision) after the VNet link is removed.
4. `falsify.sh` step 5 restores the link and the next revision is
   `Healthy` again.

Steps 3-4 together prove the PE-via-private-DNS path was the cause.

## Phase B Evidence Pack

The reusable Phase B cohort lives in [`evidence/`](evidence/README.md).

- It captures one live Azure reproduction in `koreacentral` with ACR `publicNetworkAccess=Disabled`, the `privatelink.azurecr.io` VNet link removed for H1, and restored for H2.
- The raw cohort contains 12 files (`01`-`12`) plus four derived gate JSONs (`14`-`17`).
- Gate 14 proves the cohort is structurally coherent: canonical files present, parseable, bounded in one UTC window, same lineage, and unchanged PE NIC IPs.
- Gate 15 proves H1 really failed: the pre-fix link list is empty, ACR public access stayed `Disabled`, `ImagePullUnauthorized` surfaced for `v-broken`, and at least one `v-broken` revision entered a failing state.
- Gate 16 proves H2 really recovered: exactly one VNet link is restored, the latest `v-recover` revision is `Healthy`, the post-fix KQL window shows `PullingImage` then `PulledImage`, and ACR public access still stayed `Disabled`.
- Gate 17 performs the full normalized overlapping H1↔H2 diff and bounds the causal claim to the VNet-to-Private-DNS link, not to public ACR access, PE topology drift, or a different workload lineage.

For offline reruns:

| Command | Why it is used |
|---|---|
| `cd labs/acr-network-path-pe-direct/` | Enters the lab directory so relative evidence paths resolve correctly. |
| `bash verify.sh` | Recomputes Gate 14 through Gate 17 from committed evidence without touching Azure. |

```bash
cd labs/acr-network-path-pe-direct/
bash verify.sh
```

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| ACR Premium | $1.67 / day |
| Log Analytics | <$0.10 for the lab window |
| Private Endpoint | $0.01 / hour |
| Container Apps (1 replica, Consumption profile) | <$0.10 / hour |
| **Total for a 2-3 hour run** | **~$1-2** |

Tear down with `cleanup.sh` immediately after capturing evidence.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/acr-network-path-pe-direct.md`
- Platform: `docs/platform/networking/acr-network-path-selection.md`
- Related lab: `labs/acr-pull-failure/` (covers tag/auth/manifest errors
  — this lab is purely about network path topology)
