#!/usr/bin/env bash
# test-rollback.sh — tests rollback.sh in a temp git repo.
#
# Scenarios:
#   1. rollback.sh previous → checks out first commit, calls deploy.sh stub, exits 0
#   2. rollback.sh <explicit-sha> → checks out that SHA, calls deploy.sh stub, exits 0
#   3. rollback.sh with no args → exits 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROLLBACK="$REPO_ROOT_REAL/scripts/rollback.sh"

if [ ! -f "$ROLLBACK" ]; then
    echo "ERROR: scripts/rollback.sh not found" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build temp git repo with two commits
# ---------------------------------------------------------------------------
GIT_REPO="$(mktemp -d)"
STUB_BIN="$(mktemp -d)"
trap 'rm -rf "$GIT_REPO" "$STUB_BIN"' EXIT

git -C "$GIT_REPO" init -q
git -C "$GIT_REPO" -c user.email="t@t.com" -c user.name="t" \
    commit --allow-empty -m "first commit"
FIRST_SHA="$(git -C "$GIT_REPO" rev-parse HEAD)"

git -C "$GIT_REPO" -c user.email="t@t.com" -c user.name="t" \
    commit --allow-empty -m "second commit"
SECOND_SHA="$(git -C "$GIT_REPO" rev-parse HEAD)"

# Stub deploy.sh that records what SHA was checked out when it was called.
# Uses REPO_ROOT (passed through from the calling environment) to find the repo.
cat > "$STUB_BIN/deploy.sh" << 'EOF'
#!/usr/bin/env bash
git -C "$REPO_ROOT" rev-parse HEAD > /tmp/test-rollback-deployed-sha
exit 0
EOF
chmod +x "$STUB_BIN/deploy.sh"

echo "Repo: $GIT_REPO  first=$FIRST_SHA  second=$SECOND_SHA"

# ---------------------------------------------------------------------------
# Scenario 1: rollback.sh previous
# ---------------------------------------------------------------------------
echo "--- Scenario 1: rollback.sh previous ---"

REPO_ROOT="$GIT_REPO" \
DEPLOY_SCRIPT="$STUB_BIN/deploy.sh" \
bash "$ROLLBACK" previous
RC=$?

DEPLOYED_SHA="$(cat /tmp/test-rollback-deployed-sha)"

if [ "$RC" -ne 0 ]; then
    echo "FAIL: Scenario 1 — rollback.sh exited $RC (expected 0)" >&2
    exit 1
fi
if [ "$DEPLOYED_SHA" != "$FIRST_SHA" ]; then
    echo "FAIL: Scenario 1 — deployed SHA $DEPLOYED_SHA != first SHA $FIRST_SHA" >&2
    exit 1
fi
echo "PASS: Scenario 1 — checked out $FIRST_SHA and deployed"

# Reset to second commit for next test
git -C "$GIT_REPO" checkout -q "$SECOND_SHA"

# ---------------------------------------------------------------------------
# Scenario 2: rollback.sh <explicit sha>
# ---------------------------------------------------------------------------
echo "--- Scenario 2: rollback.sh <explicit sha> ---"

REPO_ROOT="$GIT_REPO" \
DEPLOY_SCRIPT="$STUB_BIN/deploy.sh" \
bash "$ROLLBACK" "$FIRST_SHA"
RC=$?

DEPLOYED_SHA="$(cat /tmp/test-rollback-deployed-sha)"

if [ "$RC" -ne 0 ]; then
    echo "FAIL: Scenario 2 — rollback.sh exited $RC (expected 0)" >&2
    exit 1
fi
if [ "$DEPLOYED_SHA" != "$FIRST_SHA" ]; then
    echo "FAIL: Scenario 2 — deployed SHA $DEPLOYED_SHA != $FIRST_SHA" >&2
    exit 1
fi
echo "PASS: Scenario 2 — checked out $FIRST_SHA and deployed"

# ---------------------------------------------------------------------------
# Scenario 3: no arguments → exit 1
# ---------------------------------------------------------------------------
echo "--- Scenario 3: no arguments ---"

REPO_ROOT="$GIT_REPO" \
DEPLOY_SCRIPT="$STUB_BIN/deploy.sh" \
bash "$ROLLBACK" && RC=0 || RC=$?

if [ "$RC" -eq 0 ]; then
    echo "FAIL: Scenario 3 — rollback.sh exited 0 (expected non-zero)" >&2
    exit 1
fi
echo "PASS: Scenario 3 — exited $RC (non-zero as expected)"

echo "All rollback.sh tests passed."
