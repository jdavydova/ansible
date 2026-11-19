# Control Server Security Group
resource "aws_security_group" "control" {
  name        = "${var.project_name}-control-sg"
  description = "Security group for Ansible Control Server"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-control-sg"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# SSH from my public IP
resource "aws_vpc_security_group_ingress_rule" "control_ssh" {
  security_group_id = aws_security_group.control.id
  cidr_ipv4         = var.my_ip
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# Outbound traffic
resource "aws_vpc_security_group_egress_rule" "control_outbound" {
  security_group_id = aws_security_group.control.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Web Server Security Group
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Security group for Java Web Server"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-web-sg"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# SSH from Control Server
resource "aws_vpc_security_group_ingress_rule" "web_ssh" {
  security_group_id            = aws_security_group.web.id
  referenced_security_group_id = aws_security_group.control.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

# Java application access from your IP
resource "aws_vpc_security_group_ingress_rule" "web_app" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = var.my_ip
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

# Java application access from Ansible Control Server
resource "aws_vpc_security_group_ingress_rule" "web_app_from_control" {
  security_group_id            = aws_security_group.web.id
  referenced_security_group_id = aws_security_group.control.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "web_outbound" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Database Server Security Group
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Security group for MySQL Database Server"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${var.project_name}-db-sg"
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# SSH from Control Server
resource "aws_vpc_security_group_ingress_rule" "db_ssh" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.control.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

# MySQL from Web Server
resource "aws_vpc_security_group_ingress_rule" "db_mysql" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.web.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "db_outbound" {
  security_group_id = aws_security_group.db.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}