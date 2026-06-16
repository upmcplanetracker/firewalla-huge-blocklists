#!/bin/bash

# =============================================================================
# Firewalla Unbound Blocklist Update Script
# =============================================================================
# Description: Downloads and validates Unbound-formatted blocklists with
#              safety checks, logging, and automatic rollback on failure.
#              Supports multiple blocklists via .env configuration file.
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Default configuration file (can be overridden)
ENV_FILE="${ENV_FILE:-/home/pi/.firewalla/config/blocklists.env}"
LOG_FILE="${LOG_FILE:-/var/log/unbound_update.log}"
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

download_with_retry() {
    local url="$1"
    local output_file="$2"
    local list_name="$3"
    local attempt=1
    local success=false
    
    log "Downloading $list_name from $url (attempt $attempt/$MAX_RETRIES)"
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        if curl -f -L -o "$output_file" --connect-timeout 30 --max-time 300 "$url"; then
            success=true
            break
        else
            log "Download attempt $attempt failed for $list_name"
            if [[ $attempt -lt $MAX_RETRIES ]]; then
                log "Waiting $RETRY_DELAY seconds before retry..."
                sleep "$RETRY_DELAY"
            fi
            ((attempt++))
        fi
    done
    
    if [[ $success == false ]]; then
        error_exit "Failed to download $list_name after $MAX_RETRIES attempts"
    fi
    
    log "Download completed successfully for $list_name"
}

validate_file() {
    local file="$1"
    local list_name="$2"
    
    log "Starting validation for $list_name..."
    
    # Check 1: File is not empty
    if [[ ! -s "$file" ]]; then
        error_exit "Downloaded file is empty for $list_name"
    fi
    log "✓ File is not empty"
    
    # Check 2: Not HTML
    if grep -qiE "<html|<head|<body|<!DOCTYPE" "$file"; then
        error_exit "Downloaded HTML instead of blocklist for $list_name"
    fi
    log "✓ File is not HTML"
    
    # Check 3: Contains Unbound format
    if ! grep -q "local-zone:" "$file"; then
        error_exit "File does not contain expected 'local-zone:' entries for $list_name"
    fi
    log "✓ File contains Unbound format entries"
    
    # Check 4: Basic format validation - look for common patterns
    local first_line=$(head -1 "$file")
    if [[ ! "$first_line" =~ ^local-zone: || ! "$first_line" =~ (static|redirect|transparent|typetransparent|always_nxdomain|always_refuse|always_deny) ]]; then
        log "WARNING: First line doesn't match expected Unbound format: $first_line"
        log "This may still be valid, but please verify the list format"
    fi
    
    # Check 5: Validate line count is reasonable (at least 100 entries)
    local line_count=$(grep -c "local-zone:" "$file" || echo "0")
    if [[ $line_count -lt 100 ]]; then
        error_exit "Suspiciously low number of entries for $list_name: $line_count (expected at least 100)"
    fi
    log "✓ File contains $line_count entries"
    
    # Check 6: Look for common syntax errors
    if grep -E "local-zone:[[:space:]]*$" "$file" | grep -q .; then
        error_exit "Found empty domain entries for $list_name (missing domain name after local-zone:)"
    fi
    log "✓ No empty domain entries found"
    
    # Check 7: Check for malformed lines (just a warning, not fatal)
    local malformed=$(grep -vE "^local-zone:|^#|^$" "$file" | head -5)
    if [[ -n "$malformed" ]]; then
        log "WARNING: Found lines that don't look like comments or local-zone entries for $list_name:"
        echo "$malformed" | while read -r line; do
            log "  - $line"
        done
    fi
    
    log "All validation checks passed for $list_name"
}

apply_update() {
    local source_file="$1"
    local target_file="$2"
    local list_name="$3"
    
    log "Applying update for $list_name..."
    
    # Create backup of current config if it exists
    if [[ -f "$target_file" ]]; then
        cp "$target_file" "${target_file}.backup"
        log "Created backup: ${target_file}.backup"
    fi
    
    # Move new config into place
    mv "$source_file" "$target_file"
    log "Installed new configuration: $target_file"
}

restart_unbound() {
    log "Restarting Unbound..."
    
    if ! sudo systemctl restart unbound; then
        log "ERROR: Unbound failed to restart! Restoring all backups..."
        
        # Restore all backed up configs
        find /home/pi/.firewalla/config/unbound_local/ -name "*.backup" -type f | while read -r backup; do
            local original="${backup%.backup}"
            mv "$backup" "$original"
            log "Restored $original from backup"
        done
        
        if sudo systemctl restart unbound; then
            log "Unbound restarted successfully with backup configs"
        else
            error_exit "FATAL: Unbound failed to restart even with backup configs!"
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
    local file="$1"
    if [[ -f "$file" ]]; then
        local count=$(grep -c "local-zone:" "$file" 2>/dev/null || echo "0")
        echo "$count"
    else
        echo "0"
    fi
}

