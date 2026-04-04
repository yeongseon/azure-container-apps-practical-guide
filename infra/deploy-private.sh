#!/bin/bash
set -euo pipefail

echo "============================================"
echo "Azure Container Apps - Private Endpoint Deploy"
echo "============================================"
echo ""
echo "This script deploys Container Apps with:"
echo "  • VNet Integration"
echo "  • Key Vault with Private Endpoint"
echo "  • Storage Account with Private Endpoint"
echo "  • Managed Identity for secure access"
echo ""

# Load environment variables
if [ -f .env ]; then
  echo "📁 Loading configuration from .env file..."
  set -a
  source .env
  set +a
else
  echo "⚠️  .env file not found. Using default values..."
fi

RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-"rg-container-apps-private"}
LOCATION=${LOCATION:-"koreacentral"}
BASE_NAME=${BASE_NAME:-"pycontainer"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
MIN_REPLICAS=${MIN_REPLICAS:-1}
MAX_REPLICAS=${MAX_REPLICAS:-3}
INTERNAL_ONLY=${INTERNAL_ONLY:-false}

echo "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Location: $LOCATION"
echo "  Base Name: $BASE_NAME"
echo "  Image Tag: $IMAGE_TAG"
echo "  Min Replicas: $MIN_REPLICAS"
echo "  Max Replicas: $MAX_REPLICAS"
echo "  Internal Only: $INTERNAL_ONLY"
echo ""

read -p "Continue with deployment? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled."
  exit 1
fi

echo ""
echo "Step 1/6: Checking Azure CLI login status..."
if ! az account show > /dev/null 2>&1; then
  echo "❌ Not logged in to Azure. Please run 'az login' first."
  exit 1
fi
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo "✅ Logged in to Azure subscription: $SUBSCRIPTION_NAME"

echo ""
echo "Step 2/6: Creating resource group..."
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --output none
echo "✅ Resource group ready: $RESOURCE_GROUP_NAME"

echo ""
echo "Step 3/6: Deploying infrastructure with Private Endpoints (Bicep)..."
echo "⏱️  This may take 5-10 minutes due to VNet and Private Endpoint setup..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --template-file main-private.bicep \
  --parameters \
    baseName="$BASE_NAME" \
    location="$LOCATION" \
    imageTag="$IMAGE_TAG" \
    minReplicas="$MIN_REPLICAS" \
    maxReplicas="$MAX_REPLICAS" \
    internalOnly="$INTERNAL_ONLY" \
  --output json)

ACR_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.containerRegistryName.value')
ACR_LOGIN_SERVER=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.containerRegistryLoginServer.value')
CONTAINER_APP_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.containerAppName.value')
CONTAINER_APP_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.containerAppUrl.value')
KEY_VAULT_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.keyVaultName.value')
KEY_VAULT_URI=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.keyVaultUri.value')
STORAGE_ACCOUNT_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.storageAccountName.value')
MANAGED_IDENTITY_CLIENT_ID=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.managedIdentityClientId.value')
VNET_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.vnetName.value')

echo "✅ Infrastructure deployed!"

# Save deployment output
cat > .deploy-private-output.env << EOF
# Private Endpoint Deployment Output - Generated at $(date -u +"%Y-%m-%dT%H:%M:%SZ")
RESOURCE_GROUP_NAME=$RESOURCE_GROUP_NAME
VNET_NAME=$VNET_NAME
ACR_NAME=$ACR_NAME
ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER
CONTAINER_APP_NAME=$CONTAINER_APP_NAME
CONTAINER_APP_URL=$CONTAINER_APP_URL
KEY_VAULT_NAME=$KEY_VAULT_NAME
KEY_VAULT_URI=$KEY_VAULT_URI
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME
MANAGED_IDENTITY_CLIENT_ID=$MANAGED_IDENTITY_CLIENT_ID
EOF
echo "📄 Deployment outputs saved to .deploy-private-output.env"

echo ""
echo "Step 4/6: Building and pushing container image..."
az acr login --name "$ACR_NAME"

pushd ../apps/python > /dev/null
docker build -t "$ACR_LOGIN_SERVER/$BASE_NAME:$IMAGE_TAG" .
docker push "$ACR_LOGIN_SERVER/$BASE_NAME:$IMAGE_TAG"
popd > /dev/null
echo "✅ Container image pushed!"

echo ""
echo "Step 5/6: Updating container app with new image..."
az containerapp update \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --image "$ACR_LOGIN_SERVER/$BASE_NAME:$IMAGE_TAG" \
  --output none

echo ""
echo "⏱️  Waiting 30 seconds for container to start..."
sleep 30

echo ""
echo "Step 6/6: Verifying deployment..."

echo "🔍 Testing health endpoint..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$CONTAINER_APP_URL/health" || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
  echo "✅ Application is healthy!"
else
  echo "⚠️  Application returned HTTP $HTTP_STATUS. It may still be starting up."
  echo "   Check logs: az containerapp logs show -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP_NAME"
fi

echo ""
echo "============================================"
echo "✅ Private Endpoint Deployment Completed!"
echo "============================================"
echo ""
echo "Application URL: $CONTAINER_APP_URL"
echo ""
echo "Private Endpoint Resources:"
echo "  VNet: $VNET_NAME"
echo "  Key Vault: $KEY_VAULT_NAME"
echo "  Key Vault URI: $KEY_VAULT_URI"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Managed Identity Client ID: $MANAGED_IDENTITY_CLIENT_ID"
echo ""
echo "Test Private Endpoints (from within container):"
echo "  # Check Key Vault DNS resolution"
echo "  nslookup ${KEY_VAULT_NAME}.vault.azure.net"
echo ""
echo "  # Check Storage DNS resolution"
echo "  nslookup ${STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
echo ""
echo "Useful commands:"
echo "  # View logs"
echo "  az containerapp logs show -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP_NAME"
echo ""
echo "  # Open interactive shell"
echo "  az containerapp exec -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP_NAME --command /bin/bash"
echo ""
echo "  # List revisions"
echo "  az containerapp revision list -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP_NAME"
echo ""
