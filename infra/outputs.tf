output "public_ip" {
  value = var.enable_ec2 ? aws_instance.app[0].public_ip : null
}

output "alb_dns_name" {
  value = var.enable_ecs ? module.alb[0].dns_name : null
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "rds_endpoint" {
  value = var.enable_rds ? module.rds[0].db_address : null
}

output "database_url_secret_arn" {
  description = "Secrets Manager secret ARN used by ECS tasks for DATABASE_URL."
  value       = local.use_database_url_secret ? local.database_url_secret_arn : null
}

output "nat_gateway_id" {
  value = module.network.nat_gateway_id
}

output "vpc_endpoint_ids" {
  value = var.enable_ecs ? module.ecs_cluster[0].vpc_endpoint_ids : {}
}

output "github_actions_incident_logs_reader_role_arn" {
  description = "Read-only role for incident log workflow; set GitHub variable AWS_INCIDENT_LOGS_READER_ROLE_ARN to this ARN."
  value = (
    var.enable_ecs && var.enable_github_incident_logs_reader_role
    ? aws_iam_role.github_incident_logs_reader[0].arn
    : null
  )
}

output "ops_alerts_sns_topic_arn" {
  description = "SNS topic ARN for operational CloudWatch alarms (subscribe endpoints or wire chat integrations here)."
  value       = local.ops_notifications_enabled ? aws_sns_topic.ops_alerts[0].arn : null
}
