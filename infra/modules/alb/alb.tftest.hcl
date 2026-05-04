mock_provider "aws" {
  override_during = plan
}

variables {
  name_prefix = "tf-test-alb"
  common_tags = {
    Environment = "test"
    Project     = "portfolio"
  }
  vpc_id                = "vpc-0tfalbtestaaaaaaaa"
  public_subnet_ids     = ["subnet-0tfpublic1aaaaaaaa", "subnet-0tfpublic2aaaaaaaa"]
  app_port              = 8080
  alb_health_check_path = "/health"
}

run "plan_internet_facing_http_forwarding" {
  command = plan

  assert {
    condition     = aws_lb.this.internal == false && aws_lb.this.load_balancer_type == "application"
    error_message = "ALB should be public and application type."
  }

  assert {
    condition     = aws_lb_listener.http.port == 80 && aws_lb_listener.http.protocol == "HTTP"
    error_message = "Listener should expose HTTP on port 80."
  }

  assert {
    condition     = aws_lb_target_group.this.port == var.app_port && aws_lb_target_group.this.protocol == "HTTP"
    error_message = "Target group should match app_port and use HTTP."
  }
}
