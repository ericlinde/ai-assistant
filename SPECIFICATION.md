# SPECIFICATION.md — Personal Agent Full Build Spec

Read this fully before building or making structural changes.
For always-on principles and constraints, see CLAUDE.md.

---

## Repo structure

```
personal-agent/
│
├── CLAUDE.md                            ← always-active instructions
├── SPECIFICATION.md                     ← this file
├── README.md
├── .env.example                         ← documents every required secret
├── .gitignore
│
├── infra/
│   ├── terraform/
│   │   ├── main.tf                      ← VPS + firewall + SSH key
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── ansible/
│   │   ├── playbook.yml                 ← installs Docker, hardens SSH, deploys
│   │   ├── inventory.example            ← template; real inventory never in git
│   │   ├── group_vars/all/
│   │   │   ├── vault.yml                ← Ansible Vault encrypted secrets (committed)
│   │   │   └── vault.yml.example        ← documents all vault var names
│   │   └── roles/
│   │       ├── base/                    ← OS hardening, unattended-upgrades
│   │       ├── docker/                  ← Docker + Compose install
│   │       └── agent/                   ← copies files, starts services
│   └── nginx/
│       └── nginx.conf                   ← reverse proxy + TLS termination
│
├── docker-compose.yml                   ← defines all runtime services
├── docker-compose.override.example.yml  ← local dev overrides template
│
├── n8n/
│   └── workflows/
│       ├── daily-digest.json            ← main scheduled workflow
│       ├── realtime-webhook.json        ← per-email real-time processing
│       └── weekly-learning.json         ← feedback loop + rule updates
│
├── agent/
│   ├── prompts/
│   │   ├── system-prompt.md             ← versioned master prompt
│   │   └── task-format.md               ← Linear JSON schema + examples
│   ├── memory/
│   │   ├── agent-memory.md              ← seed template (live file on Drive)
│   │   └── notebook-registry.md         ← topic → NotebookLM URL map
│   └── mcp/                             ← Phase 3: NotebookLM MCP server
│       ├── Dockerfile
│       └── server.py                    ← stub, fully implemented in Phase 3
│
├── scripts/
│   ├── setup.sh                         ← first-time VPS bootstrap
│   ├── deploy.sh                        ← idempotent deploy / upgrade
│   ├── rollback.sh                      ← git checkout previous + redeploy
│   └── validate-env.sh                  ← checks all required secrets present
│
└── docs/
    ├── architecture.md
    ├── runbook.md                        ← how to operate, debug, extend
    └── phases.md                         ← roadmap reference
```

---

## Terraform spec

### Provider

Use **Hetzner Cloud** as the default provider (`hetznercloud/hcloud`).
Abstract it so swapping to DigitalOcean or Vultr requires only changing
`versions.tf` and variable values — not `main.tf` logic.

### Resources to create

- `hcloud_server` — CX22 (2 vCPU, 4 GB RAM, ~€4/mo), Ubuntu 24.04,
  location: `hel1` (Helsinki). Name: `personal-agent`.
- `hcloud_firewall` — allow inbound: SSH (22) from deployer IP only,
  HTTP (80), HTTPS (443). Deny all other inbound.
- `hcloud_ssh_key` — upload the deployer's public key.
- `hcloud_volume` — commented out, ready to uncomment in Phase 2.
  10 GB persistent volume for n8n data.

### Outputs

- `server_ip` — printed after apply, fed into Ansible inventory
- `server_id`

### State

Default to local state file (`terraform.tfstate`, gitignored).
Include a commented-out S3-compatible backend block for users who want
remote state. Do NOT require remote state for MVP.

### Variables (`variables.tf` — values in `terraform.tfvars`, gitignored)

| Variable              | Default | Description                       |
|-----------------------|---------|-----------------------------------|
| `hcloud_token`        | —       | Hetzner API token                 |
| `ssh_public_key_path` | —       | Path to local public key file     |
| `deployer_ip`         | —       | Your IP for SSH firewall rule     |
| `server_location`     | `hel1`  | Hetzner datacenter                |
| `server_type`         | `cx22`  | Hetzner server type               |

---

## Ansible spec

### Role: base

All tasks idempotent:
- Set hostname to `personal-agent`
- `apt update` + `apt upgrade`
- Install: `git`, `curl`, `unzip`, `fail2ban`, `ufw`
- Configure ufw: deny all inbound, allow 22/80/443
- Enable `unattended-upgrades` for security patches
- Disable root SSH login, disable password auth
- Set timezone to UTC

