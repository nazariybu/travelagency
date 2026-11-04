# The servers: one module call per line of "servers" (for_each), like envs/proxmox/main.tf.

# Newest official Ubuntu 22.04 image. 22.04 and not 24.04: the app needs Tomcat 9,
# and the tomcat9 package exists only up to Ubuntu 22.04 (24.04 has tomcat10).
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (the company behind Ubuntu): only official images

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Which firewall each Ansible group gets (security.tf)
locals {
  security_groups = {
    app   = [aws_security_group.app.id]
    redis = [aws_security_group.redis.id]
  }
}

module "server" {
  source   = "../../modules/aws-ec2"
  for_each = var.servers

  # common inputs (same names as in envs/proxmox)
  name           = each.key
  ip             = each.value.ip
  disk           = each.value.disk
  swap           = each.value.swap
  ssh_public_key = file(pathexpand(var.ssh_public_key_file))
  tags           = ["terraform", replace(each.value.group, "_", "-")]

  # AWS only
  instance_type      = each.value.instance_type
  ami_id             = data.aws_ami.ubuntu.id
  subnet_id          = aws_subnet.public[each.value.zone].id
  security_group_ids = local.security_groups[each.value.group]
}