# Ansible Exercise 4: Install Jenkins on Multiple Linux OS Families

## Overview

This exercise extends the Jenkins provisioning playbook so that Jenkins
can be configured on different Linux OS families.

The playbook:

-   creates an AWS Security Group for Jenkins;
-   creates an EC2 instance;
-   assigns a public IP address;
-   dynamically adds the new instance to the Ansible inventory;
-   waits until SSH is available;
-   gathers facts from the remote server;
-   detects the operating system family;
-   includes the appropriate task file for Debian/Ubuntu or RedHat-based
    systems;
-   installs Java 21, Jenkins, Node.js, Docker, and related
    dependencies;
-   starts and enables Docker and Jenkins.

The main idea of this exercise is to avoid putting OS-specific
package-management logic into one large playbook. Instead, Ansible
detects the OS family and loads the correct task file with
`include_tasks`.

------------------------------------------------------------------------

## Project Structure

``` text
ansible-exercises/
├── create-jenkins-server.yaml
└── tasks/
    ├── ubuntu.yaml
    └── redhat.yaml
```

The main playbook contains the common infrastructure and OS-detection
logic.

The files under `tasks/` contain OS-specific installation steps.

------------------------------------------------------------------------

## Main Playbook

`create-jenkins-server.yaml`

``` yaml
---
- name: Create Jenkins EC2
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: Create security group for Jenkins
      amazon.aws.ec2_security_group:
        name: jenkins-sg
        description: Security group for Jenkins
        region: eu-north-1
        vpc_id: vpc-054cf680083727d58
        rules:
          - proto: tcp
            ports:
              - 22
            cidr_ip: 0.0.0.0/0

          - proto: tcp
            ports:
              - 8080
            cidr_ip: 0.0.0.0/0
      register: jenkins_sg

    - name: Create EC2 instance
      amazon.aws.ec2_instance:
        name: "jenkins-server"
        key_name: "ansible-jenkins"
        instance_type: "t3.micro"
        image_id: "ami-0aba19e56f3eaec05"
        region: "eu-north-1"
        vpc_subnet_id: "subnet-0040a19a99d2c01ed"
        security_group: "{{ jenkins_sg.group_id }}"
        network:
          assign_public_ip: true
        wait: true
      register: ec2

    - name: Show EC2 result
      ansible.builtin.debug:
        msg: "{{ ec2.instances[0].public_ip_address }}"

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
  gather_facts: true

  tasks:
    - name: Install Jenkins on Ubuntu
      ansible.builtin.include_tasks: tasks/ubuntu.yaml
      when: ansible_facts["os_family"] == "Debian"

    - name: Install Jenkins on RedHat
      ansible.builtin.include_tasks: tasks/redhat.yaml
      when: ansible_facts["os_family"] == "RedHat"

    - name: Show detected OS family
      ansible.builtin.debug:
        msg: "OS family: {{ ansible_facts['os_family'] }}"
```

------------------------------------------------------------------------

## OS Detection with Ansible Facts

The second play enables:

``` yaml
gather_facts: true
```

Before running the tasks, Ansible collects information about the remote
machine, including its operating system.

The playbook uses:

``` yaml
ansible_facts["os_family"]
```

For Ubuntu, the OS family is normally:

``` text
Debian
```

For RedHat-family systems, it is:

``` text
RedHat
```

The conditions therefore select the appropriate task file:

``` yaml
- name: Install Jenkins on Ubuntu
  ansible.builtin.include_tasks: tasks/ubuntu.yaml
  when: ansible_facts["os_family"] == "Debian"

- name: Install Jenkins on RedHat
  ansible.builtin.include_tasks: tasks/redhat.yaml
  when: ansible_facts["os_family"] == "RedHat"
```

Conceptually:

``` text
Remote server
     |
     v
Gather Ansible facts
     |
     v
Check os_family
     |
     +---- Debian ----> tasks/ubuntu.yaml
     |
     +---- RedHat ----> tasks/redhat.yaml
```

This keeps the main playbook clean and separates
package-manager-specific tasks.

------------------------------------------------------------------------

## Ubuntu Tasks

`tasks/ubuntu.yaml`

``` yaml
---
- name: Install Java 21
  ansible.builtin.apt:
    name: openjdk-21-jre
    state: present
    update_cache: true

- name: Set Java 21 as default
  ansible.builtin.command:
    cmd: update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java

- name: Download Jenkins repository key
  ansible.builtin.get_url:
    url: https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
    dest: /usr/share/keyrings/jenkins-keyring.asc
    mode: "0644"

- name: Add Jenkins repository
  ansible.builtin.deb822_repository:
    name: jenkins
    types:
      - deb
    uris:
      - https://pkg.jenkins.io/debian-stable
    suites:
      - binary/
    signed_by: /usr/share/keyrings/jenkins-keyring.asc
    state: present

- name: Install Jenkins
  ansible.builtin.apt:
    name: jenkins
    state: present
    update_cache: true

- name: Install Node.js and npm
  ansible.builtin.apt:
    name:
      - nodejs
      - npm
    state: present

- name: Install Docker
  ansible.builtin.apt:
    name: docker.io
    state: present

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

- name: Start and enable Jenkins
  ansible.builtin.service:
    name: jenkins
    state: started
    enabled: true
```

Ubuntu uses the `apt` package manager.

Java 21 is explicitly selected as the default Java executable because
Jenkins requires a supported Java version.

------------------------------------------------------------------------

