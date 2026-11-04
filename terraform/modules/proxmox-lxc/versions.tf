# The module says only WHICH provider it needs.
# The exact version is pinned once, in the root module (envs/proxmox/versions.tf).
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}