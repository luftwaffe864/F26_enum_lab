#!/usr/bin/env bash
# =============================================================================
#  ENUM QUEST — setup_jumpbox.sh   (run with sudo on the student jumpbox)
#
#  Provisions the Kali Linux jumpbox for the DCIG enumeration lab.
#  (Also works on Debian/Ubuntu if needed.)
#  Uses the account that invoked sudo (e.g. ocig1, ocig2, …), not a
#  separate "student" user. Password convention in class: ocigN / ocigN.
#
#    sudo ./setup_jumpbox.sh              install tools + game, then start game
#    sudo ./setup_jumpbox.sh --no-switch  install only (Salt / unattended)
#    sudo ./setup_jumpbox.sh --state      refresh briefing / answers / hosts only
#    sudo ./setup_jumpbox.sh --user ocig3  force which login account owns the lab
#
#  Environment (Salt pillar / mentor overrides):
#    TARGET_UBUNTU_IP   default 192.168.1.11
#    TARGET_WIN_IP      default 192.168.1.12
#    TARGET_UBUNTU_HOST default vault-web
#    TARGET_WIN_HOST    default vault-dc
#    LAB_DOMAIN         default vault.lab
# =============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0"; exit 1; }

MODE=install
SWITCH=1
FORCE_USER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-switch) SWITCH=0; shift ;;
    --state|state) MODE=state; SWITCH=0; shift ;;
    --install|install) MODE=install; shift ;;
    --user) FORCE_USER="${2:-}"; shift 2 ;;
    *) echo "usage: $0 [--install|--state|--no-switch] [--user NAME]"; exit 1 ;;
  esac
done

TARGET_UBUNTU_IP=${TARGET_UBUNTU_IP:-192.168.1.11}
TARGET_WIN_IP=${TARGET_WIN_IP:-192.168.1.12}
TARGET_UBUNTU_HOST=${TARGET_UBUNTU_HOST:-vault-web}
TARGET_WIN_HOST=${TARGET_WIN_HOST:-vault-dc}
LAB_DOMAIN=${LAB_DOMAIN:-vault.lab}

LIB=/usr/local/lib/enum-quest
CFG=/etc/enum-quest
SELF="$(readlink -f "$0")"
GAME_SRC="$(dirname "$SELF")/enum_quest.sh"
WORDLIST_SRC="$(dirname "$SELF")/wordlists"

have() { command -v "$1" >/dev/null 2>&1; }
log() { echo "[jumpbox] $*"; }

is_kali() {
  grep -qi kali /etc/os-release 2>/dev/null || [[ -f /etc/kali-version ]]
}

apt_try() {
  # Install packages that exist; skip quietly if a name is missing on this distro
  local p
  for p in "$@"; do
    if apt-cache show "$p" >/dev/null 2>&1; then
      apt-get install -y -qq "$p" >/dev/null 2>&1 || log "WARNING: failed to install $p"
    fi
  done
}

resolve_player() {
  local u=""
  if [[ -n "$FORCE_USER" ]]; then
    u="$FORCE_USER"
  elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    u="$SUDO_USER"
  else
    # Prefer ocigN accounts if present (lab convention: ocig1, ocig2, …)
    u=$(getent passwd | awk -F: '$1 ~ /^ocig[0-9]+$/ {print $1; exit}')
  fi
  if [[ -z "$u" ]] || ! id "$u" >/dev/null 2>&1; then
    echo "Cannot determine login user. Re-run as: sudo $0 --user ocig1" >&2
    exit 1
  fi
  PLAYER="$u"
  H=$(getent passwd "$PLAYER" | cut -d: -f6)
  [[ -d "$H" ]] || { echo "Home for $PLAYER not found"; exit 1; }
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  if is_kali; then
    log "detected Kali — ensuring enum tools (many are already present)"
  else
    log "non-Kali jumpbox — installing enumeration tools via apt"
  fi

  apt-get update -qq

  # Core tools used by ENUM QUEST levels (Kali usually has these already)
  apt_try nmap curl dnsutils smbclient ftp lftp wget unzip ca-certificates \
    enum4linux enum4linux-ng ffuf python3

  # netcat: Kali often ships netcat-traditional; Debian/Ubuntu prefer openbsd
  apt_try netcat-openbsd netcat-traditional ncat

  if ! have enum4linux && ! have enum4linux-ng; then
    log "WARNING: enum4linux not found; students can still use smbclient / nmap scripts"
  fi

  install_ffuf
}

