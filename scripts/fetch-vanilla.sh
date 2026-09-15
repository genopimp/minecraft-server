#!/usr/bin/env bash
# Resolve and install the official Mojang vanilla server.jar.
# Default VERSION=LATEST tracks the same release channel as the Windows Java launcher.
set -euo pipefail

MANIFEST_URL="${MANIFEST_URL:-https://piston-meta.mojang.com/mc/game/version_manifest_v2.json}"
DATA_DIR="${DATA_DIR:-/data}"
VERSION="${VERSION:-LATEST}"
USER_AGENT="${USER_AGENT:-genopimp-minecraft-server/1.0}"
BACKUP_ON_UPGRADE="${BACKUP_ON_UPGRADE:-true}"
KEEP_BACKUPS="${KEEP_BACKUPS:-2}"
LEVEL_NAME="${LEVEL_NAME:-world}"

SERVER_VERSION=""
VERSION_TYPE=""
SERVER_URL=""
SERVER_SHA1=""
SERVER_SIZE=""
JAVA_REQUIRED=""
JAVA_HAVE=""

curl_json() {
  curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
    -H "User-Agent: ${USER_AGENT}" \
    -H "Accept: application/json" \
    "$1"
}

curl_bin() {
  curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
    -H "User-Agent: ${USER_AGENT}" \
    -o "$2" \
    "$1"
}

resolve_version() {
  local manifest version_id version_meta_url version_json

  echo "Fetching Mojang version manifest..."
  manifest="$(curl_json "$MANIFEST_URL")"

  case "${VERSION}" in
    LATEST|latest|RELEASE|release)
      version_id="$(jq -er '.latest.release' <<<"$manifest")"
      ;;
    SNAPSHOT|snapshot)
      version_id="$(jq -er '.latest.snapshot' <<<"$manifest")"
      ;;
    *)
      version_id="$VERSION"
      ;;
  esac

  version_meta_url="$(jq -er --arg id "$version_id" \
    '.versions[] | select(.id==$id) | .url' <<<"$manifest")"
  VERSION_TYPE="$(jq -er --arg id "$version_id" \
    '.versions[] | select(.id==$id) | .type' <<<"$manifest")"

  echo "Resolving ${version_id} (${VERSION_TYPE}) metadata..."
  version_json="$(curl_json "$version_meta_url")"

  SERVER_VERSION="$version_id"
  SERVER_URL="$(jq -er '.downloads.server.url' <<<"$version_json")"
  SERVER_SHA1="$(jq -er '.downloads.server.sha1' <<<"$version_json")"
  SERVER_SIZE="$(jq -er '.downloads.server.size' <<<"$version_json")"
  JAVA_REQUIRED="$(jq -er '.javaVersion.majorVersion' <<<"$version_json")"
}

print_resolve() {
  cat <<EOF
VERSION_ID=${SERVER_VERSION}
VERSION_TYPE=${VERSION_TYPE}
SERVER_URL=${SERVER_URL}
SERVER_SHA1=${SERVER_SHA1}
SERVER_SIZE=${SERVER_SIZE}
JAVA_REQUIRED=${JAVA_REQUIRED}
EOF
}

detect_java_major() {
  java -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -1
}

ensure_java() {
  if ! command -v java >/dev/null 2>&1; then
    echo "ERROR: java is not on PATH" >&2
    return 1
  fi
  JAVA_HAVE="$(detect_java_major)"
  if [[ -z "$JAVA_HAVE" ]]; then
    echo "ERROR: could not parse java -version" >&2
    java -version >&2 || true
    return 1
  fi
  echo "Java runtime ${JAVA_HAVE}; Minecraft ${SERVER_VERSION} requires ${JAVA_REQUIRED}"
  if (( JAVA_HAVE < JAVA_REQUIRED )); then
    echo "ERROR: Minecraft ${SERVER_VERSION} requires Java ${JAVA_REQUIRED}; this image has Java ${JAVA_HAVE}." >&2
    echo "Pull a newer image: ghcr.io/genopimp/minecraft-server:latest" >&2
    return 1
  fi
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

  world="${DATA_DIR}/${LEVEL_NAME}"
  if [[ ! -d "$world" ]]; then
    echo "No world at ${world}; skipping backup"
    return 0
  fi

  dest="${DATA_DIR}/backups/${previous}-$(date -u +%Y%m%dT%H%M%SZ)"
  echo "Backing up ${LEVEL_NAME} (${previous} -> ${SERVER_VERSION}) to ${dest}"
  mkdir -p "$dest"
  cp -a "$world" "$dest/"
  if [[ -f "${DATA_DIR}/server.properties" ]]; then
    cp -a "${DATA_DIR}/server.properties" "$dest/"
  fi

  if [[ "${KEEP_BACKUPS}" =~ ^[0-9]+$ ]] && (( KEEP_BACKUPS > 0 )); then
    # shellcheck disable=SC2012
    ls -1dt "${DATA_DIR}/backups"/* 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -rf
  fi
}

install_server() {
  local dir jar tmp got
  dir="${DATA_DIR}/versions/${SERVER_VERSION}"
  jar="${dir}/server.jar"
  mkdir -p "$dir"

  if [[ -f "$jar" ]]; then
    got="$(sha1sum "$jar" | awk '{print $1}')"
    if [[ "$got" == "$SERVER_SHA1" ]]; then
      echo "Using cached ${SERVER_VERSION} server.jar (sha1 ${SERVER_SHA1})"
      printf '%s\n' "$SERVER_VERSION" > "${DATA_DIR}/.current-version"
      printf '%s\n' "$SERVER_SHA1" > "${dir}/server.jar.sha1"
      return 0
    fi
    echo "Cached jar sha1 mismatch (got ${got}, want ${SERVER_SHA1}); re-downloading"
    rm -f "$jar"
  fi

  tmp="${jar}.tmp"
  echo "Downloading official Mojang server.jar for ${SERVER_VERSION} (${SERVER_SIZE} bytes)"
  echo "  ${SERVER_URL}"
  curl_bin "$SERVER_URL" "$tmp"
  got="$(sha1sum "$tmp" | awk '{print $1}')"
  if [[ "$got" != "$SERVER_SHA1" ]]; then
    rm -f "$tmp"
    echo "ERROR: sha1 mismatch after download (got ${got}, want ${SERVER_SHA1})" >&2
    return 1
  fi
  mv -f "$tmp" "$jar"
  printf '%s\n' "$SERVER_VERSION" > "${DATA_DIR}/.current-version"
  printf '%s\n' "$SERVER_SHA1" > "${dir}/server.jar.sha1"
  echo "Installed Minecraft ${SERVER_VERSION} (sha1 ${SERVER_SHA1})"
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
  echo "Vanilla ${SERVER_VERSION} (${VERSION_TYPE}) java=${JAVA_REQUIRED} sha1=${SERVER_SHA1}"

  if [[ "$mode" == "--resolve-only" ]]; then
    print_resolve
    return 0
  fi

  mkdir -p "$DATA_DIR"
  if [[ "$mode" != "--download" ]]; then
    ensure_java
  fi
  maybe_backup_world
  install_server
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "${1:-}"
fi
