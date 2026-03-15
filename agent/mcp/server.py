"""
server.py — MCP (Model Context Protocol) server stub for Phase 3.

This module will implement the MCP protocol to expose NotebookLM notebooks
as tools callable by the Claude agent via the n8n workflow.

Phase 3 contract (not yet implemented):
- Listens on a TCP port for MCP JSON-RPC requests.
- Exposes a `query_notebook` tool that accepts a notebook URL and a query
  string, and returns a summary from NotebookLM.
- Reads notebook URL mappings from agent/memory/notebook-registry.md.

Until Phase 3 begins, importing this module is safe. Calling main() raises
NotImplementedError to make the stub status explicit.
"""


def main() -> None:
    """Entry point. Not implemented until Phase 3."""
    raise NotImplementedError(
        "MCP server is a Phase 3 feature and has not been implemented yet."
    )


if __name__ == "__main__":
    main()
