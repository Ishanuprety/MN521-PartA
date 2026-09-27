variable "name" {
  description = "Name prefix for resources."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "key_name" {
  description = "Name for the AWS key pair."
  type        = string
}

variable "public_key" {
  description = "OpenSSH public key material."
  type        = string
}

variable "bastion_subnet_id" {
  description = "Public subnet for the bastion host."
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet for the application instance."
  type        = string
}

variable "bastion_sg_id" {
  description = "Security group for the bastion."
  type        = string
}

variable "private_instance_sg_id" {
  description = "Security group for the private instance."
  type        = string
}
