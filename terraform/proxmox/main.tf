# Core Proxmox VE VM provisioning configuration matching the Vagrant architecture

# 1. Download official Ubuntu 24.04 LTS cloud-init image to directory storage (local)
resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "noble-server-cloudimg-amd64.img"
}

# 2. Provision the virtual machines mirroring your local Vagrant specifications
resource "proxmox_virtual_environment_vm" "nodes" {
  for_each  = var.machines
  name      = each.value.name
  vm_id     = each.value.vm_id
  node_name = var.proxmox_node

  # High performance SCSI driver
  scsi_hardware = "virtio-scsi-pci"
  on_boot       = true

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X
  }

  agent {
    enabled = false
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES" # Emulated CPU with basic modern feature sets
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.memory # Enables memory ballooning matched to dedicated allocation
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio" # High speed paravirtualized network card
  }

  disk {
    datastore_id = var.disk_datastore
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  initialization {
    # Native Cloud-Init user account creation (completely SSH-free!)
    user_account {
      username = "vagrant"
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.gateway_ip
      }
    }

    dns {
      servers = var.dns_servers
    }
  }

  # Ensure the cloud image is fully downloaded before VM allocation begins
  depends_on = [
    proxmox_download_file.ubuntu_cloud_image
  ]
}
