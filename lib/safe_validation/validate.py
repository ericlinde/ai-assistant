#!/usr/bin/env python
"""
local-validate.py — safe, read-only file validation helper.

Usage:
    python scripts/local-validate.py <type> <file> [<substring>]

Types:
    yaml     <file>                  Parse file as YAML; exit 1 on error.
    json     <file>                  Parse file as JSON; exit 1 on error.
    py       <file>                  Compile-check a Python source file.
    contains <file> <substring>      Exit 1 if <substring> is not in the file.

All arguments are validated strictly:
  - <type> must be one of the exact strings above.
  - <file> must resolve to a path inside the current working directory.
  - <substring> must be a plain string (no code executed).
"""

import sys
import pathlib
import json
import re

# ---------------------------------------------------------------------------
# Allowed types and argument counts
# ---------------------------------------------------------------------------
TYPES = {
    "yaml":     {"args": 1},
    "json":     {"args": 1},
    "py":       {"args": 1},
    "contains": {"args": 2},
}


def safe_path(raw: str) -> pathlib.Path:
    """
    Resolve <raw> relative to CWD and reject any path that escapes CWD
    or contains shell-special characters.
    """
    forbidden = set('\x00;<>&|`$!{}()')
    if any(c in forbidden for c in raw):
        print(f"ERROR: path contains forbidden character: {raw!r}", file=sys.stderr)
        sys.exit(1)

    cwd = pathlib.Path.cwd().resolve()
    resolved = (cwd / raw).resolve()

    try:
        resolved.relative_to(cwd)
    except ValueError:
        print(f"ERROR: path escapes working directory: {raw!r}", file=sys.stderr)
        sys.exit(1)

    if not resolved.exists():
        print(f"ERROR: file not found: {resolved}", file=sys.stderr)
        sys.exit(1)

    if not resolved.is_file():
        print(f"ERROR: not a file: {resolved}", file=sys.stderr)
        sys.exit(1)

    return resolved


def safe_substring(raw: str) -> str:
    """
    Accept any non-empty string that contains only printable characters.
    No code is executed — this is used only with `in` operator.
    """
    if not raw:
        print("ERROR: substring must not be empty", file=sys.stderr)
        sys.exit(1)
    if not all(c.isprintable() for c in raw):
        print("ERROR: substring contains non-printable characters", file=sys.stderr)
        sys.exit(1)
    return raw


def validate_yaml(path: pathlib.Path) -> None:
    try:
        import yaml  # type: ignore
    except ImportError:
        print("ERROR: pyyaml not installed (pip install pyyaml)", file=sys.stderr)
        sys.exit(1)
    with path.open(encoding="utf-8") as fh:
        yaml.safe_load(fh)
    print(f"YAML valid: {path}")


def validate_json(path: pathlib.Path) -> None:
    with path.open(encoding="utf-8") as fh:
        json.load(fh)
    print(f"JSON valid: {path}")


def validate_py(path: pathlib.Path) -> None:
    import py_compile
    import tempfile
    import os
    # Compile to a temp file so we don't write a .pyc next to the source
    with tempfile.NamedTemporaryFile(suffix=".pyc", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        py_compile.compile(str(path), cfile=tmp_path, doraise=True)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
    print(f"Python compile clean: {path}")


def validate_contains(path: pathlib.Path, substring: str) -> None:
    content = path.read_text(encoding="utf-8")
    if substring not in content:
        print(f"CONTAINS FAILED: {substring!r} not found in {path}", file=sys.stderr)
        sys.exit(1)
    print(f"CONTAINS OK: {substring!r} found in {path}")


def main() -> None:
    args = sys.argv[1:]

    if not args:
        print(__doc__)
        sys.exit(1)

    vtype = args[0]

    if vtype not in TYPES:
        print(f"ERROR: unknown type {vtype!r}. Valid: {', '.join(TYPES)}", file=sys.stderr)
        sys.exit(1)

    expected_args = TYPES[vtype]["args"]
    if len(args) - 1 != expected_args:
        print(
            f"ERROR: {vtype!r} requires {expected_args} argument(s), got {len(args) - 1}",
            file=sys.stderr,
        )
        sys.exit(1)

    if vtype == "yaml":
        validate_yaml(safe_path(args[1]))
    elif vtype == "json":
        validate_json(safe_path(args[1]))
    elif vtype == "py":
        validate_py(safe_path(args[1]))
    elif vtype == "contains":
        validate_contains(safe_path(args[1]), safe_substring(args[2]))


if __name__ == "__main__":
    main()
