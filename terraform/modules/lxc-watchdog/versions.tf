#------------------------------------------------------------------------------
# Provider Constraints
#------------------------------------------------------------------------------
# Pin bpg/proxmox to the validated minor version used across the ASIP project.
#------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.61"
    }
  }
}
