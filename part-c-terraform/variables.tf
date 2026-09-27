# ---------------------------------------------------------------------------
# Input variables for the MN521 Part C stack.
# Override them in terraform.tfvars (see terraform.tfvars.example).
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1" # AWS Academy Learner Lab permitted region
}

variable "project_name" {
  description = "Short name used as a prefix for resource Name tags."
  type        = string
  default     = "mn521"
}

variable "group_number" {
  description = "Group number, applied as the Group default tag."
  type        = string
  default     = "3"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.100.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (one per AZ)."
  type        = list(string)
  default     = ["10.100.1.0/24", "10.100.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactly two public subnets are required."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (one per AZ)."
  type        = list(string)
  default     = ["10.100.11.0/24", "10.100.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Exactly two private subnets are required."
  }
}

variable "admin_cidr" {
  description = "The only source CIDR allowed to SSH to the bastion, e.g. your public IP /32."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "instance_type" {
  description = "EC2 instance type for both hosts (use a free-tier eligible type)."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the EC2 key pair registered in AWS."
  type        = string
  default     = "mn521-partc-key"
}

variable "public_key_path" {
  description = "Path to the locally generated SSH public key. The private key never leaves the workstation."
  type        = string
  default     = "~/.ssh/mn521_partc_ed25519.pub"
}

variable "private_key_path" {
  description = "Path to the matching private key. Only used to render the SSH command outputs."
  type        = string
  default     = "~/.ssh/mn521_partc_ed25519"
}
