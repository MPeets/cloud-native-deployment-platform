output "public_ip" {
  value = var.enable_ec2 ? aws_instance.app[0].public_ip : null
}

output "alb_dns_name" {
  value = var.enable_ecs ? aws_lb.app[0].dns_name : null
}

output "vpc_id" {
  value = aws_vpc.app.id
}

output "public_subnet_ids" {
  value = values(aws_subnet.public)[*].id
}

output "private_subnet_ids" {
  value = values(aws_subnet.private)[*].id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.app.id
}

output "vpc_endpoint_ids" {
  value = var.enable_ecs ? {
    ecr_api = aws_vpc_endpoint.ecr_api[0].id
    ecr_dkr = aws_vpc_endpoint.ecr_dkr[0].id
    logs    = aws_vpc_endpoint.logs[0].id
    s3      = aws_vpc_endpoint.s3[0].id
  } : {}
}

output "github_actions_incident_logs_reader_role_arn" {
  description = "Read-only role for incident log workflow; set GitHub variable AWS_INCIDENT_LOGS_READER_ROLE_ARN to this ARN."
  value = (
    var.enable_ecs && var.enable_github_incident_logs_reader_role
    ? aws_iam_role.github_incident_logs_reader[0].arn
    : null
  )
}
