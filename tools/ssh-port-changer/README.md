# SSH Port Changer for Ubuntu 24.04+

This script safely changes the SSH port on modern Ubuntu systems that use `systemd socket activation` (where changing `sshd_config` is not enough).

## Features
*   **Safe Transition:** Listens on BOTH the old (22) and new ports during setup to prevent lockout.
*   **Verification:** Pauses and asks you to verify connectivity in a new window before closing the old port.
*   **Systemd Socket:** Correctly overrides `ssh.socket` configuration.
*   **Firewall:** Auto-detects and updates **UFW** or **NFTables** (if configured via `/etc/nftables.conf`).
*   **Fail2Ban:** Updates the monitored port in `jail.local`.

## Usage

1.  **Clone or download** the script to your server.
2.  **Make executable:**
    ```bash
    chmod +x change_port.sh
    ```
3.  **Run as root:**
    ```bash
    sudo ./change_port.sh [NEW_PORT]
    ```
    *Example:* `sudo ./change_port.sh 54322`

4.  **Follow the prompts.** The script will ask you to verify the connection before finalizing.

## Requirements
*   Ubuntu 24.04 or later (uses `ssh.socket`).
*   Root privileges.
