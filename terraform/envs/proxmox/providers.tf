# How Terraform logs in to Vault and to Proxmox. No secrets in this file.

# Vault: the same login as Ansible uses.
# You run "vault login -method=userpass username=nazariy" once in 8 hours, the token goes to ~/.vault-token,
# and this provider reads it from there.
provider "vault" {
  address = var.vault_address

  # By default the provider makes a short "child" token for itself. That needs the right
  # "update" on auth/token/create, and the travelagency-admin policy does not give it.
  # Our token already lives only 8 hours, so we use it directly. (REPORT.md: how to turn it back on.)
  skip_child_token = true
}

# "ephemeral" = read on every plan/apply, kept only in memory, NEVER written to terraform.tfstate.
# (A normal "data" block would save the token in plain text in the state file.)
ephemeral "vault_kv_secret_v2" "proxmox" {
  mount = var.vault_kv_mount       # secret
  name  = var.vault_proxmox_secret # travelagency/proxmox
}

# Proxmox API with an API token: "user@realm!token-name=secret".
# The first part is not secret (variables.tf), the secret part comes from Vault.
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_api_token_id}=${ephemeral.vault_kv_secret_v2.proxmox.data["token_secret"]}"
  insecure  = var.proxmox_insecure # Proxmox uses a self-signed HTTPS certificate
}