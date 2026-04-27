terraform {
  backend "s3" {
    bucket       = "devops-terraform-state-mpeets"
    key          = "cloud-native/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}