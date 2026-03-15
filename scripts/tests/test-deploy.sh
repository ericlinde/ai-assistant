#!/usr/bin/env bash
# test-deploy.sh — tests deploy.sh using stub services.
#
# Two scenarios:
#   1. Health check passes  → deploy.sh must exit 0
#   2. Health check never responds → deploy.sh must exit 1
#
# Stubs used:
#   - REPO_ROOT overridden to a temp dir containing a no-op validate-env.sh
#   - docker stub on PATH that exits 0 for all subcommands
#   - curl stub on PATH that returns 200/empty for all calls (scenario 1)
#   - python http.server listening on TEST_PORT (scenario 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_REAL="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY="$REPO_ROOT_REAL/scripts/deploy.sh"
TEST_PORT=18678

if [ ! -f "$DEPLOY" ]; then
    echo "ERROR: scripts/deploy.sh not found" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build stub REPO_ROOT
# ---------------------------------------------------------------------------
STUB_ROOT="$(mktemp -d)"
STUB_BIN="$(mktemp -d)"
trap 'rm -rf "$STUB_ROOT" "$STUB_BIN"' EXIT

# Stub: validate-env.sh
mkdir -p "$STUB_ROOT/scripts"
cat > "$STUB_ROOT/scripts/validate-env.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB_ROOT/scripts/validate-env.sh"

# Stub: empty workflows dir (no import loops)
mkdir -p "$STUB_ROOT/n8n/workflows"

# Stub: infisical binary (passes through "run -- cmd..." and returns empty for "secrets get")
cat > "$STUB_BIN/infisical" << 'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "run" ] && [ "${2:-}" = "--" ]; then
    shift 2
    exec "$@"
fi
if [ "${1:-}" = "secrets" ] && [ "${2:-}" = "get" ]; then
    echo ""
    exit 0
fi
exit 0
EOF
chmod +x "$STUB_BIN/infisical"

# Stub: docker binary (intercepts all docker compose calls)
cat > "$STUB_BIN/docker" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB_BIN/docker"

# Stub: curl binary (returns empty JSON for workflow list)
cat > "$STUB_BIN/curl" << 'EOF'
#!/usr/bin/env bash
# Return a valid empty workflow list for GET, ignore other calls
for arg in "$@"; do
    if [ "$arg" = "-w" ]; then
        # Health check call uses -w "%{http_code}" - return 200
        echo "200"
        exit 0
    fi
done
echo '{"data":[]}'
exit 0
EOF
chmod +x "$STUB_BIN/curl"

# ---------------------------------------------------------------------------
# Scenario 1: health check passes (python serves 200 on TEST_PORT)
# ---------------------------------------------------------------------------
echo "--- Scenario 1: health check passes ---"

python -c "
import http.server, threading, sys, time

port = int(sys.argv[1])

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')
    def log_message(self, *a): pass

srv = http.server.HTTPServer(('127.0.0.1', port), H)
t = threading.Thread(target=srv.serve_forever)
t.daemon = True
t.start()

# Keep alive portably (signal.pause not available on Windows)
while True:
    time.sleep(1)
" "$TEST_PORT" &
SERVER_PID=$!
sleep 1

REPO_ROOT="$STUB_ROOT" \
N8N_HOST=127.0.0.1 \
N8N_PORT="$TEST_PORT" \
INFISICAL_TOKEN=stub-token \
PATH="$STUB_BIN:$PATH" \
bash "$DEPLOY"
RC=$?

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true

if [ "$RC" -ne 0 ]; then
    echo "FAIL: Scenario 1 — deploy.sh exited $RC (expected 0)" >&2
    exit 1
fi
echo "PASS: Scenario 1 — deploy.sh exited 0"

# ---------------------------------------------------------------------------
# Scenario 2: health check never responds (nothing on TEST_PORT+1)
# ---------------------------------------------------------------------------
echo "--- Scenario 2: health check never responds ---"

# Override curl stub to simulate connection refused (non-200 http_code)
cat > "$STUB_BIN/curl" << 'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [ "$arg" = "-w" ]; then
        echo "000"
        exit 0
    fi
done
echo '{"data":[]}'
exit 0
EOF

REPO_ROOT="$STUB_ROOT" \
N8N_HOST=127.0.0.1 \
N8N_PORT=$(( TEST_PORT + 1 )) \
INFISICAL_TOKEN=stub-token \
PATH="$STUB_BIN:$PATH" \
bash "$DEPLOY" && RC=0 || RC=$?

if [ "$RC" -eq 0 ]; then
    echo "FAIL: Scenario 2 — deploy.sh exited 0 (expected non-zero)" >&2
    exit 1
fi
echo "PASS: Scenario 2 — deploy.sh exited $RC (non-zero as expected)"

echo "All deploy.sh tests passed."
