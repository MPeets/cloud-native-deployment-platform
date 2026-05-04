aws_region               = "eu-north-1"
environment              = "dev"
# In GitHub Actions, TF_VAR_* images resolve from the latest green Docker CI on main. Do not use :latest.
docker_image             = "mpeets/devops-api:tfvars-placeholder-use-tf-var"
worker_image             = "mpeets/devops-worker:tfvars-placeholder-use-tf-var"
ami_id                   = "ami-0c1ac8a41498c1a9c"
ssh_allowed_cidrs        = ["203.0.113.10/32"]
enable_ecs               = true
enable_ec2               = false
enable_rds               = true
ecs_worker_desired_count = 1
ecs_assign_public_ip     = false
vpc_cidr                 = "10.10.0.0/16"
public_subnet_cidrs      = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs     = ["10.10.101.0/24", "10.10.102.0/24"]
