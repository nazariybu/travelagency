# RDS MySQL, the same as in envs/aws (stage Cloud), only for the EKS network.
# The database stays OUTSIDE Kubernetes: AWS backs it up and updates it; pods are easy to throw away, data is not.

# The DB password: the same db_password as at home (secret/travelagency/app).
ephemeral "vault_kv_secret_v2" "app" {
  mount = var.vault_kv_mount   # secret
  name  = var.vault_app_secret # travelagency/app
}

resource "aws_db_subnet_group" "this" {
  name       = "travelagency-eks-db"
  subnet_ids = [for s in aws_subnet.db : s.id]

  tags = { Name = "travelagency-eks-db" }
}

resource "aws_db_instance" "this" {
  identifier = "travelagency-eks-db"

  engine                   = "mysql"
  engine_version           = var.db_engine_version
  engine_lifecycle_support = "open-source-rds-extended-support-disabled" # never pay Extended Support

  instance_class    = var.db_instance_class
  allocated_storage = var.db_storage
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_user
  # Write-only: goes to AWS, NOT saved in terraform.tfstate. After a change in Vault: password_wo_version + 1.
  password_wo         = ephemeral.vault_kv_secret_v2.app.data["db_password"]
  password_wo_version = 1

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Demo that we destroy: no last snapshot, no protection.
  skip_final_snapshot      = true
  deletion_protection      = false
  delete_automated_backups = true

  tags = { Name = "travelagency-eks-db" }
}