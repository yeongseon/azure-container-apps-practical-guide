# Source this file in subsequent bash calls to recover env vars
# Generated for fresh full 24h reproduction per Hybrid A (issue #204)
# Public env vars (resource names only — no subscription/tenant/object IDs)
# Local-only IDs (subscription, tenant, LAW customer ID, UAMI principal/client) live in .local/deploy-env.local.sh (gitignored)
export SUBSCRIPTION_NAME="Visual Studio Enterprise Subscription"
export SUFFIX="260612114313"
export RG="rg-aca-zr-lab-260612114313"
export LOCATION="koreacentral"
export BASE_NAME="zrlab"
export EXPIRY_HOURS=48
export ACR_NAME="acrzrlab260612114313"
export AUDIT_IMAGE_TAG="zr-lab/audit:latest"
export ENV_NAME="cae-zrlab-5yi4px"
export LAW_NAME="log-zrlab-5yi4px"
export UAMI_NAME="id-zrlab-5yi4px"
export VNET_NAME="vnet-zrlab-5yi4px"
# To get LAW customer ID for KQL queries (re-fetch locally; never commit):
#   az monitor log-analytics workspace show --resource-group "$RG" --workspace-name "$LAW_NAME" --query customerId --output tsv
# Or source the local-only file if it exists:
LOCAL_ENV="$(dirname "${BASH_SOURCE[0]:-$0}")/.local/deploy-env.local.sh"
[ -f "$LOCAL_ENV" ] && source "$LOCAL_ENV"
