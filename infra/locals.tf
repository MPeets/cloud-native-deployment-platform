locals {
  name_prefix = "devops-api-${var.environment}"
  common_tags = {
    Environment = var.environment
    Project     = "cloud-native-deployment-platform"
  }

  # Shared destination for upcoming ALB / ECS / RDS CloudWatch alarms.
  ops_notifications_enabled = var.enable_ecs || var.enable_rds
}
