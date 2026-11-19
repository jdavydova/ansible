# Exercise 6 — AWS Infrastructure Automation with Terraform and Ansible

## Overview

This learning project provisions AWS infrastructure with Terraform and uses Ansible to configure and deploy a Java Spring Boot application backed by MySQL.

The deployment was tested end to end: infrastructure provisioning, server configuration, database initialization, REST API reads, and database updates through the API.

## Technology Stack

| Technology | Purpose |
|---|---|
| AWS EC2, VPC, subnets, NAT Gateway, Security Groups | Compute, networking, and access control |
| Terraform | Infrastructure as Code |
| Ansible | Server configuration and application deployment |
| Java 21 / Spring Boot | Backend REST API |
| MySQL | Application database |
| Gradle | Build the Java application |
| Ansible Vault | Protect database credentials |
| Git / GitHub | Version control |

## Architecture

Three EC2 instances are provisioned:

- **Control Server (public subnet):** runs Ansible and configures the other instances over SSH.
- **Web Server (public subnet):** runs the Java application on TCP port `8080`.
- **Database Server (private subnet):** runs MySQL on TCP port `3306`.

```text
Developer's Mac
       |
       | SSH
       v
Ansible Control Server
       |
       | SSH / Ansible
       +---------------------+
       |                     |
       v                     v
   Web Server             DB Server
   Java :8080             MySQL :3306
       |                     ^
       +---------------------+
                 JDBC
```

The infrastructure also includes a VPC, Internet Gateway, NAT Gateway, route tables, and Security Groups. The Control Server can reach the Web Server on port `8080` using an ingress rule that references the Control Server's Security Group.

## Project Structure

```text
.
├── terraform/
│   ├── security-groups.tf
│   ├── ansible-inventory.tf
│   └── ...
├── ansible/
│   ├── ansible.cfg
│   ├── configure-ansible-server.yaml
│   ├── configure-app-servers.yaml
│   ├── build-app.yaml
│   ├── files/
│   └── vars/
├── src/
├── build.gradle
└── README.md
```

## Prerequisites

- AWS account with permissions to provision the resources
- AWS credentials configured on the Mac
- Terraform, Ansible, Gradle, and a suitable JDK installed locally
- SSH private key at `~/.ssh/ansible-jenkins.pem`
- Ansible Vault password for the encrypted database secrets

**Security:** Never commit private SSH keys, Terraform state, or decrypted secrets. The generated `ansible/inventory-terraform.ini` is ignored by Git because its addresses change on each deployment.

## Deployment

### 1. Build the Java application

Run on the **Mac**, from the repository root:

```bash
gradle clean build
ansible-playbook -i localhost, ansible/build-app.yaml
```

This prepares the application JAR for deployment through Ansible.

### 2. Provision AWS infrastructure

Run on the **Mac**, from `terraform/`:

```bash
terraform init
terraform fmt
terraform validate
terraform plan -var="my_ip=$(curl -fsS -4 https://checkip.amazonaws.com | tr -d '\n')/32"
terraform apply -var="my_ip=$(curl -fsS -4 https://checkip.amazonaws.com | tr -d '\n')/32"
```

Terraform creates the EC2 instances and generates `ansible/inventory-terraform.ini` with their current addresses. Save the Terraform outputs for the Control Server's public IP and the Web Server's private IP.

### 3. Configure the Ansible Control Server

Run on the **Mac**, from the repository root:

```bash
cd ansible
ansible-playbook \
  -i inventory-terraform.ini \
  configure-ansible-server.yaml \
  --private-key ~/.ssh/ansible-jenkins.pem
```

This configures the Control Server and installs the required Ansible Galaxy roles and collections.

### 4. Configure the DB and Web servers

Connect from the **Mac** to the Control Server, replacing the placeholder with the current Terraform output:

```bash
ssh -A -i ~/.ssh/ansible-jenkins.pem ubuntu@<CONTROL_PUBLIC_IP>
```

Then run **on the Control Server**:

```bash
cd ~/ansible-project
ansible-playbook \
  -i inventory-terraform.ini \
  configure-app-servers.yaml \
  --ask-vault-pass
```

The playbook waits for SSH connectivity, configures MySQL, creates the application database/user and `team_members` table, installs Java, deploys the JAR, and starts the application service.

## Verification

Run the following commands **on the Control Server**, from `~/ansible-project`.

### Verify the database table

