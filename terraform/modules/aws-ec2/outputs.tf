# What the module gives back. The same names as modules/proxmox-lxc (name, ip, id),
# so the inventory template (templates/inventory.ini.tftpl) works for both platforms.

output "name" {
  description = "Server name"
  value       = var.name
}

output "ip" {
  description = "PUBLIC IP address: Ansible and SSH connect here"
  value       = aws_instance.this.public_ip
}

output "private_ip" {
  description = "Private IP inside the VPC: the servers talk to each other here (app -> redis)"
  value       = aws_instance.this.private_ip
}

output "id" {
  description = "EC2 instance ID (i-0abc...)"
  value       = aws_instance.this.id
}