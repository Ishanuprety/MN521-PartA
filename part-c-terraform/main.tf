# ---------------------------------------------------------------------------
# MN521 Part C - root module
# Wires together three child modules:
#   vpc      -> VPC, 2 public + 2 private subnets, IGW, route tables
#   security -> bastion and private-instance security groups
#   compute  -> SSH key pair, bastion host, private EC2 instance
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

module "compute" {
  source = "./modules/compute"

  name                   = var.project_name
  instance_type          = var.instance_type
  key_name               = var.key_name
  public_key             = file(pathexpand(var.public_key_path))
  bastion_subnet_id      = module.vpc.public_subnet_ids[0]
  private_subnet_id      = module.vpc.private_subnet_ids[0]
  bastion_sg_id          = module.security.bastion_sg_id
  private_instance_sg_id = module.security.private_instance_sg_id
}
