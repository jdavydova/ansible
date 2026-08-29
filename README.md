# Ansible Exercise 2 --- Push Java Artifact to Nexus

## Exercise Goal

Developers test the Java application locally and then push the
successful JAR artifact to the team's Nexus repository.

The Ansible playbook: 1. Accepts the JAR path as an extra variable. 2.
Checks that the JAR exists. 3. Fails if the file does not exist. 4.
Uploads the artifact to Nexus.

## Prerequisites

-   Ansible
-   curl
-   Nexus Repository Manager
-   Maven hosted snapshot repository
-   Built Java JAR

Artifact used:

``` text
../build/libs/java-app-1.0-SNAPSHOT.jar
```

Nexus:

``` text
http://localhost:8081
```

## Nexus Repository Configuration

Because the artifact version is `1.0-SNAPSHOT`, it is uploaded to
`maven-snapshots`.

``` text
Name:               maven-snapshots
Format:             maven2
Type:               hosted
Version policy:     Snapshot
Layout policy:      Strict
Deployment policy:  Allow redeploy
Blob store:         default
```

`maven-releases` is for release versions such as `1.0.0`;
`maven-snapshots` is for versions such as `1.0-SNAPSHOT`.

## Nexus Credentials

Credentials are provided through environment variables instead of being
hardcoded:

``` bash
export NEXUS_USER=admin
export NEXUS_PASSWORD='your-real-nexus-password'
```

The playbook reads them with:

``` yaml
nexus_user: "{{ lookup('env', 'NEXUS_USER') }}"
nexus_password: "{{ lookup('env', 'NEXUS_PASSWORD') }}"
```

## Maven Artifact Path

Maven repositories expect:

``` text
groupId/artifactId/version/artifactId-version.jar
```

For this exercise:

``` text
groupId:     com.example
artifactId:  java-app
version:     1.0-SNAPSHOT
```

`com.example` is converted to `com/example`:

``` yaml
group_path: "{{ group_id | replace('.', '/') }}"
```

Final path:

``` text
com/example/java-app/1.0-SNAPSHOT/java-app-1.0-SNAPSHOT.jar
```

Final URL:

``` text
http://localhost:8081/repository/maven-snapshots/com/example/java-app/1.0-SNAPSHOT/java-app-1.0-SNAPSHOT.jar
```

## Playbook

`push-artifact-to-nexus.yaml`:

``` yaml
---
- name: Push Java artifact to Nexus
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    nexus_url: "http://localhost:8081"
    path_repository: "maven-snapshots"

    group_id: "com.example"
    artifact_id: "java-app"
    version: "1.0-SNAPSHOT"

    nexus_user: "{{ lookup('env', 'NEXUS_USER') }}"
    nexus_password: "{{ lookup('env', 'NEXUS_PASSWORD') }}"

    group_path: "{{ group_id | replace('.', '/') }}"
    artifact_name: "{{ jar_file | basename }}"

  tasks:
    - name: Check that jar file exists
      ansible.builtin.stat:
        path: "{{ jar_file }}"
      register: jar_file_info

    - name: Fail if jar file does not exist
      ansible.builtin.fail:
        msg: "Jar file {{ jar_file }} does not exist"
      when: not jar_file_info.stat.exists

    - name: Push jar to Nexus
      ansible.builtin.command:
        argv:
          - curl
          - --fail
          - --silent
          - --show-error
          - --user
          - "{{ nexus_user }}:{{ nexus_password }}"
          - --upload-file
          - "{{ jar_file }}"
          - "{{ nexus_url }}/repository/{{ path_repository }}/{{ group_path }}/{{ artifact_id }}/{{ version }}/{{ artifact_name }}"
      register: response
      no_log: true

    - name: Print response
      ansible.builtin.debug:
        msg: "Artifact {{ artifact_name }} successfully uploaded to Nexus"
      when: response.rc == 0
```

## Run the Playbook

``` bash
ansible-playbook push-artifact-to-nexus.yaml \
  -e "jar_file=../build/libs/java-app-1.0-SNAPSHOT.jar"
```

Because the play runs on `localhost`, a remote inventory is not
required. The warning about only implicit localhost being available is
expected for this local-only playbook.

## How It Works

### Check the JAR

`ansible.builtin.stat` checks whether the local file exists and saves
the result in `jar_file_info`.

### Fail if Missing

The `fail` task stops the playbook when:

``` yaml
when: not jar_file_info.stat.exists
```

### Upload with curl

The working implementation uses:

``` text
--fail        fail on HTTP errors
--silent      hide the progress bar
--show-error  show errors even in silent mode
--user        provide Nexus credentials
--upload-file upload the JAR
```

`no_log: true` prevents credentials from appearing in Ansible output.

## Troubleshooting

### 403 --- EULA Not Accepted

The first Nexus upload returned:

``` text
403 Forbidden
You must accept the End User License Agreement (EULA)
```

The Nexus onboarding wizard and EULA had to be completed first.

### 400 --- Invalid Maven Path

Uploading the JAR directly to the repository root returned:

``` text
400 Invalid mavenPath for a Maven 2 repository
```

The solution was to use the Maven directory structure:

``` text
groupId/artifactId/version/artifactId-version.jar
```

### Snapshot vs Release

`java-app-1.0-SNAPSHOT.jar` belongs in `maven-snapshots`, not
`maven-releases`.

### Repository Name Typo

The correct repository variable is:

``` yaml
path_repository: "maven-snapshots"
```

Using `maven-snapshot` without the final `s` causes the request to
target a repository that does not exist.

### ansible.builtin.uri --- Broken Pipe

An initial implementation used:

``` yaml
ansible.builtin.uri:
  method: PUT
  src: "{{ jar_file }}"
```

but failed locally with:

``` text
<urlopen error [Errno 32] Broken pipe>
```

The same artifact, URL and credentials worked with `curl`, returning:

``` text
HTTP/1.1 201 Created
```

For this environment, the final playbook therefore uses `curl` through
`ansible.builtin.command`.

## Manual Nexus Test

``` bash
curl -v \
  -u "$NEXUS_USER:$NEXUS_PASSWORD" \
  --upload-file ../build/libs/java-app-1.0-SNAPSHOT.jar \
  http://localhost:8081/repository/maven-snapshots/com/example/java-app/1.0-SNAPSHOT/java-app-1.0-SNAPSHOT.jar
```

Successful result:

``` text
HTTP/1.1 201 Created
```

Do not share verbose curl output publicly when it contains
authentication headers.

## Result

``` text
Developer provides JAR path
        |
        v
Ansible checks JAR
        |
        v
Build Maven artifact path
        |
        v
curl uploads JAR
        |
        v
Nexus maven-snapshots
```

The developer only needs to provide the JAR path; the playbook validates
it and uploads the artifact to Nexus.
