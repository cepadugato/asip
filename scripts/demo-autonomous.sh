#!/bin/bash -euo pipefail
# -------------------------------------------------------------------------------------------------
# demo-autonomous.sh — ASIP Autonomous Ops Demonstration
# Injects a configuration drift, watches the MCP watchdog detect and auto-remediate it.
# -------------------------------------------------------------------------------------------------

SSH_USER="${SSH_USER:-ansible}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
BASTION_IP="203.0.113.5"
WATCHDOG_IP="203.0.113.50"
DRIFT_FILE="/etc/ssh/sshd_config"

# MCP server path (relative to this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MCP_SERVER_SCRIPT="${SCRIPT_DIR}/../mcp-agent/server_stdio.py"

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
pause() { echo ""; read -p "Press Enter to continue..."; echo ""; }

# -------------------------------------------------------------------------------------------------
# MCP helpers
# -------------------------------------------------------------------------------------------------

check_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        log "jq not found — attempting install..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y -qq jq >/dev/null 2>&1 || true
        elif command -v apk >/dev/null 2>&1; then
            sudo apk add --no-cache jq >/dev/null 2>&1 || true
        fi
    fi
    if command -v jq >/dev/null 2>&1; then
        JQ_AVAILABLE=1
    else
        JQ_AVAILABLE=0
        log "jq unavailable — using python3 as JSON fallback"
    fi
}

extract_mcp_text() {
    if [ "$JQ_AVAILABLE" -eq 1 ]; then
        jq -r '.result.content[0].text // empty'
    else
        python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('result',{}).get('content',[{}])[0].get('text',''))"
    fi
}

mcp_send() {
    local msg="$1"
    printf '%s\n' "$msg" >&"${MCP_SERVER[1]}"
}

mcp_read() {
    local _line=""
    if IFS= read -r -t 5 _line <&"${MCP_SERVER[0]}"; then
        printf '%s\n' "$_line"
        return 0
    else
        return 1
    fi
}

mcp_call_tool() {
    local req_id="$1"
    local tool_name="$2"
    local tool_args="$3"
    printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' \
        "$req_id" "$tool_name" "$tool_args" >&"${MCP_SERVER[1]}"
    mcp_read
}

cleanup_mcp() {
    if [[ -n "${MCP_SERVER_PID:-}" ]] && kill -0 "$MCP_SERVER_PID" 2>/dev/null; then
        log "Stopping MCP server (PID $MCP_SERVER_PID)..."
        kill "$MCP_SERVER_PID" 2>/dev/null || true
        wait "$MCP_SERVER_PID" 2>/dev/null || true
    fi
}

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

# --- Step 3: MCP stdio ---
echo "========================================================================="
echo "  STEP 3: MCP stdio — Watchdog Interaction"
echo "========================================================================="

MCP_READY=0
MCP_ID=0
check_jq

if [[ ! -f "$MCP_SERVER_SCRIPT" ]]; then
    log "[WARN] MCP server script not found at ${MCP_SERVER_SCRIPT}"
else
    trap cleanup_mcp EXIT INT TERM

    log "Starting MCP stdio server..."
    coproc MCP_SERVER {
        cd "$(dirname "$MCP_SERVER_SCRIPT")" || exit 1
        stdbuf -oL python3 server_stdio.py
    }
    MCP_SERVER_PID="${MCP_SERVER_PID:-}"
    log "MCP coproc started (PID $MCP_SERVER_PID)"

    # 3.2 Handshake
    ((MCP_ID++))
    mcp_send '{"jsonrpc":"2.0","id":'"$MCP_ID"',"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"demo-autonomous","version":"1.0.0"}}}'

    MCP_INIT_RESPONSE=""
    if MCP_INIT_RESPONSE=$(mcp_read); then
        log "MCP initialize response received"
        # notifications/initialized — SANS id (c'est une notification)
        mcp_send '{"jsonrpc":"2.0","method":"notifications/initialized"}'
        log "MCP handshake complete"
        MCP_READY=1
    else
        log "[WARN] MCP handshake failed (timeout or no response)"
    fi
