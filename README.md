
Firewalla Unbound: Advanced Blocklist Integration (External Lists)
==================================================================

This configuration allows you to manually add massive, unsupported (for MSP lite users), third-party blocklists directly into Unbound on your Firewalla. Use this if you need "Big" or "Ultimate" protection that goes beyond the standard Firewalla-provided target lists.

Files in this Repository
------------------------

*   **`update_dns.sh`** - Automated script to download, validate, and update blocklists with safety features
*   **`README.md`** - This guide

* * *

Critical: Before You Begin
--------------------------

### 1\. External List Management

*   **Scope:** This guide is strictly for non-Firewalla provided lists (e.g., OISD big, HaGeZi Ultimate or Pro++).
*   **App Stats:** Blocks from these external lists **will not** appear in your "Blocked Flows" or app stats.
*   **App Toggles:** You cannot enable or disable these lists via the Firewalla app interface. All management must be done via SSH.
*   **DNS Booster:** You must keep the **DNS Booster ON** in the Firewall app. It is required for Firewalla to intercept your traffic and hand it to Unbound.
*   **Unbound:** You must be using Unbound as the DNS resolver. Please visit my [Firewalla Unbound Configuration repo](https://github.com/upmcplanetracker/firewalla-unbound-DoT-config) first to learn how to set the Unbound cache size.

### 2\. Format & Compatibility

*   **Requirement:** You must use **Unbound-formatted** lists. The file must contain `local-zone:` entries.
*   **Warning:** Standard "hosts" files (starting with `0.0.0.0` or `127.0.0.1`) **will break Unbound**. If a list is not properly formatted, your internet will stop working.

### 3\. Hardware Tiers & Memory

Large lists (~400k+ domains) consume significant RAM. Match your list choice to your hardware:

Hardware Tier

Firewalla Models

Recommended Unbound Cache

Max Domain Recommendation

**Entry**

Purple SE, Blue Plus

16m / 32m

**Avoid Big Lists** (Use Light only)

**Mid**

Gold, Purple

32m / 64m

Up to 100k domains

**High**

Gold Plus, Gold Pro

128m / 256m

400k+ domains (Big/Ultimate)

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
    
    # curl will be automatically installed by the script if needed

### Step 2: Download the Update Script

Download the enhanced update script directly to your Firewalla:

    # Navigate to your home directory
    cd /home/pi
    
    # Download the script from this repository
    curl -O https://raw.githubusercontent.com/upmcplanetracker/firewalla-unbound-advanced-blocklists/main/update_dns.sh
    
    # Make it executable
    chmod +x /home/pi/update_dns.sh

**Review the script before running** (recommended):

    cat /home/pi/update_dns.sh

**Using a different blocklist?** Edit the URL in the script or use environment variables:

    # Edit the script directly
    nano /home/pi/update_dns.sh
    # Change the URL variable at the top
    
    # OR use environment variable (no script editing needed)
    BLOCKLIST_URL="https://hagezi.net/unbound" ./update_dns.sh

### Step 3: First Time Run (Important!)

**You must run the script manually once before editing the Unbound config.** If you skip this, Unbound will try to load a file that doesn't exist and will fail to start.

    /home/pi/update_dns.sh

**Verify the file was created:**

    ls -lh /home/pi/.firewalla/config/unbound_local/oisd_big.conf

### Step 4: Configure Unbound

Now that the blocklist file exists, point Unbound to it. If you already have other things in your `.conf` file (such as DNS over TLS), you can add this into the same file.

**File Path:** `/home/pi/.firewalla/config/unbound_local/unbound_custom.conf`

    nano /home/pi/.firewalla/config/unbound_local/unbound_custom.conf

Add or modify the following configuration:

    server:
        # Adjust these values based on your Hardware Tier from the table above
        msg-cache-size: 128m
        rrset-cache-size: 256m
        
        prefetch: yes
        prefetch-key: yes
    
        # Add your blocklist(s) here:
        include: "/home/pi/.firewalla/config/unbound_local/oisd_big.conf"
        # include: "/home/pi/.firewalla/config/unbound_local/blocklist_2.conf"  # For additional lists

### Step 5: Restart & Test

Restart Unbound to apply the changes:

    sudo systemctl restart unbound

**Verify Unbound is running:**

    sudo systemctl status unbound

### Step 6: Schedule Automatic Updates

Add the script to your crontab to update the list weekly (Sundays at midnight):

    crontab -e

Add this line:

    0 0 * * 0 /home/pi/update_dns.sh

**Apply Changes:**

To ensure the crontab is loaded and the network stack syncs correctly, reboot your Firewalla (will take 3-4 minutes for your internet to return):

    sudo reboot

* * *

Script Features
---------------

The `update_dns.sh` script includes several safety features:

📦 **Automatic curl installation** - Installs curl if not present

🔄 **Retry logic** - Retries download up to 3 times on failure

✅ **Multiple validation checks** - Validates file format, size, and content

↩️ **Automatic rollback** - Restores previous config if update fails

📝 **Detailed logging** - Logs all activity to /var/log/unbound\_update.log

📊 **Block count reporting** - Shows before/after domain counts

💾 **Disk space check** - Ensures enough space before downloading

🔍 **Unbound verification** - Tests that Unbound restarts successfully

* * *

Testing & Verification
----------------------

### Test Your Blocklist

Run a lookup for a domain known to be on your blocklist (e.g., `doubleclick.net`):

    nslookup doubleclick.net

**Success:** The result should return `0.0.0.0` or `NXDOMAIN`.

**Failure:** If it returns a real IP address, the blocklist is not loading correctly.

### Verify Blocklist Size

Check how many domains are being blocked:

    grep -c "local-zone:" /home/pi/.firewalla/config/unbound_local/oisd_big.conf

### Check Update Logs

View the script's activity log:

    # View entire log
    cat /var/log/unbound_update.log
    
    # View last 20 lines
    tail -20 /var/log/unbound_update.log
    
    # Follow log in real-time
    tail -f /var/log/unbound_update.log

### Check Unbound Status

If something isn't working, check the Unbound logs:

    sudo journalctl -u unbound -n 50

* * *

Customization
-------------

### Using Multiple Blocklists

You have several options:

**Option 1: Use environment variables with the same script**

    # Run for different lists
    BLOCKLIST_URL="https://big.oisd.nl/unbound" CONF_FILE="/home/pi/.firewalla/config/unbound_local/oisd_big.conf" ./update_dns.sh
    BLOCKLIST_URL="https://hagezi.net/unbound" CONF_FILE="/home/pi/.firewalla/config/unbound_local/hagezi.conf" ./update_dns.sh

**Option 2: Create separate scripts** for each list (copy the main script and edit URL)

**Option 3: Use one script with multiple downloads** - Edit the script to download and save multiple lists.

Then update your Unbound config to include all lists:

    include: "/home/pi/.firewalla/config/unbound_local/oisd_big.conf"
    include: "/home/pi/.firewalla/config/unbound_local/hagezi_pro.conf"

### Changing the Blocklist URL

Option 1: Edit the script:

    nano /home/pi/update_dns.sh
    # Change the URL variable at the top

Option 2: Use environment variable (no script editing):

    BLOCKLIST_URL="https://your-preferred-list/unbound" ./update_dns.sh

**Popular Unbound-formatted lists:**

*   OISD Big: `https://big.oisd.nl/unbound`
*   OISD Light: `https://oisd.nl/unbound`
*   HaGeZi Pro: `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/pro.txt`
*   HaGeZi Ultimate: `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/ultimate.txt`

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

    # Check if the conf file exists
    ls -la /home/pi/.firewalla/config/unbound_local/
    
    # Check if the file has content
    head -20 /home/pi/.firewalla/config/unbound_local/oisd_big.conf
    
    # Check Unbound logs for errors
    sudo journalctl -u unbound -n 50
    
    # Check if syntax error exists
    grep -E "local-zone:[[:space:]]*$" /home/pi/.firewalla/config/unbound_local/oisd_big.conf
    # If this returns anything, you have empty domain entries - the script should prevent this

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

### NXDOMAIN vs 0.0.0.0 results

*   Some lists return `0.0.0.0`, others return `NXDOMAIN`
*   Both are valid blocking responses
*   If you see a real IP address, the block isn't working

### The script downloaded HTML instead of the list

*   The script automatically detects this and won't install it
*   Check the URL is correct
*   Some providers may have changed their URL format

### Script not running from crontab

    # Test that the script works when run manually
    /home/pi/update_dns.sh
    
    # Check that the script has execute permissions
    ls -l /home/pi/update_dns.sh
    
    # Add full path to script in crontab
    0 0 * * 0 /home/pi/update_dns.sh
    
    # Check if logs show cron execution
    grep update_dns /var/log/syslog

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

### Monitor Memory Usage

If you're using a large list, monitor your Firewalla's memory:

    free -h

### View Block Statistics

External blocklists don't show in the Firewalla app, but you can count entries:

    # Count domains in your list
    grep -c "local-zone:" /home/pi/.firewalla/config/unbound_local/oisd_big.conf
    
    # Compare with previous count
    grep "New block count" /var/log/unbound_update.log

* * *

Updating the Script
-------------------

If you need to update the script to a newer version:

    cd /home/pi
    
    # Backup current script
    cp update_dns.sh update_dns.sh.backup
    
    # Download new version
    curl -O https://raw.githubusercontent.com/upmcplanetracker/firewalla-unbound-advanced-blocklists/main/update_dns.sh
    
    # Make it executable
    chmod +x /home/pi/update_dns.sh
    
    # Test the new version
    ./update_dns.sh

* * *

Important Notes
---------------

*   **Backup your configuration** before making changes
*   **Test thoroughly** after any change
*   **Monitor your system** for memory usage when using large lists
*   **Keep DNS Booster ON** - it's required for proper operation
*   **Manual updates only** - these lists won't appear in the Firewalla app
*   **Check logs** if something doesn't work - `/var/log/unbound_update.log`

* * *

Additional Resources
--------------------

*   [Firewalla Unbound Configuration](https://github.com/upmcplanetracker/firewalla-unbound-DoT-config) - Configure Unbound cache size
*   [OISD Blocklist](https://oisd.nl/) - The default list used in this guide
*   [HaGeZi Blocklists](https://github.com/hagezi/dns-blocklists) - Alternative blocklist provider
*   [Firewalla Community](https://community.firewalla.com/) - Get help from other users

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
