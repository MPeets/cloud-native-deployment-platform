output "db_address" {
  value = aws_db_instance.postgres.address
}

output "db_instance_identifier" {
  description = "RDS DBInstanceIdentifier dimension for CloudWatch."
  value       = aws_db_instance.postgres.identifier
}

output "database_url_secret_arn" {
  value = aws_secretsmanager_secret.database_url.arn
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
