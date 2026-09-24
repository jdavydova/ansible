# Ansible Exercise 3 - Create and Configure a Jenkins EC2 Server

## Exercise goal

Create a new EC2 instance with Ansible and configure it as a Jenkins build server. The server must have:

- Java
- Jenkins
- Node.js
- npm
- Docker

The goal is to make it possible to spin up and configure a Jenkins server with one Ansible playbook command.

## Architecture

```text
Local machine
    |
    | Ansible
    v
AWS API -> EC2 instance
              |
              | SSH
              v
        Ubuntu server
          |- Java 21
          |- Jenkins
          |- Node.js
          |- npm
          `- Docker
```

This exercise uses Ansible for both infrastructure provisioning and server configuration. In many production environments Terraform would create the EC2 infrastructure and Ansible would configure the operating system and software.

## Environment used

- AWS region: `eu-north-1`
- Instance type: `t3.micro`
- Ubuntu AMI: `ami-0aba19e56f3eaec05`
- Subnet: `subnet-0040a19a99d2c01ed`
- SSH key pair: `ansible-jenkins`
- SSH user: `ubuntu`
- Jenkins port: `8080`

## 1. Create the EC2 instance

The first play runs locally because Ansible needs to call the AWS API before the remote server exists.

```yaml
- name: Create Jenkins EC2
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: Create EC2 instance
      amazon.aws.ec2_instance:
        name: "jenkins-server-2"
        key_name: "ansible-jenkins"
        instance_type: "t3.micro"
        image_id: "ami-0aba19e56f3eaec05"
        region: "eu-north-1"
        vpc_subnet_id: "subnet-0040a19a99d2c01ed"
        wait: true
      register: ec2
```

### Problem: subnet ID was used as a security group

Initially the configuration contained something similar to:

```yaml
security_group: "subnet-0040a19a99d2c01ed"
```

and Ansible failed with:

```text
Module failed: 'NoneType' object is not subscriptable
```

A subnet and a security group are different AWS resources:

```text
subnet-... -> Subnet
sg-...     -> Security Group
```

The subnet must therefore be specified with:

```yaml
vpc_subnet_id: "subnet-0040a19a99d2c01ed"
```

We also removed a trailing space that was present after the subnet ID.

## 2. Public IP issue

The EC2 instance was initially created successfully but had only a private IP address. This meant the local Ansible machine could not connect to it over the Internet.

An attempt to add:

```yaml
network:
  assign_public_ip: true
```

produced a warning because public IP assignment is determined when an instance is created. The `network` parameter was also deprecated in the installed `amazon.aws` collection.

An attempt using `network_interfaces` also resulted in the module error:

```text
'NoneType' object is not subscriptable
```

The practical solution was to enable automatic public IPv4 assignment on the subnet and keep the EC2 task simple.

Check the subnet setting:

```bash
aws ec2 describe-subnets \
  --region eu-north-1 \
  --subnet-ids subnet-0040a19a99d2c01ed \
  --query 'Subnets[0].MapPublicIpOnLaunch'
```

If it is `false`, enable it:

```bash
aws ec2 modify-subnet-attribute \
  --region eu-north-1 \
  --subnet-id subnet-0040a19a99d2c01ed \
  --map-public-ip-on-launch
```

After this, the new EC2 instance received a public IP and could be reached over SSH.

## 3. Add the new server to Ansible runtime inventory

Because the EC2 instance is created during the same playbook run, its IP address is not known before execution. We register the AWS module result and dynamically add the new host to an in-memory inventory group.

```yaml
    - name: Add Jenkins server to inventory
      ansible.builtin.add_host:
        name: "{{ ec2.instances[0].public_ip_address }}"
        groups: jenkins_server
        ansible_user: ubuntu
        ansible_ssh_private_key_file: "~/.ssh/ansible-jenkins.pem"
```

Then wait until SSH is available:

```yaml
    - name: Wait for SSH
      ansible.builtin.wait_for:
        host: "{{ ec2.instances[0].public_ip_address }}"
        port: 22
        timeout: 300
```

This allows the second play to use:

```yaml
- name: Configure Jenkins server
  hosts: jenkins_server
  become: true
```

### Inventory warnings

The command can show:

```text
No inventory was parsed, only implicit localhost is available
provided hosts list is empty, only localhost is available
```

For this playbook this is expected at startup because the first play uses `localhost` and the remote Jenkins host is added dynamically with `add_host`.

## 4. YAML indentation problems

One error encountered was:

```text
conflicting action statements: hosts, tasks
```

This happened because the second play was accidentally indented inside the first play's `tasks` section.

A new play must start at the top level:

```yaml
- name: Configure Jenkins server
  hosts: jenkins_server
  become: true

  tasks:
```

Another error was:

```text
'ansible.builtin.get_url' is not a valid attribute for a Play
```

This happened because Jenkins installation tasks were outside the `tasks:` block. YAML indentation defines the structure of an Ansible playbook, so task indentation must be consistent.

On macOS editors, `Shift + Tab` can usually move selected code one indentation level to the left.

## 5. Install Java for Jenkins

We initially installed Java 17:

```yaml
- name: Install Java 17
  ansible.builtin.apt:
    name: openjdk-17-jre
    state: present
    update_cache: true
