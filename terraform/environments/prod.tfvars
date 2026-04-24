# ASIP Terraform Variables — Production
# Copy this file to prod.tfvars and fill in sensitive values

proxmox_endpoint   = "https://REDACTED_PROXMOX_HOST:8006"
proxmox_user       = "root@pam"
proxmox_token      = "CHANGE_ME:terraform token value"
proxmox_insecure   = true
proxmox_node       = "pve"
env_name           = "prod"
domain_name        = "corp.local"
admin_ssh_key       = "CHANGE_ME: ssh-ed25519 AAAA..."
admin_password_hash = "CHANGE_ME: hashed password"