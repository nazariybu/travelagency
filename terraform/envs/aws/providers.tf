# How Terraform logs in to Vault and to AWS. No secrets in this file.

# Vault: the same login as for envs/proxmox and Ansible.
# "vault login -method=userpass username=nazariy" once in 8 hours, the token is in ~/.vault-token.
provider "vault" {
  address          = var.vault_address
  skip_child_token = true # same reason as envs/proxmox/providers.tf
}

# AWS access key of the IAM user "terraform-travelagency".
# "ephemeral" = read on every plan/apply, kept only in memory, never written to terraform.tfstate.
ephemeral "vault_kv_secret_v2" "aws" {
  mount = var.vault_kv_mount   # secret
  name  = var.vault_aws_secret # travelagency/aws
}

provider "aws" {
  region     = var.aws_region
  access_key = ephemeral.vault_kv_secret_v2.aws.data["access_key_id"]
  secret_key = ephemeral.vault_kv_secret_v2.aws.data["secret_access_key"]

  # These tags go to EVERY resource. After "terraform destroy" you can search the whole account
  # for Project = travelagency (Resource Groups -> Tag Editor) and see that nothing is left.
  default_tags {
    tags = {
      Project   = "travelagency"
      ManagedBy = "terraform"
      Env       = "aws"
    }
  }
}