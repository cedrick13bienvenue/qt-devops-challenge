# QT DevOps Practical Challenge — ProjectHub

Provisioning, containerising, orchestrating and monitoring a 3-tier web application on Proxmox:
Terraform creates 4 VMs, Docker Compose runs the app on one of them, Ansible builds a 3-node
Kubernetes cluster on the others, and the same images are deployed to that cluster.

**Author:** Cedric Bienvenue

---

## Submission summary

### Working URLs

| Deployment | URL |
|---|---|
| Docker Compose | **http://192.168.160.210** |
| Kubernetes (NodePort) | **http://192.168.160.211:30080** (also answers on `.212:30080` and `.213:30080`) |
| Kubernetes through the Gateway API (bonus) | **http://192.168.160.211:30090** (also `.212:30090` and `.213:30090`) |

Test accounts (created automatically on first start):

| Role | Email | Password |
|---|---|---|
| admin | `admin@qt.rw` | `Admin@123` |
| manager | `manager@qt.rw` | `Manager@123` |
| member | `member@qt.rw` | `Member@123` |

### Virtual machines

| Name | Role | VMID | IP | vCPU / RAM / Disk |
|---|---|---|---|---|
| c3-docker-host | Docker Compose host | 4101 | 192.168.160.210 | 4 / 4 GB / 30 GB |
| c3-k8s-master | Kubernetes control plane | 4102 | 192.168.160.211 | 4 / 4 GB / 30 GB |
| c3-k8s-worker-1 | Kubernetes worker | 4103 | 192.168.160.212 | 4 / 4 GB / 30 GB |
| c3-k8s-worker-2 | Kubernetes worker | 4104 | 192.168.160.213 | 4 / 4 GB / 30 GB |

- **SSH username:** `cedrick-bienvenue` (passwordless `sudo`)
- **Login:** SSH private key `qt_exam` (ed25519) and a console password, both handed over with the submission. They are not committed to this repository.

```bash
ssh -i qt_exam cedrick-bienvenue@192.168.160.210
```

### Docker Hub images

| Image | Used by |
|---|---|
| `cedrick13bienvenue/projecthub-api:1.0.0` | Compose `api`, Kubernetes `api` |
| `cedrick13bienvenue/projecthub-frontend:1.0.0` | Compose `frontend`, Kubernetes `frontend` |
| `nginx:1.28-alpine` (official) | reverse proxy in both deployments |
| `mongo:7` (official) | database in both deployments |
| `valkey/valkey:8-alpine` (official) | cache in both deployments |

---

## Differences from the brief

The environment changed during the exam; everything below was done with the organisers' agreement.

| Brief | Used | Reason |
|---|---|---|
| Proxmox `192.168.160.14`, node `server4`, pool `exam-c7`, template 9102 (AlmaLinux 9) | Proxmox `192.168.160.13`, node `server3`, no pool, template **9000 (Ubuntu 24.04)** | DHCP never answered VMs on server4; the admins moved the candidate to server3 and issued a new token |
| VM addresses from DHCP | **Static** `192.168.160.210–213` | DHCP on `192.168.160.0/24` stayed unreliable (repeated 45 s timeouts, packet capture showed DISCOVER with no OFFER); the admins assigned four static IPs |
| MyDiary: Next.js 14 + Spring Boot 3 + PostgreSQL 16 + Redis | **ProjectHub: React 18/Vite + Go 1.23/Gin + MongoDB 7 + Valkey 8** | This is the code in the provided GitLab repository (its README calls it "Challenge A") |

The requirements were mapped onto the real stack:

| Brief term | ProjectHub equivalent |
|---|---|
| `nextjs` (standalone server :3000) | `frontend`: static Vite build served by NGINX on :80 |
| `springboot` (:8080) | `api`: Go binary on :8080, every route under `/api` |
| `postgres` | `mongodb` |
| `redis` | `valkey` (Redis-protocol compatible) |
| `/actuator/health` | not applicable (Spring only); health is `GET /api/health` |
| Spring profile | `GIN_MODE=release` |
| JVM heap within the container limit | `GOMEMLIMIT` within the container limit (see Task 4) |
| "diary entries, users only see their own" | projects and tasks; members only see projects they belong to, admin-only routes return 403 |

---

