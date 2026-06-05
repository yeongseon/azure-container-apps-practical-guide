#!/usr/bin/env bash
# Rebuild the metrics-load-test infrastructure end-to-end.
#
# Usage:
#   ./rebuild.sh
#
# Produces:
#   - Resource group: rg-aca-basics-d38538
#   - Consumption environment: cae-basics-d38538
#   - Workload-profile environment: cae-wp-d38538 (D4 profile, for NodeCount)
#   - ACR: acrbasicsd38538
#   - 4 Docker images via az acr build
#   - 8 Container Apps (all with --min-replicas 2):
#       ca-loadtest-d38538  (Flask public ingress)
#       ca-crashloop-d38538 (OOM-by-design, no ingress)
#       ca-dotnet-d38538    (existing .NET sample for narrative continuity)
#       ca-res-caller       (intra-env caller, no ingress)
#       ca-res-503          (returns 503, internal ingress + res-503 policy)
#       ca-res-slow         (4s slow responses, internal ingress + res-slow policy)
#       ca-res-pool         (5s slow, internal ingress + res-pool policy)
#       ca-res-blackhole    (TCP listen no accept, internal ingress + res-blackhole policy)
#
# After this completes, run:
#   ./run-load.sh   # sustained 30-min load against ca-loadtest

set -euo pipefail

RG="rg-aca-basics-d38538"
LOCATION="koreacentral"
ACR="acrbasicsd38538"
ENV_CONS="cae-basics-d38538"
ENV_WP="cae-wp-d38538"
LAW="law-aca-basics-d38538"

echo "==> [1/9] Create resource group"
az group create --name "$RG" --location "$LOCATION" --only-show-errors -o none

echo "==> [2/9] Create Log Analytics workspace"
az monitor log-analytics workspace create \
    --resource-group "$RG" \
    --workspace-name "$LAW" \
    --location "$LOCATION" \
    --only-show-errors -o none
LAW_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RG" --workspace-name "$LAW" \
    --query customerId -o tsv)
LAW_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --resource-group "$RG" --workspace-name "$LAW" \
    --query primarySharedKey -o tsv)

echo "==> [3/9] Create Container Apps environments (consumption + workload profile)"
az containerapp env create \
    --resource-group "$RG" \
    --name "$ENV_CONS" \
    --location "$LOCATION" \
    --logs-destination log-analytics \
    --logs-workspace-id "$LAW_ID" \
    --logs-workspace-key "$LAW_KEY" \
    --only-show-errors -o none

az containerapp env create \
    --resource-group "$RG" \
    --name "$ENV_WP" \
    --location "$LOCATION" \
    --logs-destination log-analytics \
    --logs-workspace-id "$LAW_ID" \
    --logs-workspace-key "$LAW_KEY" \
    --enable-workload-profiles \
    --only-show-errors -o none

az containerapp env workload-profile add \
    --resource-group "$RG" \
    --name "$ENV_WP" \
    --workload-profile-name "d4-profile" \
    --workload-profile-type "D4" \
    --min-nodes 2 --max-nodes 2 \
    --only-show-errors -o none

echo "==> [4/9] Create ACR"
az acr create \
    --resource-group "$RG" \
    --name "$ACR" \
    --sku Basic \
    --admin-enabled true \
    --only-show-errors -o none

echo "==> [5/9] Build 4 images via az acr build"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
az acr build --registry "$ACR" --image metrics-load:v1     --file "$SCRIPT_DIR/Dockerfile"           "$SCRIPT_DIR" --only-show-errors -o none
az acr build --registry "$ACR" --image metrics-caller:v1   --file "$SCRIPT_DIR/Dockerfile.caller"    "$SCRIPT_DIR" --only-show-errors -o none
az acr build --registry "$ACR" --image metrics-crash:v1    --file "$SCRIPT_DIR/Dockerfile.crashloop" "$SCRIPT_DIR" --only-show-errors -o none
az acr build --registry "$ACR" --image metrics-blackhole:v1 --file "$SCRIPT_DIR/Dockerfile.blackhole" "$SCRIPT_DIR" --only-show-errors -o none

ACR_LOGIN=$(az acr show --name "$ACR" --query loginServer -o tsv)
ACR_USER=$(az acr credential show --name "$ACR" --query username -o tsv)
ACR_PASS=$(az acr credential show --name "$ACR" --query passwords[0].value -o tsv)

echo "==> [6/9] Deploy ca-loadtest-d38538 (public ingress, min=2 max=10, HTTP scaler)"
az containerapp create \
    --resource-group "$RG" \
    --name "ca-loadtest-d38538" \
    --environment "$ENV_CONS" \
    --image "${ACR_LOGIN}/metrics-load:v1" \
    --registry-server "$ACR_LOGIN" \
    --registry-username "$ACR_USER" \
    --registry-password "$ACR_PASS" \
    --target-port 8000 \
    --ingress external \
    --cpu 0.5 --memory 1.0Gi \
    --min-replicas 2 --max-replicas 10 \
    --scale-rule-name http-rule \
    --scale-rule-type http \
    --scale-rule-http-concurrency 20 \
    --only-show-errors -o none

