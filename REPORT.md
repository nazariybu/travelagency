# REPORT: Run the application in Kubernetes (Amazon EKS)

## 1. Goal

Run TravelAgency in Kubernetes: several copies (pods) of the same Docker image, self-healing, rolling updates
without downtime, automatic scaling by CPU. Created with Terraform, secrets from Vault, and cheap enough for a pet
project: the cluster lives only during a work session.

## 2. Before and after

| | Cloud stage (EC2 + Ansible) | Now (EKS) |
|--|-----------------------------|-----------|
| What runs | WAR built by Maven on every EC2, Tomcat 9 from apt | Docker image `nazariybu/travelagency:16`, built once by Jenkins |
| Copies | 2 fixed servers | 2–4 pods, HorizontalPodAutoscaler by CPU |
| A copy crashes | stays down until Ansible runs again | kubelet restarts it (liveness probe); a deleted pod is replaced |
| A server dies | ALB skips it, nothing comes back | the node group starts a new EC2, pods move after ~1 min |
| New version | Ansible restarts Tomcat on each node | rolling update (`maxUnavailable: 0`), `kubectl rollout undo` |
| Load balancer | ALB made by Terraform | NLB made by Kubernetes (Service type LoadBalancer) |
| Redis | EC2 aws-redis | pod in the cluster |
| Database | RDS MySQL 8.4 | RDS MySQL 8.4 (same code), reached by the alias `mysql` |
| Config / passwords | systemd file from Ansible | ConfigMap + Secret (values from Vault) |

## 3. Choices

| Question | Chosen | Why | Not chosen |
|----------|--------|-----|------------|
| Where | **Amazon EKS** | Managed Kubernetes as used at work; good base for Pod Security Standards and Falco | k3s at home (the Proxmox host has 7.5 GB RAM, already in swap), ECS (not Kubernetes) |
| Version | 1.36, `upgrade_policy = STANDARD` | Standard support until 08.2027; never pay Extended Support (0.60 instead of 0.10 USD/hour) | 1.37 (newest, fewer add-on versions tested), older versions |
| Terraform | plain resources in `envs/eks` (own state) | Every part visible: roles, cluster, node group | `terraform-aws-modules/eks` (shorter, but hides a lot) |
| Nodes | managed node group, 2 × Spot `t3.medium`/`t3a.medium`/`t2.medium`, AL2023 | ~65 % cheaper; 3 types = more Spot capacity; EKS updates the nodes | On-Demand (0.05 USD/hour more), Fargate (no DaemonSets: Falco would not work), EKS Auto Mode (extra fee per node) |
| Network | public subnets, no NAT, API public only for the home IP + private for the nodes | NAT costs ~35 USD/month | private nodes + NAT gateway (better isolation) |
| Who may use kubectl | EKS access entries, `bootstrap_cluster_creator_admin_permissions` | The IAM user that creates the cluster is admin; no aws-auth ConfigMap | aws-auth ConfigMap (old way) |
| Way in | Service type LoadBalancer with NLB, `loadBalancerSourceRanges` = home IP | Nothing extra to install | Ingress + AWS Load Balancer Controller (Helm + IAM role: next step) |
| Database | RDS, outside the cluster, alias `mysql` (ExternalName) written by Terraform | Data must survive the pods; the app does not need the long RDS name | MySQL StatefulSet with EBS volumes (needs the EBS CSI driver + IAM) |
| Redis | one pod, no disk | Only sessions: losing them = log in again | ElastiCache (needs TLS, the app has no TLS) |
| Data | fresh database: Flyway V1 + V2 (seed users and hotels) | The cluster is re-created every session | `mysqldump` from vm-db (possible, as in the Cloud stage) |
| App secrets | `kubectl create secret` with values from `vault kv get` | Not in Git, not in the Terraform state, not on the screen | External Secrets Operator (Vault → Kubernetes sync: next step) |
| Terraform user rights | inline policy: `eks:*`, IAM only for roles `travelagency-*` | Least rights that work | AdministratorAccess |

## 4. Security notes

- Pods run as non-root (10001 app, 999 Redis), `allowPrivilegeEscalation: false`, all capabilities dropped,
  seccomp `RuntimeDefault`: ready for the **restricted** Pod Security Standard (next stage).
- The Kubernetes API is reachable from the internet only from the home IP; nodes use the private endpoint.
- The site (NLB) is open only for the home IP unless `site_open_to_world = true`.
- RDS has no public address; port 3306 only from the cluster security group.
- AWS key: in Vault; Terraform reads it as `ephemeral`; the shell gets it with `source aws-env.sh` (memory only).
- Not yet: NetworkPolicies, TLS, a less powerful kubectl user than the cluster admin, encryption of Secrets with KMS.

## 5. Results

Run on: 2026-11-04, EKS 1.36, 2 Spot nodes (zones a and b), RDS MySQL 8.4, image `nazariybu/travelagency:16`.

