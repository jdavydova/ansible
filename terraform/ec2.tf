data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# Ansible Control Server
resource "aws_instance" "control" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.control.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ansible.name

  associate_public_ip_address = true

  tags = {
    Name      = "${var.project_name}-ansible-control"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# Java Web Server
resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = var.key_name

  associate_public_ip_address = true

  tags = {
    Name      = "${var.project_name}-web-server"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# MySQL Database Server
resource "aws_instance" "db" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = var.key_name

  associate_public_ip_address = false

  tags = {
    Name      = "${var.project_name}-db-server"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}