data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_ecs_cluster" "app" {
  count = var.enable_ecs ? 1 : 0

  name = "devops-api"
}

resource "aws_cloudwatch_log_group" "ecs" {
  count = var.enable_ecs ? 1 : 0

  name              = "/ecs/devops-api"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_task_execution" {
  count = var.enable_ecs ? 1 : 0

  name = "devops-api-ecs-task-exec"

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
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  count = var.enable_ecs ? 1 : 0

  role       = aws_iam_role.ecs_task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "app" {
  count = var.enable_ecs ? 1 : 0

  family                   = "devops-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn

  container_definitions = jsonencode([
    {
      name      = "devops-api"
      image     = var.docker_image
      essential = true
      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs[0].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])
}
