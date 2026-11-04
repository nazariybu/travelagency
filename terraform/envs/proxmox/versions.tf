# Which Terraform and which providers (plugins) this folder needs.
# "terraform init" downloads them and writes the exact versions to .terraform.lock.hcl (commit it).
terraform {
  # 1.10+ is needed for "ephemeral" (a secret that is never written to the state file)
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    # Talks to the Proxmox API: creates, changes and deletes containers
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.1" # 0.116.x only: this provider has breaking changes in minor versions
    }
    # Reads the Proxmox token from HashiCorp Vault
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.12"
    }
    # Writes ansible/inventory.ini
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }

  # The state (terraform.tfstate) is a local file in this folder for now.
  # It is NOT in Git (.gitignore). In the cloud stage it moves to a remote backend (S3 bucket).
}