# AWS provider configuration.
# Credentials are NOT stored here: they come from the environment
# (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) or an AWS CLI profile.
provider "aws" {
  region = var.aws_region

  # Every taggable resource created by this project receives these tags.
  default_tags {
    tags = {
      Project   = "MN521"
      Group     = var.group_number
      ManagedBy = "Terraform"
      Part      = "C"
    }
  }
}
