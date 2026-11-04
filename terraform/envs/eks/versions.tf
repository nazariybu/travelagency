# Which Terraform and which providers (plugins) this folder needs.
# "terraform init" downloads them and writes the exact versions to .terraform.lock.hcl (commit it).
terraform {
  # 1.11+ is needed for "write-only" arguments (password_wo in database.tf)
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    # Talks to the AWS API: network, IAM roles, EKS cluster, nodes, database
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
    # Reads the AWS keys and the DB password from HashiCorp Vault
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.13"
    }
    # Writes k8s/05-aws-generated.yaml (the RDS address and your IP for kubectl)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
    # Finds your home public IP (only it may use the Kubernetes API and open the site)
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
  }

  # Own local state in this folder (not in Git). envs/aws, envs/proxmox and envs/eks never touch each other.
}