#!/usr/bin/env bash
# test-setup.sh — runs setup.sh inside an Ubuntu 24.04 container and asserts:
#   1. /opt/agent-deploy directory is created
#   2. ansible --version exits 0
# Requires: Docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/scripts/setup.sh"

if [ ! -f "$SETUP_SCRIPT" ]; then
    echo "ERROR: scripts/setup.sh not found" >&2
    exit 1
fi

SETUP_ABS="$(realpath "$SETUP_SCRIPT")"

echo "Running setup.sh test in Ubuntu 24.04 container..."

MSYS_NO_PATHCONV=1 docker run --rm \
    -v "$SETUP_ABS:/tmp/setup.sh:ro" \
    ubuntu:24.04 \
    bash -c '
        set -euo pipefail

        # Install git first so we can create the stub repo
        apt-get update -qq
        apt-get install -y -qq git

        # Create a minimal local git repo to use as REPO_URL stub
        git init /tmp/stub-repo
        git -C /tmp/stub-repo -c user.email="test@test.com" -c user.name="test" \
            commit --allow-empty -m "init"

        # Run setup.sh pointing at the local stub repo (skips real network clone)
        REPO_URL=/tmp/stub-repo bash /tmp/setup.sh

        # Assert /opt/agent-deploy exists
        if [ ! -d /opt/agent-deploy ]; then
            echo "FAIL: /opt/agent-deploy does not exist" >&2
            exit 1
        fi
        echo "PASS: /opt/agent-deploy exists"

        # Assert ansible is installed and functional
        if ! ansible --version > /dev/null 2>&1; then
            echo "FAIL: ansible --version failed" >&2
            exit 1
        fi
        echo "PASS: ansible --version OK"
    '

echo "setup.sh test passed."
