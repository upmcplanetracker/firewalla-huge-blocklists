# Firewalla Unbound: Advanced Blocklist Integration (External Lists)

This configuration allows you to manually add massive, unsupported (for non-MSP subscribers), third-party blocklists directly into Unbound on your Firewalla. Use this if you need "Big" or "Ultimate" protection that goes beyond the standard Firewalla-provided target lists.

## ⚠️ Critical: Before You Begin

### 1. External List Management
* **Scope:** This guide is strictly for non-Firewalla provided lists (e.g., OISD big, HaGeZi Ultimate or Pro++).
* **App Stats:** Blocks from these external lists **will not** appear in your "Blocked Flows" or app stats.
* **App Toggles:** You cannot enable or disable these lists via the Firewalla app interface. All management must be done via SSH.
* **DNS Booster:** You must keep the **DNS Booster ON** in the app. It is required for Firewalla to intercept your traffic and hand it to Unbound.
* **Unbound:** You must be using Unbound as the DNS resolver.

### 2. Format & Compatibility
* **Requirement:** You must use **Unbound-formatted** lists. The file must contain `local-zone:` entries.
* **Warning:** Standard "hosts" files (starting with `0.0.0.0` or `127.0.0.1`) **will break Unbound**. If a list is not properly formatted, your internet will stop working.

### 3. Hardware Tiers & Memory
Large lists (~400k+ domains) consume significant RAM. Match your list choice to your hardware:

| Hardware Tier | Firewalla Models | Recommended Cache | Max Domain Recommendation |
| :--- | :--- | :--- | :--- |
| **Entry** | Purple SE, Blue Plus | 16m / 32m | **Avoid Big Lists** (Use Light only) |
| **Mid** | Gold, Purple | 32m / 64m | Up to 100k domains |
| **High** | Gold Plus, Gold Pro | 128m / 256m | 400k+ domains (Big/Ultimate) |

---

## 🛠️ Configuration

### Step 1: Create the Update Script
We create the script first to ensure we can download the list before configuring Unbound to look for it.

**File Path:** `/home/pi/update_dns.sh`

```bash
#!/bin/bash

# --- EXTERNAL LIST CONFIGURATION ---
# List 1: OISD Big (High-end hardware only)
URL1="https://big.oisd.nl/unbound"
TARGET1="/home/pi/.firewalla/config/unbound_local/blocklist_1.conf"

# To add a second list, uncomment these lines:
# URL2="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/unbound/pro.conf"
# TARGET2="/home/pi/.firewalla/config/unbound_local/blocklist_2.conf"
# -----------------------------------

# Download the list
wget -qO "$TARGET1" "$URL1"

# Uncomment if using second list:
# wget -qO "$TARGET2" "$URL2"

# Restart Unbound only if download was successful
if [ $? -eq 0 ]; then
    sudo systemctl restart unbound
fi
```

**Make it executable:**
```bash
chmod +x /home/pi/update_dns.sh
```

### Step 2: First Time Run (Important!)
You must run the script manually once **before** editing the Unbound config. If you skip this, Unbound will try to load a file that doesn't exist and will fail to start.

Run this in your terminal:
```bash
/home/pi/update_dns.sh
```

*Check that the file was created:*
```bash
ls -lh /home/pi/.firewalla/config/unbound_local/blocklist_1.conf
```

### Step 3: The Unbound Config
Now that the blocklist file exists, point Unbound to it.  If you already have other things in your .conf file, such as DNS over TLS, you can add this into the same .conf file.

**File Path:** `/home/pi/.firewalla/config/unbound_local/unbound_custom.conf`

```yaml
server:
    # Adjust based on Hardware Tier table above
    msg-cache-size: 128m
    rrset-cache-size: 256m
    
    prefetch: yes
    prefetch-key: yes

    # To add multiple lists, add more include lines here:
    include: "/home/pi/.firewalla/config/unbound_local/blocklist_1.conf"
    # include: "/home/pi/.firewalla/config/unbound_local/blocklist_2.conf"
```

### Step 4: Restart & Persistence
Restart Unbound to apply the changes:
```bash
sudo systemctl restart unbound
```

**Schedule Automatic Updates:**
Add the script to your user crontab to update the list weekly (Sundays at midnight).

**File Path:** `/home/pi/.firewalla/config/user_crontab`
```bash
0 0 * * 0 /home/pi/update_dns.sh
```

**Apply Changes:**
To ensure the crontab is loaded and the network stack syncs correctly, reboot your Firewalla (will take 3-4 min for your internet to return):
```bash
sudo reboot
```

---

## ✅ Whitelisting & Testing

### How to Whitelist
**App Rules Override Everything:**
If an external list blocks a site you need:
1.  Open the Firewalla App.
2.  Tap **Rules** -> **Add Rule**.
3.  Target: The domain you want to allow.
4.  Action: **Allow**.

*Why this works:* The Firewalla DNS Booster sees your traffic first. If it sees an "Allow" rule, it resolves the IP immediately and never forwards the request to Unbound's blocklist.

### How to Verify
Run a lookup for a domain known to be on your blocklist (e.g., `doubleclick.net`):

```bash
nslookup doubleclick.net
```

**Success:** The result should return `0.0.0.0` or `NXDOMAIN`.  
**Failure:** If it returns a real IP address, the blocklist is not loading correctly.
