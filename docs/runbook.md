# Runbook

## Deploy

```bash
bash scripts/deploy.sh
```

Runs `validate-env.sh`, pulls Docker images, starts services, health-checks
n8n, and imports workflows. Idempotent — safe to run multiple times.

## Rollback

```bash
bash scripts/rollback.sh previous        # roll back one commit
bash scripts/rollback.sh <sha>           # roll back to a specific commit
```

Checks out the target commit and calls `deploy.sh`. See `scripts/rollback.sh`.

## Check logs

```bash
# All services
docker compose logs -f

# n8n only
docker compose logs -f n8n

# nginx only
docker compose logs -f nginx
```

## Debug n8n

1. Open `https://<DOMAIN>` in a browser.
2. Log in with the credentials from your `.env` (`N8N_BASIC_AUTH_*`).
3. Go to **Executions** to see recent workflow runs and error details.
4. To manually trigger a workflow: open it → click **Execute Workflow**.

## Rotate secrets

### App runtime secrets (Infisical)

Update the secret in Infisical Cloud and restart n8n to pick up the new value:
```bash
infisical secrets set KEY new-value
infisical run -- docker compose restart n8n
```

### Infisical machine identity token (Ansible Vault)

1. Update in Ansible Vault:
   ```bash
   ansible-vault edit infra/ansible/group_vars/all/vault.yml
   ```
2. Re-run the agent role to write the new token to `/opt/agent/.token`:
   ```bash
   ansible-playbook -i infra/ansible/inventory infra/ansible/playbook.yml \
     --tags agent --ask-vault-pass
   ```

## Add a new n8n workflow

1. Export the workflow from n8n as JSON (Settings → Export).
2. Rename the file to match the workflow's `name` field, e.g. `my-workflow.json`.
3. Place it in `n8n/workflows/`.
4. Validate: `python n8n/tests/test-workflow-schema.py my-workflow`.
5. Commit and run `deploy.sh` — it will import the workflow automatically.

## Extend with a new service

Add a block to `docker-compose.yml` only. Do not restructure existing services.
See `CLAUDE.md` for the full constraint list.

## Full reprovisioning from zero

```bash
# 1. Provision VPS with Terraform (via GitHub Actions or locally)
cd infra/terraform && tofu apply

# 2. Bootstrap the new server
ssh root@<SERVER_IP> "curl -fsSL https://raw.githubusercontent.com/ericlinde/ai-assistant/main/scripts/setup.sh | bash"

# 3. Configure secrets
ssh deploy@<SERVER_IP>
cp /opt/agent-deploy/.env.example /opt/agent-deploy/.env
vi /opt/agent-deploy/.env  # fill in all values

# 4. Run Ansible
ansible-playbook -i infra/ansible/inventory infra/ansible/playbook.yml --ask-vault-pass

# 5. Verify
curl https://<DOMAIN>/healthz
```
