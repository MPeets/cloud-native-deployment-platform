locals {
  port_mappings_normalized = [
    for pm in var.port_mappings : {
      containerPort = pm.containerPort
      hostPort      = pm.hostPort
      protocol      = pm.protocol != null ? pm.protocol : "tcp"
    }
  ]
  container_secrets = concat(var.database_url_secrets, var.additional_secrets)

  migrate_log_prefix = (
    var.migration_init != null ? coalesce(var.migration_init.log_stream_prefix, "migrate") : "migrate"
  )

  migrate_container = var.migration_init == null ? null : merge(
    {
      name      = var.migration_init.container_name
      image     = var.migration_init.image
      essential = false
      environment = concat(
        [
          {
            name  = "PGSSLROOTCERT"
            value = "/etc/ssl/certs/rds-global-bundle.pem"
          },
        ],
        var.migration_init.environment,
      )
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = local.migrate_log_prefix
        }
      }
    },
    length(var.database_url_secrets) > 0 ? { secrets = var.database_url_secrets } : {},
  )

  primary_container = merge(
    {
      name      = var.container_name
      image     = var.container_image
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.log_stream_prefix
        }
      }
    },
    length(local.port_mappings_normalized) > 0 ? { portMappings = local.port_mappings_normalized } : {},
    length(local.container_secrets) > 0 ? { secrets = local.container_secrets } : {},
    length(var.environment) > 0 ? { environment = var.environment } : {},
    var.migration_init != null ? {
      dependsOn = [{
        containerName = var.migration_init.container_name
        condition     = "SUCCESS"
      }]
    } : {},
  )
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn

  container_definitions = jsonencode(concat(
    var.migration_init != null ? [local.migrate_container] : [],
    [local.primary_container],
  ))
}

resource "aws_ecs_service" "this" {
  name                               = var.service_name
  cluster                            = var.ecs_cluster_id
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  dynamic "load_balancer" {
    for_each = var.load_balancer != null ? [var.load_balancer] : []
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  health_check_grace_period_seconds = (
    var.load_balancer != null ? try(var.load_balancer.health_check_grace_period_seconds, null) : null
  )

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  tags = merge(var.common_tags, {
    Name = var.resource_name_tag
  })
}
