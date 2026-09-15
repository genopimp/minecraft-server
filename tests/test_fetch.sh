#!/usr/bin/env bash
# Live check against Mojang's version manifest: LATEST must resolve to an
# official piston-data server.jar with a sha1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FETCH="${ROOT}/scripts/fetch-vanilla.sh"

if [[ ! -x "$FETCH" ]]; then
  echo "missing executable ${FETCH}" >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "== resolve LATEST =="
VERSION=LATEST "$FETCH" --resolve-only | tee "$tmp"

eval "$(grep -E '^(VERSION_ID|VERSION_TYPE|SERVER_URL|SERVER_SHA1|SERVER_SIZE|JAVA_REQUIRED)=' "$tmp")"

[[ -n "${VERSION_ID}" ]]
[[ "${VERSION_TYPE}" == "release" ]]
[[ "${SERVER_URL}" == https://piston-data.mojang.com/* ]]
[[ "${SERVER_SHA1}" =~ ^[a-f0-9]{40}$ ]]
[[ "${SERVER_SIZE}" =~ ^[0-9]+$ ]]
(( SERVER_SIZE > 1000000 ))
[[ "${JAVA_REQUIRED}" =~ ^[0-9]+$ ]]
(( JAVA_REQUIRED >= 21 ))

echo "== HEAD server.jar =="
code="$(curl -sI -o /dev/null -w '%{http_code}' -A 'genopimp-minecraft-server/1.0' "$SERVER_URL")"
[[ "$code" == "200" || "$code" == "302" ]]

echo "OK  LATEST=${VERSION_ID}  java=${JAVA_REQUIRED}  sha1=${SERVER_SHA1}  bytes=${SERVER_SIZE}"
