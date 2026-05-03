locals {
  external_database_url_secret_arn = var.database_url_secret_arn != null ? trimspace(var.database_url_secret_arn) : ""
  managed_database_url_secret_arn  = length(module.rds) > 0 ? module.rds[0].database_url_secret_arn : ""
  use_database_url_secret          = local.external_database_url_secret_arn != "" || var.enable_rds
  database_url_secret_arn          = local.external_database_url_secret_arn != "" ? local.external_database_url_secret_arn : local.managed_database_url_secret_arn
  database_url_secrets = local.use_database_url_secret ? [
    {
      name      = "DATABASE_URL"
      valueFrom = local.database_url_secret_arn
    }
  ] : []
  worker_image = var.worker_image != null && var.worker_image != "" ? var.worker_image : replace(var.docker_image, "/devops-api:", "/devops-worker:")
}

module "alb" {
  count  = var.enable_ecs ? 1 : 0
  source = "./modules/alb"

  name_prefix           = local.name_prefix
  common_tags           = local.common_tags
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  app_port              = var.app_port
  alb_health_check_path = var.alb_health_check_path
}

module "ecs_cluster" {
  count = var.enable_ecs ? 1 : 0

  source = "./modules/ecs_cluster"

  name_prefix            = local.name_prefix
  common_tags            = local.common_tags
  vpc_id                 = module.network.vpc_id
  private_subnet_ids     = module.network.private_subnet_ids
  private_route_table_id = module.network.private_route_table_id
  aws_region             = var.aws_region
  alb_security_group_id  = module.alb[0].security_group_id
  app_port               = var.app_port
  ecs_log_retention_days = var.ecs_log_retention_days
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  count = (
    var.enable_ecs &&
    local.use_database_url_secret &&
    trimspace(local.database_url_secret_arn) != ""
  ) ? 1 : 0

  name = "${local.name_prefix}-read-database-url-secret"
  role = module.ecs_cluster[0].ecs_task_execution_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = local.database_url_secret_arn
      }
    ]
  })
}

module "ecs_service_api" {
  count      = var.enable_ecs ? 1 : 0
  source     = "./modules/ecs_service"
  depends_on = [module.alb[0]]

  common_tags = local.common_tags
  aws_region  = var.aws_region

  ecs_cluster_id       = module.ecs_cluster[0].ecs_cluster_id
  service_name         = "${local.name_prefix}-api"
  task_family          = "${local.name_prefix}-api"
  container_name       = "devops-api"
  container_image      = var.docker_image
  cpu                  = var.ecs_task_cpu
  memory               = var.ecs_task_memory
  execution_role_arn   = module.ecs_cluster[0].ecs_task_execution_role_arn
  log_group_name       = module.ecs_cluster[0].log_group_name
  log_stream_prefix    = "app"
  subnet_ids           = module.network.private_subnet_ids
  security_group_ids   = [module.ecs_cluster[0].ecs_tasks_security_group_id]
  assign_public_ip     = var.ecs_assign_public_ip
  desired_count        = var.ecs_desired_count
  database_url_secrets = local.database_url_secrets

  port_mappings = [
    {
      containerPort = var.app_port
      hostPort      = var.app_port
      protocol      = "tcp"
    },
  ]

  resource_name_tag = "${local.name_prefix}-api-service"

  load_balancer = {
    target_group_arn                  = module.alb[0].target_group_arn
    container_name                    = "devops-api"
    container_port                    = var.app_port
    health_check_grace_period_seconds = var.ecs_health_check_grace_period_seconds
  }
}

module "ecs_service_worker" {
  count  = var.enable_ecs ? 1 : 0
  source = "./modules/ecs_service"

  common_tags = local.common_tags
  aws_region  = var.aws_region

  ecs_cluster_id       = module.ecs_cluster[0].ecs_cluster_id
  service_name         = "${local.name_prefix}-worker"
  task_family          = "${local.name_prefix}-worker"
  container_name       = "devops-worker"
  container_image      = local.worker_image
  cpu                  = var.ecs_task_cpu
  memory               = var.ecs_task_memory
  execution_role_arn   = module.ecs_cluster[0].ecs_task_execution_role_arn
  log_group_name       = module.ecs_cluster[0].log_group_name
  log_stream_prefix    = "worker"
  subnet_ids           = module.network.private_subnet_ids
  security_group_ids   = [module.ecs_cluster[0].ecs_tasks_security_group_id]
  assign_public_ip     = var.ecs_assign_public_ip
  desired_count        = var.ecs_worker_desired_count
  database_url_secrets = local.database_url_secrets
  port_mappings        = []

  resource_name_tag = "${local.name_prefix}-worker-service"
}
