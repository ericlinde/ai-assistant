#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="${SCRIPT_DIR}/../validate-env.sh"
PASS=0
FAIL=0

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "${TMP_DIR}/.env.example" <<'EOF'
REQUIRED_VAR_ONE=
REQUIRED_VAR_TWO=
REQUIRED_VAR_THREE=
EOF

run_test() {
  local description="$1"
  local expected="$2"  # "pass" or "fail"
  shift 2
  local result
  if "$@" > /dev/null 2>&1; then
    result="pass"
  else
    result="fail"
  fi
  if [ "${result}" = "${expected}" ]; then
    echo "PASS: ${description}"
    PASS=$((PASS+1))
  else
    echo "FAIL: ${description} (expected ${expected}, got ${result})"
    FAIL=$((FAIL+1))
  fi
}

# Test 1: missing variable exits 1
run_test "exits 1 when variable missing" "fail" \
  env REQUIRED_VAR_ONE=set REQUIRED_VAR_TWO=set \
  bash "${VALIDATE}" "${TMP_DIR}/.env.example"

# Test 2: all variables set exits 0
run_test "exits 0 when all variables set" "pass" \
  env REQUIRED_VAR_ONE=set REQUIRED_VAR_TWO=set REQUIRED_VAR_THREE=set \
  bash "${VALIDATE}" "${TMP_DIR}/.env.example"

# Test 3: empty variable exits 1
run_test "exits 1 when variable empty" "fail" \
  env REQUIRED_VAR_ONE=set REQUIRED_VAR_TWO=set REQUIRED_VAR_THREE= \
  bash "${VALIDATE}" "${TMP_DIR}/.env.example"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
