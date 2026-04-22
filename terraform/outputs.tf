output "mcp_watchdog_ip" {
  description = "MCP Watchdog VM IP address"
  value       = "10.10.10.50"
}

output "mcp_watchdog_vm_id" {
  description = "MCP Watchdog VM ID"
  value       = proxmox_virtual_environment_vm.mcp_watchdog.vm_id
}

output "mcp_watchdog_name" {
  description = "MCP Watchdog VM name"
  value       = proxmox_virtual_environment_vm.mcp_watchdog.name
}

output "watchdog_endpoints" {
  description = "MCP Watchdog service endpoints"
  value = {
    webhook_url = "http://10.10.10.50:8080/webhook/goss"
    api_url     = "http://10.10.10.50:8080/status"
  }
}

output "firewall_security_group" {
  description = "Watchdog firewall security group name"
  value       = proxmox_virtual_environment_firewall_security_group.watchdog_service.name
}