# Jenkins Setup for Travel Agency

![Jenkins](https://img.shields.io/badge/Jenkins-LTS-D24939?logo=jenkins&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-2.15%2B-EE0000?logo=ansible&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-LXC-E57000?logo=proxmox&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-agent-2496ED?logo=docker&logoColor=white)
![GitHub](https://img.shields.io/badge/GitHub-webhook-181717?logo=github&logoColor=white)

This guide shows how to set up Jenkins with a separate build agent in Proxmox LXC containers.
Every `git push` starts a pipeline: build and test in Docker, save the WAR file, deploy with Ansible.

## Contents

1. [Servers](#servers)
2. [How it works](#how-it-works)
3. [Progress](#progress)
4. [Before you start](#1-before-you-start)
5. [Create the containers](#2-create-the-containers)
6. [Install Jenkins](#3-install-jenkins)
7. [First start wizard](#4-first-start-wizard)
8. [Connect the agent](#5-connect-the-agent)
9. [Test the agent](#6-test-the-agent)
10. [The pipeline (Jenkinsfile)](#7-the-pipeline-jenkinsfile)
11. [GitHub webhook](#8-github-webhook)
12. [Useful commands](#9-useful-commands)
13. [Common problems](#10-common-problems)
14. [Next steps](#11-next-steps)

---

## Servers

| Name | CT ID | IP | CPU / RAM / Disk | What runs there |
|------|-------|----|------------------|-----------------|
| **vm-jenkins** | 303 | `192.168.18.103` | 1 / 2 GB / 16 GB | Docker, Jenkins controller, smee client |
| **vm-agent** | 304 | `192.168.18.104` | 4 / 4 GB / 32 GB | Docker, Java 17, Ansible |
| vm-app | 301 | `192.168.18.101` | 1 / 2 GB / 8 GB | Tomcat 9, the app (deploy target) |
| vm-db | 302 | `192.168.18.102` | 1 / 2 GB / 8 GB | MySQL (deploy target) |

All are Ubuntu 22.04 LXC containers on Proxmox (`192.168.18.200`).

## How it works

```mermaid
flowchart LR
    DEV["Developer"]
    GH["GitHub"]
    SMEE["smee.io"]

    subgraph PVE["Proxmox 192.168.18.200"]
        subgraph JH["vm-jenkins (CT 303)"]
            SC["smee client"]
            J["Jenkins :8080"]
        end
        AG["vm-agent (CT 304)<br/>Docker + Ansible"]
        APP["vm-app (CT 301)<br/>Tomcat"]
        DB[("vm-db (CT 302)<br/>MySQL")]
        SC -->|"POST /github-webhook/"| J
        J -->|"SSH :22"| AG
        AG -->|"ansible-playbook app.yml"| APP
        AG -->|"ansible-playbook app.yml"| DB
    end

    DEV -->|"git push"| GH
    GH -->|"webhook"| SMEE
    SC -->|"listens (outgoing)"| SMEE
```

1. You push code to GitHub.
2. GitHub sends a webhook to **smee.io**.
3. The **smee client** on `vm-jenkins` gets it and passes it to Jenkins.
   It uses only an outgoing connection, so Jenkins stays closed to the internet.
4. Jenkins sends the job to **vm-agent**. The controller does not build anything itself.
5. The agent builds and tests the code in a Maven Docker container, saves the WAR,
   and deploys it to `vm-app` with Ansible.

## Progress

| Step | Status |
|------|--------|
| Containers `vm-jenkins`, `vm-agent` created | ✅ Done |
| Jenkins controller running in Docker | ✅ Done |
| Agent connected over SSH | ✅ Done |
| Test pipeline (Java, Ansible, Docker, Maven) | ✅ Done |
| `Jenkinsfile`: build, test, archive, deploy | ✅ Done |
| Multibranch job with GitHub token | ✅ Done |
| GitHub webhook through smee.io | ✅ Done |

---

## 1. Before you start

You need the Ansible setup from the `ansible` branch: Ansible 2.15+, `proxmoxer` 2.3+,
the `.env` file with secrets, and the containers `vm-app` and `vm-db`.

Files used in this guide:

| File | What it does |
|------|--------------|
| `Jenkinsfile` | The pipeline: build, test, archive, deploy. |
| `ansible/provision.yml` | Creates the containers in Proxmox. |
| `ansible/inventory.ini` | Groups `jenkins` and `jenkins_agent`. |
| `ansible/jenkins.yml` | Installs Docker, runs Jenkins and the smee client, prepares the agent. |
| `ansible/app.yml` | Deploys the app. Can take a ready WAR from Jenkins (`-e war_file=...`). |
| `ansible/group_vars/all.yml` | Jenkins settings (image, port, agent user, smee URL). |
| `ansible/requirements.yml` | Adds `community.docker` and `ansible.posix`. |

Install the collections and load the secrets:

```bash
cd travelagency/ansible
ansible-galaxy collection install -r requirements.yml
set -a; source .env; set +a
```

Make a key for the agent (once). Jenkins uses it to log in to `vm-agent`:

```bash
ssh-keygen -t ed25519 -N "" -C "jenkins-controller" -f ~/.ssh/jenkins_agent
```

---

## 2. Create the containers

`provision.yml` has two new containers:

```yaml
- { vmid: 303, name: vm-jenkins, ip: 192.168.18.103, cores: 1, memory: 2048, disk: 16, features: [nesting=1] }
- { vmid: 304, name: vm-agent,   ip: 192.168.18.104, cores: 4, memory: 4096, disk: 32, features: [nesting=1] }
```

> `nesting=1` is needed to run Docker inside an LXC container.

`inventory.ini` has two new groups:

```ini
[jenkins]
vm-jenkins ansible_host=192.168.18.103

[jenkins_agent]
vm-agent ansible_host=192.168.18.104
```

Run:

```bash
ansible-playbook provision.yml
ansible jenkins:jenkins_agent -m ping
```

You should see `"ping": "pong"` for both.

---

## 3. Install Jenkins

First make a smee channel: open **https://smee.io** → **Start a new channel** and copy the URL.
Put it in `group_vars/all.yml`:

```yaml
# --- Jenkins ---
jenkins_image: jenkins/jenkins:lts-jdk17
jenkins_port: 8080
jenkins_agent_user: jenkins
jenkins_agent_home: /home/jenkins
smee_url: https://smee.io/your-channel
```

Then run:

```bash
ansible-playbook jenkins.yml
```

| Play | Server | What it does |
|------|--------|--------------|
| 1 | vm-jenkins, vm-agent | Installs Docker and starts it. |
| 2 | vm-jenkins | Runs `jenkins/jenkins:lts-jdk17` on port 8080 (data in the `jenkins_home` volume). Runs the smee client. Prints the first admin password. |
| 3 | vm-agent | Installs Java 17 and Git. Installs `ansible-core` and `proxmoxer` with pip. Creates the user `jenkins` in the `docker` group. Adds the key `~/.ssh/jenkins_agent.pub`. Installs Ansible collections. |
| 4 | vm-app, vm-db | Adds the agent's SSH key to `root`, so Jenkins can deploy. |

At the end you will see:

```
Open http://192.168.18.103:8080  password: 1a2b3c...
```

Make the Maven cache folder on the agent (once):

```bash
ansible jenkins_agent -b -a "install -d -o jenkins -g jenkins /home/jenkins/.m2"
```

---

## 4. First start wizard

1. Open **http://192.168.18.103:8080** and enter the password.
2. Choose **Install suggested plugins**.
3. Create the admin user.
4. **Jenkins URL:** keep `http://192.168.18.103:8080/`.
5. Install extra plugins in **Manage Jenkins → Plugins → Available**:
   - **SSH Build Agents**
   - **Docker Pipeline**

---

## 5. Connect the agent

### 5.1 Check the agent

```bash
ansible jenkins_agent -a "java -version"
ansible jenkins_agent -a "ansible --version"
ansible jenkins_agent -b -a "su - jenkins -c 'docker ps'"
ssh -i ~/.ssh/jenkins_agent jenkins@192.168.18.104 "echo OK"
```

All four must work. The last one must print `OK`.

### 5.2 Add the SSH key to Jenkins

**Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

| Field | Value |
|-------|-------|
| Kind | SSH Username with private key |
| ID | `jenkins-agent-ssh` |
| Username | `jenkins` |
| Private Key | **Enter directly**, paste the full output of `cat ~/.ssh/jenkins_agent` |

> Paste the **private** key: 7 lines, from `-----BEGIN OPENSSH PRIVATE KEY-----`
> to `-----END OPENSSH PRIVATE KEY-----`. Not the `.pub` file.

### 5.3 Add the node

**Manage Jenkins → Nodes → New Node** → name `vm-agent` → **Permanent Agent**

| Field | Value |
|-------|-------|
| Number of executors | `2` |
| Remote root directory | `/home/jenkins/agent` |
| Labels | `docker ansible` |
| Usage | Only build jobs with label expressions matching this node |
| Launch method | Launch agents via SSH |
| Host | `192.168.18.104` |
| Credentials | `jenkins-agent-ssh` |
| Host Key Verification Strategy | Non verifying Verification Strategy |

### 5.4 Turn off builds on the controller

**Manage Jenkins → Nodes → Built-In Node → Configure** → Number of executors: `0`.

### 5.5 Check

In **Manage Jenkins → Nodes**, `vm-agent` must be online (no red cross).
The agent log must end with:

```
Agent successfully connected and online
```

---

## 6. Test the agent

**New Item** → `agent-test` → **Pipeline** → paste the script → **Build Now**.

```groovy
pipeline {
    agent { label 'docker' }
    stages {
        stage('Check agent') {
            steps {
                sh 'hostname && java -version && ansible --version && docker ps'
            }
        }
        stage('Maven in Docker') {
            agent {
                docker { image 'maven:3.9-eclipse-temurin-17'; reuseNode true }
            }
            steps {
                sh 'mvn -v'
            }
        }
    }
}
```

The build must be green. The Console Output shows `vm-agent` and the versions of Java, Ansible and Maven.

---

## 7. The pipeline (Jenkinsfile)

### 7.1 Stages

| Stage | Where | What it does |
|-------|-------|--------------|
| **Build & Test** | Maven Docker container on vm-agent | `mvn clean package`: builds the code and runs the tests. |
| **Archive** | vm-agent | Saves `target/TravelAgency.war` in Jenkins. You can download it from the build page. |
| **Deploy** | vm-agent | Runs `ansible-playbook app.yml -e war_file=...`. Only for the `jenkins` branch. |

Notes:

- The Maven cache is kept in `/home/jenkins/.m2` on the agent, so the next builds are fast.
- The WAR is built **once** in Jenkins. Ansible only copies it to `vm-app`,
  so the server gets the same file that passed the tests.
- Without `war_file`, `app.yml` works as before (git clone and Maven on `vm-app`).
  So you can still deploy by hand from your PC.

### 7.2 Add the database password

**Manage Jenkins → Credentials → Global → Add Credentials**

| Field | Value |
|-------|-------|
| Kind | Secret text |
| ID | `db-password` |
| Secret | the `DB_PASSWORD` value from your `.env` |

The pipeline gives it to Ansible as the `DB_PASSWORD` variable. Jenkins hides it in the logs.

### 7.3 Add a GitHub token

Without a token, Jenkins can make only 60 GitHub API requests per hour and has to wait.

1. GitHub → **Settings → Developer settings → Personal access tokens → Tokens (classic)**
   → **Generate new token**. Scopes: `repo`, `admin:repo_hook`. Copy the token.
2. Jenkins → **Manage Jenkins → Credentials → Global → Add Credentials**:

| Field | Value |
|-------|-------|
| Kind | Username with password |
| Username | your GitHub user name |
| Password | the token |
| ID | `github-token` |

> Use **Username with password**, not Secret text. The GitHub branch source does not show Secret text.

### 7.4 Create the job

**New Item** → `travelagency` → **Multibranch Pipeline**

| Field | Value |
|-------|-------|
| Branch Sources | GitHub |
| Credentials | `github-token` (click **Validate**, it must say "Credentials ok") |
| Repository HTTPS URL | `https://github.com/nazariybu/travelagency` |

Save. Jenkins scans all branches and makes a job for each branch that has a `Jenkinsfile`.
The scan log must show:

```
Checking branch jenkins
  'Jenkinsfile' found
Met criteria
```

Branches without a `Jenkinsfile` (`main`, `ansible`, `docker`) show "not found". This is normal.

---

## 8. GitHub webhook

The servers have private IPs, so GitHub cannot reach Jenkins directly.
**smee.io** solves this: GitHub sends the webhook to smee.io, and the smee client
on `vm-jenkins` pulls it and passes it to Jenkins.

### 8.1 smee client

It is started by `jenkins.yml` (Play 2):

```yaml
- name: Run smee client (forwards GitHub webhooks to Jenkins)
  community.docker.docker_container:
    name: smee
    image: node:20-alpine
    state: started
    restart_policy: unless-stopped
    network_mode: host          # so localhost:8080 is Jenkins
    command: >
      npx --yes smee-client@2
      --url {{ smee_url }}
      --target http://localhost:{{ jenkins_port }}/github-webhook/
```

> Keep `smee-client@2`. Version 5 removes the last `/` from the target.
> Jenkins then answers with a redirect, and the webhook fails with `405`.

Check:

```bash
ssh root@192.168.18.103 docker logs smee
```

You should see `Connected https://smee.io/...`.

### 8.2 Add the webhook in GitHub

Repository → **Settings → Webhooks → Add webhook**

| Field | Value |
|-------|-------|
| Payload URL | your smee URL (`https://smee.io/your-channel`) |
| Content type | `application/json` |
| Which events | Just the push event |
| Active | ✅ |

### 8.3 Check

Push a small change to the `jenkins` branch. Then:

1. The smee channel page shows a `push` event.
2. `docker logs smee` shows `POST http://localhost:8080/github-webhook/ - 200`.
3. Jenkins starts a new build of the `jenkins` branch in a few seconds.

---

## 9. Useful commands

| Task | Command |
|------|---------|
| Jenkins logs | `ssh root@192.168.18.103 docker logs -f jenkins` |
| Restart Jenkins | `ssh root@192.168.18.103 docker restart jenkins` |
| smee client logs | `ssh root@192.168.18.103 docker logs --tail 20 smee` |
| First admin password | `ssh root@192.168.18.103 docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` |
| Log in to the agent as jenkins | `ssh -i ~/.ssh/jenkins_agent jenkins@192.168.18.104` |
| Docker on the agent | `ssh root@192.168.18.104 docker ps -a` |
| Run only the Jenkins server part | `ansible-playbook jenkins.yml --limit jenkins` |
| Run only the agent part | `ansible-playbook jenkins.yml --limit jenkins_agent` |
| Deploy a ready WAR by hand | `ansible-playbook app.yml -e war_file=/path/to/TravelAgency.war` |


