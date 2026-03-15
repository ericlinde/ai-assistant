"""
test-server-stub.py — validates agent/mcp/server.py stub.

Checks:
1. server.py imports without AttributeError.
2. Calling main() raises NotImplementedError.

Run: python agent/tests/test-server-stub.py
"""

import sys
import importlib.util
import pathlib

ROOT = pathlib.Path(__file__).parent.parent.parent
SERVER = ROOT / "agent" / "mcp" / "server.py"


def main() -> None:
    if not SERVER.exists():
        print(f"FAIL: {SERVER} does not exist", file=sys.stderr)
        print("RESULT: FAILED (exit 1)")
        sys.exit(1)

    # Load the module without running it
    spec = importlib.util.spec_from_file_location("server", SERVER)
    try:
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except AttributeError as e:
        print(f"FAIL: import raised AttributeError: {e}", file=sys.stderr)
        print("RESULT: FAILED (exit 1)")
        sys.exit(1)
    print("OK: server.py imports without AttributeError")

    # main() must raise NotImplementedError
    if not hasattr(mod, "main"):
        print("FAIL: server.py has no main() function", file=sys.stderr)
        print("RESULT: FAILED (exit 1)")
        sys.exit(1)

    try:
        mod.main()
        print("FAIL: main() did not raise NotImplementedError", file=sys.stderr)
        print("RESULT: FAILED (exit 1)")
        sys.exit(1)
    except NotImplementedError:
        print("OK: main() raises NotImplementedError as expected")

    print("All server-stub checks passed.")


if __name__ == "__main__":
    try:
        main()
    except SystemExit as e:
        if e.code != 0:
            print(f"RESULT: FAILED (exit {e.code})")
        raise
