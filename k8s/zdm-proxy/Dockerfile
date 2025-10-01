# Dockerfile for ZDM Proxy ARM64
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download and install ZDM proxy ARM64 binary
ARG ZDM_VERSION=v2.3.4
ADD https://github.com/datastax/zdm-proxy/releases/download/${ZDM_VERSION}/zdm-proxy-linux-arm64-${ZDM_VERSION}.tgz /tmp/zdm-proxy.tgz

# Extract and install ZDM proxy
RUN cd /tmp && \
    tar -xzf zdm-proxy.tgz && \
    mv zdm-proxy-${ZDM_VERSION} /usr/local/bin/zdm-proxy && \
    chmod +x /usr/local/bin/zdm-proxy && \
    rm -rf zdm-proxy.tgz LICENSE

# Create non-root user
RUN useradd -r -s /bin/false zdm

# Set working directory
WORKDIR /app

# Switch to non-root user
USER zdm

# Expose ZDM proxy port
EXPOSE 9042

# Run ZDM proxy
ENTRYPOINT ["/usr/local/bin/zdm-proxy"]