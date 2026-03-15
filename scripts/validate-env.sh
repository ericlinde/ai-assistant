#!/usr/bin/env bash
# Validates that:
#   1. The infisical CLI is installed
#   2. INFISICAL_TOKEN is set (or a .token file exists)
#   3. .infisical.json project config exists
#   4. All secret names from .env.example are present in Infisical (prod)
# Usage: validate-env.sh
# Exits 0 if all checks pass, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

ENV_EXAMPLE="${REPO_ROOT}/.env.example"
TOKEN_FILE="${REPO_ROOT}/.token"
INFISICAL_JSON="${REPO_ROOT}/.infisical.json"

# ---------------------------------------------------------------------------
# Load INFISICAL_TOKEN from .token file if not already set in environment
# ---------------------------------------------------------------------------
if [ -z "${INFISICAL_TOKEN:-}" ] && [ -f "${TOKEN_FILE}" ]; then
  INFISICAL_TOKEN="$(cat "${TOKEN_FILE}")"
  export INFISICAL_TOKEN
fi

# ---------------------------------------------------------------------------
# 1. Check infisical CLI is installed
# ---------------------------------------------------------------------------
if ! command -v infisical > /dev/null 2>&1; then
  echo "ERROR: infisical CLI not found. Install from https://infisical.com/docs/cli/overview" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Check INFISICAL_TOKEN is set
# ---------------------------------------------------------------------------
if [ -z "${INFISICAL_TOKEN:-}" ]; then
  echo "ERROR: INFISICAL_TOKEN is not set and ${TOKEN_FILE} does not exist." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Check .infisical.json exists
# ---------------------------------------------------------------------------
if [ ! -f "${INFISICAL_JSON}" ]; then
  echo "ERROR: .infisical.json not found at ${INFISICAL_JSON}." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Fetch available secret names from Infisical
# ---------------------------------------------------------------------------
AVAILABLE_JSON="$(infisical secrets --format=json --silent 2>/dev/null)" || {
  echo "ERROR: Failed to fetch secrets from Infisical. Check token and project config." >&2
  exit 1
}

AVAILABLE_NAMES="$(echo "${AVAILABLE_JSON}" | python -c "
import json, sys
data = json.load(sys.stdin)
for item in data:
    print(item['secretKey'])
" 2>/dev/null)" || {
  echo "ERROR: Failed to parse Infisical secrets response." >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 5. Check all required names from .env.example are present in Infisical
# ---------------------------------------------------------------------------
if [ ! -f "${ENV_EXAMPLE}" ]; then
  echo "ERROR: .env.example not found at ${ENV_EXAMPLE}" >&2
  exit 1
fi

MISSING=0
while IFS= read -r line; do
  # Only match lines where the value after = is strictly empty.
  # Lines with hardcoded values (e.g. LINEAR_TEAM_ID=e96a084f-...) are skipped.
  if [[ "${line}" =~ ^([A-Z0-9_]+)=$ ]]; then
    var="${BASH_REMATCH[1]}"
    if ! echo "${AVAILABLE_NAMES}" | grep -qx "${var}"; then
      echo "MISSING in Infisical: ${var}" >&2
      MISSING=$((MISSING + 1))
    fi
  fi
done < "${ENV_EXAMPLE}"

if [ "${MISSING}" -gt 0 ]; then
  echo "ERROR: ${MISSING} required secret(s) missing from Infisical." >&2
  exit 1
fi

echo "OK: Infisical CLI authenticated and all required secrets present."
