# One EC2 virtual machine in AWS.
# The same job as modules/proxmox-lxc: hostname, fixed IP, SSH key, disk. Only the platform is different.

resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type = var.instance_type

  # Network: subnet (= availability zone), fixed private IP, firewalls
  subnet_id                   = var.subnet_id
  private_ip                  = var.ip
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = true # Ansible on the ansible host connects to this public IP

  root_block_device {
    volume_size           = var.disk
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true # terraform destroy deletes the disk too: no forgotten disk on the bill
  }

  # First boot settings (cloud-init): hostname, SSH key for ubuntu, swap
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname       = var.name
    ssh_public_key = trimspace(var.ssh_public_key)
    swap_bytes     = var.swap * 1024 * 1024
  })
  # cloud-init runs only at the FIRST boot, so a change here means nothing for a running server.
  # true = changed user_data -> Terraform creates a new server, and the code stays equal to reality.
  user_data_replace_on_change = true

  # Only the safer metadata API v2 (IMDSv2): a hacked app cannot simply read the server's metadata
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # t3 = "burstable": the CPU may run at 100% for a while, then AWS counts CPU credits.
  # unlimited = never slowed down; above the average limit AWS charges a few cents per hour.
  # (standard = free, but a Maven build on a new server can be slowed down to 10% of a CPU.)
  credit_specification {
    cpu_credits = "unlimited"
  }

  tags = {
    Name   = var.name
    Labels = join(" ", sort(var.tags))
  }

  lifecycle {
    # envs/aws always finds the NEWEST Ubuntu 22.04 image. Canonical publishes one every few weeks.
    # Without this line each new image would mean "delete the server and create a new one".
    ignore_changes = [ami]
  }
}