Firewalla Unbound: Advanced Blocklist Integration (External Lists)
==================================================================

This configuration allows you to manually add massive, unsupported (for MSP lite users), third-party blocklists directly into Unbound on your Firewalla. Use this if you need "Big" or "Ultimate" protection that goes beyond the standard Firewalla-provided target lists.

Files in this Repository
------------------------

*   **`update_dns.sh`** – The main script that downloads, validates, and updates your blocklists. Auto-detects and converts multiple formats.
*   **`blocklists.env`** – Your personal configuration file to define which lists to use. **This file is never overwritten by the script after creation.**
*   **`README.md`** – This guide.

* * *

Critical: Before You Begin
--------------------------

### 1\. External List Management

*   **Scope:** This guide is strictly for non-Firewalla provided lists (e.g., OISD big, HaGeZi Ultimate or Pro++).
*   **App Stats:** Blocks from these external lists **will not** appear in your "Blocked Flows" or app stats. I do have CLI commands below that will show you live, past 1 hour, and past 7 day blocked sites.
*   **App Toggles:** You cannot enable or disable these lists via the Firewalla app interface. All management must be done via SSH.
*   **DNS Booster:** You must keep the **DNS Booster ON** in the Firewall app. It is required for Firewalla to intercept your traffic and hand it to Unbound.
*   **Unbound:** You must be using Unbound as the DNS resolver. Please visit my [Firewalla Unbound Configuration repo](https://github.com/upmcplanetracker/firewalla-unbound-DoT-config) first to learn how to set the Unbound cache size.

### 2\. Format & Compatibility

*   **Requirement:** You must use **Unbound-formatted** lists. The file must contain `local-zone:` entries.
*   **Warning:** Standard "hosts" files (starting with `0.0.0.0` or `127.0.0.1`) **will break Unbound** if not converted. The script **automatically detects and converts** many common formats (see below).
*   **IP-only lists are not supported** – Unbound requires domain names to block. The script will reject any list that doesn't contain valid domain names.

### 3\. Supported Formats (Auto-Detected & Converted)

The script can automatically detect and convert the following formats to Unbound's `local-zone` format:

| Format | Example | Notes |
|----------|----------|----------|
| Unbound Native | `local-zone: "example.com." always_null` | Already correct |
| RPZ | `example.com. CNAME .` | Converts to `local-zone` |
| Wildcard | `*.example.com` | Blocks entire domain and all subdomains |
| Hosts File | `0.0.0.0 example.com` or `127.0.0.1 example.com` | Extracts domain names |
| Adblock | `||example.com^` | Used by uBlock Origin, Pi-hole, AdGuard |
| DNSMasq | `address=/example.com/0.0.0.0` | Used by some router firmwares |
| Plain Domains | `example.com` | One domain per line |

If the script cannot detect the format, it will **skip** the list and continue with the next one, preventing Unbound from being broken.

Unbound does not support IP only blocklists. This script will **skip** those to prevent Unbound from crashing.

### 4\. Hardware Tiers & Memory

Large lists (~400k+ domains) consume significant RAM. Match your list choice to your hardware:

| Hardware Tier | Firewalla Models | Recommended Unbound Cache | Max Domain Recommendation |
| :--- | :--- | :--- | :--- |
| **Entry** | Purple SE | 16m / 32m | **Avoid Big Lists** (Use Light only/may want to stick with built in lists) |
| **Mid** | Gold, Gold SE, Orange, Purple | 32m / 64m | Up to 100k domains |
| **High** | Gold Plus, Gold Pro | 128m / 256m | 400k+ domains (Big/Ultimate) |

* * *

Installation & Configuration
----------------------------

### Step 1: Install Prerequisites

SSH into your Firewalla and ensure required tools are available:

    unalias apt
    sudo apt update
    # NEVER run sudo apt upgrade - it will probably break your Firewalla
    
    # Install nano for editing (if not already installed)
    sudo apt install nano

    # curl is already built into Firewalla.

### Step 2: Download the Update Script

Download the enhanced update script directly to your Firewalla:

    # Navigate to your home directory
    cd /home/pi
    
    # Download the script from this repository
    curl -O https://raw.githubusercontent.com/upmcplanetracker/firewalla-huge-blocklists/main/update_dns.sh
    
    # Make it executable
    chmod +x /home/pi/update_dns.sh

**Review the script before running** (recommended):

    cat /home/pi/update_dns.sh

### Step 3: Set Up Your Blocklists (.env file)

The script uses a `.env` file to manage your blocklists. You have two options:

#### Option A: Let the script create it (Easiest)

Simply run the script once. It will create a template `blocklists.env` file at `/home/pi/.firewalla/config/blocklists.env`.

    sudo /home/pi/update_dns.sh

The script will show output like:

    [timestamp] ✓ Created .env configuration template at /home/pi/.firewalla/config/blocklists.env
    [timestamp] ℹ Please edit /home/pi/.firewalla/config/blocklists.env to customize your blocklists

**Important:** The script will **never overwrite** this file once it exists. Your edits are safe.

#### Option B: Download the .env file directly

Download the pre-configured `blocklists.env` file from the repository:

    # Create the directory if it doesn't exist
    mkdir -p /home/pi/.firewalla/config
    
    # Download the .env file
    curl -o /home/pi/.firewalla/config/blocklists.env \
      https://raw.githubusercontent.com/upmcplanetracker/firewalla-huge-blocklists/main/blocklists.env

#### Edit the .env file

Whether you used Option A or B, edit the file to enable the lists you want:

    sudo nano /home/pi/.firewalla/config/blocklists.env

**.env file format:**

    LIST_NAME|URL|OUTPUT_FILE

Each line defines one blocklist. To enable a list, remove the `#` at the start of its line. To disable a list, add a `#` to comment it out.

**Example with multiple lists enabled:**

    # OISD Big List (Recommended for High tier hardware)
    oisd_big|https://big.oisd.nl/unbound|/home/pi/.firewalla/config/unbound_local/oisd_big.conf
    
    # HaGeZi Pro List (auto-converts from Unbound format)
    hagezi_pro|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/pro.txt|/home/pi/.firewalla/config/unbound_local/hagezi_pro.conf
    
    # HaGeZi TIF (RPZ format - auto-converts)
    hagezi_tif|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/tif.txt|/home/pi/.firewalla/config/unbound_local/hagezi_tif.conf
    
    # Steven Black's Hosts File (hosts format - auto-converts)
    stevenblack|https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|/home/pi/.firewalla/config/unbound_local/stevenblack.conf

**Note:** The script automatically removes blocklist files that are no longer enabled in your `.env` file. If you comment out a list, its `.conf` file will be deleted on the next run.

### Step 4: Run the Script to Download Your Lists

Now run the script again to download all the lists you enabled:

    sudo /home/pi/update_dns.sh

The script will:

1.  Read your `.env` file
2.  Download each enabled list
3.  Auto-detect and convert the format (if needed)
4.  Validate each file (checks for proper format, not HTML, etc.)
5.  Install each list to the specified location
6.  Create backups before replacing existing files
7.  Remove any obsolete blocklist files no longer in `.env`
8.  Clean up any old `include:` lines from your main local Unbound config

**Verify the files were created:**

    ls -lh /home/pi/.firewalla/config/unbound_local/

### Step 5: Configure Unbound (Automatic!)

**Firewalla automatically includes all `.conf` files in the `unbound_local` directory.** You don't need to manually add `include:` lines for each blocklist. The script will also **automatically remove any old `include:` lines** from your `unbound_custom.conf` file that point to this directory.

If you need to customize Unbound settings (like cache size), edit:

    sudo nano /home/pi/.firewalla/config/unbound_local/unbound_custom.conf

Example configuration:

    server:
        # Adjust these values based on your Hardware Tier from the table above
        msg-cache-size: 128m
        rrset-cache-size: 256m
        
        prefetch: yes
        prefetch-key: yes
    
        # Do NOT add include: lines for blocklists here!
        # Firewalla loads all .conf files in unbound_local automatically.

### Step 6: Restart & Test

Restart Unbound to apply the changes:

    sudo systemctl restart unbound

**Verify Unbound is running:**

    sudo systemctl status unbound

### Step 7: Schedule Automatic Updates with Cron

The script can be scheduled to run automatically using cron. Here are several scheduling options:

#### Option 1: Weekly Updates (Recommended)

Update all lists every Sunday at midnight:

    crontab -e

Add this line:

    0 0 * * 0 /home/pi/update_dns.sh

#### Option 2: Daily Updates

Update all lists every day at 2:00 AM:

    0 2 * * * /home/pi/update_dns.sh

#### Option 3: Multiple Times Per Week

Update on Sunday, Wednesday, and Friday at midnight:

    0 0 * * 0,3,5 /home/pi/update_dns.sh

#### Option 4: Quiet Mode for Cron (Recommended)

To reduce log noise, use the `--quiet` flag:

    0 0 * * 0 /home/pi/update_dns.sh --quiet

**Apply Changes:**

To ensure the crontab is loaded and the network stack syncs correctly, restart your Firewalla service (will take 1-2 minutes for your internet to return):

    sudo systemctl restart firewalla

* * *

Script Features
---------------

The `update_dns.sh` script includes several safety and convenience features:

### Core Features

*   **Automatic curl detection** – `curl` should be preinstalled but it if isn't the script will gracefully exit
*   **Retry logic** – Retries download up to 3 times on failure
*   **Multiple validation checks** – Validates file format, size, and content
*   **Automatic rollback** – Restores previous config if update fails
*   **Detailed logging** – Logs all activity to `/var/log/unbound_update.log`
*   **Block count reporting** – Shows before/after domain counts for each list
*   **Disk space check** – Warns if disk space is low (but doesn't fail)
*   **Unbound verification** – Tests that Unbound restarts successfully

### Format Support

*   **Auto-detects and converts** 7 different formats to Unbound format
*   **Skips unsupported formats** – Continues with next list if format is unknown
*   **Prevents IP-only lists** – Rejects lists with only IP addresses (Unbound can't use them)

### Cleanup & Maintenance

*   **Removes obsolete blocklists** – Deletes `.conf` files that are no longer in your `.env`
*   **Cleans up old `include:` lines** – Removes redundant includes from `unbound_custom.conf`
*   **Safe deletion** – Only removes files marked as generated by the script
*   **Log rotation** – Automatically configures daily log rotation (keeps 7 days)

* * *

Testing & Verification
----------------------

### Test Your Blocklist

Since Firewalla's DNS Booster intercepts DNS queries, you should test your blocklist using one of these methods:

**Option 1: Query Unbound Directly (Most Reliable)**

    nslookup ad.doubleclick.net 127.0.0.1

**Option 2: Test a Domain That's Definitely in OISD**

    # OISD definitely blocks these domains
    nslookup ad.doubleclick.net
    nslookup doubleclick.net
    nslookup googleadservices.com

**Option 3: Check the Blocklist File Directly**

    # See if a domain is in the list
    grep "doubleclick" /home/pi/.firewalla/config/unbound_local/oisd_big.conf

**Success:** If querying Unbound directly, you should see `0.0.0.0` or `NXDOMAIN`.  
**Failure:** If you see a real IP address, the blocklist is not loading correctly.

> **Note:** If you see `connection refused` when querying `127.0.0.1`, this is normal on some Firewalla setups. Use Option 2 or 3 instead.

### Verify Blocklist is Loaded in Unbound

    # Check Unbound status
    sudo systemctl status unbound
    
    # Count entries in the blocklist
    grep -c "local-zone:" /home/pi/.firewalla/config/unbound_local/oisd_big.conf

### Verify Blocklist Sizes

    # Count domains in each list
    for file in /home/pi/.firewalla/config/unbound_local/*.conf; do
        if [[ "$file" != *"unbound_custom.conf" && "$file" != *"unbound_local.conf" ]]; then
            echo "$(basename "$file"): $(grep -c 'local-zone:' "$file") entries"
        fi
    done

### Check Unbound Logs

If something isn't working, check the Unbound logs:

    sudo journalctl -u unbound -n 50

### Check Update Logs

View the script's activity log:

    # View entire log
    cat /var/log/unbound_update.log
    
    # View last 20 lines
    tail -20 /var/log/unbound_update.log
    
    # Follow log in real-time
    tail -f /var/log/unbound_update.log

* * *

Rescue Your Firewalla
---------------------

If Unbound fails to start after an update, your internet may stop working. Here's how to recover:

### Option 1: Use the Script's Auto-Restore

The script automatically creates backups before updating. If Unbound fails to restart, it will restore all backups automatically. Check the logs:

    tail -50 /var/log/unbound_update.log

### Option 2: Manually Remove Problematic Lists

If the script couldn't recover automatically:

    # 1. Move all blocklist files out of the directory
    sudo mkdir /tmp/unbound_backup
    sudo mv /home/pi/.firewalla/config/unbound_local/*.conf /tmp/unbound_backup/
    
    # 2. Restart Unbound (should start with default config)
    sudo systemctl restart unbound
    
    # 3. Check if Unbound is running
    sudo systemctl status unbound
    
    # 4. If it's running, troubleshoot by adding lists back one by one
    # Move files back one at a time and restart Unbound after each

### Option 3: Fix Invalid Include Lines

If the script somehow didn't clean up old `include:` lines:

    # Check for include lines in unbound_custom.conf
    grep "^include:" /home/pi/.firewalla/config/unbound_local/unbound_custom.conf
    
    # Remove all include lines pointing to unbound_local
    sudo sed -i '/^include:.*unbound_local/d' /home/pi/.firewalla/config/unbound_local/unbound_custom.conf

### Option 4: Remove Specific Invalid Blocklist

If you know which list is causing the problem:

    # Remove the problem file (replace with actual filename)
    sudo rm /home/pi/.firewalla/config/unbound_local/problem_list.conf
    
    # Restart Unbound
    sudo systemctl restart unbound

### Option 5: Start Fresh

If nothing works:

    # 1. Disable all blocklists in .env
    sudo nano /home/pi/.firewalla/config/blocklists.env
    # Comment out ALL lines by adding # at the start of each
    
    # 2. Clean up all generated blocklist files
    sudo rm /home/pi/.firewalla/config/unbound_local/*.conf
    
    # 3. Restart Unbound
    sudo systemctl restart unbound
    
    # 4. Re-enable lists one by one in .env and run the script

* * *

Customization
-------------

### Adding a New Blocklist

To add a new blocklist, simply edit your `.env` file:

    sudo nano /home/pi/.firewalla/config/blocklists.env

Add a new line with the format:

    list_name|https://url-to-your-list|/home/pi/.firewalla/config/unbound_local/your_list.conf

The script will auto-detect the format (RPZ, hosts, adblock, wildcard, etc.) and convert it.

Run the script again to download the new list:

    sudo /home/pi/update_dns.sh

### Removing a Blocklist

To remove a blocklist, either:

1.  Comment it out in the `.env` file by adding `#` at the start of the line, OR
2.  Delete the line entirely

The script will automatically delete the corresponding `.conf` file on the next run.

### Popular Blocklist URLs

| List Name | URL | Size | Recommended Hardware |
| :--- | :--- | :--- | :--- |
| OISD Big | `https://big.oisd.nl/unbound` | ~400k+ | High |
| HaGeZi Pro | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/pro.txt` | ~150k | Mid |
| HaGeZi Ultimate | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/ultimate.txt` | ~500k+ | High |
| HaGeZi TIF (RPZ) | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/tif.txt` | ~1.5M | High |
| HaGeZi DoH (RPZ) | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/rpz/doh.txt` | ~3-5k | Any |
| Steven Black's Hosts | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` | ~100k+ | Mid/High |

> **Note:** The OISD Light list is already built into Firewalla's standard protection (listed in the app as just OISD) and does not need to be added manually.

* * *

Whitelisting
------------

### How to Whitelist

**App Rules Override Everything:**

If an external list blocks a site you need:

1.  Open the Firewalla App
2.  Tap **Rules** -> **Add Rule**
3.  Target: The domain you want to allow
4.  Action: **Allow**

**Why this works:** The Firewalla DNS Booster sees your traffic first. If it sees an "Allow" rule, it resolves the IP immediately and never forwards the request to Unbound's blocklist.

* * *

Troubleshooting
---------------

### Unbound won't start after adding the list

Check these common issues:

    # Check if any blocklist files exist
    ls -la /home/pi/.firewalla/config/unbound_local/*.conf
    
    # Check if any file has content
    head -20 /home/pi/.firewalla/config/unbound_local/oisd_big.conf
    
    # Check Unbound logs for errors
    sudo journalctl -u unbound -n 50
    
    # Check if there are empty domain entries in any file
    grep -E "local-zone:[[:space:]]*$" /home/pi/.firewalla/config/unbound_local/*.conf

### The update script fails with "Download was empty"

    # Check your internet connection
    ping -c 4 8.8.8.8
    
    # Try downloading manually
    curl -v https://big.oisd.nl/unbound
    
    # The list provider may be temporarily unavailable - the script will keep your current list

### "Permission denied" when running the script

    # Make the script executable
    chmod +x /home/pi/update_dns.sh
    
    # Check ownership
    ls -la /home/pi/update_dns.sh
    
    # If needed, change owner
    sudo chown pi:pi /home/pi/update_dns.sh

### No valid lists found in .env file

    # Check your .env file
    cat /home/pi/.firewalla/config/blocklists.env
    
    # Make sure you have uncommented at least one list
    # Lines should not start with #
    # Format should be: NAME|URL|OUTPUT_FILE

### The script downloaded HTML instead of the list

*   The script automatically detects this and won't install it
*   Check the URL is correct
*   Some providers may have changed their URL format

### Script not running from crontab

    # Test that the script works when run manually
    sudo /home/pi/update_dns.sh
    
    # Check that the script has execute permissions
    ls -l /home/pi/update_dns.sh
    
    # Use full path to script in crontab
    0 0 * * 0 /home/pi/update_dns.sh
    
    # Check if logs show cron execution
    grep update_dns /var/log/syslog
    
    # Use the absolute path to sudo in crontab if needed
    0 0 * * 0 /usr/bin/sudo /home/pi/update_dns.sh --quiet

### Format detection error

If the script says "Unable to detect format", it means the list is in an unrecognized format. The script will skip it and continue. To fix:

1.  Check the URL is correct
2.  Make sure the list contains domain names (not just IP addresses)
3.  Try a different URL from the same provider (e.g., use the Unbound format instead of RPZ)

### "Connection refused" when testing DNS

This is normal on some Firewalla setups. DNS Booster handles queries differently. Use file-based verification instead:

    # Check if the blocklist has entries
    grep -c "local-zone:" /home/pi/.firewalla/config/unbound_local/oisd_big.conf
    
    # Check if a specific domain is in the list
    grep "example.com" /home/pi/.firewalla/config/unbound_local/oisd_big.conf

* * *

Monitoring
----------

### Check Update History

The script logs all activity to `/var/log/unbound_update.log`:

    # View the log
    cat /var/log/unbound_update.log
    
    # See when updates ran
    grep "Starting Unbound blocklist update" /var/log/unbound_update.log
    
    # Check for errors
    grep ERROR /var/log/unbound_update.log
    
    # See which lists were updated
    grep "Processing list" /var/log/unbound_update.log

### Monitor Memory Usage

If you're using large lists, monitor your Firewalla's memory:

    free -h

### View Block Statistics

External blocklists don't show in the Firewalla app, but you can count entries:

    # Count domains in each list
    for file in /home/pi/.firewalla/config/unbound_local/*.conf; do
        if [[ "$file" != *"unbound_custom.conf" && "$file" != *"unbound_local.conf" ]]; then
            echo "$(basename "$file"): $(grep -c 'local-zone:' "$file") entries"
        fi
    done
    
    # Compare with previous counts from logs
    grep "New block count" /var/log/unbound_update.log

View the top 40 weekly blocks:
```
sudo journalctl -u unbound --since "7 days ago" --no-pager \
  | grep -F "always_null" \
  | awk '{for(i=1;i<=NF;i++) if($i=="info:") print $(i+1)}' \
  | sort | uniq -c | sort -nr | head -n 40
```
View the top 20 daily blocks:
```
sudo journalctl -u unbound --since "24 hours ago" --no-pager \
  | grep -F "always_null" \
  | awk '{for(i=1;i<=NF;i++) if($i=="info:") print $(i+1)}' \
  | sort | uniq -c | sort -nr | head -n 20
```
View blocks as they happen:
```
sudo journalctl -u unbound -f -o cat \
  | grep --line-buffered always_null \
  | awk '{count++; print strftime("%H:%M:%S"), count, $0; fflush()}'
```

* * *

Updating the Script
-------------------

If you need to update the script to a newer version:

    cd /home/pi
    
    # Backup current script
    cp update_dns.sh update_dns.sh.backup
    
    # Download new version
    curl -O https://raw.githubusercontent.com/upmcplanetracker/firewalla-huge-blocklists/main/update_dns.sh
    
    # Make it executable
    chmod +x /home/pi/update_dns.sh
    
    # Test the new version
    sudo /home/pi/update_dns.sh --dry-run

* * *

Important Notes
---------------

*   **Backup your configuration** before making changes
*   **Test thoroughly** after any change
*   **Monitor your system** for memory usage when using large lists
*   **Keep DNS Booster ON** – it's required for proper operation
*   **Manual updates only** – these lists won't appear in the Firewalla app
*   **Check logs** if something doesn't work – `/var/log/unbound_update.log`
*   **Your .env file is safe** – the script will never overwrite it
*   **Firewalla auto-loads all `.conf` files** – no `include:` lines needed
*   **The script auto-cleans up** old lists and redundant includes

* * *

Additional Resources
--------------------

*   [Firewalla Unbound Configuration](https://github.com/upmcplanetracker/firewalla-unbound-DoT-config) – Configure Unbound cache size
*   [OISD Blocklist](https://oisd.nl/) – The default list used in this guide
*   [HaGeZi Blocklists](https://github.com/hagezi/dns-blocklists) – Alternative blocklist provider
*   [Firewalla Community](https://community.firewalla.com/) – Get help from other users

* * *

Contributing
------------

Found a bug or have an improvement? Feel free to:

*   Open an issue
*   Submit a pull request
*   Suggest new features

* * *

Disclaimer
----------

Not affiliated with or endorsed by Firewalla, OISD, or any other organization. Use at your own risk. Always backup your configuration before making changes.
