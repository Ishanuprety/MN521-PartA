# ---------------------------------------------------------------------------
# Compute module: SSH key pair, bastion host (public subnet) and
# private EC2 Linux instance (private subnet, reachable only via bastion).
# ---------------------------------------------------------------------------

# Latest Amazon Linux 2023 x86_64 AMI published by Amazon.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Public half of a locally generated key; the private key stays on the workstation.
resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = var.public_key

  tags = {
    Name = var.key_name
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.bastion_subnet_id
  vpc_security_group_ids      = [var.bastion_sg_id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    hostname = "${var.name}-bastion"
  })

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-bastion"
    Role = "bastion"
  }
}

resource "aws_instance" "private" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.private_subnet_id
  vpc_security_group_ids      = [var.private_instance_sg_id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    hostname = "${var.name}-private-ec2"
  })

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-private-ec2"
    Role = "app-server"
  }
}
