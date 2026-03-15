#!/usr/bin/env bash
# rollback.sh — rolls back to a given commit SHA and redeploys.
# Usage: rollback.sh <sha>|previous
#
# Arguments:
#   previous   — resolves to HEAD~1 (the commit before the current one)
#   <sha>      — any valid git commit SHA or ref

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Allow tests to inject a stub deploy script
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-$SCRIPT_DIR/deploy.sh}"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <sha>|previous" >&2
    exit 1
fi

TARGET="$1"

# Resolve 'previous' to HEAD~1
if [ "$TARGET" = "previous" ]; then
    TARGET="$(git -C "$REPO_ROOT" rev-parse HEAD~1)"
fi

# Validate the SHA resolves in the repo
if ! git -C "$REPO_ROOT" cat-file -e "${TARGET}^{commit}" 2>/dev/null; then
    echo "ERROR: '$TARGET' is not a valid commit in $REPO_ROOT" >&2
    exit 1
fi

echo "==> Rolling back to $TARGET..."
git -C "$REPO_ROOT" checkout "$TARGET"

DEPLOYED_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
echo "==> Checked out $DEPLOYED_SHA"

echo "==> Running deploy..."
bash "$DEPLOY_SCRIPT"

echo "==> Rollback complete. Deployed SHA: $DEPLOYED_SHA"
