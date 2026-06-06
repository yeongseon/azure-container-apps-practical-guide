# Lab: ACR Network Path C — PE with Forced Inspection

Reproduce **Scenario C** from
[ACR Network Path Selection](../../docs/platform/networking/acr-network-path-selection.md):
ACR is exposed only via a Private Endpoint (PE), the Container Apps
subnet has a UDR forcing default-route egress to an Azure Firewall for
inspection, but the firewall is **silently bypassed** for ACR traffic
unless the UDR also has **explicit /32 routes for each PE NIC IP**.

**Empirical finding (this lab, see Observed Evidence in the lab guide):**
toggling the /32 UDR routes for the PE NIC IPs deterministically flips
the firewall's visibility into ACR traffic. With the /32 routes
present, every `docker pull` from the Container App appears in
`AZFWApplicationRule` with the ACR FQDN. With the /32 routes removed,
pulls still succeed (replica becomes Healthy, `/` returns the expected
`build_tag`), but `AZFWApplicationRule` records **zero** new entries
for the ACR FQDN — the inspection NVA is silently bypassed via the
system-injected /32 route for the PE.

## Why this lab is structurally different from Labs 1 and 4

Labs 1 (Scenario B: PE direct) and 4 (Scenario A: firewall allowlist)
both demonstrated a failure mode where the **pull itself fails**: in
Lab 1, the broken DNS forwarder produced an NXDOMAIN; in Lab 4,
removing the firewall PIP from ACR's allowlist produced an HTTP 403.
In both cases the lab's primary signal was a visibly failed revision.

Scenario C does not produce a failed revision. The pulls succeed in
**both** the bypass case and the recover case. The variable that
differs is not pull success — it is whether the inspection firewall
**sees** the pull happen. The lab's primary signal is therefore the
**silence** in `AZFWApplicationRule` during the bypass window, paired
with the **presence** of the same rows during the baseline and
recovery windows.

This matters operationally because it is the worst-case-for-detection
failure mode for a security team: an FQDN-based block / audit /
inspection policy at the firewall has been silently disabled by a
routing change that looks like it should be irrelevant (no /32 routes
were touched, just the default route → firewall stayed). The
operator's mental model says "default route still goes through the
firewall, so all egress is inspected"; reality says "default route
loses to system /32 route for the PE, so PE traffic is not inspected".

## Architecture

```text
Container App replica (10.90.0.x in snet-aca)
       │  docker login + image pull over https://acr<x>.azurecr.io
       │  -> Azure DNS resolves to PE NIC IP (e.g. 10.90.2.4)
       │  -> longest-prefix match against route table:
       │       /32 route present?   pkt -> firewall private IP -> PE NIC
       │       /32 route absent?    pkt -> system /32 route -> PE NIC directly
       ▼
   Route table on snet-aca:
       0.0.0.0/0  -> Azure Firewall private IP   (always present)
       10.90.2.4/32 -> Azure Firewall private IP (controlled variable)
       10.90.2.5/32 -> Azure Firewall private IP (controlled variable)
       │
       │  When /32 routes are present: longest-prefix match picks them,
       │    packet goes through firewall, firewall app rule allows ACR FQDN,
       │    AZFWApplicationRule logs the row.
       │  When /32 routes are absent: system-injected /32 route for the PE
       │    wins, packet goes DIRECTLY to PE NIC, firewall sees nothing,
       │    AZFWApplicationRule has no row, but pull SUCCEEDS.
       ▼
   ACR Premium (publicNetworkAccess=Disabled, PE-only)
       │  PE has NIC IPs for both the global login endpoint and the
       │  regional data endpoint. BOTH must have /32 UDR routes or the
       │  firewall will see only one half of the pull conversation.
       ▼
   Image pull SUCCEEDS in either case. The difference is whether the
   firewall recorded the traffic.

Baseline behavior:
   v1 revision pulled through firewall (with /32 routes) ->
     AZFWApplicationRule has ACR rows for the pull window.
   /32 routes removed, v-bypass deployed ->
     v-bypass revision becomes Healthy and serves v-bypass content.
     AZFWApplicationRule has ZERO new rows for the ACR FQDN since
     the bypass deploy timestamp.
   /32 routes re-added, v-recover deployed ->
     v-recover revision becomes Healthy and serves v-recover content.
     AZFWApplicationRule has at least one new row for the ACR FQDN
     since the recover deploy timestamp.
```

## Structure

