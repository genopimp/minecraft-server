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

Accept the [Minecraft EULA](https://aka.ms/MinecraftEULA) (`EULA=TRUE` in the template).

Configure everything from the **Docker** tab form (world name, allow list, difficulty, ports). Do not use Compose Manager and this template at the same time for the same appdata folder.

### Add the template to the Unraid UI

**Option A — user template (fastest)**

On the Unraid box:

```bash
wget -O /boot/config/plugins/dockerMan/templates-user/my-minecraft-server.xml \
  https://raw.githubusercontent.com/genopimp/minecraft-server/main/minecraft-server.xml
```

Then: **Docker → Add Container → Template dropdown → `minecraft-server`**.

**Option B — template repository**

1. **Settings → Docker** → enable **Template authoring mode** if it is off.
2. **Docker → Add Container** → at the bottom, **Template Repositories**.
3. Add:

   `https://github.com/genopimp/minecraft-server`

4. Apply, then **Add Container** and pick `minecraft-server`.

Fill the form (defaults are fine for a first run):

| Field | Typical value |
|---|---|
| World Data | `/mnt/user/appdata/minecraft-server` |
| Game Port IPv4 | `19132` UDP |
| EULA | `TRUE` |
| Version | `LATEST` |
| Level Name | `Bedrock level` (must match the world folder you copy) |
| Enable Allow List | `true` |
| Allow List Users | **leave empty** if you copied `allowlist.json` |

Apply. First start downloads the current official BDS zip (~90 MB).

If GHCR is private: GitHub → Packages → `minecraft-server` → Package settings → Public. Unraid then needs a GitHub token under Docker Hub logins, or make the package public.

Forward **UDP 19132** on the router. In Minecraft for Windows: Play → Servers → Add server → `unraid-ip` port `19132`.

### Compose Manager (optional)

Only if you prefer compose instead of the Docker tab template:

```bash
mkdir -p /mnt/user/appdata/minecraft-server
# copy unraid/docker-compose.yml into that directory
cd /mnt/user/appdata/minecraft-server
docker compose pull
docker compose up -d
docker compose logs -f
```

### Stay current

Restart after any Minecraft for Windows update:

```bash
docker restart minecraft
```

Optional daily restart (User Scripts, ~05:00): `unraid/daily-restart.sh`.

### Admin console (in-container)

The dedicated-server process has a full operator console on stdin (cheats for in-game players are separate). The image runs BDS inside tmux so you can attach without stopping the world.

**Unraid:** Docker tab → `minecraft-server` → **Console**, then:

```bash
mc-console
```

You see live logs and can type commands (`help`, `list`, `say hello`, `op <gamertag>`, `time set day`, `gamerule ...`). Detach with **Ctrl-b** then **d**. Do not Ctrl-C; that can stop the server.

One-shot from Unraid Console or SSH:

```bash
mc-cmd say hello
mc-cmd list
mc-cmd op SomeGamertag
```

From another host:

```bash
docker exec -it minecraft-server mc-console
docker exec minecraft-server mc-cmd say hello
```

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
