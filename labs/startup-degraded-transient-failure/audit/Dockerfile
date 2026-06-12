# Stage B audit sidecar image.
#
# Goals:
#   - Mariner base for parity with the Stage A audit image.
#   - Pins bash, curl, jq, coreutils so the JSON emission path is stable.
#   - Runs sample.sh as PID 1 so the Container Apps Job runtime receives
#     SIGTERM during graceful termination.
#
# Build / push:
#   az acr build --registry $ACR --image startup-degraded/audit:latest .

FROM mcr.microsoft.com/cbl-mariner/base/core:2.0

RUN tdnf install -y \
        bash \
        curl \
        jq \
        coreutils \
    && tdnf clean all

WORKDIR /audit
COPY sample.sh /audit/sample.sh
RUN chmod +x /audit/sample.sh

ENTRYPOINT ["/audit/sample.sh"]
