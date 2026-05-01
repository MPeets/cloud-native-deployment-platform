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

variable "worker_image" {
  type        = string
  default     = null
  description = "Container image for the ECS background worker. Defaults to docker_image with devops-api replaced by devops-worker."
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

variable "ecs_worker_desired_count" {
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
  default = false
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "enable_github_incident_logs_reader_role" {
  type        = bool
  default     = true
  description = "Least-privilege IAM role (OIDC) for GitHub Actions to run incident log reports against the ECS log group."
}

variable "github_actions_oidc_repository" {
  type        = string
  default     = "MPeets/cloud-native-deployment-platform"
  description = "Restricts GitHub OIDC sub claim to repo:ORG/NAME:* (no repo: prefix here)."
}
