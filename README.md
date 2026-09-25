
# Ansible Exercise 5: Run Jenkins as a Docker Container

EXERCISE 5: Install Jenkins as a Docker Container
In addition to having different OS flavors as an option, your team also wants to be able to run Jenkins as a docker container. So you write another playbook that starts Jenkins as a Docker container with volumes for Jenkins home and Docker itself, because you want to be able to execute Docker commands inside Jenkins.

Here is a reference of a full docker command for starting Jenkins container, which you should map to Ansible playbook:

docker run --name jenkins -p 8080:8080 -p 50000:50000 -d \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /usr/local/bin/docker:/usr/bin/docker \
-v jenkins_home:/var/jenkins_home \
jenkins/jenkins:lts


Your team is happy, because they can now use Ansible to quickly spin up a Jenkins server for different needs.


## Overview

This exercise extends the previous Ansible automation by running Jenkins
inside a Docker container instead of running Jenkins directly as a
systemd service on the EC2 host.

The playbook: - creates an EC2 instance for Jenkins; - detects the Linux
OS family; - installs and starts Docker; - creates a persistent Docker
volume for Jenkins; - starts Jenkins from the `jenkins/jenkins:lts`
image; - exposes Jenkins on port `8080`; - exposes the Jenkins
inbound-agent port `50000`; - mounts the host Docker socket and Docker
CLI into the Jenkins container; - stores Jenkins data in a persistent
named volume.

## Architecture

``` text
AWS EC2
|
+-- Docker daemon
|   +-- /var/run/docker.sock
|
+-- Jenkins container
    +-- Jenkins Web UI :8080
    +-- Jenkins agent port :50000
    +-- Docker CLI
    +-- /var/jenkins_home
        +-- jenkins_home volume
```

Jenkins runs inside the container, while Docker itself runs on the EC2
host.

## Project Structure

``` text
ansible-exercises/
|-- create-jenkins-server.yaml
+-- tasks/
    |-- ubuntu.yaml
    |-- redhat.yaml
    +-- jenkins-docker.yaml
```

## Jenkins Docker Tasks

`tasks/jenkins-docker.yaml`

``` yaml
---
- name: Create Jenkins home volume
  community.docker.docker_volume:
    name: jenkins_home
    state: present

- name: Start Jenkins container
  community.docker.docker_container:
    name: jenkins
    image: jenkins/jenkins:lts
    state: started
    restart_policy: unless-stopped
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "/usr/bin/docker:/usr/bin/docker"
      - "jenkins_home:/var/jenkins_home"
```

## Docker Port Mapping

Docker uses `HOST_PORT:CONTAINER_PORT`.

``` text
EC2 :8080  ---> Jenkins container :8080
EC2 :50000 ---> Jenkins container :50000
```

Port `8080` provides access to the Jenkins Web UI. Port `50000` is
traditionally used for Jenkins inbound agents.

## Persistent Jenkins Data

The playbook creates the named volume `jenkins_home` and mounts it at:

``` text
/var/jenkins_home
```

This directory contains Jenkins configuration, jobs, plugins, users,
secrets, and other Jenkins state. The container can therefore be
replaced without automatically losing Jenkins home data.

Check volumes with:

``` bash
docker volume ls
```

## Docker Socket and Docker CLI

The mount:

``` yaml
- "/var/run/docker.sock:/var/run/docker.sock"
```

allows processes inside Jenkins to communicate with the Docker daemon on
the EC2 host.

``` text
Docker CLI
    |
    v
/var/run/docker.sock
    |
    v
Host Docker daemon
```

The Docker CLI is also mounted:

``` yaml
- "/usr/bin/docker:/usr/bin/docker"
```

Check the Docker binary path on the host with:

``` bash
which docker
```

This allows Jenkins jobs to issue Docker commands while using the host
Docker daemon.

> **Security note:** access to `/var/run/docker.sock` is highly
> privileged. Only trusted Jenkins jobs and users should receive this
> access.

## Port 8080 Conflict

During the exercise, the container initially failed with:

``` text
failed to bind host port 0.0.0.0:8080/tcp:
address already in use
```

The reason was that Jenkins was already running directly on the EC2 host
as a systemd service and was using port `8080`.

``` text
EC2
|-- Jenkins systemd service -> :8080
|
+-- Jenkins Docker container -> wants :8080
                               X conflict
```

Check which process is listening on port `8080`:

``` bash
sudo ss -ltnp | grep :8080
```

The options mean:

``` text
-l  listening sockets
-t  TCP sockets
-n  numeric ports and addresses
-p  process information
```

The pipe (`|`) passes the output to `grep`, which keeps only lines
containing `:8080`.

## Stop the Host Jenkins Service

For Exercise 5, Jenkins should run in Docker rather than simultaneously
as a host service.

Stop it now:

``` bash
sudo systemctl stop jenkins
```

Prevent automatic startup after reboot:

``` bash
sudo systemctl disable jenkins
```

`stop` stops the service now, while `disable` prevents automatic startup
at boot.

## Check the Jenkins Container

Show running containers:

``` bash
docker ps
```

Show all containers:

``` bash
docker ps -a
```

View Jenkins logs:

``` bash
docker logs jenkins
```

Follow logs:

``` bash
docker logs -f jenkins
```

## Unlock Jenkins

For the official Jenkins Docker image, Jenkins home is:

``` text
/var/jenkins_home
```

Get the initial administrator password:

``` bash
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

`docker exec` runs a command inside an already running container. Here,
`cat` prints the password file from the Jenkins container.

## Verify Docker Access from Jenkins

Check whether the Docker CLI is available:

``` bash
docker exec jenkins docker --version
```

Test access to the host Docker daemon:

``` bash
docker exec jenkins docker ps
```

If successful:

``` text
Jenkins container
      |
      | Docker CLI
      v
/var/run/docker.sock
      |
      v
Host Docker daemon
```

## Required Ansible Collection

Install the Docker collection on the Ansible control machine:

``` bash
ansible-galaxy collection install community.docker
```

The playbook uses:

``` text
community.docker.docker_volume
community.docker.docker_container
```

## Running the Playbook

Run:

``` bash
ansible-playbook create-jenkins-server.yaml
```

A successful recap should contain:

``` text
failed=0
unreachable=0
```

## Useful Commands

``` bash
sudo systemctl status docker
docker ps
docker ps -a
docker logs jenkins
docker logs -f jenkins
docker volume ls
sudo ss -ltnp | grep :8080
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
docker exec jenkins docker --version
docker exec jenkins docker ps
```

## Key Takeaway

Exercise 4 ran Jenkins directly as a service on the operating system:

``` text
EC2
+-- systemd
    +-- Jenkins
```

Exercise 5 changes the architecture:

``` text
EC2
+-- Docker daemon
    +-- Jenkins container
        |-- Jenkins home volume
        |-- Docker CLI
        +-- Docker socket
```

Running Jenkins as a container makes the Jenkins runtime reproducible
and replaceable, while the `jenkins_home` volume keeps Jenkins data
persistent. The Docker socket allows Jenkins jobs to use the host Docker
daemon, but it also grants substantial privileges and must be treated as
a sensitive security boundary.
