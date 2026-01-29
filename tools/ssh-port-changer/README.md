# 🛡️ SSH Port Changer `v1.0`

> **Safely migrate your SSH port on modern Ubuntu systems without getting locked out.**

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%2B-E95420?logo=ubuntu&style=flat-square)](https://ubuntu.com/)
[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?logo=gnu-bash&style=flat-square)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

---

## 🚀 Why this script?

In **Ubuntu 24.04 LTS** and later, changing the SSH port is no longer as simple as editing `/etc/ssh/sshd_config`. Canonical moved to **Systemd Socket Activation**, meaning `ssh.socket` controls the listening port, ignoring your config file.

This script handles the complexity for you, ensuring a **zero-downtime**, safe transition.

### ✨ Key Features

*   **🛡️ Fail-Safe Transition:** Automatically configures the server to listen on **BOTH** the old and new ports simultaneously during setup.
*   **🔌 Systemd Socket Override:** Correctly creates `listen.conf` drop-ins to handle socket binding.
*   **🧱 Firewall Auto-Config:** Detects and updates **NFTables** (native) or **UFW** automatically.
*   **🚫 Anti-Lockout Verification:** Pauses and forces you to verify connectivity in a new window before closing the old port.
*   **🤖 Fail2Ban Integration:** Updates jails to monitor the new port instantly.

---

## ⚡ Quick Start

Run this on your server as `root`:

```bash
# Download and make executable
curl -fsSL https://raw.githubusercontent.com/weby-homelab/voip-installer/main/tools/ssh-port-changer/change_port.sh -o change_port.sh
chmod +x change_port.sh

# Run (Replace 54322 with your desired port)
sudo ./change_port.sh 54322
```

---

## 📖 Detailed Usage

### 1. Interactive Mode
Run without arguments to be prompted for the port:
```bash
./change_port.sh
# > Enter new SSH port (1024-65535):
```

### 2. Non-Interactive Mode
Pass the port as an argument for automation:
```bash
./change_port.sh 2222
```

### 3. Verification Step (Crucial)
The script will pause at this stage:

> **CRITICAL: DO NOT CLOSE THIS SESSION!**
> Open a NEW terminal window and verify you can connect:
> `ssh -p 54322 root@<your-server-ip>`

**Only** after you successfully log in via the new port in a separate window, type `yes` in the script to finalize the changes (close port 22).

---

## 🔧 How it Works

1.  **Validation:** Checks root privileges and OS version.
2.  **Firewall Open:** Adds an `ALLOW` rule for the NEW port immediately.
3.  **Socket Dual-Bind:** Configures `ssh.socket` to listen on `0.0.0.0:OldPort` AND `0.0.0.0:NewPort`.
4.  **Wait for User:** Pauses for manual verification.
5.  **Cleanup:**
    *   Removes `OldPort` from `ssh.socket`.
    *   Updates `sshd_config` (for protocol consistency).
    *   Updates `fail2ban` jails.
    *   Removes `OldPort` from Firewall rules.

---

## 📦 Compatibility

| OS | Version | Support | Note |
| :--- | :--- | :--- | :--- |
| **Ubuntu** | 24.04 LTS (Noble) | ✅ Fully Supported | Uses `ssh.socket` logic |
| **Ubuntu** | 22.04 LTS | ⚠️ Untested | Should work if socket activation is enabled |
| **Debian** | 12 (Bookworm) | ❌ Not Supported | Uses standard `sshd_config` |

---

## 🤝 Contributing

Found a bug? Use the [Issues](https://github.com/weby-homelab/voip-installer/issues) tab.
Pull requests are welcome!

**License:** MIT