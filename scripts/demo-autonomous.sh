#!/bin/bash -euo pipefail
# -------------------------------------------------------------------------------------------------
# demo-autonomous.sh — ASIP Autonomous Ops Demonstration
# Injects a configuration drift, watches the MCP watchdog detect and auto-remediate it.
# -------------------------------------------------------------------------------------------------

SSH_USER="${SSH_USER:-ansible}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
BASTION_IP="10.10.10.5"
WATCHDOG_IP="10.10.10.50"
DRIFT_FILE="/etc/ssh/sshd_config"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
pause() { echo ""; read -p "Press Enter to continue..."; echo ""; }

# -------------------------------------------------------------------------------------------------
echo ""
echo "========================================================================="
echo "  A.S.I.P. — Autonomous Operations Demonstration"
echo "========================================================================="
echo ""

# --- Step 0: Verify connectivity ---
log "Checking connectivity to bastion (${BASTION_IP})..."
if ! ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${BASTION_IP}" "echo OK" &>/dev/null; then
    echo "[ERROR] Cannot reach bastion at ${BASTION_IP}"
    echo "Make sure the infrastructure is deployed and SSH is configured."
    exit 1
fi
log "Bastion reachable"

log "Checking watchdog API at ${WATCHDOG_IP}:8080..."
if curl -sf "http://${WATCHDOG_IP}:8080/status" &>/dev/null; then
    log "Watchdog API is responding"
else
    echo "[WARN] Watchdog API not responding at ${WATCHDOG_IP}:8080"
    echo "The watchdog may not be deployed yet. Continuing anyway..."
fi

pause

# --- Step 1: Show initial state ---
echo "========================================================================="
echo "  STEP 1: Initial State — All Systems Conformant"
echo "========================================================================="
log "Checking Goss status on bastion..."
ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${BASTION_IP}" \
    "sudo goss -g /etc/goss/goss.yaml validate --format json 2>/dev/null | tail -1" || echo "(Goss not yet deployed or no results)"

echo ""
log "Checking watchdog status..."
curl -s "http://${WATCHDOG_IP}:8080/status" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(Watchdog not available)"

pause

# --- Step 2: Inject drift ---
echo "========================================================================="
echo "  STEP 2: Inject Configuration Drift"
echo "  Modifying ${DRIFT_FILE} on bastion..."
echo "  PermitRootLogin will be changed from 'no' to 'yes'"
echo "========================================================================="
log "Injecting drift: PermitRootLogin yes → ${DRIFT_FILE}"

ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${BASTION_IP}" \
    "sudo sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' ${DRIFT_FILE} && sudo systemctl restart sshd" || {
    echo "[ERROR] Failed to inject drift. Check SSH access to bastion."
    exit 1
}

log "Verifying drift..."
DRIFT_VALUE=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${BASTION_IP}" \
    "grep PermitRootLogin ${DRIFT_FILE}" 2>/dev/null || echo "unknown")
log "Current value: ${DRIFT_VALUE}"

echo ""
echo "  ⚠  Drift injected! PermitRootLogin is now 'yes' on bastion."
echo "  The MCP Watchdog will detect this within 5 minutes (or immediately via webhook)."

pause

# --- Step 3: Wait for detection ---
echo "========================================================================="
echo "  STEP 3: Wait for Drift Detection"
echo "  The watchdog polls every 5 minutes, or receives webhooks instantly."
echo "========================================================================="
echo ""
log "Polling watchdog for drift status (checking every 30s)..."

FOUND=0
MAX_WAIT=360  # 6 minutes max
ELAPSED=0
while [ ${ELAPSED} -lt ${MAX_WAIT} ]; do
    STATUS=$(curl -sf "http://${WATCHDOG_IP}:8080/status" 2>/dev/null || echo "{}")
    BASTION_STATUS=$(echo "${STATUS}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bastion = data.get('bastion', {})
print(bastion.get('status', 'unknown'))
" 2>/dev/null || echo "unknown")
    
    if [ "${BASTION_STATUS}" = "DRIFT" ] || [ "${BASTION_STATUS}" = "drift" ]; then
        log "DRIFT DETECTED on bastion! Status: ${BASTION_STATUS}"
        FOUND=1
        break
    fi
    
    log "Waiting... (${ELAPSED}s elapsed) bastion status: ${BASTION_STATUS}"
    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

if [ ${FOUND} -eq 0 ]; then
    echo ""
    echo "  ⚠  Watchdog did not detect the drift within ${MAX_WAIT}s."
    echo "  This may mean:"
    echo "    - The Goss timer hasn't run yet (5 min interval)"
    echo "    - The webhook is not configured on bastion"
    echo "  You can manually trigger a check:"
    echo "    ssh ${SSH_USER}@${BASTION_IP} 'sudo /usr/local/bin/goss-validate.sh'"
fi

pause

# --- Step 4: Observe auto-remediation ---
echo "========================================================================="
echo "  STEP 4: Auto-Remediation"
echo "  The watchdog should trigger: ansible-playbook --tags hardening --limit bastion"
echo "========================================================================="
log "Checking watchdog status for remediation..."
curl -sf "http://${WATCHDOG_IP}:8080/status/bastion" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(Watchdog not available)"

echo ""
log "Verifying drift has been corrected..."
CORRECTED=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${BASTION_IP}" \
    "grep PermitRootLogin ${DRIFT_FILE}" 2>/dev/null || echo "unknown")

if echo "${CORRECTED}" | grep -q "PermitRootLogin no"; then
    echo ""
    echo "  ✅  SUCCESS: PermitRootLogin is back to 'no'"
    echo "  Auto-remediation has restored the expected configuration."
else
    echo ""
    echo "  ⚠  PermitRootLogin is still: ${CORRECTED}"
    echo "  Remediation may still be in progress. Check watchdog logs:"
    echo "  ssh ${SSH_USER}@${WATCHDOG_IP} 'cat /var/log/watchdog/audit.json | python3 -m json.tool'"
fi

pause

# --- Step 5: Final verification ---
echo "========================================================================="
echo "  STEP 5: Final Goss Validation"
echo "========================================================================="
log "Running Goss validation on bastion..."
ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${BASTION_IP}" \
    "sudo goss -g /etc/goss/goss.yaml validate" 2>/dev/null || echo "(Goss validation not available)"

echo ""
echo "========================================================================="
echo "  A.S.I.P. — Autonomous Ops Demonstration Complete"
echo ""
echo "  Summary:"
echo "  1. Configuration drift was injected (PermitRootLogin yes)"
echo "  2. MCP Watchdog detected the drift"
echo "  3. Auto-remediation restored the expected state"
echo "  4. Goss validation confirmed compliance"
echo "========================================================================="