echo "==> [7/9] Deploy ca-crashloop-d38538 (OOM-by-design, no ingress, min=2)"
az containerapp create \
    --resource-group "$RG" \
    --name "ca-crashloop-d38538" \
    --environment "$ENV_CONS" \
    --image "${ACR_LOGIN}/metrics-crash:v1" \
    --registry-server "$ACR_LOGIN" \
    --registry-username "$ACR_USER" \
    --registry-password "$ACR_PASS" \
    --cpu 0.25 --memory 0.5Gi \
    --min-replicas 2 --max-replicas 2 \
    --only-show-errors -o none

echo "==> [8/9] Deploy resiliency targets + caller (internal ingress, min=2)"

az containerapp create \
    --resource-group "$RG" --name "ca-res-503" --environment "$ENV_CONS" \
    --image "${ACR_LOGIN}/metrics-load:v1" \
    --registry-server "$ACR_LOGIN" --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
    --target-port 8000 --ingress internal \
    --cpu 0.5 --memory 1.0Gi --min-replicas 2 --max-replicas 2 \
    --only-show-errors -o none

az containerapp create \
    --resource-group "$RG" --name "ca-res-slow" --environment "$ENV_CONS" \
    --image "${ACR_LOGIN}/metrics-load:v1" \
    --registry-server "$ACR_LOGIN" --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
    --target-port 8000 --ingress internal \
    --cpu 0.5 --memory 1.0Gi --min-replicas 2 --max-replicas 2 \
    --only-show-errors -o none

az containerapp create \
    --resource-group "$RG" --name "ca-res-pool" --environment "$ENV_CONS" \
    --image "${ACR_LOGIN}/metrics-load:v1" \
    --registry-server "$ACR_LOGIN" --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
    --target-port 8000 --ingress internal \
    --cpu 0.5 --memory 1.0Gi --min-replicas 2 --max-replicas 2 \
    --only-show-errors -o none

az containerapp create \
    --resource-group "$RG" --name "ca-res-blackhole" --environment "$ENV_CONS" \
    --image "${ACR_LOGIN}/metrics-blackhole:v1" \
    --registry-server "$ACR_LOGIN" --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
    --target-port 8000 --ingress internal --transport tcp \
    --cpu 0.5 --memory 1.0Gi --min-replicas 2 --max-replicas 2 \
    --only-show-errors -o none

az containerapp create \
    --resource-group "$RG" --name "ca-res-caller" --environment "$ENV_CONS" \
    --image "${ACR_LOGIN}/metrics-caller:v1" \
    --registry-server "$ACR_LOGIN" --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
    --cpu 0.5 --memory 1.0Gi --min-replicas 2 --max-replicas 2 \
    --env-vars "CONCURRENCY_PER_TARGET=20" \
    --only-show-errors -o none

echo "==> [9/9] Attach resiliency policies"
az containerapp resiliency create \
    --resource-group "$RG" --container-app-name "ca-res-503" \
    --name "policy-503" --yaml "$SCRIPT_DIR/res-503.yaml" \
    --only-show-errors -o none

az containerapp resiliency create \
    --resource-group "$RG" --container-app-name "ca-res-slow" \
    --name "policy-slow" --yaml "$SCRIPT_DIR/res-slow.yaml" \
    --only-show-errors -o none

az containerapp resiliency create \
    --resource-group "$RG" --container-app-name "ca-res-pool" \
    --name "policy-pool" --yaml "$SCRIPT_DIR/res-pool.yaml" \
    --only-show-errors -o none

az containerapp resiliency create \
    --resource-group "$RG" --container-app-name "ca-res-blackhole" \
    --name "policy-blackhole" --yaml "$SCRIPT_DIR/res-blackhole.yaml" \
    --only-show-errors -o none

echo "==> [extra] Deploy ca-node-anchor to workload-profile env (forces NodeCount=2)"
az containerapp create \
    --resource-group "$RG" --name "ca-node-anchor" --environment "$ENV_WP" \
    --image "mcr.microsoft.com/k8se/quickstart:latest" \
    --target-port 80 --ingress internal \
    --workload-profile-name "d4-profile" \
    --cpu 1.0 --memory 2.0Gi --min-replicas 2 --max-replicas 2 \
    --only-show-errors -o none

LOADTEST_FQDN=$(az containerapp show \
    --resource-group "$RG" --name "ca-loadtest-d38538" \
    --query properties.configuration.ingress.fqdn -o tsv)

echo ""
echo "================================================================"
echo "Rebuild complete."
echo "================================================================"
echo "ca-loadtest public URL: https://$LOADTEST_FQDN"
echo ""
echo "Next steps:"
echo "  1) Update BASE in run-load.sh to https://$LOADTEST_FQDN"
echo "  2) ./run-load.sh   # starts 30-min sustained load"
echo "  3) Wait 30-60min for Azure Monitor metrics to populate"
echo "  4) Capture 17 Portal screenshots"
echo "================================================================"
