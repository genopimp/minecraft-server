# minecraft-server

Vanilla **Minecraft: Bedrock Edition** dedicated server in Docker. On every start it asks Mojang for the current Linux Bedrock Dedicated Server zip — the **same release** as **Minecraft for Windows** (Microsoft Store / Xbox app) — installs that official binary, and runs it.

This is **not** Java Edition. Clients are Windows Store, Xbox, PlayStation, Switch, iOS, and Android. Port **19132/udp**.

Image: `ghcr.io/genopimp/minecraft-server:latest` (linux/amd64; Unraid)

## How version lockstep works

The BDS zip is **not** pinned in the image.

1. Container starts.
2. It reads Mojang’s download-links API (`serverBedrockLinux`).
3. `VERSION=LATEST` (default) is the current **release** build. Linux and Windows BDS share that version id, which is what the Windows Store client is on.
4. It downloads `https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-<ver>.zip`.
5. Cached zips live on the data volume under `versions/<id>/`. Worlds and `server.properties` are kept across upgrades.

`VERSION=PREVIEW` tracks the beta/preview channel (only if you also run Minecraft Preview). Pin with `VERSION=1.26.51.1`.

The server cannot hot-swap versions. After Minecraft for Windows updates, **restart this container**. A daily Unraid User Script is included so you never sit more than a day behind.

## Unraid

Accept the [Minecraft EULA](https://aka.ms/MinecraftEULA) (`EULA=TRUE`).

### Compose Manager

1. Put `unraid/docker-compose.yml` at `/mnt/user/appdata/minecraft-server/docker-compose.yml`.
2. Compose up. First start downloads the current official zip (~100 MB).
3. Forward **UDP 19132** (and 19133 if you use IPv6) on the router to the Unraid host.
4. In Minecraft for Windows: Play → Servers → Add server → `unraid-ip` port `19132`.

```bash
# on Unraid
mkdir -p /mnt/user/appdata/minecraft-server
cd /mnt/user/appdata/minecraft-server
# copy unraid/docker-compose.yml here, then:
docker compose pull
docker compose up -d
docker compose logs -f
```

### Docker tab (XML template)

Add container from `unraid/minecraft-server.xml`, or repository:

```
ghcr.io/genopimp/minecraft-server:latest
```

Map `/mnt/user/appdata/minecraft-server` → `/data`. Host port **19132 UDP**.

If GHCR shows the package as private after the first Actions run: GitHub → Packages → `minecraft-server` → Package settings → Public.

### Stay current

Restart after any Minecraft for Windows update:

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
| `VERSION` | `LATEST` | `LATEST`, `PREVIEW`, or a BDS id like `1.26.51.1` |
| `PUID` / `PGID` | `99` / `100` | Unraid `nobody:users` |
| `TZ` | `UTC` | Timezone |
| `SERVER_NAME` | | LAN / friends list name |
| `LEVEL_NAME` | `Bedrock level` | World folder under `worlds/` |
| `LEVEL_SEED` | | New worlds only |
| `GAMEMODE` | | `survival` / `creative` / `adventure` |
| `DIFFICULTY` | | `peaceful` / `easy` / `normal` / `hard` |
| `MAX_PLAYERS` | | |
| `ONLINE_MODE` | | `true` = Xbox Live / Microsoft accounts |
| `ALLOW_LIST_USERS` | | Comma-separated gamertags → `allowlist.json` |
| `OPS` | | Comma-separated Xbox XUIDs → `permissions.json` operators |
| `VIEW_DISTANCE` / `TICK_DISTANCE` | | |
| `ALLOW_CHEATS` | | |
| `BACKUP_ON_UPGRADE` | `true` | Copy `worlds/` when the BDS version changes |
| `KEEP_BACKUPS` | `2` | Upgrade backups to keep |
| `FETCH_ONLY` | `false` | Download/install BDS and exit (CI) |

## Ports

- `19132/udp` — game (IPv4)
- `19133/udp` — game (IPv6)

## Update the Unraid host after a git push

On the Unraid box:

```bash
docker pull ghcr.io/genopimp/minecraft-server:latest
docker restart minecraft
docker logs minecraft | head
```

Or, if you run the compose file:

```bash
cd /mnt/user/appdata/minecraft-server
docker compose pull
docker compose up -d
docker compose logs --tail 50
```

Confirm the log line `Bedrock <version> (release)` matches the Windows Store client. Add the server in Minecraft for Windows at `unraid-ip:19132` (UDP).
