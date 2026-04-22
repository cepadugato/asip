#!/bin/bash -euo pipefail
# -------------------------------------------------------------------------------------------------
# simulate-hybrid.sh — ASIP Hybrid Storage Demonstration
# Simulates on-prem → LocalStack S3 backup/restore cycle
# -------------------------------------------------------------------------------------------------

S3_ENDPOINT="http://localhost:4566"
S3_BUCKET="asip-backup"
S3_DOCS="asip-documents"
RCLONE_REMOTE="asip-s3"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

# --- Prerequisites ---
check_localstack() {
    log "Checking LocalStack..."
    if ! curl -sf "${S3_ENDPOINT}/_localstack/health" &>/dev/null; then
        err "LocalStack is not running. Start it with: cd localstack && docker compose up -d"
    fi
    log "LocalStack is running"
}

check_rclone() {
    if ! command -v rclone &>/dev/null; then
        log "Installing rclone..."
        curl -sf https://rclone.org/install.sh | bash
    fi
    log "rclone available: $(rclone version | head -1)"
}

check_awslocal() {
    if ! command -v awslocal &>/dev/null && ! command -v aws &>/dev/null; then
        log "Installing awscli..."
        pip install awscli 2>/dev/null || pip3 install awscli
    fi
}

# --- Configure rclone ---
setup_rclone() {
    log "Configuring rclone remote '${RCLONE_REMOTE}'..."
    rclone config create "${RCLONE_REMOTE}" \
        s3 \
        provider=Other \
        env_auth=false \
        access_key_id=test \
        secret_access_key=test \
        endpoint="${S3_ENDPOINT}" \
        force_path_style=true \
        region=eu-west-1 \
        no_check_bucket=true \
        2>/dev/null || true
    log "rclone remote configured"
}

# --- Test 1: Create local file ---
create_test_file() {
    local TEST_DIR="/tmp/asip-hybrid-demo"
    mkdir -p "${TEST_DIR}"
    local TEST_FILE="${TEST_DIR}/backup-$(date +%Y%m%d_%H%M%S).txt"
    echo "ASIP Hybrid Storage Test - $(date)" > "${TEST_FILE}"
    echo "This file demonstrates hybrid on-prem → S3 backup." >> "${TEST_FILE}"
    log "Created test file: ${TEST_FILE}"
    echo "${TEST_FILE}"
}

# --- Test 2: Upload to LocalStack S3 ---
upload_to_s3() {
    local FILE="$1"
    log "Uploading to s3://${S3_BUCKET}..."
    rclone copy "${FILE}" "${RCLONE_REMOTE}:${S3_BUCKET}/backup-test/" \
        --config "${HOME}/.config/rclone/rclone.conf" \
        --verbose 2>&1 | tail -3
    log "Upload complete"
}

# --- Test 3: Verify S3 content ---
verify_s3() {
    log "Verifying S3 bucket content..."
    rclone ls "${RCLONE_REMOTE}:${S3_BUCKET}/backup-test/" \
        --config "${HOME}/.config/rclone/rclone.conf" 2>/dev/null || \
        log "No files found in S3 bucket (may need to check configuration)"
    log "S3 verification complete"
}

# --- Test 4: Delete local file ---
delete_local() {
    local FILE="$1"
    log "Deleting local file: ${FILE}"
    rm -f "${FILE}"
    log "Local file deleted"
}

# --- Test 5: Restore from S3 ---
restore_from_s3() {
    local TEST_DIR="/tmp/asip-hybrid-demo-restored"
    mkdir -p "${TEST_DIR}"
    log "Restoring from s3://${S3_BUCKET}..."
    rclone copy "${RCLONE_REMOTE}:${S3_BUCKET}/backup-test/" "${TEST_DIR}/" \
        --config "${HOME}/.config/rclone/rclone.conf" \
        --verbose 2>&1 | tail -3
    log "Restore complete. Restored files:"
    ls -la "${TEST_DIR}/"
    
    local RESTORED_FILE
    RESTORED_FILE=$(find "${TEST_DIR}" -name "backup-*.txt" | head -1)
    if [ -n "${RESTORED_FILE}" ]; then
        log "Restored file content:"
        cat "${RESTORED_FILE}"
    else
        err "No file restored from S3!"
    fi
}

# --- Test 6: Cleanup ---
cleanup() {
    log "Cleaning up..."
    rm -rf /tmp/asip-hybrid-demo /tmp/asip-hybrid-demo-restored
    log "Local temp files cleaned up"
}

# --- Main ---
main() {
    echo ""
    echo "========================================================================="
    echo "  A.S.I.P. — Hybrid Storage Simulation"
    echo "  Simulating: on-prem backup → LocalStack S3 → restore"
    echo "========================================================================="
    echo ""

    check_localstack
    check_rclone
    check_awslocal
    setup_rclone

    echo ""
    log "--- Step 1/5: Creating local test file ---"
    TEST_FILE=$(create_test_file)

    echo ""
    log "--- Step 2/5: Uploading to LocalStack S3 ---"
    upload_to_s3 "${TEST_FILE}"

    echo ""
    log "--- Step 3/5: Verifying S3 content ---"
    verify_s3

    echo ""
    log "--- Step 4/5: Deleting local file (simulating data loss) ---"
    delete_local "${TEST_FILE}"

    echo ""
    log "--- Step 5/5: Restoring from S3 ---"
    restore_from_s3

    echo ""
    cleanup

    echo ""
    echo "========================================================================="
    echo "  Hybrid Storage Simulation: SUCCESS"
    echo "  Local file was backed up to S3, deleted, and restored successfully."
    echo "  This demonstrates cloud hybrid storage without any real AWS connection."
    echo "========================================================================="
}

main