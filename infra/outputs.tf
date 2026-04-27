output "public_ip" {
  value = aws_instance.app.public_ip
}

output "alb_dns_name" {
  value = var.enable_ecs ? aws_lb.app[0].dns_name : null
}