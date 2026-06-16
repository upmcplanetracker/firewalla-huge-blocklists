Firewalla Unbound: Advanced Blocklist Integration (External Lists)
==================================================================

This configuration allows you to manually add massive, unsupported (for MSP lite users), third-party blocklists directly into Unbound on your Firewalla. Use this if you need "Big" or "Ultimate" protection that goes beyond the standard Firewalla-provided target lists.

Files in this Repository
------------------------

*   **`update_dns.sh`** - The main script that downloads, validates, and updates your blocklists.
*   **`blocklists.env`** - Your personal configuration file to define which lists to use. **This file is never overwritten by the script after creation.**
*   **`README.md`** - This guide.

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

### 3. Hardware Tiers & Memory

Large lists (~400k+ domains) consume significant RAM. Match your list choice to your hardware:

| Hardware Tier | Firewalla Models | Recommended Unbound Cache | Max Domain Recommendation |
| :--- | :--- | :--- | :--- |
| **Entry** | Purple SE, Blue Plus | 16m / 32m | **Avoid Big Lists** (Use Light only) |
| **Mid** | Gold, Purple | 32m / 64m | Up to 100k domains |
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
    
    # curl will be automatically installed by the script if needed

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

The script uses a `.env` file to manage your blocklists. You have two options to set this up:

#### Option A: Let the script create it (Easiest)

Simply run the script once. It will create a template `blocklists.env` file at `/home/pi/.firewalla/config/blocklists.env`.

    /home/pi/update_dns.sh

The script will show output like:

    [timestamp] ✓ Created .env configuration template at /home/pi/.firewalla/config/blocklists.env
    [timestamp] ℹ Please edit /home/pi/.firewalla/config/blocklists.env to customize your blocklists

**Important:** The script will **never overwrite** this file once it exists. Your edits are safe.

#### Option B: Download the .env file directly (Recommended for advanced users)

Download the pre-configured `blocklists.env` file from the repository:

    # Create the directory if it doesn't exist
    mkdir -p /home/pi/.firewalla/config
    
    # Download the .env file
    curl -o /home/pi/.firewalla/config/blocklists.env \
      https://raw.githubusercontent.com/upmcplanetracker/firewalla-huge-blocklists/main/blocklists.env

#### Edit the .env file

Whether you used Option A or B, edit the file to enable the lists you want:

    nano /home/pi/.firewalla/config/blocklists.env

**.env file format:**

    LIST_NAME|URL|OUTPUT_FILE

Each line defines one blocklist. To enable a list, remove the `#` at the start of its line. To disable a list, add a `#` to comment it out.

**Example with multiple lists enabled:**

    # OISD Big List (Recommended for High tier hardware)
    oisd_big|https://big.oisd.nl/unbound|/home/pi/.firewalla/config/unbound_local/oisd_big.conf
    
    # OISD Light List (Recommended for Entry tier hardware)
    oisd_light|https://oisd.nl/unbound|/home/pi/.firewalla/config/unbound_local/oisd_light.conf
    
    # HaGeZi Pro List
    hagezi_pro|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/pro.txt|/home/pi/.firewalla/config/unbound_local/hagezi_pro.conf
    
    # HaGeZi Ultimate List (Large - requires High tier hardware)
    # hagezi_ultimate|https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/ultimate.txt|/home/pi/.firewalla/config/unbound_local/hagezi_ultimate.conf

**Note:** The .env file is a simple text file. Each uncommented line must have exactly three parts separated by the pipe character `|`.

### Step 4: Run the Script to Download Your Lists

Now run the script again to download all the lists you enabled in the .env file:

    /home/pi/update_dns.sh

The script will:

1.  Read your .env file
2.  Download each enabled list
3.  Validate each file (checks format, not HTML, etc.)
4.  Install each list to the specified location
5.  Create backups before replacing existing files

**Verify the files were created:**

    ls -lh /home/pi/.firewalla/config/unbound_local/

### Step 5: Configure Unbound

Now point Unbound to your downloaded blocklist files. Edit your Unbound config:

**File Path:** `/home/pi/.firewalla/config/unbound_local/unbound_custom.conf`

    nano /home/pi/.firewalla/config/unbound_local/unbound_custom.conf

Add or modify the following configuration:

    server:
        # Adjust these values based on your Hardware Tier from the table above
        msg-cache-size: 128m
        rrset-cache-size: 256m
        
        prefetch: yes
        prefetch-key: yes
    
        # Include ALL your blocklists from the .env file
        include: "/home/pi/.firewalla/config/unbound_local/oisd_big.conf"
        include: "/home/pi/.firewalla/config/unbound_local/oisd_light.conf"
        include: "/home/pi/.firewalla/config/unbound_local/hagezi_pro.conf"
        # include: "/home/pi/.firewalla/config/unbound_local/hagezi_ultimate.conf"

**Important:** Each list you enable in the .env file must have a corresponding `include:` line in your Unbound config.

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

#### Option 4: Different Schedules for Different Lists

If you want different update frequencies for different lists, you can create separate .env files and scripts:

