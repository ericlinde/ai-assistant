# MANUAL_SETUP.md — One-time human steps

Everything in this file requires a human with browser access or account credentials.
None of it can be automated. Do these once, in order, before running Terraform or Ansible.

---

## Overview: what goes where

```
GitHub Secrets          Ansible Vault              Infisical (prod env)
─────────────           ─────────────              ────────────────────
HCLOUD_TOKEN            vault_ssh_private_key       ANTHROPIC_API_KEY
SSH_PUBLIC_KEY          vault_infisical_token       LINEAR_API_KEY
DEPLOYER_IP             vault_domain                GMAIL_CLIENT_ID
SERVER_LOCATION         vault_admin_email           GMAIL_CLIENT_SECRET
SERVER_TYPE                                         GMAIL_REFRESH_TOKEN
R2_ACCESS_KEY_ID                                    SLACK_BOT_TOKEN
R2_SECRET_ACCESS_KEY                                GDRIVE_AGENT_MEMORY_FILE_ID
ANSIBLE_VAULT_PASSWORD                              GDRIVE_NOTEBOOK_REGISTRY_FILE_ID
                                                    GDRIVE_SERVICE_ACCOUNT_JSON
                                                    N8N_ENCRYPTION_KEY
                                                    N8N_BASIC_AUTH_PASSWORD
                                                    N8N_WEBHOOK_SECRET
                                                    N8N_API_KEY
                                                    DOMAIN
                                                    ADMIN_EMAIL
```

**Why this split:**
- GitHub Secrets = only what Terraform (CI) needs + the vault password to unlock everything else
- Ansible Vault = SSH key, Infisical token, server config — GitHub Actions decrypts the vault to get these
- Infisical = all app runtime secrets fetched by the running containers

---

## 1. SSH key pair

Generate a dedicated deploy key pair (do not reuse your personal key):

```bash
ssh-keygen -t ed25519 -C "agent-deploy" -f ~/.ssh/id_ed25519_agent_deploy -N ""
```

You will need:
- The **public key** content → GitHub Secret `SSH_PUBLIC_KEY`
  ```bash
  cat ~/.ssh/id_ed25519_agent.pub
  ```
- The **private key** content → Ansible Vault `vault_ssh_private_key` (step 12)
  ```bash
  cat ~/.ssh/id_ed25519_agent
  ```

The private key never goes into GitHub Secrets directly — it lives in Ansible Vault,
which GitHub Actions unlocks using `ANSIBLE_VAULT_PASSWORD`.

---

## 2. Hetzner Cloud

1. Create account at **hetzner.com**
2. Create a new project (e.g. "personal-agent")
3. Go to **Security → API Tokens → Generate API Token**
   - Name: `terraform`
   - Permissions: Read & Write
4. Copy the token → GitHub Secret `HCLOUD_TOKEN`

Choose your datacenter and server size:
- `SERVER_LOCATION`: e.g. `hel1` (Helsinki), `fsn1` (Falkenstein), `nbg1` (Nuremberg)
- `SERVER_TYPE`: `cx22` (2 vCPU / 4 GB RAM, ~€4/mo) is sufficient for Phase 1

---

## 3. Domain and DNS

1. Point a (sub)domain at the VPS IP — you won't know the IP until after `terraform apply`
2. After Terraform runs, get the IP from the output (`server_ip`) and add an **A record**:
   - Host: `agent` (or whatever subdomain you chose)
   - Value: `<server_ip>`
   - TTL: 300

This domain becomes `DOMAIN` in Infisical (e.g. `agent.yourdomain.com`).

---

## 4. Cloudflare R2 (Terraform state backend)

1. Log in to **dash.cloudflare.com**
2. Go to **R2 Object Storage → Create bucket**
   - Name: `agent-terraform-state`
   - Location: default
3. Go to **R2 → Manage R2 API Tokens → Create API token** (Account API Token)
   - Permissions: Object Read & Write
   - Bucket: `agent-terraform-state`
4. Save the credentials:
   - Access Key ID → GitHub Secret `R2_ACCESS_KEY_ID`
   - Secret Access Key → GitHub Secret `R2_SECRET_ACCESS_KEY`
