variable "name" {
  description = "Name prefix for resources."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC IPv4 CIDR block."
  type        = string
}

variable "azs" {
  description = "Availability Zones, one per subnet pair."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, index-aligned with azs."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, index-aligned with azs."
  type        = list(string)
}
