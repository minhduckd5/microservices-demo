# Quickstart: Proxmox VE Terraform Deployment

This guide explains how to deploy the **Online Boutique** on-premises microservices architecture onto a **Proxmox VE (PVE) 8.x/9.x** node using Terraform and Ansible.

This setup provisions 4 virtual machines matching the Vagrant foot-print:
- `k3s-control` (`192.168.1.210`) - Kubernetes control-plane
- `k3s-worker1` (`192.168.1.211`) - Kubernetes worker node 1
- `k3s-worker2` (`192.168.1.212`) - Kubernetes worker node 2
- `registry-vm` (`192.168.1.220`) - Local insecure image registry

---

## Prerequisites

1. **Terraform / OpenTofu** installed locally.
2. **Ansible** installed locally or inside WSL.
3. A **Proxmox VE** node running (Version 8.x or 9.x recommended).
4. An **API Token** created in PVE (*Datacenter > Permissions > API Tokens*) with standard privileges (e.g. `root@pam!root-token`).
5. SSH access to the PVE node enabled (needed by the provider for snippet uploads).

---

## Step 1: Configure Terraform & Ansible Secrets

You can manage your secrets (API tokens, SSH passwords, keys) securely using an environment file instead of hardcoding them:

1. Navigate to the repository root directory (where `.env.example` resides) and copy the example:
   ```bash
   cp .env.example .env
   ```

2. Open the newly created `.env` in your editor and populate the secrets:
   - `TF_VAR_proxmox_api_token`: Your Proxmox API token.
   - `TF_VAR_proxmox_ssh_password`: SSH password for snippet uploads (if not using ssh-agent).
   - `TF_VAR_ssh_public_key`: Your SSH public key (authorized on the guest VMs).
   - `PROXMOX_PRIVATE_KEY`: Local private key path used by Ansible to connect to the VMs.

3. Source the environment secrets in your active terminal:
   - **WSL / Linux / macOS (Bash/Zsh):**
     ```bash
     source .env
     ```
   - **Windows (PowerShell):**
     ```powershell
     . scripts/load-env.ps1
     ```

4. (Optional) Customize non-sensitive variables (e.g. node names, bridges, storage datastores) in `terraform/proxmox/terraform.tfvars`:
   ```bash
   cd terraform/proxmox
   cp terraform.tfvars.example terraform.tfvars
   # Open terraform.tfvars and change non-sensitive variables.
   ```

---

## Step 2: Deploy Infrastructure

1. Initialize Terraform and download the PVE provider:
   ```bash
   terraform init
   ```

2. Verify the deployment plan:
   ```bash
   terraform plan
   ```

3. Deploy the virtual machines:
   ```bash
   terraform apply -auto-approve
   ```

*Note: The provider will automatically download the official Ubuntu 24.04 Cloud-Init image to your PVE node, upload custom cloud-init user data snippets via SSH, and provision the 4 virtual machines.*

---

## Step 3: Run Ansible Setup

Since the Terraform VMs maintain the exact same username (`vagrant`) and static IP allocations, you can reuse your existing Ansible playbooks seamlessly!

1. Set your SSH private key path as an environment variable (or run with CLI arguments):
   ```bash
   export PROXMOX_PRIVATE_KEY="~/.ssh/id_rsa"
   ```

2. Bootstrap K3s cluster:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/k3s-bootstrap.yml
   ```

3. Provision local image registry:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/registry-vm.yml
   ```

4. Build and deploy the Online Boutique microservices:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-app.yml
   ```

---

## Step 4: Verify Deployment

Once the plays complete successfully, you can verify your cluster:

1. Fetch your dynamic K3s kubeconfig:
   ```bash
   export KUBECONFIG=./ansible/playbooks/k3s-kubeconfig
   ```

2. Verify all nodes are ready:
   ```bash
   kubectl get nodes
   ```

3. Access your Online Boutique frontend:
   Open `http://192.168.1.210` (or `http://boutique.internal` if mapped in `/etc/hosts`) in your browser.
