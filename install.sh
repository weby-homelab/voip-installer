#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# ============================================================ 
# VoIP Server Installer v4.7.5
# Stack: Asterisk 22 (Docker, host network)
# SIP: TLS 5061 (PJSIP Wizard), SRTP SDES, ICE enabled
# Firewall: nftables (Strict Mode: DROP policy + Auto-SSH) + Fail2Ban
# Changes v4.7.5: Strict firewall by default (whitelist only)
# ============================================================ 

VERSION="4.7.5"

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
UPDATE=0

DOMAIN=""
EMAIL=""
TZ="UTC"
EXT_IP=""
CERT_PATH=""      # Custom certs path
ASTERISK_UIDGID="" # Custom UID:GID

ASTERISK_IMAGE="andrius/asterisk:22"
SIP_USERS=({100..105})
PORT_SIP_TLS=5061
RTP_MIN=10000
RTP_MAX=19999
F2B_MAXRETRY=2
F2B_FINDTIME="600m"
F2B_BANTIME="120h"
TLS_METHODS="tlsv1_2 tlsv1_3"

# ---------- helpers ----------
have(){ command -v "$1" >/dev/null 2>&1; }
need_cmd(){ have "$1" || die "Command not found: $1"; }

install_dependencies(){
  log_i "Updating system and installing required dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  
  local pkgs=(
    curl wget openssl iproute2 
    nftables fail2ban 
    certbot 
    qrencode
  )
  
  # Check if docker is already installed to avoid conflicts (e.g. in CI/CD)
  if ! have docker; then
    pkgs+=(docker.io)
  else
    log_ok "Docker is already installed, skipping."
  fi

  if ! docker compose version >/dev/null 2>&1; then
    pkgs+=(docker-compose-v2)
  else
    log_ok "Docker Compose V2 is already installed, skipping."
  fi
  
  # Install packages ensuring no prompts
  apt-get install -y --no-install-recommends "${pkgs[@]}"
  
  # Enable docker if it was just installed or present
  if have systemctl; then
    systemctl enable --now docker || true
  fi
}

detect_compose_cmd(){
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    die "Neither 'docker compose' nor 'docker-compose' found. Install Docker Compose."
  fi
}

restart_service(){
  local svc="$1"
  if have systemctl; then
    systemctl restart "$svc" || log_w "Failed to restart $svc via systemctl"
  elif have service; then
    service "$svc" restart || log_w "Failed to restart $svc via service"
  else
    log_w "System service manager not found. Please restart '$svc' manually."
  fi
}

ensure_system_logging(){
  log_i "Configuring system & docker log limits (max 100MB)..."

  # 1. Systemd Journal
  if [[ -f /etc/systemd/journald.conf ]]; then
    # Create backup
    cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak 2>/dev/null || true
    # Ensure SystemMaxUse is set
    if grep -q "^SystemMaxUse=" /etc/systemd/journald.conf; then
      sed -i 's/^SystemMaxUse=.*/SystemMaxUse=100M/' /etc/systemd/journald.conf
    else
      # If commented out or missing
      if grep -q "^#SystemMaxUse=" /etc/systemd/journald.conf; then
        sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=100M/' /etc/systemd/journald.conf
      else
        echo "SystemMaxUse=100M" >> /etc/systemd/journald.conf
      fi
    fi
    restart_service systemd-journald
  fi

  # 2. Docker Daemon
  # We want defaults: max-size=20m, max-file=5 (Total 100MB)
  local daemon_json="/etc/docker/daemon.json"
  if [[ ! -f "$daemon_json" ]]; then
    safe_write "$daemon_json" 0644 root root <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  }
}
EOF
    restart_service docker
  else
    # Simple check if already configured to avoid restart loops or complex parsing without jq
    if ! grep -q "max-size" "$daemon_json"; then
      log_w "$daemon_json exists but might lack log-opts. Overwriting for safety (backup saved)."
      cp "$daemon_json" "${daemon_json}.bak"
      safe_write "$daemon_json" 0644 root root <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  }
}
EOF
      restart_service docker
    else
      log_ok "Docker daemon.json already has log settings."
    fi
  fi
}

