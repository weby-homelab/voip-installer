#!/bin/bash
set -e

# ==============================================================================
# SSH Port Changer for Ubuntu 24.04+ (Systemd Socket Activation)
# Safely migrates SSH to a custom port and updates Firewall/Fail2Ban.
# ==============================================================================

NEW_PORT="$1"

# Colors
c_red='\033[0;31m'; c_grn='\033[0;32m'; c_ylw='\033[0;33m'; c_reset='\033[0m'
log() { echo -e "${c_grn}[INFO]${c_reset} $1"; }
warn() { echo -e "${c_ylw}[WARN]${c_reset} $1"; }
err() { echo -e "${c_red}[ERROR]${c_reset} $1" >&2; exit 1; }

# --- Step 0: Validation & Detection ---

if [[ $EUID -ne 0 ]]; then err "This script must be run as root."; fi

# Detect Old Port
OLD_PORT=$(ss -tnlp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | head -n 1)
[[ -z "$OLD_PORT" ]] && OLD_PORT=22
log "Detected current SSH port: $OLD_PORT"

# Input New Port
if [[ -z "$NEW_PORT" ]]; then
    read -rp "Enter new SSH port (1024-65535): " NEW_PORT
fi

if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -le 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
    err "Invalid port: $NEW_PORT. Must be numeric and between 1024-65535."
fi

if [[ "$NEW_PORT" -eq "$OLD_PORT" ]]; then
    err "New port ($NEW_PORT) is the same as current port."
fi

log "Migrating SSH from $OLD_PORT to $NEW_PORT..."

# --- Step 1: Open Firewall (Temporary Safety) ---

log "Step 1: Opening Firewall for Port $NEW_PORT..."
FW_TYPE="none"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    FW_TYPE="ufw"
    ufw allow "$NEW_PORT/tcp"
    log "UFW rule added for $NEW_PORT."
elif command -v nft >/dev/null && nft list ruleset | grep -q "table"; then
    FW_TYPE="nftables"
    # Specific logic for voip-installer firewall
    if nft list tables | grep -q "voip_firewall"; then
        nft add rule inet voip_firewall input tcp dport "$NEW_PORT" accept
        log "NFTables (voip_firewall) rule added for $NEW_PORT."
    else
        warn "NFTables active but 'voip_firewall' table not found. Please manually allow TCP/$NEW_PORT."
    fi
fi

# --- Step 2: Configure SSH Socket ---

log "Step 2: Configuring SSH Socket to listen on BOTH ports..."
mkdir -p /etc/systemd/system/ssh.socket.d

# Listen on both ports temporarily
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
    log "SSH is now listening on $NEW_PORT (and $OLD_PORT)."
else
    # Rollback
    rm -f /etc/systemd/system/ssh.socket.d/listen.conf
    systemctl daemon-reload
    systemctl restart ssh.socket
    err "Failed to bind to $NEW_PORT. Rolled back."
fi

# --- Step 3: User Verification ---

echo -e "\n${c_ylw}======================================================${c_reset}"
echo -e "${c_ylw}CRITICAL: DO NOT CLOSE THIS SESSION!${c_reset}"
echo -e "Open a NEW terminal and verify connection:"
echo -e "    ssh -p $NEW_PORT root@<your-server-ip>"
echo -e "${c_ylw}======================================================${c_reset}\n"

read -rp "Did the connection work? Type 'yes' to close port $OLD_PORT and finalize: " confirmation
if [[ "$confirmation" != "yes" ]]; then
    warn "Aborting. Both ports are still open."
    warn "To revert manually: rm /etc/systemd/system/ssh.socket.d/listen.conf && systemctl daemon-reload && systemctl restart ssh.socket"
    exit 0
fi

# --- Step 4: Finalize SSH Config ---

log "Step 3: Removing Port $OLD_PORT from SSH..."

# Update Socket to listen ONLY on new port
cat > /etc/systemd/system/ssh.socket.d/listen.conf <<EOF
[Socket]
ListenStream=
ListenStream=0.0.0.0:$NEW_PORT
ListenStream=[::]:$NEW_PORT
EOF

systemctl daemon-reload
systemctl restart ssh.socket

# Update sshd_config for consistency
sed -i "/^Port $OLD_PORT/d" /etc/ssh/sshd_config
sed -i "/^#Port $OLD_PORT/d" /etc/ssh/sshd_config
if ! grep -q "Port $NEW_PORT" /etc/ssh/sshd_config; then
    echo "Port $NEW_PORT" >> /etc/ssh/sshd_config
fi

# --- Step 5: Update Fail2Ban ---

if [[ -f /etc/fail2ban/jail.local ]]; then
    log "Step 4: Updating Fail2Ban..."
    if grep -q "port\s*=" /etc/fail2ban/jail.local; then
         # Replace port = old with port = new
         sed -i "s/port\s*=\s*$OLD_PORT/port = $NEW_PORT/g" /etc/fail2ban/jail.local
         # Also handle cases where multiple ports are listed e.g. "ssh,22" -> "ssh,2222"
         sed -i "s/,$OLD_PORT/,$NEW_PORT/g" /etc/fail2ban/jail.local
    fi
    systemctl restart fail2ban || warn "Failed to restart Fail2Ban."
fi

# --- Step 6: Close Old Firewall Port ---

log "Step 5: Closing Firewall for Port $OLD_PORT..."

case "$FW_TYPE" in
    ufw)
        ufw delete allow "$OLD_PORT/tcp" || warn "Could not delete UFW rule for $OLD_PORT"
        log "UFW rule removed."
        ;;
    nftables)
        # Attempt to clean up persistent config
        CONF="/etc/nftables.conf"
        if [[ -f "$CONF" ]]; then
            # Replace old port with new port in text file
            # Handles "tcp dport 22 accept" -> "tcp dport 2222 accept"
            sed -i "s/tcp dport $OLD_PORT accept/tcp dport $NEW_PORT accept/g" "$CONF"
            
            # Handles sets: "tcp dport { 22, 80 }" -> "tcp dport { 2222, 80 }"
            # Warning: simplistic regex, assumes comma separation
            sed -i "s/{ $OLD_PORT,/{ $NEW_PORT,/g" "$CONF"
            sed -i "s/, $OLD_PORT }/, $NEW_PORT }/g" "$CONF"
            
            # Apply changes
            nft -f "$CONF" && log "NFTables config updated and reloaded." || warn "Failed to reload NFTables. Check $CONF manually."
        fi
        ;;
esac

log "Done! SSH is now running ONLY on port $NEW_PORT."