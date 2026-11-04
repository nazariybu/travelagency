# Printed after "terraform apply" and by "terraform output".

output "servers" {
  description = "Name -> IP of every server"
  value       = { for name, m in module.server : name => m.ip }
}

output "proxmox_ids" {
  description = "Name -> Proxmox node/vmid"
  value       = { for name, m in module.server : name => m.id }
}

output "inventory_file" {
  description = "Ansible inventory written by Terraform"
  value       = abspath(local_file.ansible_inventory.filename)
}