## Repository structure

```
.
├── iac/          Task 1 — Terraform: 4 VMs on Proxmox + generated Ansible inventory
├── ansible/      Task 3 — playbooks and roles (common, docker_host, k8s_node, k8s_control_plane, k8s_worker)
├── docker/       Task 2 — multi-stage Dockerfiles, NGINX configs, docker-compose.yml
├── k8s/          Task 4 — Kubernetes manifests, resilience test script and its output
├── helm/         Bonus — Helm chart for the same app, with optional Gateway API routing
├── app/          Application source from GitLab (backend/ and frontend/)
├── monitoring/   Task 5 — screenshots, one folder per VM
└── README.md
```

Secrets never enter git: `iac/terraform.tfvars`, `*.tfstate`, `docker/.env`, `k8s/02-secret.yaml` and
`helm/values.secret.yaml` are ignored. Each has a committed template (`terraform.tfvars.example`, `.env.example`,
`02-secret.yaml.example`, `values.secret.yaml.example`).

---

## Architecture

### Infrastructure

```mermaid
flowchart LR
    mac["Workstation<br/>Terraform · Ansible · Docker · kubectl"]
    pve["Proxmox VE 9.1<br/>192.168.160.13 · node server3"]
    hub[("Docker Hub<br/>cedrick13bienvenue/*")]

    subgraph lan["LAN 192.168.160.0/24 · gateway .1"]
        vm1["c3-docker-host<br/>.210 · Docker Compose"]
        vm2["c3-k8s-master<br/>.211 · control plane"]
        vm3["c3-k8s-worker-1<br/>.212"]
        vm4["c3-k8s-worker-2<br/>.213"]
    end

    mac -- "terraform apply (API token)" --> pve
    pve -- "clone template 9000 + cloud-init" --> lan
    mac -- "ansible-playbook (SSH)" --> vm1 & vm2 & vm3 & vm4
    mac -- "docker push" --> hub
    hub -- "docker pull" --> vm1
    hub -- "image pull" --> vm3 & vm4
    mac -- "kubectl apply" --> vm2
```

### Docker Compose deployment (c3-docker-host)

```mermaid
flowchart LR
    user(["Browser"]) -- ":80" --> nginx

    subgraph web["network: web"]
        nginx["nginx<br/>nginx:1.28-alpine"]
        fe["frontend<br/>projecthub-frontend:1.0.0"]
        api["api<br/>projecthub-api:1.0.0"]
    end

    subgraph data["network: data (internal, no host ports)"]
        mongo[("mongodb<br/>mongo:7<br/>volume mongo-data")]
        valkey[("valkey<br/>valkey/valkey:8-alpine<br/>requirepass")]
    end

    nginx -- "/" --> fe
    nginx -- "/api/" --> api
    api --> mongo
    api -. "cache (optional)" .-> valkey
```

### Kubernetes deployment (namespace `qt-spring-app`)

```mermaid
flowchart LR
    user(["Browser"]) -- "NodeIP:30080" --> svc["Service nginx<br/>NodePort 30080"]

    subgraph ns["namespace qt-spring-app"]
        svc --> ngx["Deployment nginx ×2<br/>ConfigMap nginx-config"]
        ngx -- "/" --> fesvc["Service frontend"] --> fe["Deployment frontend ×2"]
        ngx -- "/api/" --> apisvc["Service api"] --> api["Deployment api ×3<br/>ConfigMap + Secret"]
        api --> mongosvc["Service mongodb (headless)"] --> mongo["StatefulSet mongodb-0"]
        api -.-> valkeysvc["Service valkey"] --> valkey["Deployment valkey ×1"]
        mongo --- pvc[("PVC mongodb-data")] --- pv[("PV hostPath<br/>on c3-k8s-worker-1")]
    end
```

Pods of `api`, `frontend` and `nginx` are spread across both workers (`topologySpreadConstraints`);
`mongodb-0` follows its PersistentVolume to `c3-k8s-worker-1`; the control plane is tainted and runs only system pods.

---

## Task 1 — Infrastructure as Code (Terraform)

