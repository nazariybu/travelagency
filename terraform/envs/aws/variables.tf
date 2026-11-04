# All settings of this folder. Values that you change are in terraform.tfvars.

# --- AWS ---

variable "aws_region" {
  description = "AWS region (city of the data centres). eu-central-1 = Frankfurt, close to Ukraine"
  type        = string
  default     = "eu-central-1"
}

# --- Vault ---

variable "vault_address" {
  description = "Vault URL (home network). Also written to the AWS inventory for Ansible"
  type        = string
  default     = "http://192.168.18.109:8200"
}

variable "vault_kv_mount" {
  description = "KV v2 secrets engine path in Vault"
  type        = string
  default     = "secret"
}

variable "vault_aws_secret" {
  description = "Secret with the keys access_key_id and secret_access_key"
  type        = string
  default     = "travelagency/aws"
}

variable "vault_app_secret" {
  description = "Secret with the key db_password (the same one Ansible uses)"
  type        = string
  default     = "travelagency/app"
}

# --- Network ---

variable "network" {
  description = "VPC address range and subnets. Key of a subnet = availability zone letter (a, b)"
  type = object({
    vpc_cidr       = string
    public_subnets = map(string) # servers + load balancer, with internet
    db_subnets     = map(string) # RDS only, without internet
  })
  default = {
    vpc_cidr       = "10.20.0.0/16"
    public_subnets = { a = "10.20.1.0/24", b = "10.20.2.0/24" }
    db_subnets     = { a = "10.20.11.0/24", b = "10.20.12.0/24" }
  }
}

variable "site_open_to_world" {
  description = "false = only your home IP can open the site. true = anyone on the internet"
  type        = bool
  default     = false
}

variable "app_port" {
  description = "Tomcat port on every app node (same as app_port in ansible/group_vars/all.yml)"
  type        = number
  default     = 8080
}

# --- Servers ---

variable "ssh_public_key_file" {
  description = "Public key for the user ubuntu on every server (Ansible logs in with it)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "inventory_groups" {
  description = "Ansible groups in the order they appear in ansible/inventory-aws.ini"
  type        = list(string)
  default     = ["app", "redis"]
}

variable "servers" {
  description = "All EC2 servers. Key = name. optional(...) = default value if the line does not set it"
  type = map(object({
    ip            = string                       # fixed private IP, must be inside the subnet of its zone
    zone          = string                       # a or b (a key of network.public_subnets)
    group         = string                       # Ansible group: app or redis
    instance_type = optional(string, "t3.micro") # Free Tier size
    disk          = optional(number, 8)          # GB. Free Tier: 30 GB for ALL servers together
    swap          = optional(number, 0)          # MB
  }))

  validation {
    condition     = length(distinct([for s in values(var.servers) : s.ip])) == length(var.servers)
    error_message = "Two servers have the same ip."
  }

  validation {
    condition     = alltrue([for s in values(var.servers) : contains(keys(var.network.public_subnets), s.zone)])
    error_message = "Every server.zone must be a key of network.public_subnets (a or b)."
  }

  validation {
    condition     = alltrue([for s in values(var.servers) : contains(["app", "redis"], s.group)])
    error_message = "server.group must be app or redis (the database is RDS, see database.tf)."
  }
}

# --- Database (RDS) ---

variable "db_name" {
  description = "Database name (same as db_name in ansible/group_vars/all.yml)"
  type        = string
  default     = "travelagency"
}

variable "db_user" {
  description = "Database user (same as db_user in ansible/group_vars/all.yml)"
  type        = string
  default     = "travel"
}

variable "db_engine_version" {
  description = "MySQL version. 8.4 = LTS. NOT 8.0: its standard support ended on 31.07.2026, it costs extra now"
  type        = string
  default     = "8.4"
}

variable "db_instance_class" {
  description = "Size of the DB server. db.t4g.micro = Free Tier (2 vCPU ARM, 1 GB RAM)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_storage" {
  description = "DB disk in GB. Free Tier: 20 GB"
  type        = number
  default     = 20
}