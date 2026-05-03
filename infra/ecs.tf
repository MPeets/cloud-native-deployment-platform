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

resource "aws_security_group" "ecs_service" {
  count = var.enable_ecs ? 1 : 0

  name   = "${local.name_prefix}-ecs-service"
  vpc_id = module.network.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-service"
  })

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  count = var.enable_ecs ? 1 : 0

  name   = "${local.name_prefix}-alb"
  vpc_id = module.network.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_ecs ? 1 : 0

  name   = "${local.name_prefix}-vpc-endpoints"
  vpc_id = module.network.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  })

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_service[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_ecs ? 1 : 0

  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_ecs ? 1 : 0

  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-dkr-endpoint"
  })
}

resource "aws_vpc_endpoint" "logs" {
  count = var.enable_ecs ? 1 : 0

  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_ecs ? 1 : 0

  vpc_id            = module.network.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.network.private_route_table_id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-endpoint"
  })
}

resource "aws_lb" "app" {
  count = var.enable_ecs ? 1 : 0

  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = module.network.public_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })
}

resource "aws_lb_target_group" "app" {
  count = var.enable_ecs ? 1 : 0

  name        = "${local.name_prefix}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = module.network.vpc_id
  target_type = "ip"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tg"
  })

  health_check {
    path                = var.alb_health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  count = var.enable_ecs ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }
}

resource "aws_ecs_cluster" "app" {
  count = var.enable_ecs ? 1 : 0

  name = local.name_prefix

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}

resource "aws_cloudwatch_log_group" "ecs" {
  count = var.enable_ecs ? 1 : 0

  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.ecs_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/ecs/${local.name_prefix}"
  })
}

resource "aws_iam_role" "ecs_task_execution" {
  count = var.enable_ecs ? 1 : 0

  name = "${local.name_prefix}-ecs-task-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-task-exec"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  count = var.enable_ecs ? 1 : 0

  role       = aws_iam_role.ecs_task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  count = var.enable_ecs && local.use_database_url_secret ? 1 : 0

  name = "${local.name_prefix}-read-database-url-secret"
  role = aws_iam_role.ecs_task_execution[0].id

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
  depends_on = [aws_lb_listener.http[0]]

  common_tags = local.common_tags
  aws_region  = var.aws_region

  ecs_cluster_id       = aws_ecs_cluster.app[0].id
  service_name         = "${local.name_prefix}-api"
  task_family          = "${local.name_prefix}-api"
  container_name       = "devops-api"
  container_image      = var.docker_image
  cpu                  = var.ecs_task_cpu
  memory               = var.ecs_task_memory
  execution_role_arn   = aws_iam_role.ecs_task_execution[0].arn
  log_group_name       = aws_cloudwatch_log_group.ecs[0].name
  log_stream_prefix    = "app"
  subnet_ids           = module.network.private_subnet_ids
  security_group_ids   = [aws_security_group.ecs_service[0].id]
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
    target_group_arn                  = aws_lb_target_group.app[0].arn
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

  ecs_cluster_id       = aws_ecs_cluster.app[0].id
  service_name         = "${local.name_prefix}-worker"
  task_family          = "${local.name_prefix}-worker"
  container_name       = "devops-worker"
  container_image      = local.worker_image
  cpu                  = var.ecs_task_cpu
  memory               = var.ecs_task_memory
  execution_role_arn   = aws_iam_role.ecs_task_execution[0].arn
  log_group_name       = aws_cloudwatch_log_group.ecs[0].name
  log_stream_prefix    = "worker"
  subnet_ids           = module.network.private_subnet_ids
  security_group_ids   = [aws_security_group.ecs_service[0].id]
  assign_public_ip     = var.ecs_assign_public_ip
  desired_count        = var.ecs_worker_desired_count
  database_url_secrets = local.database_url_secrets
  port_mappings        = []

  resource_name_tag = "${local.name_prefix}-worker-service"
}