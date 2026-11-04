# One LXC container in Proxmox.
# Same settings as the old ansible/provision.yml (community.proxmox.proxmox).

resource "proxmox_virtual_environment_container" "this" {
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "Managed by Terraform (terraform/envs/proxmox). Change it in code, not in the Proxmox UI."
  tags        = sort(var.tags) # Proxmox keeps tags sorted; same order here = no false changes

  unprivileged  = true # root inside the container is NOT root on the Proxmox host
  started       = true
  start_on_boot = true # start again after the Proxmox host reboots

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk
  }

  # Only vm-jenkins, vm-agent, vm-monitor need it (they run Docker).
  # "dynamic" writes the block only when nesting = true.
  dynamic "features" {
    for_each = var.nesting ? [1] : []
    content {
      nesting = true
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  initialization {
    hostname = var.name

    ip_config {
      ipv4 {
        address = "${var.ip}/${var.prefix_length}"
        gateway = var.gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  lifecycle {
    # Proxmox uses these two only when it CREATES a container and does not keep them.
    # After "terraform import" they are empty in the state, and a change here would mean
    # "delete the container and create a new one". We ignore them: new containers still get them.
    ignore_changes = [
      operating_system,
      initialization[0].user_account,
    ]
  }
}