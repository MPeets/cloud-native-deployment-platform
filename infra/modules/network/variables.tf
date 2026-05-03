variable "name_prefix" {
  type        = string
  description = "Prefix for VPC and subnet resource names (typically includes environment)."
}

variable "common_tags" {
  type        = map(string)
  description = "Tags merged into VPC-layer resources (Environment, Project, etc.)."
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}
