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

variable "ecs_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed to reach PostgreSQL on 5432 (typically the ECS service SG)."
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "database_name" {
  type = string
}

variable "username" {
  type = string
}

variable "backup_retention_days" {
  type = number
}

variable "deletion_protection" {
  type = bool
}
