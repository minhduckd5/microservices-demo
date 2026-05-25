# Ansible playbook orchestration and best practices guide

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   └── hosts.yml           # Host inventory (VMs, groups)
├── playbooks/
│   ├── k3s-bootstrap.yml   # K3s cluster initialization
│   ├── registry-vm.yml     # Docker registry setup
│   └── deploy-app.yml      # Build, push, deploy app
├── roles/
│   └── k3s-node/           # K3s node role (optional, modular)
│       └── tasks/
│           └── main.yml    # K3s node tasks
└── README.md               # This file
```

## Running Playbooks

### Sequential Execution (Recommended)

```bash
# K3s cluster setup
ansible-playbook -i inventory/hosts.yml playbooks/k3s-bootstrap.yml -v

# Registry setup
ansible-playbook -i inventory/hosts.yml playbooks/registry-vm.yml -v

# Deploy app
ansible-playbook -i inventory/hosts.yml playbooks/deploy-app.yml -v
```

### Automated (Single Command)

From repository root:

```bash
bash scripts/run-ansible.sh
```

Or with options:

```bash
bash scripts/run-ansible.sh --check      # Dry-run
bash scripts/run-ansible.sh --step       # Interactive step-by-step
```

### Idempotent Execution

All playbooks are designed to be re-runnable (idempotent). If a playbook fails:

```bash
# Fix the issue, then re-run
ansible-playbook -i inventory/hosts.yml playbooks/<playbook>.yml -v
```

## Inventory Customization

Edit `inventory/hosts.yml` to:
- Change VM IP addresses (must match Vagrant IPs)
- Add/remove worker nodes
- Adjust resource limits (registry_port, etc.)

Example: Add a 3rd worker node:

```yaml
k3s-worker3:
  ansible_host: 192.168.1.13
  ansible_user: vagrant
  ansible_ssh_private_key_file: .vagrant/machines/k3s-worker3/provider/private_key
```

Then add to group:

```yaml
k3s_agents:
  hosts:
    k3s-worker1:
    k3s-worker2:
    k3s-worker3:  # New entry
```

## Playbook Descriptions

### k3s-bootstrap.yml

**Purpose**: Initialize K3s cluster and join worker nodes.

**Plays**:
1. **Bootstrap K3s Control-Plane** — Installs K3s server on control-plane
2. **Join K3s Agents** — Installs K3s agents on workers and joins them to cluster
3. **Verify K3s Cluster Health** — Waits for all nodes to be `Ready`

**Idempotency**: Re-running is safe; K3s installation is skipped if already present.

### registry-vm.yml

**Purpose**: Set up Docker Registry 2.0 and configure K3s nodes to use it.

**Tasks**:
1. Start Docker registry container
2. Verify registry is responsive
3. Configure all K3s nodes to trust the registry
4. Add registry.local DNS entry to all nodes

**Idempotency**: Safe to re-run; registry container check/restart is idempotent.

### deploy-app.yml

**Purpose**: Build, push, and deploy Online Boutique.

**Plays**:
1. **Prepare Build Environment** — Verify Docker, kubectl, skaffold
2. **Build and Push Images** — Uses skaffold or docker build to create and push images
3. **Deploy Online Boutique** — Clones repo, renders kustomize manifests, applies to cluster

**Idempotency**: Re-running re-deploys (updates) the app; image rebuild can be slow. For faster re-runs, keep images in registry.

**Notes**:
- Requires internet access for skaffold/docker pull
- Builds happen on localhost (your machine), pushes to local registry
- First build of all services may take 20-30 minutes

## Debugging

### SSH into a Host

```bash
# From vagrant/ directory:
vagrant ssh k3s-control
vagrant ssh k3s-worker1
vagrant ssh registry-vm
```

### Check Ansible Connectivity

```bash
ansible all -i inventory/hosts.yml -m ping
```

### Run Playbook with Extra Verbosity

```bash
ansible-playbook -i inventory/hosts.yml playbooks/k3s-bootstrap.yml -vvvv
```

### Limit Playbook to Specific Hosts

```bash
# Run only on control-plane
ansible-playbook -i inventory/hosts.yml playbooks/k3s-bootstrap.yml --limit k3s_control_plane

# Run only on one host
ansible-playbook -i inventory/hosts.yml playbooks/registry-vm.yml --limit registry-vm
```

### Check Playbook Syntax

```bash
ansible-playbook -i inventory/hosts.yml playbooks/k3s-bootstrap.yml --syntax-check
```

### Dry-Run Mode (No Changes)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/k3s-bootstrap.yml --check
```

## Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| SSH connection timeout | VM not booted yet | Wait 30 seconds, then retry |
| Host key verification failed | ~/.ssh/known_hosts issue | Delete entry: `ssh-keygen -R 192.168.1.10` |
| K3s install fails | Internet connectivity | Check VM internet access: `vagrant ssh k3s-control -- curl -I https://get.k3s.io` |
| Registry not reachable from nodes | DNS issue | Verify `/etc/hosts` entries on all nodes: `vagrant ssh k3s-control -- cat /etc/hosts` |
| Deployment fails with `ImagePullBackOff` | Images not built/pushed | Re-run deploy-app.yml with extra verbosity |
| **WSL SSH private key permission error** (`0777` too open) | Windows mounts `/mnt/c/` in WSL default to 777 permissions, which OpenSSH rejects. | Copy your key into WSL home: `mkdir -p ~/.ssh && cp /mnt/c/Users/A/.ssh/id_rsa ~/.ssh/id_rsa && chmod 600 ~/.ssh/id_rsa` (Ansible automatically checks `~/.ssh/id_rsa` first!). |
| **QEMU Guest Agent service fails to start** (PVE only) | The VM setting `agent.enabled = false` is active in Proxmox VE (disables guest agent serial port). | Either enable it in Terraform `agent { enabled = true }` followed by a **VM cold boot (stop/start)** in PVE, or set `ignore_errors: yes` on the agent service task in the playbook. |

## Next Steps

1. Customize cluster (add nodes, change K3s version in `inventory/hosts.yml`)
2. Add custom roles (e.g., `monitoring`, `logging`) in `ansible/roles/`
3. Integrate into CI/CD (auto-deploy on code changes)
4. Scale to multiple environments (development, staging, production)

## Resources

- Ansible docs: https://docs.ansible.com/
- K3s docs: https://docs.k3s.io/
- Vagrant docs: https://www.vagrantup.com/docs
