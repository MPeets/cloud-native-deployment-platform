variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "docker_image" {
  type = string
}

variable "key_name" {
  type    = string
  default = "devops-key"
}

variable "ami_id" {
  type = string
}

variable "ssh_allowed_cidrs" {
  type = list(string)
}

variable "enable_ecs" {
  type    = bool
  default = true
}

variable "enable_ec2" {
  type    = bool
  default = false
}

variable "app_port" {
  type    = number
  default = 3000
}

variable "ecs_desired_count" {
  type    = number
  default = 1
}

variable "alb_health_check_path" {
  type    = string
  default = "/"
}

variable "ecs_health_check_grace_period_seconds" {
  type    = number
  default = 60
}

variable "ecs_task_cpu" {
  type    = number
  default = 256
}

variable "ecs_task_memory" {
  type    = number
  default = 512
}

variable "ecs_log_retention_days" {
  type    = number
  default = 7
}

variable "ecs_assign_public_ip" {
  type    = bool
  default = true
}
