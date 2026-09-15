FROM eclipse-temurin:25-jre-jammy

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        tini \
        tzdata \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/fetch-vanilla.sh scripts/entrypoint.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/fetch-vanilla.sh /usr/local/bin/entrypoint.sh \
    && mkdir -p /data

ENV EULA=FALSE \
    VERSION=LATEST \
    MEMORY=4G \
    PUID=99 \
    PGID=100 \
    TZ=UTC \
    DATA_DIR=/data \
    BACKUP_ON_UPGRADE=true \
    KEEP_BACKUPS=2

WORKDIR /data
VOLUME ["/data"]
EXPOSE 25565/tcp 25565/udp 25575/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=5 \
    CMD bash -c 'echo > /dev/tcp/127.0.0.1/25565' || exit 1

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
