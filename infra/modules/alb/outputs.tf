output "security_group_id" {
  value = aws_security_group.this.id
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "target_group_arn" {
  value = aws_lb_target_group.this.arn
}

output "load_balancer_arn_suffix" {
  description = "Suffix for CloudWatch ApplicationELB LoadBalancer dimension."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Suffix for CloudWatch ApplicationELB TargetGroup dimension."
  value       = aws_lb_target_group.this.arn_suffix
}
