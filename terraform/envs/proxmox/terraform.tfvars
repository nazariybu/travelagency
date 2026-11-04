# What exists in Proxmox. Terraform makes Proxmox look like this file.
# Same list as the old ansible/provision.yml.
#   add a line    -> terraform apply creates the container
#   change a line -> terraform apply changes it (some changes restart the container, read the plan!)
#   delete a line -> terraform apply DELETES the container with all its data
# Not set in a line = default from variables.tf: cores 1, memory 2048, swap 512, disk 8, nesting false.

servers = {
  "vm-app"     = { vm_id = 301, ip = "192.168.18.101", group = "app" }
  "vm-app2"    = { vm_id = 305, ip = "192.168.18.105", group = "app" }
  "vm-db"      = { vm_id = 302, ip = "192.168.18.102", group = "db" }
  "vm-lb"      = { vm_id = 306, ip = "192.168.18.106", group = "lb", memory = 512 }
  "vm-redis"   = { vm_id = 307, ip = "192.168.18.107", group = "redis", memory = 512 }
  "vm-jenkins" = { vm_id = 303, ip = "192.168.18.103", group = "jenkins", cores = 1, memory = 2048, disk = 16, nesting = true }
  "vm-agent"   = { vm_id = 304, ip = "192.168.18.104", group = "jenkins_agent", cores = 4, memory = 4096, disk = 32, nesting = true }
  "vm-monitor" = { vm_id = 309, ip = "192.168.18.108", group = "monitoring", cores = 2, memory = 2048, disk = 16, nesting = true }
  "vm-vault"   = { vm_id = 310, ip = "192.168.18.109", group = "vault", memory = 512 }
}