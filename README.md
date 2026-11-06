EXERCISE 6: Web server and Database server configuration
Great, you have helped automate some IT processes in your company. Now another team wants your support as well. They want to automate deploying and configuring a web server and a database server on AWS. The project is not dockerized and they are using a traditional application setup.

The setup you and the team agreed on is the following: You create a dedicated Ansible server on AWS. In the same VPC as the Ansible server, you create 2 servers, 1 for deploying your Java application and another one for running a MySQL database. Also, the database should not be accessible from outside, only within the VPC, so the DB server shouldn't have a public IP address.

So your task is to:

Provision and configure dedicated Ansible server

Write an Ansible playbook that provisions a dedicated ansible-control-plane server
Write an Ansible playbook that configures the ansible server with all needed tools as well as copies all needed ansible playbooks and configuration for execution there
Provision and configure databse and web servers

Write Ansible playbook that provisions database and web servers.
Write Ansible playbook that installs and starts MySQL server on the EC2 instance without a public IP address. And deploys and runs the Java web application on another EC2 instance
NOTES:

Use an existing mysql role for installing mysql on the database server, instead of writing the whole logic yourself
The last 2 playbooks for provisioning and configuring web and database servers will be executed from Ansible control server, because we can't access the database private IP address from outside VPC
Since the database server will have no public IP address, it will not have direct internet access. But we will need to download and install some tools, like mysql service itself on the server, and you can do it via NAT gateway. So make sure to create database server in a "private" subnet, with NAT gateway instead of Internet gateway configuration.
Once all the playbooks executed successfully, check that the java application is running and accessible from browser at http://web-server-public-address:8080

# Exercise 6 — Automated AWS Infrastructure and Java Application Deployment with Ansible

An Ansible-based DevOps exercise that provisions AWS infrastructure, configures an Ansible control node, deploys a Java application and MySQL database on separate EC2 instances, and provides playbooks for cleanup and teardown.

> **Scope:** This repository archive contains the `ansible/` directory and a prebuilt application JAR. The Java/Gradle source project is not included in this archive. This README documents the playbooks as supplied, rather than claiming that every operation has been tested in a fresh AWS account.

## Architecture

```text
Developer workstation (Ansible + AWS credentials + SSH key)
    |
    | SSH :22 (developer public IPv4 /32)
    v
AWS VPC: exercise-6-vpc (10.0.0.0/16), eu-north-1
|
+-- Public subnet: 10.0.1.0/24
|   +-- Ansible Control Server (EC2, public IP, IAM instance profile)
|   |      | SSH :22 over private networking
|   |      +----------------------------+
|   |                                   |
|   +-- Web Server (EC2, public IP) <---+
|          Java / Spring Boot :8080
|          | MySQL :3306
|          v
+-- Private subnet: 10.0.2.0/24
|   +-- DB Server (EC2, private IP only)
|          MySQL
|   +-- Private route table -> NAT Gateway in public subnet
|
+-- Internet Gateway + public route table
```

The public subnet hosts the control and web servers. The database is isolated in the private subnet and can use the NAT Gateway for outbound access. Both subnets are configured in `eu-north-1a`.

### Network access

| Destination | Port | Allowed source |
|---|---:|---|
| Ansible Control Server | 22/TCP | Developer's detected public IPv4 (`/32`) |
| Web Server | 22/TCP | Ansible Control security group |
| Web Server | 8080/TCP | Developer's detected public IPv4 (`/32`) |
| DB Server | 22/TCP | Ansible Control security group |
| DB Server | 3306/TCP | Web Server security group |

**Note:** Port 8080 is not opened to the Ansible Control security group. Access from the developer's allowed public IP is the intended test path; a request to the web server's private IP from the control node may time out even when the Java service is running.

## Technology stack

- **Automation:** Ansible, `amazon.aws`, custom Ansible roles, `geerlingguy.mysql`
- **Cloud:** AWS EC2, VPC, subnets, route tables, Internet Gateway, NAT Gateway, Elastic IP, Security Groups, IAM
- **Application:** Java 21, Spring Boot application packaged as a JAR, systemd
- **Database:** MySQL (`community.mysql` module for application user creation)
- **Build:** Gradle (when the parent Java source project is available)
- **Region:** `eu-north-1` (Stockholm)