| Check | Result |
|-------|--------|
| `terraform apply` | ✅ 22 resources (after the IAM fix in section 6, the node group was created on the second run) |
| `kubectl get nodes` | ✅ 2 × `Ready`, `SPOT`, `ip-10-30-1-20` (zone a) and `ip-10-30-2-147` (zone b) |
| Pods | ✅ 2 app pods (one per node) + 1 Redis pod `Running` |
| Network pod → RDS | ✅ `nc -zv mysql 3306` → `mysql (10.30.11.83:3306) open` (ExternalName alias works) |
| Site through the NLB | ✅ sign up on `/create`, log in, hotel list |
| `kubectl delete pod` | ✅ new pod Ready after ~__ s, curl loop: only 200 |
| `rollout restart` while logged in | ✅ still logged in (session in Redis) |
| `set image ...:15` → `rollout undo` | ✅ back to `:16`, no downtime |
| EC2 node terminated in the console | ✅ EKS started a new node after ~__ min, site kept working |
| HPA under k6 (`TEST_TYPE=load`, `VUS=30`, 10 min, run from vm-agent) | ✅ 2 → 4 pods (CPU 182–217 % of the request); 0 % errors, 356 bookings, ~5.2 req/s, p95 18.96 s (see below) | |

### Load test (k6, testid `load-20261104-2025`)

| | Home, 2 LXC nodes (`load-20261103-1000`) | EKS, 2 → 4 pods |
|--|------------------------------------------|-----------------|
| Errors | 0 % | 0 % (`http_req_failed` 0 of 3417, all 2864 checks passed) |
| Requests per second | ~9 | ~5.2 |
| Bookings in 10 min | 516 | 356 |
| p95 all requests | ~8–10 s | 18.96 s (median 0.93 s) |
| p95 login / search / book | | 14.99 s / 24.34 s / 19.74 s |
| Thresholds | | `checks`, `http_req_failed`, `bookings_failed` ✅; all `p(95)` ❌ |

What it shows:
- **Kubernetes did its job**: the HPA saw CPU at 182–217 % of the request (250m) and went from 2 to 4 pods
  within about a minute; no request failed, also while new pods were starting.
- **More pods did not make it faster.** The median stayed under 1 s, but the slow tail grew. The likely bottleneck
  is not Tomcat but the database (not measured in this stage): the same problems as in the k6 stage
  (~300 SQL queries per request because of `FetchType.EAGER`, a new MySQL connection per request because
  `DriverManagerDataSource` has no pool), now against `db.t4g.micro` (the smallest RDS, burstable CPU, 1 GB RAM)
  over the network. 4 pods = more parallel queries to the same small database.
- Other differences to home: Spot `t3.medium` nodes are burstable too, and k6 ran from home to Frankfurt
  (extra network time on every request).
- Next fix is in the code, not in Kubernetes: a connection pool (HikariCP), `LAZY` fetching, and turning off
  `hibernate.show_sql`. Then the same test shows what more pods really give.

## 6. Problems found

| Problem | Cause | Fix |
|---------|-------|-----|
| `CreateNodegroup ... missing permissions for 'iam:GetRole'` (the cluster was already created) | Before it creates a node group, EKS checks whether the service-linked role `AWSServiceRoleForAmazonEKSNodegroup` exists. The policy allowed `iam:GetRole` only for `role/travelagency-*`; a role that does not exist yet has no `aws-service-role/` path, so `role/aws-service-role/*` did not match either | Statement `CheckServiceLinkedRoles`: `iam:GetRole` on `arn:aws:iam::*:role/*` (read only). `terraform apply` again: only the missing resources were created |
| App pods `0/1 Running`, killed after 3 min by the startup probe, then `404` | Kubernetes gives every pod "service link" variables for each Service, e.g. `REDIS_PORT=tcp://172.20.140.58:6379`. Spring resolves `${redis.port}` also from the env variable `REDIS_PORT`, which wins over `application.properties` → `NumberFormatException`, the web app did not start (Tomcat itself did, hence 404) | `enableServiceLinks: false` in the pod spec (`k8s/20-deployment.yaml`). Lesson: do not name settings like `<service>.port` / `<service>.host`, or switch the links off |
| Seed users (`michael.scott` ...) cannot log in on a fresh database | `V2__seed_data.sql` stores plain-text passwords, the app compares with bcrypt hashes | Sign up a new user on `/create`. (A later migration could store bcrypt hashes for the seed users) |
| `run-k6.sh: docker: command not found` on the ansible host | The script runs k6 in Docker; the ansible host has no Docker | Copied `k6/` to vm-agent and ran it there (same home public IP, so the NLB lets it in) |
| Fresh database has no rooms for the k6 booking flow | Seed has hotels only | `k6/seed-rooms.sql` through a temporary `mysql:8.4` pod (`kubectl run --rm -i ... < seed-rooms.sql`): RDS is reachable only from the cluster |
| Home lab too small for Kubernetes | Proxmox host has 7.5 GB RAM, already ~6 GB in swap | Moved the stage to EKS; the k3s-on-Proxmox design stays as an option for more RAM |
