mock_provider "aws" {
  override_during = plan
}

mock_provider "random" {
  override_during = plan
}

variables {
  name_prefix = "tf-test-rds"
  common_tags = {
    Environment = "test"
    Project     = "portfolio"
  }
  vpc_id                 = "vpc-0tfrdsaaaaaaaaaaaaaaa"
  private_subnet_ids     = ["subnet-0tfrds1aaaaaaaaaaaa", "subnet-0tfrds2aaaaaaaaaaaa"]
  ecs_security_group_ids = ["sg-0tfecsaaaaaaaaaaaaaaa"]
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  database_name          = "appdb"
  username               = "appuser"
  backup_retention_days  = 1
  deletion_protection    = false
}

run "plan_postgres_in_private_subnets" {
  command = plan

  assert {
    condition     = aws_db_instance.postgres.engine == "postgres" && aws_db_instance.postgres.publicly_accessible == false && aws_db_instance.postgres.storage_encrypted == true
    error_message = "RDS should be private encrypted PostgreSQL."
  }

  assert {
    condition     = aws_db_subnet_group.postgres.name == "${var.name_prefix}-postgres"
    error_message = "DB subnet group name should follow name_prefix."
  }

  assert {
    condition     = aws_secretsmanager_secret.database_url.name == "${var.name_prefix}/database-url"
    error_message = "Secret name should be namespaced under name_prefix."
  }
}
