#!/usr/bin/env bash
# test-nginx-conf.sh — validates nginx.conf syntax using nginx:alpine in Docker.
# Runs nginx -t against the conf file; exits 0 on success, 1 on failure.
# Requires: Docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/../nginx.conf"

if [ ! -f "$CONF" ]; then
    echo "ERROR: nginx.conf not found at $CONF" >&2
    exit 1
fi

CONF_ABS="$(realpath "$CONF")"

echo "Testing nginx config: $CONF_ABS"

MSYS_NO_PATHCONV=1 docker run --rm \
    -v "$CONF_ABS:/etc/nginx/nginx.conf:ro" \
    nginx:alpine \
    nginx -t

echo "nginx config test passed."
