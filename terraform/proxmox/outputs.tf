# Outputs for Proxmox VE Terraform module to assist Ansible integration

output "vm_ips" {
  value = {
    for k, v in proxmox_virtual_environment_vm.nodes : k => v.initialization[0].ip_config[0].ipv4[0].address
  }
  description = "Assigned IP addresses of the provisioned VMs"
}

output "ansible_inventory_tip" {
  value = <<EOF

================================================================================
=== Proxmox VM Provisioning Complete! ==========================================
================================================================================

Your Proxmox virtual machines are successfully provisioned. Since we preserved
the exact same username ("vagrant") and static IPs as the Vagrant configuration,
your existing Ansible playbooks will work out-of-the-box!

Just update your Ansible run to specify your custom private key:

  ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/k3s-bootstrap.yml --private-key=~/.ssh/id_rsa

================================================================================
EOF
  description = "Instructions for integrating with the existing Ansible playbook pipeline"
}
