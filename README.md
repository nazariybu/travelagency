# Jenkins Setup for Travel Agency

![Jenkins](https://img.shields.io/badge/Jenkins-LTS-D24939?logo=jenkins&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-2.15%2B-EE0000?logo=ansible&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-LXC-E57000?logo=proxmox&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-agent-2496ED?logo=docker&logoColor=white)



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
10. [Useful commands](#7-useful-commands)
11. [Common problems](#8-common-problems)
12. [Next steps](#9-next-steps)

---

## Servers

| Name | CT ID | IP | CPU / RAM / Disk | What runs there |
|------|-------|----|------------------|-----------------|
| **vm-jenkins** | 303 | `192.168.18.103` | 1 / 2 GB / 16 GB | Docker, Jenkins controller |
| **vm-agent** | 304 | `192.168.18.104` | 4 / 4 GB / 32 GB | Docker, Java 17, Ansible |

Both are Ubuntu 22.04 LXC containers on Proxmox (`192.168.18.200`).

## How it works

```mermaid
flowchart LR
    PC["Ansible PC"]
    GH["GitHub"]

    subgraph PVE["Proxmox 192.168.18.200"]
        J["vm-jenkins (CT 303)<br/>Jenkins in Docker<br/>:8080"]
        AG["vm-agent (CT 304)<br/>Docker + Java 17 + Ansible"]
        APP["vm-app (CT 301)"]
        DB[("vm-db (CT 302)")]
        J -->|"SSH :22"| AG
        AG -->|"deploy (SSH)"| APP
        AG -->|"deploy (SSH)"| DB
    end

    PC -->|"provision.yml"| PVE
    PC -->|"jenkins.yml"| J
    PC -->|"jenkins.yml"| AG
    GH -.->|"webhook (next step)"| J
```

- **Controller** (`vm-jenkins`) only manages jobs. It does not build anything.
- **Agent** (`vm-agent`) runs all jobs. It builds the code inside Docker containers
  and can deploy the app with Ansible.

## Progress

| Step | Status |
|------|--------|
| Containers `vm-jenkins`, `vm-agent` created | ✅ Done |
| Jenkins controller running in Docker | ✅ Done |
| Agent connected over SSH | ✅ Done |
| Test pipeline (Java, Ansible, Docker, Maven) | ✅ Green |
| `Jenkinsfile` for the app | ⏳ Next |
| GitHub webhook | ⏳ Next |

---

## 1. Before you start

You need the Ansible setup from the `ansible` branch: Ansible 2.15+, `proxmoxer` 2.3+,
the `.env` file with secrets, and the containers `vm-app` and `vm-db`.

Files used in this guide:

| File | What it does |
|------|--------------|
| `ansible/provision.yml` | Creates the containers in Proxmox. |
| `ansible/inventory.ini` | Groups `jenkins` and `jenkins_agent`. |
| `ansible/jenkins.yml` | Installs Docker, runs Jenkins, prepares the agent. |
| `ansible/group_vars/all.yml` | Jenkins settings (image, port, agent user). |
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

```bash
ansible-playbook jenkins.yml
```

| Play | Server | What it does |
|------|--------|--------------|
| 1 | vm-jenkins, vm-agent | Installs Docker and starts it. |
| 2 | vm-jenkins | Runs `jenkins/jenkins:lts-jdk17` on port 8080. Data is kept in the `jenkins_home` volume. Prints the first admin password. |
| 3 | vm-agent | Installs Java 17 and Git. Installs `ansible-core` and `proxmoxer` with pip. Creates the user `jenkins` in the `docker` group. Adds the key `~/.ssh/jenkins_agent.pub`. Installs Ansible collections. |
| 4 | vm-app, vm-db | Adds the agent's SSH key to `root`, so Jenkins can deploy. |

At the end you will see:

```
Open http://192.168.18.103:8080  password: 1a2b3c...
```

---

## 4. First start wizard

1. Open **http://192.168.18.103:8080** and enter the password.
2. Choose **Install suggested plugins**.
3. Create the admin user.
4. **Jenkins URL:** keep `http://192.168.18.103:8080/` for now.
   Later change it to the public tunnel address
   (**Manage Jenkins → System → Jenkins Location**).
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

## 7. Useful commands

| Task | Command |
|------|---------|
| Jenkins logs | `ssh root@192.168.18.103 docker logs -f jenkins` |
| Restart Jenkins | `ssh root@192.168.18.103 docker restart jenkins` |
| First admin password | `ssh root@192.168.18.103 docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` |
| Log in to the agent as jenkins | `ssh -i ~/.ssh/jenkins_agent jenkins@192.168.18.104` |
| Docker on the agent | `ssh root@192.168.18.104 docker ps -a` |
| Run only the agent part | `ansible-playbook jenkins.yml --limit jenkins_agent` |

---

## 8. Common problems

| Error | Why | Fix |
|-------|-----|-----|
| `gnupg ... do not seem to be installed` | The minimal LXC template has no `gnupg`, so the Ansible PPA cannot be added. | Ansible on the agent is installed with pip. No PPA needed. |
| `keyserver receive failed` | The Ubuntu keyserver did not answer. | Same fix: install `ansible-core` with pip. |
| `PEM problem: it is of unknown type` | The key in Jenkins is pasted wrong, or it is the `.pub` key. | Paste the full private key again (section 5.2). |
| `Server rejected the private key` | Wrong username or key. | Username must be `jenkins`. Test with `ssh -i ~/.ssh/jenkins_agent jenkins@192.168.18.104`. |
| Docker does not start in a container | No `nesting` feature. | On Proxmox: `pct set 304 --features nesting=1`, then restart the container. |
| `permission denied ... docker.sock` in a job | The `jenkins` user is not in the `docker` group yet. | Relaunch the agent in Jenkins (or restart the container). |
| Job waits forever: `There are no nodes with the label` | Wrong label or the agent is offline. | Use `agent { label 'docker' }` and check the node is online. |

---

## 9. Next steps

1. **Jenkinsfile**: add a pipeline to the repo: Checkout → Build → Test → Archive WAR → Deploy with `app.yml`.
2. **Deploy secrets**: add `DB_PASSWORD` to Jenkins Credentials (Secret text).
3. **GitHub webhook**: the servers have private IPs, so GitHub cannot reach Jenkins directly.
   Use a tunnel (Cloudflare Tunnel, ngrok or smee.io) and add the webhook
   `https://<tunnel>/github-webhook/` in GitHub (event: push).
