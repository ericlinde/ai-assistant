#!/usr/bin/env bash
# Validates that all variables declared in .env.example are set and non-empty.
# Usage: validate-env.sh [path-to-env-example]
# Exits 0 if all present, 1 if any missing or empty.
set -uo pipefail

ENV_EXAMPLE="${1:-"$(dirname "$0")/../.env.example"}"

if [ ! -f "${ENV_EXAMPLE}" ]; then
  echo "ERROR: env example file not found: ${ENV_EXAMPLE}" >&2
  exit 1
fi

MISSING=0

while IFS= read -r line; do
  # Match lines starting with an uppercase variable name followed by =
  if [[ "${line}" =~ ^([A-Z0-9_]+)= ]]; then
    var="${BASH_REMATCH[1]}"
    value="$(printenv "${var}" 2>/dev/null || true)"
    if [ -z "${value}" ]; then
      echo "MISSING: ${var}" >&2
      MISSING=$((MISSING + 1))
    fi
  fi
done < "${ENV_EXAMPLE}"

if [ "${MISSING}" -gt 0 ]; then
  echo "ERROR: ${MISSING} required variable(s) not set." >&2
  exit 1
fi

echo "OK: all required environment variables are set."