**Create a script for each schedule:**

    # /home/pi/update_weekly.sh
    #!/bin/bash
    ENV_FILE=/home/pi/.firewalla/config/blocklists_weekly.env /home/pi/update_dns.sh
    
    # /home/pi/update_monthly.sh
    #!/bin/bash
    ENV_FILE=/home/pi/.firewalla/config/blocklists_monthly.env /home/pi/update_dns.sh

Make them executable and add to crontab:

    chmod +x /home/pi/update_*.sh
    crontab -e

Add:

    0 0 * * 0 /home/pi/update_weekly.sh
    0 0 1 * * /home/pi/update_monthly.sh

#### Option 5: Manual Updates Only

If you prefer to update manually, simply run:

    /home/pi/update_dns.sh

Whenever you want to refresh your lists.

* * *

Script Features
---------------

The `update_dns.sh` script includes several safety features:

📦 **Automatic curl installation** - Installs curl if not present

🔄 **Retry logic** - Retries download up to 3 times on failure

✅ **Multiple validation checks** - Validates file format, size, and content

↩️ **Automatic rollback** - Restores previous config if update fails

📝 **Detailed logging** - Logs all activity to /var/log/unbound\_update.log

📊 **Block count reporting** - Shows before/after domain counts for each list

💾 **Disk space check** - Ensures enough space before downloading

🔍 **Unbound verification** - Tests that Unbound restarts successfully

📄 **.env file support** - Manage multiple lists with a simple config file

🛡️ **Never overwrites config** - Your .env file edits are always preserved

* * *

Testing & Verification
----------------------

### Test Your Blocklist

Run a lookup for a domain known to be on your blocklist (e.g., `doubleclick.net`):

    nslookup doubleclick.net

**Success:** The result should return `0.0.0.0` or `NXDOMAIN`.

**Failure:** If it returns a real IP address, the blocklist is not loading correctly.

### Verify Blocklist Sizes

Check how many domains are being blocked by each list:

    # Count domains in each list
    grep -c "local-zone:" /home/pi/.firewalla/config/unbound_local/oisd_big.conf
    grep -c "local-zone:" /home/pi/.firewalla/config/unbound_local/oisd_light.conf
    grep -c "local-zone:" /home/pi/.firewalla/config/unbound_local/hagezi_pro.conf

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

### Adding a New Blocklist

To add a new blocklist, simply edit your .env file:

    nano /home/pi/.firewalla/config/blocklists.env

Add a new line with the format:

    list_name|https://url-to-your-list/unbound|/home/pi/.firewalla/config/unbound_local/your_list.conf

Then add the corresponding include line to your Unbound config:

    include: "/home/pi/.firewalla/config/unbound_local/your_list.conf"

Run the script again to download the new list:

    /home/pi/update_dns.sh

### Removing a Blocklist

To remove a blocklist, either:

1.  Comment it out in the .env file by adding `#` at the start of the line, OR
2.  Delete the line entirely

Then remove the corresponding `include:` line from your Unbound config and restart Unbound.

### Popular Blocklist URLs

List Name

URL

Size

Recommended Hardware

OISD Big

`https://big.oisd.nl/unbound`

~400k+

High

OISD Light

`https://oisd.nl/unbound`

~100k

Entry/Mid

HaGeZi Pro

`https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/pro.txt`

~150k

Mid

HaGeZi Ultimate

`https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/ultimate.txt`

~500k+

High

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

    # Check if the conf files exist
    ls -la /home/pi/.firewalla/config/unbound_local/
    
    # Check if each file has content
    head -20 /home/pi/.firewalla/config/unbound_local/oisd_big.conf
    
    # Check Unbound logs for errors
    sudo journalctl -u unbound -n 50
    
    # Check if syntax error exists in any file
    grep -E "local-zone:[[:space:]]*$" /home/pi/.firewalla/config/unbound_local/*.conf
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

### No valid lists found in .env file

    # Check your .env file
    cat /home/pi/.firewalla/config/blocklists.env
    
    # Make sure you have uncommented at least one list
    # Lines should not start with #
    # Format should be: NAME|URL|OUTPUT_FILE

### NXDOMAIN vs 0.0.0.0 results

*   Some lists return `0.0.0.0`, others return `NXDOMAIN`
*   Both are valid blocking responses
*   If you see a real IP address, the block isn't working

### Script not running from crontab

    # Test that the script works when run manually
    /home/pi/update_dns.sh
    
    # Check that the script has execute permissions
    ls -l /home/pi/update_dns.sh
    
    # Use full path to script in crontab
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
    
    # See which lists were updated
    grep "Processing list" /var/log/unbound_update.log

### Monitor Memory Usage

If you're using large lists, monitor your Firewalla's memory:

    free -h

### View Block Statistics

External blocklists don't show in the Firewalla app, but you can count entries:

    # Count domains in each list
    for file in /home/pi/.firewalla/config/unbound_local/*.conf; do
        echo "$(basename $file): $(grep -c 'local-zone:' $file) entries"
    done
    
    # Compare with previous counts from logs
    grep "New block count" /var/log/unbound_update.log

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
*   **Your .env file is safe** - the script will never overwrite it

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
