#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# ============================================================ 
# VoIP Server Installer v4.6.2
# Based on v4.6.1 + CRITICAL FIX: NFTables Docker Safety
# Stack: Asterisk 22 (Docker, host network)
# SIP: TLS 5061 (PJSIP Wizard), SRTP SDES, ICE enabled
# Firewall: nftables (Safe Mode - no flush ruleset) + Fail2Ban
# ============================================================ 

VERSION="4.6.2"

# ---------- logging ----------
c_reset='\033[0m'; c_red='\033[0;31m'; c_grn='\033[0;32m'; c_ylw='\033[0;33m'; c_blu='\033[0;34m'
log_i(){ echo -e "${c_blu}[INFO]${c_reset} $*"; }
log_ok(){ echo -e "${c_grn}[OK]${c_reset} $*"; }
log_w(){ echo -e "${c_ylw}[NOTE]${c_reset} $*"; }
log_e(){ echo -e "${c_red}[ERR]${c_reset} $*" >&2; }
die(){ log_e "$*"; exit 1; }

on_err(){
  local ec=$?
  log_e "Error (exit=$ec) at line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
  exit "$ec"
}
trap on_err ERR

# ---------- paths ----------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="/root/voip-server"
CFG_DIR="$PROJECT_DIR/config"
CERTS_DIR="$PROJECT_DIR/certs"
DATA_DIR="$PROJECT_DIR/data"
LOGS_DIR="$PROJECT_DIR/logs"
RUN_DIR="$PROJECT_DIR/run"
QR_DIR="$PROJECT_DIR/qr_codes"
USERS_ENV="$PROJECT_DIR/users.env"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

ASTERISK_CFG_DIR="$CFG_DIR/asterisk"
ASTERISK_RUN_DIR="$RUN_DIR/asterisk"

# nft/f2b (host)
NFT_MAIN="/etc/nftables.conf"
F2B_JAIL_LOCAL="/etc/fail2ban/jail.local"
F2B_FILTER="/etc/fail2ban/filter.d/asterisk-pjsip-security.conf"

# ---------- defaults ----------
YES=0
UPDATE=0
SMOKE_TEST=1

DOMAIN=""
EMAIL=""
TZ="UTC"
EXT_IP=""

ASTERISK_IMAGE="andrius/asterisk:22"
SIP_USERS=({100..105})
PORT_SIP_TLS=5061
RTP_MIN=10000
RTP_MAX=19999
F2B_MAXRETRY=2
F2B_FINDTIME="600m"
F2B_BANTIME="120h"

# ---------- helpers ----------
have(){ command -v "$1" >/dev/null 2>&1; }
need_cmd(){ have "$1" || die "Command not found: $1"; }

usage(){
  cat <<USAGE
VoIP Server Installer v${VERSION}
Usage:
  ./install_v4.6.2.sh --domain example.com [--email you@example.com] [--ext-ip 1.2.3.4] [--tz Europe/Kyiv] [--update] [--yes]
USAGE
  exit 0
}

require_root(){
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root (sudo)."
}

apt_install(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends "$@"
}

safe_write(){
  local path="$1" mode="${2:-0600}" owner="${3:-root}" group="${4:-root}"
  local dir tmp
  dir="$(dirname "$path")"
  install -d -m 0755 "$dir"
  tmp="$(mktemp)"
  cat > "$tmp"
  install -o "$owner" -g "$group" -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}

detect_ext_ip(){
  local ip=""
  if [[ -n "$EXT_IP" ]]; then
    echo "$EXT_IP"; return 0
  fi
  if have curl; then ip="$(curl -4fsS https://api.ipify.org 2>/dev/null || true)"; fi
  if [[ -z "$ip" ]] && have wget; then ip="$(wget -qO- https://api.ipify.org 2>/dev/null || true)"; fi
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Could not detect external IPv4. Use --ext-ip."
  echo "$ip"
}

rand_b64(){ openssl rand -base64 "$1" | tr -d '\n'; }

ensure_dirs(){
  install -d -m 0755 "$PROJECT_DIR" "$CFG_DIR" "$CERTS_DIR" "$DATA_DIR" "$LOGS_DIR" "$RUN_DIR"
  install -d -m 0755 "$ASTERISK_CFG_DIR"
  install -d -m 0755 "$DATA_DIR/asterisk" "$LOGS_DIR/asterisk" "$LOGS_DIR/asterisk/cdr-csv"
  install -d -m 0775 "$ASTERISK_RUN_DIR"
  install -d -m 0700 "$QR_DIR"
}

check_ports_free(){
  log_i "Checking ports..."
  local bad=0
  if ss -H -lnt "sport = :$PORT_SIP_TLS" | grep -q .; then log_w "TCP $PORT_SIP_TLS is busy"; bad=1; fi
  [[ $bad -eq 0 ]] && log_ok "Ports are free." || log_w "Port conflicts detected."
}

