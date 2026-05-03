variable "name_prefix" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "private_route_table_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "alb_security_group_id" {
  type = string
}

variable "app_port" {
  type = number
}

variable "ecs_log_retention_days" {
  type = number
}
