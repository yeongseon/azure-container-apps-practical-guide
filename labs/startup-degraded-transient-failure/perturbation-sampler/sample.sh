#!/usr/bin/env bash
# Stage B high-frequency perturbation sampler.
#
# Designed to run as a short Container Apps Job around each perturbation
# event. Polls the ARM REST API every SAMPLE_INTERVAL_SECONDS (default 5s)
# for SAMPLE_DURATION_SECONDS (default 600s) and emits the same two event
# types as the long-running audit sidecar:
#
#   ReplicaInventorySample
#   RevisionStateSample
#
# Plus a third event type unique to this sampler:
#
#   PerturbationWindowMarker - emitted once at job start and once at job
#                              end, with the perturbation_id for KQL join.
#
# Per Oracle Stage B revision #5: a 5-minute audit interval is too coarse
# for a 10-second-bucket transition lab. This sampler closes that gap.
#
# Required environment:
#   SUBSCRIPTION_ID
#   RESOURCE_GROUP
#   CONTAINER_APP_NAMES         Comma-separated subject app names.
#   MANAGED_IDENTITY_CLIENT_ID
#   PERTURBATION_ID             Free-form ID (e.g. rollout-event-3) joined
#                               to the k6 bucket logs in KQL.
#   SAMPLE_INTERVAL_SECONDS     Optional, default 5.
#   SAMPLE_DURATION_SECONDS     Optional, default 600 (10 minutes).

set -euo pipefail

: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID is required}"
: "${RESOURCE_GROUP:?RESOURCE_GROUP is required}"
: "${CONTAINER_APP_NAMES:?CONTAINER_APP_NAMES is required}"
: "${MANAGED_IDENTITY_CLIENT_ID:?MANAGED_IDENTITY_CLIENT_ID is required}"
: "${PERTURBATION_ID:?PERTURBATION_ID is required}"

SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-5}"
SAMPLE_DURATION_SECONDS="${SAMPLE_DURATION_SECONDS:-600}"

IMDS_URL="http://169.254.169.254/metadata/identity/oauth2/token"
ARM_RESOURCE="https://management.azure.com/"

emit() {
  jq --null-input --compact-output \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
    --arg perturbation_id "${PERTURBATION_ID}" \
    --argjson body "$1" \
    '$body + {ts: $ts, perturbation_id: $perturbation_id}'
}

acquire_token() {
  curl --silent --fail \
    --header "Metadata: true" \
    "${IMDS_URL}?api-version=2018-02-01&resource=${ARM_RESOURCE}&client_id=${MANAGED_IDENTITY_CLIENT_ID}" \
    | jq --raw-output '.access_token'
}

sample_replicas() {
  local app_name="$1"
  local token="$2"

  local revisions_url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${app_name}/revisions?api-version=2024-03-01"

  local revisions
  revisions=$(curl --silent --fail \
    --header "Authorization: Bearer ${token}" \
    "${revisions_url}") || return 0

  echo "${revisions}" | jq --compact-output \
    --arg app "${app_name}" \
    '.value[] | {kind: "RevisionStateSample", app: $app, revision: .name, active: .properties.active, replicas: .properties.replicas, traffic_weight: (.properties.trafficWeight // null), provisioning_state: .properties.provisioningState}' \
    | while read -r rev_line; do
        emit "${rev_line}"
      done

  echo "${revisions}" | jq --raw-output '.value[] | .name' | while read -r rev_name; do
    local replicas_detail_url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${app_name}/revisions/${rev_name}/replicas?api-version=2024-03-01"
    local detail
    detail=$(curl --silent --fail \
      --header "Authorization: Bearer ${token}" \
      "${replicas_detail_url}") || continue

    echo "${detail}" | jq --compact-output \
      --arg app "${app_name}" \
      --arg rev "${rev_name}" \
      '.value[] | {kind: "ReplicaInventorySample", app: $app, revision: $rev, replica: .name, running_state: (.properties.runningState // null), created_time: (.properties.createdTime // null)}' \
      | while read -r line; do
          emit "${line}"
        done
  done
}

main() {
  local token
  token=$(acquire_token)

  emit "$(jq --null-input --compact-output --arg phase start '{kind: "PerturbationWindowMarker", phase: $phase}')"

  local end_epoch=$(($(date -u +%s) + SAMPLE_DURATION_SECONDS))
  IFS=',' read -ra APPS <<< "${CONTAINER_APP_NAMES}"

  while [[ $(date -u +%s) -lt ${end_epoch} ]]; do
    for app in "${APPS[@]}"; do
      sample_replicas "${app}" "${token}"
    done
    sleep "${SAMPLE_INTERVAL_SECONDS}"
  done

  emit "$(jq --null-input --compact-output --arg phase end '{kind: "PerturbationWindowMarker", phase: $phase}')"
}

main "$@"
