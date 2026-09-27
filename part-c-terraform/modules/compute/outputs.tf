output "ami_id" {
  description = "Amazon Linux 2023 AMI used for both instances."
  value       = data.aws_ami.al2023.id
}

output "ami_name" {
  description = "Name of the AMI."
  value       = data.aws_ami.al2023.name
}

output "key_pair_name" {
  description = "Name of the EC2 key pair."
  value       = aws_key_pair.this.key_name
}

output "bastion_instance_id" {
  description = "Instance ID of the bastion."
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IPv4 address of the bastion."
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IPv4 address of the bastion."
  value       = aws_instance.bastion.private_ip
}

output "private_instance_id" {
  description = "Instance ID of the private EC2."
  value       = aws_instance.private.id
}

output "private_instance_private_ip" {
  description = "Private IPv4 address of the private EC2."
  value       = aws_instance.private.private_ip
}
