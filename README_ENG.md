# 📞 Asterisk Deployment Guide

**Version:** `v4.6.2` (Safe Docker Mode)

This guide describes the installation process for a secure VoIP server (**Asterisk 22** + **PJSIP** + **TLS/SRTP** + **Fail2Ban** + **NFTables**) on a clean **Ubuntu 24.04** server.

### 🌟 Features

* **Safe Mode:** Does **NOT** reset Docker network settings (no flush ruleset).
* **Security:** Uses TLS 1.3 on port `5061`.
* **Automation:** Automatic SSL generation (Let's Encrypt).

---

## 🛠 Step 1: Server Preparation

1. **Log in to the server** via SSH as root:
```bash
ssh root@your-server-ip

```


2. **Check Ports:** Ensure ports `80`, `443`, and `5061` are free.
> *Note: If this is a clean system installation, these ports should be free by default.*



---

## 📝 Step 2: Create the Script

1. Create an empty file for the script:
```bash
nano install_voip.sh

```


2. **Copy** the FULL code of script `v4.6.2` (`install.sh`) to your clipboard.
3. **Paste** the code into the terminal:
* **Windows** (PuTTY/PowerShell): Right-click.
* **Mac/Linux:** `Cmd+V` or `Ctrl+Shift+V`.


4. **Save and Close**:
* Press `Ctrl+O`, then `Enter`.
* Press `Ctrl+X`.



---

## 🚀 Step 3: Run Installation

1. Make the script executable:
```bash
chmod +x install_voip.sh

```


2. **Run the script** (replace the placeholders with your actual data):
```bash
./install_voip.sh --domain your-domain.com --email admin@your-domain.com

```


**Options:**
| Option | Description |
| :--- | :--- |
| `--domain` | Your domain name (required, must point to server IP). |
| `--email` | Email for Let's Encrypt certificate registration. |
| `--ext-ip` | *(Optional)* External IP if behind NAT. Usually auto-detected. |

---

## ⚙️ Step 4: Automated Actions

The script will automatically perform the following:

1. 🐳 Install **Docker**, **Fail2Ban**, and **NFTables**.
2. 🔒 Obtain an **SSL certificate** via Certbot.
3. 👤 Generate passwords for users **100-105**.
4. 🛡️ Configure firewall (`table inet voip_firewall`) **without breaking Docker**.
5. ▶️ Start **Asterisk** in a container.

---

## ✅ Step 5: Post-Installation & Checks

### 1. Get SIP Credentials

Retrieve the generated passwords:

```bash
cat /root/voip-server/users.env

```

### 2. Check Container Status

Ensure the container is running healthy:

```bash
docker ps

```

> **Expected:** Status should be `"Up (healthy)"`.

### 3. Check Firewall Rules

Verify the rules were applied:

```bash
nft list table inet voip_firewall

```

### 🚨 3.1. Critical Check (Docker Network Safety)

Run these commands to verify that the firewall has not blocked container networking:

```bash
systemctl restart nftables
docker exec asterisk-voip curl -Is https://google.com | grep HTTP

```

* **Expected Result:** `HTTP/2 200` (or `HTTP/1.1 200`).
* **Why this works:**
* *Host network:* Container uses host IP/stack.
* *Used accept:* Outbound curl -> SYN -> matched as 'established' on return.
* *No block outbound:* Default policy is accept (Safe Mode).



> **Success:** If the test passes, Safe Mode is fully protecting Docker network connectivity.

### 4. Client Connection (e.g., Linphone)

Configure your softphone with these settings:

* **Username:** `100` (or 101-105)
* **Password:** *(from users.env)*
* **Domain:** `your-domain.com:5061`
* **Transport:** `TLS`
* **Media Encryption:** `SRTP`
* **AVPF:** Disabled (usually)
* **ICE:** Enabled

---

## 🔧 Troubleshooting

* **No Audio:** Check UDP range `10000-19999` in your hosting panel firewall (e.g., Hetzner Firewall / AWS Security Group).
* **SSL Error:** Ensure the domain A-record points correctly to the server.
* **View Logs:**
```bash
docker logs -f asterisk-voip

```