**Files:** [`iac/`](iac/) — `provider.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `inventory.tf`, `templates/hosts.ini.tftpl`

Provider `bpg/proxmox` 0.123.1 (`~> 0.69` as required) and `hashicorp/local` 2.9.1.

### What it does

- One `proxmox_virtual_environment_vm` resource with `for_each` over the `vms` map, so all four VMs come from the same code.
- Full clone of template 9000, resized to 4 vCPU / 4 GB / 30 GB, installer ISO ejected.
- **cloud-init** sets the hostname, static IP, gateway, DNS, the user `cedrick-bienvenue`, its SSH key and password.
- CPU type `x86-64-v3` so the VMs expose AVX/AVX2, which MongoDB 5+ requires.
- QEMU guest agent enabled; outputs report IPs, VMIDs, MACs and ready-made SSH commands.
- Writes `ansible/inventory/hosts.ini` from the real IPs, so nothing is copied by hand between Terraform and Ansible.

### Variables

| Variable | Value |
|---|---|
| `proxmox_endpoint` | `https://192.168.160.13:8006/` |
| `proxmox_token_id` | `exam@pve!candidate1` |
| `proxmox_api_token_secret` | from `terraform.tfvars` (git-ignored) |
| `proxmox_node` / `datastore_id` / `network_bridge` | `server3` / `local-lvm` / `vmbr0` |
| `template_vm_id` | `9000` |
| `cpu_type` | `x86-64-v3` |
| `gateway` / `network_cidr_prefix` / `dns_servers` | `192.168.160.1` / `24` / `8.8.8.8, 8.8.4.4` |
| `vm_username` / `vm_password` / `ssh_public_key_path` | `cedrick-bienvenue` / tfvars / `~/.ssh/qt_exam.pub` |
| `vms` | map of name → `vm_id`, `role`, `ip` (omit `ip` for DHCP), optional size overrides |

### Run

```bash
cd iac
cp terraform.tfvars.example terraform.tfvars    # add the token secret and vm_password
terraform init
terraform plan -out=vms.tfplan
terraform apply vms.tfplan
terraform output vm_ips
```

```
vm_ips = {
  "c3-docker-host"  = "192.168.160.210"
  "c3-k8s-master"   = "192.168.160.211"
  "c3-k8s-worker-1" = "192.168.160.212"
  "c3-k8s-worker-2" = "192.168.160.213"
}
```

---

## Task 2 — Docker Compose (c3-docker-host)

**Files:** [`docker/`](docker/)

### Multi-stage images

| Dockerfile | Build stage | Runtime stage | Size |
|---|---|---|---|
| [`api.Dockerfile`](docker/api.Dockerfile) | `golang:1.23-alpine`: download modules (cached layer), `CGO_ENABLED=0 go build` | `alpine:3.22`, single static binary, non-root UID 10001 | ~20 MB |
| [`frontend.Dockerfile`](docker/frontend.Dockerfile) | `node:22-alpine`: `npm ci`, `npm run build` with `VITE_API_URL=/api` | `nginx:1.28-alpine` serving `dist/` with SPA fallback | ~62 MB |

The build context is limited by [`.dockerignore`](.dockerignore) to `app/backend`, `app/frontend` and the frontend NGINX config.

### Services ([`docker-compose.yml`](docker/docker-compose.yml))

| Service | Image | Notes |
|---|---|---|
| `nginx` | `nginx:1.28-alpine` | **only service with a host port (80)**; `/` → frontend, `/api/` → api |
| `frontend` | `cedrick13bienvenue/projecthub-frontend:1.0.0` | static React build |
| `api` | `cedrick13bienvenue/projecthub-api:1.0.0` | config and secrets from `.env` |
| `mongodb` | `mongo:7` | root user from `.env`, data in named volume `mongo-data`, **no host port** |
| `valkey` | `valkey/valkey:8-alpine` | **`--requirepass`**, no persistence, 128 MB LRU, **no host port** |

- Two networks: `web` (nginx, frontend, api) and `data` (api, mongodb, valkey) with `internal: true`, so the database and cache are unreachable from outside and from NGINX.
- Health checks on every service; `depends_on: condition: service_healthy` starts them in order mongodb → api → nginx.
- [`nginx.conf`](docker/nginx.conf) re-resolves container names through Docker DNS (`resolver 127.0.0.11`) so restarted containers are followed, and forwards `Host` with its port (`$http_host`).
- `docker-compose.build.yml` adds the `build:` sections; the VM itself only pulls.

