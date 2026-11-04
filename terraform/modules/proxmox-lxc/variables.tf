# Inputs of one server.
# The first block is the same for every platform (Proxmox now, a cloud later):
# a future module "aws-vm" or "hetzner-vm" takes the same names, so envs/* only swaps the module.

# --- Common inputs (any platform) ---

variable "name" {
  description = "Server name, also the hostname inside it (vm-app, vm-db ...)"
  type        = string
}

variable "ip" {
  description = "Fixed IPv4 address, without /24"
  type        = string
}

variable "cores" {
  description = "CPU cores"
  type        = number
}

variable "memory" {
  description = "RAM in MB"
  type        = number
}

variable "disk" {
  description = "Root disk size in GB"
  type        = number
}

variable "ssh_public_key" {
  description = "Public SSH key for root (text of ~/.ssh/id_ed25519.pub). Ansible logs in with it"
  type        = string
}

variable "tags" {
  description = "Labels shown in the Proxmox UI (lower case)"
  type        = list(string)
  default     = []
}

# --- Proxmox-only inputs ---

variable "node_name" {
  description = "Proxmox node (host) name"
  type        = string
}

variable "vm_id" {
  description = "Proxmox container ID (301, 302 ...)"
  type        = number
}

variable "swap" {
  description = "Swap in MB"
  type        = number
}

variable "nesting" {
  description = "Allow containers inside the container (needed for Docker)"
  type        = bool
  default     = false
}

variable "template_file_id" {
  description = "LXC template, e.g. local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  type        = string
}

variable "datastore_id" {
  description = "Proxmox storage for the root disk"
  type        = string
}

variable "bridge" {
  description = "Proxmox network bridge"
  type        = string
}

variable "gateway" {
  description = "Default gateway (the router)"
  type        = string
}

variable "prefix_length" {
  description = "Network mask length: 24 means 255.255.255.0"
  type        = number
}