install_ffuf() {
  if have ffuf; then log "ffuf already present ($(command -v ffuf))"; return; fi
  # Prefer distro package (Kali ships ffuf)
  apt_try ffuf
  if have ffuf; then log "installed ffuf from apt"; return; fi

  local ver="2.1.0" arch tmp
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) log "WARNING: no ffuf binary for $(uname -m); install manually"; return ;;
  esac
  tmp=$(mktemp -d)
  if wget -q -O "$tmp/ffuf.tar.gz" \
    "https://github.com/ffuf/ffuf/releases/download/v${ver}/ffuf_${ver}_linux_${arch}.tar.gz"; then
    tar -xzf "$tmp/ffuf.tar.gz" -C "$tmp"
    install -m 755 "$tmp/ffuf" /usr/local/bin/ffuf
    log "installed /usr/local/bin/ffuf (GitHub release)"
  else
    log "WARNING: could not download ffuf — offline Kali? use: sudo apt install ffuf"
  fi
  rm -rf "$tmp"
}

install_game() {
  install -d -m 755 "$LIB" "$CFG"
  cp "$SELF" "$LIB/setup_jumpbox.sh"
  chmod 755 "$LIB/setup_jumpbox.sh"
  if [[ -f "$GAME_SRC" ]]; then
    install -m 755 "$GAME_SRC" /usr/local/bin/enum-quest
    log "installed /usr/local/bin/enum-quest"
  else
    log "WARNING: enum_quest.sh missing next to setup_jumpbox.sh"
  fi
  if [[ ! -s "$CFG/secret" ]]; then
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$CFG/secret"
  fi
  chmod 644 "$CFG/secret"
}

write_targets_and_answers() {
  install -d -m 755 "$CFG"
  cat > "$CFG/targets.conf" <<EOF
# ENUM QUEST targets (edited by setup / Salt)
UBUNTU_HOST=$TARGET_UBUNTU_HOST
UBUNTU_IP=$TARGET_UBUNTU_IP
WIN_HOST=$TARGET_WIN_HOST
WIN_IP=$TARGET_WIN_IP
LAB_DOMAIN=$LAB_DOMAIN
EOF
  chmod 644 "$CFG/targets.conf"

  # Canonical answers — must match setup_ubuntu_target.sh / setup_win_target.ps1
  cat > "$CFG/answers" <<EOF
BRIEFING_CODE=OSPREY
TARGET_COUNT=2
UBUNTU_HOST=$TARGET_UBUNTU_HOST
WIN_HOST=$TARGET_WIN_HOST
UBUNTU_IP=$TARGET_UBUNTU_IP
WIN_IP=$TARGET_WIN_IP
SSH_PORT=22
RDP_PORT=3389
SMB_PORT=445
FTP_PORT=21
DNS_PORT=53
HTTP_PORT=80
UBUNTU_OPEN_PORTS=21,22,53,80,139,445
WIN_OPEN_PORTS=53,80,445,3389
WEB_SVC_UBUNTU=nginx
WEB_SVC_WIN=iis
SSH_PRODUCT=openssh
DNS_SVC=domain
SMB_SVC=microsoft-ds
FTP_SVC=ftp
FTP_ANON=yes
FTP_FLAG_FILE=flag.txt
WIN_USER_SVC=svc_backup
WIN_USER_INTERN=intern
LINUX_USER_WEB=webadmin
LINUX_USER_DEPLOY=deploy
SHARE_PUBLIC=Public
SHARE_FINANCE=Finance
SHARE_HIDDEN=IT$
SHARE_LINUX=teamfiles
FLAG_FTP=FLAG{ftp_anon_loot}
FLAG_SMB_PUBLIC=FLAG{smb_public_read}
FLAG_SMB_LINUX=FLAG{linux_share_loot}
ROBOTS_PATH_ADMIN=/admin
ROBOTS_PATH_BACKUP=/backup
FLAG_WEB_ADMIN=FLAG{web_admin_panel}
FLAG_WEB_SECRET=FLAG{iis_secret_stash}
FLAG_WEB_BACKUP=FLAG{nginx_backup_note}
DNS_TXT_FLAG=FLAG{dns_zone_transfer}
DNS_MX=mail.$LAB_DOMAIN
DNS_A_WEB=$TARGET_UBUNTU_HOST.$LAB_DOMAIN
DNS_A_DC=$TARGET_WIN_HOST.$LAB_DOMAIN
LAB_DOMAIN=$LAB_DOMAIN
EOF
  chmod 644 "$CFG/answers"
}

