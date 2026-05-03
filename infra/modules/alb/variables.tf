variable "name_prefix" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "app_port" {
  type        = number
  description = "Container / target group listener port forwarded from HTTP:80."
}

variable "alb_health_check_path" {
  type = string
}