### Role: docker

All tasks idempotent:
- Install Docker CE via official apt repo (not snap)
- Install Docker Compose plugin (not standalone binary)
- Add deploy user to `docker` group
- Enable + start docker service
- Verify: `docker run hello-world`

### Role: agent

All tasks idempotent:
- Create `/opt/agent` directory, owned by deploy user
- rsync repo files to `/opt/agent`
  (exclude: `.git`, `.env`, `infra/terraform/`, `*.tfstate`)
- Template `.env` from Ansible Vault vars
- Run `validate-env.sh` — fail playbook if any secret missing
- `docker compose pull`
- `docker compose up -d`
- Wait for n8n health endpoint (retry 10×, 3 s sleep)
- Import n8n workflows via n8n REST API:
  `GET /api/v1/workflows` to check existing by name,
  `PUT` if exists, `POST` if new
- Verify health: assert n8n health endpoint returns HTTP 200

### Secrets management

Use **Ansible Vault**. Store encrypted vars in
`ansible/group_vars/all/vault.yml` (encrypted file committed to git;
plaintext never committed). Document all var names in
`ansible/group_vars/all/vault.yml.example`.

Required vault vars:

```
vault_anthropic_api_key
vault_linear_api_key
vault_gmail_client_id
vault_gmail_client_secret
vault_gmail_refresh_token
vault_slack_bot_token
vault_n8n_encryption_key              # random 32-char string
vault_n8n_basic_auth_password
vault_gdrive_agent_memory_file_id
vault_gdrive_notebook_registry_file_id
vault_gdrive_service_account_json     # base64-encoded service account key JSON
vault_domain                          # e.g. agent.yourdomain.com
vault_admin_email                     # for Let's Encrypt
vault_hcloud_token                    # Terraform only, not needed at runtime
```

---

## Docker Compose spec

### Service: n8n

```yaml
n8n:
  image: n8nio/n8n:latest
  restart: unless-stopped
  ports:
    - "127.0.0.1:5678:5678"     # localhost only — nginx proxies externally
  environment:
    N8N_BASIC_AUTH_ACTIVE: "true"
    N8N_BASIC_AUTH_USER: "admin"
    N8N_BASIC_AUTH_PASSWORD: "${N8N_BASIC_AUTH_PASSWORD}"
    N8N_ENCRYPTION_KEY: "${N8N_ENCRYPTION_KEY}"
    N8N_HOST: "${DOMAIN}"
    N8N_PROTOCOL: "https"
    WEBHOOK_URL: "https://${DOMAIN}"
    GENERIC_TIMEZONE: "UTC"
    N8N_WORKFLOW_RELOAD_DEFAULTS: "true"
  volumes:
    - n8n_data:/home/node/.n8n
    - ./n8n/workflows:/workflows:ro
    - ./agent:/agent:ro
```

### Service: nginx

```yaml
nginx:
  image: nginx:alpine
  restart: unless-stopped
  ports:
    - "80:80"
    - "443:443"
  volumes:
    - ./infra/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - certbot_data:/etc/letsencrypt
  depends_on:
    - n8n
```

### Service: certbot

```yaml
certbot:
  image: certbot/certbot
  volumes:
    - certbot_data:/etc/letsencrypt
  entrypoint: >
    certbot certonly --webroot
    --webroot-path=/var/www/certbot
    --email ${ADMIN_EMAIL}
    --agree-tos --no-eff-email
    -d ${DOMAIN}
```

Runs once to issue cert. A cron job on the host runs
`docker compose run certbot renew` weekly.

### Service: notebook-mcp (Phase 3 only — add when ready)

```yaml
notebook-mcp:
  build: ./agent/mcp
  restart: unless-stopped
  ports:
    - "127.0.0.1:3001:3001"
  volumes:
    - ./agent/memory/notebook-registry.md:/data/registry.md:ro
```

This block is commented out in the initial `docker-compose.yml`.
Uncomment in Phase 3. Zero impact on other services.

### Volumes

```yaml
volumes:
  n8n_data:       # persists n8n credentials and workflow state
  certbot_data:   # persists TLS certs across container restarts
```

---

## Scripts spec

### setup.sh

Purpose: run once on a brand-new Ubuntu 24.04 VPS.
Safe to `curl | bash`.

