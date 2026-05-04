aws_region  = "eu-north-1"
environment = "prod"
# In GitHub Actions, TF_VAR_* images are set from the latest green Docker CI on main (see scripts/ci_resolve_terraform_container_images.sh). Do not use :latest.
docker_image              = "mpeets/devops-api:tfvars-placeholder-use-tf-var"
worker_image              = "mpeets/devops-worker:tfvars-placeholder-use-tf-var"
ami_id                    = "ami-0c1ac8a41498c1a9c"
ssh_allowed_cidrs         = ["203.0.113.10/32"]
enable_ecs                = true
enable_ec2                = false
enable_rds                = true
rds_backup_retention_days = 7
rds_deletion_protection   = true
ecs_worker_desired_count  = 1
ecs_log_retention_days    = 30
ecs_assign_public_ip      = false
vpc_cidr                  = "10.20.0.0/16"
public_subnet_cidrs       = ["10.20.1.0/24", "10.20.2.0/24"]
private_subnet_cidrs      = ["10.20.101.0/24", "10.20.102.0/24"]
