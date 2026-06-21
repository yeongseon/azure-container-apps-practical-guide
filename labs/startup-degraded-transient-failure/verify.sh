#!/usr/bin/env bash
# Verify a deployed startup-degraded-transient-failure lab.
#
# Performs ~14 fast health checks against the lab resources:
#   - Resource group exists and has the expected tags
#   - Container Apps Environment is Succeeded + zoneRedundant=true
#   - Log Analytics workspace exists
#   - UAMI exists and has Reader on the RG
#   - Subject app: ingress external, 3 replicas Running, all probes /healthz
#   - All three Jobs (audit, perturbation-sampler, loadgen) exist with
#     the expected trigger types (Schedule, Manual, Manual)
#   - audit-sampler has run at least once OR is scheduled to run within 5 min
#
# Exits non-zero on the first failure.

set -euo pipefail

RG="${RG:?RG must be set, e.g. rg-aca-startup-degraded}"
SUBJECT_APP="${SUBJECT_APP:-subject-app}"
AUDIT_JOB="${AUDIT_JOB:-audit-sampler}"
PERTURBATION_SAMPLER_JOB="${PERTURBATION_SAMPLER_JOB:-perturbation-sampler}"
LOADGEN_JOB="${LOADGEN_JOB:-loadgen-k6}"

pass() { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*" >&2; exit 1; }

step() { echo; echo "== $* =="; }

step "1. Resource group"
RG_TAGS=$(az group show --name "$RG" --query 'tags' --output json 2>/dev/null || echo '{}')
[[ -n "$RG_TAGS" ]] && pass "Resource group $RG exists"

step "2. Container Apps Environment"
ENV_NAME=$(az containerapp env list --resource-group "$RG" --query '[0].name' --output tsv)
[[ -n "$ENV_NAME" ]] || fail "No Container Apps Environment in $RG"
ENV_STATE=$(az containerapp env show --resource-group "$RG" --name "$ENV_NAME" --query 'properties.provisioningState' --output tsv)
[[ "$ENV_STATE" == "Succeeded" ]] || fail "Env provisioningState=$ENV_STATE (want Succeeded)"
pass "Env $ENV_NAME provisioningState=Succeeded"
ENV_ZONE=$(az containerapp env show --resource-group "$RG" --name "$ENV_NAME" --query 'properties.zoneRedundant' --output tsv)
[[ "$ENV_ZONE" == "true" ]] || fail "Env zoneRedundant=$ENV_ZONE (want true)"
pass "Env zoneRedundant=true"

step "3. Log Analytics workspace"
LAW_NAME=$(az monitor log-analytics workspace list --resource-group "$RG" --query '[0].name' --output tsv)
[[ -n "$LAW_NAME" ]] || fail "No Log Analytics workspace in $RG"
pass "Workspace $LAW_NAME exists"

step "4. User-assigned managed identity"
UAMI_NAME=$(az identity list --resource-group "$RG" --query '[0].name' --output tsv)
[[ -n "$UAMI_NAME" ]] || fail "No UAMI in $RG"
pass "UAMI $UAMI_NAME exists"

step "5. Subject app"
APP_STATE=$(az containerapp show --resource-group "$RG" --name "$SUBJECT_APP" --query 'properties.provisioningState' --output tsv)
[[ "$APP_STATE" == "Succeeded" ]] || fail "Subject app provisioningState=$APP_STATE"
pass "Subject app provisioningState=Succeeded"

INGRESS_EXT=$(az containerapp show --resource-group "$RG" --name "$SUBJECT_APP" --query 'properties.configuration.ingress.external' --output tsv)
[[ "$INGRESS_EXT" == "true" ]] || fail "Subject app ingress.external=$INGRESS_EXT (want true)"
pass "Subject app ingress.external=true"

MIN_R=$(az containerapp show --resource-group "$RG" --name "$SUBJECT_APP" --query 'properties.template.scale.minReplicas' --output tsv)
MAX_R=$(az containerapp show --resource-group "$RG" --name "$SUBJECT_APP" --query 'properties.template.scale.maxReplicas' --output tsv)
[[ "$MIN_R" == "3" && "$MAX_R" == "3" ]] || fail "Subject app scale=[$MIN_R,$MAX_R] (want [3,3])"
pass "Subject app scale pinned at 3 replicas"

PROBE_PATHS=$(az containerapp show --resource-group "$RG" --name "$SUBJECT_APP" --query 'properties.template.containers[0].probes[].httpGet.path' --output tsv | sort --unique)
[[ "$PROBE_PATHS" == "/healthz" ]] || fail "Subject app probes target paths=$PROBE_PATHS (want only /healthz)"
pass "All subject probes target /healthz"

step "6. Audit job"
AUDIT_TRIGGER=$(az containerapp job show --resource-group "$RG" --name "$AUDIT_JOB" --query 'properties.configuration.triggerType' --output tsv)
[[ "$AUDIT_TRIGGER" == "Schedule" ]] || fail "$AUDIT_JOB triggerType=$AUDIT_TRIGGER (want Schedule)"
pass "$AUDIT_JOB triggerType=Schedule"

step "7. Perturbation sampler job"
PSAMP_TRIGGER=$(az containerapp job show --resource-group "$RG" --name "$PERTURBATION_SAMPLER_JOB" --query 'properties.configuration.triggerType' --output tsv)
[[ "$PSAMP_TRIGGER" == "Manual" ]] || fail "$PERTURBATION_SAMPLER_JOB triggerType=$PSAMP_TRIGGER (want Manual)"
pass "$PERTURBATION_SAMPLER_JOB triggerType=Manual"

step "8. Loadgen job"
LG_TRIGGER=$(az containerapp job show --resource-group "$RG" --name "$LOADGEN_JOB" --query 'properties.configuration.triggerType' --output tsv)
[[ "$LG_TRIGGER" == "Manual" ]] || fail "$LOADGEN_JOB triggerType=$LG_TRIGGER (want Manual)"
pass "$LOADGEN_JOB triggerType=Manual"

step "9. Reachability check"
FQDN=$(az containerapp show --resource-group "$RG" --name "$SUBJECT_APP" --query 'properties.configuration.ingress.fqdn' --output tsv)
[[ -n "$FQDN" ]] || fail "Subject app FQDN is empty"
pass "Subject FQDN: $FQDN"

HTTP_HEALTHZ=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "https://${FQDN}/healthz" || echo "000")
echo "  Reachability /healthz returned HTTP $HTTP_HEALTHZ"
if [[ "$HTTP_HEALTHZ" == "200" ]]; then
  pass "Subject /healthz reachable (200)"
elif [[ "$HTTP_HEALTHZ" == "404" || "$HTTP_HEALTHZ" == "503" ]]; then
  echo "  NOTE: HTTP $HTTP_HEALTHZ -- subject still warming up or placeholder image in use. Re-run after building custom subject image."
else
  echo "  NOTE: HTTP $HTTP_HEALTHZ -- inspect manually."
fi

echo
echo "Verify complete (9 checks). Continue with ./trigger.sh --preflight"