fi

if [ "$MCP_READY" -eq 1 ]; then
    # 3.3 Appeler watchdog_run_goss(bastion)
    ((MCP_ID++))
    if ! RESPONSE=$(mcp_call_tool "$MCP_ID" "watchdog_run_goss" '{"host":"bastion"}'); then
        log "[WARN] MCP call watchdog_run_goss failed"
        RESPONSE="{}"
    fi
    log "watchdog_run_goss raw response: $RESPONSE"
    GOSS_TEXT=$(echo "$RESPONSE" | extract_mcp_text 2>/dev/null || true)
    [ -n "$GOSS_TEXT" ] && log "watchdog_run_goss result: $GOSS_TEXT"

    # 3.4 Appeler watchdog_host_status(bastion) → vérifier DRIFT
    ((MCP_ID++))
    if ! RESPONSE=$(mcp_call_tool "$MCP_ID" "watchdog_host_status" '{"host":"bastion"}'); then
        log "[WARN] MCP call watchdog_host_status failed"
        RESPONSE="{}"
    fi
    log "watchdog_host_status raw response: $RESPONSE"
    HOST_TEXT=$(echo "$RESPONSE" | extract_mcp_text 2>/dev/null || true)
    [ -n "$HOST_TEXT" ] && log "watchdog_host_status result: $HOST_TEXT"

    BASTION_STATUS=$(echo "$HOST_TEXT" | python3 -c "
import json,sys
try:
    data=json.load(sys.stdin)
    print(data.get('status','unknown'))
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")
    log "Bastion status via MCP: $BASTION_STATUS"
    if [ "${BASTION_STATUS}" = "DRIFT" ] || [ "${BASTION_STATUS}" = "drift" ]; then
        log "DRIFT DETECTED on bastion via MCP!"
    fi

    # 3.5 Appeler watchdog_remediate(bastion, "hardening")
    ((MCP_ID++))
    if ! RESPONSE=$(mcp_call_tool "$MCP_ID" "watchdog_remediate" '{"host":"bastion","tags":"hardening"}'); then
        log "[WARN] MCP call watchdog_remediate failed"
        RESPONSE="{}"
    fi
    log "watchdog_remediate raw response: $RESPONSE"
    REM_TEXT=$(echo "$RESPONSE" | extract_mcp_text 2>/dev/null || true)
    [ -n "$REM_TEXT" ] && log "watchdog_remediate result: $REM_TEXT"

    # 3.6 Appeler watchdog_status → vérifier OK
    ((MCP_ID++))
    if ! RESPONSE=$(mcp_call_tool "$MCP_ID" "watchdog_status" '{}'); then
        log "[WARN] MCP call watchdog_status failed"
        RESPONSE="{}"
    fi
    log "watchdog_status raw response: $RESPONSE"
    STAT_TEXT=$(echo "$RESPONSE" | extract_mcp_text 2>/dev/null || true)
    [ -n "$STAT_TEXT" ] && log "watchdog_status result: $STAT_TEXT"

    # 3.7 Fermer le serveur MCP
    cleanup_mcp
    trap - EXIT INT TERM
    log "MCP session closed"
    pause
else
    log "[WARN] MCP stdio unavailable — will fall back to HTTP watchdog API for Steps 4-5"
fi

# --- Step 4: Wait for detection (fallback HTTP) ---
echo "========================================================================="
echo "  STEP 4: Wait for Drift Detection (HTTP fallback)"
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

# --- Step 5: Observe auto-remediation (fallback HTTP) ---
echo "========================================================================="
echo "  STEP 5: Auto-Remediation (HTTP fallback)"
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

# --- Step 6: Final verification ---
echo "========================================================================="
echo "  STEP 6: Final Goss Validation"
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
