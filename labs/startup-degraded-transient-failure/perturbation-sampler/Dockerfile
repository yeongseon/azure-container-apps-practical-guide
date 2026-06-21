# High-frequency perturbation sampler image for startup-degraded-transient-failure lab.
#
# Goals:
#   - Identical base + package set as the audit sidecar so behavior is
#     comparable across both samplers.
#   - Runs sample.sh as PID 1; the Container Apps Job runtime honors
#     SAMPLE_DURATION_SECONDS by simply letting the script return.
#
# Build / push:
#   az acr build --registry $ACR --image startup-degraded/perturbation-sampler:latest .

FROM mcr.microsoft.com/cbl-mariner/base/core:2.0

RUN tdnf install -y \
        bash \
        curl \
        jq \
        coreutils \
    && tdnf clean all

WORKDIR /sampler
COPY sample.sh /sampler/sample.sh
RUN chmod +x /sampler/sample.sh

ENTRYPOINT ["/sampler/sample.sh"]