usage(){
  cat <<USAGE
VoIP Server Installer v${VERSION}
Usage:
  ./install.sh --domain example.com [--email you@example.com] [options]

Options:
  --domain DOMAIN       Domain name for the server
  --email EMAIL         Email for Let\'s Encrypt
  --ext-ip IP           Manually specify external IP
  --cert-path PATH      Path to existing fullchain.pem/privkey.pem (skips certbot)
  --asterisk-uidgid U:G Manually specify Asterisk UID:GID (e.g. 1000:1000)
  --tz TIMEZONE         Timezone (default: UTC)
  --update              Update configs without overwriting users.env
  --yes                 Skip confirmation prompts

Note on DNS-01:
  If port 80 is not available, use --cert-path to provide certificates generated 
  manually via 'certbot certonly --manual --preferred-challenges dns -d DOMAIN'.
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
  tmp="$(mktemp "$dir/.tmp.XXXXXXXX")"
  
  # Set trap to clean up tmp file on return or error within this scope
  trap 'rm -f "$tmp"' RETURN
  
  cat > "$tmp"
  install -o "$owner" -g "$group" -m "$mode" "$tmp" "$path"
  
  # Explicit remove not strictly needed due to trap, but good practice
  rm -f "$tmp"
  trap - RETURN
}