```bash
ansible -i inventory-terraform.ini db_server \
  -b -m ansible.builtin.command \
  -a "mysql -N -e 'SHOW TABLES FROM \`java-app-db\`;'"
```

Expected table: `team_members`.

### Verify the Java REST API

Replace `<WEB_PRIVATE_IP>` with the current Terraform output:

```bash
curl --connect-timeout 5 --max-time 10 -i http://<WEB_PRIVATE_IP>:8080/get-data
```

An empty table returns `[]`. **Note:** in the current application, SQL exceptions may also result in `[]`; verify the table and test with an actual record rather than relying on an empty response alone.

### Insert a test record

```bash
ansible -i inventory-terraform.ini db_server \
  -b -m ansible.builtin.command \
  -a "mysql java-app-db -e \"INSERT INTO team_members (member_name, member_role) VALUES ('Test User', 'Developer') ON DUPLICATE KEY UPDATE member_role='Developer';\""
```

Now check:

```bash
curl -sS http://<WEB_PRIVATE_IP>:8080/get-data
```

Expected response:

```json
[{"name":"Test User","role":"Developer"}]
```

### Update a role through the API

```bash
curl -sS -X POST http://<WEB_PRIVATE_IP>:8080/update-roles \
  -H "Content-Type: application/json" \
  -d '[{"name":"Test User","role":"DevOps Engineer"}]'

curl -sS http://<WEB_PRIVATE_IP>:8080/get-data
```

Expected final response:

```json
[{"name":"Test User","role":"DevOps Engineer"}]
```

This confirms that the API can both read and update persisted MySQL data.

## Security Considerations

- Restrict SSH access using Security Group rules.
- Allow application access from the configured developer public IP and, separately, from the Control Server Security Group.
- Keep the MySQL instance in the private subnet.
- Store database credentials in encrypted Ansible Vault files.
- Keep host-key checking enabled. `StrictHostKeyChecking=accept-new` accepts previously unknown hosts, but **does not** silently accept a changed key for an existing host.
- The application currently interpolates input into SQL update statements. Replace this with parameterized queries (`PreparedStatement`) before any production use.

This is a learning environment, **not** a production-ready deployment.

## Troubleshooting

### `Host key verification failed`

Run Ansible from the `ansible/` directory and check which configuration is loaded:

```bash
ansible --version | grep 'config file'
```

If a previously known host's key changes after EC2 recreation, verify the new host fingerprint before updating `known_hosts`.

### API unreachable from the Control Server

Check whether Java is listening on the Web Server:

```bash
ansible -i inventory-terraform.ini web_server \
  -b -m ansible.builtin.shell \
  -a "ss -lntp | grep ':8080' || true"
```

Then test locally on the Web Server:

```bash
ansible -i inventory-terraform.ini web_server \
  -m ansible.builtin.command \
  -a "curl --max-time 10 -i http://127.0.0.1:8080/get-data"
```

If the local test succeeds but the Control Server times out, check the Web Security Group's port `8080` ingress rules.

**Important:** `10.x.x.x` private VPC addresses are not directly reachable from a Mac on the public internet. Run private-IP checks from the Control Server or another authorized host inside the VPC.

### API returns `[]`

The table may be empty, or the current Java application may have caught a SQL exception. Confirm that `team_members` exists, inspect application logs, and test with a known record.

## Cleanup

AWS resources such as EC2 instances and NAT Gateways can incur charges. After testing, run on the **Mac**, from `terraform/`:

```bash
terraform destroy -var="my_ip=$(curl -fsS -4 https://checkip.amazonaws.com | tr -d '\n')/32"
```

Review the destroy plan before confirming. This deletes the test servers and database data, but not the Git repository.

## Verified Results

- Terraform provisioned the AWS infrastructure.
- Ansible configured the Control, Web, and DB servers without failed tasks.
- Ansible created the `team_members` table automatically.
- The Java API returned HTTP `200` from the Web Server and from the Control Server after the Security Group update.
- A test record inserted into MySQL was returned by `GET /get-data`.
- `POST /update-roles` changed the stored role, confirmed by a subsequent GET request.
- The infrastructure changes were committed and pushed to GitHub.

## Future Improvements

- Add Jenkins-based CI/CD.
- Add automated integration tests.
- Use parameterized SQL and improve exception handling.
- Add HTTPS, a reverse proxy, and observability.
- Strengthen secrets management and deployment automation.