```

The Jenkins package installed, but the Jenkins service failed to start.

Useful diagnostic commands were:

```bash
sudo systemctl status jenkins --no-pager -l
sudo journalctl -xeu jenkins.service --no-pager
java -version
```

The Jenkins log showed the actual problem:

```text
Running with Java 17 ... which is older than the minimum required version (Java 21).
Supported Java versions are: [21, 25]
```

The playbook was changed to Java 21:

```yaml
    - name: Install Java 21
      ansible.builtin.apt:
        name: openjdk-21-jre
        state: present
        update_cache: true
```

After that Jenkins could start successfully.

## 6. Install Jenkins

Add the Jenkins repository key:

```yaml
    - name: Add Jenkins repository key
      ansible.builtin.get_url:
        url: https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
        dest: /usr/share/keyrings/jenkins-keyring.asc
        mode: "0644"
```

Add the Jenkins repository:

```yaml
    - name: Add Jenkins repository
      ansible.builtin.apt_repository:
        repo: "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/"
        state: present
        filename: jenkins
```

Install Jenkins:

```yaml
    - name: Install Jenkins
      ansible.builtin.apt:
        name: jenkins
        state: present
        update_cache: true
```

Start it and enable it at boot:

```yaml
    - name: Start and enable Jenkins
      ansible.builtin.service:
        name: jenkins
        state: started
        enabled: true
```

### Problem: Jenkins service did not exist

At one point the playbook tried to start Jenkins before the package had been installed and failed with:

```text
Could not find the requested service jenkins: host
```

The missing `Install Jenkins` task was added before the service task.

### `apt_repository` deprecation warning

With the current Ansible version, this warning is displayed:

```text
ansible.builtin.apt_repository has been deprecated.
Use deb822_repository instead.
```

The current task still works, but a future improvement is to migrate the repository definition to `ansible.builtin.deb822_repository` before `apt_repository` is removed from ansible-core.

## 7. Open Jenkins port 8080

Jenkins was running on the EC2 instance, but connecting from the local machine to:

```text
http://<PUBLIC_IP>:8080
```

initially hung.

The service could be checked directly on EC2 with:

```bash
sudo ss -lntp | grep 8080
curl http://localhost:8080
```

The issue was network access through the AWS Security Group. TCP port `8080` must be allowed for the client that needs Jenkins access.

For better security, allow only the required public IP using `/32` rather than exposing Jenkins to the entire Internet.

Example:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id <SECURITY_GROUP_ID> \
  --protocol tcp \
  --port 8080 \
  --cidr <YOUR_PUBLIC_IP>/32 \
  --region eu-north-1
```

After the Security Group rule was added, the Jenkins web UI became accessible.

## 8. Unlock Jenkins

The first Jenkins page asks for the initial administrator password stored at:

```text
/var/lib/jenkins/secrets/initialAdminPassword
```

Retrieve it on EC2:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Then paste it into the Jenkins UI, install the suggested plugins, create the admin user, and complete the setup wizard.

## 9. Install Node.js and npm

Node.js and npm are required for Jenkins builds.

```yaml
    - name: Install Node.js
      ansible.builtin.apt:
        name: nodejs
        state: present

    - name: Install npm
      ansible.builtin.apt:
        name: npm
        state: present
```

The playbook output confirmed both packages were installed successfully:

```text
TASK [Install Node.js]
changed

TASK [Install npm]
changed
```

On subsequent runs these tasks returned `ok`, demonstrating Ansible idempotency: if the desired state already exists, Ansible does not reinstall the packages unnecessarily.

Verify manually if needed:

```bash
node --version
npm --version
```

## 10. Install Docker

On Ubuntu the package used in this exercise is `docker.io`:

```yaml
    - name: Install Docker
      ansible.builtin.apt:
        name: docker.io
        state: present
        update_cache: true
```

Ensure Docker is running and enabled at boot:

```yaml
    - name: Start and enable Docker
      ansible.builtin.service:
        name: docker
        state: started
        enabled: true
```

### Docker installation appeared to hang

During the playbook run Ansible appeared to stop at:

```text
TASK [Install Docker]
```

Instead of immediately interrupting Ansible, we connected to EC2 from another terminal and inspected the service/process state.

Useful commands:

```bash
ps aux | grep -E 'apt|dpkg'
sudo systemctl status docker --no-pager -l
sudo tail -f /var/log/dpkg.log
df -h
```

The Docker service log eventually showed:

```text
Started docker.service - Docker Application Container Engine.
```

Docker was then verified with:

```bash
docker --version
sudo docker ps
```

The result showed Docker 29.1.3 and `docker ps` completed successfully. The empty container list is normal when no containers are currently running.

## 11. Allow Jenkins builds to use Docker

Installing Docker is not enough if Jenkins jobs need to execute Docker commands. Jenkins normally runs as the Linux user `jenkins`, so that user should be added to the `docker` group.

