# tfsec:ignore:aws-ec2-add-description-to-security-group
# tfsec:ignore:aws-ec2-add-description-to-security-group-rule
# tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group" "ecs_tasks" {
  name   = "${var.name_prefix}-ecs-service"
  vpc_id = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ecs-service"
  })

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# tfsec:ignore:aws-ec2-add-description-to-security-group
# tfsec:ignore:aws-ec2-add-description-to-security-group-rule
# tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group" "vpc_endpoints" {
  name   = "${var.name_prefix}-vpc-endpoints"
  vpc_id = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-vpc-endpoints-sg"
  })

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ecr-dkr-endpoint"
  })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-logs-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [var.private_route_table_id]

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-s3-endpoint"
  })
}

# tfsec:ignore:aws-ecs-enable-container-insight
resource "aws_ecs_cluster" "this" {
  name = var.name_prefix

  tags = merge(var.common_tags, {
    Name = var.name_prefix
  })
}

# tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = var.ecs_log_retention_days

  tags = merge(var.common_tags, {
    Name = "/ecs/${var.name_prefix}"
  })
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.name_prefix}-ecs-task-exec"

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

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ecs-task-exec"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