Steps:
1. Assert running as root; exit 1 if not
2. `apt install -y python3 ansible git`
3. Clone this repo to `/opt/agent-deploy`
4. Print: "Bootstrap complete. Fill in .env then run:"
   `ansible-playbook -i inventory infra/ansible/playbook.yml`

### deploy.sh

Purpose: idempotent deploy/upgrade. Safe to run on every push,
from cron, or from a webhook. No CI platform required.

Steps:
1. Run `validate-env.sh` — exit 1 if any var missing
2. `docker compose pull`
3. `docker compose up -d`
4. Wait for n8n health endpoint (retry 10×, 3 s sleep)
5. Import/update n8n workflows from `n8n/workflows/*.json`
   via n8n REST API — workflow name is idempotency key
6. Print: `Deploy complete. n8n: https://${DOMAIN}`

### rollback.sh

Steps:
1. Accept one argument: commit SHA or the string `previous`
2. If `previous`: resolve to `HEAD~1`
3. `git checkout <sha>`
4. Call `deploy.sh`
5. Print the deployed commit SHA

### validate-env.sh

Steps:
1. Parse `.env.example` for all variable names
   (lines matching `^[A-Z_]+=`)
2. For each name: check it is set and non-empty in environment or `.env`
3. Print each missing variable name
4. Exit 1 if any missing, exit 0 if all present

---

## n8n workflows spec

All three workflows stored as exported JSON in `n8n/workflows/`.
Imported via n8n REST API on every deploy. Workflow name = idempotency key.

---

### Workflow: daily-digest.json

**Trigger:** Cron — `0 7 * * *` (07:00 UTC daily)

**Nodes in order:**

1. **Read agent-memory**
   HTTP GET Google Drive file
   (file ID from env `GDRIVE_AGENT_MEMORY_FILE_ID`)
   Auth: service account from env `GDRIVE_SERVICE_ACCOUNT_JSON`

2. **Read notebook-registry**
   HTTP GET Google Drive file
   (file ID from env `GDRIVE_NOTEBOOK_REGISTRY_FILE_ID`)

3. **Fetch Gmail**
   Gmail node, query:
   `after:{{$env.LAST_WATERMARK}} is:inbox -category:promotions -category:social`
   Max results: 100

4. **Format messages**
   Code node (JS): map emails to `{id, from, subject, date, body_snippet}`.
   Deduplicate against processed IDs in agent-memory.
   If resulting array is empty, skip to step 9.

5. **Claude API call**
   HTTP Request node:
   - URL: `https://api.anthropic.com/v1/messages`
   - Method: POST
   - Headers: `x-api-key: ${ANTHROPIC_API_KEY}`,
     `anthropic-version: 2023-06-01`
   - Body:
     ```json
     {
       "model": "claude-sonnet-4-6",
       "max_tokens": 4096,
       "system": "<agent-memory content + task-format.md concatenated>",
       "messages": [{ "role": "user", "content": "<messages array as JSON string>" }]
     }
     ```
   - Add header `anthropic-beta: message-batches-2024-09-24` for batch discount

6. **Parse output**
   Code node: `JSON.parse(response.content[0].text)`.
   Validate it is an array. On parse error: log and continue with empty array.

7. **Loop: create Linear issues**
   Split In Batches (size 1), then for each issue:
   HTTP Request to `https://api.linear.app/graphql`
   Header: `Authorization: ${LINEAR_API_KEY}`
   Mutation: `createIssue` with all fields from issue JSON object.
   If `notebook_url` present: follow with `createAttachment` mutation
   to add the URL as a link on the issue.

8. **Update watermark**
   HTTP PATCH Google Drive: append to agent-memory:
   - New `Last Gmail watermark:` (current ISO datetime)
   - New processed IDs appended to `## Processed message IDs` section

