#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="${SCRIPT_DIR}/../validate-env.sh"
PASS=0
FAIL=0

TMP_DIR="$(mktemp -d)"
STUB_BIN="$(mktemp -d)"
NO_JSON_DIR="$(mktemp -d)"
PYTHON_DIR="$(dirname "$(command -v python)")"
trap 'rm -rf "$TMP_DIR" "$STUB_BIN" "$NO_JSON_DIR"' EXIT

# --- Stub .env.example: 2 required secrets, 1 hardcoded value ---
cat > "${TMP_DIR}/.env.example" <<'EOF'
REQ_VAR_ONE=
REQ_VAR_TWO=
HARDCODED_VAR=some-fixed-value
EOF

# --- Stub .infisical.json ---
cat > "${TMP_DIR}/.infisical.json" <<'EOF'
{"workspaceId":"test-workspace","defaultEnvironment":"prod"}
EOF

# --- Stub .env.example for no-json-dir test (no .infisical.json) ---
cp "${TMP_DIR}/.env.example" "${NO_JSON_DIR}/.env.example"

# --- Infisical CLI stub ---
# Handles: login (returns a stub token), secrets (returns JSON from STUB_INFISICAL_JSON)
cat > "${STUB_BIN}/infisical" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "login" ]; then
  echo "stub-session-token"
elif [ "${1:-}" = "secrets" ]; then
  if [ -n "${STUB_INFISICAL_JSON:-}" ]; then
    echo "${STUB_INFISICAL_JSON}"
  else
    echo '[{"secretKey":"REQ_VAR_ONE","secretValue":"v1"},{"secretKey":"REQ_VAR_TWO","secretValue":"v2"}]'
  fi
fi
EOF
chmod +x "${STUB_BIN}/infisical"

run_test() {
  local description="$1"
  local expected="$2"
  shift 2
  local result
  if "$@" > /dev/null 2>&1; then
    result="pass"
  else
    result="fail"
  fi
  if [ "${result}" = "${expected}" ]; then
    echo "PASS: ${description}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${description} (expected ${expected}, got ${result})"
    FAIL=$((FAIL + 1))
  fi
}

# Test 1: infisical CLI not found → exit 1
run_test "exits 1 when infisical CLI not found" "fail" \
  env INFISICAL_CLIENT_ID=test-id \
  INFISICAL_CLIENT_SECRET=test-secret \
  REPO_ROOT="${TMP_DIR}" \
  PATH="${PYTHON_DIR}:/usr/bin:/bin" \
  bash "${VALIDATE}"

# Test 2: INFISICAL_CLIENT_ID not set → exit 1
run_test "exits 1 when INFISICAL_CLIENT_ID not set" "fail" \
  env INFISICAL_CLIENT_ID="" \
  INFISICAL_CLIENT_SECRET=test-secret \
  REPO_ROOT="${TMP_DIR}" \
  PATH="${STUB_BIN}:${PYTHON_DIR}:/usr/bin:/bin" \
  bash "${VALIDATE}"

# Test 3: .infisical.json missing → exit 1
run_test "exits 1 when .infisical.json missing" "fail" \
  env INFISICAL_CLIENT_ID=test-id \
  INFISICAL_CLIENT_SECRET=test-secret \
  REPO_ROOT="${NO_JSON_DIR}" \
  PATH="${STUB_BIN}:${PYTHON_DIR}:/usr/bin:/bin" \
  bash "${VALIDATE}"

# Test 4: all secrets present → exit 0
ALL_JSON='[{"secretKey":"REQ_VAR_ONE","secretValue":"v1"},{"secretKey":"REQ_VAR_TWO","secretValue":"v2"}]'
run_test "exits 0 when all secrets present in Infisical" "pass" \
  env INFISICAL_CLIENT_ID=test-id \
  INFISICAL_CLIENT_SECRET=test-secret \
  REPO_ROOT="${TMP_DIR}" \
  PATH="${STUB_BIN}:${PYTHON_DIR}:/usr/bin:/bin" \
  STUB_INFISICAL_JSON="${ALL_JSON}" \
  bash "${VALIDATE}"

# Test 5: missing secret → exit 1
MISSING_JSON='[{"secretKey":"REQ_VAR_ONE","secretValue":"v1"}]'
run_test "exits 1 when a required secret is missing from Infisical" "fail" \
  env INFISICAL_CLIENT_ID=test-id \
  INFISICAL_CLIENT_SECRET=test-secret \
  REPO_ROOT="${TMP_DIR}" \
  PATH="${STUB_BIN}:${PYTHON_DIR}:/usr/bin:/bin" \
  STUB_INFISICAL_JSON="${MISSING_JSON}" \
  bash "${VALIDATE}"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
