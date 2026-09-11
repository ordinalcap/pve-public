locals {
  ifaces = proxmox_virtual_environment_vm.this.network_interface_names
  addrs  = proxmox_virtual_environment_vm.this.ipv4_addresses
  by_if  = { for i, n in local.ifaces : n => try(local.addrs[i][0], null) }
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  value = proxmox_virtual_environment_vm.this.name
}

output "public_ipv4" {
  description = "DHCP address on the public NIC (ens18) as reported by the guest agent; first deploy target."
  value       = lookup(local.by_if, "ens18", null)
}

output "private_ipv4" {
  description = "Stable PVE-IPAM address on the project VNet (ens19)."
  value       = lookup(local.by_if, "ens19", null)
}

output "mac_addresses" {
  value = proxmox_virtual_environment_vm.this.mac_addresses
}