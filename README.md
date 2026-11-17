# Exercise 6 — AWS Infrastructure with Terraform and Application Deployment with Ansible

This educational DevOps project uses **Terraform** to provision AWS infrastructure and **Ansible** to configure a dedicated control server, a Java web server, and a private MySQL database server.

> **Status:** Terraform validation and planning and Ansible syntax checks have been performed during development. A successful end-to-end AWS deployment has **not yet been verified**. The instructions below describe the intended workflow, not a completed deployment.

## Exercise requirements

- Run a dedicated Ansible Control Server on AWS.
- Deploy the Java application and MySQL database on separate EC2 instances in the same VPC.
- Keep the database instance in a private subnet **without a public IP address**.
- Allow the private database to download packages through a NAT Gateway.
- Configure MySQL using an existing Ansible Galaxy role (`geerlingguy.mysql`).
- Run Web and DB configuration playbooks **from the Ansible Control Server**.
- Verify the Java application at `http://<WEB_PUBLIC_IP>:8080`.

## Architecture

```text
Developer workstation (Terraform, Ansible, AWS CLI, SSH key)
  |
  | Terraform -> AWS API
  | SSH :22 -> Control public IP (developer public IPv4 /32)
  v
AWS VPC 10.0.0.0/16 — eu-north-1
  |
  +-- Public subnet 10.0.1.0/24 — eu-north-1a
  |     +-- Ansible Control EC2 (public + private IP)
  |     |     | SSH :22 to Web and DB over private IPs
  |     |     +------------------------------+
  |     |                                    |
  |     +-- Web EC2 (public + private IP) <--+
  |           Java application :8080
  |           | MySQL :3306
  |           v
  +-- Private subnet 10.0.2.0/24 — eu-north-1a
  |     +-- DB EC2 (private IP only)
  |           MySQL :3306
  |     +-- Private route table -> NAT Gateway (public subnet)
  |
  +-- Internet Gateway + public route table
```

### Network access

| Destination | Port | Allowed source |
|---|---:|---|
| Ansible Control | TCP/22 | Developer's public IPv4 (`my_ip`, `/32`) |
| Web | TCP/22 | Ansible Control security group |
| Web | TCP/8080 | Developer's public IPv4 (`my_ip`, `/32`) |
| DB | TCP/22 | Ansible Control security group |
| DB | TCP/3306 | Web security group |

Security groups permit outbound traffic. The DB instance has no public IP; its private subnet uses a NAT Gateway for outbound package downloads. The web application's port 8080 is **not** opened to the Control security group, so test it from the developer's allowed public IP.

## Technology stack

- **Infrastructure:** Terraform, AWS EC2, VPC, public/private subnets, Internet Gateway, NAT Gateway, Elastic IP, route tables, security groups, IAM.
- **Configuration:** Ansible, custom `create_user` and `install_java` roles, `geerlingguy.mysql` Galaxy role, `ansible.mysql` collection.
- **Application:** Java 21, Spring Boot JAR, systemd.
- **Database:** MySQL.
- **Region:** `eu-north-1` (Stockholm).

## Repository layout

```text
.
├── README.md
├── build.gradle
├── settings.gradle
├── src/
├── terraform/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── vpc.tf
│   ├── subnets.tf
│   ├── networking.tf
│   ├── security-groups.tf
│   ├── iam.tf
│   ├── ec2.tf
│   ├── outputs.tf
│   └── .terraform.lock.hcl
└── ansible/
    ├── configure-ansible-server.yaml
    ├── configure-app-servers.yaml
    ├── run-app-playbooks.yaml
    ├── deploy-terraform.yaml
    ├── inventory-terraform.ini
    ├── requirements.yaml
    ├── vars/
    │   └── project-vars.yaml
    ├── roles/
    │   ├── create_user/
    │   └── install_java/
    └── files/
        └── java-app-1.0-SNAPSHOT.jar
```

Older `provision-*.yaml`, `deploy-all.yaml`, `cleanup.yaml`, and `destroy.yaml` playbooks belong to the **legacy Ansible-based infrastructure workflow**. Do not run them together with Terraform-managed resources. For this workflow, use `terraform destroy` to remove infrastructure.

## Prerequisites