plant_hosts_and_home() {
  sed -i.bak \
    -e "/[[:space:]]$TARGET_UBUNTU_HOST\$/d" \
    -e "/[[:space:]]$TARGET_WIN_HOST\$/d" \
    -e "/[[:space:]]$TARGET_UBUNTU_HOST\\.$LAB_DOMAIN\$/d" \
    -e "/[[:space:]]$TARGET_WIN_HOST\\.$LAB_DOMAIN\$/d" \
    /etc/hosts 2>/dev/null || true
  {
    echo "$TARGET_UBUNTU_IP  $TARGET_UBUNTU_HOST $TARGET_UBUNTU_HOST.$LAB_DOMAIN"
    echo "$TARGET_WIN_IP  $TARGET_WIN_HOST $TARGET_WIN_HOST.$LAB_DOMAIN"
  } >> /etc/hosts

  install -d -o "$PLAYER" -g "$PLAYER" "$H/wordlists" "$H/notes"

  if [[ -d "$WORDLIST_SRC" ]]; then
    cp -a "$WORDLIST_SRC/." "$H/wordlists/"
  else
    cat > "$H/wordlists/common.txt" <<'EOF'
admin
login
backup
secret
assets
images
api
test
dev
old
EOF
  fi
  chown -R "$PLAYER:$PLAYER" "$H/wordlists" "$H/notes"

  cat > "$H/briefing.txt" <<EOF
=== ENUM QUEST BRIEFING — DCIG Recon Lab ===

You are on a Kali jumpbox. Your job is to enumerate two systems on the lab network
without exploiting them. Map what is there, then move on.

Targets (also in /etc/enum-quest/targets.conf):
  Linux  : $TARGET_UBUNTU_HOST  ($TARGET_UBUNTU_IP)
  Windows: $TARGET_WIN_HOST   ($TARGET_WIN_IP)
  Domain : $LAB_DOMAIN

Missions:
  1. NETWORK   - find live hosts and open ports (nmap)
  2. SERVICES  - identify what those ports run (nmap -sV, banners)
  3. USERS     - discover accounts (enum4linux, smbclient)
  4. SHARES    - FTP first, then SMB shares
  5. WEB       - curl and ffuf the HTTP sites
  6. DNS       - dig records and zone data

You are logged in as: $PLAYER
Start the lab with:  enum-quest

Briefing codeword: OSPREY
EOF
  chown "$PLAYER:$PLAYER" "$H/briefing.txt"
}

# ---------------------------------------------------------------------------
resolve_player
log "player account: $PLAYER  home: $H"

case "$MODE" in
  install)
    install_packages
    install_game
    write_targets_and_answers
    plant_hosts_and_home
    log "done. Run as $PLAYER:  enum-quest"
    if (( SWITCH )) && [[ -t 0 && -t 1 ]]; then
      log "switching to $PLAYER and starting enum-quest..."
      trap '' INT
      exec su - "$PLAYER" -c enum-quest
    fi
    ;;
  state)
    write_targets_and_answers
    plant_hosts_and_home
    log "briefing / targets / answers refreshed for $PLAYER"
    ;;
  *) echo "usage: $0 [--install|--state|--no-switch] [--user NAME]"; exit 1 ;;
esac
