#!/usr/bin/env bash
# Live check against Mojang's BDS download-links API: LATEST Linux zip must
# match the current Windows Bedrock dedicated-server build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FETCH="${ROOT}/scripts/fetch-bds.sh"

if [[ ! -x "$FETCH" ]]; then
  echo "missing executable ${FETCH}" >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "== resolve LATEST =="
VERSION=LATEST "$FETCH" --resolve-only | tee "$tmp"

eval "$(grep -E '^(VERSION_ID|VERSION_TYPE|SERVER_URL|DOWNLOAD_TYPE)=' "$tmp")"

[[ -n "${VERSION_ID}" ]]
[[ "${VERSION_TYPE}" == "release" ]]
[[ "${DOWNLOAD_TYPE}" == "serverBedrockLinux" ]]
[[ "${SERVER_URL}" == https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-*.zip ]]
[[ "${SERVER_URL}" == *"${VERSION_ID}"* ]]

echo "== Windows client binary is the same version =="
win_url="$(curl -fsSL -A 'Mozilla/5.0 (compatible; genopimp-minecraft-server/1.0)' \
  'https://net.web.minecraft-services.net/api/v1.0/download/links' \
  | jq -er '.result.links[] | select(.downloadType=="serverBedrockWindows") | .downloadUrl')"
[[ "$win_url" == *"${VERSION_ID}"* ]]

echo "== HEAD linux zip =="
code="$(curl -sI -o /dev/null -w '%{http_code}' -A 'Mozilla/5.0 (compatible; genopimp-minecraft-server/1.0)' "$SERVER_URL")"
[[ "$code" == "200" || "$code" == "302" ]]

echo "OK  LATEST=${VERSION_ID}  linux=${SERVER_URL}  windows=${win_url}"
