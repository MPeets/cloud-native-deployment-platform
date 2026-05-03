variable "common_tags" {
  type = map(string)
}

variable "aws_region" {
  type = string
}

variable "ecs_cluster_id" {
  type = string
}

variable "service_name" {
  type = string
}

variable "task_family" {
  type = string
}

variable "container_name" {
  type = string
}

variable "container_image" {
  type = string
}

variable "cpu" {
  type = number
}

variable "memory" {
  type = number
}

variable "execution_role_arn" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "log_stream_prefix" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "assign_public_ip" {
  type = bool
}

variable "desired_count" {
  type = number
}

variable "deployment_minimum_healthy_percent" {
  type    = number
  default = 100
}

variable "deployment_maximum_percent" {
  type    = number
  default = 200
}

variable "port_mappings" {
  type = list(object({
    containerPort = number
    hostPort      = number
    protocol      = optional(string)
  }))
  default = []
}

variable "database_url_secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "load_balancer" {
  type = object({
    target_group_arn                  = string
    container_name                    = string
    container_port                    = number
    health_check_grace_period_seconds = optional(number)
  })
  default = null
}

variable "resource_name_tag" {
  type        = string
  description = "AWS Name tag applied to aws_ecs_service.this."
}
