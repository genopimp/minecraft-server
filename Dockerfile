FROM ubuntu:22.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        libcurl4 \
        python3 \
        tini \
        tzdata \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/fetch-bds.sh scripts/entrypoint.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/fetch-bds.sh /usr/local/bin/entrypoint.sh \
    && mkdir -p /data

ENV EULA=FALSE \
    VERSION=LATEST \
    PUID=99 \
    PGID=100 \
    TZ=UTC \
    DATA_DIR=/data \
    BACKUP_ON_UPGRADE=true \
    KEEP_BACKUPS=2 \
    LEVEL_NAME="Bedrock level"

WORKDIR /data
VOLUME ["/data"]
EXPOSE 19132/udp 19133/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
    CMD bash -c 'kill -0 "$(cat /data/.bedrock.pid 2>/dev/null)"' || exit 1

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
