# PLAN.md — Personal Agent Build Plan

Tasks are in strict dependency order matching the build order in SPECIFICATION.md.
Each task maps to exactly one item in that list.
All shell scripts use TDD: write a failing test first, then implement.

GitHub Actions files live in `.github/workflows/` only. They are thin trigger
wrappers — no business logic. All logic stays in `scripts/` and `infra/`.

---

## Phase 1 — Running Agent

### Foundations (repo scaffold + secrets contract)

- [ ] **Create .gitignore**
  - File: `.gitignore`
  - Ensures secrets, state files, and Ansible inventory are never committed.
    No dependencies. Must exist before any other file is added to git.
  - Validation: `git check-ignore .env terraform.tfstate ansible/inventory` — all three must print the filename.

- [ ] **Create .env.example**
  - File: `.env.example`
  - Documents every required secret as a placeholder. Consumed by `validate-env.sh`.
    Depends on `.gitignore` (so `.env` is already ignored before this is committed).
  - TDD: Write `validate-env.sh` test harness (see task below) expecting all variable
    names to be parseable from this file before writing the file itself.
  - Validation: `python3 -c "import re,pathlib; names=[l.split('=')[0] for l in pathlib.Path('.env.example').read_text().splitlines() if re.match(r'^[A-Z_]+=', l)]; assert len(names) >= 15, names"` — must list all 15+ vars.

- [ ] **Create README.md**
  - File: `README.md`
  - Top-level orientation: what the system is, quickstart steps referencing
    `setup.sh` → `deploy.sh`, link to `docs/`. No secrets, no hardcoded values.
  - Validation: `python3 -c "import pathlib; t=pathlib.Path('README.md').read_text(); assert 'setup.sh' in t and 'deploy.sh' in t"`.

- [ ] **Create scripts/validate-env.sh**
  - File: `scripts/validate-env.sh`
  - Parses `.env.example` for required variable names; checks each is set and
    non-empty in the environment or `.env`; exits 1 if any missing.
    Depends on `.env.example` (source of truth for required names).
  - TDD: Before writing the script, write `scripts/tests/test-validate-env.sh`
    that sources a minimal `.env.example` stub, runs `validate-env.sh` with a
    missing var and asserts exit 1; then with all vars set and asserts exit 0.
    Confirm the test fails. Then implement the script. Confirm the test passes.
  - Validation:
    ```
    shellcheck scripts/validate-env.sh
    bash scripts/tests/test-validate-env.sh
    ```

---

### Infrastructure — Terraform

- [ ] **Create infra/terraform/versions.tf**
  - File: `infra/terraform/versions.tf`
  - Pins `terraform` version and the `hetznercloud/hcloud` provider version.
    Includes a commented-out S3-compatible backend block. No other files depend
    on this first, but it must exist before `terraform init` can run.
  - Validation: `cd infra/terraform && terraform init -backend=false && terraform validate`.

- [ ] **Create infra/terraform/variables.tf**
  - File: `infra/terraform/variables.tf`
  - Declares all five input variables (`hcloud_token`, `ssh_public_key_path`,
    `deployer_ip`, `server_location`, `server_type`) with descriptions and
    defaults where applicable. Depends on `versions.tf` (`init` must pass first).
  - Validation: `cd infra/terraform && terraform validate`.

- [ ] **Create infra/terraform/main.tf**
  - File: `infra/terraform/main.tf`
  - Defines `hcloud_server`, `hcloud_firewall`, `hcloud_ssh_key` resources,
    and a commented-out `hcloud_volume` block. SSH firewall rule scoped to
    `deployer_ip` only. Depends on `variables.tf`.
  - Validation: `cd infra/terraform && terraform validate`.

- [ ] **Create infra/terraform/outputs.tf**
  - File: `infra/terraform/outputs.tf`
  - Exports `server_ip` and `server_id`. Depends on `main.tf`.
  - Validation: `cd infra/terraform && terraform validate` (full module must pass clean).

