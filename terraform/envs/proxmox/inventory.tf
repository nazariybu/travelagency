# Terraform writes ansible/inventory.ini from the same list of servers.
# One source of truth: add a server in terraform.tfvars -> apply -> Ansible already knows it.
# The template is shared with envs/aws (terraform/templates/inventory.ini.tftpl).

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../ansible/inventory.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/../../templates/inventory.ini.tftpl", {
    env = "proxmox"
    # only groups that have at least one server, in the order of inventory_groups
    groups = [for g in var.inventory_groups : g if contains([for s in values(var.servers) : s.group], g)]
    servers = {
      for name, s in var.servers : name => {
        ip         = module.server[name].ip
        private_ip = "" # home network: the IP Ansible uses is already the private one
        group      = s.group
      }
    }
    # [all:vars] at the end of the file
    all_vars = {
      ansible_user = "root"
    }
  })
}