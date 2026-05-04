# https://github.com/terraform-linters/tflint

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
  version = "0.42.0"
}

rule "aws_resource_missing_tags" {
  enabled = true
  tags    = ["Environment", "Project"]
}
