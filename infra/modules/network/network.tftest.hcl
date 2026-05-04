mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
}

variables {
  name_prefix = "tf-test-network"
  common_tags = {
    Environment = "test"
    Project     = "portfolio"
  }
  vpc_cidr             = "10.42.0.0/16"
  public_subnet_cidrs  = ["10.42.1.0/24", "10.42.2.0/24"]
  private_subnet_cidrs = ["10.42.101.0/24", "10.42.102.0/24"]
}

run "plan_public_and_private_subnets_per_az" {
  command = plan

  assert {
    condition     = aws_vpc.app.cidr_block == var.vpc_cidr
    error_message = "VPC CIDR should match the configured variable."
  }

  assert {
    condition     = length(output.public_subnet_ids) == length(var.public_subnet_cidrs)
    error_message = "One public subnet id per public CIDR."
  }

  assert {
    condition     = length(output.private_subnet_ids) == length(var.private_subnet_cidrs)
    error_message = "One private subnet id per private CIDR."
  }
}
