"""
test-task-format.py — validates agent/prompts/task-format.md.

Checks:
1. The file exists and contains a JSON Schema definition block.
2. All ```json example blocks in the file are valid JSON.
3. Each example validates against the declared schema using jsonschema.

Run: python agent/tests/test-task-format.py
"""

import sys
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).parent.parent.parent
TASK_FORMAT = ROOT / "agent" / "prompts" / "task-format.md"


def extract_json_blocks(text: str) -> list[str]:
    """Return all fenced ```json ... ``` blocks from markdown text."""
    return re.findall(r"```json\s*([\s\S]*?)```", text)


def find_schema_block(blocks: list[str]) -> dict:
    """Find the block that looks like a JSON Schema (has '$schema' or 'type':'array')."""
    for block in blocks:
        try:
            obj = json.loads(block)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict) and ("$schema" in obj or obj.get("type") == "array"):
            return obj
    return {}


def main() -> None:
    if not TASK_FORMAT.exists():
        print(f"FAIL: {TASK_FORMAT} does not exist", file=sys.stderr)
        sys.exit(1)

    text = TASK_FORMAT.read_text(encoding="utf-8")
    blocks = extract_json_blocks(text)

    if not blocks:
        print("FAIL: no ```json blocks found in task-format.md", file=sys.stderr)
        sys.exit(1)

    # Parse all blocks
    parsed = []
    for i, block in enumerate(blocks):
        try:
            parsed.append(json.loads(block))
        except json.JSONDecodeError as e:
            print(f"FAIL: block {i+1} is not valid JSON: {e}", file=sys.stderr)
            sys.exit(1)
    print(f"OK: {len(parsed)} JSON block(s) all parse cleanly")

    # Find schema block
    schema = find_schema_block(blocks)
    if not schema:
        print("FAIL: no JSON Schema block found (expected dict with '$schema' or type:array)",
              file=sys.stderr)
        sys.exit(1)
    print("OK: schema block found")

    # Validate example arrays against schema
    try:
        import jsonschema  # type: ignore
    except ImportError:
        print("SKIP: jsonschema not installed — install with: pip install jsonschema")
        sys.exit(0)

    item_schema = schema.get("items", {})
    example_arrays = [p for p in parsed if isinstance(p, list)]

    if not example_arrays:
        print("FAIL: no example arrays (list blocks) found in task-format.md",
              file=sys.stderr)
        sys.exit(1)

    for i, example in enumerate(example_arrays):
        for j, item in enumerate(example):
            try:
                jsonschema.validate(instance=item, schema=item_schema)
            except jsonschema.ValidationError as e:
                print(f"FAIL: example array {i+1}, item {j+1} fails schema: {e.message}",
                      file=sys.stderr)
                sys.exit(1)
    print(f"OK: {len(example_arrays)} example array(s) all validate against schema")

    print("All task-format.md checks passed.")


if __name__ == "__main__":
    try:
        main()
    except SystemExit as e:
        if e.code != 0:
            print(f"RESULT: FAILED (exit {e.code})")
        raise
