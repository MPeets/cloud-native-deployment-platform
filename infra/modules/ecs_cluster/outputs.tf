output "ecs_tasks_security_group_id" {
  value = aws_security_group.ecs_tasks.id
}

output "ecs_cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_execution_role_id" {
  value = aws_iam_role.ecs_task_execution.id
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.ecs.name
}

output "log_group_arn" {
  value = aws_cloudwatch_log_group.ecs.arn
}

output "vpc_endpoint_ids" {
  value = {
    ecr_api = aws_vpc_endpoint.ecr_api.id
    ecr_dkr = aws_vpc_endpoint.ecr_dkr.id
    logs    = aws_vpc_endpoint.logs.id
    s3      = aws_vpc_endpoint.s3.id
  }
}
