#!/bin/bash

# =============================================================================
# Firewalla Unbound Blocklist Update Script
# =============================================================================
# Description: Downloads and validates Unbound-formatted blocklists with
#              safety checks, logging, and automatic rollback on failure.
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Default configuration - can be overridden by environment variables
URL="${BLOCKLIST_URL:-https://big.oisd.nl/unbound}"
CONF_FILE="${CONF_FILE:-/home/pi/.firewalla/config/unbound_local/oisd_big.conf}"
TEMP_FILE="/tmp/oisd_big_tmp.conf"
BACKUP_FILE="${CONF_FILE}.backup"
LOG_FILE="/var/log/unbound_update.log"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"

# =============================================================================
# Functions
# =============================================================================

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

cleanup() {
    if [[ -f "$TEMP_FILE" ]]; then
        rm -f "$TEMP_FILE"
        log "Cleaned up temporary file"
    fi
}

check_disk_space() {
    local required_space=100  # MB
    local available_space=$(df -m /tmp | awk 'NR==2 {print $4}')
    
    if [[ $available_space -lt $required_space ]]; then
        error_exit "Insufficient disk space: ${available_space}MB available, ${required_space}MB required"
    fi
    log "Disk space check passed: ${available_space}MB available"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "$1 is not installed. Please install it first."
    fi
}

download_with_retry() {
    local attempt=1
    local success=false
    
    log "Starting download from $URL (attempt $attempt/$MAX_RETRIES)"
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        if curl -f -L -o "$TEMP_FILE" --connect-timeout 30 --max-time 300 "$URL"; then
            success=true
            break
        else
            log "Download attempt $attempt failed"
            if [[ $attempt -lt $MAX_RETRIES ]]; then
                log "Waiting $RETRY_DELAY seconds before retry..."
                sleep "$RETRY_DELAY"
            fi
            ((attempt++))
        fi
    done
    
    if [[ $success == false ]]; then
        error_exit "Failed to download after $MAX_RETRIES attempts"
    fi
    
    log "Download completed successfully"
}

validate_file() {
    log "Starting file validation..."
    
    # Check 1: File is not empty
    if [[ ! -s "$TEMP_FILE" ]]; then
        error_exit "Downloaded file is empty"
    fi
    log "✓ File is not empty"
    
    # Check 2: Not HTML
    if grep -qiE "<html|<head|<body|<!DOCTYPE" "$TEMP_FILE"; then
        error_exit "Downloaded HTML instead of blocklist"
    fi
    log "✓ File is not HTML"
    
    # Check 3: Contains Unbound format
    if ! grep -q "local-zone:" "$TEMP_FILE"; then
        error_exit "File does not contain expected 'local-zone:' entries"
    fi
    log "✓ File contains Unbound format entries"
    
    # Check 4: Basic format validation - look for common patterns
    local first_line=$(head -1 "$TEMP_FILE")
    if [[ ! "$first_line" =~ ^local-zone: || ! "$first_line" =~ (static|redirect|transparent|typetransparent|always_nxdomain|always_refuse|always_deny) ]]; then
        log "WARNING: First line doesn't match expected Unbound format: $first_line"
        log "This may still be valid, but please verify the list format"
    fi
    
    # Check 5: Validate line count is reasonable (at least 100 entries)
    local line_count=$(grep -c "local-zone:" "$TEMP_FILE" || echo "0")
    if [[ $line_count -lt 100 ]]; then
        error_exit "Suspiciously low number of entries: $line_count (expected at least 100)"
    fi
    log "✓ File contains $line_count entries"
    
    # Check 6: Look for common syntax errors
    if grep -E "local-zone:[[:space:]]*$" "$TEMP_FILE" | grep -q .; then
        error_exit "Found empty domain entries (missing domain name after local-zone:)"
    fi
    log "✓ No empty domain entries found"
    
    # Check 7: Check for malformed lines (just a warning, not fatal)
    local malformed=$(grep -vE "^local-zone:|^#|^$" "$TEMP_FILE" | head -5)
    if [[ -n "$malformed" ]]; then
        log "WARNING: Found lines that don't look like comments or local-zone entries:"
        echo "$malformed" | while read -r line; do
            log "  - $line"
        done
    fi
    
    log "All validation checks passed"
}

