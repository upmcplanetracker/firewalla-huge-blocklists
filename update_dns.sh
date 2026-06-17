#!/bin/bash

# =============================================================================
# Firewalla Unbound Blocklist Update Script
# =============================================================================
# Description: Downloads and validates Unbound-formatted blocklists with
#              safety checks, logging, and automatic rollback on failure.
#              Supports multiple blocklists via .env configuration file.
#              AUTO-DETECTS and converts various list formats to Unbound format.
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
DRY_RUN="${DRY_RUN:-false}"
QUIET="${QUIET:-false}"
MIN_DISK_SPACE="${MIN_DISK_SPACE:-50}"  # MB

# =============================================================================
# Functions
# =============================================================================

log() {
    if [[ "$QUIET" == "true" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] $1" >> "$LOG_FILE"
    else
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] $1" | tee -a "$LOG_FILE"
    fi
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

fix_ownership() {
    local target_dir="$1"
    if [[ -d "$target_dir" ]]; then
        chown -R pi:pi "$target_dir" 2>/dev/null || true
        log "Fixed ownership for $target_dir"
    fi
}

check_disk_space() {
    local required_space=$MIN_DISK_SPACE
    local available_space=$(df -m /tmp | awk 'NR==2 {print $4}')
    
    if [[ $available_space -lt $required_space ]]; then
        log "WARNING: Low disk space: ${available_space}MB available, ${required_space}MB recommended"
        log "  Firewalla may dynamically free space as needed"
    else
        log "Disk space check passed: ${available_space}MB available"
    fi
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

# -----------------------------------------------------------------------------
# Log Rotation Setup
# -----------------------------------------------------------------------------
setup_log_rotation() {
    local log_file="$1"
    local rotate_config="/etc/logrotate.d/unbound_update"
    
    log "Checking log rotation configuration..."
    
    # Check if log rotation is already configured
    if [[ -f "$rotate_config" ]]; then
        log "✓ Log rotation already configured at $rotate_config"
        return 0
    fi
    
    log "Setting up log rotation for $log_file..."
    
    # Create logrotate config file (protect against failures)
    if sudo tee "$rotate_config" > /dev/null << EOF 2>/dev/null
# Log rotation for Firewalla Unbound update script
# Configured by update_dns.sh on $(date)

$log_file {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0640 pi pi
    postrotate
        # No need to restart anything as logs are just files
        true
    endscript
}
EOF
    then
        log "✓ Log rotation configured successfully"
        log "  - Log file: $log_file"
        log "  - Rotated daily"
        log "  - Keep 7 days of logs"
        log "  - Compressed old logs"
        
        # Test the configuration (ignore failure)
        if sudo logrotate -f "$rotate_config" 2>/dev/null; then
            log "✓ Log rotation test passed"
        else
            log "WARNING: Log rotation test failed, but config was created"
        fi
    else
        log "WARNING: Failed to set up log rotation (permission issue)"
        log "  You can manually configure it by creating: $rotate_config"
    fi
}

# -----------------------------------------------------------------------------
# Download functions
# -----------------------------------------------------------------------------

download_with_retry() {
    local url="$1"
    local output_file="$2"
    local list_name="$3"
    local attempt=1
    local success=false
    
    log "Downloading $list_name from $url (attempt $attempt/$MAX_RETRIES)"
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        if curl -f -L -o "$output_file" --connect-timeout 30 --max-time 300 "$url" 2>/dev/null; then
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
        log "ERROR: Failed to download $list_name after $MAX_RETRIES attempts"
        return 1
    fi
    
    log "Download completed successfully for $list_name"
    return 0
}

# -----------------------------------------------------------------------------
# Format detection and conversion
# -----------------------------------------------------------------------------
detect_format_and_convert() {
    local input_file="$1"
    local output_file="$2"
    local list_name="$3"
    
    log "Analyzing format for $list_name..."
    
    # Check if already Unbound format
    if grep -q "local-zone:" "$input_file"; then
        log "✓ Already in Unbound format"
        return 0
    fi
    
    # Check for RPZ format (contains "CNAME ." in first 50 lines)
    if head -50 "$input_file" | grep -q "CNAME \."; then
        log "Detected RPZ format - converting..."
        return convert_rpz_to_unbound "$input_file" "$output_file" "$list_name"
    fi
    
    # Check for Wildcard format (lines like "*.example.com")
    if head -50 "$input_file" | grep -qE "^\*\.|[[:space:]]\*\."; then
        log "Detected Wildcard format - converting..."
        return convert_wildcard_to_unbound "$input_file" "$output_file" "$list_name"
    fi
    
    # Check for Hosts format (lines with IP address followed by domain)
    if head -50 "$input_file" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+"; then
        log "Detected Hosts file format - converting..."
        return convert_hosts_to_unbound "$input_file" "$output_file" "$list_name"
    fi
    
    # Check for Adblock format (lines like "||example.com^")
    if head -50 "$input_file" | grep -qE "^\|\|[^*]+\^"; then
        log "Detected Adblock format - converting..."
        return convert_adblock_to_unbound "$input_file" "$output_file" "$list_name"
    fi
    
    # Check for DNSMasq format (lines like "address=/example.com/0.0.0.0")
    if head -50 "$input_file" | grep -qE "^address=/"; then
        log "Detected DNSMasq format - converting..."
        return convert_dnsmasq_to_unbound "$input_file" "$output_file" "$list_name"
    fi
    
    # Check for plain domains (one domain per line, no special characters)
    if head -20 "$input_file" | grep -qE "^[a-zA-Z0-9\.-]+$"; then
        log "Detected plain domains format - converting..."
        return convert_domains_to_unbound "$input_file" "$output_file" "$list_name"
    fi
    
    log "ERROR: Unable to detect format for $list_name"
    log "  Please ensure the file is in one of these formats:"
    log "  - Unbound (local-zone:)"
    log "  - RPZ (CNAME .)"
    log "  - Wildcard (*.domain.com)"
    log "  - Hosts (0.0.0.0 domain.com)"
    log "  - Adblock (||domain.com^)"
    log "  - DNSMasq (address=/domain.com/0.0.0.0)"
    log "  - Plain domains (domain.com)"
    return 1
}

# -----------------------------------------------------------------------------
# Individual format converters
# -----------------------------------------------------------------------------

convert_rpz_to_unbound() {
    local input_file="$1"
    local output_file="$2"
    local list_name="$3"
    
    log "Converting RPZ to Unbound format for $list_name..."
    
    {
        echo "server:"
        awk '
            /^[[:space:]]*$/ { next }
            /^[[:space:]]*[;#]/ { next }
            /^\$/ { next }
            /^\*\./ { next }
            {
                domain = $1
                sub(/\.$/, "", domain)
                if (domain != "" && domain != "NS" && domain != "SOA") {
                    printf "    local-zone: \"%s.\" always_null\n", domain
                }
            }
        ' "$input_file"
    } > "$output_file"
    
    if [[ ! -s "$output_file" ]] || ! grep -q "local-zone:" "$output_file"; then
        log "ERROR: RPZ conversion failed"
        return 1
    fi
    
    log "✓ RPZ conversion successful"
    return 0
}

convert_wildcard_to_unbound() {
    local input_file="$1"
    local output_file="$2"
    local list_name="$3"
    
    log "Converting Wildcard to Unbound format for $list_name..."
    
    {
        echo "server:"
        grep -vE '^[[:space:]]*$|^[[:space:]]*[;#]' "$input_file" | \
        sed 's/^\*\.//' | \
        awk '{printf "    local-zone: \"%s.\" always_null\n", $1}'
    } > "$output_file"
    
    if [[ ! -s "$output_file" ]] || ! grep -q "local-zone:" "$output_file"; then
        log "ERROR: Wildcard conversion failed"
        return 1
    fi
    
    log "✓ Wildcard conversion successful"
    return 0
}

convert_hosts_to_unbound() {
    local input_file="$1"
    local output_file="$2"
    local list_name="$3"
    
    log "Converting Hosts format to Unbound for $list_name..."
    
    {
        echo "server:"
        grep -vE '^[[:space:]]*$|^[[:space:]]*[;#]' "$input_file" | \
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+' | \
        awk '{print $2}' | \
        while read -r domain; do
            if [[ -n "$domain" && ! "$domain" =~ ^# ]]; then
                printf "    local-zone: \"%s.\" always_null\n" "$domain"
            fi
        done
    } > "$output_file"
    
    if [[ ! -s "$output_file" ]] || ! grep -q "local-zone:" "$output_file"; then
        log "ERROR: Hosts conversion failed"
        return 1
    fi
    
    log "✓ Hosts conversion successful"
    return 0
}

convert_adblock_to_unbound() {
    local input_file="$1"
    local output_file="$2"
    local list_name="$3"
    
    log "Converting Adblock format to Unbound for $list_name..."
    
    {
        echo "server:"
        grep -vE '^[[:space:]]*$|^[[:space:]]*[;#]' "$input_file" | \
        grep '^||' | \
        sed 's/^||//' | \
        sed 's/\^$//' | \
        while read -r domain; do
            if [[ -n "$domain" && ! "$domain" =~ ^# ]]; then
                # Check if it's a wildcard domain
                if [[ "$domain" == *"*"* ]]; then
                    domain=$(echo "$domain" | sed 's/\*\.//')
                    printf "    local-zone: \"%s.\" always_null\n" "$domain"
                else
                    printf "    local-zone: \"%s.\" always_null\n" "$domain"
                fi
            fi
        done
    } > "$output_file"
    
    if [[ ! -s "$output_file" ]] || ! grep -q "local-zone:" "$output_file"; then
        log "ERROR: Adblock conversion failed"
        return 1
    fi
    
    log "✓ Adblock conversion successful"
    return 0
}

convert_dnsmasq_to_unbound() {
    local input_file="$1"
    local output_file="$2"
    local list_name="$3"
    
    log "Converting DNSMasq format to Unbound for $list_name..."
    
    {
        echo "server:"
        grep -vE '^[[:space:]]*$|^[[:space:]]*[;#]' "$input_file" | \
        grep '^address=/' | \
        sed 's/^address=\///' | \
        sed 's/\/[0-9.]*$//' | \
        while read -r domain; do
            if [[ -n "$domain" && ! "$domain" =~ ^# ]]; then
                printf "    local-zone: \"%s.\" always_null\n" "$domain"
            fi
        done
    } > "$output_file"
    
    if [[ ! -s "$output_file" ]] || ! grep -q "local-zone:" "$output_file"; then
        log "ERROR: DNSMasq conversion failed"
        return 1
    fi
    
    log "✓ DNSMasq conversion successful"
    return 0
}

convert_domains_to_unbound() {
    local input_file="$1"
    local output_file="$2"
    local list_name="$3"
    
    log "Converting plain domains to Unbound format for $list_name..."
    
    {
        echo "server:"
        grep -vE '^[[:space:]]*$|^[[:space:]]*[;#]' "$input_file" | \
        grep -vE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        while read -r domain; do
            # Remove leading/trailing whitespace
            domain=$(echo "$domain" | xargs)
            if [[ -n "$domain" && ! "$domain" =~ ^# ]]; then
                printf "    local-zone: \"%s.\" always_null\n" "$domain"
            fi
        done
    } > "$output_file"
    
    if [[ ! -s "$output_file" ]] || ! grep -q "local-zone:" "$output_file"; then
        log "ERROR: Domains conversion failed"
        return 1
    fi
    
    log "✓ Plain domains conversion successful"
    return 0
}

# -----------------------------------------------------------------------------
# Validation and update functions
# -----------------------------------------------------------------------------

validate_file() {
    local file="$1"
    local list_name="$2"
    
    log "Starting validation for $list_name..."
    
    # Check 1: File is not empty
    if [[ ! -s "$file" ]]; then
        log "ERROR: Downloaded file is empty for $list_name"
        return 1
    fi
    log "✓ File is not empty"
    
    # Check 2: Not HTML
    if grep -qiE "<html|<head|<body|<!DOCTYPE" "$file"; then
        log "ERROR: Downloaded HTML instead of blocklist for $list_name"
        return 1
    fi
    log "✓ File is not HTML"
    
    # Check 3: Detect format and convert if needed
    local temp_converted="/tmp/${list_name}_converted.conf"
    if ! detect_format_and_convert "$file" "$temp_converted" "$list_name"; then
        log "ERROR: Format detection/conversion failed for $list_name"
        return 1
    fi
    
    # Move converted file to original location if conversion happened
    if [[ -f "$temp_converted" ]]; then
        mv "$temp_converted" "$file"
        log "✓ Applied converted format"
    fi
    
    # Check 4: Validate line count is reasonable (at least 100 entries)
    local line_count=$(grep -c "local-zone:" "$file" || echo "0")
    if [[ $line_count -lt 100 ]]; then
        log "ERROR: Suspiciously low number of entries for $list_name: $line_count (expected at least 100)"
        log "  This might be a corrupted download or unsupported format"
        return 1
    fi
    log "✓ File contains $line_count entries"
    
    # Check 5: Look for common syntax errors
    if grep -E "local-zone:[[:space:]]*$" "$file" | grep -q .; then
        log "ERROR: Found empty domain entries for $list_name (missing domain name after local-zone:)"
        return 1
    fi
    log "✓ No empty domain entries found"
    
    log "All validation checks passed for $list_name"
    return 0
}

apply_update() {
    local source_file="$1"
    local target_file="$2"
    local list_name="$3"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would apply update for $list_name"
        return 0
    fi
    
    log "Applying update for $list_name..."
    
    # Create backup of current config if it exists
    if [[ -f "$target_file" ]]; then
        cp "$target_file" "${target_file}.backup"
        log "Created backup: ${target_file}.backup"
    fi
    
    # Move new config into place (protected)
    if mv "$source_file" "$target_file" 2>/dev/null; then
        log "Installed new configuration: $target_file"
    else
        log "ERROR: Failed to move $source_file to $target_file"
        return 1
    fi
    
    # Fix ownership of the config file
    chown pi:pi "$target_file" 2>/dev/null || true
    log "Fixed ownership for $target_file"
    return 0
}

restart_unbound() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would restart Unbound"
        return 0
    fi
    
    log "Restarting Unbound..."
    
    if ! sudo systemctl restart unbound; then
        log "ERROR: Unbound failed to restart! Restoring all backups..."
        
        find /home/pi/.firewalla/config/unbound_local/ -name "*.backup" -type f | while read -r backup; do
            local original="${backup%.backup}"
            mv "$backup" "$original"
            log "Restored $original from backup"
            chown pi:pi "$original" 2>/dev/null || true
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
    
    if ! systemctl is-active --quiet unbound; then
        error_exit "Unbound is not running after restart!"
    fi
    log "✓ Unbound is running"
    
    local memory_mb=$(free -m | awk '/Mem:/ {print $3}')
    local total_mb=$(free -m | awk '/Mem:/ {print $2}')
    local percent=$((memory_mb * 100 / total_mb))
    log "Memory usage: ${memory_mb}MB / ${total_mb}MB (${percent}%)"
    if [[ $percent -gt 90 ]]; then
        log "WARNING: High memory usage! Consider using a smaller blocklist."
    fi
    
    log "Testing DNS resolution..."
    if command -v dig &> /dev/null; then
        if dig google.com +short &> /dev/null; then
            log "✓ DNS resolution test passed (DNS Booster is working)"
        else
            log "WARNING: DNS resolution test failed. Check your network."
        fi
    elif command -v nslookup &> /dev/null; then
        if nslookup google.com &> /dev/null; then
            log "✓ DNS resolution test passed (DNS Booster is working)"
        else
            log "WARNING: DNS resolution test failed. Check your network."
        fi
    else
        log "⚠ dig/nslookup not available, skipping DNS resolution test"
    fi
    
    log "Checking Unbound logs for errors..."
    # Use || true to prevent script exit if journalctl fails
    local error_count=$(sudo journalctl -u unbound --since "1 minute ago" 2>/dev/null | grep -iE "error|fatal" | grep -v "duplicate local-zone" | grep -v "SSL_read" | wc -l || echo "0")
    if [[ $error_count -eq 0 ]]; then
        log "✓ No errors in Unbound logs"
    else
        log "WARNING: Found $error_count errors in Unbound logs"
        sudo journalctl -u unbound --since "1 minute ago" 2>/dev/null | grep -iE "error|fatal" | grep -v "duplicate local-zone" | grep -v "SSL_read" | head -5 | while read -r line; do
            log "  - $line"
        done
    fi
    
    local unbound_conf="/home/pi/.firewalla/config/unbound_local/unbound_custom.conf"
    if [[ -f "$unbound_conf" ]]; then
        if grep -q "include:.*\.conf" "$unbound_conf"; then
            log "✓ Blocklist includes found in Unbound config"
        else
            log "WARNING: No blocklist includes found in Unbound config!"
        fi
    fi
    
    for conf_file in /home/pi/.firewalla/config/unbound_local/*.conf; do
        if [[ -f "$conf_file" && "$conf_file" != *"unbound_custom.conf" && "$conf_file" != *"unbound_local.conf" ]]; then
            local block_count=$(grep -c "local-zone:" "$conf_file" 2>/dev/null || echo "0")
            if [[ $block_count -gt 0 ]]; then
                log "✓ $(basename "$conf_file") loaded with $block_count entries"
            fi
        fi
    done
    
    log "✓ Unbound verification complete"
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
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        if [[ "$line" =~ ^[[:space:]]*([^|]+)\|[[:space:]]*([^|]+)\|[[:space:]]*(.+)$ ]]; then
            local name="${BASH_REMATCH[1]}"
            local url="${BASH_REMATCH[2]}"
            local output="${BASH_REMATCH[3]}"
            
            name=$(echo "$name" | xargs)
            url=$(echo "$url" | xargs)
            output=$(echo "$output" | xargs)
            
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
    if [[ -f "$ENV_FILE" ]]; then
        log "✓ .env file already exists at $ENV_FILE - keeping your edits"
        chown pi:pi "$ENV_FILE" 2>/dev/null || true
        return 0
    fi
    
    mkdir -p "$(dirname "$ENV_FILE")"
    
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
# 
# SUPPORTED FORMATS (auto-detected):
# - Unbound native (local-zone:)
# - RPZ (CNAME .)
# - Wildcard (*.domain.com)
# - Hosts (0.0.0.0 domain.com)
# - Adblock (||domain.com^)
# - DNSMasq (address=/domain.com/0.0.0.0)
# - Plain domains (domain.com)
# =============================================================================

# OISD Big List (Unbound format)
oisd_big|https://big.oisd.nl/unbound|/home/pi/.firewalla/config/unbound_local/oisd_big.conf

# OISD Light List (Unbound format)
# oisd_light|https://oisd.nl/unbound|/home/pi/.firewalla/config/unbound_local/oisd_light.conf

# HaGeZi Pro List - Unbound format
# hagezi_pro|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/pro.txt|/home/pi/.firewalla/config/unbound_local/hagezi_pro.conf

# HaGeZi Ultimate - Unbound format
# hagezi_ultimate|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/ultimate.txt|/home/pi/.firewalla/config/unbound_local/hagezi_ultimate.conf

# HaGeZi TIF - RPZ format (auto-converts)
# hagezi_tif|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/tif.txt|/home/pi/.firewalla/config/unbound_local/hagezi_tif.conf

# HaGeZi DoH - RPZ format (auto-converts)
# hagezi_doh|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/doh.txt|/home/pi/.firewalla/config/unbound_local/hagezi_doh.conf

# HaGeZi TIF - Wildcard format (auto-converts)
# hagezi_tif_wildcard|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/tif.txt|/home/pi/.firewalla/config/unbound_local/hagezi_tif_wildcard.conf

# Steven Black's Hosts File (hosts format - auto-converts)
# stevenblack|https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|/home/pi/.firewalla/config/unbound_local/stevenblack.conf

# EasyList Adblock Format (auto-converts)
# easylist|https://easylist.to/easylist/easylist.txt|/home/pi/.firewalla/config/unbound_local/easylist.conf

# Custom lists can be added here
# custom_list|https://example.com/blocklist.txt|/home/pi/.firewalla/config/unbound_local/custom.conf
EOF
    
    chown pi:pi "$ENV_FILE" 2>/dev/null || true
    chown -R pi:pi "$(dirname "$ENV_FILE")" 2>/dev/null || true
    
    log "✓ Created .env configuration template at $ENV_FILE"
    log "ℹ Please edit $ENV_FILE to customize your blocklists"
    log "  Example: nano $ENV_FILE"
    log "  The script will NEVER overwrite this file once it exists"
    log "✓ File ownership set to pi:pi"
}

process_list() {
    local list_name="$1"
    local url="$2"
    local output_file="$3"
    local temp_file="/tmp/${list_name}_tmp.conf"
    
    log "=========================================="
    log "Processing list: $list_name"
    log "=========================================="
    
    if ! download_with_retry "$url" "$temp_file" "$list_name"; then
        log "✗ Failed to download $list_name - skipping"
        return 1
    fi
    
    if ! validate_file "$temp_file" "$list_name"; then
        log "✗ Validation/conversion failed for $list_name - skipping"
        rm -f "$temp_file"
        return 1
    fi
    
    old_count=$(get_block_count "$output_file")
    log "Old block count for $list_name: $old_count"
    
    if ! apply_update "$temp_file" "$output_file" "$list_name"; then
        log "✗ Failed to apply update for $list_name - skipping"
        rm -f "$temp_file"
        return 1
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        new_count=$(get_block_count "$output_file")
        log "New block count for $list_name: $new_count"
        
        if [[ $new_count -gt $old_count ]]; then
            log "✓ $list_name increased by $((new_count - old_count)) domains"
        elif [[ $new_count -lt $old_count ]]; then
            log "ℹ $list_name decreased by $((old_count - new_count)) domains"
        else
            log "ℹ $list_name unchanged"
        fi
        
        if [[ -f "${output_file}.backup" ]]; then
            rm -f "${output_file}.backup"
            log "Cleaned up backup file for $list_name"
        fi
    else
        log "DRY RUN: Would have reported block count changes"
    fi
    
    if [[ -f "$temp_file" ]]; then
        rm -f "$temp_file"
        log "Cleaned up temporary file for $list_name"
    fi
    
    log "✓ Successfully updated $list_name"
    return 0
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help        Show this help message
  -d, --dry-run     Perform a dry run (download and validate, but don't apply)
  -q, --quiet       Quiet mode (minimal output, only log to file)
  -e, --env FILE    Use specified .env file instead of default
  -v, --version     Show version information

Supported Formats (auto-detected):
  - Unbound native (local-zone:)
  - RPZ (CNAME .)
  - Wildcard (*.domain.com)
  - Hosts (0.0.0.0 domain.com)
  - Adblock (||domain.com^)
  - DNSMasq (address=/domain.com/0.0.0.0)
  - Plain domains (domain.com)

Log Rotation:
  - The script automatically configures log rotation
  - Logs are rotated daily
  - 7 days of logs are kept
  - Old logs are compressed

Examples:
  $0                 Run normally
  $0 --dry-run       Test without applying changes
  $0 --quiet         Run silently (good for cron jobs)
  $0 --env custom.env Use a custom .env file

Environment Variables:
  ENV_FILE         Path to .env file (default: /home/pi/.firewalla/config/blocklists.env)
  LOG_FILE         Path to log file (default: /var/log/unbound_update.log)
  MAX_RETRIES      Number of download retries (default: 3)
  RETRY_DELAY      Delay between retries in seconds (default: 5)
  DRY_RUN          Set to "true" for dry run
  QUIET            Set to "true" for quiet mode
  MIN_DISK_SPACE   Minimum disk space in MB (default: 50)
EOF
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -q|--quiet)
                QUIET="true"
                shift
                ;;
            -e|--env)
                ENV_FILE="$2"
                shift 2
                ;;
            -v|--version)
                echo "Firewalla Unbound Blocklist Update Script v2.3"
                exit 0
                ;;
            *)
                log "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "=========================================="
    log "Starting Unbound blocklist update"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "** DRY RUN MODE - No changes will be applied **"
    fi
    log "=========================================="
    
    log "Running pre-flight checks..."
    check_curl_installed
    check_command grep
    check_command systemctl
    check_disk_space
    
    if [[ $EUID -ne 0 ]]; then
        log "Note: Not running as root. Some operations require sudo."
        log "  The script will use sudo for:"
        log "  - Installing curl (if needed)"
        log "  - Restarting Unbound"
    fi
    
    # Setup log rotation
    setup_log_rotation "$LOG_FILE"
    
    create_env_template
    
    declare -a BLOCKLISTS
    if ! parse_env_file "$ENV_FILE" BLOCKLISTS; then
        log "WARNING: No valid lists found in .env file"
        log "  Please edit $ENV_FILE to add your blocklists"
        log "  Format: NAME|URL|OUTPUT_FILE"
        log "  Example: oisd_big|https://big.oisd.nl/unbound|/home/pi/.firewalla/config/unbound_local/oisd_big.conf"
        error_exit "No blocklists configured"
    fi
    
    local failed_lists=()
    local success_lists=()
    for list_entry in "${BLOCKLISTS[@]}"; do
        IFS='|' read -r list_name url output_file <<< "$list_entry"
        
        if process_list "$list_name" "$url" "$output_file"; then
            success_lists+=("$list_name")
        else
            failed_lists+=("$list_name")
            log "✗ Failed to update $list_name - continuing with next list"
        fi
    done
    
    if [[ ${#success_lists[@]} -gt 0 ]]; then
        fix_ownership "/home/pi/.firewalla/config"
        
        if ! restart_unbound; then
            error_exit "Update failed during restart phase"
        fi
        
        if [[ "$DRY_RUN" != "true" ]]; then
            verify_unbound
        else
            log "DRY RUN: Skipping Unbound verification"
        fi
    else
        log "ERROR: No lists were successfully updated!"
        log "  Please check your .env file and URLs"
        error_exit "All lists failed to update"
    fi
    
    log "=========================================="
    log "Update Summary:"
    log "✓ Successfully updated: ${#success_lists[@]} list(s)"
    if [[ ${#success_lists[@]} -gt 0 ]]; then
        for list in "${success_lists[@]}"; do
            log "  - $list"
        done
    fi
    if [[ ${#failed_lists[@]} -gt 0 ]]; then
        log "⚠ Failed to update: ${#failed_lists[@]} list(s)"
        for list in "${failed_lists[@]}"; do
            log "  - $list"
        done
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "ℹ DRY RUN - No changes were applied"
    fi
    log "=========================================="
    log "Update completed!"
    log "=========================================="
}

# =============================================================================
# Execution
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
