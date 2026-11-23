locals {
  vm_ips = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => coalesce(
      var.vms[name].ip,
      try([for ip in flatten(vm.ipv4_addresses) : ip if !startswith(ip, "127.")][0], null),
      "unknown"
    )
  }
  ssh_private_key = trimsuffix(var.ssh_public_key_path, ".pub")
}

output "vm_ips" {
  description = "IPv4 address of each VM (static if set, otherwise reported by the guest agent)"
  value       = local.vm_ips
}

output "vm_ids" {
  description = "Proxmox VMID of each VM"
  value       = { for name, vm in proxmox_virtual_environment_vm.vm : name => vm.vm_id }
}

output "vm_macs" {
  description = "MAC address of each VM's first NIC"
  value       = { for name, vm in proxmox_virtual_environment_vm.vm : name => vm.network_device[0].mac_address }
}

output "ssh_commands" {
  description = "Ready-to-use SSH command for each VM"
  value = {
    for name, ip in local.vm_ips :
    name => "ssh -i ${local.ssh_private_key} ${var.vm_username}@${ip}"
  }
}

output "ansible_inventory_file" {
  description = "Ansible inventory generated from the VM IPs"
  value       = abspath(local_file.ansible_inventory.filename)
}
