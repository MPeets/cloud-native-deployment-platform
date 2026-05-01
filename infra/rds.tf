resource "random_password" "rds_master" {
  count = var.enable_rds ? 1 : 0

  length  = 32
  special = false
}

resource "aws_security_group" "rds" {
  count = var.enable_rds ? 1 : 0

  name   = "devops-api-rds"
  vpc_id = aws_vpc.app.id

  dynamic "ingress" {
    for_each = var.enable_ecs ? [1] : []

    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [aws_security_group.ecs_service[0].id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "postgres" {
  count = var.enable_rds ? 1 : 0

  name       = "devops-api-postgres"
  subnet_ids = values(aws_subnet.private)[*].id
}

resource "aws_db_instance" "postgres" {
  count = var.enable_rds ? 1 : 0

  identifier                 = "devops-api-postgres"
  engine                     = "postgres"
  instance_class             = var.rds_instance_class
  allocated_storage          = var.rds_allocated_storage
  db_name                    = var.rds_database_name
  username                   = var.rds_username
  password                   = random_password.rds_master[0].result
  db_subnet_group_name       = aws_db_subnet_group.postgres[0].name
  vpc_security_group_ids     = [aws_security_group.rds[0].id]
  publicly_accessible        = false
  storage_encrypted          = true
  backup_retention_period    = var.rds_backup_retention_days
  deletion_protection        = var.rds_deletion_protection
  skip_final_snapshot        = !var.rds_deletion_protection
  final_snapshot_identifier  = var.rds_deletion_protection ? "devops-api-postgres-final" : null
  auto_minor_version_upgrade = true
}

resource "aws_secretsmanager_secret" "database_url" {
  count = var.enable_rds ? 1 : 0

  name                    = "devops-api/database-url"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_url" {
  count = var.enable_rds ? 1 : 0

  secret_id = aws_secretsmanager_secret.database_url[0].id
  secret_string = format(
    "postgres://%s:%s@%s:%s/%s",
    var.rds_username,
    urlencode(random_password.rds_master[0].result),
    aws_db_instance.postgres[0].address,
    aws_db_instance.postgres[0].port,
    var.rds_database_name,
  )
}
