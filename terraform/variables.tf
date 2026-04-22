variable "proxmox_endpoint" {
  description = "Proxmox VE API URL"
  type        = string
  default     = "https://192.168.100.254:8006"
}

variable "proxmox_user" {
  description = "Proxmox API user"
  type        = string
  default     = "root@pam"
}

variable "proxmox_token" {
  description = "Proxmox API token (sensitive)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "env_name" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "AD domain name"
  type        = string
  default     = "corp.local"
}

variable "admin_ssh_key" {
  description = "SSH public key for admin access"
  type        = string
}

variable "admin_password_hash" {
  description = "Hashed admin password for cloud-init"
  type        = string
  sensitive   = true
}

variable "ubuntu_template_id" {
  description = "Ubuntu cloud-init template VM ID"
  type        = number
  default     = 9000
}

variable "vm_disk_storage" {
  description = "Proxmox storage for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "cloud_init_storage" {
  description = "Proxmox storage for cloud-init snippets"
  type        = string
  default     = "local"
}

variable "network_config" {
  description = "Network VLAN configuration (references infra-proxmox)"
  type = object({
    management_vlan  = number
    services_vlan    = number
    collab_vlan      = number
    clients_vlan     = number
    dmz_vlan          = number
    mgmt_subnet      = string
    svc_subnet       = string
    collab_subnet    = string
    client_subnet    = string
    dmz_subnet       = string
    pg_subnet        = string
    nameserver       = string
    mgmt_gateway     = string
    svc_gateway      = string
    collab_gateway   = string
    client_gateway   = string
    dmz_gateway      = string
    wan_interface    = string
  })
  default = {
    management_vlan = 10
    services_vlan   = 20
    collab_vlan     = 30
    clients_vlan    = 40
    dmz_vlan         = 50
    mgmt_subnet      = "10.10.10"
    svc_subnet       = "10.10.20"
    collab_subnet    = "10.10.30"
    client_subnet    = "10.10.40"
    dmz_subnet       = "10.10.50"
    pg_subnet        = "10.10.10"
    nameserver       = "10.10.20.10"
    mgmt_gateway     = "10.10.10.1"
    svc_gateway      = "10.10.20.1"
    collab_gateway   = "10.10.30.1"
    client_gateway   = "10.10.40.1"
    dmz_gateway      = "10.10.50.1"
    wan_interface    = "vmbr0"
  }
}