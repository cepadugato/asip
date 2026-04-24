terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.61"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  backend "http" {
    address        = "http://localhost:3000/api/state/asip"
    lock_address   = "http://localhost:3000/api/state/asip/lock"
    unlock_address = "http://localhost:3000/api/state/asip/lock"
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  username  = var.proxmox_user
  api_token = var.proxmox_token
  insecure  = var.proxmox_insecure
  tmp_dir   = "/var/tmp"
}

locals {
  asip_tags = {
    ManagedBy = "asip-terraform"
    Project   = "ASIP"
  }
}

resource "local_file" "cloud_init_userdata_watchdog" {
  content = templatefile(
    "${path.module}/../../infra-proxmox/cloud-init/user-data.tpl",
    {
      hostname        = "mcp-watchdog"
      domain_name     = var.domain_name
      ssh_public_key  = var.admin_ssh_key
      admin_password  = var.admin_password_hash
      vm_role         = "mcp-watchdog"
    }
  )
  filename        = "${path.module}/../cloud-init/mcp-watchdog/user-data"
  file_permission = "0644"
}

resource "local_file" "cloud_init_network_watchdog" {
  content = templatefile(
    "${path.module}/../../infra-proxmox/cloud-init/network-config.tpl",
    {
      ip         = "203.0.113.50"
      vlan       = 10
      gateway    = var.network_config.mgmt_gateway
      nameserver = var.network_config.nameserver
    }
  )
  filename        = "${path.module}/../cloud-init/mcp-watchdog/network-config"
  file_permission = "0644"
}

resource "local_file" "cloud_init_metadata_watchdog" {
  content = templatefile(
    "${path.module}/../../infra-proxmox/cloud-init/meta-data.tpl",
    {
      hostname    = "mcp-watchdog"
      domain_name = var.domain_name
    }
  )
  filename        = "${path.module}/../cloud-init/mcp-watchdog/meta-data"
  file_permission = "0644"
}

module "lxc_watchdog" {
  source = "./modules/lxc-watchdog"

  proxmox_node      = var.proxmox_node
  vm_id             = 119
  hostname          = "mcp-watchdog"
  description       = "MCP Watchdog — Autonomous Operations Agent (polling + webhook + auto-remediation)"
  ip_address        = "203.0.113.50/24"
  gateway           = var.network_config.mgmt_gateway
  vlan_id           = var.network_config.management_vlan
  bridge            = var.network_config.wan_interface
  dns_servers       = [var.network_config.nameserver]
  domain_name       = var.domain_name
  ssh_public_key    = var.admin_ssh_key
  admin_password_hash = var.admin_password_hash
  cpu_cores         = 2
  memory_dedicated  = 4096
  memory_swap       = 1024
  disk_size         = 32
  disk_datastore    = var.vm_disk_storage
  container_template = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
  tags              = ["asip", "watchdog", "autonomous-ops"]
}