### Build, push and deploy

Docker Engine is installed on the VM by the Ansible role `docker_host`.

```bash
# workstation
cd docker
cp .env.example .env                      # set MONGO_ROOT_PASSWORD, JWT_SECRET, VALKEY_PASSWORD
docker compose -f docker-compose.yml -f docker-compose.build.yml build
docker login -u cedrick13bienvenue
docker compose -f docker-compose.yml -f docker-compose.build.yml push api frontend

cd ../ansible && ansible-playbook site.yml --limit docker
cd ../docker && scp -i ~/.ssh/qt_exam docker-compose.yml nginx.conf .env cedrick-bienvenue@192.168.160.210:projecthub/

# on c3-docker-host
cd ~/projecthub
docker compose pull
docker compose up -d
docker compose ps
```

### Verified

| Check | Result |
|---|---|
| `curl http://192.168.160.210/api/health` | `{"status":"ok","database":"up","cache":"up"}` |
| Listening TCP ports on the VM | only `:22` and `:80` (MongoDB 27017 and Valkey 6379 stay inside Docker) |
| `valkey-cli ping` without password | `NOAUTH Authentication required` |
| member calling admin-only `/api/users` | `403` |
| call without a token | `401` |

---

## Task 3 — Kubernetes cluster with Ansible

**Files:** [`ansible/`](ansible/) — run from the workstation (control node) against the VMs.

```bash
cd ansible
ansible all -m ping
ansible-playbook site.yml
```

### Plays in [`site.yml`](ansible/site.yml)

| Play | Hosts | Role | Tasks |
|---|---|---|---|
| Baseline | all | `common` | grow the root LV into the space the Ubuntu installer left unused (14 GB → 28 GB), install `htop`, `sysstat`, `net-tools`, `jq` |
| Docker host | `docker` | `docker_host` | Docker CE + Compose plugin from download.docker.com, user in `docker` group |
| Node prep | `k8s` | `k8s_node` | swap off (now and in fstab), `overlay` + `br_netfilter`, bridge/forwarding sysctls, **containerd 2.2** with `SystemdCgroup = true`, **kubeadm/kubelet/kubectl v1.36.6** from pkgs.k8s.io, held |
| Control plane | `control_plane` | `k8s_control_plane` | `kubeadm init` (pod CIDR `10.244.0.0/16`), kubeconfig for the user and the workstation, **Flannel v0.28.11** CNI, wait for Ready, create join command |
| Workers | `workers` | `k8s_worker` | `kubeadm join` with the command registered on the control plane |
| Verify | `control_plane` | `k8s_control_plane/verify` | label workers, wait for all nodes Ready, print `kubectl get nodes` |

Versions live in [`group_vars/k8s.yml`](ansible/group_vars/k8s.yml). The inventory is generated by Terraform.

**Idempotent:** `kubeadm init` and `join` are guarded by `creates:`, the disk grow by a free-space check, so a second run changes nothing.

### Result

```
NAME              STATUS   ROLES           VERSION   INTERNAL-IP       OS-IMAGE             CONTAINER-RUNTIME
c3-k8s-master     Ready    control-plane   v1.36.6   192.168.160.211   Ubuntu 24.04.5 LTS   containerd://2.2.1
c3-k8s-worker-1   Ready    worker          v1.36.6   192.168.160.212   Ubuntu 24.04.5 LTS   containerd://2.2.1
c3-k8s-worker-2   Ready    worker          v1.36.6   192.168.160.213   Ubuntu 24.04.5 LTS   containerd://2.2.1
```

---

## Task 4 — Application on Kubernetes

**Files:** [`k8s/`](k8s/) — applied in filename order.

```bash
export KUBECONFIG=~/.kube/qt-exam.conf
# generate the real Secret from docker/.env (git-ignored)
set -a; source docker/.env; set +a
kubectl create secret generic projecthub-secret -n qt-spring-app \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=MONGO_ROOT_USERNAME="$MONGO_ROOT_USERNAME" \
  --from-literal=MONGO_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD" \
  --from-literal=MONGO_URI="mongodb://$MONGO_ROOT_USERNAME:$MONGO_ROOT_PASSWORD@mongodb-0.mongodb.qt-spring-app.svc.cluster.local:27017/?authSource=admin" \
  --from-literal=VALKEY_PASSWORD="$VALKEY_PASSWORD" \
  --dry-run=client -o yaml > k8s/02-secret.yaml
kubectl apply -f k8s/
kubectl get pods -n qt-spring-app -o wide
```

