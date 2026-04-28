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
