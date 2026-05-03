output "db_address" {
  value = aws_db_instance.postgres.address
}

output "database_url_secret_arn" {
  value = aws_secretsmanager_secret.database_url.arn
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
