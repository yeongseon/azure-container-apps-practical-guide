FROM mcr.microsoft.com/cbl-mariner/base/core:2.0

# Tools the diag.sh script depends on. ca-certificates is included so
# the image can be reused for HTTPS-based follow-up tests if needed.
RUN tdnf install -y \
        bash \
        ca-certificates \
        coreutils \
        jq \
        procps-ng \
    && tdnf clean all

COPY diag.sh /usr/local/bin/diag.sh
RUN chmod +x /usr/local/bin/diag.sh

# Keep the container alive so `az containerapp exec` can invoke diag.sh
# on demand. We deliberately avoid a daemon process; the container does
# nothing except wait, which keeps CPU/memory pressure off the scheduler
# during scale tests.
ENTRYPOINT ["/bin/bash", "-c", "trap 'exit 0' TERM; while true; do sleep 30 & wait $!; done"]