## Repository layout

```text
ansible/
├── deploy-all.yaml                 # Main orchestration entry point
├── provision-network.yaml         # VPC, subnets, routing, NAT, security groups
├── provision-iam.yaml             # IAM policy, role and instance profile
├── provision-ansible-server.yaml  # Control EC2 instance
├── configure-ansible-server.yaml  # Install Ansible/AWS dependencies and copy project
├── run-app-playbooks.yaml         # Run application playbooks from control server
├── provision-app-servers.yaml     # Web and DB EC2 instances
├── configure-app-servers.yaml     # MySQL, Java, systemd application service
├── build-app.yaml                 # Optional local Gradle build and JAR copy
├── cleanup.yaml                   # Terminate EC2 instances with project tag
├── destroy.yaml                   # EC2 and network infrastructure teardown
├── inventory                      # Local Ansible control group configuration
├── vars/
│   └── project-vars.yaml          # Shared app and database variables
├── templates/
│   └── ansible-control-policy.json.j2
├── roles/
│   ├── create_user/
│   └── install_java/
└── files/
    └── java-app-1.0-SNAPSHOT.jar  # Prebuilt deployable application
```

## Prerequisites

1. An AWS account with credentials permitted to provision the EC2, networking and IAM resources used by the playbooks.
2. Ansible installed on your workstation, plus the `amazon.aws` collection and Python AWS SDK (`boto3`/`botocore`) in the Python environment used by Ansible.
3. AWS CLI configured for the intended account, with `eu-north-1` available.
4. An existing EC2 key pair named **`ansible-jenkins`**, with its private key at `~/.ssh/ansible-jenkins.pem` on your workstation.
5. Network access to AWS APIs and SSH access from your workstation's current public IPv4 address.
6. Sufficient AWS service quotas and budget for three `t3.micro` EC2 instances, a NAT Gateway, an Elastic IP and related resources.

Example setup and checks:

```bash
aws sts get-caller-identity
aws configure get region
ansible-galaxy collection install amazon.aws
python3 -m pip show boto3 botocore
chmod 600 ~/.ssh/ansible-jenkins.pem
```

> The playbooks reference a specific Ubuntu AMI (`ami-0aba19e56f3eaec05`) in `eu-north-1`. Verify that it is still available before deploying. The `geerlingguy.mysql` Galaxy role is installed by `run-app-playbooks.yaml` on the control node. Ensure its required MySQL collection dependencies are available as well.

## Deployment

Run the commands from the `ansible/` directory.

### 1. Optional: build the Java application

The archive already contains `files/java-app-1.0-SNAPSHOT.jar`. If you also have the parent Java/Gradle project, rebuild and copy the JAR with:

```bash
ansible-playbook -i inventory build-app.yaml
```

`build-app.yaml` runs `gradle build` in the parent directory and copies the resulting JAR into `ansible/files/`. **It is not part of `deploy-all.yaml`**, so run it separately whenever you change application code.

### 2. Deploy the infrastructure and application

```bash
ansible-playbook -i inventory deploy-all.yaml
```

The orchestrator imports the playbooks in this order:

1. `provision-network.yaml` — VPC, subnets, route tables, IGW, NAT Gateway, Elastic IP and security groups.
2. `provision-iam.yaml` — restricted custom policy, role and instance profile for the control node.
3. `provision-ansible-server.yaml` — EC2 control node and dynamic Ansible inventory entry.
4. `configure-ansible-server.yaml` — installs required software and copies the Ansible project.
5. `run-app-playbooks.yaml` — transfers the SSH key, installs the MySQL Galaxy role and executes the app provisioning/configuration playbooks on the control node.

The application servers are provisioned and configured **from the Ansible Control Server**, not directly from the developer workstation. Host discovery uses AWS instance information and dynamically adds hosts to inventory.

### 3. Verify the application

Find the Web Server's public IPv4 address in the playbook output or AWS EC2 console. From the developer workstation whose public IP is allowed by the security group:

```bash
curl -i http://<WEB_PUBLIC_IP>:8080/
```

