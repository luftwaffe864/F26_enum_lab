#!/usr/bin/env bash
# =============================================================================
#  ENUM QUEST — setup_ubuntu_target.sh   (run as root on the Ubuntu target)
#
#  Plants SSH, nginx, Bind9 (AXFR), vsftpd (FTP), and Samba for the lab.
#
#    sudo ./setup_ubuntu_target.sh
#    sudo ./setup_ubuntu_target.sh --state
#    sudo ./setup_ubuntu_target.sh --no-switch   (Salt; same as install)
#
#  Env overrides: LAB_DOMAIN, TARGET_UBUNTU_HOST, TARGET_WIN_HOST,
#                 TARGET_UBUNTU_IP, TARGET_WIN_IP, JUMPBOX_CIDR (AXFR ACL)
#  Defaults (same on every team pod): 192.168.1.10 / 192.168.1.11 / 192.168.1.0/24
# =============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }

MODE="${1:-install}"
[[ "$MODE" == "--no-switch" ]] && MODE=install
[[ "$MODE" == "--state" || "$MODE" == "state" ]] && MODE=state
[[ "$MODE" == "--install" || "$MODE" == "install" ]] || {
  echo "usage: $0 [--install|--state|--no-switch]"; exit 1
}

LAB_DOMAIN=${LAB_DOMAIN:-vault.lab}
TARGET_UBUNTU_HOST=${TARGET_UBUNTU_HOST:-vault-web}
TARGET_WIN_HOST=${TARGET_WIN_HOST:-vault-dc}
TARGET_UBUNTU_IP=${TARGET_UBUNTU_IP:-192.168.1.10}
TARGET_WIN_IP=${TARGET_WIN_IP:-192.168.1.11}
JUMPBOX_CIDR=${JUMPBOX_CIDR:-192.168.1.0/24}

have() { command -v "$1" >/dev/null 2>&1; }
systemd_up() { have systemctl && [[ -d /run/systemd/system ]]; }
log() { echo "[ubuntu-target] $*"; }

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "installing nginx bind9 vsftpd samba openssh"
  apt-get update -qq
  apt-get install -y -qq nginx bind9 vsftpd samba openssh-server ftp >/dev/null
}

ensure_users() {
  id webadmin >/dev/null 2>&1 || useradd -m -s /bin/bash -c "Web Admin" webadmin
  id deploy >/dev/null 2>&1 || useradd -m -s /bin/bash -c "Deploy Bot" deploy
  echo "webadmin:WebAdmin!lab" | chpasswd
  echo "deploy:Deploy!lab" | chpasswd
}

plant_nginx() {
  log "planting nginx site"
  rm -rf /var/www/html
  install -d -m 755 /var/www/html/admin /var/www/html/backup /var/www/html/assets

  cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html><head><title>Vault Corp</title></head>
<body style="font-family:sans-serif;margin:2rem">
  <h1>Vault Corp — Internal Portal</h1>
  <p>Welcome to the $LAB_DOMAIN intranet host <code>$TARGET_UBUNTU_HOST</code>.</p>
  <p>See <a href="/robots.txt">robots.txt</a>.</p>
</body></html>
EOF

  cat > /var/www/html/robots.txt <<'EOF'
User-agent: *
Disallow: /admin
Disallow: /backup
EOF

  cat > /var/www/html/admin/index.html <<'EOF'
<!DOCTYPE html>
<html><head><title>Admin</title></head>
<body>
  <h1>Admin (should not be public)</h1>
  <p><code>FLAG{web_admin_panel}</code></p>
</body></html>
EOF

  cat > /var/www/html/backup/notes.txt <<'EOF'
backup scratch pad — do not publish
FLAG{nginx_backup_note}
EOF

  cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;
    location / { try_files $uri $uri/ =404; }
}
EOF

  if systemd_up; then
    systemctl enable --now nginx >/dev/null 2>&1 || systemctl restart nginx
  fi
}

