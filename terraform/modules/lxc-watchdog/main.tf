#------------------------------------------------------------------------------
# LXC Watchdog Module — main.tf
#------------------------------------------------------------------------------
# Deploys an unprivileged Proxmox LXC container for the MCP Watchdog.
#
# DevSecOps best practices applied:
#   • Unprivileged container (isolated UIDs/GIDs)
#   • Kernel features enabled (nesting + keyctl) for Goss security audits
#   • Static IP via initialization block (LXC "cloud-init")
#   • Tags ignored in lifecycle to avoid perpetual diffs (Proxmox lowercases)
#   • No serial_device (QEMU-only artifact)
#------------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "watchdog" {
  node_name     = var.proxmox_node
  vm_id         = var.vm_id
  description   = var.description
  tags          = var.tags
  unprivileged  = true
  start_on_boot = true

  #----------------------------------------------------------------------------
  # Base OS — requires an LXC template pre-downloaded on Proxmox storage.
  #----------------------------------------------------------------------------
  operating_system {
    template_file_id = var.container_template
  }

  #----------------------------------------------------------------------------
  # Compute Resources
  #----------------------------------------------------------------------------
  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_dedicated
    swap      = var.memory_swap
  }

  #----------------------------------------------------------------------------
  # Storage
  #----------------------------------------------------------------------------
  disk {
    datastore_id = var.disk_datastore
    size         = var.disk_size
  }

  #----------------------------------------------------------------------------
  # Networking (single veth on the management/services bridge)
  #----------------------------------------------------------------------------
  network_interface {
    name    = "eth0"
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  #----------------------------------------------------------------------------
  # Initialization — LXC equivalent of cloud-init.
  # Sets hostname, network, root password hash, SSH key, and DNS.
  #----------------------------------------------------------------------------
  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      keys     = [var.ssh_public_key]
      password = var.admin_password_hash
    }

    dns {
      domain = var.domain_name
      servers = var.dns_servers
    }
  }

  #----------------------------------------------------------------------------
  # Kernel Features
  # nesting  = allows nested containers / privileged operations inside CT
  # keyctl   = required by Goss for kernel-level security assertions
  #----------------------------------------------------------------------------
  features {
    nesting = true
    keyctl  = true
  }

  #----------------------------------------------------------------------------
  # Lifecycle Guards
  # Proxmox REST API normalises tag casing; ignoring tags prevents
  # perpetual "tags => ["ASIP"] -> ["asip"]" diffs on every plan.
  #----------------------------------------------------------------------------
  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}