5. Your Account ID (visible on the R2 overview page) is already baked into
   `infra/terraform/versions.tf` — no action needed unless you change accounts.

---

## 5. GitHub Secrets

Go to **github.com → your repo → Settings → Secrets and variables → Actions → New repository secret**.

Add all eight:

| Secret | Where to get it |
|---|---|
| `HCLOUD_TOKEN` | Step 2 |
| `SSH_PUBLIC_KEY` | Step 1 — full contents of `~/.ssh/id_ed25519_agent.pub` |
| `DEPLOYER_IP` | Your current public IP — check at whatismyip.com |
| `SERVER_LOCATION` | Your choice — e.g. `hel1` |
| `SERVER_TYPE` | e.g. `cx22` |
| `R2_ACCESS_KEY_ID` | Step 4 |
| `R2_SECRET_ACCESS_KEY` | Step 4 |
| `ANSIBLE_VAULT_PASSWORD` | Your chosen vault password from step 12 |

Note: `ANSIBLE_VAULT_PASSWORD` must be added after step 12 (you choose the password there).

---

## 6. Anthropic API key

1. Go to **console.anthropic.com → API Keys → Create Key**
2. Copy the key → Infisical secret `ANTHROPIC_API_KEY`

---

## 7. Linear API key

1. Go to **linear.app → Settings → API → Personal API keys → Create key**
2. Copy the key → Infisical secret `LINEAR_API_KEY`

The team ID and project ID are already hardcoded in `.env.example` — no action needed.

---

## 8. Google Cloud: Gmail OAuth2 + Drive service account

Both credentials come from the same Google Cloud project.

### 8a. Create a Google Cloud project

1. Go to **console.cloud.google.com → New Project** (e.g. "personal-agent")
2. Enable APIs:
   - **Gmail API**
   - **Google Drive API**

### 8b. Gmail OAuth2 credentials

1. Go to **APIs & Services → Credentials → Create Credentials → OAuth client ID**
   - Application type: Web application
   - Authorised redirect URIs: `https://developers.google.com/oauthplayground`
2. Download the credentials — note `client_id` and `client_secret`
3. Go to **OAuth 2.0 Playground** (developers.google.com/oauthplayground)
   - Click the gear icon → check "Use your own OAuth credentials" → enter client ID + secret
   - Scope: `https://www.googleapis.com/auth/gmail.readonly`
   - Authorise → exchange for tokens → copy the **Refresh Token**
4. Add to Infisical:
   - `GMAIL_CLIENT_ID`
   - `GMAIL_CLIENT_SECRET`
   - `GMAIL_REFRESH_TOKEN`

### 8c. Google Drive service account

1. Go to **APIs & Services → Credentials → Create Credentials → Service account**
   - Name: `agent-drive`
2. Go to the service account → **Keys → Add key → JSON** — download the file
3. Base64-encode the JSON:
   ```bash
   base64 -w 0 service-account.json
   ```
4. Add the base64 string → Infisical secret `GDRIVE_SERVICE_ACCOUNT_JSON`

---

## 9. Google Drive: agent memory files

1. Go to **drive.google.com** and create a new folder (e.g. "agent-data")
2. Upload `agent/memory/agent-memory.md` — rename it to `agent-memory.md`
3. Upload `agent/memory/notebook-registry.md` — rename it to `notebook-registry.md`
4. Share both files with the service account email (from step 8c) — **Editor** access
5. Get each file's ID from the URL:
   `https://drive.google.com/file/d/<FILE_ID>/view`
6. Add to Infisical:
   - `GDRIVE_AGENT_MEMORY_FILE_ID`
   - `GDRIVE_NOTEBOOK_REGISTRY_FILE_ID`

---

## 10. Slack bot token

1. Go to **api.slack.com/apps → Create New App → From scratch**
2. Add OAuth scope: `channels:history`, `channels:read`, `chat:write`
3. Install to workspace → copy **Bot User OAuth Token** (starts with `xoxb-`)
4. Add to Infisical: `SLACK_BOT_TOKEN`

---

## 11. Infisical setup

1. Create account at **app.infisical.com**
2. Create a new project (e.g. "personal-agent")
3. Go to **Settings → Machine Identities → Create** — name it `agent-runtime`
   - Copy the token → Ansible Vault `vault_infisical_token`
