---
 ASTERISK DEPLOYMENT GUIDE (v4.6.2)
================================================================

This guide describes the installation process for a secure VoIP server (Asterisk 22 + PJSIP + TLS/SRTP + Fail2Ban + NFTables) on a clean Ubuntu 24.04 server.
---
VERSION: v4.6.2 (Safe Docker Mode)
FEATURES: 
 - Does NOT reset Docker network settings (no flush ruleset).
 - Uses TLS 1.3 on port 5061.
 - Automatic SSL generation (Let's Encrypt).

---

STEP 1. SERVER PREPARATION
-------------------------
1. Log in to the server via SSH as root:
   ssh root@your-server-ip

2. Ensure ports 80, 443, and 5061 are free.
   (If this is a clean system, they should be free).

---

STEP 2. CREATE THE SCRIPT
-----------------------
1. Create an empty file for the script:
   nano install_voip.sh

2. Copy the FULL code of script v4.6.2 (install_eng.sh) to the clipboard.

3. Paste the code into the terminal:
   - Windows (PuTTY/PowerShell): Right-click.
   - Mac/Linux: Cmd+V or Ctrl+Shift+V.

4. Save and close the file:
   - Press Ctrl+O, then Enter.
   - Press Ctrl+X.

---

STEP 3. RUN INSTALLATION
-----------------------
1. Make the script executable:
   chmod +x install_voip.sh

2. Run the script (replace data with your own):

   ./install_voip.sh --domain your-domain.com --email admin@your-domain.com

   OPTIONS:
   --domain  : Your domain name (required, must point to the server IP).
   --email   : Email for Let's Encrypt certificate registration.
   --ext-ip  : (Optional) External IP if the server is behind NAT. Usually auto-detected.

---

STEP 4. WHAT WILL HAPPEN
---------------------
The script will automatically perform the following actions:
1. Install Docker, Fail2Ban, NFTables.
2. Obtain an SSL certificate via Certbot.
3. Generate passwords for users 100-105 (see users.env file).
4. Configure firewall (table inet voip_firewall) without breaking Docker.
5. Start Asterisk in a container.

---

STEP 5. POST-INSTALLATION
----------------------
1. Get SIP user passwords:
   cat /root/voip-server/users.env

2. Check container status:
   docker ps
   (Status should be "Up (healthy)")

3. Check Firewall:
   nft list table inet voip_firewall

3.1. Critical Check (Docker Network Safety Check):
   Run these commands to verify that the firewall has not blocked the container network:
   
   systemctl restart nftables
   docker exec asterisk-voip curl -Is https://google.com | grep HTTP
   
   Expected result: HTTP/2 200 (or HTTP/1.1 200).
   
   Why this works:
   - Host network: container uses host IP/stack.
   - Used accept: outbound curl -> SYN -> matched as 'established' on return.
   - No block outbound: default policy is accept (Safe Mode).
   
   If the test passes, Safe Mode fully protects Docker network connectivity.

4. Phone connection (e.g., Linphone):
   - Username: 100 (or 101-105)
   - Password: (from users.env)
   - Domain: your-domain.com:5061
   - Transport: TLS
   - Media Encryption: SRTP
   - AVPF: Disabled (usually) / ICE: Enabled

---

TROUBLESHOOTING
--------------------
- No audio: check UDP range 10000-19999 in your hosting panel (Hetzner Firewall / AWS SG).
- SSL error: ensure the domain responds from the server.
- Asterisk logs: docker logs -f asterisk-voip
