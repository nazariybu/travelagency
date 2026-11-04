# One module call per line of "servers" (for_each).
# To move to a cloud later: a new folder envs/<cloud> calls modules/<cloud>-vm with the same
# common inputs (name, ip, cores, memory, disk, ssh_public_key, tags). servers and the inventory stay.

module "server" {
  source   = "../../modules/proxmox-lxc"
  for_each = var.servers

  # common inputs
  name           = each.key
  ip             = each.value.ip
  cores          = each.value.cores
  memory         = each.value.memory
  disk           = each.value.disk
  ssh_public_key = file(pathexpand(var.ssh_public_key_file))
  tags           = ["terraform", replace(each.value.group, "_", "-")]

  # Proxmox only
  node_name        = var.proxmox_node
  vm_id            = each.value.vm_id
  swap             = each.value.swap
  nesting          = each.value.nesting
  template_file_id = var.lxc_template
  datastore_id     = var.datastore_id
  bridge           = var.network.bridge
  gateway          = var.network.gateway
  prefix_length    = var.network.prefix_length
}