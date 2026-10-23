#!/usr/bin/env bash
#
# Fetch a statically-linked PHP binary for the Lambda Web Function runtime
# (Amazon Linux 2023, arm64 by default) and drop it at bin/php.
#
# Lambda's nodejs24.x image has no PHP, so we ship our own. It must be:
#   - statically linked (no reliance on system libs that may be absent)
#   - built for Linux and the SAME architecture as the function (arm64 == aarch64)
#
# Source: the static-php-cli project's prebuilt binaries at dl.static-php.dev.
# Asset names are  php-<FULL.VERSION>-cli-linux-<arch>.tar.gz  (full patch
# version, e.g. 8.3.15 — NOT 8.3). Rather than hardcode a patch number that
# goes stale and 404s, this script reads the directory listing and picks the
# newest available patch for the requested minor + arch.
#
# Override via env:
#   PHP_MINOR     e.g. 8.3  (default below) — selects newest patch in this line
#   PHP_VERSION   e.g. 8.3.15 — pin an exact patch (overrides PHP_MINOR)
#   TARGET_ARCH   aarch64 | x86_64   (Lambda arm64 == aarch64)
#   BUILD         common | bulk      (bulk has more extensions; default common)
#
set -euo pipefail

cd "$(dirname "$0")/.."

PHP_MINOR="${PHP_MINOR:-8.3}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"   # matches Lambda arm64
BUILD="${BUILD:-common}"
BASE="https://dl.static-php.dev/static-php-cli/${BUILD}"

mkdir -p bin

# Resolve the asset name.
if [ -n "${PHP_VERSION:-}" ]; then
  ASSET="php-${PHP_VERSION}-cli-linux-${TARGET_ARCH}.tar.gz"
else
  echo ">> Resolving newest ${PHP_MINOR}.x cli-linux-${TARGET_ARCH} build from ${BASE}/ ..."
  LISTING="$(curl -fsSL "${BASE}/" 2>/dev/null || true)"
  if [ -z "$LISTING" ]; then
    echo "ERROR: could not read directory listing at ${BASE}/" >&2
    echo "Pin an exact version instead, e.g.: PHP_VERSION=8.3.15 $0" >&2
    exit 1
  fi
  # Extract matching filenames, sort by version, take the newest.
  # version-sort (-V) orders 8.3.9 < 8.3.10 correctly.
  ASSET="$(printf '%s\n' "$LISTING" \
    | grep -oE "php-${PHP_MINOR}\.[0-9]+-cli-linux-${TARGET_ARCH}\.tar\.gz" \
    | sort -V -u \
    | tail -1)"
  if [ -z "$ASSET" ]; then
    echo "ERROR: no php-${PHP_MINOR}.x-cli-linux-${TARGET_ARCH} asset found in listing." >&2
    echo "Browse ${BASE}/ and set PHP_VERSION to an exact patch." >&2
    exit 1
  fi
fi

URL="${BASE}/${ASSET}"
echo ">> Downloading static PHP: ${URL}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! curl -fsSL "$URL" -o "$TMP/php.tar.gz"; then
  cat >&2 <<EOF

ERROR: download failed for ${URL}

Browse available builds here and pick a linux-${TARGET_ARCH} cli tarball:
  ${BASE}/
Then either:
  PHP_VERSION=<full.version> $0
or extract its 'php' binary to $(pwd)/bin/php and run: chmod +x bin/php

Lambda arm64 == aarch64.
EOF
  exit 1
fi

tar -xzf "$TMP/php.tar.gz" -C "$TMP"
PHP_PATH="$(find "$TMP" -type f -name php | head -1)"
if [ -z "$PHP_PATH" ]; then
  echo "ERROR: no 'php' binary found inside the archive" >&2
  exit 1
fi

cp "$PHP_PATH" bin/php
chmod +x bin/php

echo ">> Installed bin/php  (from ${ASSET})"
file bin/php || true
echo ">> NOTE: this binary targets linux-${TARGET_ARCH}; it will NOT run on macOS."
echo ">> That's expected — it only needs to run inside Lambda."
