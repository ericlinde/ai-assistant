#!/usr/bin/env bash
# deploy.sh — idempotent deploy script.
# Validates env, pulls and starts Docker Compose services, health-checks n8n,
# and imports n8n workflows via REST API.
# Safe to run multiple times; second run produces no net changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Load INFISICAL_TOKEN from .token file if not already set in environment
TOKEN_FILE="${REPO_ROOT}/.token"
if [ -z "${INFISICAL_TOKEN:-}" ] && [ -f "${TOKEN_FILE}" ]; then
  INFISICAL_TOKEN="$(cat "${TOKEN_FILE}")"
  export INFISICAL_TOKEN
fi

N8N_HOST="${N8N_HOST:-localhost}"
N8N_PORT="${N8N_PORT:-5678}"
N8N_BASE="http://${N8N_HOST}:${N8N_PORT}"
HEALTH_RETRIES=10
HEALTH_DELAY=3

# ---------------------------------------------------------------------------
# Validate environment
# ---------------------------------------------------------------------------
echo "==> Validating environment..."
bash "$REPO_ROOT/scripts/validate-env.sh"

# ---------------------------------------------------------------------------
# Pull latest images and start services
# ---------------------------------------------------------------------------
echo "==> Pulling Docker images..."
infisical run -- docker compose -f "$REPO_ROOT/docker-compose.yml" pull

echo "==> Starting services..."
infisical run -- docker compose -f "$REPO_ROOT/docker-compose.yml" up -d

# ---------------------------------------------------------------------------
# Health check — retry loop
# ---------------------------------------------------------------------------
echo "==> Waiting for n8n to be healthy (${HEALTH_RETRIES} attempts, ${HEALTH_DELAY}s apart)..."
ATTEMPT=0
while [ "$ATTEMPT" -lt "$HEALTH_RETRIES" ]; do
    ATTEMPT=$(( ATTEMPT + 1 ))
    HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" "${N8N_BASE}/healthz" 2>/dev/null || echo "000")"
    if [ "$HTTP_CODE" = "200" ]; then
        echo "==> n8n healthy (attempt $ATTEMPT)."
        break
    fi
    echo "    Attempt $ATTEMPT/$HEALTH_RETRIES — got HTTP $HTTP_CODE, retrying in ${HEALTH_DELAY}s..."
    if [ "$ATTEMPT" -ge "$HEALTH_RETRIES" ]; then
        echo "ERROR: n8n did not become healthy after $HEALTH_RETRIES attempts." >&2
        exit 1
    fi
    sleep "$HEALTH_DELAY"
done

# ---------------------------------------------------------------------------
# Import n8n workflows (idempotent: update if exists, create if not)
# ---------------------------------------------------------------------------
echo "==> Importing n8n workflows..."

N8N_API_KEY="${N8N_API_KEY:-$(infisical secrets get N8N_API_KEY --plain --silent 2>/dev/null || echo "")}"
if [ -z "$N8N_API_KEY" ]; then
    echo "WARNING: N8N_API_KEY not available — skipping workflow import." >&2
else
    WORKFLOW_DIR="$REPO_ROOT/n8n/workflows"
    if [ -d "$WORKFLOW_DIR" ]; then
        for WF_FILE in "$WORKFLOW_DIR"/*.json; do
            [ -f "$WF_FILE" ] || continue
            WF_NAME="$(python -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$WF_FILE")"

            # Check if workflow already exists
            EXISTING_ID="$(curl -s \
                -H "X-N8N-API-KEY: $N8N_API_KEY" \
                "${N8N_BASE}/api/v1/workflows" \
                | python -c "
import json,sys
data=json.load(sys.stdin).get('data',[])
match=[w['id'] for w in data if w.get('name')=='$WF_NAME']
print(match[0] if match else '')
" 2>/dev/null || echo "")"

            if [ -n "$EXISTING_ID" ]; then
                curl -s -X PUT \
                    -H "X-N8N-API-KEY: $N8N_API_KEY" \
                    -H "Content-Type: application/json" \
                    -d "@$WF_FILE" \
                    "${N8N_BASE}/api/v1/workflows/${EXISTING_ID}" > /dev/null
                echo "    Updated: $WF_NAME"
            else
                curl -s -X POST \
                    -H "X-N8N-API-KEY: $N8N_API_KEY" \
                    -H "Content-Type: application/json" \
                    -d "@$WF_FILE" \
                    "${N8N_BASE}/api/v1/workflows" > /dev/null
                echo "    Created: $WF_NAME"
            fi
        done
    fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "==> Deploy complete. n8n is running at ${N8N_BASE}"
