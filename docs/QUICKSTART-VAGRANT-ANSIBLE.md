# Quick start: Vagrant + VMware + K3s + Ansible (Online Boutique)

Step-by-step path to run the **Google microservices demo** (Online Boutique) on a **local multi-VM** stack: four guests (control plane, two workers, registry), then **Ansible** installs **K3s**, a **local registry**, and **builds/deploys** the app.

For deeper detail and alternatives (e.g. Kind), see [on-prem-deployment.md](./on-prem-deployment.md).

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| **Vagrant** 2.4+ | |
| **VMware Workstation** (or Fusion) + **Vagrant VMware plugin** | Example: `vagrant plugin install vagrant-vmware-desktop` |
| **Ansible** 2.9+ | On **WSL** or **Linux** is simplest for `ansible-playbook` |
| **~12 GB RAM**, **~50 GB disk** | Four VMs |
| Repo cloned | You are in the repository root for Ansible commands |

Ansible needs a **UTF-8** locale. If you see `Ansible requires the locale encoding to be UTF-8`, run (WSL/Linux):

```bash
export LC_ALL=C.UTF-8 LANG=C.UTF-8
```

---

## Architecture (what each part does)

| Piece | Role |
|-------|------|
| **registry-vm** | Runs **Docker Registry 2** on port **5000**. Stores images you build on `k3s-control` and push to `registry.local:5000/...`. Every K3s node pulls from here (not from Google’s public registry). |
| **k3s-control** | K3s server; builds images (Docker), pushes to the registry, runs `kubectl` / kustomize apply. |
| **k3s-worker1 / k3s-worker2** | Run workload pods; **must** have the same `/etc/rancher/k3s/registries.yaml` and `/etc/hosts` for `registry.local` as the control plane (handled by `registry-vm.yml`). |

---

## Step 1 — Start the VMs

```bash
cd vagrant
# Optional: match your LAN (e.g. 192.168.0.0/24 with gateway 192.168.0.1)
#   export VMWARE_IP_PREFIX=192.168.0
#   export VMWARE_GATEWAY=192.168.0.1
# Then update ansible/inventory/hosts.yml to the same prefix before Ansible.
vagrant validate
vagrant up
```

Confirm:

```bash
vagrant status
```

Expected VM names: `k3s-control`, `k3s-worker1`, `k3s-worker2`, `registry-vm`.

**Static IPs (default `VMWARE_IP_PREFIX=192.168.1` in `vagrant/Vagrantfile`):**

| VM | Address |
|----|---------|
| k3s-control | `192.168.1.210` |
| k3s-worker1 | `192.168.1.211` |
| k3s-worker2 | `192.168.1.212` |
| registry-vm | `192.168.1.220` |

`ansible/inventory/hosts.yml` must use the **same** addresses, plus `k3s_apiserver_advertise_address` and `registry_ip`. If you change the prefix, update **every** `192.168.1.x` in the inventory (and `Vagrantfile` env) consistently.

**`/etc/hosts` inside VMs** (provisioned by Vagrant) includes `registry.local` → registry VM and `boutique.internal` → **control-plane** (`192.168.1.210` by default) for ingress/DNS tests.

---

## Step 2 — SSH key for Ansible (Vagrant `insert_key = false`)

The Vagrantfile uses **`config.ssh.insert_key = false`**, so Ansible must use Vagrant’s **insecure** private key path (not per-VM files under `.vagrant/machines/.../private_key`).

From the **repository root**:

```bash
source vagrant/ansible-ssh-env.sh
```

This sets `VAGRANT_INSECURE_KEY` for Ansible and writes `vagrant/.ansible-ssh-env.generated` (gitignored).  
If the key lives under **`/mnt/c/...`**, the script copies it to **`~/.vagrant.d/insecure_private_key`** on the Linux side and `chmod 600`s it — OpenSSH on WSL will not use keys that stay on the Windows mount with `0777` permissions.

If you use **Windows Vagrant** but **WSL Ansible**, the script tries your Windows profile under `/mnt/c/Users/...` when needed.

New shell later:

```bash
source vagrant/.ansible-ssh-env.generated
```

---

## Step 3 — Run Ansible (order matters)

Always from **repository root** (so `ansible.cfg` and inventory paths resolve).

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/k3s-bootstrap.yml -v
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/registry-vm.yml -v
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-app.yml -v
```

What each step does:

1. **k3s-bootstrap** — K3s server + agents; fetches **`./k3s-kubeconfig`** to the repo root.
2. **registry-vm** — Docker Registry on `registry-vm`; `registry.local` in `/etc/hosts` on all nodes; **insecure** registry mirror in Docker on `k3s-control` for `docker push`; **`/etc/rancher/k3s/registries.yaml` on every cluster node** (control + workers) so **containerd** can pull `http://registry.local:5000/...`.
3. **deploy-app** — Syncs repo to the control plane, `docker build` / `docker push` images tagged with **`microservices_image_tag`** (default **`v0.10.5`**, matching `kustomize/base`), mirrors **`redis:alpine`** into the registry, then `kubectl kustomize` + apply for `kustomize/environments/onprem/k3s`.

