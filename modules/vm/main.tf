# A project VM: full clone of the golden NixOS template with the platform's
# machine shape (q35, OVMF without Secure Boot keys, fresh vTPM, virtio-scsi-single,
# QEMU guest agent, serial console) and the project's two networks.
#
# OpenTofu stops at the machine. The guest converges with
#   nixos-rebuild switch --flake .#<name> --target-host ops@<ip> --sudo
# against the address the guest agent reports (outputs below).
resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  description = var.description
  node_name   = var.node
  vm_id       = var.vm_id
  pool_id     = var.pool
  tags        = sort(concat(["nixos"], var.tags))

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]
  on_boot       = var.on_boot
  protection    = var.protection != null ? var.protection : length(var.data_disks) > 0

  agent {
    enabled = true
    timeout = "5m"
  }

  cpu {
    cores = var.cores
    type  = "host"
    numa  = true
  }

  memory {
    dedicated = var.memory_mib
    floating  = var.balloon_mib
  }

  efi_disk {
    datastore_id      = var.storage
    type              = "4m"
    pre_enrolled_keys = false # the template ships a key-free vars store; Secure Boot stays off
  }

  # The template has no TPM on purpose: adding it here makes PVE generate a
  # unique endorsement key per VM instead of cloning the template's.
  tpm_state {
    datastore_id = var.storage
    version      = "v2.0"
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.storage
    size         = var.os_disk_gib
    discard      = "on"
    iothread     = true
    ssd          = contains(var.ssd_storages, var.storage)
    file_format  = "raw"
  }

  dynamic "disk" {
    for_each = var.data_disks
    content {
      interface    = "scsi${disk.key + 1}"
      datastore_id = coalesce(disk.value.storage, var.storage)
      size         = disk.value.size_gib
      discard      = "on"
      iothread     = true
      ssd          = contains(var.ssd_storages, coalesce(disk.value.storage, var.storage))
      backup       = disk.value.backup
      file_format  = "raw"
    }
  }

  # net0 -> ens18: LAN, internet, Tailscale.
  network_device {
    bridge   = var.public_bridge
    model    = "virtio"
    firewall = var.pve_firewall
  }

  # net1 -> ens19: the project's private VNet (DHCP from PVE IPAM, no default route).
  # Jumbo (matches the zone MTU) and virtio multiqueue: one queue per core, capped
  # at PVE's limit of 64. The guest module sets the same MTU on the interface.
  dynamic "network_device" {
    for_each = var.private_vnet == null ? [] : [var.private_vnet]
    content {
      bridge = network_device.value
      model  = "virtio"
      mtu    = var.private_mtu
      queues = min(var.cores, 64)
    }
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [
      clone, # create-time only; changing the template input must not replace existing VMs
    ]
  }
}