detect_asterisk_uid_gid(){
  local uid gid
  uid="$(docker run --rm "$ASTERISK_IMAGE" id -u asterisk 2>/dev/null || echo 1000)"
  gid="$(docker run --rm "$ASTERISK_IMAGE" id -g asterisk 2>/dev/null || echo 999)"
  echo "$uid:$gid"
}

seed_asterisk_dirs(){
  log_i "Seeding base Asterisk files..."
  docker run --rm --user 0:0 -v "$ASTERISK_CFG_DIR:/dst" "$ASTERISK_IMAGE" sh -c 'cp -an /etc/asterisk/. /dst/ 2>/dev/null || true'
  docker run --rm --user 0:0 -v "$DATA_DIR/asterisk:/dst" "$ASTERISK_IMAGE" sh -c 'cp -an /var/lib/asterisk/. /dst/ 2>/dev/null || true'
}

ensure_users_env(){
  [[ -f "$USERS_ENV" ]] && { log_ok "users.env exists"; return; }
  log_i "Generating users.env..."
  local tmp
  tmp="$(mktemp)"
  {
    for u in "${SIP_USERS[@]}"; do printf 'USER_%s_PASS=%s\n' "$u" "$(rand_b64 18)"; done
  } > "$tmp"
  install -m 0600 "$tmp" "$USERS_ENV"
  rm -f "$tmp"
}

read_env_kv(){
  grep -E "^$2=" "$1" | head -n1 | cut -d= -f2- || true
}

sync_certs(){
  local live="/etc/letsencrypt/live/${DOMAIN}"
  if [[ -d "$live" && -f "$live/fullchain.pem" && -f "$live/privkey.pem" ]]; then
    log_ok "Certificates found in $live"
  else
    log_w "No certificates found. Need port 80 free for certbot."
    [[ -n "$EMAIL" ]] || die "Cert missing. Provide --email."
    if ss -H -lnt "sport = :80" | grep -q .; then die "Port 80 busy! Free it or use DNS-01."; fi
    need_cmd certbot
    certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"
  fi

  install -d -m 0755 "$CERTS_DIR"
  install -m 0644 "$live/fullchain.pem" "$CERTS_DIR/fullchain.pem"
  install -m 0640 "$live/privkey.pem" "$CERTS_DIR/privkey.pem"
}

ensure_certbot_hook(){
  local hook="/etc/letsencrypt/renewal-hooks/deploy/voip-renew.sh"
  safe_write "$hook" 0755 root root <<EOF
#!/usr/bin/env bash
set -euo pipefail
CERTS_DIR="${CERTS_DIR}"
LIVE="/etc/letsencrypt/live/${DOMAIN}"
cp -f "\$LIVE/fullchain.pem" "\$CERTS_DIR/fullchain.pem"
cp -f "\$LIVE/privkey.pem" "\$CERTS_DIR/privkey.pem"
chmod 0644 "\$CERTS_DIR/fullchain.pem"
chmod 0640 "\$CERTS_DIR/privkey.pem"
docker restart asterisk-voip || true
EOF
}

