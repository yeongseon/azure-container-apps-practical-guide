FROM mcr.microsoft.com/cbl-mariner/base/core:2.0

RUN tdnf install -y \
        bash \
        ca-certificates \
        curl \
        jq \
        coreutils \
    && tdnf clean all

COPY sample.sh /usr/local/bin/sample.sh
RUN chmod +x /usr/local/bin/sample.sh

ENTRYPOINT ["/usr/local/bin/sample.sh"]
