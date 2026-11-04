# Terraform writes ansible/inventory-aws.ini, with the same template as envs/proxmox.
# Ansible: ansible-playbook -i inventory-aws.ini <playbook>.yml
# The file is NOT in Git (.gitignore): the public IPs change every time the servers are re-created.

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../ansible/inventory-aws.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/../../templates/inventory.ini.tftpl", {
    env = "aws"
    # only groups that have at least one server, in the order of inventory_groups
    groups = [for g in var.inventory_groups : g if contains([for s in values(var.servers) : s.group], g)]
    servers = {
      for name, s in var.servers : name => {
        ip         = module.server[name].ip         # public: Ansible connects here
        private_ip = module.server[name].private_ip # private: Redis listens here, the app connects here
        group      = s.group
      }
    }
    # [all:vars] at the end of the file
    all_vars = {
      ansible_user  = "ubuntu"                     # EC2 Ubuntu: no SSH as root, Ansible uses sudo
      db_endpoint   = aws_db_instance.this.address # RDS address instead of the [db] server
      vault_address = var.vault_address            # Vault stays at home, there is no [vault] server in AWS
    }
  })
}