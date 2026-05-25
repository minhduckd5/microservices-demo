# Proxmox VE Terraform Provisioning Module

This directory contains a production-grade, highly resilient, and 100% automated **Proxmox VE (PVE) 8.x/9.x** Terraform module. It provisions a 4-VM architecture matching the exact footprints of your local Vagrant setup:

*   **`k3s-control`** (`192.168.31.210` / VM ID: `210`) - Kubernetes Control-Plane
*   **`k3s-worker1`** (`192.168.31.211` / VM ID: `211`) - Kubernetes Agent Node 1
*   **`k3s-worker2`** (`192.168.31.212` / VM ID: `212`) - Kubernetes Agent Node 2
*   **`registry-vm`** (`192.168.31.220` / VM ID: `220`) - Local Insecure Image Registry

---

## 🛠️ What We Encountered & Solved (Engineering Log)

During development and testing, we encountered several advanced Proxmox, Terraform, and Tailscale gotchas. Here is the full log of what was solved:

### 1. Terraform `.tfvars` Function Limitation
*   **Gotcha:** Running `file()` functions inside `terraform.tfvars` failed with `Error: Function calls not allowed. Functions may not be called here.` in Terraform.
*   **Solution:** Migrated the variable to `ssh_public_key_path` (storing the path as a string) and implemented the dynamic file loading inside `main.tf` using `trimspace(file(pathexpand(var.ssh_public_key_path)))`. The `pathexpand()` function automatically expands tildes (`~`) to the correct home directory on both Windows and Linux hosts!

### 2. Proxmox API Token Permission Block (`HTTP 403`)
*   **Gotcha:** Terraform failed to query datastores or query download file metadata, returning `Reason: Permission check failed (/storage/local, Datastore.Audit|Datastore.AllocateSpace)`.
*   **Solution:** By default, PVE API Tokens are created with **Privilege Separation: Yes** which has no permissions. This was resolved by unchecking Privilege Separation on the API token (so it inherits full `root` admin rights securely) or manually assigning permissions to the API Token under *Datacenter > Permissions*.

### 3. Tailscale Routing Failure to Fresh VMs
*   **Gotcha:** Freshly provisioned VMs do not have Tailscale installed. Running Ansible from a remote machine over Tailscale failed to connect to the VMs' static LAN IPs (`192.168.31.x`).
*   **Solution:** Turned the Proxmox host into a **Tailscale Subnet Router** to advertise the LAN range (`192.168.31.0/24`). 
    *   To make it functional, **IP Forwarding** was enabled on the Proxmox host kernel:
        ```bash
        sysctl -w net.ipv4.ip_forward=1
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        ```
    *   This allowed the remote machine to route traffic directly to the fresh VMs' static IPs through the host without installing Tailscale inside the guest VMs!

### 4. VM Provisioning Hang (QEMU Guest Agent Waiting)
*   **Gotcha:** Terraform would hang for 15 minutes waiting for the QEMU Guest Agent to respond, because `agent.enabled = true` was active in the HCL configuration, but the agent was not yet installed inside the raw Ubuntu Cloud image.
*   **Solution:** Set `agent.enabled = false` inside `main.tf` and routed baseline package setup (installing Docker, QEMU agent, vim, git, hosts mappings) to the very beginning of the Ansible bootstrap playbook. This makes Terraform VM creation **instant and SSH-free** (less than 20 seconds total!), allowing Ansible to handle guest baseline configuration with highly visible error retries.

### 5. Aborted Run Refresh Hang
*   **Gotcha:** Interrupting a running `terraform apply` (`Ctrl + C`) left the active VMs with `agent.enabled = true` in Proxmox. The next `terraform apply` hung during the initial `Refreshing state...` stage as the provider tried to query non-existent guest agent ports over the network.
*   **Solution:** Resolved by running the apply once with the **`-refresh=false`** flag:
    ```powershell
    terraform apply -refresh=false -auto-approve
    ```
    This completely bypassed the active guest-network check, updated the VM settings to `agent.enabled = false` in 4 seconds, and restored instant execution on all subsequent runs!

---

## 🚀 Quickstart Instructions

### Step 1: Populate Secrets
1. Copy the global `.env.example` in the project root to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Populate `.env` with your API Tokens, VM public key file paths, and local SSH private key path:
   *   `TF_VAR_proxmox_api_token`: Your PVE API token value.
   *   `TF_VAR_ssh_public_key_path`: The local path to your public key (e.g. `C:/Users/username/.ssh/id_rsa.pub`).
   *   `PROXMOX_PRIVATE_KEY`: The path to the private key used by Ansible to connect.

3. Sourced environment variables:
    *   **WSL / Linux (Bash/Zsh):**
        ```bash
        source .env
        ```
    *   **Windows (PowerShell):**
        ```powershell
        . scripts/load-env.ps1
        ```

### Step 2: Customize non-sensitive variables
Duplicate `terraform/proxmox/terraform.tfvars.example` to `terraform/proxmox/terraform.tfvars` and customize your local IP prefix (`192.168.31`), gateways, datastore name (`HDD-LVM`), and network bridges (`vmbr0`).

### Step 3: Run Terraform
Navigate to the module directory and deploy:
```bash
cd terraform/proxmox
terraform init
terraform apply -auto-approve
```
*(If resuming from a previous aborted run, run: `terraform apply -refresh=false -auto-approve`)*

### Step 4: Run Ansible Bootstrap
Navigate to the project root and kick off the bootstrap playbooks:
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/k3s-bootstrap.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/registry-vm.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-app.yml
```