```yaml
    - name: Add Jenkins user to Docker group
      ansible.builtin.user:
        name: jenkins
        groups: docker
        append: true
```

Restart Jenkins so its processes receive the new group membership:

```yaml
    - name: Restart Jenkins
      ansible.builtin.service:
        name: jenkins
        state: restarted
```

Verify:

```bash
id jenkins
sudo -u jenkins docker ps
```

If `docker` appears in the Jenkins user's groups and `sudo -u jenkins docker ps` does not return a permission error, Jenkins can use Docker in builds.

## Final playbook structure

The important design is to use two plays:

```text
PLAY 1 - localhost
  |- Create EC2
  |- Register EC2 result
  |- Add EC2 public IP to runtime inventory
  `- Wait for SSH

PLAY 2 - jenkins_server
  |- Test connection
  |- Install Java 21
  |- Configure Jenkins repository
  |- Install Jenkins
  |- Start Jenkins
  |- Install Node.js
  |- Install npm
  |- Install Docker
  |- Start Docker
  |- Add Jenkins to docker group
  `- Restart Jenkins
```

A consolidated version is:

```yaml
---
- name: Create Jenkins EC2
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: Create EC2 instance
      amazon.aws.ec2_instance:
        name: "jenkins-server-2"
        key_name: "ansible-jenkins"
        instance_type: "t3.micro"
        image_id: "ami-0aba19e56f3eaec05"
        region: "eu-north-1"
        vpc_subnet_id: "subnet-0040a19a99d2c01ed"
        wait: true
      register: ec2

    - name: Show EC2 result
      ansible.builtin.debug:
        var: ec2

    - name: Add Jenkins server to inventory
      ansible.builtin.add_host:
        name: "{{ ec2.instances[0].public_ip_address }}"
        groups: jenkins_server
        ansible_user: ubuntu
        ansible_ssh_private_key_file: "~/.ssh/ansible-jenkins.pem"

    - name: Wait for SSH
      ansible.builtin.wait_for:
        host: "{{ ec2.instances[0].public_ip_address }}"
        port: 22
        timeout: 300

- name: Configure Jenkins server
  hosts: jenkins_server
  become: true

  tasks:
    - name: Test connection
      ansible.builtin.ping:

    - name: Install Java 21
      ansible.builtin.apt:
        name: openjdk-21-jre
        state: present
        update_cache: true

    - name: Add Jenkins repository key
      ansible.builtin.get_url:
        url: https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
        dest: /usr/share/keyrings/jenkins-keyring.asc
        mode: "0644"

    - name: Add Jenkins repository
      ansible.builtin.apt_repository:
        repo: "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/"
        state: present
        filename: jenkins

    - name: Install Jenkins
      ansible.builtin.apt:
        name: jenkins
        state: present
        update_cache: true

    - name: Start and enable Jenkins
      ansible.builtin.service:
        name: jenkins
        state: started
        enabled: true

    - name: Install Node.js
      ansible.builtin.apt:
        name: nodejs
        state: present

    - name: Install npm
      ansible.builtin.apt:
        name: npm
        state: present

    - name: Install Docker
      ansible.builtin.apt:
        name: docker.io
        state: present
        update_cache: true

    - name: Start and enable Docker
      ansible.builtin.service:
        name: docker
        state: started
        enabled: true

    - name: Add Jenkins user to Docker group
      ansible.builtin.user:
        name: jenkins
        groups: docker
        append: true

    - name: Restart Jenkins
      ansible.builtin.service:
        name: jenkins
        state: restarted
```

## Run the playbook

```bash
ansible-playbook create-jenkins-server.yaml
```

When the EC2 resource already exists in the desired state, the AWS task can return:

```text
TASK [Create EC2 instance]
ok: [localhost]
```

rather than creating another instance. This is an important example of idempotency.

## Verification checklist

After a successful run:

```bash
java -version
node --version
npm --version
docker --version
sudo docker ps
sudo systemctl status jenkins --no-pager
sudo systemctl status docker --no-pager
id jenkins
sudo -u jenkins docker ps
```

Expected state:

```text
EC2       OK
Public IP OK
SSH       OK
Java 21   OK
Jenkins   OK
Port 8080 OK
Node.js   OK
npm       OK
Docker    OK
```

## What we learned

### Ansible can provision infrastructure

Although Ansible is mainly known for configuration management, modules such as `amazon.aws.ec2_instance` can also create cloud resources. That is why this exercise can create and configure the Jenkins server in one playbook.

### Terraform vs Ansible

A common production separation is:

```text
Terraform -> infrastructure
Ansible   -> server configuration
```

For example:

```text
Terraform
  |- VPC
  |- Subnets
  |- Security Groups
  `- EC2
       |
       v
Ansible
  |- Java
  |- Jenkins
  |- Docker
  |- Node.js/npm
  `- Linux configuration
```

However, teams can work without Ansible. Terraform `user_data`, prebuilt machine images, containers, Kubernetes, Helm, or GitOps tools may remove the need for traditional configuration management.

Ansible is particularly useful when a team has existing VMs/servers that must be repeatedly configured, updated, or kept in a desired OS/software state.

