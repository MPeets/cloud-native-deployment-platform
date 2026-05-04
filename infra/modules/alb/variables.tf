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
  description = "Container / target group port; ALB forwards HTTP or HTTPS to this port on the task."
}

variable "alb_health_check_path" {
  type = string
}

variable "certificate_arn" {
  type        = string
  default     = null
  description = "When set (validated ACM ARN in this region), ALB listens on 443/TLS and port 80 redirects to HTTPS."
}
