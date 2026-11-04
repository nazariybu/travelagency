# REPORT: Infrastructure as Code with Terraform (Proxmox)

## 1. Goal

Describe all TravelAgency servers (9 LXC containers in Proxmox) as code with Terraform, instead of the
Ansible playbook `provision.yml`. Take the Proxmox token from Vault. Build the folders so that the next stages
(cloud, Kubernetes) can switch the platform without rewriting everything.

## 2. Before and after

| | Before (`ansible/provision.yml`) | After (Terraform) |
|---|---|---|
| Create a container | ✅ | ✅ |
| Change CPU / RAM of an existing one | ❌ (`state: present` skips existing containers) | ✅ in place |
| Delete a container that is not in the list | ❌ manual | ✅ `apply` deletes it |
| Show the difference before changing | ❌ | ✅ `terraform plan` |
| Know what was created by code | ❌ | ✅ state file, `terraform state list` |
| Inventory for Ansible | written by hand, could differ | generated from the same list |
| Proxmox token | Vault lookup (Ansible) | Vault, `ephemeral` (not saved anywhere) |

## 3. Choices

| Question | Chosen | Why | Not chosen |
|----------|--------|-----|------------|
| Proxmox provider | `bpg/proxmox` 0.116.x | Actively maintained, supports LXC and API tokens, import | `Telmate/proxmox`: fewer LXC features, slower releases |
| Version pin | `~> 0.116.1` + `.terraform.lock.hcl` in Git | The provider has breaking changes in minor versions; same versions on every machine | `>= 0.x` (an update could break the plan) |
| Existing containers | `import` blocks (`imports.tf`), then the file is removed | Containers keep their data, nothing is re-created | Destroy + create (data loss), `terraform import` command 9 times (not in code) |
| OS template and SSH key after import | `lifecycle.ignore_changes` | Proxmox does not store them; without ignore the plan wants to re-create all 9 containers | |
| Secret in the state | `ephemeral "vault_kv_secret_v2"` (Terraform 1.10+) | Not in `terraform.tfstate`, not in plan files | `data "vault_kv_secret_v2"`: writes the token in plain text to the state |
| Vault child token | `skip_child_token = true` | The `travelagency-admin` policy has no `auth/token/create`; our userpass token already lives only 8 h | Child token: better (shorter life), needs `path "auth/token/create" { capabilities = ["update"] }` in the policy (root token) |
| Proxmox token | Same `ansible@pve!ansible` | Already has the rights and is in Vault | A separate `terraform@pve` user: better audit, next improvement |
| State | Local file, not in Git | One person, one machine; Git must never hold state | Remote backend (S3 / MinIO / Terraform Cloud): in the cloud stage |
| Structure | `modules/proxmox-lxc` + `envs/proxmox` + shared inventory template | Platform-specific code in one module; a cloud = new module + new env folder | One flat folder (hard to add a second platform) |
| Inventory | `local_file` from `templates/inventory.ini.tftpl` | One list of servers for Terraform and Ansible | Hand-written inventory (two lists can drift apart) |

## 4. How a change works

1. Edit `envs/proxmox/terraform.tfvars`.
2. `terraform plan`: Terraform reads the token from Vault, asks Proxmox the real state, compares it with the
   code and the state file, prints `+` create, `~` change, `-` delete, `-/+` re-create.
3. `terraform apply`: the same plan, `yes`, then the API calls. The state and `ansible/inventory.ini` are updated.
4. Ansible playbook for the new or changed server.

Changes that **restart** a container (bpg/proxmox): memory/swap, network or IP, hostname, DNS, console.
No restart: CPU cores, tags, description, start on boot, nesting.

## 5. Security notes

- No secret in Git, in `*.tf` or in the state. Checked with `grep -c token_secret terraform.tfstate` → `0`.
- `terraform.tfstate` still describes the whole infrastructure (IPs, IDs): it is in `.gitignore`.
- `insecure = true` for the Proxmox API (self-signed certificate). Fix later: Proxmox certificate from an
  internal CA or Let's Encrypt, then `insecure = false`.
- Vault over HTTP (home lab, see the Vault REPORT): the token travels in plain text inside the LAN.

## 6. Results

Run on 2026-11-04. Proxmox VE 9.1.4, provider bpg/proxmox 0.116.x.

| Check | Expected | Result |
|-------|----------|--------|
| `pct config` of all 9 containers before import | same as `terraform.tfvars` | OK: cores, memory, swap 512, disk, nesting, IP, bridge all equal; no `onboot` line (autostart was off) |
| `terraform version` | >= 1.10 | 1.17 |
| First `terraform plan` | `9 to import, 1 to add, 9 to change, 0 to destroy`, no `must be replaced` | OK |
| `terraform apply` | `Apply complete! Resources: 9 imported, 1 added, 9 changed, 0 destroyed.` | OK |
| Proxmox UI | tags `terraform` + group on all 9, Notes "Managed by Terraform" | OK (screenshot below) |
| `terraform plan` after apply | `No changes.` | OK |
| `terraform state list` | 9 containers + `local_file.ansible_inventory` | OK: 10 lines |
| `git diff ansible/inventory.ini` | only the header comment and whitespace | OK: + 2 comment lines, trailing spaces after vm-lb and empty lines at the end removed; hosts and IPs the same |
| Token not in state | `grep -c token_secret terraform.tfstate` → `0` | OK: `0`, and `0` for `ansible@pve!ansible=` |
| Test server vm-tftest (create → destroy) | created in ~1 min, SSH works, then deleted | OK: plan `2 to add, 1 to destroy` (the 1 = inventory file re-written), container 399 created, then removed with `1 to add, 2 to destroy` |
| `ansible all -m ping` | 9 × `pong` | OK: 9 × `pong` from the generated inventory |

![Proxmox tags](../images/terraform-proxmox-tags.png)

## 7. Problems found

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 1 | `terraform plan` failed: `failed to lookup token ... Code: 503 ... Vault is sealed` | vm-vault had been restarted earlier; a restarted Vault always starts sealed | `vault operator unseal` two times, then plan again. Terraform needs Vault for every plan/apply, like Ansible |
| 2 | After `apply` all 9 containers had the same short uptime (`up 7 minutes`, vm-app in the UI `00:01:57`), vm-vault too | Confirmed by the Proxmox task log (`pvenode task list`): `vzreboot` of all 9 containers by `ansible@pve!ansible` (the token Terraform uses) in the same second, during `apply`. The Proxmox host itself was not restarted (up since 2026-10-26). The provider reboots a container after an update when memory, network/IP, hostname, DNS or console changed; the exact field: `terraform show import.tfplan` | Check the plan for `~ memory`, `~ network_interface`, `~ initialization`, `~ console`. After a restart of vm-vault: unseal again. Next time look for these blocks in the plan before `apply` |

## 8. Next

- Cloud stage: `modules/<cloud>-vm` + `envs/<cloud>`, remote state backend.
- Separate Proxmox user `terraform@pve` with only the needed rights.
- Kubernetes: cluster nodes from the same `servers` list.