1. An AWS account and AWS CLI credentials authorized to create the required EC2, networking, IAM, and related resources.
2. Terraform and Ansible installed on the developer workstation.
3. An existing AWS EC2 key pair named `ansible-jenkins`, with the matching private key stored locally at `~/.ssh/ansible-jenkins.pem`.
4. An SSH agent with that key loaded, if using agent forwarding to the trusted Control EC2.
5. A current public IPv4 address to restrict SSH and application access.
6. An AWS budget that allows **three EC2 instances, a NAT Gateway, Elastic IP, public IPv4 addresses, and associated usage charges**. NAT Gateway charges accrue while it exists, even when the app is idle.

Check the environment from the **repository root**:

```bash
aws sts get-caller-identity
aws configure get region
terraform version
ansible --version
ssh-add -l
```

If needed, load the SSH key:

```bash
chmod 600 ~/.ssh/ansible-jenkins.pem
ssh-add ~/.ssh/ansible-jenkins.pem
```

## 1. Provision infrastructure with Terraform

Run from the repository root:

```bash
cd terraform
terraform init
terraform fmt -check
terraform validate
```

Get your current public IPv4 address from a trusted source and pass it as a CIDR with `/32`:

```bash
terraform plan -var="my_ip=<YOUR_PUBLIC_IPV4>/32"
```

Review the planned resources and expected costs. **Only after reviewing the plan**, create the infrastructure:

```bash
terraform apply -var="my_ip=<YOUR_PUBLIC_IPV4>/32"
```

Terraform will ask for confirmation. Do not use an old public IP if your network address has changed.

Retrieve the created addresses:

```bash
terraform output
terraform output -raw control_public_ip
terraform output -raw web_public_ip
terraform output -raw web_private_ip
terraform output -raw db_private_ip
```

Return to the repository root:

```bash
cd ..
```

> Terraform outputs and resource identifiers are generated **only after a successful apply**. The earlier plan of 26 resources is not proof that deployment has completed.

## 2. Populate the Ansible inventory

Edit `ansible/inventory-terraform.ini`, replacing the placeholders with **actual Terraform outputs**:

```ini
[ansible_control]
control ansible_host=CONTROL_PUBLIC_IP

[web_server]
web ansible_host=WEB_PRIVATE_IP

[db_server]
db ansible_host=DB_PRIVATE_IP

[all:vars]
ansible_user=ubuntu
```

The Control host uses its public IP for workstation access. The Web and DB hosts use private IPs because they are managed from within the VPC. Do not attempt to connect to the private DB IP directly from the workstation.

## 3. Prepare application configuration and secrets

The tracked `ansible/vars/project-vars.yaml` is an **example configuration**. It must not contain a real password. Example:

```yaml
---
region: eu-north-1

# Application
linux_user: java-app
app_dir: "/home/{{ linux_user }}/app"
app_version: "1.0-SNAPSHOT"
jar_name: "java-app-{{ app_version }}.jar"
local_jar: "{{ playbook_dir }}/files/{{ jar_name }}"

# Database
db_name: java_app_db
db_user: java_app_user
db_port: 3306
```

For a real deployment, create an **encrypted** file containing `db_password`:

```bash
ansible-vault create ansible/vars/secrets.yaml
```

Enter a strong Vault password when prompted. In the editor, enter:

```yaml
---
db_password: "REPLACE_WITH_A_STRONG_REAL_PASSWORD"
```

Save and exit. The text above is a template: use a real password **only inside the encrypted Vault file**. Do not commit the Vault password. In this project, `ansible/vars/secrets.yaml` is excluded from Git as a local secret file.

Update the `vars_files` section in **both plays** of `ansible/configure-app-servers.yaml`:

```yaml
vars_files:
  - vars/project-vars.yaml
  - vars/secrets.yaml
```

This is a required playbook change before using Vault. The encrypted `secrets.yaml` must also be present on the Control EC2 when that machine runs the configuration playbook. The existing `configure-ansible-server.yaml` copies the Ansible project directory to `/home/ubuntu/ansible-project/`; verify the encrypted file is included and has appropriately restricted permissions. Do **not** copy the Vault password file to EC2.

Useful Vault commands (from repository root):

```bash
ansible-vault edit ansible/vars/secrets.yaml
ansible-vault rekey ansible/vars/secrets.yaml
```

**Security limitation:** Ansible Vault encrypts the secrets file at rest. The current `configure-app-servers.yaml` writes the database password into a systemd service unit, which is not a secure secret store. Before using this outside a learning environment, replace that approach with a root-protected environment file (`0600`) or a secrets manager. `no_log: true` alone does not protect the on-disk unit file. If a real password was previously committed, rotate it; changing the current file does not erase Git history.