- [ ] **Create .github/workflows/terraform.yml**
  - File: `.github/workflows/terraform.yml`
  - Thin trigger only: checks out repo, injects GitHub Secrets as env vars,
    runs `terraform init && terraform apply -auto-approve` inside
    `infra/terraform/`. Triggered manually (`workflow_dispatch`) and on push
    to `main` when any `infra/terraform/**` file changes. No business logic.
    Depends on all four Terraform files existing.
  - GitHub Secrets required (mirror of `terraform.tfvars` vars):
    `HCLOUD_TOKEN`, `SSH_PUBLIC_KEY` (key content, not path),
    `SERVER_LOCATION`, `SERVER_TYPE`.
  - Validation: workflow lint via `actionlint` if available; otherwise confirm
    the file is valid YAML: `python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)" < .github/workflows/terraform.yml`.

---

### Infrastructure — Ansible

- [ ] **Create infra/ansible/roles/base/tasks/main.yml**
  - File: `infra/ansible/roles/base/tasks/main.yml`
  - OS hardening: hostname, apt upgrade, git/curl/unzip/fail2ban/ufw install,
    ufw rules, unattended-upgrades, disable root SSH + password auth, UTC timezone.
    All tasks idempotent. No role dependencies.
  - TDD: Write `infra/ansible/tests/test-base.yml` (an Ansible playbook using
    `assert` tasks) that verifies hostname, ufw status, and sshd config flags
    before running the role — expect failures — then after applying the role expect
    all assertions to pass.
  - Validation:
    ```
    ansible-lint infra/ansible/roles/base/tasks/main.yml
    ansible-playbook infra/ansible/tests/test-base.yml --check (on a test host or molecule)
    ```

- [ ] **Create infra/ansible/roles/docker/tasks/main.yml**
  - File: `infra/ansible/roles/docker/tasks/main.yml`
  - Installs Docker CE via official apt repo (not snap), Compose plugin, adds
    deploy user to `docker` group, enables + starts docker service, runs
    `hello-world` verify step. Depends on `base` role (ufw/apt already configured).
  - TDD: Write `infra/ansible/tests/test-docker.yml` asserting `docker info`
    returns success and `docker compose version` exits 0, run before role
    (expect fail), then after (expect pass).
  - Validation:
    ```
    ansible-lint infra/ansible/roles/docker/tasks/main.yml
    ansible-playbook infra/ansible/tests/test-docker.yml --check
    ```

- [ ] **Create infra/ansible/roles/agent/tasks/main.yml**
  - File: `infra/ansible/roles/agent/tasks/main.yml`
  - Creates `/opt/agent`, rsyncs repo files (excluding `.git`, `.env`,
    `infra/terraform/`, `*.tfstate`), templates `.env` from Vault vars, runs
    `validate-env.sh`, pulls and starts Docker Compose, waits for n8n health,
    imports n8n workflows via REST API (GET to check by name, PUT or POST).
    Depends on `docker` role and `validate-env.sh` existing in repo.
  - TDD: Write `infra/ansible/tests/test-agent.yml` asserting `/opt/agent`
    exists, `.env` is present and non-empty, and n8n health endpoint returns 200.
    Run before role (expect fail), then after (expect pass).
  - Validation:
    ```
    ansible-lint infra/ansible/roles/agent/tasks/main.yml
    ansible-playbook infra/ansible/tests/test-agent.yml --check
    ```

- [ ] **Create infra/ansible/playbook.yml**
  - File: `infra/ansible/playbook.yml`
  - Top-level playbook: applies `base`, `docker`, `agent` roles in order against
    `all` hosts. Depends on all three role task files existing.
  - Validation: `ansible-lint infra/ansible/playbook.yml`.

- [ ] **Create infra/ansible/inventory.example**
  - File: `infra/ansible/inventory.example`
  - Template inventory with placeholder IP and deploy user. The real
    `ansible/inventory` is gitignored; this documents the expected format.
  - Validation: `ansible-inventory -i infra/ansible/inventory.example --list` exits 0.

- [ ] **Create infra/ansible/group_vars/all/vault.yml.example**
  - File: `infra/ansible/group_vars/all/vault.yml.example`
  - Documents all 14 vault variable names as commented placeholders.
    No values. Consumed by the `agent` role tasks and `.env` template.
  - Validation: `python3 -c "import pathlib; lines=pathlib.Path('infra/ansible/group_vars/all/vault.yml.example').read_text().splitlines(); assert any('vault_anthropic_api_key' in l for l in lines)"`.

