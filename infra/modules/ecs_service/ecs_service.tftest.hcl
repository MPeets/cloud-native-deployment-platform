mock_provider "aws" {
  override_during = plan
}

variables {
  common_tags = {
    Environment = "test"
    Project     = "portfolio"
  }
  aws_region           = "us-east-1"
  ecs_cluster_id       = "arn:aws:ecs:us-east-1:123456789012:cluster/tf-test"
  service_name         = "tf-test-api"
  task_family          = "tf-test-api"
  container_name       = "api"
  container_image      = "123456789012.dkr.ecr.us-east-1.amazonaws.com/demo:sha256abcdef1234567890abcdef1234567890abcdef1234567890abcdef12345678"
  cpu                  = 256
  memory               = 512
  execution_role_arn   = "arn:aws:iam::123456789012:role/tf-test-ecs-exec"
  log_group_name       = "/ecs/tf-test-api"
  log_stream_prefix    = "api"
  subnet_ids           = ["subnet-0tfsvc1aaaaaaaaaaaaa", "subnet-0tfsvc2aaaaaaaaaaaaa"]
  security_group_ids   = ["sg-0tfsvcaaaaaaaaaaaaaaa"]
  assign_public_ip     = false
  desired_count        = 1
  resource_name_tag    = "tf-test-api-service"
}

run "plan_fargate_service_without_load_balancer" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.name == var.service_name && aws_ecs_service.this.desired_count == var.desired_count
    error_message = "Service identity and desired count should match variables."
  }

  assert {
    condition     = aws_ecs_task_definition.this.family == var.task_family && aws_ecs_task_definition.this.cpu == tostring(var.cpu) && aws_ecs_task_definition.this.memory == tostring(var.memory)
    error_message = "Task definition should reflect Fargate sizing inputs."
  }

  assert {
    condition     = aws_ecs_service.this.launch_type == "FARGATE"
    error_message = "Service should use Fargate launch type."
  }
}
