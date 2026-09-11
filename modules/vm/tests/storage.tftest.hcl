mock_provider "proxmox" {}
variables {
  name          = "example-data"
  vm_id         = 1001
  pool          = "example"
  node          = "node-example"
  template_vmid = 900
  storage       = "fast-store"
  ssd_storages  = ["fast-store"]
  public_bridge = "br-public"
  private_mtu   = 1500
  cores         = 2
  memory_mib    = 2048
}
run "data_disk_inherits_storage_and_enables_protection" {
  command = plan
  variables { data_disks = [{ size_gib = 64 }] }
  assert {
    condition     = proxmox_virtual_environment_vm.this.protection
    error_message = "Data-bearing VMs must be protected unless explicitly overridden."
  }
  assert {
    condition     = alltrue([for disk in proxmox_virtual_environment_vm.this.disk : disk.datastore_id == "fast-store" && disk.ssd])
    error_message = "OS and implicit data storage must use the handed-off SSD datastore, independent of its name."
  }
}
run "explicit_bulk_disk_does_not_emulate_ssd" {
  command = plan
  variables {
    data_disks = [{ size_gib = 64, storage = "bulk-store", backup = false }]
    protection = false
  }
  assert {
    condition     = !proxmox_virtual_environment_vm.this.protection
    error_message = "The operator must be able to explicitly clear protection before removal."
  }
  assert {
    condition     = alltrue([for disk in proxmox_virtual_environment_vm.this.disk : disk.interface != "scsi1" || (disk.datastore_id == "bulk-store" && !disk.ssd && !disk.backup)])
    error_message = "Explicit bulk storage must retain its non-SSD and backup policy."
  }
}