---

### Infrastructure — nginx

- [ ] **Create infra/nginx/nginx.conf**
  - File: `infra/nginx/nginx.conf`
  - Reverse proxy: HTTP→HTTPS redirect on port 80; HTTPS on 443 with TLS
    termination from `certbot_data` volume; proxy_pass to
    `http://n8n:5678`. Depends on nothing else but must exist before
    `docker-compose.yml` mounts it.
  - TDD: Write `infra/nginx/tests/test-nginx-conf.sh` that runs
    `nginx -t -c <absolute-path>` inside an `nginx:alpine` container and
    asserts exit 0. Run before writing the conf (empty file → fail), then after
    (valid conf → pass).
  - Validation:
    ```
    bash infra/nginx/tests/test-nginx-conf.sh
    ```

---

### Runtime — Docker Compose

- [ ] **Create docker-compose.yml**
  - File: `docker-compose.yml`
  - Defines `n8n`, `nginx`, and `certbot` services plus `n8n_data` and
    `certbot_data` volumes. `notebook-mcp` block present but commented out.
    All secret values referenced via `${VAR}` from `.env`. Depends on
    `infra/nginx/nginx.conf` path being established.
  - Validation: `python3 -m json.tool docker-compose.yml > /dev/null` (if YAML,
    use `python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)" < docker-compose.yml`).

- [ ] **Create docker-compose.override.example.yml**
  - File: `docker-compose.override.example.yml`
  - Local dev overrides: exposes n8n on `0.0.0.0:5678`, disables TLS cert
    fetching. Documents the pattern for local iteration without touching
    `docker-compose.yml`. Depends on `docker-compose.yml` existing.
  - Validation: `python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)" < docker-compose.override.example.yml`.

---

### Scripts

- [ ] **Create scripts/setup.sh**
  - File: `scripts/setup.sh`
  - One-time VPS bootstrap: asserts root, installs `python3 ansible git` via apt,
    clones repo to `/opt/agent-deploy`, prints next-step instructions. Safe to
    `curl | bash`. Depends on `.gitignore` and `.env.example` being committed.
  - TDD: Write `scripts/tests/test-setup.sh` using a Docker container (Ubuntu 24.04)
    to run `setup.sh` and assert `/opt/agent-deploy` exists and `ansible --version`
    exits 0. Run before implementation (expect fail), after (expect pass).
  - Validation:
    ```
    shellcheck scripts/setup.sh
    bash scripts/tests/test-setup.sh
    ```

- [ ] **Create scripts/deploy.sh**
  - File: `scripts/deploy.sh`
  - Idempotent deploy: runs `validate-env.sh`, `docker compose pull`,
    `docker compose up -d`, health-check retry loop (10×, 3 s), n8n workflow
    import via REST API, prints completion message. Depends on `validate-env.sh`
    and `docker-compose.yml`.
  - TDD: Write `scripts/tests/test-deploy.sh` with a mock n8n endpoint (using
    `nc` or `python3 -m http.server`) that returns 200 on the health path.
    Assert that `deploy.sh` exits 0 when health check passes and exits 1 when it
    never responds. Run before implementation (expect fail/error), after (expect pass).
  - Validation:
    ```
    shellcheck scripts/deploy.sh
    bash scripts/tests/test-deploy.sh
    ```

- [ ] **Create scripts/rollback.sh**
  - File: `scripts/rollback.sh`
  - Accepts a commit SHA or `previous`; resolves `previous` to `HEAD~1`;
    runs `git checkout <sha>` then calls `deploy.sh`; prints deployed SHA.
    Depends on `deploy.sh`.
  - TDD: Write `scripts/tests/test-rollback.sh` in a temp git repo with two
    commits. Call `rollback.sh previous` and assert the checked-out SHA equals
    the first commit and that `deploy.sh` was invoked (stub it to exit 0).
    Run before implementation (expect fail), after (expect pass).
  - Validation:
    ```
    shellcheck scripts/rollback.sh
    bash scripts/tests/test-rollback.sh
    ```

---

### Agent files

