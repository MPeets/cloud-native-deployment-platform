mock_provider "aws" {
  override_during = plan
}

variables {
  name_prefix = "tf-test-ecs"
  common_tags = {
    Environment = "test"
    Project     = "portfolio"
  }
  vpc_id                 = "vpc-0tfecsclaaaaaaaaaaaaa"
  private_subnet_ids     = ["subnet-0tfprivate1aaaaaaaa", "subnet-0tfprivate2aaaaaaaa"]
  private_route_table_id = "rtb-0tfrouteaaaaaaaaaaaaa"
  aws_region             = "us-east-1"
  alb_security_group_id  = "sg-0tfalbssssssssssssss"
  app_port               = 8080
  ecs_log_retention_days = 7
}

run "plan_cluster_log_group_and_vpc_endpoints" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.this.name == var.name_prefix
    error_message = "Cluster name should follow name_prefix."
  }

  assert {
    condition     = aws_cloudwatch_log_group.ecs.name == "/ecs/${var.name_prefix}" && aws_cloudwatch_log_group.ecs.retention_in_days == var.ecs_log_retention_days
    error_message = "Log group path and retention should match inputs."
  }

  assert {
    condition     = aws_vpc_endpoint.ecr_api.service_name == "com.amazonaws.${var.aws_region}.ecr.api"
    error_message = "ECR API endpoint should target the configured region."
  }

  assert {
    condition     = length(output.vpc_endpoint_ids) == 4
    error_message = "All four VPC endpoints (ECR api/dkr, logs, S3) should be present."
  }
}
