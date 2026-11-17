# Trust policy: allows EC2 to assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM Role for Ansible Control Server
resource "aws_iam_role" "ansible" {
  name               = "${var.project_name}-ansible-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ansible" {
  name = "${var.project_name}-ansible-profile"
  role = aws_iam_role.ansible.name

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}