- [ ] **Create agent/prompts/system-prompt.md**
  - File: `agent/prompts/system-prompt.md`
  - Versioned master prompt: Linear workspace context, per-run instructions,
    standing rules, output format reference to `task-format.md`. Read at runtime
    by n8n HTTP Request node. No code dependencies.
  - Validation: `python3 -c "import pathlib; t=pathlib.Path('agent/prompts/system-prompt.md').read_text(); assert 'task-format.md' in t and '4edee420' in t"`.

- [ ] **Create agent/prompts/task-format.md**
  - File: `agent/prompts/task-format.md`
  - Exact JSON schema Claude must output: field definitions table, full JSON
    Schema object, three worked examples (one per label type), malformed-message
    error case, explicit "array only" instruction. Depends on `system-prompt.md`
    referencing it.
  - TDD: Write `agent/tests/test-task-format.py` that loads `task-format.md`,
    extracts the example JSON blocks, and validates each against the declared
    schema using `jsonschema`. Run before writing examples (schema missing →
    fail), after (valid examples → pass).
  - Validation:
    ```
    python3 agent/tests/test-task-format.py
    ```

- [ ] **Create agent/memory/agent-memory.md**
  - File: `agent/memory/agent-memory.md`
  - Seed template for the Google Drive live file. Contains watermark headers,
    `## Standing rules`, `## Learned patterns`, `## Processed message IDs`
    sections. Uploaded once to Drive on first setup; not modified in repo
    after that.
  - Validation: `python3 -c "import pathlib; t=pathlib.Path('agent/memory/agent-memory.md').read_text(); assert all(s in t for s in ['Standing rules','Learned patterns','Processed message IDs','Last Gmail watermark'])"`.

- [ ] **Create agent/memory/notebook-registry.md**
  - File: `agent/memory/notebook-registry.md`
  - Registry of NotebookLM notebooks with keyword → URL → title mapping.
    Seed template with commented-out example entries. Format validated by
    `daily-digest.json` Format messages node.
  - Validation: `python3 -c "import pathlib; t=pathlib.Path('agent/memory/notebook-registry.md').read_text(); assert '|' in t"`.

- [ ] **Create agent/mcp/Dockerfile**
  - File: `agent/mcp/Dockerfile`
  - Phase 3 stub: `python:3.12-slim` base, copies `requirements.txt` and
    `server.py`, runs `python server.py`. Commented-out in `docker-compose.yml`
    until Phase 3. Depends on `server.py` path being defined.
  - Validation: `docker build -t agent-mcp-test ./agent/mcp` (image builds,
    container fails at runtime with `NotImplementedError` — that is expected).

- [ ] **Create agent/mcp/server.py**
  - File: `agent/mcp/server.py`
  - Phase 3 stub: module docstring explaining MCP protocol contract, `main()`
    raising `NotImplementedError`. Imported cleanly with no runtime errors at
    import time. Depends on `Dockerfile`.
  - TDD: Write `agent/tests/test-server-stub.py` that imports `server` and
    asserts `AttributeError` is not raised on import and that calling `main()`
    raises `NotImplementedError`. Run before writing the file (ImportError →
    fail), after (both assertions pass).
  - Validation:
    ```
    python3 -m py_compile agent/mcp/server.py
    python3 agent/tests/test-server-stub.py
    ```

---

### n8n Workflows

- [ ] **Create n8n/workflows/daily-digest.json**
  - File: `n8n/workflows/daily-digest.json`
  - Cron 07:00 UTC workflow: read agent-memory → read notebook-registry →
    fetch Gmail → format/deduplicate → Claude API call → parse output →
    loop create Linear issues (+ attachments) → update watermark → error handler.
    Depends on agent prompt files and `.env.example` vars being defined.
    Uses batch API header. Workflow name is idempotency key for import.
  - TDD: Write `n8n/tests/test-workflow-schema.py` that loads the JSON,
    validates top-level keys (`name`, `nodes`, `connections`), checks each
    node has `type` and `name`, and asserts the workflow name equals
    `"daily-digest"`. Run before creating the file (FileNotFoundError →
    fail), after (all assertions pass).
  - Validation:
    ```
    python3 -m json.tool n8n/workflows/daily-digest.json > /dev/null
    python3 n8n/tests/test-workflow-schema.py daily-digest
    ```

