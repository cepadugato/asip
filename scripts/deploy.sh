#!/bin/bash -euo pipefail
# -------------------------------------------------------------------------------------------------
# deploy.sh — ASIP Zero-Touch Infrastructure Deployment
# Orchestrates: Terraform → Ansible → LocalStack → MCP Watchdog → Verify
# References infra-proxmox/ for existing roles and Terraform
# -------------------------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_ROOT="${PROJECT_ROOT}/../infra-proxmox"
TF_DIR="${PROJECT_ROOT}/terraform"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
LOCALSTACK_DIR="${PROJECT_ROOT}/localstack"
SSH_USER="${SSH_USER:-ansible}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" >&2; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

# -------------------------------------------------------------------------------------------------
# Step 0: Prerequisites check
# -------------------------------------------------------------------------------------------------
check_prereqs() {
    log "=== Checking prerequisites ==="
    for cmd in terraform ansible-playbook python3 docker; do
        command -v "$cmd" &>/dev/null || err "Required command not found: $cmd"
    done
    [ -f "${SSH_KEY}" ] || warn "SSH key not found at ${SSH_KEY} — some steps may require manual setup"
    log "All prerequisites satisfied"
}

# -------------------------------------------------------------------------------------------------
# Step 1: Start LocalStack (S3 + IAM simulation)
# -------------------------------------------------------------------------------------------------
start_localstack() {
    log "=== Step 1: Starting LocalStack ==="
    cd "${LOCALSTACK_DIR}"
    docker compose up -d
    log "Waiting for LocalStack to be ready..."
    retries=0
    while [ ${retries} -lt 30 ]; do
        if curl -sf http://localhost:4566/_localstack/health &>/dev/null; then
            log "LocalStack is ready"
            break
        fi
        retries=$((retries + 1))
        log "Waiting for LocalStack... attempt ${retries}/30"
        sleep 5
    done
    if [ ${retries} -eq 30 ]; then
        err "LocalStack not ready after 2.5 minutes"
    fi

    log "Provisioning LocalStack with Terraform..."
    pip install terraform-local 2>/dev/null || true
    cd "${LOCALSTACK_DIR}/terraform"
    tflocal init -upgrade
    tflocal plan -out=tfplan
    tflocal apply -auto-approve tfplan
    cd "${PROJECT_ROOT}"
    log "LocalStack provisioning complete"
}

# -------------------------------------------------------------------------------------------------
# Step 2: Deploy existing infrastructure (references infra-proxmox)
# -------------------------------------------------------------------------------------------------
deploy_infra() {
    log "=== Step 2: Deploying existing infrastructure ==="
    if [ -x "${INFRA_ROOT}/scripts/deploy.sh" ]; then
        "${INFRA_ROOT}/scripts/deploy.sh" all
    else
        warn "infra-proxmox deploy.sh not found — running Terraform + Ansible manually"
        terraform -chdir="${INFRA_ROOT}/terraform" init -upgrade
        terraform -chdir="${INFRA_ROOT}/terraform" plan -parallelism=1 -var-file="${INFRA_ROOT}/terraform/environments/prod.tfvars" -out=tfplan
        terraform -chdir="${INFRA_ROOT}/terraform" apply -parallelism=1 -auto-approve tfplan
        ansible-playbook -i "${INFRA_ROOT}/ansible/inventory/prod.yml" "${INFRA_ROOT}/ansible/site.yml" --private-key "${SSH_KEY}" -u "${SSH_USER}" -b
    fi
    log "Existing infrastructure deployed"
}

# -------------------------------------------------------------------------------------------------
# Step 3: Deploy ASIP-specific infrastructure (mcp-watchdog VM)
# -------------------------------------------------------------------------------------------------
deploy_asip_infra() {
    log "=== Step 3: Deploying ASIP infrastructure (mcp-watchdog) ==="
    cd "${TF_DIR}"
    terraform init -upgrade
    terraform plan -parallelism=1 -var-file=environments/prod.tfvars -out=tfplan
    terraform apply -parallelism=1 -auto-approve tfplan
    cd "${PROJECT_ROOT}"
    log "ASIP Terraform complete"
}