apply_update() {
    log "Applying update..."
    
    # Create backup of current config if it exists
    if [[ -f "$CONF_FILE" ]]; then
        cp "$CONF_FILE" "$BACKUP_FILE"
        log "Created backup: $BACKUP_FILE"
    fi
    
    # Move new config into place
    mv "$TEMP_FILE" "$CONF_FILE"
    log "Installed new configuration: $CONF_FILE"
}

restart_unbound() {
    log "Restarting Unbound..."
    
    if ! sudo systemctl restart unbound; then
        log "ERROR: Unbound failed to restart! Restoring backup..."
        
        if [[ -f "$BACKUP_FILE" ]]; then
            mv "$BACKUP_FILE" "$CONF_FILE"
            log "Restored backup configuration"
            
            if sudo systemctl restart unbound; then
                log "Unbound restarted successfully with backup config"
            else
                error_exit "FATAL: Unbound failed to restart even with backup config!"
            fi
        else
            error_exit "FATAL: Unbound failed to restart and no backup exists!"
        fi
        
        return 1
    fi
    
    log "✓ Unbound restarted successfully"
}

verify_unbound() {
    log "Verifying Unbound status..."
    sleep 2
    
    # Check if Unbound is running
    if ! systemctl is-active --quiet unbound; then
        error_exit "Unbound is not running after restart!"
    fi
    log "✓ Unbound is running"
    
    # Try to query Unbound directly (bypassing DNS Booster)
    if command -v dig &> /dev/null; then
        log "Testing DNS resolution using dig..."
        if dig @127.0.0.1 google.com +short &> /dev/null; then
            log "✓ DNS resolution test passed"
        else
            log "WARNING: DNS resolution test failed! Check your configuration."
        fi
    elif command -v nslookup &> /dev/null; then
        log "Testing DNS resolution using nslookup..."
        if nslookup google.com 127.0.0.1 &> /dev/null; then
            log "✓ DNS resolution test passed"
        else
            log "WARNING: DNS resolution test failed! Check your configuration."
        fi
    else
        log "⚠ dig/nslookup not available, skipping DNS resolution test"
    fi
}

get_block_count() {
    if [[ -f "$CONF_FILE" ]]; then
        local count=$(grep -c "local-zone:" "$CONF_FILE" 2>/dev/null || echo "0")
        echo "$count"
    else
        echo "0"
    fi
}

check_curl_installed() {
    if ! command -v curl &> /dev/null; then
        log "curl not found, attempting to install..."
        if sudo apt install -y curl; then
            log "✓ curl installed successfully"
        else
            error_exit "Failed to install curl. Please install manually: sudo apt install curl"
        fi
    fi
}

main() {
    # Initial setup
    trap cleanup EXIT
    log "=========================================="
    log "Starting Unbound blocklist update"
    log "=========================================="
    
    # Pre-flight checks
    log "Running pre-flight checks..."
    check_curl_installed
    check_command grep
    check_command systemctl
    check_disk_space
    
    # Check if running as root (needed for systemctl)
    if [[ $EUID -ne 0 ]]; then
        log "Note: Not running as root. Some operations require sudo."
    fi
    
    # Download
    download_with_retry
    
    # Validate
    validate_file
    
    # Get old block count for reporting
    old_count=$(get_block_count)
    log "Old block count: $old_count"
    
    # Apply and restart
    apply_update
    
    # Try to restart Unbound (with rollback on failure)
    if ! restart_unbound; then
        error_exit "Update failed during restart phase"
    fi
    
    # Verify Unbound is working
    verify_unbound
    
    # Report new block count
    new_count=$(get_block_count)
    log "New block count: $new_count"
    
    if [[ $new_count -gt $old_count ]]; then
        log "✓ Block count increased by $((new_count - old_count)) domains"
    elif [[ $new_count -lt $old_count ]]; then
        log "ℹ Block count decreased by $((old_count - new_count)) domains"
    else
        log "ℹ Block count unchanged"
    fi
    
    # Clean up backup if everything succeeded
    if [[ -f "$BACKUP_FILE" ]]; then
        rm -f "$BACKUP_FILE"
        log "Cleaned up backup file (update successful)"
    fi
    
    log "=========================================="
    log "Update completed successfully!"
    log "=========================================="
}

# =============================================================================
# Execution
# =============================================================================

# Allow sourcing for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
