# ---------------------------------------------------------------------------
# MN521 Part C - root module
#   vpc      -> VPC, 2 public + 2 private subnets, IGW, route tables
#   security -> bastion and private-instance security groups
# ---------------------------------------------------------------------------

# First two available AZs in the region (2-AZ design).
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source = "./modules/vpc"

  name                 = var.project_name
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "security" {
  source = "./modules/security"

  name       = var.project_name
  vpc_id     = module.vpc.vpc_id
  vpc_cidr   = var.vpc_cidr
  admin_cidr = var.admin_cidr
}