plant_bind() {
  log "planting Bind9 zone $LAB_DOMAIN (AXFR open to $JUMPBOX_CIDR)"
  local named_conf=/etc/bind/named.conf.options
  local zone_conf=/etc/bind/named.conf.local
  local zone_file=/etc/bind/db.$LAB_DOMAIN

  cat > "$named_conf" <<EOF
options {
    directory "/var/cache/bind";
    allow-query { any; };
    allow-transfer { $JUMPBOX_CIDR; 127.0.0.1; };
    recursion no;
    dnssec-validation no;
    listen-on { any; };
    listen-on-v6 { any; };
};
EOF

  cat > "$zone_conf" <<EOF
zone "$LAB_DOMAIN" {
    type master;
    file "$zone_file";
    allow-transfer { $JUMPBOX_CIDR; 127.0.0.1; };
};
EOF

  cat > "$zone_file" <<EOF
\$TTL 300
@   IN SOA  ns1.$LAB_DOMAIN. admin.$LAB_DOMAIN. (
        2026010101 ; serial
        3600       ; refresh
        600        ; retry
        86400      ; expire
        300 )      ; minimum
@           IN NS    ns1.$LAB_DOMAIN.
@           IN MX 10 mail.$LAB_DOMAIN.
@           IN TXT   "FLAG{dns_zone_transfer}"
ns1         IN A     $TARGET_UBUNTU_IP
mail        IN A     $TARGET_UBUNTU_IP
$TARGET_UBUNTU_HOST IN A $TARGET_UBUNTU_IP
$TARGET_WIN_HOST    IN A $TARGET_WIN_IP
www         IN CNAME $TARGET_UBUNTU_HOST.$LAB_DOMAIN.
EOF

  if systemd_up; then
    systemctl enable --now named >/dev/null 2>&1 || systemctl enable --now bind9 >/dev/null 2>&1 || true
    systemctl restart named >/dev/null 2>&1 || systemctl restart bind9 >/dev/null 2>&1 || true
  fi
}

plant_ftp() {
  log "planting vsftpd (anonymous read)"
  install -d -m 755 /srv/ftp/pub
  # Ubuntu vsftpd often uses /srv/ftp as anon root
  echo "anonymous ftp drop — not for production" > /srv/ftp/pub/readme.txt
  echo "FLAG{ftp_anon_loot}" > /srv/ftp/pub/flag.txt
  chmod 644 /srv/ftp/pub/*

  cat > /etc/vsftpd.conf <<'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=YES
local_enable=NO
write_enable=NO
anon_root=/srv/ftp
anon_world_readable_only=YES
anon_upload_enable=NO
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO
pasv_min_port=40000
pasv_max_port=40100
EOF

  install -d -m 755 /var/run/vsftpd/empty
  if systemd_up; then
    systemctl enable --now vsftpd >/dev/null 2>&1 || true
    systemctl restart vsftpd >/dev/null 2>&1 || true
  fi
}

plant_samba() {
  log "planting Samba users and teamfiles share"
  install -d -m 775 -o deploy -g deploy /srv/teamfiles
  echo "team share — internal only" > /srv/teamfiles/readme.txt
  echo "FLAG{linux_share_loot}" > /srv/teamfiles/loot.txt
  chown -R deploy:deploy /srv/teamfiles

  cat > /etc/samba/smb.conf <<'EOF'
[global]
   workgroup = VAULT
   server string = Vault Linux File Server
   map to guest = Bad User
   usershare allow guests = no
   smb ports = 445 139

[teamfiles]
   path = /srv/teamfiles
   browseable = yes
   read only = yes
   guest ok = yes
EOF

  # Samba passwords (lab-only)
  (echo "WebAdmin!lab"; echo "WebAdmin!lab") | smbpasswd -a -s webadmin >/dev/null 2>&1 || true
  (echo "Deploy!lab"; echo "Deploy!lab") | smbpasswd -a -s deploy >/dev/null 2>&1 || true
  smbpasswd -e webadmin >/dev/null 2>&1 || true
  smbpasswd -e deploy >/dev/null 2>&1 || true

  if systemd_up; then
    systemctl enable --now smbd nmbd >/dev/null 2>&1 || true
    systemctl restart smbd nmbd >/dev/null 2>&1 || true
  fi
}

ensure_ssh() {
  if systemd_up; then
    systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now sshd >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
case "$MODE" in
  install)
    install_packages
    ensure_users
    plant_nginx
    plant_bind
    plant_ftp
    plant_samba
    ensure_ssh
    log "ubuntu target ready ($TARGET_UBUNTU_HOST / $LAB_DOMAIN)"
    ;;
  state)
    ensure_users
    plant_nginx
    plant_bind
    plant_ftp
    plant_samba
    ensure_ssh
    log "ubuntu target state refreshed"
    ;;
esac
