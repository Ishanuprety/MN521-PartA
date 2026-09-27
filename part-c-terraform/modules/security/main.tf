# ---------------------------------------------------------------------------
# Security module: least-privilege SSH path
#   admin_cidr --22--> bastion SG --22--> private instance SG
# ---------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "${var.name}-bastion-sg"
  description = "Bastion host: SSH from the admin CIDR only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-bastion-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_admin" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH from admin workstation"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.admin_cidr
}

# Bastion may SSH into the VPC and reach HTTP/HTTPS for OS package updates.
resource "aws_vpc_security_group_egress_rule" "bastion_ssh_vpc" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH to hosts inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "bastion_https" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTPS for package updates"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "bastion_http" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTP for package updates"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "private_instance" {
  name        = "${var.name}-private-ec2-sg"
  description = "Private EC2: SSH from the bastion security group only"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-private-ec2-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "private_ssh_from_bastion" {
  security_group_id            = aws_security_group.private_instance.id
  description                  = "SSH from bastion SG only"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

# Private instance traffic stays inside the VPC.
resource "aws_vpc_security_group_egress_rule" "private_vpc_only" {
  security_group_id = aws_security_group.private_instance.id
  description       = "All traffic within the VPC only"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}
