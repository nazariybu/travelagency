# Inputs of one server in AWS (one EC2 virtual machine).
# The first block uses the same names as modules/proxmox-lxc, so both envs/* folders look alike.
# "cores" and "memory" are not here: in the cloud you do not set them one by one,
# you pick a ready size (instance_type). t3.micro = 2 vCPU + 1 GB RAM.

# --- Common inputs (any platform) ---

variable "name" {
  description = "Server name, also the hostname inside it (aws-app1, aws-redis ...)"
  type        = string
}

variable "ip" {
  description = "Fixed PRIVATE IPv4 address inside the subnet (10.20.1.101 ...). The public IP is given by AWS"
  type        = string
}

variable "disk" {
  description = "Root disk (EBS volume) size in GB"
  type        = number
}

variable "swap" {
  description = "Swap file in MB, 0 = no swap. t3.micro has only 1 GB RAM, Maven + Tomcat need more"
  type        = number
  default     = 0
}

variable "ssh_public_key" {
  description = "Public SSH key (text of ~/.ssh/id_ed25519.pub) for the user ubuntu. Ansible logs in with it"
  type        = string
}

variable "tags" {
  description = "Labels, saved in the AWS tag Labels (lower case)"
  type        = list(string)
  default     = []
}

# --- AWS-only inputs ---

variable "instance_type" {
  description = "Size of the virtual machine, e.g. t3.micro (Free Tier)"
  type        = string
}

variable "ami_id" {
  description = "Disk image to start from (AMI). envs/aws finds the newest official Ubuntu 22.04"
  type        = string
}

variable "subnet_id" {
  description = "Subnet (part of the VPC in one availability zone) where the server lives"
  type        = string
}

variable "security_group_ids" {
  description = "Firewalls (security groups) of this server"
  type        = list(string)
}