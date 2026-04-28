data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  subnet_azs = slice(
    data.aws_availability_zones.available.names,
    0,
    max(length(var.public_subnet_cidrs), length(var.private_subnet_cidrs))
  )

  public_subnets = {
    for index, cidr in var.public_subnet_cidrs : index => {
      cidr_block        = cidr
      availability_zone = local.subnet_azs[index]
    }
  }

  private_subnets = {
    for index, cidr in var.private_subnet_cidrs : index => {
      cidr_block        = cidr
      availability_zone = local.subnet_azs[index]
    }
  }
}

resource "aws_vpc" "app" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "devops-api-vpc"
  }
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "devops-api-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.app.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "devops-api-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.app.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "devops-api-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }

  tags = {
    Name = "devops-api-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