## RedHat Tasks

`tasks/redhat.yaml`

``` yaml
---
- name: Install Java 21
  ansible.builtin.dnf:
    name: java-21-amazon-corretto
    state: present

- name: Add Jenkins repository
  ansible.builtin.get_url:
    url: https://pkg.jenkins.io/redhat-stable/jenkins.repo
    dest: /etc/yum.repos.d/jenkins.repo

- name: Import Jenkins key
  ansible.builtin.rpm_key:
    state: present
    key: https://pkg.jenkins.io/redhat-stable/jenkins.io-2026.key

- name: Install Jenkins
  ansible.builtin.dnf:
    name: jenkins
    state: present

- name: Install Node.js
  ansible.builtin.dnf:
    name: nodejs
    state: present

- name: Install Docker
  ansible.builtin.dnf:
    name: docker
    state: present

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

- name: Start and enable Jenkins
  ansible.builtin.service:
    name: jenkins
    state: started
    enabled: true
```

This task file uses `dnf` instead of `apt`.

> **Note:** `java-21-amazon-corretto` is Amazon Linux-specific rather
> than a generic package for every RedHat-family distribution. If this
> playbook is extended to RHEL, Rocky Linux, AlmaLinux, Fedora, or
> another RedHat-family system, the Java and Docker package names may
> need separate distribution-specific handling.

------------------------------------------------------------------------

## Dynamic Inventory

The EC2 instance does not need to exist in a static inventory before the
playbook starts.

After creating the instance, its public IP is registered in:

``` yaml
ec2.instances[0].public_ip_address
```

The `add_host` module then creates an in-memory inventory entry:

``` yaml
- name: Add Jenkins server to inventory
  ansible.builtin.add_host:
    name: "{{ ec2.instances[0].public_ip_address }}"
    groups: jenkins_server
```

The second play can therefore use:

``` yaml
hosts: jenkins_server
```

The flow is:

``` text
localhost
   |
   v
Create EC2
   |
   v
Get public IP
   |
   v
add_host
   |
   v
jenkins_server group
   |
   v
Configure remote server
```

------------------------------------------------------------------------

## Security Group

The playbook creates an AWS Security Group with:

``` text
22    SSH
8080  Jenkins Web UI
```

For a learning environment, the example allows access from:

``` text
0.0.0.0/0
```

This means any IPv4 address can attempt to connect to those ports.

> **Security note:** for a real environment, SSH and Jenkins should
> normally be restricted to trusted IP ranges, VPNs, private networks,
> load balancers, or other controlled access paths instead of exposing
> them broadly to the Internet.

------------------------------------------------------------------------

## Requirements

The control machine needs Ansible and the AWS collection:

``` bash
ansible-galaxy collection install amazon.aws
```

The Python environment used by Ansible also needs the AWS SDK
dependencies required by the collection, such as `boto3` and `botocore`.

AWS credentials must be configured so that Ansible can create EC2
instances and Security Groups.

The SSH private key referenced by the playbook must also exist:

``` text
~/.ssh/ansible-jenkins.pem
```

------------------------------------------------------------------------

## Running the Playbook

Run:

``` bash
ansible-playbook create-jenkins-server.yaml
```

The playbook first runs locally to create the AWS resources and then
connects to the new EC2 instance to configure Jenkins.

A successful recap should contain:

``` text
failed=0
unreachable=0
```

One OS-specific include will normally be skipped because only the task
file matching the detected OS family is executed.

For example, on Ubuntu:

``` text
Install Jenkins on Ubuntu  -> included
Install Jenkins on RedHat  -> skipped
```

------------------------------------------------------------------------

## Verify Jenkins

Check the Jenkins service on the remote machine:

``` bash
sudo systemctl status jenkins
```

Check Docker:

``` bash
sudo systemctl status docker
```

Check Java:

``` bash
java -version
```

Check Docker:

``` bash
docker --version
```

Jenkins should be reachable at:

``` text
http://PUBLIC_IP:8080
```

provided that the AWS Security Group and any additional network controls
allow access.

To inspect Jenkins logs:

``` bash
sudo journalctl -u jenkins --no-pager -n 100
```

------------------------------------------------------------------------

## What This Exercise Demonstrates

This exercise introduces several useful Ansible concepts:

  Concept                           Purpose
  --------------------------------- --------------------------------------------------------
  `amazon.aws.ec2_security_group`   Creates an AWS Security Group
  `amazon.aws.ec2_instance`         Creates an EC2 instance
  `register`                        Stores a module result in a variable
  `add_host`                        Adds a dynamically created host to in-memory inventory
  `gather_facts`                    Collects information about the remote OS
  `ansible_facts["os_family"]`      Identifies the OS family
  `when`                            Executes tasks conditionally
  `include_tasks`                   Loads an OS-specific task file
  `apt`                             Manages Debian/Ubuntu packages
  `dnf`                             Manages RedHat-family packages
  `service`                         Starts and enables system services
  `user`                            Manages users and group membership

------------------------------------------------------------------------

## Key Takeaway

Instead of duplicating an entire Jenkins provisioning playbook for each
operating system, the common workflow stays in one main playbook:

``` text
Create infrastructure
        |
        v
Connect to server
        |
        v
Gather facts
        |
        v
Detect OS family
        |
        +-------- Debian --------> ubuntu.yaml
        |
        +-------- RedHat --------> redhat.yaml
```

This makes the automation easier to read, maintain, and extend with
additional operating systems later.