- [ ] **Create n8n/workflows/realtime-webhook.json**
  - File: `n8n/workflows/realtime-webhook.json`
  - Webhook trigger on `POST /webhook/gmail`. Identical processing to
    daily-digest steps 3–9 for a single Pub/Sub message. No batch API header.
    Depends on `daily-digest.json` node patterns being established.
  - TDD: `test-workflow-schema.py` extended to accept workflow name as arg;
    run with `realtime-webhook`. Also assert trigger node type is `n8n-nodes-base.webhook`.
  - Validation:
    ```
    python3 -m json.tool n8n/workflows/realtime-webhook.json > /dev/null
    python3 n8n/tests/test-workflow-schema.py realtime-webhook
    ```

- [ ] **Create n8n/workflows/weekly-learning.json**
  - File: `n8n/workflows/weekly-learning.json`
  - Cron 09:00 UTC Monday: fetch closed/cancelled Linear issues → extract
    feedback comments → read agent-memory → Claude learning call → apply rule
    changes → update agent-memory. Depends on `daily-digest.json` establishing
    Claude API and Google Drive node patterns.
  - TDD: `test-workflow-schema.py` run with `weekly-learning`. Also assert
    cron expression node is present and trigger is not webhook.
  - Validation:
    ```
    python3 -m json.tool n8n/workflows/weekly-learning.json > /dev/null
    python3 n8n/tests/test-workflow-schema.py weekly-learning
    ```

---

### Documentation

- [ ] **Create docs/architecture.md**
  - File: `docs/architecture.md`
  - Describes data flow (Gmail/Slack → n8n → Claude → Linear), component
    responsibilities, network topology, and volume layout. No code dependency.
  - Validation: `python3 -c "import pathlib; t=pathlib.Path('docs/architecture.md').read_text(); assert all(s in t for s in ['n8n','Claude','Linear','nginx'])"`.

- [ ] **Create docs/runbook.md**
  - File: `docs/runbook.md`
  - Operational reference: how to deploy, check logs, debug n8n, rotate secrets,
    extend with a new workflow, rollback. References `deploy.sh` and `rollback.sh`.
  - Validation: `python3 -c "import pathlib; t=pathlib.Path('docs/runbook.md').read_text(); assert 'rollback.sh' in t and 'deploy.sh' in t"`.

- [ ] **Create docs/phases.md**
  - File: `docs/phases.md`
  - Roadmap reference: phases 1–6 with names, what gets built, and status
    (Phase 1 = complete after this build, 2–6 = planned). Maps directly to the
    phased roadmap table in SPECIFICATION.md.
  - Validation: `python3 -c "import pathlib; t=pathlib.Path('docs/phases.md').read_text(); assert all(str(i) in t for i in range(1,7))"`.

---

## Phase 2 — Slack + Learning *(planned)*

Not yet tasked. Depends on Phase 1 definition of done passing in full.
Key additions: Slack ingestion node, `weekly-learning.json` activation,
2-year Gmail backfill script.

## Phase 3 — NotebookLM MCP *(planned)*

Not yet tasked. Key additions: implement `agent/mcp/server.py`,
uncomment `notebook-mcp` in `docker-compose.yml`, add tool definition to
`system-prompt.md`.

## Phase 4 — Draft Outputs *(planned)*

## Phase 5 — Research Kicks *(planned)*

## Phase 6 — Auto-Execute *(planned)*

---

## Definition of done (Phase 1)

- [ ] `terraform apply` provisions Hetzner VPS with no errors
- [ ] `ansible-playbook playbook.yml` configures a fresh Ubuntu 24.04 and starts all services
- [ ] `deploy.sh` is idempotent: second run produces no changes
- [ ] n8n reachable at `https://${DOMAIN}` after deploy
- [ ] All three n8n workflows import without validation errors in n8n
- [ ] `validate-env.sh` exits 1 on a missing variable, 0 when all present
- [ ] `rollback.sh previous` restores the previous commit and redeploys
- [ ] Zero hardcoded secrets anywhere in the codebase
- [ ] All shell scripts pass `shellcheck` with no warnings
- [ ] All Terraform files pass `terraform validate`
- [ ] All test scripts in `scripts/tests/`, `agent/tests/`, `n8n/tests/`,
      and `infra/*/tests/` pass clean