# -------------------------------------------------------------------------------------------------
# Step 4: Start mcp-watchdog VM
# -------------------------------------------------------------------------------------------------
start_watchdog() {
    log "=== Step 4: Starting mcp-watchdog VM ==="
    VM_ID=119
    PROXMOX_HOST="${PROXMOX_HOST:-192.0.2.10}"
    PROXMOX_NODE="${PROXMOX_NODE:-pve}"

    if command -v qm &>/dev/null; then
        qm start "${VM_ID}" 2>/dev/null || log "Watchdog VM ${VM_ID} may already be running"
    else
        curl -sk -X POST "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/qemu/${VM_ID}/status/start" \
            -H "Authorization: PVEAPIToken ${PROXMOX_API_TOKEN:-root@pam!terraform=changeme}" \
            2>/dev/null || warn "Could not start watchdog VM via API"
    fi

    log "Waiting for SSH on watchdog (203.0.113.50)..."
    retries=0
    while [ ${retries} -lt 60 ]; do
        if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@203.0.113.50" "echo OK" &>/dev/null; then
            log "SSH ready on watchdog (after ${retries} attempts)"
            break
        fi
        retries=$((retries + 1))
        sleep 5
    done
    if [ ${retries} -eq 60 ]; then
        err "SSH not reachable on watchdog after 5 minutes"
    fi
}

# -------------------------------------------------------------------------------------------------
# Step 5: Provision ASIP-specific services (watchdog + hybrid-storage)
# -------------------------------------------------------------------------------------------------
provision_asip() {
    log "=== Step 5: Provisioning ASIP services ==="
    ansible-playbook "${ANSIBLE_DIR}/site.yml" \
        -i "${ANSIBLE_DIR}/inventory/prod.yml" \
        --private-key "${SSH_KEY}" \
        -u "${SSH_USER}" -b \
        --tags "mcp-watchdog,hybrid-storage"

    log "ASIP provisioning complete"
}

# -------------------------------------------------------------------------------------------------
# Step 6: Verify
# -------------------------------------------------------------------------------------------------
verify() {
    log "=== Step 6: Verification ==="
    if [ -x "${SCRIPT_DIR}/verify.sh" ]; then
        "${SCRIPT_DIR}/verify.sh"
    else
        warn "verify.sh not found — skipping"
    fi
}

# -------------------------------------------------------------------------------------------------
# Print summary
# -------------------------------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "========================================================================="
    echo "  A.S.I.P. Deployment Complete"
    echo "========================================================================="
    echo ""
    echo "  ASIP Endpoints:"
    echo "    MCP Watchdog:        http://203.0.113.50:8080/status"
    echo "    Webhook URL:          http://203.0.113.50:8080/webhook/goss"
    echo "    Forgejo:             http://localhost:3000"
    echo "    LocalStack S3:        http://localhost:4566"
    echo ""
    echo "  Existing Infrastructure (from infra-proxmox):"
    echo "    OPNsense:             https://203.0.113.1"
    echo "    Grafana:              http://203.0.113.20:3000"
    echo "    Keycloak:             https://203.0.113.20:8443"
    echo "    Nextcloud:            https://203.0.113.10"
    echo "    Vaultwarden:          https://203.0.113.12"
    echo ""
    echo "  To test autonomous ops:"
    echo "    ./scripts/demo-autonomous.sh"
    echo ""
    echo "  To test hybrid storage:"
    echo "    ./scripts/simulate-hybrid.sh"
    echo "========================================================================="
}

# -------------------------------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------------------------------
main() {
    local step="${1:-all}"

    log "Starting ASIP deployment (step: ${step})"

    case "${step}" in
        prereqs|0)  check_prereqs ;;
        localstack|1) start_localstack ;;
        infra|2)    deploy_infra ;;
        asip-tf|3)  deploy_asip_infra ;;
        start|4)    start_watchdog ;;
        provision|5) provision_asip ;;
        verify|6)   verify ;;
        all)
            check_prereqs
            start_localstack
            deploy_infra
            deploy_asip_infra
            start_watchdog
            provision_asip
            verify
            print_summary
            ;;
        *)
            echo "Usage: $0 {all|prereqs|localstack|infra|asip-tf|start|provision|verify}"
            echo ""
            echo "Steps:"
            echo "  0/prereqs      — Check prerequisites"
            echo "  1/localstack   — Start LocalStack (S3+IAM)"
            echo "  2/infra         — Deploy existing infrastructure (infra-proxmox)"
            echo "  3/asip-tf       — Deploy ASIP Terraform (mcp-watchdog VM)"
            echo "  4/start         — Start mcp-watchdog VM"
            echo "  5/provision     — Provision ASIP services (Ansible)"
            echo "  6/verify        — Run health checks"
            echo "  all             — Run all steps in sequence (default)"
            exit 1
            ;;
    esac

    log "Deployment step '${step}' complete"
}

main "$@"