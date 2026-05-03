locals {
  name_prefix = "devops-api-${var.environment}"
  common_tags = {
    Environment = var.environment
    Project     = "cloud-native-deployment-platform"
  }
}
