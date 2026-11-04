# Printed after "terraform apply" and by "terraform output".

output "site_url" {
  description = "The site, through the load balancer"
  value       = "http://${aws_lb.this.dns_name}"
}

output "servers" {
  description = "Name -> public IP (SSH: ssh ubuntu@<ip>)"
  value       = { for name, m in module.server : name => m.ip }
}

output "private_ips" {
  description = "Name -> private IP inside the VPC"
  value       = { for name, m in module.server : name => m.private_ip }
}

output "db_endpoint" {
  description = "RDS MySQL address (works only from inside the VPC)"
  value       = aws_db_instance.this.address
}

output "my_ip" {
  description = "Your home public IP: only it may SSH (and open the site if site_open_to_world = false)"
  value       = local.my_ip_cidr
}

output "inventory_file" {
  description = "Ansible inventory written by Terraform"
  value       = abspath(local_file.ansible_inventory.filename)
}