The app was first deployed with these plain manifests (the resilience proof below ran on them). The cluster now
runs the same resources from the Helm chart in [`helm/`](#bonus-1--helm-chart); apply one or the other, not both.

### Requirements → resources

| Requirement | Implementation |
|---|---|
| Namespace `qt-spring-app` | [`00-namespace.yaml`](k8s/00-namespace.yaml) |
| ConfigMaps | [`01-configmap.yaml`](k8s/01-configmap.yaml) (`GIN_MODE`, `MONGO_DB`, `VALKEY_ADDR`, TTLs, seeding) and `nginx-config` in [`50-nginx.yaml`](k8s/50-nginx.yaml) |
| Secrets | `projecthub-secret`: `JWT_SECRET`, `MONGO_URI`, MongoDB root credentials, `VALKEY_PASSWORD` ([template](k8s/02-secret.yaml.example)) |
| Database with PV + PVC | [`10-mongodb.yaml`](k8s/10-mongodb.yaml): 5Gi `hostPath` PV on `c3-k8s-worker-1` (`Retain`), PVC `mongodb-data`, StatefulSet `mongodb`, headless Service |
| Cache Deployment + Service | [`20-valkey.yaml`](k8s/20-valkey.yaml) |
| API Deployment + Service | [`30-api.yaml`](k8s/30-api.yaml): 3 replicas, rolling update with `maxUnavailable: 0` |
| Frontend Deployment + Service | [`40-frontend.yaml`](k8s/40-frontend.yaml): 2 replicas |
| NodePort | [`50-nginx.yaml`](k8s/50-nginx.yaml): NGINX ×2 behind Service `nginx`, `nodePort: 30080` |
| Probes | API: readiness and liveness on `/api/health`; frontend: on `/`; NGINX, MongoDB and Valkey also probed |

### Requests and limits

| Container | Requests (CPU / memory) | Limits (CPU / memory) |
|---|---|---|
| api | 100m / 64Mi | 500m / 256Mi |
| frontend | 20m / 32Mi | 200m / 128Mi |
| nginx | 20m / 32Mi | 200m / 128Mi |
| mongodb | 100m / 512Mi | 1 / 1Gi |
| valkey | 50m / 64Mi | 250m / 192Mi |

**Memory must fit the limit.** The brief asks for the Spring Boot JVM heap to stay within its limit. The Go
equivalent of `-Xmx` is `GOMEMLIMIT`: the API sets `GOMEMLIMIT=200MiB` under a `256Mi` limit, so the garbage
collector works harder as the heap approaches 200 MiB instead of the kernel OOM-killing the container.
MongoDB gets `--wiredTigerCacheSizeGB 0.25` for the same reason under its `1Gi` limit.

### Does the cache need persistent storage?

**No.** Valkey only holds copies of data whose source of truth is MongoDB (dashboard statistics and user
lookups, with 1–2 minute TTLs). If the Valkey pod restarts empty, the API reads from MongoDB and refills the
cache; nothing is lost and users see no error. A PersistentVolume would add disk I/O and pin the pod to one
node for no benefit, so Valkey runs with persistence off (`--save '' --appendonly no`), a 128 MB cap and LRU eviction.
The opposite holds for MongoDB, which is why only it gets a PV.

### Resilience proof

Script: [`k8s/resilience-test.sh`](k8s/resilience-test.sh) · full output: [`k8s/resilience-test.log`](k8s/resilience-test.log)

**1. Scale the API to 3 replicas and delete one pod under traffic** (`GET /api/health` every 200 ms):

```
========== Delete API pod api-7cc468d5b5-pjcd4 while traffic is running ==========
pod "api-7cc468d5b5-pjcd4" deleted from qt-spring-app namespace
NAME                   READY   STATUS    RESTARTS   AGE     NODE
api-7cc468d5b5-hkrr2   1/1     Running   0          15s     c3-k8s-worker-2    <- replacement
api-7cc468d5b5-s4n7f   1/1     Running   0          7m14s   c3-k8s-worker-2
api-7cc468d5b5-shn5d   1/1     Running   0          7m14s   c3-k8s-worker-1

========== Traffic result during the pod deletion ==========
requests sent: 74
HTTP 200:      74
failed:        0
```

A terminating pod is removed from the Service endpoints at once, the other replicas take the traffic,
and the Deployment schedules a replacement.

**2. Stop the cache** (`kubectl scale deploy/valkey --replicas=0`):

```
========== /api/health with the cache stopped ==========
{"status":"ok","database":"up","cache":"down"}

========== The app still works without the cache ==========
POST /api/auth/login -> token received
GET /api/projects -> HTTP 200
GET /api/stats    -> HTTP 200

========== Restore the cache ==========
{"status":"ok","database":"up","cache":"up"}
```

The API reconnects to Valkey by itself once it is back.

---

## Task 5 — Server monitoring

Screenshots were taken on each VM over SSH while both deployments and the cluster were running. Every
screenshot shows the hostname in its header and in the prompt line above the command.

### All four VMs

Each VM folder contains the same eight system views (`vmN` = vm1 docker-host, vm2 master, vm3 worker-1, vm4 worker-2):

| Screenshot | Command | What it shows |
|---|---|---|
| `vmN-htop.png` | `htop` | per-core CPU, memory and swap bars, load average, tasks and the live process list |
| `vmN-df.png` | `df -hT -x tmpfs -x overlay -x devtmpfs` | disk usage per partition: the root LV (28 GB after the Ansible resize) and `/boot` |
| `vmN-free.png` | `free -h` | total, used, free and available memory; swap is 0 on the Kubernetes nodes |
| `vmN-uptime.png` | `uptime` | time since boot and 1/5/15-minute load averages |
| `vmN-ports.png` | `sudo ss -tulpn` | listening sockets and owning processes: sshd :22 everywhere; docker-proxy :80 on vm1; kube-apiserver :6443, etcd :2379–2381, controller-manager :10257, scheduler :10259 on vm2; kubelet :10250 and kube-proxy :10249/:10256 on every node. NodePort 30080 does not appear: kube-proxy implements it with iptables NAT rules, not a listening socket |
| `vmN-ps.png` | `ps aux --sort=-%cpu \| head -25` | processes ordered by CPU with %CPU, %MEM, RSS and command |
| `vmN-iostat.png` | `iostat -xz 1 3` | per-device reads/writes per second, throughput, wait times and utilisation |
| `vmN-vmstat.png` | `vmstat -w 1 5` | run queue, memory, swap in/out, block I/O, interrupts, context switches and CPU split |

Folders: [`monitoring/vm1-docker-host/`](monitoring/vm1-docker-host/) ·
[`monitoring/vm2-k8s-master/`](monitoring/vm2-k8s-master/) ·
[`monitoring/vm3-k8s-worker-1/`](monitoring/vm3-k8s-worker-1/) ·
[`monitoring/vm4-k8s-worker-2/`](monitoring/vm4-k8s-worker-2/)

### c3-docker-host (vm1)

| Screenshot | Command | What it shows |
|---|---|---|
| [`vm1-docker-ps.png`](monitoring/vm1-docker-host/vm1-docker-ps.png) | `docker ps` | the five containers, their images, `healthy` status and ports (only nginx publishes `0.0.0.0:80`) |
| [`vm1-docker-stats.png`](monitoring/vm1-docker-host/vm1-docker-stats.png) | `docker stats --no-stream` | CPU %, memory usage/limit, network and block I/O per container |
| [`vm1-api-logs.png`](monitoring/vm1-docker-host/vm1-api-logs.png) | `docker logs --tail 50 projecthub-api-1` | last 50 API log lines in Gin's request format (time, status, latency, client, method, path), mostly the Compose healthcheck calling `/api/health` every 15 s plus login and page requests |
| [`vm1-valkey.png`](monitoring/vm1-docker-host/vm1-valkey.png) | `valkey-cli DBSIZE`, `--scan`, `INFO memory/stats/keyspace` | cached keys (`projecthub:*`), memory used vs the 128 MB cap, `keyspace_hits` and `keyspace_misses` |
| [`vm1-health.png`](monitoring/vm1-docker-host/vm1-health.png) | `curl .../api/health` | health of both deployments: status, database and cache all up |

### c3-k8s-master (vm2)

| Screenshot | Command | What it shows |
|---|---|---|
| [`vm2-k8s-nodes.png`](monitoring/vm2-k8s-master/vm2-k8s-nodes.png) | `kubectl get nodes -o wide` | three nodes `Ready`, roles, version v1.36.6, internal IPs, OS and containerd version |
| [`vm2-k8s-pods.png`](monitoring/vm2-k8s-master/vm2-k8s-pods.png) | `kubectl get pods -n qt-spring-app -o wide` and `-n kube-system` | app and system pods with readiness, restarts and the node each one runs on |
| [`vm2-health.png`](monitoring/vm2-k8s-master/vm2-health.png) | `curl .../api/health` | health of the Kubernetes and Compose deployments |

---

## Bonus 1 — Helm chart

**Files:** [`helm/projecthub/`](helm/projecthub/) (chart `projecthub` 0.1.0, appVersion 1.0.0), installed with Helm v4.3.2.

The chart packages every Task 4 resource as templates driven by one `values.yaml`, so an image tag, replica count,
resource limit or NodePort changes in one place, and the whole app installs, upgrades or rolls back with one command.

| File | Purpose |
|---|---|
| `values.yaml` | portable defaults: images, replicas, resources, NodePort, storage; Gateway off |
| [`helm/values.qt-cluster.yaml`](helm/values.qt-cluster.yaml) | this cluster's overrides: Gateway on |
| `helm/values.secret.yaml` (git-ignored) | JWT, MongoDB and Valkey secrets ([template](helm/values.secret.yaml.example)) |
| `templates/_helpers.tpl` | shared labels, image names, and `MONGO_URI` built from the release namespace |
| `templates/*.yaml` | ConfigMaps, Secret, MongoDB (PV, PVC, StatefulSet, Service), Valkey, API, frontend, NGINX + NodePort, Gateway + HTTPRoute |

What the chart adds over the plain manifests:

- **Secrets are mandatory:** `required` makes `helm install` fail with `secrets.jwtSecret is required` instead of deploying empty passwords.
- **Config changes roll the pods:** `checksum/config` and `checksum/secret` annotations hash the ConfigMaps and Secret into the pod template, so `helm upgrade` restarts exactly the pods whose configuration changed.
- **Releases are versioned:** `helm history` lists every revision and `helm rollback` returns to any of them.

### Install

```bash
helm install projecthub helm/projecthub -n qt-spring-app --create-namespace \
  -f helm/values.qt-cluster.yaml -f helm/values.secret.yaml --wait

helm upgrade projecthub helm/projecthub -n qt-spring-app \
  -f helm/values.qt-cluster.yaml -f helm/values.secret.yaml --set api.replicas=4 --wait
helm history projecthub -n qt-spring-app
helm rollback projecthub 1 -n qt-spring-app --wait
```

### Switching from the plain manifests without losing data

The kubectl-managed resources were deleted (`kubectl delete -f k8s/`, including the namespace, PVC and PV
objects) and the chart installed in their place. A project created just before the switch was still there
afterwards, and the API logged no first-start seeding, so the MongoDB data on `c3-k8s-worker-1` survived:
a `hostPath` PV with `Retain` keeps its directory when the PV object is deleted, and the new PV mounts the same path.

| Check after `helm install` | Result |
|---|---|
| `helm list -n qt-spring-app` | `projecthub`, chart `projecthub-0.1.0`, `deployed` |
| Objects | every Deployment, StatefulSet, Service, PVC and the PV labelled `app.kubernetes.io/managed-by: Helm` |
| Data | 3 users, the seeded project and the marker project `Persistence check (before Helm)` |

---

## Bonus 2 — Gateway API

External traffic reaches the app through a `Gateway` and an `HTTPRoute` handled by
**NGINX Gateway Fabric 2.9.0**, using **Gateway API v1.7.0** (standard channel).

```mermaid
flowchart LR
    user(["Browser"]) -- "NodeIP:30090" --> svc["Service projecthub-gateway-nginx<br/>NodePort 30090"]
    subgraph ngfns["namespace nginx-gateway"]
        ctrl["NGF controller<br/>GatewayClass nginx"]
    end
    subgraph ns["namespace qt-spring-app"]
        svc --> dp["NGINX data plane pod<br/>(created by NGF for the Gateway)"]
        gw["Gateway projecthub-gateway<br/>listener http :80"]
        rt["HTTPRoute projecthub"]
        dp -- "PathPrefix /api" --> api["Service api :8080"]
        dp -- "PathPrefix /" --> fe["Service frontend :80"]
    end
    ctrl -. "watches Gateway + HTTPRoute,<br/>provisions and configures" .-> dp
    rt -. "parentRef" .-> gw
```

NGF watches Gateways of class `nginx`; for `projecthub-gateway` it creates an NGINX Deployment and Service in
`qt-spring-app` and turns the HTTPRoute rules into that NGINX's configuration. No NGINX config is written by hand
for this path. The Gateway and HTTPRoute are chart templates ([`gateway.yaml`](helm/projecthub/templates/gateway.yaml)),
enabled by `gateway.enabled: true` in `values.qt-cluster.yaml`.

### Install

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.7.0/standard-install.yaml

helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric --version 2.9.0 \
  -n nginx-gateway --create-namespace -f helm/ngf-values.yaml --wait

helm upgrade projecthub helm/projecthub -n qt-spring-app \
  -f helm/values.qt-cluster.yaml -f helm/values.secret.yaml --wait
```

[`helm/ngf-values.yaml`](helm/ngf-values.yaml) exposes the data plane as NodePort **30090** (there is no cloud load
balancer) with `externalTrafficPolicy: Cluster`, so every node answers, not only the one running the NGINX pod.

### Verified

| Check | Result |
|---|---|
| `kubectl get gatewayclass` | `nginx`, `ACCEPTED True` |
| `kubectl get gateway -n qt-spring-app` | `projecthub-gateway`, `PROGRAMMED True` |
| HTTPRoute status | `Accepted=True`, `ResolvedRefs=True` |
| `:30090` on `.211`, `.212`, `.213` | health `ok/up/up`, browser-style login 200, SPA deep link 200 |
| Same data through `:30080` (NGINX) and `:30090` (Gateway) | identical project list |

---

## Application functionality

ProjectHub is a project manager with JWT authentication and three roles:

- **admin:** manages users and every project
- **manager:** creates projects and manages the ones they own
- **member:** sees only the projects they belong to and updates the status of their own tasks

Login and the dashboard were checked in a browser on both URLs. The full flow was then checked against
both deployments through the API, sending the browser's `Origin` header:

| Step | Docker Compose | Kubernetes |
|---|---|---|
| Register a new user | member, token issued | member, token issued |
| Manager creates a project and a task | created | created |
| Task moved to "in progress" | 200 | 200 |
| New user lists projects | 0 (sees none of the manager's) | 0 |
| New user opens the manager's project by ID | 404 (existence not revealed) | 404 |
| Member calls admin-only `/api/users` | 403 | 403 |
| Test project and user deleted | 204 / 204 | 204 / 204 |

---

## Problems met and how they were solved

| Problem | Diagnosis | Fix |
|---|---|---|
| VMs on server4 never received an IP | QEMU agent reported only IPv6 link-local; `NetworkManager` logs showed repeated `dhcp4 ... no lease` | moved to server3 with static IPs from the admins; `ip` became an optional per-VM variable |
| Root filesystem only 14 GB on a 30 GB disk | the Ubuntu installer gives the root LV half of the volume group | Ansible `common` role runs `lvextend --resizefs -l +100%FREE` when free space exists |
| MongoDB 7 needs AVX | the default QEMU CPU model hides AVX | `cpu_type = "x86-64-v3"` (host Xeon E5-2695 v4 supports it) |
| Gateway API CRD install via `kubectl kustomize` timed out | the kustomization clones two Git repositories within a 27 s limit | applied the identical published bundle `standard-install.yaml` (v1.7.0) with `--server-side` |
| Browser login on `:30080` returned 403, curl worked | the API's CORS check compares `Origin` with `Host`; NGINX's `$host` drops the port, so `http://IP:30080` ≠ `IP` | forward `Host $http_host` in both NGINX configs |
