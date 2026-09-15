#!/usr/bin/env bash
# Start official Bedrock Dedicated Server after syncing to Mojang's latest Linux build.
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
EULA="${EULA:-FALSE}"
VERSION="${VERSION:-LATEST}"
PUID="${PUID:-99}"
PGID="${PGID:-100}"
FETCH_ONLY="${FETCH_ONLY:-false}"
LEVEL_NAME="${LEVEL_NAME:-Bedrock level}"

cd /

reexec_as_player() {
  if [[ "$(id -u)" != "0" ]]; then
    return 0
  fi
  mkdir -p "$DATA_DIR"
  chown -R "${PUID}:${PGID}" "$DATA_DIR"
  echo "Dropping root (uid=${PUID} gid=${PGID})"
  exec setpriv --reuid="$PUID" --regid="$PGID" --clear-groups -- "$0" "$@"
}

accept_eula() {
  local v
  v="$(echo "$EULA" | tr '[:upper:]' '[:lower:]')"
  if [[ "$v" != "true" ]]; then
    echo "You must accept the Minecraft EULA to run this server:" >&2
    echo "  https://aka.ms/MinecraftEULA" >&2
    echo "Set EULA=TRUE on the container." >&2
    exit 1
  fi
}

set_prop() {
  local key="$1" val="$2" file="${DATA_DIR}/server.properties"
  local escaped
  escaped="$(printf '%s' "$val" | sed 's/[&|\\]/\\&/g')"
  touch "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${escaped}|" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

set_from_env() {
  local env_name="$1" prop="$2"
  local val="${!env_name:-}"
  if [[ -n "$val" ]]; then
    set_prop "$prop" "$val"
  fi
}

apply_properties() {
  [[ -f "${DATA_DIR}/server.properties" ]] || return 0
  set_from_env SERVER_NAME server-name
  set_from_env LEVEL_NAME level-name
  set_from_env LEVEL_SEED level-seed
  set_from_env GAMEMODE gamemode
  set_from_env DIFFICULTY difficulty
  set_from_env MAX_PLAYERS max-players
  set_from_env ONLINE_MODE online-mode
  set_from_env VIEW_DISTANCE view-distance
  set_from_env TICK_DISTANCE tick-distance
  set_from_env ALLOW_CHEATS allow-cheats
  set_from_env DEFAULT_PLAYER_PERMISSION_LEVEL default-player-permission-level
  set_from_env TEXTUREPACK_REQUIRED texturepack-required
  set_from_env SERVER_PORT server-port
  set_from_env SERVER_PORTV6 server-portv6
  set_from_env WHITE_LIST white-list
  set_from_env ALLOW_LIST allow-list
}

write_allowlist() {
  local csv="${1:-}" dest="${DATA_DIR}/allowlist.json"
  if [[ -z "$csv" ]]; then
    return 0
  fi
  python3 - "$csv" "$dest" <<'PY'
import json, sys
raw, dest = sys.argv[1], sys.argv[2]
names = [n.strip() for n in raw.split(",") if n.strip()]
data = [{"ignoresPlayerLimit": False, "name": n} for n in names]
with open(dest, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  if [[ -z "${ALLOW_LIST:-}" && -z "${WHITE_LIST:-}" ]]; then
    set_prop allow-list true
  fi
}

write_ops() {
  local csv="${1:-}" dest="${DATA_DIR}/permissions.json"
  if [[ -z "$csv" ]]; then
    return 0
  fi
  python3 - "$csv" "$dest" <<'PY'
import json, sys
raw, dest = sys.argv[1], sys.argv[2]
vals = [n.strip() for n in raw.split(",") if n.strip()]
data = []
for v in vals:
    if v.isdigit() and len(v) >= 16:
        data.append({"permission": "operator", "xuid": v})
    else:
        print(f"WARN: skipping OPS entry {v!r}; Bedrock permissions.json needs an Xbox XUID", file=sys.stderr)
with open(dest, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

MC_PID=""

stop_server() {
  echo "Caught signal; stopping Bedrock Dedicated Server..."
  if [[ -n "${MC_PID}" ]] && kill -0 "$MC_PID" 2>/dev/null; then
    echo stop >&3 || true
    local i
    for i in $(seq 1 40); do
      kill -0 "$MC_PID" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$MC_PID" 2>/dev/null; then
      echo "Server still running; sending SIGTERM"
      kill -TERM "$MC_PID" 2>/dev/null || true
      sleep 5
    fi
    if kill -0 "$MC_PID" 2>/dev/null; then
      kill -KILL "$MC_PID" 2>/dev/null || true
    fi
    wait "$MC_PID" 2>/dev/null || true
  fi
  exec 3>&- 2>/dev/null || true
}

start_server() {
  local bin console version
  version="$(cat "${DATA_DIR}/.current-version")"
  bin="${DATA_DIR}/bedrock_server"
  if [[ ! -x "$bin" ]]; then
    echo "ERROR: bedrock_server missing at ${bin}" >&2
    exit 1
  fi

  console="${DATA_DIR}/.console"
  rm -f "$console"
  mkfifo "$console"

  echo "Starting Bedrock Dedicated Server ${version}"
  cd "$DATA_DIR"
  export LD_LIBRARY_PATH="${DATA_DIR}"
  "$bin" <>"$console" &
  MC_PID=$!
  echo "$MC_PID" > "${DATA_DIR}/.bedrock.pid"
  exec 3>"$console"
  trap stop_server SIGTERM SIGINT
  set +e
  wait "$MC_PID"
  local rc=$?
  set -e
  exec 3>&- 2>/dev/null || true
  rm -f "$console" "${DATA_DIR}/.bedrock.pid"
  echo "Bedrock Dedicated Server exited (${rc})"
  return "$rc"
}

reexec_as_player "$@"
accept_eula
export DATA_DIR VERSION LEVEL_NAME BACKUP_ON_UPGRADE KEEP_BACKUPS
/usr/local/bin/fetch-bds.sh

if [[ "$(echo "$FETCH_ONLY" | tr '[:upper:]' '[:lower:]')" == "true" ]]; then
  echo "FETCH_ONLY=true; not starting the server"
  exit 0
fi

apply_properties
write_allowlist "${ALLOW_LIST_USERS:-${WHITELIST:-}}"
write_ops "${OPS:-}"

start_server
