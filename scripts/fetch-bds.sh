#!/usr/bin/env bash
# Resolve and install official Bedrock Dedicated Server (Linux).
# VERSION=LATEST tracks the same release as Minecraft for Windows (Store / Xbox app).
set -euo pipefail

LINKS_URL="${LINKS_URL:-https://net.web.minecraft-services.net/api/v1.0/download/links}"
LINKS_URL_SECONDARY="${LINKS_URL_SECONDARY:-https://net-secondary.web.minecraft-services.net/api/v1.0/download/links}"
DATA_DIR="${DATA_DIR:-/data}"
VERSION="${VERSION:-LATEST}"
USER_AGENT="${USER_AGENT:-Mozilla/5.0 (compatible; genopimp-minecraft-server/1.0)}"
BACKUP_ON_UPGRADE="${BACKUP_ON_UPGRADE:-true}"
KEEP_BACKUPS="${KEEP_BACKUPS:-2}"
LEVEL_NAME="${LEVEL_NAME:-Bedrock level}"

SERVER_VERSION=""
VERSION_TYPE=""
SERVER_URL=""
DOWNLOAD_TYPE=""

curl_json() {
  curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
    -A "$USER_AGENT" \
    -H "Accept: application/json" \
    "$1"
}

curl_bin() {
  curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
    -A "$USER_AGENT" \
    -o "$2" \
    "$1"
}

lookup_url() {
  local dtype="$1" url body found
  for url in "$LINKS_URL" "$LINKS_URL_SECONDARY"; do
    body="$(curl_json "$url" || true)"
    if [[ -z "$body" ]]; then
      continue
    fi
    found="$(jq -er --arg t "$dtype" \
      '.result.links[] | select(.downloadType==$t) | .downloadUrl' <<<"$body" 2>/dev/null || true)"
    if [[ -n "$found" && "$found" != "null" ]]; then
      printf '%s\n' "$found"
      return 0
    fi
  done
  return 1
}

version_from_url() {
  local url="$1"
  if [[ "$url" =~ bedrock-server-([0-9.]+)\.zip ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  echo "ERROR: could not parse version from ${url}" >&2
  return 1
}

replace_version_in_url() {
  local url="$1" ver="$2"
  printf '%s\n' "$url" | sed -E "s/(bedrock-server-)[^/]+(\.zip)/\1${ver}\2/"
}

resolve_version() {
  local latest_url

  case "${VERSION}" in
    LATEST|latest|RELEASE|release)
      DOWNLOAD_TYPE="serverBedrockLinux"
      VERSION_TYPE="release"
      echo "Looking up latest Bedrock Dedicated Server (Linux) from Mojang..."
      latest_url="$(lookup_url "$DOWNLOAD_TYPE")"
      SERVER_URL="$latest_url"
      SERVER_VERSION="$(version_from_url "$latest_url")"
      ;;
    PREVIEW|preview|SNAPSHOT|snapshot)
      DOWNLOAD_TYPE="serverBedrockPreviewLinux"
      VERSION_TYPE="preview"
      echo "Looking up latest Bedrock Dedicated Server preview (Linux) from Mojang..."
      latest_url="$(lookup_url "$DOWNLOAD_TYPE")"
      SERVER_URL="$latest_url"
      SERVER_VERSION="$(version_from_url "$latest_url")"
      ;;
    *)
      DOWNLOAD_TYPE="serverBedrockLinux"
      VERSION_TYPE="release"
      echo "Resolving pinned Bedrock version ${VERSION}..."
      latest_url="$(lookup_url "$DOWNLOAD_TYPE")"
      SERVER_URL="$(replace_version_in_url "$latest_url" "$VERSION")"
      SERVER_VERSION="$VERSION"
      ;;
  esac

  if [[ -z "$SERVER_URL" || -z "$SERVER_VERSION" ]]; then
    echo "ERROR: failed to resolve Bedrock download URL" >&2
    return 1
  fi
}

print_resolve() {
  cat <<EOF
VERSION_ID=${SERVER_VERSION}
VERSION_TYPE=${VERSION_TYPE}
SERVER_URL=${SERVER_URL}
DOWNLOAD_TYPE=${DOWNLOAD_TYPE}
EOF
}

