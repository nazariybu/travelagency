# Which Terraform and which providers (plugins) this folder needs.
# "terraform init" downloads them and writes the exact versions to .terraform.lock.hcl (commit it).
terraform {
  # 1.11+ is needed for "write-only" arguments (password_wo in database.tf):
  # the DB password goes to AWS, but is NEVER written to terraform.tfstate.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    # Talks to the AWS API: network, servers, load balancer, database
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
    # Reads the AWS keys and the DB password from HashiCorp Vault
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.13"
    }
    # Writes ansible/inventory-aws.ini
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
    # Finds your home public IP (only it may SSH to the servers), see security.tf
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
  }

  # State (terraform.tfstate) is a local file in this folder, NOT in Git (.gitignore), like envs/proxmox.
  # Each envs/* folder has its own state: AWS and Proxmox never touch each other.
}