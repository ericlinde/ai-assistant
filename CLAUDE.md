# CLAUDE.md — Personal Agent

Always-active instructions. Read before every operation.
Before building anything or making structural changes, read SPECIFICATION.md first.

---

## What this repo is

A self-hostable personal AI agent: Gmail + Slack → Claude API → Linear tasks.
Single VPS, Docker Compose runtime, n8n workflows, plain-text memory file.

---

## Core principles

1. **No vendor lock-in.** Everything must run from a plain terminal on any
   Linux host. No Vercel, no Railway, no PaaS. Terraform providers and Ansible
   roles must be swappable without touching application code.
   **Exception:** a minimal GitHub Actions workflow file (`.github/workflows/`)
   is permitted solely as a trigger layer — it may only check out the repo,
   inject secrets from GitHub Secrets, and call the existing shell scripts
   (`terraform apply`, `deploy.sh`, etc.). No business logic belongs in the
   Actions file.

2. **Single source of truth.** The repo contains everything needed to
   recreate the full system from zero. Secrets are the only exception
   (documented in `.env.example`).

3. **Idempotent everything.** Every script, playbook, and workflow must
   be safe to run multiple times. Running `deploy.sh` twice must produce
   the same result as running it once.

4. **Extensibility over cleverness.** Prefer flat, readable config over
   abstractions. Adding a capability means adding a file — not refactoring
   existing ones.

5. **Fail loudly.** Scripts exit non-zero and print a clear message on any
   error. Never silently continue past a failure.

---

## Tech stack — do not deviate without good reason

| Layer             | Tool                      |
|-------------------|---------------------------|
| VPS provisioning  | Terraform (OpenTofu)      |
| Server config     | Ansible                   |
| Runtime           | Docker Compose            |
| Workflow runner   | n8n (self-hosted)         |
| AI model          | Claude Sonnet 4.6 via API |
| Memory store      | Google Drive (plain .md)  |
| Task output       | Linear                    |

---

## Hard constraints

- Zero hardcoded secrets anywhere — all values from `.env` or Ansible Vault
- GitHub Actions-specific syntax confined to `.github/workflows/` only —
  never in `scripts/`, `infra/`, or any other file
- All shell scripts must pass `shellcheck` with no warnings
- All Terraform files must pass `terraform validate`
- All JSON files must be valid (parseable by `python3 -m json.tool`)
- n8n workflows stored as exported JSON, imported via API — never via UI-only config
- `.env`, `*.tfstate`, `terraform.tfvars`, and `ansible/inventory` are never committed

---

## Known live Linear context — do not recreate

| Item        | Value                                              |
|-------------|----------------------------------------------------|
| Team        | Ericlinde — `e96a084f-7033-4b61-be58-3fb1e6679a50` |
| Project     | AI Inbox — `4edee420-cd11-48be-90fb-01bd19f54a1f`  |
| Labels      | "Do myself", "AI-assisted", "Auto-execute", "Today" |
| Issue ERI-5 | Setup guide — do not modify                        |

---

## Development approach

- **Use TDD where applicable.** Write tests before implementation for shell scripts,
  Python, and any logic-bearing code. For infrastructure files (Terraform, Ansible,
  nginx config), write the validation command first and confirm it fails before
  writing the file, then confirm it passes after.

---

## When making changes

- **Structural or architectural changes:** read SPECIFICATION.md first
- **Adding a new n8n workflow:** follow the node patterns in SPECIFICATION.md
- **Adding a new service:** add a block to `docker-compose.yml` only —
  do not restructure existing services
- **Updating the agent prompt:** edit `agent/prompts/system-prompt.md` only —
  the n8n workflow HTTP Request node reads it at runtime
- **Adding secrets:** document in `.env.example` as placeholders only, never as values