You can also inspect the service from the Web Server itself:

```bash
sudo systemctl status java-app
sudo journalctl -u java-app -n 100 --no-pager
curl -i http://localhost:8080/
```

The web service is installed as `/etc/systemd/system/java-app.service`, enabled at boot, and configured to restart automatically. The service receives database connection details through environment variables.

## Cleanup and teardown

### Terminate project EC2 instances only

```bash
ansible-playbook -i inventory cleanup.yaml
```

`cleanup.yaml` selects EC2 instances tagged `Project=ansible-exercise-6`. This includes the control node for **new deployments** using the updated `provision-ansible-server.yaml`; older control instances may not have the tag. This playbook does **not** delete VPC networking.

### Destroy the EC2 and network infrastructure

```bash
ansible-playbook -i inventory destroy.yaml
```

`destroy.yaml` discovers and terminates the named Web, DB and Control EC2 instances (filtered by project tag), then attempts to delete the NAT Gateway, release the associated tagged Elastic IP, delete DB/Web/Control security groups, remove both subnets, delete the two custom route tables, remove the Internet Gateway and delete the VPC. It also checks that no more than one VPC matches the project name.

**Important limitations:**

- Run teardown from your **workstation**, not from the control node that will be terminated.
- The main VPC route table is AWS-managed as part of VPC deletion; the playbook explicitly targets the two named custom route tables.
- Resource deletion can fail because of AWS dependencies, timing or resources created outside these playbooks. Inspect the final play recap and AWS console rather than assuming a completely empty account.
- These actions are destructive and may incur AWS charges until resources are actually removed.

## Security considerations

- The SSH security group and web application ingress are limited to the developer's detected public IPv4 address, rather than the entire internet.
- The database server has no public IP and allows MySQL traffic only from the Web Server security group.
- The control server uses an IAM instance profile backed by a project-specific policy template.
- **Do not commit real credentials.** `vars/project-vars.yaml` currently contains a plaintext database password value. Replace it with Ansible Vault, AWS Secrets Manager or another appropriate secret-management approach before using this outside a learning environment.
- `run-app-playbooks.yaml` copies the developer's private SSH key to the control server. This is a deliberate exercise implementation, but it increases key exposure; use tighter key handling or an alternative access model for production.
- `configure-app-servers.yaml` writes database credentials into a systemd unit. Prefer a protected environment file or secret retrieval at runtime in production.
- Review the AWS account, region, tags and resource identifiers before running `destroy.yaml`.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `provided hosts list is empty` warning | The local inventory initially contains no concrete hosts; the control server is added dynamically during deployment. |
| SSH timeout or banner exchange error | Instance status checks, security group source IPv4, SSH service readiness, key pair and username (`ubuntu`). An open TCP port alone does not guarantee a successful SSH handshake. |
| Application does not respond on port 8080 | `systemctl status java-app`, `journalctl`, `ss -lntp`, the Web Server public IP and developer-IP security group rule. |
| Control node cannot `curl` Web Server on port 8080 | The Web Server ingress rule permits the developer's public IP, not the control server's security group. |
| Database connection fails | Private IP discovery, DB security group TCP/3306 rule, MySQL service and application database variables. |
| Teardown fails with dependency errors | Wait for EC2/NAT deletion and inspect remaining network interfaces, security group references, subnet associations and route tables. |
| AWS authentication or permission error | AWS CLI identity, region, IAM policy, SDK installation and credentials on the machine running the task. |

## What this exercise demonstrates

- AWS infrastructure provisioning with Ansible instead of manual console configuration.
- A public/private VPC design with NAT-based outbound access for private workloads.
- Project-scoped IAM permissions and EC2 instance profiles.
- Multi-stage orchestration across a developer workstation, Ansible control node and managed EC2 instances.
- Reusable Ansible roles, shared variables, dynamic inventory and systemd service management.
- Separate workflows for application build, deployment, EC2 cleanup and broader infrastructure teardown.

---

**Project type:** Educational DevOps / Ansible exercise. Not production-hardened; review credentials, access controls, AMI selection, dependency versions and teardown safeguards before reuse.
