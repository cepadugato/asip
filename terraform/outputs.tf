output "mcp_watchdog_ip" {
  description = "MCP Watchdog LXC IP address"
  value       = "203.0.113.50"
}

output "mcp_watchdog_vm_id" {
  description = "MCP Watchdog LXC CT ID"
  value       = module.lxc_watchdog.lxc_id
}

output "mcp_watchdog_name" {
  description = "MCP Watchdog LXC hostname"
  value       = module.lxc_watchdog.lxc_name
}

output "watchdog_endpoints" {
  description = "MCP Watchdog service endpoints"
  value = {
    webhook_url = "http://203.0.113.50:8080/webhook/goss"
    api_url     = "http://203.0.113.50:8080/status"
  }
}