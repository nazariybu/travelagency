# Report: secrets in HashiCorp Vault

## 1. Goal

Move all passwords and tokens out of `ansible/.env` and out of Jenkins credentials into one secret store.
Every reader (a person, Jenkins) logs in with its own identity and may read only the secrets it needs.
Stage: "Secrets (Vault)".

## 2. Before

| Secret | Where it was | Problem |
|--------|--------------|---------|
| `DB_PASSWORD`, `REDIS_PASSWORD` | `ansible/.env` **and** Jenkins credentials `db-password`, `redis-password` | Two copies: change one, forget the other |
| `GRAFANA_ADMIN_PASSWORD`, `PVE_EXPORTER_TOKEN`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | `ansible/.env` | Plain text file, anyone with a shell on the ansible host reads it |
| `PROXMOX_TOKEN_SECRET` (can create and delete containers!) | `ansible/.env` | Same file as the less dangerous secrets, no separation |
| All | `set -a; source .env` | Secrets in environment variables of the terminal: visible to every process started from it. No log of who read what. Forgot `source` = empty password |

## 3. Choices

| Need | Option | Plus | Minus |
|------|--------|------|-------|
| Secret store | **HashiCorp Vault** ✅ | Industry standard, policies per path, many login methods, audit log, secret versions, UI | One more server; sealed after restart; BSL license since 2023 |
| | OpenBao | Open source fork of Vault (MPL), same commands | Smaller community, fewer guides |
| | Ansible Vault (`ansible-vault encrypt`) | Nothing to run, file in Git | One shared password for all secrets, no per-reader access, Jenkins needs that password |
| | Jenkins credentials only | Already there | Only Jenkins can use them; Ansible on the ansible host cannot |
| Where Vault runs | **Own LXC `vm-vault`** ✅ | Not on vm-monitor or Jenkins: if they are broken into, the store is still separate | +512 MB RAM |
| Storage | **Integrated storage (raft)** ✅ | Built in, recommended by HashiCorp, can grow to 3 nodes for HA | — |
| | File storage | Simple | Not recommended any more, no HA |
| Secrets engine | **KV version 2** ✅ | Keeps old versions, `kv patch`, `kv rollback` | Paths have `data/` and `metadata/` inside (policies must use them) |
| Login for a person | **userpass** ✅ | Simple, token with 8 h TTL | Password managed in Vault (in a company: OIDC / LDAP) |
| Login for Jenkins | **AppRole** ✅ | Made for machines: role_id + secret_id, can be bound to the agent IP | `secret_id` is still a secret kept in Jenkins ("secret zero") |
| How Ansible reads | **`community.hashi_vault.vault_kv2_get` lookup** ✅ | Read at run time, no secret on disk on the ansible host | Needs `hvac` and the collection on every Ansible controller |
| Unseal | **Manual, Shamir 3 keys / threshold 2** ✅ | No extra service, you see how it works | After every restart a person must unseal |
| | Auto-unseal (cloud KMS, Transit of another Vault) | No manual step | Needs a cloud account or a second Vault |
| TLS | **Off (HTTP)** ⚠️ | Simple for the home lab | Passwords go over the LAN in plain text. Next step: own CA + certificate, `tls_cert_file`, `ca_cert` in the lookups |

## 4. Design

- Paths split by **who needs them**: `app` (Jenkins + Ansible), `monitoring`, `proxmox`.
  So the Jenkins policy is one line: read `secret/data/travelagency/app`.
- AppRole `jenkins-deploy`: `token_ttl=20m`, `secret_id_bound_cidrs` and `token_bound_cidrs` = `192.168.18.104/32`.
  A stolen `role_id` + `secret_id` do not work from another machine.
- `group_vars/all.yml`: `vault_app`, `vault_monitoring`, `vault_proxmox` are lookups. Ansible evaluates a
  variable only when a task uses it, so `app.yml` from Jenkins never asks for `monitoring` (it would be denied).
- Login method is not in the code: the lookup uses the token from `~/.vault-token` by default (you),
  Jenkins sets `ANSIBLE_HASHI_VAULT_AUTH_METHOD=approle` and the two IDs as environment variables.
- `provision.yml` can still take `PROXMOX_TOKEN_SECRET` from the terminal: only to create vm-vault itself
  (chicken and egg: Vault cannot give the token that creates Vault).
- Monitoring: node_exporter on vm-vault (it is in `all`), and blackbox probes `/v1/sys/health`
  (200 only when unsealed), so a sealed Vault sends `SiteDown` to Telegram.

## 5. Setup commands (once)

On the ansible host, `export VAULT_ADDR=http://192.168.18.109:8200`, logged in with the root token.

