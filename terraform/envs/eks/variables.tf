# All settings of this folder. Values that you change are in terraform.tfvars.

# --- AWS ---

variable "aws_region" {
  description = "AWS region. eu-central-1 = Frankfurt, the same as the Cloud stage"
  type        = string
  default     = "eu-central-1"
}

# --- Vault ---

variable "vault_address" {
  description = "Vault URL (home network)"
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
    public_subnets = map(string) # Kubernetes nodes + load balancer, with internet
    db_subnets     = map(string) # RDS only, without internet
  })
  # 10.30.x.x: different from envs/aws (10.20.x.x), so both could even exist at the same time
  default = {
    vpc_cidr       = "10.30.0.0/16"
    public_subnets = { a = "10.30.1.0/24", b = "10.30.2.0/24" }
    db_subnets     = { a = "10.30.11.0/24", b = "10.30.12.0/24" }
  }
}

variable "site_open_to_world" {
  description = "false = only your home IP can open the site. true = anyone on the internet"
  type        = bool
  default     = false
}

# --- Kubernetes (EKS) ---

variable "cluster_name" {
  description = "Name of the EKS cluster (also in kubectl config and in the AWS console)"
  type        = string
  default     = "travelagency"
}

variable "kubernetes_version" {
  description = "Kubernetes version. 1.36: standard support until 08.2027 (old versions cost 6x more: Extended Support)"
  type        = string
  default     = "1.36"
}

variable "node_instance_types" {
  description = "EC2 sizes the nodes may use. Several = more chances to get a Spot server. *.medium = 2 vCPU, 4 GB"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium", "t2.medium"]
}

variable "node_capacity_type" {
  description = "SPOT = spare AWS servers, ~60-70 % cheaper, AWS may take one back (2 min warning). ON_DEMAND = normal price"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.node_capacity_type)
    error_message = "node_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "node_count" {
  description = "How many worker nodes (EC2 servers for pods). 2 = pods survive one node"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Disk of every node in GB (images of containers live here)"
  type        = number
  default     = 20
}

# --- Database (RDS) ---

variable "db_name" {
  description = "Database name (same as in ansible/group_vars/all.yml)"
  type        = string
  default     = "travelagency"
}

variable "db_user" {
  description = "Database user (same as in ansible/group_vars/all.yml)"
  type        = string
  default     = "travel"
}

variable "db_engine_version" {
  description = "MySQL version. 8.4 = LTS (8.0 costs extra since 31.07.2026)"
  type        = string
  default     = "8.4"
}

variable "db_instance_class" {
  description = "Size of the DB server. db.t4g.micro = the smallest (2 vCPU ARM, 1 GB RAM)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_storage" {
  description = "DB disk in GB"
  type        = number
  default     = 20
}