# Ansible Exercise 1 --- Build & Deploy Java Artifact

## Goal

Automate building a Java application locally and deploying the resulting
JAR artifact to a remote server with Ansible.

Requirements: - Build the Java application on the developer's local
machine. - Let the developer specify their first name as the Linux user
that runs the application. - Create that Linux user if it does not
exist. - Stop the previously running application. - Remove the old
JAR. - Copy the new JAR to the remote server. - Start the application as
the specified Linux user.

## Project structure

``` text
ansible-exercises/
├── build.gradle
├── src/
├── build/
│   └── libs/
│       └── java-app-1.0-SNAPSHOT.jar
└── ansible/
    ├── build-deploy-java-app.yaml
    ├── inventory_aws_ec2.yaml
    ├── ansible.cfg
    └── roles/
        ├── create_user/
        │   └── tasks/main.yaml
        └── install_java/
            └── tasks/main.yaml
```

`playbook_dir` is a special Ansible variable containing the directory of
the current playbook. Because the playbook is in `ansible/`,
`{{ playbook_dir }}/..` points to the Java project root.

## Build locally

``` yaml
- name: Build Java application locally
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: Build application with Gradle
      ansible.builtin.command: gradle build
      args:
        chdir: "{{ playbook_dir }}/.."
```

The artifact is built under `build/libs/`. For this project:

``` text
build/libs/java-app-1.0-SNAPSHOT.jar
```

## AWS EC2 dynamic inventory

``` yaml
plugin: amazon.aws.aws_ec2

regions:
  - eu-north-1

filters:
  instance-state-name: running
  tag:Name: "dev*"

hostnames:
  - tag:Name

compose:
  ansible_host: public_ip_address
  ansible_user: "'ubuntu'"

groups:
  app_server: true
```

Inspect inventory:

``` bash
ansible-inventory -i inventory_aws_ec2.yaml --graph
```

Test connectivity:

``` bash
ansible app_server -i inventory_aws_ec2.yaml -m ping
```

The correct SSH private key must also be configured for Ansible.

## Create the Linux user

The developer supplies the user at runtime:

``` bash
-e "linux_user=julia"
```

Role example:

``` yaml
---
- name: Create new linux user
  ansible.builtin.user:
    name: "{{ linux_user }}"
    state: present
```

`state: present` means Ansible ensures that the user exists.

## Install Java 17

The remote server used for the exercise is Ubuntu, so Java is installed
with `apt`:

``` yaml
---
- name: Install Java 17
  ansible.builtin.apt:
    name: openjdk-17-jre
    state: present
    update_cache: true
```

An earlier attempt used `dnf` and `java-17-amazon-corretto`, which is
appropriate for Amazon Linux rather than Ubuntu. Ansible facts showed
`pkg_mgr: apt`, helping identify the mismatch.

## ACL and become_user

The application must run as the specified unprivileged Linux user:

``` yaml
become_user: "{{ linux_user }}"
```

Ansible initially failed to set permissions on temporary files while
becoming this user. Installing `acl` on Ubuntu provides `setfacl` and
resolves this:

``` yaml
- name: Install ACL
  ansible.builtin.apt:
    name: acl
    state: present
```

## Deployment variables

``` yaml
vars:
  app_dir: "/home/{{ linux_user }}/app"
  jar_name: "java-app.jar"
  local_jar: "{{ playbook_dir }}/../build/libs/java-app-1.0-SNAPSHOT.jar"
```

The local Gradle artifact is copied to the server as:

``` text
/home/julia/app/java-app.jar
```

## Create application directory

``` yaml
- name: Create application directory
  ansible.builtin.file:
    path: "{{ app_dir }}"
    state: directory
    owner: "{{ linux_user }}"
    group: "{{ linux_user }}"
    mode: "0755"
```

## Stop the previous application

``` yaml
- name: Stop old application
  ansible.builtin.shell: |
    if [ -f "{{ app_dir }}/app.pid" ]; then
      kill "$(cat {{ app_dir }}/app.pid)" || true
      rm -f "{{ app_dir }}/app.pid"
    fi
  changed_when: false
  failed_when: false
```

## Remove the old JAR

``` yaml
- name: Remove old jar
  ansible.builtin.file:
    path: "{{ app_dir }}/{{ jar_name }}"
    state: absent
```

`state: absent` means Ansible ensures that the file does not exist.

## Copy the new JAR

``` yaml
- name: Copy new jar
  ansible.builtin.copy:
    src: "{{ local_jar }}"
    dest: "{{ app_dir }}/{{ jar_name }}"
    owner: "{{ linux_user }}"
    group: "{{ linux_user }}"
    mode: "0755"
```

## Start the application

