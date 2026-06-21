# k6 loadgen image for startup-degraded-transient-failure.
#
# Goals:
#   - Pin k6 to a known minor version (image digest also recorded in evidence).
#   - Bake the k6 script INTO the image so the loadgen Job has no external
#     volume dependency (Container Apps Jobs do not expose configmap-style
#     file mounts cleanly).
#   - ENTRYPOINT runs k6 against /scripts/k6-script.js, reading the test
#     parameters from environment variables (SUBJECT_URL, TARGET_RPS,
#     DURATION_SECONDS, PERTURBATION_ID, RUN_ID).
#
# Build / push:
#   az acr build --registry $ACR --image startup-degraded/loadgen:latest .

FROM grafana/k6:0.50.0

COPY k6-script.js /scripts/k6-script.js

ENTRYPOINT ["k6", "run", "--quiet", "/scripts/k6-script.js"]
