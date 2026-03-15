#!/usr/bin/env bash
# validate.sh — thin wrapper around validate.py and CLI tools.
# All Python-based validation is delegated to lib/safe_validation/validate.py.
# This script only handles tools that require a shell binary (terraform, shellcheck).
# Must be run from the repo root.
#
# Usage:
#   bash lib/safe_validation/validate.sh yaml     <file>
#   bash lib/safe_validation/validate.sh json     <file>
#   bash lib/safe_validation/validate.sh py       <file>
#   bash lib/safe_validation/validate.sh contains <file> <substring>
#   bash lib/safe_validation/validate.sh tf-fmt   <dir>
#   bash lib/safe_validation/validate.sh sh       <file>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_PY="$SCRIPT_DIR/validate.py"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Input validation helpers
# ---------------------------------------------------------------------------

# Reject targets containing shell metacharacters
check_no_metacharacters() {
    local val="$1"
    if echo "$val" | grep -qP '[;\|\&`\$!<>\(\)\{\}\x00]'; then
        echo "ERROR: target contains forbidden characters: $val" >&2
        exit 1
    fi
}

# Resolve a path and assert it stays inside the repo root
check_within_repo() {
    local raw="$1"
    local resolved
    resolved="$(cd "$REPO_ROOT" && realpath -m "$raw" 2>/dev/null)" || {
        echo "ERROR: cannot resolve path: $raw" >&2
        exit 1
    }
    # resolved must start with REPO_ROOT
    case "$resolved" in
        "$REPO_ROOT"/*|"$REPO_ROOT")
            ;;
        *)
            echo "ERROR: path escapes repo root: $raw (resolved to $resolved)" >&2
            exit 1
            ;;
    esac
}

# For file targets: must exist as a file or directory
check_exists() {
    local raw="$1"
    if [ ! -e "$raw" ]; then
        echo "ERROR: path does not exist: $raw" >&2
        exit 1
    fi
}

validate_target() {
    local raw="$1"
    check_no_metacharacters "$raw"
    check_within_repo "$raw"
    check_exists "$raw"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <type> <target> [<extra>]" >&2
    exit 1
fi

TYPE="$1"
TARGET="$2"

# Validate TYPE is a known literal (no metacharacters can slip through here)
case "$TYPE" in
    yaml|json|py|contains|tf-fmt|sh) ;;
    *)
        echo "ERROR: unknown type '$TYPE'. Valid: yaml json py contains tf-fmt sh" >&2
        exit 1
        ;;
esac

# Validate TARGET for all types
validate_target "$TARGET"

case "$TYPE" in
    yaml|json|py)
        python "$VALIDATE_PY" "$TYPE" "$TARGET"
        ;;

    contains)
        if [ "$#" -lt 3 ]; then
            echo "Usage: $0 contains <file> <substring>" >&2
            exit 1
        fi
        # Substring is passed to the Python script which validates it there
        python "$VALIDATE_PY" contains "$TARGET" "$3"
        ;;

    tf-fmt)
        terraform fmt -check "$TARGET"
        echo "Terraform fmt clean: $TARGET"
        ;;

    sh)
        export PATH="$PATH:/c/Users/ericl/AppData/Local/Microsoft/WinGet/Links"
        shellcheck "$TARGET"
        echo "shellcheck clean: $TARGET"
        ;;
esac