4. Add all secrets listed in the Infisical column of the overview table above.
   Fastest way via CLI (run once):
   ```bash
   infisical secrets set ANTHROPIC_API_KEY <value>
   infisical secrets set LINEAR_API_KEY <value>
   # ... repeat for each secret
   ```
5. Generate values for the n8n secrets:
   ```bash
   # N8N_ENCRYPTION_KEY — random 32-char string
   openssl rand -hex 16
   # N8N_BASIC_AUTH_PASSWORD — strong password of your choice
   # N8N_WEBHOOK_SECRET — random string for validating Gmail Pub/Sub payloads
   openssl rand -hex 16
   # N8N_API_KEY — set this after first n8n login (Settings → API → Create)
   ```

---

## 12. Ansible Vault

Use `ansible-vault create` — this opens your editor in an encrypted context so
plaintext values are **never written to disk unencrypted**. Do not use a plain
text editor to write secrets directly into the repo.

```bash
ansible-vault create infra/ansible/group_vars/all/vault.yml
```

You will be prompted for a vault password — choose a strong one and store it in
your password manager. Fill in the following in your editor:

```yaml
vault_ssh_private_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  <paste contents of ~/.ssh/id_ed25519_agent here>
  -----END OPENSSH PRIVATE KEY-----
vault_infisical_token: "<from Infisical step 11>"
vault_domain: "agent.yourdomain.com"
vault_admin_email: "you@yourdomain.com"
```

Save and close — the file is encrypted immediately on save. To edit later:
```bash
ansible-vault edit infra/ansible/group_vars/all/vault.yml
```

Commit the encrypted file — it is safe and required for CI:
```bash
git add infra/ansible/group_vars/all/vault.yml
git commit -m "Add encrypted Ansible Vault"
git push
```

Then add the vault password to GitHub Secrets as `ANSIBLE_VAULT_PASSWORD` (step 5).

---

## 13. Ansible inventory

No inventory file is needed for CI runs. The Ansible GitHub Actions workflow reads
the server IP directly from Terraform state (`tofu output server_ip`) and constructs
a dynamic inventory on the fly.

For local Ansible runs (debugging), create an inventory manually after `terraform apply`:
```bash
cp infra/ansible/inventory.example infra/ansible/inventory
# Edit infra/ansible/inventory and replace the placeholder IP with the real server_ip
```

---

## 14. First deploy

With all of the above done:

```bash
# 1. Trigger Terraform via GitHub Actions (provisions VPS)
#    Go to: Actions → Terraform → Run workflow
#    OR merge the PR — it triggers automatically on push to main

# 2. Note the server_ip from the Actions log output

# 3. Update DNS A record (step 3) with the server_ip

# 4. Update infra/ansible/inventory with the server_ip and commit + push
#    GitHub Actions (Ansible workflow) will trigger automatically

# 5. Watch the Ansible workflow run in: Actions → Ansible

# 6. Visit https://<DOMAIN> — n8n should be running
```

To run Ansible locally instead (e.g. for debugging):
```bash
ansible-playbook -i infra/ansible/inventory infra/ansible/playbook.yml --ask-vault-pass
```

---

## 15. Post-deploy: n8n API key

After n8n is running:

1. Log in to `https://<DOMAIN>` with `admin` / `N8N_BASIC_AUTH_PASSWORD`
2. Go to **Settings → API → Create API Key**
3. Copy the key → update Infisical secret `N8N_API_KEY`
4. Re-run `deploy.sh` to import workflows using the new key:
   ```bash
   ssh root@<server_ip> "cd /opt/agent && bash scripts/deploy.sh"
   ```

---

## 16. Post-deploy: Gmail push notifications (optional — enables realtime-webhook)

1. Go to **console.cloud.google.com → Pub/Sub → Create topic** (e.g. `gmail-push`)
2. Create a subscription → Push → endpoint: `https://<DOMAIN>/webhook/gmail`
3. In Gmail API settings, set up a watch on your inbox pointing to the Pub/Sub topic
4. The `realtime-webhook.json` n8n workflow handles incoming Pub/Sub messages automatically
