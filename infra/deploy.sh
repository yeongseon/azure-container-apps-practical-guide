#!/bin/bash
set -euo pipefail

echo "============================================"
echo "Azure Container Apps Python Guide - Deploy"
echo "============================================"
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

RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-"rg-container-apps-python"}
LOCATION=${LOCATION:-"koreacentral"}
BASE_NAME=${BASE_NAME:-"pycontainer"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
MIN_REPLICAS=${MIN_REPLICAS:-0}
MAX_REPLICAS=${MAX_REPLICAS:-3}

echo "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Location: $LOCATION"
echo "  Base Name: $BASE_NAME"
echo "  Image Tag: $IMAGE_TAG"
echo "  Min Replicas: $MIN_REPLICAS"
echo "  Max Replicas: $MAX_REPLICAS"
echo ""

read -p "Continue with deployment? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled."
  exit 1
fi

echo ""
echo "Step 1/5: Checking Azure CLI login status..."
if ! az account show > /dev/null 2>&1; then
  echo "❌ Not logged in to Azure. Please run 'az login' first."
  exit 1
fi
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo "✅ Logged in to Azure subscription: $SUBSCRIPTION_NAME"

echo ""
echo "Step 2/5: Creating resource group..."
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --output none
echo "✅ Resource group ready: $RESOURCE_GROUP_NAME"

echo ""
echo "Step 3/5: Deploying infrastructure (Bicep)..."
echo "⏱️  This may take 3-5 minutes..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --template-file main.bicep \
  --parameters \
    baseName="$BASE_NAME" \
    location="$LOCATION" \
    imageTag="$IMAGE_TAG" \
    minReplicas="$MIN_REPLICAS" \
    maxReplicas="$MAX_REPLICAS" \
  --output json)

ACR_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.containerRegistryName.value')
ACR_LOGIN_SERVER=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.containerRegistryLoginServer.value')
CONTAINER_APP_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.containerAppName.value')
CONTAINER_APP_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.containerAppUrl.value')

echo "✅ Infrastructure deployed!"

# Save deployment output
cat > .deploy-output.env << EOF
# Deployment Output - Generated at $(date -u +"%Y-%m-%dT%H:%M:%SZ")
RESOURCE_GROUP_NAME=$RESOURCE_GROUP_NAME
ACR_NAME=$ACR_NAME
ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER
CONTAINER_APP_NAME=$CONTAINER_APP_NAME
CONTAINER_APP_URL=$CONTAINER_APP_URL
EOF
echo "📄 Deployment outputs saved to .deploy-output.env"

echo ""
echo "Step 4/5: Building and pushing container image..."
az acr login --name "$ACR_NAME"

pushd ../app > /dev/null
docker build -t "$ACR_LOGIN_SERVER/$BASE_NAME:$IMAGE_TAG" .
docker push "$ACR_LOGIN_SERVER/$BASE_NAME:$IMAGE_TAG"
popd > /dev/null
echo "✅ Container image pushed!"

echo ""
echo "Step 5/5: Updating container app with new image..."
az containerapp update \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --image "$ACR_LOGIN_SERVER/$BASE_NAME:$IMAGE_TAG" \
  --output none

echo ""
echo "⏱️  Waiting 30 seconds for container to start..."
sleep 30

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
echo "✅ Deployment Completed!"
echo "============================================"
echo ""
echo "Application URL: $CONTAINER_APP_URL"
echo ""
echo "Useful commands:"
echo "  az containerapp logs show -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP_NAME"
echo "  az containerapp revision list -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP_NAME"
echo ""