9. **Error handler** (connected to every node's error output)
   Create a single Linear issue:
   - Title: `Agent run failed — [error message]`
   - Priority: 1 (Urgent), Label: "Do myself"
   - Team: Ericlinde, Project: AI Inbox

---

### Workflow: realtime-webhook.json

**Trigger:** Webhook node — `POST /webhook/gmail`

Configure Gmail push notifications via Google Cloud Pub/Sub to POST
to this URL when a new message arrives in the inbox.

Processing: identical to daily-digest steps 3–9, for a single message
extracted from the Pub/Sub payload.

Do NOT add the batch API header — this path requires real-time response.

---

### Workflow: weekly-learning.json

**Trigger:** Cron — `0 9 * * 1` (09:00 UTC every Monday)

**Nodes in order:**

1. **Fetch closed/cancelled Linear issues**
   GraphQL: issues in AI Inbox, states `[Done, Cancelled]`,
   `updatedAt` within last 7 days. Include: id, title, labels, state, comments.

2. **Extract feedback comments**
   Code node: from each issue's comments, extract any containing
   `skip`, `auto`, or `good` (case-insensitive).

3. **Read current agent-memory**
   HTTP GET Google Drive (same as daily-digest step 1)

4. **Claude learning call**
   HTTP Request to Claude API:
   - System: "You update a personal agent's standing rules.
     Return ONLY a JSON array of rule changes.
     Each item: `{action: 'add'|'remove'|'update', rule: string}`"
   - User: JSON of closed tasks + feedback comments + current standing rules

5. **Apply rule changes**
   Code node: parse the JSON array, build updated standing rules section.

6. **Update agent-memory**
   HTTP PATCH Google Drive: replace `## Standing rules` section,
   append to `## Learned patterns` with date + what changed.

---

## Agent files spec

### agent/prompts/system-prompt.md

```markdown
You are a personal productivity agent for Eric Linde.

## Context
- Linear workspace: Ericlinde
- Project: AI Inbox (ID: 4edee420-cd11-48be-90fb-01bd19f54a1f)
- Team: Ericlinde (ID: e96a084f-7033-4b61-be58-3fb1e6679a50)
- Labels available: "Do myself", "AI-assisted", "Auto-execute", "Today"
- Priority: 1=Urgent, 2=High, 3=Normal, 4=Low
- Estimate: 1=15 min, 2=30 min, 3=1 hr, 5=half day

## On every run
1. Read agent-memory (provided in context) — standing rules override
   your own judgement without exception
2. Read notebook-registry (provided in context)
3. Process the messages array in the user turn
4. Return ONLY valid JSON — no prose, no markdown fences, no explanation

## Rules
- Never create duplicate tasks — check processed IDs in agent-memory
- Skip: newsletters, automated notifications, calendar confirmations,
  CI/CD notifications unless they require explicit human action
- Batch related messages into one task where logical
- For each task: check notebook-registry for topic keyword matches
  (case-insensitive, partial match on subject + body snippet).
  If match found: include notebook_url and notebook_title in output.
- Apply standing rules from agent-memory with no exceptions
- If uncertain on priority: default to Normal (3)
- If uncertain on label: default to "Do myself"

## Output format
See task-format.md (appended below) for exact JSON schema and examples.
```

---

### agent/prompts/task-format.md

Define the exact JSON schema Claude must output.

Field definitions:

| Field            | Type    | Required | Description                                       |
|------------------|---------|----------|---------------------------------------------------|
| `title`          | string  | yes      | Action-oriented, starts with a verb               |
| `description`    | string  | yes      | Who sent it, what they need, suggested next step  |
| `priority`       | integer | yes      | 1=Urgent, 2=High, 3=Normal, 4=Low                |
| `labels`         | array   | yes      | One or more of the four label strings             |
| `estimate`       | integer | no       | 1=15 min, 2=30 min, 3=1 hr, 5=half day           |
| `notebook_url`   | string  | no       | NotebookLM URL if topic matched registry          |
| `notebook_title` | string  | no       | Display title for the notebook link               |

Include:
- Full JSON Schema object with all fields, types, required fields
- Three worked examples (one per execution label type)
- Error case: if a message is malformed, output a task with
  title `Review malformed message`, label `Do myself`, priority 3,
  description containing the raw message text
- Explicit final instruction: output is an array only — no wrapper object

---

### agent/memory/agent-memory.md

Seed template — upload this content to Google Drive on first setup.
The live file is on Google Drive; this is the initial seed only.

```markdown
# Agent Memory — Eric Linde
# Last updated: [timestamp]
# Last Gmail watermark: 2024-01-01T00:00:00Z
# Last Slack watermark: 2024-01-01T00:00:00Z

## Standing rules
# Add rules here — one per line, plain English.
# These override Claude's judgement without exception.
# Examples:
# - Emails from [name] are always priority: Urgent
# - Invoice receipts → label: Auto-execute, estimate: 1
# - Newsletter digests → skip entirely, do not create task
# - Meeting scheduling requests → label: AI-assisted

## Learned patterns
# Agent appends here during weekly learning run.
# Format: - [YYYY-MM-DD] learned: [rule description]

## Processed message IDs
# Agent appends here after each run. Do not edit manually.
# gmail: []
# slack: []
```

---

### agent/memory/notebook-registry.md

```markdown
# NotebookLM Registry
# One entry per line.
# Format: keywords (comma-separated) | url | display title
# Keywords matched case-insensitively against email subject + body snippet.
# Replace example entries with real notebooks:

# climate,policy,carbon,emissions | https://notebooklm.google.com/notebook/REPLACE | Climate Policy Research
# budget,Q4,finance,forecast | https://notebooklm.google.com/notebook/REPLACE | Q4 Budget Planning
# competitor,pricing,market | https://notebooklm.google.com/notebook/REPLACE | Competitor Analysis
# fundraising,series,investor,deck | https://notebooklm.google.com/notebook/REPLACE | Series A Prep
```

---

### agent/mcp/server.py (Phase 3 stub)

```python
"""
NotebookLM MCP Server — Phase 3
Stub file. Implement when ready to upgrade from link-only to
full notebook context retrieval.

When implemented, this server:
  1. Accepts a topic string via MCP tool call
  2. Reads notebook-registry.md to find matching notebook URL
  3. Fetches the NotebookLM share URL (public HTML)
  4. Returns extracted text summary (first 2000 chars)

MCP protocol: stdio transport
Tool name:    get_notebook_context
Input:        { "topic": string }
Output:       { "url": string, "title": string, "summary": string }

To activate in Phase 3:
  1. Implement this file
  2. Uncomment notebook-mcp block in docker-compose.yml
  3. Add one tool definition to agent/prompts/system-prompt.md
  4. Run deploy.sh — no other changes needed
"""


def main():
    raise NotImplementedError("Phase 3 — not yet implemented")


if __name__ == "__main__":
    main()
```

---

### agent/mcp/Dockerfile (stub)

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY server.py .
CMD ["python", "server.py"]
```

---

## .env.example

```bash
# ── Anthropic ──────────────────────────────────────────────────
ANTHROPIC_API_KEY=               # platform.anthropic.com → API Keys

# ── Linear ─────────────────────────────────────────────────────
LINEAR_API_KEY=                  # linear.app/settings/api
LINEAR_TEAM_ID=e96a084f-7033-4b61-be58-3fb1e6679a50
LINEAR_PROJECT_ID=4edee420-cd11-48be-90fb-01bd19f54a1f

# ── Gmail (OAuth2) ─────────────────────────────────────────────
GMAIL_CLIENT_ID=                 # console.cloud.google.com → OAuth 2.0
GMAIL_CLIENT_SECRET=
GMAIL_REFRESH_TOKEN=             # generate via OAuth 2.0 Playground

# ── Slack ──────────────────────────────────────────────────────
SLACK_BOT_TOKEN=                 # api.slack.com/apps → OAuth Tokens

# ── Google Drive ───────────────────────────────────────────────
GDRIVE_AGENT_MEMORY_FILE_ID=     # from Drive file URL
GDRIVE_NOTEBOOK_REGISTRY_FILE_ID=
GDRIVE_SERVICE_ACCOUNT_JSON=     # base64-encoded service account key JSON

# ── n8n ────────────────────────────────────────────────────────
N8N_ENCRYPTION_KEY=              # random 32-char string — keep secret
N8N_BASIC_AUTH_PASSWORD=         # strong password for n8n UI
N8N_WEBHOOK_SECRET=              # for validating Gmail Pub/Sub payloads

# ── Server ─────────────────────────────────────────────────────
DOMAIN=                          # e.g. agent.yourdomain.com
ADMIN_EMAIL=                     # for Let's Encrypt certificate

# ── Hetzner (Terraform only — not needed at runtime) ───────────
HCLOUD_TOKEN=                    # hetzner.com → Cloud Console → API Tokens
```

---

## .gitignore

```
# Secrets
.env
*.tfvars
ansible/group_vars/all/vault.yml

# Terraform state
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl

# Ansible
ansible/inventory

# Runtime
*.log
.DS_Store
__pycache__/
*.pyc
*.pyo
node_modules/
```

---

## Phased roadmap

| Phase | Name             | What gets built                                                                  |
|-------|------------------|----------------------------------------------------------------------------------|
| 1     | Running agent    | Terraform + Ansible + Docker Compose + n8n + Gmail + Linear + notebook links     |
| 2     | Slack + learning | Slack ingestion. Weekly feedback loop. Historical 2-year backfill.               |
| 3     | NotebookLM MCP   | Implement agent/mcp/server.py. Uncomment docker-compose service block.           |
| 4     | Draft outputs    | Agent drafts email replies as Linear sub-tasks. Approve → n8n sends.            |
| 5     | Research kicks   | Agent creates tasks with pre-loaded search URLs for research topics.             |
| 6     | Auto-execute     | Trusted task types run end-to-end with full audit log in Linear.                 |

---

## Extensibility guide

Only the listed files change for each capability — nothing else.

| Capability                              | What to change                                                                                       |
|-----------------------------------------|------------------------------------------------------------------------------------------------------|
| Add new input source (WhatsApp, etc.)   | Add fetch node in n8n before "Format messages". Prompt and Linear output untouched.                  |
| Add new output (Notion, Todoist, etc.)  | Add output node after "Parse output". JSON schema from Claude unchanged.                             |
| Upgrade NotebookLM to MCP (Phase 3)    | Implement agent/mcp/server.py. Uncomment docker-compose block. Add tool def to system-prompt.md.     |
| Add email drafting (Phase 4)            | Add `draft` field to task-format.md. Add Gmail draft node in n8n. One new line in system-prompt.md. |
| Add research kicks (Phase 5)            | Add `research_url` field to task-format.md. Agent populates it; Linear card shows the link.          |
| Switch AI model                         | Change `model` field in n8n HTTP Request node. Prompt is model-agnostic.                             |
| Add a second user                       | New n8n workflow set + new agent-memory.md with different standing rules.                             |
| Make tasks more autonomous              | Move task types from "AI-assisted" to "Auto-execute" in agent-memory.md. No code change.             |

---

## Build order

Implement files in this exact sequence.
Validate each file before proceeding to the next.

```
 1. .gitignore
 2. .env.example
 3. README.md
 4. scripts/validate-env.sh
 5. infra/terraform/versions.tf
 6. infra/terraform/variables.tf
 7. infra/terraform/main.tf
 8. infra/terraform/outputs.tf
 9. infra/ansible/roles/base/tasks/main.yml
10. infra/ansible/roles/docker/tasks/main.yml
11. infra/ansible/roles/agent/tasks/main.yml
12. infra/ansible/playbook.yml
13. infra/ansible/inventory.example
14. infra/ansible/group_vars/all/vault.yml.example
15. infra/nginx/nginx.conf
16. docker-compose.yml
17. docker-compose.override.example.yml
18. scripts/setup.sh
19. scripts/deploy.sh
20. scripts/rollback.sh
21. agent/prompts/system-prompt.md
22. agent/prompts/task-format.md
23. agent/memory/agent-memory.md
24. agent/memory/notebook-registry.md
25. agent/mcp/Dockerfile
26. agent/mcp/server.py
27. n8n/workflows/daily-digest.json
28. n8n/workflows/realtime-webhook.json
29. n8n/workflows/weekly-learning.json
30. docs/architecture.md
31. docs/runbook.md
32. docs/phases.md
```

### Validation per file type

| File type       | Command                                      |
|-----------------|----------------------------------------------|
| Shell scripts   | `shellcheck <file>`                          |
| Terraform       | `terraform validate` (run in infra/terraform/) |
| Ansible         | `ansible-lint <file>`                        |
| JSON            | `python3 -m json.tool <file> > /dev/null`    |
| Python          | `python3 -m py_compile <file>`               |

---

## Definition of done

- [ ] `terraform apply` provisions a Hetzner VPS with no errors
- [ ] `ansible-playbook playbook.yml` configures a fresh Ubuntu 24.04
      server and starts all services with no errors
- [ ] `deploy.sh` is idempotent: running it twice produces no changes
      on the second run
- [ ] n8n is reachable at `https://${DOMAIN}` after deploy
- [ ] All three n8n workflows import without validation errors in n8n
- [ ] `validate-env.sh` exits 1 on a missing variable, 0 when all present
- [ ] `rollback.sh previous` restores the previous commit and redeploys
- [ ] Zero hardcoded secrets anywhere in the codebase
- [ ] All shell scripts pass `shellcheck` with no warnings
- [ ] All Terraform files pass `terraform validate`