```text
labs/acr-network-path-pe-forced-inspection/
├── infra/main.bicep            # RG-scoped: VNet + AFW Basic + Firewall Policy + UDR + ACR Premium + PE + CAE + App
├── workload/
│   ├── app.py                  # minimal Flask, / and /health report BUILD_TAG
│   └── Dockerfile              # BUILD_TAG baked as build-arg -> different digest per tag
├── trigger.sh                  # build 3 tags -> ACR PE-only -> discover PE IPs -> add /32 UDRs -> deploy v1
├── verify.sh                   # assert revision Healthy + build_tag=v1 + ACR PE-only + /32 routes for each PE IP
├── falsify.sh                  # remove /32 UDRs -> v-bypass Healthy + firewall sees 0 ACR rows -> re-add -> v-recover Healthy + firewall sees rows again
├── cleanup.sh                  # az group delete --no-wait
└── README.md                   # this file
```

`main.bicep` ships ACR with `publicNetworkAccess=Enabled` so that
`trigger.sh` can build all 3 tags via `az acr build` (which runs on
ACR Tasks build agents pushing over the public endpoint). After the 3
tags are built, `trigger.sh` sets `publicNetworkAccess=Disabled`,
which forces every subsequent pull through the Private Endpoint. This
matches a real-world deployment flow: build once in CI when the
registry is still publicly accessible, then lock down to PE-only and
let production revisions pull through the PE path.

## Quick Start

```bash
export RG="rg-acr-pe-forced-inspection-lab"
export LOCATION="koreacentral"
export BASE_NAME="acrpefci"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" --name acr-pe-forced-inspection \
    --template-file labs/acr-network-path-pe-forced-inspection/infra/main.bicep \
    --parameters baseName="$BASE_NAME"

bash labs/acr-network-path-pe-forced-inspection/trigger.sh
bash labs/acr-network-path-pe-forced-inspection/verify.sh
bash labs/acr-network-path-pe-forced-inspection/falsify.sh
bash labs/acr-network-path-pe-forced-inspection/cleanup.sh
```

The failure is injected by removing the /32 UDR entries for the PE NIC
IPs — two ARM operations against the route table. The recovery
re-adds them. The default 0.0.0.0/0 → firewall route is never touched
because it is **not** the controlled variable; the lab thesis is
specifically about why that default route alone is insufficient.

## What "Success" Looks Like

The lab is reproduced when **all** of the following hold:

1. `verify.sh` exits `PASS` — latest revision is `Healthy`, `/`
   returns `build_tag=v1`, ACR `publicNetworkAccess=Disabled`, and the
   route table has an exact `/32` route for every PE NIC IP pointing
   to the firewall private IP.
2. `falsify.sh` baseline visibility step — `AZFWApplicationRule`
   already contains at least one row with `Fqdn ends with .azurecr.io`
   from the trigger.sh pull window. Without baseline visibility, the
   bypass-gate assertion is vacuously true.
3. `falsify.sh` bypass step — after removing the /32 UDR routes and
   deploying v-bypass, the v-bypass revision becomes `Healthy`, `/`
   returns `build_tag=v-bypass`, **AND** `AZFWApplicationRule` shows
   zero new ACR FQDN rows since the bypass deploy timestamp.
4. `falsify.sh` recover step — after re-adding the /32 UDR routes and
   deploying v-recover, the v-recover revision becomes `Healthy`, `/`
   returns `build_tag=v-recover`, **AND** `AZFWApplicationRule` shows
   at least one new ACR FQDN row since the recover deploy timestamp.

Steps 2-4 together prove the **/32 UDR entries control firewall
visibility of PE traffic** while leaving pull success unaffected. The
`baseline (firewall sees ACR) -> bypass (firewall sees nothing,
pull still succeeds) -> recover (firewall sees ACR again)` transition
with the /32 routes as the single controlled variable is the
strongest falsification signal available for the silent-bypass
failure mode. It is the only scenario in the 5-lab ACR network path
series where the failure mode is "successful pull, silent
inspection"; the other four labs all produce visibly failed pulls.

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| Azure Firewall Basic + 2 public IPs (data + mgmt) | ~$24 / day |
| ACR Premium | $1.67 / day |
| Container Apps (1 replica, Consumption profile) | <$0.10 / hour |
| Private Endpoint + Private DNS zone | <$0.10 / day |
| Log Analytics | <$0.10 for the lab window |
| **Total for a 2-3 hour run** | **~$3-4** |

The firewall dominates the cost. Leave it running only for the
duration of the experiment and tear down with `cleanup.sh`
immediately after capturing evidence.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/acr-network-path-pe-forced-inspection.md`
- Platform: `docs/platform/networking/acr-network-path-selection.md`
- Related lab: `labs/acr-network-path-pe-direct/` (Scenario B — PE
  with no NVA inspection, the topology this lab adds inspection on top of)
- Related lab: `labs/acr-network-path-firewall-allowlist/` (Scenario A
  — public ACR through firewall with allowlist, the public-access
  counterpart of this PE topology)
- Related lab: `labs/acr-network-path-dns-forwarder-bypass/` (Scenario
  E — resolver topology failure on the PE path)
- Related lab: `labs/acr-network-path-record-split-brain/` (Scenario D
  — record-level zone authority on the PE path)
