# All settings of this folder. Values are in terraform.tfvars.

# --- Proxmox ---

variable "proxmox_endpoint" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://192.168.18.200:8006/"
}

variable "proxmox_insecure" {
  description = "true = do not check the HTTPS certificate (Proxmox has a self-signed one)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name (left column in the Proxmox UI)"
  type        = string
  default     = "pve"
}

variable "proxmox_api_token_id" {
  description = "API token ID: user@realm!token-name. Not secret; the secret part is in Vault"
  type        = string
  default     = "ansible@pve!ansible"
}

# --- Vault ---

variable "vault_address" {
  description = "Vault URL"
  type        = string
  default     = "http://192.168.18.109:8200"
}

variable "vault_kv_mount" {
  description = "KV v2 secrets engine path in Vault"
  type        = string
  default     = "secret"
}

variable "vault_proxmox_secret" {
  description = "Secret with the key token_secret"
  type        = string
  default     = "travelagency/proxmox"
}

# --- Settings for all containers ---

variable "lxc_template" {
  description = "LXC template for NEW containers (existing ones keep their OS)"
  type        = string
  default     = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
}

variable "datastore_id" {
  description = "Proxmox storage for root disks"
  type        = string
  default     = "local-lvm"
}

variable "network" {
  description = "Home network: bridge, gateway, mask length"
  type = object({
    bridge        = string
    gateway       = string
    prefix_length = number
  })
  default = {
    bridge        = "vmbr0"
    gateway       = "192.168.18.1"
    prefix_length = 24
  }
}

variable "ssh_public_key_file" {
  description = "Public key that goes to root of every container (Ansible logs in with it)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# --- Servers ---

variable "inventory_groups" {
  description = "Ansible groups in the order they appear in ansible/inventory.ini (empty groups are skipped)"
  type        = list(string)
  # "test" = for experiments: no playbook uses this group
  default = ["app", "db", "lb", "jenkins", "jenkins_agent", "redis", "monitoring", "vault", "test"]
}

variable "servers" {
  description = "All servers. Key = name. optional(...) = default value if the line does not set it"
  type = map(object({
    vm_id   = number
    ip      = string
    group   = string # Ansible group (one of inventory_groups)
    cores   = optional(number, 1)
    memory  = optional(number, 2048) # MB
    swap    = optional(number, 512)  # MB
    disk    = optional(number, 8)    # GB
    nesting = optional(bool, false)  # true = Docker can run inside
  }))

  validation {
    condition     = length(distinct([for s in values(var.servers) : s.vm_id])) == length(var.servers)
    error_message = "Two servers have the same vm_id."
  }

  validation {
    condition     = length(distinct([for s in values(var.servers) : s.ip])) == length(var.servers)
    error_message = "Two servers have the same ip."
  }

  validation {
    condition     = alltrue([for s in values(var.servers) : contains(var.inventory_groups, s.group)])
    error_message = "Every server.group must be one of inventory_groups."
  }
}