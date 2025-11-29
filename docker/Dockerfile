# =============================================================================
# Privacy Router - AmneziaWG VPN Client
# =============================================================================
# Multi-arch Docker image for AmneziaWG VPN gateway
# Supports: amd64, arm64 (Raspberry Pi 4/5)
#
# Based on amneziawg-go (userspace implementation - no kernel module required)
# =============================================================================

FROM golang:1.24-alpine AS builder

# Install build dependencies (git, make, C compiler for amneziawg-tools)
RUN apk add --no-cache git make build-base linux-headers

# Build amneziawg-go from source
WORKDIR /build
RUN git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-go.git && \
    cd amneziawg-go && \
    make && \
    cp amneziawg-go /usr/local/bin/

# Build amneziawg-tools
RUN git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-tools.git && \
    cd amneziawg-tools/src && \
    make && \
    cp wg /usr/local/bin/amneziawg

# =============================================================================
# Runtime image
# =============================================================================
FROM alpine:3.20

LABEL maintainer="Privacy Router Project"
LABEL description="AmneziaWG VPN Client with kill switch for privacy routing"
LABEL org.opencontainers.image.source="https://github.com/your-repo/privacy-router"

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    iptables \
    ip6tables \
    iproute2 \
    curl \
    bind-tools \
    conntrack-tools \
    procps \
    && rm -rf /var/cache/apk/*

# Copy built binaries from builder
COPY --from=builder /usr/local/bin/amneziawg-go /usr/local/bin/
COPY --from=builder /usr/local/bin/amneziawg /usr/local/bin/

# Create directories
RUN mkdir -p /etc/amneziawg /opt/scripts /var/log

# Copy scripts (mounted at runtime, but set permissions)
COPY scripts/entrypoint.sh /opt/scripts/
COPY scripts/healthcheck.sh /opt/scripts/
COPY scripts/watchdog.sh /opt/scripts/
COPY scripts/test-suite.sh /opt/scripts/
COPY scripts/quick-test.sh /opt/scripts/

# Make scripts executable
RUN chmod +x /opt/scripts/*.sh

# Environment defaults
ENV VPN_IP="" \
    VPN_ENDPOINT_IP="" \
    VPN_ENDPOINT_PORT="51820" \
    LAN_SUBNET="192.168.1.0/24" \
    WATCHDOG_ENABLED="true" \
    WATCHDOG_INTERVAL="30" \
    WATCHDOG_FAIL_THRESHOLD="3" \
    PROBE_TARGETS="1.1.1.1 8.8.8.8 9.9.9.9" \
    TZ="UTC"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /opt/scripts/healthcheck.sh

# Expose ports
# DNS (AdGuard runs in same network namespace)
EXPOSE 53/udp 53/tcp
# AdGuard Web UI
EXPOSE 3000/tcp

ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
