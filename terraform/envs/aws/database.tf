# RDS = MySQL that AWS runs for us (a "managed" database): AWS installs it, updates it,
# makes backups. We do not get SSH to it, only the MySQL port 3306. It replaces vm-db.

# The DB password: the same db_password that Ansible gives to Tomcat (secret/travelagency/app).
ephemeral "vault_kv_secret_v2" "app" {
  mount = var.vault_kv_mount   # secret
  name  = var.vault_app_secret # travelagency/app
}

# RDS must know which subnets it may use (2 zones, without internet)
resource "aws_db_subnet_group" "this" {
  name       = "travelagency-db"
  subnet_ids = [for s in aws_subnet.db : s.id]

  tags = { Name = "travelagency-db" }
}

resource "aws_db_instance" "this" {
  identifier = "travelagency-db" # the name in the AWS console and the start of the address

  engine         = "mysql"
  engine_version = var.db_engine_version # 8.4: the newest minor version of 8.4
  # Never pay for "Extended Support" (old MySQL versions after their end of support)
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"

  instance_class    = var.db_instance_class # db.t4g.micro = Free Tier
  allocated_storage = var.db_storage        # 20 GB = Free Tier
  storage_type      = "gp2"
  storage_encrypted = true

  # The database and its main user, the same names as in ansible/group_vars/all.yml
  db_name  = var.db_name
  username = var.db_user
  # Write-only (Terraform 1.11+): the password goes to AWS and is NOT saved in terraform.tfstate.
  # Terraform cannot see if the password changed, so after a change in Vault: password_wo_version + 1.
  password_wo         = ephemeral.vault_kv_secret_v2.app.data["db_password"]
  password_wo_version = 1

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false # no public address: only the app nodes in the VPC can connect
  multi_az               = false # one server. true = a standby copy in the 2nd zone (2x price, not Free Tier)

  backup_retention_period    = 1 # 1 day of automatic backups (Free Tier: 20 GB of backups)
  auto_minor_version_upgrade = true
  apply_immediately          = true # apply changes now, not in the next maintenance window

  # For a demo that we destroy: no last snapshot, no protection, delete the backups too.
  # In real production: skip_final_snapshot = false, deletion_protection = true.
  skip_final_snapshot      = true
  deletion_protection      = false
  delete_automated_backups = true

  tags = { Name = "travelagency-db" }
}