```bash
vault secrets enable -path=secret kv-v2
vault policy write travelagency-admin vault/policies/travelagency-admin.hcl
vault policy write jenkins-deploy     vault/policies/jenkins-deploy.hcl

vault auth enable userpass
vault write auth/userpass/users/nazariy password="$P" token_policies=travelagency-admin token_ttl=8h token_max_ttl=24h

vault auth enable approle
vault write auth/approle/role/jenkins-deploy token_policies=jenkins-deploy token_ttl=20m token_max_ttl=30m \
  secret_id_bound_cidrs=192.168.18.104/32 token_bound_cidrs=192.168.18.104/32
vault read -field=role_id auth/approle/role/jenkins-deploy/role-id          # -> Jenkins credential vault-role-id
vault write -f -field=secret_id auth/approle/role/jenkins-deploy/secret-id  # -> Jenkins credential vault-secret-id

vault kv put secret/travelagency/app        db_password=... redis_password=...
vault kv put secret/travelagency/monitoring grafana_admin_password=... pve_exporter_token=... telegram_bot_token=... telegram_chat_id=...
vault kv put secret/travelagency/proxmox    token_secret=...
```

## 6. Results

Run on 03.11.2026.

| Check | Expected | Result |
|-------|----------|--------|
| `vault status` | `Initialized true`, `Sealed false`, `Storage Type raft` | ✅ OK |
| `vault version` | | `Vault v2.2.1` |
| `ansible-playbook app.yml` with the secrets from Vault | `failed=0`; DB user and `travelagency.conf` (passwords) `ok`, not `changed` = the same passwords came from Vault. The WAR is rebuilt because the branch changed | ✅ OK |
| `ansible-playbook monitoring.yml` | `failed=0`, node_exporter on vm-vault, Prometheus target `vm-vault` UP | ✅ OK |
| `ansible/.env` | deleted, `env \| grep -cE 'PASSWORD\|TOKEN_SECRET\|BOT_TOKEN'` = 0 | ✅ OK (0) |
| Ansible reads secrets only from Vault (ad-hoc `debug` of the secret lengths, no `.env`) | lengths > 0 | ✅ OK |
| Jenkins build of `secrets-vault`, stage Deploy | green, no `db-password` / `redis-password` credentials in Jenkins | ✅ OK |
| Token with policy `jenkins-deploy` reads `secret/travelagency/monitoring` | `permission denied` (403); `app` is readable | ✅ OK |
| Restart Vault | `Sealed true`, playbook fails with "Vault is sealed", Telegram `SiteDown`; after 2 unseal keys all OK | ✅ OK |

### Problems found during the setup

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 1 | `provision.yml` failed with `No Vault Token specified or discovered` although `PROXMOX_TOKEN_SECRET` was set | `proxmox_token: "{{ A if A else vault_proxmox... }}"`: this Ansible version templated **both** parts of the inline `if`, so it asked Vault before Vault existed | Two `set_fact` tasks: first from the terminal, second from Vault with `when: proxmox_token \| length == 0`. A task skipped by `when` is not templated at all (commit `fix(provision)`) |
| 2 | `'db_password' is undefined` in an ad-hoc `ansible localhost ...` | Command was run in the repo root: `ansible.cfg`, `inventory.ini`, `group_vars/` are read from the current folder | Run Ansible commands from `ansible/` |
| 3 | `ansible-galaxy collection install` said "Nothing to do" | `community.hashi_vault` already comes with the `ansible` package | Nothing to fix, the installed version matches `>=6.2.0,<7.0.0` |

## 7. What is still not perfect

| # | What | Next step |
|---|------|-----------|
| 1 | HTTP without TLS between Ansible and Vault | Own CA, certificate for 192.168.18.109, `tls_cert_file`/`tls_key_file`, `ca_cert` option in the lookups |
| 2 | Manual unseal after every restart | Auto-unseal (Transit or cloud KMS) when the project moves to the cloud |
| 3 | `secret_id` of Jenkins never expires | Rotate it: new `secret-id`, update Jenkins, `secret-id/destroy` the old one; or `secret_id_ttl` |
| 4 | Static passwords (same DB password for months) | Database secrets engine: Vault creates a MySQL user per deploy with a short TTL |
| 5 | No audit log | `vault audit enable file file_path=/var/log/vault_audit.log`, send it to Loki with Alloy |
| 6 | One Vault node | Raft cluster of 3 nodes |
| 7 | `dockerhub-creds` still in Jenkins | Jenkins HashiCorp Vault plugin, or read it in the pipeline with the same AppRole |
