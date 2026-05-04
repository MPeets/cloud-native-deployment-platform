resource "random_password" "rds_master" {
  length  = 32
  special = false
}

# tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "database_url" {
  name                    = "${var.name_prefix}/database-url"
  recovery_window_in_days = 0

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}/database-url"
  })
}

# tfsec:ignore:aws-ec2-add-description-to-security-group
resource "aws_security_group" "rds" {
  name   = "${var.name_prefix}-rds"
  vpc_id = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-rds-sg"
  })

  dynamic "ingress" {
    for_each = length(var.ecs_security_group_ids) > 0 ? [1] : []

    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = var.ecs_security_group_ids
    }
  }

  # tfsec:ignore:aws-ec2-no-public-egress-sgr
  # tfsec:ignore:aws-ec2-add-description-to-security-group-rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.name_prefix}-postgres"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-postgres-subnets"
  })
}

# tfsec:ignore:aws-rds-enable-iam-auth
# tfsec:ignore:aws-rds-specify-backup-retention
# tfsec:ignore:aws-rds-enable-performance-insights
resource "aws_db_instance" "postgres" {
  identifier                 = "${var.name_prefix}-postgres"
  engine                     = "postgres"
  instance_class             = var.instance_class
  allocated_storage          = var.allocated_storage
  db_name                    = var.database_name
  username                   = var.username
  password                   = random_password.rds_master.result
  db_subnet_group_name       = aws_db_subnet_group.postgres.name
  vpc_security_group_ids     = [aws_security_group.rds.id]
  publicly_accessible        = false
  storage_encrypted          = true
  backup_retention_period    = var.backup_retention_days
  # tfsec:ignore:AVD-AWS-0177
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = !var.deletion_protection
  final_snapshot_identifier  = var.deletion_protection ? "${var.name_prefix}-postgres-final" : null
  auto_minor_version_upgrade = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-postgres"
  })
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id = aws_secretsmanager_secret.database_url.id
  # RDS PostgreSQL pg_hba expects TLS for in-VPC clients when force_ssl is on (or default rules
  # only match hostssl). node-postgres reads sslmode from the connection string.
  secret_string = format(
    "postgres://%s:%s@%s:%s/%s?sslmode=require",
    var.username,
    urlencode(random_password.rds_master.result),
    aws_db_instance.postgres.address,
    aws_db_instance.postgres.port,
    var.database_name,
  )
}
