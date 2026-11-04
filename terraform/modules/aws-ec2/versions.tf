# The module says only WHICH provider it needs.
# The exact version is pinned once, in the root module (envs/aws/versions.tf).
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}