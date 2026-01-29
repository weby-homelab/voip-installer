#!/bin/bash
set -e

# ==============================================================================
# SSH Port Changer for Ubuntu 24.04+ (Systemd Socket Activation)
# Safely migrates SSH from port 22 to a custom port.
# ==============================================================================

OLD_PORT=22
NEW_PORT="$1"

# Colors
c_red='\033[0;31m'
c_grn='\033[0;32m'
c_ylw='\033[0;33m'
c_reset='\033[0m'

log() { echo -e "${c_grn}[INFO]${c_reset} $1"; }
warn() { echo -e "${c_ylw}[WARN]${c_reset} $1"; }
err() { echo -e "${c_red}[ERROR]${c_reset} $1" >&2; exit 1; }

# --- Validation ---

if [[ $EUID -ne 0 ]]; then
   err "This script must be run as root."
fi

# Detect Ubuntu 24.04+
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]] || [[ "${VERSION_ID%%.*}" -lt 24 ]]; then
        warn "This script is optimized for Ubuntu 24.04+. Detected: $PRETTY_NAME"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
else
    warn "Cannot detect OS version. Use with caution."
fi

# Input Port
if [[ -z "$NEW_PORT" ]]; then
    read -p "Enter new SSH port (1024-65535): " NEW_PORT
fi

if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -le 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
    err "Invalid port: $NEW_PORT. Must be numeric and between 1024-65535."
fi

if [[ "$NEW_PORT" -eq "$OLD_PORT" ]]; then
    err "New port must be different from old port ($OLD_PORT)."
fi

log "Migrating SSH from $OLD_PORT to $NEW_PORT..."

# --- Step 1: Firewall Safety ---

log "Step 1: Opening Firewall for Port $NEW_PORT..."

# Detect Firewall
FW_TYPE="none"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    FW_TYPE="ufw"
elif command -v nft >/dev/null && nft list ruleset | grep -q "table"; then
    FW_TYPE="nftables"
fi

case "$FW_TYPE" in
    ufw)
        ufw allow "$NEW_PORT/tcp"
        log "UFW rule added."
        ;;
    nftables)
        # Try to find the input chain. This is heuristic.
        # We assume a standard table 'inet filter' or 'inet voip_firewall' from our other projects
        if nft list tables | grep -q "voip_firewall"; then
            nft add rule inet voip_firewall input tcp dport "$NEW_PORT" accept
            log "NFTables (voip_firewall) rule added."
        elif nft list tables | grep -q "filter"; then
             # Attempt generic insert
             warn "Generic NFTables detected. You might need to verify the rule manually."
             # This is risky without knowing table name. Skipping auto-add to avoid syntax error.
             warn "Please manually allow port $NEW_PORT in your NFTables config!"
        else
             warn "NFTables active but no known table found. Please allow port $NEW_PORT manually."
        fi
        ;;
    *)
        warn "No active firewall detected (UFW/NFT). Skipping."
        ;;
esac

# --- Step 2: Systemd Socket Config ---

log "Step 2: Configuring SSH Socket to listen on $OLD_PORT AND $NEW_PORT..."
mkdir -p /etc/systemd/system/ssh.socket.d

# We must bind explicit 0.0.0.0 and [::] to avoid 'BindIPv6Only' conflicts in Ubuntu 24.04
cat > /etc/systemd/system/ssh.socket.d/listen.conf <<EOF
[Socket]
ListenStream=
ListenStream=0.0.0.0:$OLD_PORT
ListenStream=[::]:$OLD_PORT
ListenStream=0.0.0.0:$NEW_PORT
ListenStream=[::]:$NEW_PORT
EOF

systemctl daemon-reload
systemctl restart ssh.socket

sleep 2
if ss -tlnp | grep -q ":$NEW_PORT"; then
    log "SSH is now listening on port $NEW_PORT (and $OLD_PORT)."
else
    # Rollback attempt
    rm -f /etc/systemd/system/ssh.socket.d/listen.conf
    systemctl daemon-reload
    systemctl restart ssh.socket
    err "SSH failed to bind to port $NEW_PORT. Rolled back changes. Check 'systemctl status ssh.socket'."
fi

# --- Step 3: Verification ---

echo -e "\n${c_ylw}======================================================${c_reset}"
echo -e "${c_ylw}CRITICAL: DO NOT CLOSE THIS SESSION!${c_reset}"
echo -e "Open a NEW terminal window and verify you can connect:"
echo -e "    ssh -p $NEW_PORT root@<your-server-ip>"
echo -e "${c_ylw}======================================================${c_reset}\n"

read -p "Did the connection work? If yes, type 'yes' to close port $OLD_PORT: " confirmation
if [[ "$confirmation" != "yes" ]]; then
    warn "Aborting. Both ports are still open."
    warn "To revert manually: rm /etc/systemd/system/ssh.socket.d/listen.conf && systemctl daemon-reload && systemctl restart ssh.socket"
    exit 0
fi

# --- Step 4: Finalize ---

log "Step 3: Removing Port $OLD_PORT..."

# Update Socket
cat > /etc/systemd/system/ssh.socket.d/listen.conf <<EOF
[Socket]
ListenStream=
ListenStream=0.0.0.0:$NEW_PORT
ListenStream=[::]:$NEW_PORT
EOF

systemctl daemon-reload
systemctl restart ssh.socket

# Update SSHD Config (Best Practice)
sed -i "/^Port $OLD_PORT/d" /etc/ssh/sshd_config
sed -i "/^#Port $OLD_PORT/d" /etc/ssh/sshd_config
if ! grep -q "Port $NEW_PORT" /etc/ssh/sshd_config; then
    echo "Port $NEW_PORT" >> /etc/ssh/sshd_config
fi

# --- Step 5: Fail2Ban ---

if [[ -f /etc/fail2ban/jail.local ]]; then
    log "Step 4: Updating Fail2Ban..."
    # Heuristic replacement for sshd jail
    if grep -q "\[sshd\]" /etc/fail2ban/jail.local; then
        # Check if port is already defined
        if grep -q "port\s*=" /etc/fail2ban/jail.local; then
             sed -i "s/port\s*=\s*$OLD_PORT/port = $NEW_PORT/g" /etc/fail2ban/jail.local
        else
             warn "Fail2Ban config found but 'port' not explicitly set. Please verify manually."
        fi
        systemctl restart fail2ban || warn "Failed to restart Fail2Ban."
    fi
fi

# --- Step 6: Close Firewall ---

log "Step 5: Closing Firewall for Port $OLD_PORT..."

case "$FW_TYPE" in
    ufw)
        ufw delete allow "$OLD_PORT/tcp"
        log "UFW rule removed."
        ;;
    nftables)
        if [[ -f /etc/nftables.conf ]]; then
            # Simple text replacement for persistence
            sed -i "s/tcp dport $OLD_PORT accept/tcp dport $NEW_PORT accept/g" /etc/nftables.conf
            nft -f /etc/nftables.conf || warn "Failed to reload NFTables config."
            log "NFTables config updated."
        else
            warn "NFTables active but no config file found at /etc/nftables.conf. Remove rule for $OLD_PORT manually."
        fi
        ;;
esac

log "Done! SSH is now running ONLY on port $NEW_PORT."