**Inventory flag:** use a normal path, e.g. `-i ansible/inventory/hosts.yml`.  
Do **not** use a leading comma or `/ansible/...` from filesystem root — that loads **no hosts**.

---

## Step 4 — Use the cluster and open the app

Kubeconfig from bootstrap:

```bash
export KUBECONFIG="$PWD/k3s-kubeconfig"
# If the server address in the file is wrong for your network:
# sed -i 's/127.0.0.1/192.168.1.210/g' k3s-kubeconfig
kubectl get nodes
```

On the control-plane VM:

```bash
sudo k3s kubectl get nodes
```

### Port-forward (recommended)

Service **`frontend`** exposes port **80** → pod **8080**. Forward **local 8080** to **service port 80**:

```bash
kubectl port-forward -n default svc/frontend 8080:80
# or on the VM:
sudo k3s kubectl port-forward -n default svc/frontend 8080:80
```

- **Same machine as `kubectl`:** open **http://127.0.0.1:8080** or **http://localhost:8080**.
- **Default `port-forward` binds `127.0.0.1` only** — your Windows browser **cannot** use `http://<VM-LAN-IP>:8080` unless you either:
  - **Listen on all interfaces:**  
    `sudo k3s kubectl port-forward -n default --address 0.0.0.0 svc/frontend 8080:80`  
    then browse **http://192.168.1.210:8080** (use your real control-plane IP), or
  - **SSH tunnel:** `ssh -L 8080:127.0.0.1:8080 vagrant@192.168.1.210` and open **http://localhost:8080** on the PC.

### Ingress hostname `boutique.internal`

Manifests use host **`boutique.internal`** (Ingress class **traefik** in `kustomize/environments/onprem/k3s`). You need an ingress controller matching that class; many lab setups use **port-forward** instead.

To use the hostname from your **PC**, add to **Windows** `C:\Windows\System32\drivers\etc\hosts` (or Linux/Mac `/etc/hosts`):

```text
192.168.1.210  boutique.internal
```

Use the **control-plane** IP (same as Vagrant `boutique.internal` line). **Only the VMs’ `/etc/hosts** are updated by Vagrant; your browser host does not read the Vagrantfile.

---

## Step 5 — Tear down (optional)

```bash
cd vagrant
vagrant destroy -f
```

---

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| `skipping: no hosts matched` | Inventory path wrong; run from repo root; use `-i ansible/inventory/hosts.yml` |
| `no such identity ... private_key` | Run `source vagrant/ansible-ssh-env.sh` (see Step 2) |
| `UNPROTECTED PRIVATE KEY FILE` / `Permissions 0777` on `/mnt/c/...` | Re-run `bash vagrant/ansible-ssh-env.sh`; it copies the key into `~/.vagrant.d/` with strict perms |
| `Could not resolve host` during `vagrant` provision | DNS after apt upgrades; re-run `vagrant provision <vm>` or fix resolver |
| `docker push` / registry timeouts | Re-run `registry-vm.yml`; confirm `registry_ip` and `registry.local` on nodes; Docker on control must allow **insecure** `registry.local:5000` |
| **`ImagePullBackOff`** on workers | (1) Registry must contain tags in **inventory** (e.g. `v0.10.5` for apps, `alpine` for redis) — re-run **deploy-app**. (2) **Workers** need `/etc/rancher/k3s/registries.yaml` (re-run **registry-vm.yml** if workers were added later). |
| Ansible SSH works but IPs wrong | `ip -4 addr` on each VM vs `ansible/inventory/hosts.yml`; align `VMWARE_IP_PREFIX` / `VMWARE_GATEWAY` before first `vagrant up` |
| **`unknown flag: --all`** on `kubectl rollout` | Older `k3s kubectl`: loop deployments, e.g. `for d in $(sudo k3s kubectl get deploy -n default -o jsonpath='{.items[*].metadata.name}'); do sudo k3s kubectl rollout restart deployment/$d -n default; done` or `sudo k3s kubectl delete pods -n default --all` to force new pulls |
| Port-forward works on VM but **connection refused** from PC | Default bind is **127.0.0.1**; use `--address 0.0.0.0` or SSH `-L` (see Step 4) |
| Ansible hangs at **"Verify registry is responding"** | Vagrant suspend cycles can freeze the docker proxies. Fix by flushing the Docker network stack: `vagrant ssh registry-vm -c "sudo systemctl restart docker"` |

---

## Completion checklist

After a successful run you should have:

- [ ] `kubectl get nodes` — all nodes **Ready**
- [ ] `sudo k3s kubectl get pods -n default` — app pods **Running** (not `ImagePullBackOff`)
- [ ] UI: **http://localhost:8080** (with port-forward as above) or **http://\<control-ip\>:8080** with `--address 0.0.0.0`

---

## One-command alternative (optional)

From repo root, after VMs are up and SSH env is set:

```bash
bash scripts/run-ansible.sh
```

Review `scripts/run-ansible.sh` for provider assumptions (`vagrant up` flags). You may prefer the manual three-playbook sequence above for clarity.