generate_asterisk_conf(){
  local ext_ip="$1"
  log_i "Generating Asterisk configs (Ext IP: \$ext_ip)..."

  safe_write "$ASTERISK_CFG_DIR/rtp.conf" 0640 root root <<EOF
[general]
rtpstart=${RTP_MIN}
rtpend=${RTP_MAX}
icesupport=yes
EOF

  safe_write "$ASTERISK_CFG_DIR/logger.conf" 0640 root root <<'EOF'
[general]
dateformat=%F %T
[logfiles]
security => security
messages => notice,warning,error
EOF

  safe_write "$ASTERISK_CFG_DIR/modules.conf" 0640 root root <<'EOF'
[modules]
autoload=yes
noload => chan_sip.so
noload => res_http_websocket.so
noload => res_pjsip_transport_websocket.so
load => res_pjsip_transport_tls.so
load => res_pjsip_config_wizard.so
load => cdr_csv.so
load => res_srtp.so
EOF

  safe_write "$ASTERISK_CFG_DIR/extensions.conf" 0640 root root <<'EOF'
[general]
static=yes
writeprotect=no

[phones]
exten => _10[0-9],1,Dial(PJSIP/${EXTEN},30)
same  => n,Hangup()

exten => *43,1,Playback(hello-world)
same  => n,Hangup()
EOF

  safe_write "$ASTERISK_CFG_DIR/pjsip.conf" 0640 root root <<EOF
[global]
type=global
user_agent=Asterisk-Secure

[transport-udp]
type=transport
protocol=udp
bind=127.0.0.1:5060
local_net=127.0.0.1/8
local_net=192.168.0.0/16
local_net=172.16.0.0/12
local_net=10.0.0.0/8

[transport-tls]
type=transport
protocol=tls
bind=0.0.0.0:${PORT_SIP_TLS}
local_net=127.0.0.1/8
local_net=192.168.0.0/16
local_net=172.16.0.0/12
local_net=10.0.0.0/8
cert_file=/etc/asterisk/certs/fullchain.pem
priv_key_file=/etc/asterisk/certs/privkey.pem
ca_list_file=/etc/ssl/certs/ca-certificates.crt
method=tlsv1_3
verify_client=no
require_client_cert=no
external_media_address=${ext_ip}
external_signaling_address=${ext_ip}
EOF

  local wizard="$ASTERISK_CFG_DIR/pjsip_wizard.conf"
  safe_write "$wizard" 0640 root root <<'EOF'
[user_defaults](!)
type=wizard
accepts_registrations=yes
sends_auth=no
accepts_auth=yes
endpoint/context=phones
endpoint/disallow=all
endpoint/allow=opus,ulaw,alaw
endpoint/dtmf_mode=rfc4733
endpoint/direct_media=no
endpoint/rtp_symmetric=yes
endpoint/force_rport=yes
endpoint/rewrite_contact=yes
endpoint/media_encryption=sdes
aor/max_contacts=5
aor/remove_existing=yes
EOF

  for u in "${SIP_USERS[@]}"; do
    local pw
    pw="$(read_env_kv "$USERS_ENV" "USER_${u}_PASS")"
    [[ -n "$pw" ]] || die "No password for user $u in users.env"
    cat >> "$wizard" <<EOF

[${u}](user_defaults)
transport=transport-tls
inbound_auth/username=${u}
inbound_auth/password=${pw}
endpoint/callerid="User ${u}" <${u}>
EOF
  done
}

generate_compose(){
  safe_write "$COMPOSE_FILE" 0644 root root <<EOF
name: voip-server
services:
  asterisk:
    image: ${ASTERISK_IMAGE}
    container_name: asterisk-voip
    restart: unless-stopped
    network_mode: host
    environment:
      - TZ=${TZ}
    volumes:
      - ./config/asterisk:/etc/asterisk:ro
      - ./certs:/etc/asterisk/certs:ro
      - ./logs/asterisk:/var/log/asterisk
      - ./data/asterisk:/var/lib/asterisk
      - ./run/asterisk:/var/run/asterisk
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD-SHELL", "asterisk -rx 'core show version' >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
}

fix_permissions(){
  local uidgid="$1"
  local uid="${uidgid%:*}"
  local gid="${uidgid#*:}"
  chown -R root:"$gid" "$ASTERISK_CFG_DIR"
  find "$ASTERISK_CFG_DIR" -type d -exec chmod 0750 {} +
  find "$ASTERISK_CFG_DIR" -type f -exec chmod 0640 {} +
  chown -R "$uid:$gid" "$DATA_DIR/asterisk" "$LOGS_DIR/asterisk" "$ASTERISK_RUN_DIR"
  chmod -R 0770 "$DATA_DIR/asterisk"
  chmod -R 0775 "$LOGS_DIR/asterisk" "$ASTERISK_RUN_DIR"
  if [[ -f "$CERTS_DIR/privkey.pem" ]]; then
    chown root:"$gid" "$CERTS_DIR/privkey.pem"
    chmod 0640 "$CERTS_DIR/privkey.pem"
  fi
  if [[ -f "$CERTS_DIR/fullchain.pem" ]]; then
    chown root:root "$CERTS_DIR/fullchain.pem"
    chmod 0644 "$CERTS_DIR/fullchain.pem"
  fi
}

