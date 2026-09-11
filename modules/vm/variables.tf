variable "name" {
  description = "VM display name; convention: <project>-<role>."
  type        = string
}
variable "vm_id" {
  description = "VMID allocated from the platform handoff; the caller owns range selection."
  type        = number
}
variable "pool" {
  description = "Resource pool authorized for this project."
  type        = string
}
variable "node" {
  description = "Proxmox node from the platform handoff."
  type        = string
}
variable "template_vmid" {
  description = "Platform-provided NixOS template VMID. This is a resource identity, not an immutable image digest."
  type        = number
}
variable "storage" {
  description = "Authorized datastore for OS, EFI, TPM, and data disks without an override."
  type        = string
}
variable "ssd_storages" {
  description = "Authorized SSD datastores from the platform handoff; controls SSD emulation without guessing from names."
  type        = list(string)
}
variable "public_bridge" {
  description = "Authorized public bridge from the platform handoff."
  type        = string
}
variable "private_mtu" {
  description = "Private VNet zone MTU from the handoff; use the same value in the guest."
  type        = number
}
variable "cores" {
  type = number
}
variable "memory_mib" {
  description = "Dedicated memory. Ballooning is off unless balloon_mib is set."
  type        = number
}
variable "balloon_mib" {
  description = "Minimum memory with ballooning enabled; 0 disables it."
  type        = number
  default     = 0
}
variable "os_disk_gib" {
  description = "Root disk size; the clone grows the template's 32 GiB partition on first boot."
  type        = number
  default     = 32
  validation {
    condition     = var.os_disk_gib >= 32
    error_message = "The template root disk is 32 GiB and cannot be shrunk."
  }
}
variable "data_disks" {
  description = "Append-only data disks at scsi1, scsi2, etc. Omitted storage uses var.storage. Removing an entry deletes its disk; growing requires guest filesystem growth."
  type = list(object({
    size_gib = number
    storage  = optional(string)
    backup   = optional(bool, true)
  }))
  default = []
}
variable "private_vnet" {
  description = "Authorized project VNet; null omits the private NIC."
  type        = string
  default     = null
}
variable "pve_firewall" {
  description = "Enable the PVE firewall on the public NIC; rules remain a platform/project responsibility."
  type        = bool
  default     = true
}
variable "tags" {
  type    = list(string)
  default = []
}
variable "on_boot" {
  type    = bool
  default = true
}
variable "protection" {
  description = "Refuse VM/disk removal until cleared. null enables protection for VMs carrying data disks."
  type        = bool
  default     = null
}
variable "description" {
  type    = string
  default = ""
}