``` yaml
- name: Start Java application
  become_user: "{{ linux_user }}"
  ansible.builtin.shell: |
    nohup java -jar "{{ app_dir }}/{{ jar_name }}"       > "{{ app_dir }}/app.log" 2>&1 &
    echo $! > "{{ app_dir }}/app.pid"
  args:
    chdir: "{{ app_dir }}"
```

`nohup` keeps the process running after the SSH session ends. `$!`
contains the PID of the background process and is saved in `app.pid`.

## Complete playbook

``` yaml
---
- name: Build Java application locally
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: Build application with Gradle
      ansible.builtin.command: gradle build
      args:
        chdir: "{{ playbook_dir }}/.."

- name: Deploy Java application
  hosts: app_server
  become: true

  vars:
    app_dir: "/home/{{ linux_user }}/app"
    jar_name: "java-app.jar"
    local_jar: "{{ playbook_dir }}/../build/libs/java-app-1.0-SNAPSHOT.jar"

  roles:
    - create_user
    - install_java

  tasks:
    - name: Create application directory
      ansible.builtin.file:
        path: "{{ app_dir }}"
        state: directory
        owner: "{{ linux_user }}"
        group: "{{ linux_user }}"
        mode: "0755"

    - name: Stop old application
      ansible.builtin.shell: |
        if [ -f "{{ app_dir }}/app.pid" ]; then
          kill "$(cat {{ app_dir }}/app.pid)" || true
          rm -f "{{ app_dir }}/app.pid"
        fi
      changed_when: false
      failed_when: false

    - name: Remove old jar
      ansible.builtin.file:
        path: "{{ app_dir }}/{{ jar_name }}"
        state: absent

    - name: Copy new jar
      ansible.builtin.copy:
        src: "{{ local_jar }}"
        dest: "{{ app_dir }}/{{ jar_name }}"
        owner: "{{ linux_user }}"
        group: "{{ linux_user }}"
        mode: "0755"

    - name: Start Java application
      become_user: "{{ linux_user }}"
      ansible.builtin.shell: |
        nohup java -jar "{{ app_dir }}/{{ jar_name }}"           > "{{ app_dir }}/app.log" 2>&1 &
        echo $! > "{{ app_dir }}/app.pid"
      args:
        chdir: "{{ app_dir }}"
```

## Run

``` bash
ansible-playbook   -i inventory_aws_ec2.yaml   build-deploy-java-app.yaml   -e "linux_user=julia"
```

## Verify deployment

Check the process:

``` bash
ps aux | grep java
```

Successful deployment showed the JAR running as the requested user:

``` text
julia ... java -jar /home/julia/app/java-app.jar
```

Check logs:

``` bash
sudo tail -n 50 /home/julia/app/app.log
```

Successful startup included:

``` text
Java app started
Starting ProtocolHandler ["http-nio-8080"]
Started App
```

Check port 8080:

``` bash
ss -lntp | grep 8080
```

Test HTTP:

``` bash
curl http://<SERVER_PUBLIC_IP>:8080
```

A `404 Not Found` response for `/` still confirms that the Spring Boot
web server is reachable; it only means the application has no endpoint
mapped to `/`.

## Problems encountered and lessons learned

### Java class/file naming

The build failed when `Application.java` contained `public class App`. A
public Java class must match its filename, so the source/class naming
was corrected.

### Dynamic inventory group

The playbook expected:

``` yaml
hosts: app_server
```

The dynamic inventory therefore needed to create that group:

``` yaml
groups:
  app_server: true
```

### SSH authentication

Finding an EC2 instance through dynamic inventory does not configure SSH
authentication automatically. Ansible still needs the correct SSH user
and private key.

### Ubuntu vs Amazon Linux

The Ubuntu server uses `apt`; `dnf` and `java-17-amazon-corretto` were
not suitable for it. The final Ubuntu setup uses `openjdk-17-jre`.

### Privilege escalation

Starting the application with `become_user: "{{ linux_user }}"` required
ACL support for Ansible temporary files. Installing the `acl` package
resolved the error.

## Useful Ansible special variables

-   `playbook_dir` --- directory containing the current playbook.
-   `inventory_hostname` --- current host name as known by Ansible
    inventory.
-   `groups` --- inventory groups and their hosts.
-   `group_names` --- groups to which the current host belongs.
-   `hostvars` --- variables belonging to inventory hosts.
-   `ansible_facts` --- facts gathered from the remote machine, such as
    OS, architecture and package manager.

## Result

Exercise 1 now automates the complete flow:

``` text
Build JAR locally
       ↓
Discover EC2 server
       ↓
Create Linux user
       ↓
Install Java
       ↓
Stop old application
       ↓
Remove old JAR
       ↓
Copy new JAR
       ↓
Start application as specified user
       ↓
Spring Boot running on port 8080
```

Next: **Exercise 2 --- Push Java Artifact to Nexus**.
