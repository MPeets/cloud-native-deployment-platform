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
  default = false
}

variable "app_port" {
  type    = number
  default = 3000
}