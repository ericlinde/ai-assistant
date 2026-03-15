#!/usr/bin/env bash
# setup.sh — one-time VPS bootstrap.
# Installs python3, ansible, and git; clones the repo to /opt/agent-deploy.
# Safe to run via: curl -fsSL <url> | bash
# Must be run as root.

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/ericlinde/ai-assistant.git}"
DEPLOY_DIR="/opt/agent-deploy"

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: setup.sh must be run as root." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Install dependencies
# ---------------------------------------------------------------------------
echo "==> Updating apt..."
apt-get update -qq

echo "==> Installing python3, ansible, git..."
# ansible is available in Ubuntu 24.04 universe repo
apt-get install -y -qq python3 git ansible

# ---------------------------------------------------------------------------
# Clone repo
# ---------------------------------------------------------------------------
if [ -d "$DEPLOY_DIR/.git" ]; then
    echo "==> Repo already cloned at $DEPLOY_DIR — pulling latest..."
    git -C "$DEPLOY_DIR" pull --ff-only
else
    echo "==> Cloning repo to $DEPLOY_DIR..."
    git clone "$REPO_URL" "$DEPLOY_DIR"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "==> Setup complete."
echo ""
echo "Next steps:"
echo "  1. Copy your secrets:  cp $DEPLOY_DIR/.env.example $DEPLOY_DIR/.env && vi $DEPLOY_DIR/.env"
echo "  2. Copy inventory:     cp $DEPLOY_DIR/infra/ansible/inventory.example $DEPLOY_DIR/infra/ansible/inventory"
echo "  3. Copy vault:         cp $DEPLOY_DIR/infra/ansible/group_vars/all/vault.yml.example $DEPLOY_DIR/infra/ansible/group_vars/all/vault.yml"
echo "  4. Encrypt vault:      ansible-vault encrypt $DEPLOY_DIR/infra/ansible/group_vars/all/vault.yml"
echo "  5. Run deploy:         bash $DEPLOY_DIR/scripts/deploy.sh"
