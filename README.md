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