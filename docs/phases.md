# Phases

## Phase 1 — Running Agent ✓ (this build)

**Goal:** End-to-end working system — Gmail → Claude → Linear.

What gets built:
- Terraform + Ansible infrastructure for a single Hetzner VPS
- Docker Compose runtime (n8n, nginx, certbot)
- `validate-env.sh`, `setup.sh`, `deploy.sh`, `rollback.sh`
- Three n8n workflows: `daily-digest`, `realtime-webhook`, `weekly-learning`
- Agent prompts and memory seed files
- MCP server stub (Phase 3 placeholder)

**Status:** Complete when all items in PLAN.md Phase 1 are ticked.

---

## Phase 2 — Slack + Learning *(planned)*

**Goal:** Add Slack as a second ingestion source; activate the weekly
learning loop; run a one-time 2-year Gmail backfill.

Key additions:
- Slack ingestion node in a new `slack-digest` workflow
- `weekly-learning.json` fully activated (currently wired but not deployed)
- `scripts/backfill-gmail.sh` — bulk-processes historical messages in batches

---

## Phase 3 — NotebookLM MCP *(planned)*

**Goal:** Let Claude query NotebookLM notebooks during task extraction,
so tasks can reference relevant research without the user having to look
things up.

Key additions:
- Implement `agent/mcp/server.py` (MCP JSON-RPC server)
- Uncomment `notebook-mcp` service in `docker-compose.yml`
- Add `query_notebook` tool definition to `agent/prompts/system-prompt.md`
- Wire the MCP server call into `daily-digest` and `realtime-webhook`

---

## Phase 4 — Draft Outputs *(planned)*

**Goal:** For `AI-assisted` tasks, have the agent produce a first draft
(email reply, document outline, research summary) attached to the Linear issue.

Key additions:
- Extended output schema in `task-format.md` (optional `draft` field)
- Draft rendering node in n8n workflows
- Linear attachment creation for drafts

---

## Phase 5 — Research Kicks *(planned)*

**Goal:** For complex tasks, have the agent proactively research background
context (web search, NotebookLM queries) before creating the Linear issue.

Key additions:
- Web search tool integration in the Claude API call
- Multi-turn reasoning loop in n8n (tool use → result → final task)

---

## Phase 6 — Auto-Execute *(planned)*

**Goal:** For `Auto-execute` labelled tasks, have the agent carry out the
action directly (send email, create calendar event, update a document) and
mark the Linear issue complete automatically.

Key additions:
- Action executor module in `agent/`
- Approval gate workflow in n8n (optional human-in-the-loop step)
- Audit log in Google Drive
