# minecraft-server

Vanilla **Minecraft: Java Edition** dedicated server in Docker. On every start it asks Mojang for `latest.release` — the same channel the Windows Java launcher uses — and downloads that official `server.jar` (SHA-1 verified). Restart the container after a client update and the server does not drift.

This is **not** Bedrock / Minecraft for Windows (Microsoft Store). Clients connect with **Minecraft: Java Edition** on port **25565**.

Image: `ghcr.io/genopimp/minecraft-server:latest`

## How version lockstep works

The jar is **not** pinned in the image.

1. Container starts.
2. It reads [Mojang’s version manifest](https://piston-meta.mojang.com/mc/game/version_manifest_v2.json).
3. `VERSION=LATEST` (default) → `latest.release` (today that is the same build the Windows Java launcher calls “Latest release”).
4. It downloads `downloads.server` from `piston-data.mojang.com` and checks the published SHA-1.
5. Cached jars live on the data volume under `versions/<id>/server.jar`. A matching sha1 skips the download.

`VERSION=SNAPSHOT` tracks `latest.snapshot` (only if you also run snapshots in the launcher). Pin a version with `VERSION=26.3`.

Minecraft 26.x needs **Java 25**. If Mojang raises that, the entrypoint refuses to start until you pull a newer image.

The server cannot hot-swap versions. After the Windows launcher updates, **restart this container**. A daily Unraid User Script is included so you never sit more than a day behind.

## Unraid

Accept the [Minecraft EULA](https://aka.ms/MinecraftEULA) (`EULA=TRUE`).

### Compose Manager

1. Put `unraid/docker-compose.yml` at `/mnt/user/appdata/minecraft-server/docker-compose.yml` (or point Compose Manager at this repo).
2. Compose up. First start downloads the current official jar (~60 MB).
3. Forward **TCP+UDP 25565** on the router to the Unraid host.
4. Connect from the Windows Java launcher to `unraid-ip:25565`.

```bash
# on Unraid
mkdir -p /mnt/user/appdata/minecraft-server
# copy unraid/docker-compose.yml into that directory, then:
cd /mnt/user/appdata/minecraft-server
docker compose pull
docker compose up -d
docker compose logs -f
```

### Docker tab (XML template)

Add container → template `unraid/minecraft-server.xml`, or paste repository:

```
ghcr.io/genopimp/minecraft-server:latest
```

Map `/mnt/user/appdata/minecraft-server` → `/data`. Host port `25565` TCP and UDP.

If GHCR shows the package as private after the first Actions run: GitHub → Packages → `minecraft-server` → Package settings → Change visibility → Public.

### Stay current

Restart after any Java launcher update:

```bash
docker restart minecraft
```

Optional daily restart (User Scripts, ~05:00): `unraid/daily-restart.sh`.

## Local

```bash
docker compose up -d --build
```

Data directory: `./data` (override with `MINECRAFT_DATA=`).

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `EULA` | `FALSE` | Must be `TRUE` |
| `VERSION` | `LATEST` | `LATEST`, `SNAPSHOT`, or a manifest id |
| `MEMORY` | `4G` | `-Xmx` (and `-Xms` unless `INIT_MEMORY` is set) |
| `INIT_MEMORY` | `$MEMORY` | `-Xms` |
| `PUID` / `PGID` | `99` / `100` | Unraid `nobody:users` |
| `TZ` | `UTC` | Timezone |
| `MOTD` | | `server.properties` overlay |
| `DIFFICULTY` | | `peaceful` / `easy` / `normal` / `hard` |
| `GAMEMODE` | | `survival` / `creative` / `adventure` / `spectator` |
| `MAX_PLAYERS` | | |
| `ONLINE_MODE` | | `true` for Microsoft / Java accounts |
| `LEVEL_NAME` | `world` | World folder |
| `LEVEL_SEED` | | New worlds only |
| `VIEW_DISTANCE` | | |
| `SIMULATION_DISTANCE` | | |
| `PVP` / `HARDCORE` | | |
| `OPS` | | Comma-separated names → `ops.txt` |
| `WHITELIST` | | Comma-separated names; enables whitelist |
| `ENABLE_RCON` / `RCON_PASSWORD` / `RCON_PORT` | | |
| `BACKUP_ON_UPGRADE` | `true` | Copy the world when the jar version changes |
| `KEEP_BACKUPS` | `2` | Upgrade backups to keep |
| `JVM_OPTS` | | Extra JVM flags |
| `FETCH_ONLY` | `false` | Download/verify jar and exit (CI) |

Give the container more RAM than `MEMORY` (compose uses `mem_limit: 6g` for a 4G heap).

## Ports

- `25565/tcp` — game
- `25565/udp` — query
- `25575/tcp` — RCON (off unless you set a password)

## Update the Unraid host after a git push

On the Unraid box:

```bash
docker pull ghcr.io/genopimp/minecraft-server:latest
docker restart minecraft
docker logs -f minecraft | head
```

Or, if you run the compose file:

```bash
cd /mnt/user/appdata/minecraft-server
docker compose pull
docker compose up -d
docker compose logs --tail 50
```

Confirm the log line `Vanilla <version> (release)` matches **Latest release** in the Windows Java launcher. Point the client at `unraid-ip:25565`.
