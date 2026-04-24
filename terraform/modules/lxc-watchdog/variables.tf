#------------------------------------------------------------------------------
# Module Variables — LXC Watchdog
#------------------------------------------------------------------------------
# All variables are strongly typed and documented for CI/CD-driven reuse.
#------------------------------------------------------------------------------

variable "proxmox_node" {
  description = "Proxmox node name where the LXC container will be deployed."
  type        = string
  default     = "pve"
}

variable "vm_id" {
  description = "Unique VM/CT ID for the LXC container."
  type        = number
  default     = 119
}

variable "hostname" {
  description = "Hostname of the LXC container."
  type        = string
  default     = "mcp-watchdog"
}

variable "description" {
  description = "Human-readable description of the container's role."
  type        = string
  default     = "MCP Watchdog — Autonomous Operations Agent"
}

variable "ip_address" {
  description = "IPv4 address with CIDR (e.g. 203.0.113.50/24)."
  type        = string
  default     = "203.0.113.50/24"
}

variable "gateway" {
  description = "Default IPv4 gateway."
  type        = string
  default     = "203.0.113.1"
}

variable "vlan_id" {
  description = "VLAN tag for the container network interface."
  type        = number
  default     = 10
}

variable "bridge" {
  description = "Proxmox bridge to attach the container to."
  type        = string
  default     = "vmbr0"
}

variable "dns_servers" {
  description = "List of DNS servers for the container."
  type        = list(string)
  default     = ["203.0.113.1"]
}

variable "domain_name" {
  description = "DNS domain name for the container."
  type        = string
  default     = "corp.local"
}

variable "ssh_public_key" {
  description = "SSH public key for admin access (passed into root user's authorized_keys)."
  type        = string
}

variable "admin_password_hash" {
  description = "Hashed admin password for the root account (cloud-init / LXC user_account)."
  type        = string
  sensitive   = true
}

variable "cpu_cores" {
  description = "Number of CPU cores allocated to the container."
  type        = number
  default     = 2
}

variable "memory_dedicated" {
  description = "Dedicated RAM in MB."
  type        = number
  default     = 4096
}

variable "memory_swap" {
  description = "Swap size in MB."
  type        = number
  default     = 1024
}

variable "disk_size" {
  description = "Root disk size in GB."
  type        = number
  default     = 32
}

variable "disk_datastore" {
  description = "Proxmox storage ID for the root disk."
  type        = string
  default     = "local-lvm"
}

variable "container_template" {
  description = "LXC template file ID on Proxmox storage (format: <datastore>:vztmpl/<filename>)."
  type        = string
  default     = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
}

variable "tags" {
  description = "Tags for the container in Proxmox. Note: Proxmox API forces lowercase."
  type        = list(string)
  default     = ["asip", "watchdog", "autonomous-ops"]
}
