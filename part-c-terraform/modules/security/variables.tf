variable "name" {
  description = "Name prefix for resources."
  type        = string
}

variable "vpc_id" {
  description = "VPC in which to create the security groups."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR, used to scope egress rules."
  type        = string
}

variable "admin_cidr" {
  description = "Only CIDR allowed to SSH to the bastion."
  type        = string
}
