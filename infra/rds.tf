module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "./modules/rds"

  name_prefix            = local.name_prefix
  common_tags            = local.common_tags
  vpc_id                 = module.network.vpc_id
  private_subnet_ids     = module.network.private_subnet_ids
  ecs_security_group_ids = aws_security_group.ecs_service[*].id
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  database_name          = var.rds_database_name
  username               = var.rds_username
  backup_retention_days  = var.rds_backup_retention_days
  deletion_protection    = var.rds_deletion_protection
}