parse_env_file() {
    local env_file="$1"
    local -n list_array="$2"
    
    list_array=()
    
    if [[ ! -f "$env_file" ]]; then
        log "WARNING: No env file found at $env_file"
        return 1
    fi
    
    log "Loading configuration from $env_file"
    
    # Read the env file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse lines that define blocklists (LIST_NAME|URL|OUTPUT_FILE)
        if [[ "$line" =~ ^[[:space:]]*([^|]+)\|[[:space:]]*([^|]+)\|[[:space:]]*(.+)$ ]]; then
            local name="${BASH_REMATCH[1]}"
            local url="${BASH_REMATCH[2]}"
            local output="${BASH_REMATCH[3]}"
            
            # Trim whitespace
            name=$(echo "$name" | xargs)
            url=$(echo "$url" | xargs)
            output=$(echo "$output" | xargs)
            
            # Only add if all fields are non-empty
            if [[ -n "$name" && -n "$url" && -n "$output" ]]; then
                list_array+=("$name|$url|$output")
                log "  Loaded: $name -> $output"
            fi
        fi
    done < "$env_file"
    
    if [[ ${#list_array[@]} -eq 0 ]]; then
        log "WARNING: No valid blocklist entries found in $env_file"
        return 1
    fi
    
    log "Loaded ${#list_array[@]} blocklist(s) from $env_file"
    return 0
}

create_env_template() {
    # Check if the env file already exists
    if [[ -f "$ENV_FILE" ]]; then
        log "✓ .env file already exists at $ENV_FILE - keeping your edits"
        return 0
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$ENV_FILE")"
    
    # Create the template with default OISD Big list
    cat > "$ENV_FILE" << 'EOF'
# =============================================================================
# Firewalla Unbound Blocklist Configuration
# =============================================================================
# Format: LIST_NAME|URL|OUTPUT_FILE
# Each line defines one blocklist to download and validate
# 
# To add a list: Add a new line with NAME|URL|OUTPUT_FILE
# To remove a list: Comment it out with # at the start of the line
# To disable temporarily: Add # at the start of the line
# =============================================================================

# OISD Big List (Recommended for High tier hardware)
oisd_big|https://big.oisd.nl/unbound|/home/pi/.firewalla/config/unbound_local/oisd_big.conf

# OISD Light List (Recommended for Entry tier hardware)
# oisd_light|https://oisd.nl/unbound|/home/pi/.firewalla/config/unbound_local/oisd_light.conf

# HaGeZi Pro List
# hagezi_pro|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/pro.txt|/home/pi/.firewalla/config/unbound_local/hagezi_pro.conf

# HaGeZi Ultimate List (Large - requires High tier hardware)
# hagezi_ultimate|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/ultimate.txt|/home/pi/.firewalla/config/unbound_local/hagezi_ultimate.conf

# Custom lists can be added here
# custom_list|https://example.com/unbound-list.txt|/home/pi/.firewalla/config/unbound_local/custom.conf
EOF
    
    log "✓ Created .env configuration template at $ENV_FILE"
    log "ℹ Please edit $ENV_FILE to customize your blocklists"
    log "  Example: nano $ENV_FILE"
    log "  The script will NEVER overwrite this file once it exists"
}

process_list() {
    local list_name="$1"
    local url="$2"
    local output_file="$3"
    local temp_file="/tmp/${list_name}_tmp.conf"
    
    log "=========================================="
    log "Processing list: $list_name"
    log "=========================================="
    
    # Download
    download_with_retry "$url" "$temp_file" "$list_name"
    
    # Validate
    validate_file "$temp_file" "$list_name"
    
    # Get old block count for reporting
    old_count=$(get_block_count "$output_file")
    log "Old block count for $list_name: $old_count"
    
    # Apply update
    apply_update "$temp_file" "$output_file" "$list_name"
    
    # Report new block count
    new_count=$(get_block_count "$output_file")
    log "New block count for $list_name: $new_count"
    
    if [[ $new_count -gt $old_count ]]; then
        log "✓ $list_name increased by $((new_count - old_count)) domains"
    elif [[ $new_count -lt $old_count ]]; then
        log "ℹ $list_name decreased by $((old_count - new_count)) domains"
    else
        log "ℹ $list_name unchanged"
    fi
    
    # Clean up backup if everything succeeded
    if [[ -f "${output_file}.backup" ]]; then
        rm -f "${output_file}.backup"
        log "Cleaned up backup file for $list_name"
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
    
    # Create env template if it doesn't exist (will NOT overwrite existing)
    create_env_template
    
    # Parse .env file
    declare -a BLOCKLISTS
    if ! parse_env_file "$ENV_FILE" BLOCKLISTS; then
        log "WARNING: No valid lists found in .env file"
        log "  Please edit $ENV_FILE to add your blocklists"
        log "  Format: NAME|URL|OUTPUT_FILE"
        log "  Example: oisd_big|https://big.oisd.nl/unbound|/home/pi/.firewalla/config/unbound_local/oisd_big.conf"
        error_exit "No blocklists configured"
    fi
    
    # Process each list
    local failed_lists=()
    for list_entry in "${BLOCKLISTS[@]}"; do
        IFS='|' read -r list_name url output_file <<< "$list_entry"
        
        if process_list "$list_name" "$url" "$output_file"; then
            log "✓ Successfully updated $list_name"
        else
            log "✗ Failed to update $list_name"
            failed_lists+=("$list_name")
        fi
    done
    
    # Restart Unbound once after all updates
    if ! restart_unbound; then
        error_exit "Update failed during restart phase"
    fi
    
    # Verify Unbound is working
    verify_unbound
    
    # Report results
    log "=========================================="
    log "Update Summary:"
    if [[ ${#failed_lists[@]} -eq 0 ]]; then
        log "✓ All lists updated successfully!"
    else
        log "⚠ Some lists failed: ${failed_lists[*]}"
    fi
    log "=========================================="
    log "Update completed!"
    log "=========================================="
}

# =============================================================================
# Execution
# =============================================================================

# Allow sourcing for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
