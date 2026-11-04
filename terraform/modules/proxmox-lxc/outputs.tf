# What the module gives back. A cloud module must give back the same names,
# so the inventory template (templates/inventory.ini.tftpl) works with any platform.

output "name" {
  description = "Server name"
  value       = var.name
}

output "ip" {
  description = "IP address Ansible connects to"
  value       = var.ip
}

output "id" {
  description = "Proxmox ID: node/vmid"
  value       = "${var.node_name}/${proxmox_virtual_environment_container.this.vm_id}"
}