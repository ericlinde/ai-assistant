# Architecture

## Data flow

```
Gmail / Slack
      │
      ▼
  n8n workflows  ──── reads ────►  Google Drive (agent-memory.md)
      │                                    ▲
      │ HTTP POST                          │ writes
      ▼                                    │
 Claude API (claude-sonnet-4-6)   ─────────┘
      │
      │ JSON array of task objects
      ▼
 Linear API  ──►  Issues in "AI Inbox" project
```

## Component responsibilities

| Component             | Responsibility                                                       |
|-----------------------|----------------------------------------------------------------------|
| n8n (self-hosted)     | Workflow orchestration: scheduling, HTTP, Google Drive, Linear calls |
| Claude API            | Message parsing, task extraction, weekly learning                    |
| Google Drive          | Plain-text memory file (`agent-memory.md`, `notebook-registry.md`)  |
| Linear                | Task output — issues created in the "AI Inbox" project               |
| nginx                 | TLS termination, reverse proxy to n8n on port 5678                  |
| certbot               | Automatic TLS certificate renewal via Let's Encrypt                  |

## Network topology

```
Internet
   │
   │ :80 / :443
   ▼
nginx (Docker)
   │
   │ HTTP proxy_pass :5678
   ▼
n8n (Docker)
   │
   ├── outbound: api.anthropic.com
   ├── outbound: api.linear.app
   ├── outbound: www.googleapis.com (Gmail, Drive)
   └── inbound webhook: POST /webhook/gmail  (from Google Pub/Sub)
```

All services run in a single Docker Compose stack on one VPS.
The `agent` Docker network is internal-only — only nginx is exposed externally.

## Volume layout

| Volume          | Contents                                              |
|-----------------|-------------------------------------------------------|
| `n8n_data`      | n8n database, workflow state, credentials (encrypted) |
| `certbot_data`  | TLS certificates from Let's Encrypt                   |

## Secrets

Three-tier secrets architecture:

| Tier             | Scope                                      | Storage                          |
|------------------|--------------------------------------------|----------------------------------|
| **Infisical**    | App runtime secrets (API keys, tokens)     | Infisical Cloud — prod env       |
| **Ansible Vault** | Server config (infisical token, domain)   | Encrypted file in git            |
| **GitHub Secrets** | CI/CD only (HCLOUD_TOKEN, SSH key)       | GitHub repository secrets        |

At runtime, `infisical run -- docker compose up -d` injects all app secrets as
environment variables. The Infisical machine identity token is written to
`/opt/agent/.token` by Ansible and loaded automatically by `deploy.sh`.

See `.env.example` for the full list of required Infisical secret names.
The `.token` and `.env` files are never committed (enforced by `.gitignore`).
