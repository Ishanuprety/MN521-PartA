# ---------------------------------------------------------------------------
# Root outputs: printed after `terraform apply` and via `terraform output`.
# ---------------------------------------------------------------------------

output "aws_region" {
  description = "Region the stack is deployed in."
  value       = var.aws_region
}

output "availability_zones" {
  description = "The two AZs used."
  value       = local.azs
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID."
  value       = module.vpc.internet_gateway_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "public_route_table_id" {
  description = "Public route table ID (0.0.0.0/0 -> IGW)."
  value       = module.vpc.public_route_table_id
}

output "private_route_table_id" {
  description = "Private route table ID (local route only)."
  value       = module.vpc.private_route_table_id
}

output "bastion_sg_id" {
  description = "Bastion security group ID."
  value       = module.security.bastion_sg_id
}

output "private_instance_sg_id" {
  description = "Private instance security group ID."
  value       = module.security.private_instance_sg_id
}

output "ami_id" {
  description = "Amazon Linux 2023 AMI ID."
  value       = module.compute.ami_id
}

output "key_pair_name" {
  description = "EC2 key pair name."
  value       = module.compute.key_pair_name
}

output "bastion_instance_id" {
  description = "Bastion instance ID."
  value       = module.compute.bastion_instance_id
}

output "bastion_public_ip" {
  description = "Bastion public IPv4."
  value       = module.compute.bastion_public_ip
}

output "private_instance_id" {
  description = "Private EC2 instance ID."
  value       = module.compute.private_instance_id
}

output "private_instance_private_ip" {
  description = "Private EC2 private IPv4."
  value       = module.compute.private_instance_private_ip
}

output "ssh_bastion_command" {
  description = "SSH to the bastion."
  value       = "ssh -i ${var.private_key_path} ec2-user@${module.compute.bastion_public_ip}"
}

output "ssh_private_via_bastion_command" {
  description = "SSH to the private EC2 through the bastion using ProxyJump (key loaded in ssh-agent)."
  value       = "ssh-add ${var.private_key_path} && ssh -J ec2-user@${module.compute.bastion_public_ip} ec2-user@${module.compute.private_instance_private_ip}"
}

output "ssh_config_snippet" {
  description = "~/.ssh/config entries so that `ssh mn521-private` jumps through the bastion."
  value       = <<-EOT
    Host mn521-bastion
      HostName ${module.compute.bastion_public_ip}
      User ec2-user
      IdentityFile ${var.private_key_path}

    Host mn521-private
      HostName ${module.compute.private_instance_private_ip}
      User ec2-user
      IdentityFile ${var.private_key_path}
      ProxyJump mn521-bastion
  EOT
}
