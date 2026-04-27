output "public_ip" {
  value = var.enable_ec2 ? aws_instance.app[0].public_ip : null
}

output "alb_dns_name" {
  value = var.enable_ecs ? aws_lb.app[0].dns_name : null
}