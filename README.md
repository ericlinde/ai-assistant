# Personal Agent

A self-hostable personal AI agent that processes Gmail into Linear tasks.

Gmail → n8n → Claude API → Linear

Runs on a single Hetzner VPS with Docker Compose. No PaaS, no vendor lock-in.

---

## What it does

- Fetches your Gmail inbox daily at 07:00 UTC
- Sends emails to Claude (Sonnet 4.6) for triage
- Creates actionable Linear tasks with priority, labels, and estimates
- Learns your preferences over time via a weekly feedback loop
- Optionally links tasks to relevant NotebookLM notebooks

---

## Prerequisites

- Hetzner Cloud account + API token
- Google Cloud project with Gmail API and Drive API enabled
- Anthropic API key
- Linear API key
- A domain (e.g. `agent.ejlinde.com`) with Cloudflare DNS
- SSH key pair

See [docs/runbook.md](docs/runbook.md) for full setup instructions.

---

## First-time setup

### 1. Collect secrets

Copy `.env.example` to `.env` and fill in all values:

```bash
cp .env.example .env
```

See [docs/runbook.md](docs/runbook.md) for where to obtain each secret.

### 2. Add secrets to GitHub

Add each value from `.env` as a GitHub Actions secret in your repo:
**Settings → Secrets and variables → Actions → New repository secret**

### 3. Provision the VPS

Trigger the Terraform workflow from GitHub Actions:
**Actions → Terraform Apply → Run workflow**

Note the `server_ip` output, then add a DNS A record in Cloudflare:
- Name: `agent`
- Value: `<server_ip>`

### 4. Deploy

Trigger the deploy workflow:
**Actions → Deploy → Run workflow**

n8n will be available at `https://agent.ejlinde.com` once DNS propagates.

---

## Repository structure

```
.env.example          — documents every required secret
scripts/              — setup.sh, deploy.sh, rollback.sh, validate-env.sh
infra/terraform/      — provisions Hetzner VPS and firewall
infra/ansible/        — configures server, installs Docker, deploys services
infra/nginx/          — reverse proxy + TLS termination config
docker-compose.yml    — defines all runtime services
n8n/workflows/        — exported n8n workflow JSON files
agent/prompts/        — Claude system prompt and task format schema
agent/memory/         — seed files for Google Drive memory store
docs/                 — architecture, runbook, and roadmap
```

---

## Docs

- [Architecture](docs/architecture.md)
- [Runbook](docs/runbook.md)
- [Phases / roadmap](docs/phases.md)
