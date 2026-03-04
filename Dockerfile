## NOTE: to retain configuration; mount a Docker volume, or use a bind-mount, on /var/lib/zerotier-one
FROM debian:bookworm AS builder

ARG ZT_VERSION=1.14.2

RUN apt-get update && apt-get install -y curl gnupg ca-certificates wget apt-transport-https

RUN curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/main/doc/contact%40zerotier.com.gpg' | gpg --import && \
    if z=$(curl -s 'https://install.zerotier.com/' | gpg); then echo "$z" | bash; fi

RUN apt-get update && apt-cache policy zerotier-one

RUN apt-get install -y zerotier-one=${ZT_VERSION} || \
    apt-get install -y zerotier-one

# Install runtime dependencies in builder and collect their files into /runtime-deps
RUN apt-get install -y --no-install-recommends iproute2 iputils-ping libssl3 procps && \
    mkdir -p /runtime-deps && \
    PKGS="iproute2 iputils-ping libssl3 procps" && \
    ALL_PKGS=$(echo "$PKGS" | xargs -n1 | sort -u) && \
    DEPS=$(for p in $ALL_PKGS; do apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$p" 2>/dev/null; done | grep '^\w' | sort -u) && \
    ALL_PKGS=$(printf '%s\n%s' "$ALL_PKGS" "$DEPS" | sort -u) && \
    for pkg in $ALL_PKGS; do \
        dpkg -L "$pkg" 2>/dev/null | while read -r f; do \
            if [ -f "$f" ] && [ ! -d "$f" ]; then \
                dir=$(dirname "$f"); \
                mkdir -p "/runtime-deps${dir}"; \
                cp -aL "$f" "/runtime-deps${f}" 2>/dev/null || true; \
            fi; \
        done; \
    done

FROM debian:bookworm-slim
LABEL author="zvyzu"
LABEL description="Containerized ZeroTier One for use on CoreOS or other Docker-only Linux hosts."

# ZeroTier relies on UDP port 9993
EXPOSE 9993/udp

# Copy runtime dependency files collected from builder
COPY --from=builder /runtime-deps/ /
RUN ldconfig

RUN mkdir -p /var/lib/zerotier-one
COPY --from=builder /usr/sbin/zerotier-cli /usr/sbin/zerotier-cli
COPY --from=builder /usr/sbin/zerotier-idtool /usr/sbin/zerotier-idtool
COPY --from=builder /usr/sbin/zerotier-one /usr/sbin/zerotier-one

COPY startup.sh /startup.sh

RUN chmod 0755 /startup.sh
ENTRYPOINT ["/startup.sh"]
