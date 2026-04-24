#------------------------------------------------------------------------------
# Module Outputs — LXC Watchdog
#------------------------------------------------------------------------------
# Expose stable identifiers for downstream Ansible inventory / pipelines.
#------------------------------------------------------------------------------

output "lxc_id" {
  description = "Proxmox VM/CT ID of the LXC container."
  value       = proxmox_virtual_environment_container.watchdog.vm_id
}

output "lxc_name" {
  description = "Hostname / name of the LXC container."
  value       = var.hostname
}

output "lxc_status" {
  description = "Current runtime status of the container (true = started, false = stopped)."
  value       = proxmox_virtual_environment_container.watchdog.started
}

output "lxc_ipv4_address" {
  description = "Configured IPv4 address of the container (from initialization block)."
  value       = var.ip_address
}

output "lxc_node" {
  description = "Proxmox node hosting the container."
  value       = proxmox_virtual_environment_container.watchdog.node_name
}