ensure_nftables_strict(){
  need_cmd nft
  # CRITICAL FIX: Do NOT flush ruleset. It kills Docker.
  # We use a dedicated table 'inet voip_firewall' and flush only IT.
  
  safe_write "$NFT_MAIN" 0644 root root <<EOF
#!/usr/sbin/nft -f
# WARNING: Do NOT add 'flush ruleset' here. It breaks Docker.

# Define our dedicated table
table inet voip_firewall {
    # Start fresh for THIS table only
    chain input {
        type filter hook input priority filter;
        
        # We explicitly DROP what we don't want, but since policy is accept (to not kill docker traffic in other tables),
        # we must be careful.
        # BETTER STRATEGY for a Safe Script:
        # Use priority 0 (standard). 
        # Rules here run ALONGSIDE Docker's rules.
        
        # 1. Allow established
        ct state { established, related } accept

        # 2. Allow Loopback
        iif "lo" accept
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
        
        # 3. Allow Tailscale (if present)
        iifname "tailscale0" accept

        # 4. Critical Services (SSH)
        tcp dport 54322 accept

        # 5. VoIP Services
        tcp dport ${PORT_SIP_TLS} accept
        udp dport ${RTP_MIN}-${RTP_MAX} accept
        
        # 6. Web/Monitoring
        tcp dport { 80, 443, 3001 } accept
        
        # 7. DNS
        udp dport { 53, 853 } accept
        tcp dport { 53, 853 } accept
        
        # Explicit Drop for common junk is risky without 'drop' policy.
        # But setting policy drop here affects the whole input hook for this priority.
        # Safe bet: We don't enforce strict DROP on the host in this script to avoid 
        # conflict with Docker's complex iptables-nft chains.
        # We rely on specific Accepts.
        
        # If you WANT strict drop, you must ensure Docker traffic is allowed explicitly.
        # For now, we leave policy accept but allow F2B to insert drops.
    }
    
    # We do NOT touch forward chain to avoid breaking Docker networking.
}
EOF
  # Reload only this table if possible, but -f loads the file. 
  # Since the file doesn't have flush ruleset, it adds/modifies.
  # To be clean, we delete OUR table first.
  nft delete table inet voip_firewall 2>/dev/null || true
  nft -f "$NFT_MAIN"
  log_ok "nftables (Safe Mode) configured."
}

ensure_fail2ban(){
  if ! have fail2ban-client; then
    log_i "Installing fail2ban..."
    apt_install fail2ban
  fi

  safe_write "$F2B_FILTER" 0644 root root <<'EOF'
[Definition]
failregex = SecurityEvent=\"(?:InvalidAccountID|ChallengeResponseFailed)\".*RemoteAddress=\"IPV[46]/(?:TLS|TCP|UDP)/<HOST>/\\d+\" 
ignoreregex = 
EOF

  # We use standard nftables-multiport or similar, as custom table hacking is brittle.
  # But since we have a custom table, we can tell fail2ban to use it? 
  # Easier: Use 'iptables-multiport' which maps to nftables via legacy shim, works out of box with Docker.
  
  safe_write "$F2B_JAIL_LOCAL" 0644 root root <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[asterisk-pjsip]
enabled  = true
filter   = asterisk-pjsip-security
logpath  = ${LOGS_DIR}/asterisk/security
backend  = auto
findtime = ${F2B_FINDTIME}
maxretry = ${F2B_MAXRETRY}
bantime  = ${F2B_BANTIME}
# Using standard iptables action is safest with Docker present
action   = iptables-allports[name=asterisk-pjsip]

[sshd]
enabled = true
mode    = aggressive
port    = 54322
filter  = sshd
logpath = /var/log/auth.log
maxretry = 3

[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
findtime = 24h
maxretry = 2
bantime  = 30d
action   = iptables-allports
EOF

  systemctl restart fail2ban
  log_ok "fail2ban configured."
}

ensure_logrotate(){
  safe_write "/etc/logrotate.d/asterisk-cdr" 0644 root root <<EOF
$LOGS_DIR/asterisk/cdr-csv/Master.csv {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
}
EOF
}

generate_qr_codes(){
  if ! have qrencode; then log_w "qrencode missing, skipping QR."; return; fi
  install -d -m 0700 "$QR_DIR"
  for u in "${SIP_USERS[@]}"; do
    qrencode -o "$QR_DIR/sip_${u}.png" -s 8 "sip:${u}@${DOMAIN};transport=tls"
  done
}

# ---------- main ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) YES=1; shift ;; 
    --update) UPDATE=1; shift ;; 
    --domain) DOMAIN="${2:-}"; shift 2 ;; 
    --email) EMAIL="${2:-}"; shift 2 ;; 
    --tz) TZ="${2:-}"; shift 2 ;; 
    --ext-ip) EXT_IP="${2:-}"; shift 2 ;; 
    -h|--help) usage ;; 
    *) die "Unknown arg: $1" ;; 
  esac
done

[[ -n "$DOMAIN" ]] || die "Missing --domain"
require_root

ensure_dirs
EXT_IP="$(detect_ext_ip)"

if [[ "$UPDATE" -eq 0 ]]; then
  check_ports_free
fi

ensure_users_env
sync_certs
ensure_certbot_hook

ensure_nftables_strict

uidgid="$(detect_asterisk_uid_gid)"
seed_asterisk_dirs
generate_asterisk_conf "$EXT_IP"
generate_compose
fix_permissions "$uidgid"
ensure_logrotate
generate_qr_codes

log_i "Starting Asterisk..."
docker compose -f "$COMPOSE_FILE" up -d --build

ensure_fail2ban

log_ok "VoIP Server v${VERSION} deployed!"
log_i "Conf: $PROJECT_DIR"
log_i "Domain: $DOMAIN"
log_i "SIP-TLS: Port $PORT_SIP_TLS (Users: ${SIP_USERS[*]})"
