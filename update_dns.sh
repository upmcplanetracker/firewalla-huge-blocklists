#!/bin/bash

# Paths
CONF_FILE="/home/pi/.firewalla/config/unbound_local/oisd_big.conf"
TEMP_FILE="/tmp/oisd_big_tmp.conf"
URL="https://big.oisd.nl/unbound"

echo "Starting OISD update..."

# 1. Download to temporary file
# -f: fail on server errors, -L: follow redirects
curl -f -L -o "$TEMP_FILE" "$URL"

# 2. Safety Check: Did the download fail or is the file empty?
if [ ! -s "$TEMP_FILE" ]; then
    echo "Update Failed: Download was empty or server returned an error. Keeping old list."
    exit 1
fi

# 3. Safety Check: Did we get HTML?
if grep -qiE "<html|<head|<body|<!DOCTYPE" "$TEMP_FILE"; then
    echo "Update Failed: Downloaded an HTML page instead of the list. Keeping old list."
    rm "$TEMP_FILE"
    exit 1
fi

# 4. Content Check: Does it actually look like an Unbound list?
# OISD Unbound files MUST contain "local-zone:"
if ! grep -q "local-zone:" "$TEMP_FILE"; then
    echo "Update Failed: File format does not look like Unbound config. Keeping old list."
    rm "$TEMP_FILE"
    exit 1
fi

# 5. All checks passed!
echo "Checks passed. Applying new list and restarting Unbound..."
mv "$TEMP_FILE" "$CONF_FILE"
sudo systemctl restart unbound
echo "Update complete."
