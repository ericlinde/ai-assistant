#!/usr/bin/env bash
# Runs all local test and validation checks.
# Safe to run on any Linux/macOS machine with shellcheck, python3, and tofu installed.
# Called by CI but can also be run locally before pushing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> shellcheck"
shellcheck \
  "$REPO_ROOT/scripts/validate-env.sh" \
  "$REPO_ROOT/scripts/deploy.sh" \
  "$REPO_ROOT/scripts/setup.sh" \
  "$REPO_ROOT/scripts/rollback.sh" \
  "$REPO_ROOT/scripts/tests/test-validate-env.sh" \
  "$REPO_ROOT/scripts/tests/test-deploy.sh" \
  "$REPO_ROOT/scripts/tests/test-setup.sh" \
  "$REPO_ROOT/scripts/tests/test-rollback.sh"

echo "==> test-validate-env.sh"
bash "$REPO_ROOT/scripts/tests/test-validate-env.sh"

echo "==> test-task-format.py"
python "$REPO_ROOT/agent/tests/test-task-format.py"

echo "==> test-server-stub.py"
python "$REPO_ROOT/agent/tests/test-server-stub.py"

echo "==> test-workflow-schema.py"
python "$REPO_ROOT/n8n/tests/test-workflow-schema.py" daily-digest
python "$REPO_ROOT/n8n/tests/test-workflow-schema.py" realtime-webhook
python "$REPO_ROOT/n8n/tests/test-workflow-schema.py" weekly-learning

echo "==> terraform fmt -check"
tofu fmt -check "$REPO_ROOT/infra/terraform/"

echo ""
echo "==> All checks passed."
