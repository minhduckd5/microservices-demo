# Variable definitions for the Proxmox VE Terraform module

variable "proxmox_api_endpoint" {
  type        = string
  description = "The Proxmox VE API endpoint URL (e.g. https://192.168.1.100:8006/)"
}

variable "proxmox_api_token" {
  type        = string
  description = "The Proxmox VE API token (e.g. root@pam!token_name=token_uuid)"
  sensitive   = true
}

variable "proxmox_insecure" {
  type        = bool
  description = "Disable SSL verification for self-signed certificates"
  default     = true
}

variable "proxmox_node" {
  type        = string
  description = "The Proxmox VE node to provision resources on"
  default     = "pve"
}

variable "disk_datastore" {
  type        = string
  description = "The target datastore for virtual machine disks (e.g., HDD-LVM or local-lvm)"
  default     = "HDD-LVM"
}

variable "network_bridge" {
  type        = string
  description = "The Proxmox network bridge interface"
  default     = "vmbr0"
}

variable "gateway_ip" {
  type        = string
  description = "The gateway IP address for the VMs"
  default     = "192.168.31.1"
}

variable "ip_prefix" {
  type        = string
  description = "The IP address prefix (first three octets) for static IPs (e.g. 192.168.1)"
  default     = "192.168.31"
}

variable "dns_servers" {
  type        = list(string)
  description = "The DNS servers to configure in the VMs"
  default     = ["8.8.8.8", "1.1.1.1"]
}

variable "ssh_public_key_path" {
  type        = string
  description = "The path to the local SSH public key file to authorize for the 'vagrant' user in the VMs"
  default     = "~/.ssh/id_rsa.pub"
}

variable "proxmox_ssh_agent" {
  type        = bool
  description = "Enable SSH agent authentication for file uploads to Proxmox node"
  default     = true
}

variable "proxmox_ssh_username" {
  type        = string
  description = "The SSH username for direct node access (usually root)"
  default     = "root"
}

variable "proxmox_ssh_password" {
  type        = string
  description = "The SSH password for direct node access (optional if using ssh-agent)"
  default     = null
  sensitive   = true
}

variable "machines" {
  type = map(object({
    name      = string
    ip        = string
    vm_id     = number
    cores     = number
    memory    = number
    disk_size = number
  }))
  description = "Map of virtual machine configurations matching the Vagrant specs"
  default = {
    "k3s-control" = {
      name      = "k3s-control"
      ip        = "192.168.31.210"
      vm_id     = 210
      cores     = 2
      memory    = 4096
      disk_size = 20
    }
    "k3s-worker1" = {
      name      = "k3s-worker1"
      ip        = "192.168.31.211"
      vm_id     = 211
      cores     = 2
      memory    = 2048
      disk_size = 20
    }
    "k3s-worker2" = {
      name      = "k3s-worker2"
      ip        = "192.168.31.212"
      vm_id     = 212
      cores     = 2
      memory    = 2048
      disk_size = 20
    }
    "registry-vm" = {
      name      = "registry-vm"
      ip        = "192.168.31.220"
      vm_id     = 220
      cores     = 2
      memory    = 2048
      disk_size = 20
    }
  }
}