detect_ext_ip(){
  local ip=""
  if [[ -n "$EXT_IP" ]]; then
    echo "$EXT_IP"; return 0
  fi
  
  local services=(https://api.ipify.org https://ifconfig.co https://icanhazip.com)
  for svc in "${services[@]}"; do
    if have curl; then
      ip="$(curl -4fsS "$svc" 2>/dev/null || true)"
    elif have wget; then
      ip="$(wget -qO- "$svc" 2>/dev/null || true)"
    else
      log_w "Neither curl nor wget available to detect external IP from $svc"
      continue
    fi
    
    # Trim whitespace
    ip="${ip//[[:space:]]/}" 
    
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo "$ip"
      return 0
    fi
  done
  
  die "Could not detect external IPv4. Use --ext-ip."
}

rand_b64(){
  openssl rand -base64 "$1" | tr -d '\n'
}

ensure_dirs(){
  install -d -m 0755 "$PROJECT_DIR" "$CFG_DIR" "$CERTS_DIR" "$DATA_DIR" "$LOGS_DIR" "$RUN_DIR"
  install -d -m 0755 "$ASTERISK_CFG_DIR" "$ASTERISK_CFG_DIR/certs"
  install -d -m 0755 "$DATA_DIR/asterisk" "$LOGS_DIR/asterisk" "$LOGS_DIR/asterisk/cdr-csv"
  install -d -m 0775 "$ASTERISK_RUN_DIR"
  install -d -m 0700 "$QR_DIR"
}

check_ports_free(){
  log_i "Checking ports..."
  local bad=0
  if ss -H -lnt "sport = :$PORT_SIP_TLS" | grep -q .; then log_w "TCP $PORT_SIP_TLS is busy"; bad=1; fi
  if [[ -z "$CERT_PATH" ]]; then
    if ss -H -lnt "sport = :80" | grep -q .; then log_w "TCP 80 is busy (needed for Certbot)"; bad=1; fi
  fi

  if [[ $bad -eq 0 ]]; then
    log_ok "Ports are free."
  else
    log_w "Port conflicts detected."
  fi
}

detect_asterisk_uid_gid(){
  if [[ -n "$ASTERISK_UIDGID" ]]; then
    echo "$ASTERISK_UIDGID"
    log_i "Using manual Asterisk UID:GID: $ASTERISK_UIDGID" >&2
    return
  fi

  local uid gid
  # Check if image exists locally to avoid implicit pull delay/error
  if docker image inspect "$ASTERISK_IMAGE" >/dev/null 2>&1; then
    uid="$(docker run --rm "$ASTERISK_IMAGE" id -u asterisk 2>/dev/null || echo 1000)"
    gid="$(docker run --rm "$ASTERISK_IMAGE" id -g asterisk 2>/dev/null || echo 999)"
    log_i "Detected Asterisk UID:GID from image: $uid:$gid" >&2
  else
    log_w "Image $ASTERISK_IMAGE not found locally. Using default UID:GID 1000:999 to avoid pull." >&2
    log_w "Use --asterisk-uidgid if you need custom permissions." >&2
    uid=1000
    gid=999
  fi
  echo "$uid:$gid"
}

seed_asterisk_dirs(){
  log_i "Seeding base Asterisk files..."
  # If image missing, this might pull, but user was warned.
  docker run --rm --user 0:0 -v "$ASTERISK_CFG_DIR:/dst" "$ASTERISK_IMAGE" sh -c 'cp -an /etc/asterisk/. /dst/ 2>/dev/null || true'
  docker run --rm --user 0:0 -v "$DATA_DIR/asterisk:/dst" "$ASTERISK_IMAGE" sh -c 'cp -an /var/lib/asterisk/. /dst/ 2>/dev/null || true'
}

ensure_users_env(){
  if [[ -f "$USERS_ENV" ]]; then
    log_ok "users.env exists, preserving."
    return
  fi
  
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
  local file="$1"
  local key="$2"
  # Use fixed-string grep to avoid regexp pitfalls
  grep -F "${key}=" "$file" | head -n1 | cut -d= -f2- || true
}

sync_certs(){
  # If user provided custom certs path
  if [[ -n "$CERT_PATH" ]]; then
    if [[ -f "$CERT_PATH/fullchain.pem" && -f "$CERT_PATH/privkey.pem" ]]; then
      log_i "Using custom certificates from $CERT_PATH"
      install -d -m 0755 "$CERTS_DIR"
      install -m 0644 "$CERT_PATH/fullchain.pem" "$CERTS_DIR/fullchain.pem"
      install -m 0640 "$CERT_PATH/privkey.pem" "$CERTS_DIR/privkey.pem"
      return
    else
      die "Custom certs not found at $CERT_PATH"
    fi
  fi

  local live="/etc/letsencrypt/live/${DOMAIN}"
  if [[ -d "$live" && -f "$live/fullchain.pem" && -f "$live/privkey.pem" ]]; then
    log_ok "Certificates found in $live"
  else
    log_w "No certificates found. Starting Certbot..."
    if ss -H -lnt "sport = :80" | grep -q .; then 
      die "Port 80 busy! Cannot run certbot standalone. Free port 80 or use --cert-path with manual certs."
    fi
    [[ -n "$EMAIL" ]] || die "Cert missing. Provide --email or --cert-path."
    need_cmd certbot
    certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"
  fi

  install -d -m 0755 "$CERTS_DIR"
  install -m 0644 "$live/fullchain.pem" "$CERTS_DIR/fullchain.pem"
  install -m 0640 "$live/privkey.pem" "$CERTS_DIR/privkey.pem"
}

ensure_certbot_hook(){
  [[ -n "$CERT_PATH" ]] && return 0 # Skip hook if using custom path

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
  local tls_methods_comma="${TLS_METHODS// /,}"
  log_i "Generating Asterisk configs (IP: $ext_ip, TLS: $tls_methods_comma)..."

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
method=${tls_methods_comma}
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
  # Use absolute paths in compose file to allow running from anywhere
  safe_write "$COMPOSE_FILE" 0644 root root <<EOF
services:
  asterisk:
    image: ${ASTERISK_IMAGE}
    container_name: asterisk-voip
    restart: unless-stopped
    network_mode: host
    environment:
      - TZ=${TZ}
    volumes:
      - ${ASTERISK_CFG_DIR}:/etc/asterisk:ro
      - ${CERTS_DIR}:/etc/asterisk/certs:ro
      - ${LOGS_DIR}/asterisk:/var/log/asterisk
      - ${DATA_DIR}/asterisk:/var/lib/asterisk
      - ${ASTERISK_RUN_DIR}:/var/run/asterisk
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
  
  log_i "Fixing permissions for $uid:$gid..."
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
  
  # Detect SSH port to avoid lockout
  local ssh_port
  if have ss; then
    ssh_port="$(ss -tlnp | grep -E 'sshd|ssh' | awk '{print $4}' | awk -F: '{print $NF}' | sort -n | head -n1 || true)"
  fi
  # Fallback if detection fails or empty
  [[ -z "$ssh_port" || ! "$ssh_port" =~ ^[0-9]+$ ]] && ssh_port=22
  
  log_i "Detected active SSH port: $ssh_port"

  # Backup existing table if it exists
  if nft list table inet voip_firewall >/dev/null 2>&1; then
    local bfile
    bfile="${PROJECT_DIR}/nft_backup_$(date -u +%Y%m%dT%H%M%SZ).conf"
    log_i "Backing up existing nftables table to $bfile"
    nft list table inet voip_firewall > "$bfile" 2>/dev/null || log_w "Failed to dump existing table"
    nft delete table inet voip_firewall 2>/dev/null || true
  fi
  
  safe_write "$NFT_MAIN" 0644 root root <<EOF
#!/usr/sbin/nft -f

table inet voip_firewall {
    chain input {
        type filter hook input priority filter; policy drop;
        
        # 1. Allow established/related
        ct state { established, related } accept

        # 2. Allow Loopback
        iif "lo" accept
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
        
        # 3. Allow Tailscale (optional, keep if interface exists)
        iifname "tailscale0" accept

        # 4. Critical: SSH (Detected port + Standard 22 to be safe)
        tcp dport { 22, ${ssh_port} } accept

        # 5. VoIP Services (SIP TLS + RTP)
        tcp dport ${PORT_SIP_TLS} accept
        udp dport ${RTP_MIN}-${RTP_MAX} accept
        
        # 6. Web (Certbot/monitor)
        tcp dport { 80, 443 } accept
    }
}
EOF
nft -f "$NFT_MAIN"
log_ok "nftables configured (Strict Mode: SSH=$ssh_port)."
}

ensure_fail2ban(){
  # Detect SSH port (standard logic)
  local ssh_port
  if have ss; then
    ssh_port="$(ss -tlnp | grep -E 'sshd|ssh' | awk '{print $4}' | awk -F: '{print $NF}' | sort -n | head -n1 || true)"
  fi
  [[ -z "$ssh_port" || ! "$ssh_port" =~ ^[0-9]+$ ]] && ssh_port=22

  # Installation handled globally in install_dependencies
  safe_write "$F2B_FILTER" 0644 root root <<'EOF'
[Definition]
failregex = SecurityEvent="(?:InvalidAccountID|ChallengeResponseFailed)".*RemoteAddress="IPV[46]/(?:TLS|TCP|UDP)/<HOST>/\d+" 
ignoreregex = 
EOF
  
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
# Note: Using iptables-allports acts as a shim for nftables in modern fail2ban.
# If full nftables native support is needed, update action to nftables-allports
action   = iptables-allports[name=asterisk-pjsip]

[sshd]
enabled = true
mode    = aggressive
port    = ${ssh_port}
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

  restart_service fail2ban
  log_ok "fail2ban configured (SSH Port: ${ssh_port})."
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
    --yes) shift ;; # Kept for compatibility 
    --update) UPDATE=1; shift ;; 
    --domain) DOMAIN="${2:-}"; shift 2 ;; 
    --email) EMAIL="${2:-}"; shift 2 ;; 
    --tz) TZ="${2:-}"; shift 2 ;; 
    --ext-ip) EXT_IP="${2:-}"; shift 2 ;;
    --cert-path) CERT_PATH="${2:-}"; shift 2 ;;
    --asterisk-uidgid) ASTERISK_UIDGID="${2:-}"; shift 2 ;;
    -h|--help) usage ;; 
    *) die "Unknown arg: $1" ;; 
  esac
done

# Start by installing everything needed
require_root
install_dependencies

# Early validation - these should now be present
need_cmd ss
need_cmd openssl
need_cmd nft
need_cmd docker
[[ -z "$CERT_PATH" ]] && need_cmd certbot # Only if cert-path not set

COMPOSE_CMD="$(detect_compose_cmd)"
log_i "Using compose command: $COMPOSE_CMD"

[[ -n "$DOMAIN" ]] || die "Missing --domain"

ensure_system_logging
ensure_dirs
EXT_IP="$(detect_ext_ip)"

ensure_users_env # Does internal check for existence

if [[ "$UPDATE" -eq 0 ]]; then
  check_ports_free
fi

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
OLD_IFS="$IFS"
IFS=$' \n\t'
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d --build
IFS="$OLD_IFS"

ensure_fail2ban

log_ok "VoIP Server v${VERSION} deployed!"
log_i "Conf: $PROJECT_DIR"
log_i "Domain: $DOMAIN"
log_i "SIP-TLS: Port $PORT_SIP_TLS (Users: ${SIP_USERS[*]})"