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

data "proxmox_virtual_environment_vm" "template" {
  node_name = var.proxmox_node
  vm_id     = var.ubuntu_template_id
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

resource "proxmox_virtual_environment_file" "cloud_init_userdata_watchdog" {
  content_type = "snippets"
  datastore_id = var.cloud_init_storage
  node_name    = var.proxmox_node

  source_file {
    path = local_file.cloud_init_userdata_watchdog.filename
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_network_watchdog" {
  content_type = "snippets"
  datastore_id = var.cloud_init_storage
  node_name    = var.proxmox_node

  source_file {
    path = local_file.cloud_init_network_watchdog.filename
  }
}

resource "proxmox_virtual_environment_vm" "mcp_watchdog" {
  name        = "${var.env_name}-mcp-watchdog"
  description = "MCP Watchdog — Autonomous Operations Agent (polling + webhook + auto-remediation)"
  node_name   = var.proxmox_node
  vm_id       = 119

  clone {
    vm_id = var.ubuntu_template_id
    full  = true
  }

  cpu {
    architecture = "x86_64"
    cores        = 2
    sockets      = 1
    type         = "host"
  }

  memory {
    dedicated = 4096
    floating  = 4096
  }

  disk {
    datastore_id = var.vm_disk_storage
    interface    = "virtio0"
    iothread     = true
    size         = "32G"
    discard      = "on"
  }

  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    tag      = 10
    firewall = true
  }

  serial_device {
    device = "socket"
  }

  cloud_init {
    datastore_id = var.cloud_init_storage
    user_data {
      file_id = proxmox_virtual_environment_file.cloud_init_userdata_watchdog.id
    }
    network_data {
      file_id = proxmox_virtual_environment_file.cloud_init_network_watchdog.id
    }
  }

  boot {
    order = ["virtio0"]
  }

  agent {
    enabled = true
  }

  started = false
  on_boot = true

  timeout {
    migrate  = 180
    shutdown = 300
  }
}

resource "proxmox_virtual_environment_firewall_security_group" "watchdog_service" {
  name = "watchdog-service"
  rule {
    type    = "in"
    action  = "accept"
    proto   = "tcp"
    dport   = "8080"
    source  = "203.0.113.0/24"
    comment = "Watchdog webhook listener from internal"
  }
  rule {
    type    = "in"
    action  = "accept"
    proto   = "tcp"
    dport   = "22"
    source  = "203.0.113.0/24"
    comment = "SSH from services VLAN (Ansible)"
  }
  rule {
    type    = "out"
    action  = "accept"
    proto   = "tcp"
    dport   = "22"
    dest    = "203.0.113.0/24"
    comment = "SSH to all VMs for Ansible remediation"
  }
  rule {
    type    = "out"
    action  = "accept"
    proto   = "tcp"
    dport   = "4566"
    dest    = "0.0.0.0/0"
    comment = "LocalStack S3 API access"
  }
  rule {
    type    = "out"
    action  = "accept"
    proto   = "tcp"
    dport   = "3000"
    source  = "203.0.113.0/24"
    comment = "Forgejo API access"
  }
}