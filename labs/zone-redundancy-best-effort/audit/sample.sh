#!/usr/bin/env bash
# Audit sampler — polls ARM REST API every cron tick and emits one
# ReplicaInventorySample JSON line per subject app to stdout.
#
# ACA's built-in stdout collection ships these to Log Analytics
# under ContainerAppConsoleLogs_CL, so KQL queries can compute
# clustered-churn and recovery metrics directly.
#
# Required env (set by Bicep audit Job resource):
#   AZURE_CLIENT_ID    User-assigned managed identity client ID
#   SUBSCRIPTION_ID    Subscription containing the lab RG
#   RESOURCE_GROUP     Resource group containing the subject apps
#   ENVIRONMENT_NAME   Container Apps environment name (informational)
#   SUBJECT_APPS       Comma-separated list of app names
#   API_VERSION        ARM API version for Microsoft.App resources

set -uo pipefail

: "${AZURE_CLIENT_ID:?required}"
: "${SUBSCRIPTION_ID:?required}"
: "${RESOURCE_GROUP:?required}"
: "${SUBJECT_APPS:?required}"
: "${API_VERSION:=2024-03-01}"

now_iso() { date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"; }

emit_error() {
  local app="$1" stage="$2" detail="$3"
  jq -cn \
    --arg event "ReplicaInventorySample" \
    --arg sampleTime "$(now_iso)" \
    --arg app "$app" \
    --arg revisionName "" \
    --argjson observedReplicaCount 0 \
    --argjson configuredMinReplicas 0 \
    --arg collectionMethod "managementPlaneReplicaList" \
    --arg sampleKind "baseline" \
    --arg resolutionStatus "$stage" \
    --arg resolutionDetail "$detail" \
    '{event:$event, sampleTime:$sampleTime, app:$app, revisionName:$revisionName,
      observedReplicaCount:$observedReplicaCount, configuredMinReplicas:$configuredMinReplicas,
      replicaIds:[], replicaCreatedTimes:[], replicaRunningStates:[],
      collectionMethod:$collectionMethod, sampleKind:$sampleKind,
      resolutionStatus:$resolutionStatus, resolutionDetail:$resolutionDetail}'
}

acquire_token() {
  local endpoint header
  endpoint="${IDENTITY_ENDPOINT:-}"
  header="${IDENTITY_HEADER:-}"

  if [[ -z "$endpoint" || -z "$header" ]]; then
    echo "ERROR: IDENTITY_ENDPOINT / IDENTITY_HEADER not set inside container" >&2
    return 1
  fi

  curl --silent --show-error --fail \
    -H "X-IDENTITY-HEADER: ${header}" \
    "${endpoint}?api-version=2019-08-01&resource=https://management.azure.com/&client_id=${AZURE_CLIENT_ID}" \
    | jq -r '.access_token'
}

list_active_revisions() {
  # Returns a JSON array of revision names with active=true. Callers
  # detect zero/multiple active revisions explicitly so the sample event
  # records the anomaly instead of silently collapsing to the first one.
  local token="$1" app="$2"
  curl --silent --show-error --fail \
    -H "Authorization: Bearer ${token}" \
    "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${app}/revisions?api-version=${API_VERSION}" \
    | jq -c '[.value[] | select(.properties.active == true) | .name]'
}

list_replicas() {
  local token="$1" app="$2" rev="$3"
  curl --silent --show-error --fail \
    -H "Authorization: Bearer ${token}" \
    "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${app}/revisions/${rev}/replicas?api-version=${API_VERSION}"
}

get_min_replicas() {
  local token="$1" app="$2"
  curl --silent --show-error --fail \
    -H "Authorization: Bearer ${token}" \
    "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${app}?api-version=${API_VERSION}" \
    | jq -r '.properties.template.scale.minReplicas // 0'
}

sample_app() {
  local token="$1" app="$2"
  local active_json active_count rev replicas_json min_replicas
  local resolution_status resolution_detail observed_count

  if ! active_json=$(list_active_revisions "$token" "$app"); then
    emit_error "$app" "no_active_revision" "list_active_revisions ARM call failed"
    return
  fi

  active_count=$(echo "$active_json" | jq 'length')

  if [[ "$active_count" -eq 0 ]]; then
    emit_error "$app" "no_active_revision" "ARM returned zero revisions with active=true"
    return
  fi

  if [[ "$active_count" -gt 1 ]]; then
    local names
    names=$(echo "$active_json" | jq -r 'join(",")')
    emit_error "$app" "multiple_active_revisions" "active_count=${active_count} revisions=${names}"
    return
  fi

  rev=$(echo "$active_json" | jq -r '.[0]')

  if ! replicas_json=$(list_replicas "$token" "$app" "$rev"); then
    emit_error "$app" "replicas_fetch_failed" "list_replicas ARM call failed for revision=${rev}"
    return
  fi

  if ! min_replicas=$(get_min_replicas "$token" "$app"); then
    min_replicas=0
  fi

  observed_count=$(echo "$replicas_json" | jq '.value | length')
  resolution_status="ok"
  resolution_detail=""

  if [[ "${min_replicas:-0}" -eq 0 ]]; then
    resolution_status="partial"
    resolution_detail="configuredMinReplicas could not be resolved or is zero"
  elif [[ "$observed_count" -eq 0 ]]; then
    resolution_status="empty_replica_list"
    resolution_detail="ARM replica list returned zero entries for active revision=${rev}"
  fi

  jq -cn \
    --arg event "ReplicaInventorySample" \
    --arg sampleTime "$(now_iso)" \
    --arg app "$app" \
    --arg revisionName "$rev" \
    --argjson configuredMinReplicas "${min_replicas:-0}" \
    --arg collectionMethod "managementPlaneReplicaList" \
    --arg sampleKind "baseline" \
    --arg resolutionStatus "$resolution_status" \
    --arg resolutionDetail "$resolution_detail" \
    --argjson replicas "$(echo "$replicas_json" | jq '[.value[] | {id: .name, createdTime: .properties.createdTime, runningState: .properties.runningState}]')" \
    '{
      event:$event,
      sampleTime:$sampleTime,
      app:$app,
      revisionName:$revisionName,
      observedReplicaCount: ($replicas | length),
      configuredMinReplicas: $configuredMinReplicas,
      replicaIds: [$replicas[].id],
      replicaCreatedTimes: [$replicas[].createdTime],
      replicaRunningStates: [$replicas[].runningState],
      collectionMethod: $collectionMethod,
      sampleKind: $sampleKind,
      resolutionStatus: $resolutionStatus,
      resolutionDetail: $resolutionDetail
    }'
}

main() {
  local token
  IFS=',' read -r -a apps <<< "$SUBJECT_APPS"

  if ! token=$(acquire_token); then
    echo "ERROR: failed to acquire managed identity token" >&2
    for app in "${apps[@]}"; do
      emit_error "$app" "token_acquisition_failed" \
        "IMDS managed identity token request did not return an access_token"
    done
    exit 0
  fi

  for app in "${apps[@]}"; do
    sample_app "$token" "$app"
  done
}

main "$@"