## 4. Configure the Ansible Control Server

From the **developer workstation**, in the repository root, verify the syntax:

```bash
ansible-playbook --syntax-check \
  -i ansible/inventory-terraform.ini \
  ansible/configure-ansible-server.yaml
```

Then install Ansible, supporting tools, Galaxy dependencies, and copy the Ansible project to the Control EC2:

```bash
ansible-playbook \
  -i ansible/inventory-terraform.ini \
  --private-key ~/.ssh/ansible-jenkins.pem \
  ansible/configure-ansible-server.yaml
```

The playbook should copy `ansible/files/java-app-1.0-SNAPSHOT.jar` and the configured inventory as well. Confirm the copy completed before proceeding.

## 5. Configure Web and DB from the Control Server

Connect from your workstation to the **trusted** Control EC2 with SSH agent forwarding:

```bash
ssh -A -i ~/.ssh/ansible-jenkins.pem ubuntu@<CONTROL_PUBLIC_IP>
```

Agent forwarding permits the remote Control EC2 to use your forwarded SSH agent while the session is active. Only use `-A` with a server you trust; do not copy your private SSH key to EC2.

On the **Control EC2**:

```bash
cd /home/ubuntu/ansible-project
ansible --version
ansible-galaxy role list
ansible-galaxy collection list
ansible -i inventory-terraform.ini all -m ping
```

The `geerlingguy.mysql` role and `ansible.mysql` collection should be installed by the Control configuration playbook using `requirements.yaml`. Check that the role and collection are available before running the next command.

Configure the DB and Web instances from **Control EC2**:

```bash
ansible-playbook \
  -i inventory-terraform.ini \
  configure-app-servers.yaml \
  --ask-vault-pass
```

The playbook is intended to install MySQL on the private DB server, create the application database/user, create a dedicated Linux user on Web, install Java 21, copy the JAR, and start a systemd service.

> **Before execution:** Verify the MySQL role is configured to listen on the DB private network interface (for example, using the role's supported bind-address variable), that the application uses the DB host's **private IP** rather than the inventory alias `db`, and that the MySQL authentication settings match the installed MySQL version. The current playbooks have passed syntax checks, not full runtime validation.

> The existing `run-app-playbooks.yaml` wrapper does not forward a Vault password prompt to its nested `ansible-playbook` command. When using Vault, run `configure-app-servers.yaml` interactively on Control as shown above, or update the wrapper explicitly.

## 6. Verify the application

From your **developer workstation** (whose public IPv4 is permitted by the Web security group):

```bash
curl -i http://<WEB_PUBLIC_IP>:8080/
```

Open the same address in your browser:

```text
http://<WEB_PUBLIC_IP>:8080
```

For troubleshooting, SSH from Control EC2 to Web using its **private IP**, then inspect the service:

```bash
sudo systemctl status java-app
sudo journalctl -u java-app -n 100 --no-pager
sudo ss -lntp
curl -i http://localhost:8080/
```

If the application cannot connect to MySQL, check the DB private IP, the MySQL bind address, the MySQL service status, the DB user's permissions, and the security group rule allowing TCP/3306 **from Web**.

## 7. Destroy AWS resources after the exercise

From the **developer workstation**, in the repository root:

```bash
cd terraform
terraform plan -destroy -var="my_ip=<YOUR_PUBLIC_IPV4>/32"
terraform destroy -var="my_ip=<YOUR_PUBLIC_IPV4>/32"
```

Review the destroy plan and confirm only the intended exercise resources will be deleted. Do **not** use the old Ansible `destroy.yaml` to remove Terraform-managed resources. Verify that EC2 instances, the NAT Gateway, Elastic IP, and other billable resources have actually been removed.

Terraform state may contain sensitive values. Keep state files out of Git and store them securely; `.gitignore` alone does not protect a remote state backend or files previously committed.

## Git hygiene

- Commit Terraform source files and `terraform/.terraform.lock.hcl`.
- Do not commit `.terraform/`, `*.tfstate`, `*.tfvars`, private SSH keys, Vault passwords, or plaintext credentials.
- Keep `ansible/vars/project-vars.yaml` tracked as a **non-secret example**.
- Keep the encrypted `ansible/vars/secrets.yaml` local under the current `.gitignore` policy.
- Do not run `git add .` until you have checked the changed files for secrets.

