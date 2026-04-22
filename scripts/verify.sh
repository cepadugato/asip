#!/bin/bash -euo pipefail
# -------------------------------------------------------------------------------------------------
# verify.sh — ASIP Infrastructure Health Checks
# -------------------------------------------------------------------------------------------------

SSH_USER="${SSH_USER:-ansible}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes"
PASS=0
FAIL=0
WARN=0

ok()   { echo "  [OK]   $*"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN+1)); }

echo "========================================================================="
echo "  A.S.I.P. — Infrastructure Verification"
echo "========================================================================="
echo ""

# -------------------------------------------------------------------------------------------------
# LocalStack
# -------------------------------------------------------------------------------------------------
echo "--- LocalStack ---"
if curl -sf http://localhost:4566/_localstack/health 2>/dev/null | grep -q "running"; then
    ok "LocalStack is running"
else
    fail "LocalStack is not running (expected localhost:4566)"
fi

if curl -sf http://localhost:4566/_localstack/health 2>/dev/null | grep -q "s3"; then
    ok "LocalStack S3 service available"
else
    warn "LocalStack S3 service not detected"
fi

S3_BUCKETS=$(docker exec localstack-main awslocal s3 ls 2>/dev/null || echo "")
if echo "$S3_BUCKETS" | grep -q "asip-backup"; then
    ok "S3 bucket 'asip-backup' exists"
else
    fail "S3 bucket 'asip-backup' not found"
fi

if echo "$S3_BUCKETS" | grep -q "asip-documents"; then
    ok "S3 bucket 'asip-documents' exists"
else
    fail "S3 bucket 'asip-documents' not found"
fi

echo ""

# -------------------------------------------------------------------------------------------------
# Proxmox VMs
# -------------------------------------------------------------------------------------------------
echo "--- Proxmox VMs ---"
PROXMOX_HOST="${PROXMOX_HOST:-192.168.100.254}"
PROXMOX_NODE="${PROXMOX_NODE:-pve}"

for vm_ip in 10.10.10.5 10.10.10.20 10.10.10.50 10.10.20.10 10.10.20.12 10.10.20.20 10.10.30.10; do
    if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${vm_ip}" "echo OK" &>/dev/null; then
        ok "SSH to ${vm_ip}"
    else
        fail "SSH to ${vm_ip}"
    fi
done

echo ""

# -------------------------------------------------------------------------------------------------
# MCP Watchdog
# -------------------------------------------------------------------------------------------------
echo "--- MCP Watchdog ---"
WATCHDOG_STATUS=$(curl -sf http://10.10.10.50:8080/status 2>/dev/null || echo "")
if [ -n "$WATCHDOG_STATUS" ]; then
    ok "Watchdog API responding on :8080"
else
    warn "Watchdog API not responding on 10.10.10.50:8080"
fi

echo ""

# -------------------------------------------------------------------------------------------------
# Services
# -------------------------------------------------------------------------------------------------
echo "--- Services ---"
SERVICES=(
    "Grafana|10.10.10.20|3000|/api/health"
    "Prometheus|10.10.10.20|9090|/-/healthy"
    "Keycloak|10.10.20.20|8443|/health/ready"
    "Nextcloud|10.10.30.10|443|/status.php"
    "Vaultwarden|10.10.20.12|443|/alive"
)

for service_info in "${SERVICES[@]}"; do
    IFS='|' read -r name ip port path <<< "$service_info"
    if curl -skf "https://${ip}:${port}${path}" &>/dev/null || curl -sf "http://${ip}:${port}${path}" &>/dev/null; then
        ok "${name} on ${ip}:${port}"
    else
        fail "${name} on ${ip}:${port}"
    fi
done

echo ""

# -------------------------------------------------------------------------------------------------
# Security
# -------------------------------------------------------------------------------------------------
echo "--- Security ---"
if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@10.10.10.5" "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config" &>/dev/null; then
    ok "SSH: PermitRootLogin=no on bastion"
else
    fail "SSH: PermitRootLogin not set to 'no' on bastion"
fi

if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@10.10.10.5" "systemctl is-active ufw" &>/dev/null; then
    ok "UFW is active on bastion"
else
    fail "UFW is not active on bastion"
fi

if ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@10.10.10.5" "systemctl is-active crowdsec" &>/dev/null; then
    ok "CrowdSec is active on bastion"
else
    warn "CrowdSec not active on bastion"
fi

echo ""

# -------------------------------------------------------------------------------------------------
# Forgejo
# -------------------------------------------------------------------------------------------------
echo "--- Forgejo ---"
if curl -sf http://localhost:3000/api/v1/version &>/dev/null; then
    ok "Forgejo is accessible on localhost:3000"
else
    warn "Forgejo not accessible on localhost:3000"
fi

echo ""
echo "========================================================================="
echo "  Results: ${PASS} OK, ${FAIL} FAIL, ${WARN} WARN"
echo "========================================================================="

[ ${FAIL} -eq 0 ] && exit 0 || exit 1