# Terraform configuration for Proxmox VE provider using bpg/proxmox

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.69.1"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  # SSH configuration is required by the provider to import/copy VM disks on the host.
  ssh {
    agent    = var.proxmox_ssh_agent
    username = var.proxmox_ssh_username
    password = var.proxmox_ssh_password
  }
}