maybe_backup_world() {
  local previous dest world
  previous="$(cat "${DATA_DIR}/.current-version" 2>/dev/null || true)"
  if [[ -z "$previous" || "$previous" == "$SERVER_VERSION" ]]; then
    return 0
  fi
  if [[ "${BACKUP_ON_UPGRADE}" != "true" ]]; then
    echo "Upgrading ${previous} -> ${SERVER_VERSION} (BACKUP_ON_UPGRADE=${BACKUP_ON_UPGRADE})"
    return 0
  fi

  world="${DATA_DIR}/worlds/${LEVEL_NAME}"
  if [[ ! -d "$world" ]]; then
    echo "No world at ${world}; skipping backup"
    return 0
  fi

  dest="${DATA_DIR}/backups/${previous}-$(date -u +%Y%m%dT%H%M%SZ)"
  echo "Backing up world (${previous} -> ${SERVER_VERSION}) to ${dest}"
  mkdir -p "$dest"
  cp -a "${DATA_DIR}/worlds" "$dest/"
  if [[ -f "${DATA_DIR}/server.properties" ]]; then
    cp -a "${DATA_DIR}/server.properties" "$dest/"
  fi

  if [[ "${KEEP_BACKUPS}" =~ ^[0-9]+$ ]] && (( KEEP_BACKUPS > 0 )); then
    # shellcheck disable=SC2012
    ls -1dt "${DATA_DIR}/backups"/* 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -rf
  fi
}

install_from_zip() {
  local zip="$1" tmp
  tmp="$(mktemp -d "${DATA_DIR}/.extract.XXXXXX")"
  echo "Extracting Bedrock Dedicated Server ${SERVER_VERSION}"
  python3 - "$zip" "$tmp" <<'PY'
import sys, zipfile
src, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as zf:
    zf.extractall(dest)
PY

  # Replace the native binary and bundled libraries every upgrade.
  cp -a "${tmp}/bedrock_server" "${DATA_DIR}/bedrock_server"
  chmod +x "${DATA_DIR}/bedrock_server"
  find "$tmp" -maxdepth 1 -name '*.so' -exec cp -a {} "${DATA_DIR}/" \;

  # Seed config only on first install so operator edits survive upgrades.
  if [[ ! -f "${DATA_DIR}/server.properties" && -f "${tmp}/server.properties" ]]; then
    cp -a "${tmp}/server.properties" "${DATA_DIR}/server.properties"
  fi
  if [[ ! -f "${DATA_DIR}/allowlist.json" && -f "${tmp}/allowlist.json" ]]; then
    cp -a "${tmp}/allowlist.json" "${DATA_DIR}/allowlist.json"
  fi
  if [[ ! -f "${DATA_DIR}/permissions.json" && -f "${tmp}/permissions.json" ]]; then
    cp -a "${tmp}/permissions.json" "${DATA_DIR}/permissions.json"
  fi

  # Refresh Mojang content packs; leave worlds/ and custom packs alone.
  local dir
  for dir in resource_packs behavior_packs definitions structures treatments world_templates; do
    if [[ -d "${tmp}/${dir}" ]]; then
      mkdir -p "${DATA_DIR}/${dir}"
      cp -a "${tmp}/${dir}/." "${DATA_DIR}/${dir}/"
    fi
  done

  mkdir -p "${DATA_DIR}/worlds"
  rm -rf "$tmp"
}

install_server() {
  local dir zip
  dir="${DATA_DIR}/versions/${SERVER_VERSION}"
  zip="${dir}/bedrock-server.zip"
  mkdir -p "$dir" "$DATA_DIR"

  if [[ -x "${DATA_DIR}/bedrock_server" ]]; then
    local current
    current="$(cat "${DATA_DIR}/.current-version" 2>/dev/null || true)"
    if [[ "$current" == "$SERVER_VERSION" && -f "$zip" ]]; then
      echo "Already running Bedrock Dedicated Server ${SERVER_VERSION}"
      return 0
    fi
  fi

  if [[ ! -f "$zip" ]]; then
    echo "Downloading official BDS ${SERVER_VERSION}"
    echo "  ${SERVER_URL}"
    curl_bin "$SERVER_URL" "${zip}.tmp"
    if ! python3 - "${zip}.tmp" <<'PY'
import sys, zipfile
path = sys.argv[1]
try:
    with zipfile.ZipFile(path) as zf:
        bad = zf.testzip()
except zipfile.BadZipFile as e:
    print(f"ERROR: downloaded zip is not a valid archive: {e}", file=sys.stderr)
    sys.exit(1)
if bad:
    print(f"ERROR: corrupt zip member: {bad}", file=sys.stderr)
    sys.exit(1)
PY
    then
      rm -f "${zip}.tmp"
      return 1
    fi
    mv -f "${zip}.tmp" "$zip"
  fi

  maybe_backup_world
  install_from_zip "$zip"
  printf '%s\n' "$SERVER_VERSION" > "${DATA_DIR}/.current-version"
  echo "Installed Bedrock Dedicated Server ${SERVER_VERSION}"
}

usage() {
  echo "Usage: $0 [--resolve-only | --download]" >&2
  exit 2
}

main() {
  local mode="${1:-}"
  case "$mode" in
    ""|--download|--resolve-only) ;;
    -h|--help) usage ;;
    *) usage ;;
  esac

  resolve_version
  echo "Bedrock ${SERVER_VERSION} (${VERSION_TYPE}) ${SERVER_URL}"

  if [[ "$mode" == "--resolve-only" ]]; then
    print_resolve
    return 0
  fi

  mkdir -p "$DATA_DIR"
  install_server
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "${1:-}"
fi
