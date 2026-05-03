output "vpc_id" {
  value = aws_vpc.app.id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.app.id
}

output "nat_source_public_subnet_id" {
  description = "Public subnet hosting the NAT gateway (EC2/debug placement)."
  value       = aws_subnet.public[local.nat_public_subnet_key].id
}

output "public_subnet_ids" {
  value       = [for k in sort(keys(aws_subnet.public)) : aws_subnet.public[k].id]
  description = "Stable lexical order over subnet keys."
}

output "private_subnet_ids" {
  value       = [for k in sort(keys(aws_subnet.private)) : aws_subnet.private[k].id]
  description = "Stable lexical order over subnet keys."
}
