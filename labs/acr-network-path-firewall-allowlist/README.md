# Lab: ACR Network Path A — Firewall Allowlist

Reproduce **Scenario A** from
[ACR Network Path Selection](../../docs/platform/networking/acr-network-path-selection.md):
the Container Apps replica reaches ACR over ACR's **public** FQDN, but
that egress is forced through an Azure Firewall whose SNAT public IP
is the **only** entry in ACR's `networkRuleSet.ipRules` allowlist. The
selected-networks IP rule on ACR is therefore keyed on the **firewall's
outbound public IP**, NOT on any replica IP (replicas have no public
IP of their own; their RFC1918 internal IPs are invisible to ACR's
firewall layer once SNAT'd).

**Empirical finding (this lab, see Observed Evidence in the lab guide):**
toggling the single firewall public IP entry in ACR's `ipRules`
deterministically flips fresh-pull behavior between success and
failure on the replica side. With the firewall PIP in the allowlist,
a new revision pulls v1/v-recover successfully. With the firewall PIP
removed, a new revision pulling v-broken receives HTTP 403 from ACR's
firewall layer and Container Apps surfaces this as a
`provisioningState=Failed` revision while the already-running v1
revision keeps serving traffic from its cached image layers. Re-adding
the firewall PIP restores fresh-pull behavior.

## Why this lab is the first in the series to prove fresh-pull behavior

This is the **first lab in the 5-lab ACR network path series** that
cleanly demonstrates fresh-pull behavior during a broken-window
deployment. The reason is the **auth choice**: this lab uses ACR
**admin credentials** (via `az containerapp registry set --username
--password`), not a managed identity. Labs 2 (private endpoint) and 3
(record-level zone authority) both used managed identity for ACR auth,
which introduces a control-plane token exchange step (CAE control
plane &rarr; ACR for an ACR refresh token) whose network path is
**different from the replica's image-pull path**. That confound made
it impossible to cleanly isolate the network variable under test:
when the broken-window pull failed, the failure could have been
attributable to the control-plane token-exchange call, the replica
data-plane pull, or both.

With admin credentials, the only authentication is a `docker login`
happening **inside the replica's egress path through the firewall**.
The firewall's IP allowlist on ACR is therefore the **single
controlled variable** for the entire experiment, and the falsification
proof is unambiguous: removing the firewall PIP from ACR's allowlist
breaks fresh pulls; re-adding it restores them.

This means Scenario A is the only scenario where the lab can script a
broken-window fresh pull as part of falsification. Labs 2 and 3 used
the layer-3 probe (NXDOMAIN, PE NIC IP) as the falsification proof
instead, with a `## Scope note` calling out the fresh-pull confound.

## Architecture

```text
Container App replica (10.80.0.x in snet-aca)
       │  docker login + image pull over the public ACR FQDN
       │           ↓
       │      egress via default route 0.0.0.0/0 -> Azure Firewall
       ▼
   Azure Firewall (Basic, private IP 10.80.2.4 in AzureFirewallSubnet)
       │  application rule: HTTPS to acr<x>.azurecr.io is ALLOWED
       │  SNAT to the firewall's public IP (e.g., 4.230.x.x)
       │           ↓
       ▼
   ACR Premium (public FQDN, regional data endpoint)
       networkRuleSet.defaultAction = Deny
       networkRuleBypassOptions = None
       ipRules = [<firewall public IP>]   <-- controlled variable
            │
            │  IF firewall PIP IS in ipRules -> 401 (auth challenge) -> docker login OK -> 200 (image manifest + layers)
            │  IF firewall PIP NOT in ipRules -> 403 at ACR firewall layer (before backend)
            ▼
       Image pull SUCCEEDS or FAILS based purely on the IP allowlist

Already-running revision behavior during the broken window:
   Cached image layers in the replica continue to serve traffic. The
   v1 revision's healthState stays Healthy through the entire broken
   window. Only NEW revision pulls (v-broken in this lab) fail.
```

## Structure

```text
labs/acr-network-path-firewall-allowlist/
├── infra/main.bicep            # RG-scoped: VNet + AFW Basic + Firewall Policy + UDR + ACR Premium + CAE + App
├── workload/
│   ├── app.py                  # minimal Flask, / and /health report BUILD_TAG
│   └── Dockerfile              # BUILD_TAG baked as build-arg -> different digest per tag
├── trigger.sh                  # build v1/v-broken/v-recover -> lock down ACR -> deploy v1
├── verify.sh                   # assert revision Healthy + build_tag=v1 + ACR ipRules contains FW PIP
├── falsify.sh                  # remove FW PIP -> v-broken Fails -> v1 still Healthy -> re-add -> v-recover Healthy
├── cleanup.sh                  # az group delete --no-wait
└── README.md                   # this file
```

`main.bicep` ships ACR with `defaultAction=Allow` so that `trigger.sh`
can build all 3 tags via `az acr build` (which pushes from the ACR
Tasks build agent over the public endpoint). After the 3 tags are
built, `trigger.sh` locks ACR down to `defaultAction=Deny` +
`networkRuleBypassOptions=None` + `ipRules=[firewall public IP]`. This
matches a real-world deployment flow: build once in CI, then lock down
the registry and let revisions pull through the firewall.

## Quick Start

```bash
export RG="rg-acr-firewall-allowlist-lab"
export LOCATION="koreacentral"
export BASE_NAME="acrfwallow"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --resource-group "$RG" --name acr-firewall-allowlist \
    --template-file labs/acr-network-path-firewall-allowlist/infra/main.bicep \
    --parameters baseName="$BASE_NAME"

bash labs/acr-network-path-firewall-allowlist/trigger.sh
bash labs/acr-network-path-firewall-allowlist/verify.sh
bash labs/acr-network-path-firewall-allowlist/falsify.sh
bash labs/acr-network-path-firewall-allowlist/cleanup.sh
```

No VM, no SSH, no managed identity for ACR auth. The failure is
injected by removing the firewall's public IP from ACR's network
rule set — a single ARM operation against the ACR resource.

## What "Success" Looks Like

The lab is reproduced when **all** of the following hold:

1. `verify.sh` exits `PASS` — latest revision is `Healthy`, `/`
   returns `build_tag=v1`, and ACR's `networkRuleSet.ipRules`
   contains the firewall public IP as the only allowed IP.
2. `falsify.sh` baseline step — same as (1): v1 revision Healthy,
   build_tag=v1.
3. `falsify.sh` broken step — after `az acr network-rule remove`
   removes the firewall PIP and `az containerapp update` deploys
   v-broken, the v-broken revision has `provisioningState=Failed`
   (or `healthState=Unhealthy`), and the OLD v1 revision is STILL
   `Healthy` with `/` still returning `build_tag=v1`.
4. `falsify.sh` recovery step — after `az acr network-rule add`
   re-adds the firewall PIP and `az containerapp update` deploys
   v-recover, the v-recover revision becomes `Healthy` and `/`
   returns `build_tag=v-recover`.

Steps 2-4 together prove the **IP allowlist on ACR's network rule set
controls fresh-pull behavior** while leaving the already-running
revision's health unaffected. The `v1 Healthy -> v-broken Failed +
v1 still Healthy -> v-recover Healthy` transition with the IP
allowlist as the single controlled variable is the strongest
falsification signal in the entire 5-lab series — it is the only
scenario where the broken-window fresh pull cleanly attributes
failure to a single, well-defined cause.

## Estimated Cost

| Resource | Approx. cost (Korea Central) |
|---|---|
| Azure Firewall Basic + 2 public IPs (data + mgmt) | ~$24 / day |
| ACR Premium | $1.67 / day |
| Container Apps (1 replica, Consumption profile) | <$0.10 / hour |
| Log Analytics | <$0.10 for the lab window |
| **Total for a 2-3 hour run** | **~$3-4** |

The firewall dominates the cost — leave it running only for the
duration of the experiment and tear down with `cleanup.sh`
immediately after capturing evidence. NAT Gateway is NOT a valid
substitute for this lab: NAT Gateway also SNATs egress to a single
public IP, but the lab thesis specifically requires the egress to
flow through a stateful firewall whose application-layer rules
allow only specific FQDNs. Substituting NAT Gateway would change
the topology and destroy the experimental control.

## See Also

- Lab guide: `docs/troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md`
- Platform: `docs/platform/networking/acr-network-path-selection.md`
- Related lab: `labs/acr-network-path-pe-direct/` (Scenario B —
  the private-endpoint topology that is the realistic alternative
  to this lab's public-with-firewall topology)
- Related lab: `labs/acr-network-path-dns-forwarder-bypass/`
  (Scenario E — resolver-topology failure on the private path)
- Related lab: `labs/acr-network-path-record-split-brain/`
  (Scenario D — record-level zone authority on the private path)
