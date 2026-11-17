resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory-terraform.ini"
  file_permission = "0644"

  content = <<-EOT
    [ansible_control]
    control ansible_host=${aws_instance.control.public_ip}

    [web_server]
    web ansible_host=${aws_instance.web.private_ip}

    [db_server]
    db ansible_host=${aws_instance.db.private_ip}

    [all:vars]
    ansible_user=ubuntu
  EOT
}