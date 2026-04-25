terraform {
  backend "s3" {
    bucket         = "devops-terraform-state-mpeets"
    key            = "cloud-native/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}