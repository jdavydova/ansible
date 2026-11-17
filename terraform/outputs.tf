output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "control_public_ip" {
  description = "Public IP of Ansible Control Server"
  value       = aws_instance.control.public_ip
}

output "control_private_ip" {
  description = "Private IP of Ansible Control Server"
  value       = aws_instance.control.private_ip
}

output "web_public_ip" {
  description = "Public IP of Java Web Server"
  value       = aws_instance.web.public_ip
}

output "web_private_ip" {
  description = "Private IP of Java Web Server"
  value       = aws_instance.web.private_ip
}

output "db_private_ip" {
  description = "Private IP of MySQL Database Server"
  value       = aws_instance.db.private_ip
}