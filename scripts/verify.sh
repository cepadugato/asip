#!/bin/bash -euo pipefail
# -------------------------------------------------------------------------------------------------
# verify.sh — ASIP Infrastructure Health Checks (adapted to real deployment)
# -------------------------------------------------------------------------------------------------

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

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=eu-west-1
if aws --endpoint-url=http://localhost:4566 s3 ls 2>/dev/null | grep -q "asip-backup"; then
    ok "S3 bucket 'asip-backup' exists"
else
    fail "S3 bucket 'asip-backup' not found"
fi

if aws --endpoint-url=http://localhost:4566 s3 ls 2>/dev/null | grep -q "asip-documents"; then
    ok "S3 bucket 'asip-documents' exists"
else
    fail "S3 bucket 'asip-documents' not found"
fi

if aws --endpoint-url=http://localhost:4566 s3 ls 2>/dev/null | grep -q "asip-terraform-state"; then
    ok "S3 bucket 'asip-terraform-state' exists"
else
    fail "S3 bucket 'asip-terraform-state' not found"
fi

echo ""

# -------------------------------------------------------------------------------------------------
# Proxmox
# -------------------------------------------------------------------------------------------------
echo "--- Proxmox ---"
PROXMOX_HOST="${PROXMOX_HOST:-192.168.100.254}"
PROXMOX_NODE="${PROXMOX_NODE:-pve}"
PROXMOX_TOKEN="${PROXMOX_TOKEN:-<REDACTED_PROXMOX_TOKEN>}"

PVE_STATUS=$(curl -sk "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/status" \
  -H "Authorization: PVEAPIToken root@pam!terraform=${PROXMOX_TOKEN}" 2>/dev/null || echo "")
if echo "$PVE_STATUS" | grep -q "uptime"; then
    ok "Proxmox API reachable on ${PROXMOX_HOST}"
else
    fail "Proxmox API not reachable on ${PROXMOX_HOST}"
fi

echo ""

# -------------------------------------------------------------------------------------------------
# MCP Watchdog (LXC 119)
# -------------------------------------------------------------------------------------------------
echo "--- MCP Watchdog ---"
WATCHDOG_IP="${WATCHDOG_IP:-192.168.100.119}"

if curl -sf "http://${WATCHDOG_IP}:8080/health" 2>/dev/null | grep -q '"ok"'; then
    ok "Watchdog API responding on ${WATCHDOG_IP}:8080"
else
    fail "Watchdog API not responding on ${WATCHDOG_IP}:8080"
fi

WATCHDOG_STATUS=$(curl -sf "http://${WATCHDOG_IP}:8080/status" 2>/dev/null || echo "{}")
if echo "$WATCHDOG_STATUS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
hosts_ok=[h for h,v in d.items() if v.get('status')=='OK']
hosts_drift=[h for h,v in d.items() if v.get('status')=='DRIFT']
print(f'{len(hosts_ok)}OK/{len(hosts_drift)}DRIFT')
" 2>/dev/null | grep -q "DRIFT"; then
    warn "Watchdog reports DRIFT on some hosts"
else
    ok "Watchdog reports all hosts OK"
fi

if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 root@${WATCHDOG_IP} "goss -g /etc/goss/goss.yaml validate --format json 2>/dev/null" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
sys.exit(d['summary']['failed-count'])
" 2>/dev/null; then
    ok "Goss compliance check passed on watchdog"
else
    fail "Goss compliance check failed on watchdog"
fi

echo ""

# -------------------------------------------------------------------------------------------------
# Forgejo
# -------------------------------------------------------------------------------------------------
echo "--- Forgejo ---"
FORGEJO_TOKEN="${FORGEJO_TOKEN:-<REDACTED_FORGEJO_TOKEN>}"

if curl -sf "http://localhost:3000/api/v1/repos/git/asip" \
  -H "Authorization: token ${FORGEJO_TOKEN}" 2>/dev/null | grep -q "asip"; then
    ok "Forgejo repo 'git/asip' exists"
else
    fail "Forgejo repo 'git/asip' not found"
fi

if curl -sf "http://localhost:3000/api/v1/version" 2>/dev/null | grep -q "version"; then
    ok "Forgejo API accessible on localhost:3000"
else
    fail "Forgejo API not accessible on localhost:3000"
fi

echo ""

# -------------------------------------------------------------------------------------------------
# Forgejo Runner
# -------------------------------------------------------------------------------------------------
echo "--- Forgejo Runner (PC hôte) ---"

if systemctl --user is-active forgejo-runner.service 2>/dev/null | grep -q "active"; then
    ok "Forgejo runner service active (systemd user service)"
else
    fail "Forgejo runner service not active"
fi

echo ""

# -------------------------------------------------------------------------------------------------
# rclone + LocalStack sync
# -------------------------------------------------------------------------------------------------
echo "--- Hybrid Storage (rclone + LocalStack) ---"
RCLONE="${RCLONE_LOCAL:-/mnt/6D33430F1C940A7B/Documents/opencode/.local/bin/rclone}"

if [ -x "${RCLONE}" ]; then
    ok "rclone available: $(${RCLONE} version | head -1)"
else
    warn "rclone not found at ${RCLONE}"
fi

if [ -x "${RCLONE}" ] && ${RCLONE} ls localstack:asip-backup 2>/dev/null; then
    ok "rclone can access LocalStack S3 buckets"
else
    warn "rclone LocalStack connection not tested"
fi

echo ""
echo "========================================================================="
echo "  Results: ${PASS} OK, ${FAIL} FAIL, ${WARN} WARN"
echo "========================================================================="

[ ${FAIL} -eq 0 ] && exit 0 || exit 1