"""
test-workflow-schema.py — validates n8n workflow JSON files.

Usage:
    python n8n/tests/test-workflow-schema.py <workflow-name>

Workflow name is the filename without .json, e.g.:
    python n8n/tests/test-workflow-schema.py daily-digest
    python n8n/tests/test-workflow-schema.py realtime-webhook
    python n8n/tests/test-workflow-schema.py weekly-learning

Checks (all workflows):
1. File exists and is valid JSON.
2. Top-level keys 'name', 'nodes', 'connections' are present.
3. Each node has 'type' and 'name'.
4. Workflow name matches the argument.

Additional checks per workflow:
- realtime-webhook: trigger node type is n8n-nodes-base.webhook
- weekly-learning:  a cron/schedule trigger node is present (not webhook)
"""

import sys
import json
import pathlib

ROOT = pathlib.Path(__file__).parent.parent.parent
WORKFLOWS_DIR = ROOT / "n8n" / "workflows"

REQUIRED_TOP_KEYS = {"name", "nodes", "connections"}


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    print("RESULT: FAILED (exit 1)")
    sys.exit(1)


def check_common(wf: dict, name: str) -> None:
    # Top-level keys
    for key in REQUIRED_TOP_KEYS:
        if key not in wf:
            fail(f"missing top-level key '{key}'")

    # Workflow name matches
    if wf["name"] != name:
        fail(f"workflow name '{wf['name']}' != expected '{name}'")

    # Every node has type and name
    for i, node in enumerate(wf.get("nodes", [])):
        if "type" not in node:
            fail(f"node[{i}] missing 'type'")
        if "name" not in node:
            fail(f"node[{i}] missing 'name'")


def check_realtime_webhook(wf: dict) -> None:
    node_types = [n["type"] for n in wf.get("nodes", [])]
    if "n8n-nodes-base.webhook" not in node_types:
        fail("realtime-webhook must have a trigger node of type n8n-nodes-base.webhook")
    print("OK: webhook trigger node present")


def check_weekly_learning(wf: dict) -> None:
    node_types = [n["type"] for n in wf.get("nodes", [])]
    cron_types = {"n8n-nodes-base.scheduleTrigger", "n8n-nodes-base.cron"}
    if not any(t in cron_types for t in node_types):
        fail("weekly-learning must have a cron/schedule trigger node")
    if "n8n-nodes-base.webhook" in node_types:
        fail("weekly-learning must not use a webhook trigger")
    print("OK: cron/schedule trigger node present (no webhook)")


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: python test-workflow-schema.py <workflow-name>", file=sys.stderr)
        print("RESULT: FAILED (exit 1)")
        sys.exit(1)

    name = sys.argv[1]
    path = WORKFLOWS_DIR / f"{name}.json"

    if not path.exists():
        fail(f"{path} does not exist")

    try:
        wf = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        fail(f"invalid JSON: {e}")

    print(f"OK: {path.name} is valid JSON")

    check_common(wf, name)
    print(f"OK: top-level keys present, name='{name}', all nodes have type+name")

    if name == "realtime-webhook":
        check_realtime_webhook(wf)
    elif name == "weekly-learning":
        check_weekly_learning(wf)

    print(f"All schema checks passed for '{name}'.")


if __name__ == "__main__":
    try:
        main()
    except SystemExit as e:
        if e.code != 0:
            print(f"RESULT: FAILED (exit {e.code})")
        raise
