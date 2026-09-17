#!/usr/bin/env bash
# =============================================================================
#  LINUX QUEST — setup.sh   (run as root, Ubuntu 22.04 / 24.04)
#
#  Provisions one VM for the DCIG "Linux Basics for Cybersecurity" lab.
#
#    sudo ./setup.sh              full install: student account, packages,
#                                 game binary, and the compromised state
#    sudo ./setup.sh --state      rebuild ONLY the compromised state
#                                 (what the game's `reset` command calls)
#    sudo ./setup.sh --no-switch  full install, but do not launch the game
#                                 afterwards (for Salt / unattended runs)
#
#  When run from an interactive terminal, setup finishes by switching to the
#  student account and starting the game. Unattended runs (Salt, cron, no
#  TTY) just install and exit.
#
#  Idempotent: safe to run again at any time (Salt can run it on every apply).
#
#  What it creates
#    student account         student / password "123456", passwordless sudo
#    legit users             webadmin (password changed by "attacker"),
#                            group vault-team
#    rogue user              backup-svc (UID 1337) added to the sudo group
#    /root/.attacker_notes   readable only by root
#    /home/student/...       briefing, hidden note, logs/, junk/, site/, tools/
#    /usr/local/lib/.cache/  kworkerd (running rogue process), sync.sh (rogue
#                            service script), beacon.sh (cron job)
#    backup-sync.service     rogue systemd service, enabled + running
#    cron                    root crontab + /etc/cron.d/system-update entries,
#                            cron service stopped + disabled ("by the attacker")
#    /var/log/auth.log       200 planted SSH lines from 203.0.113.42
#    apt                     nginx pre-downloaded, package lists wiped so the
#                            student must run `apt update`; apt-daily timers
#                            disabled to avoid lock fights during class
# =============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }

MODE="${1:-install}"
SWITCH=1; [[ "$MODE" == "--no-switch" ]] && { MODE=install; SWITCH=0; }
STUDENT=student
STUDENT_PW=123456
H=/home/$STUDENT
LIB=/usr/local/lib/linux-quest
CFG=/etc/linux-quest
CACHE=/usr/local/lib/.cache
SELF="$(readlink -f "$0")"
GAME_SRC="$(dirname "$SELF")/linux_quest.sh"

have() { command -v "$1" >/dev/null 2>&1; }
systemd_up() { have systemctl && systemctl is-system-running >/dev/null 2>&1 || [[ -d /run/systemd/system ]]; }
log() { echo "[setup] $*"; }

# ---------------------------------------------------------------------------
# 1. Accounts (install mode only; state mode leaves student alone)
# ---------------------------------------------------------------------------
create_student() {
  if ! id "$STUDENT" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -c "DCIG Student" "$STUDENT"
    log "created user $STUDENT"
  fi
  echo "$STUDENT:$STUDENT_PW" | chpasswd
  install -d -m 755 /etc/sudoers.d
  echo "$STUDENT ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-linux-quest
  chmod 440 /etc/sudoers.d/90-linux-quest
}

# ---------------------------------------------------------------------------
# 2. Packages, game binary, secrets (install mode only)
# ---------------------------------------------------------------------------
install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "apt update + download nginx into the cache"
  apt-get update -qq
  apt-get install -y -qq curl iproute2 cron rsyslog man-db procps psmisc >/dev/null
  apt-get install -y -qq --download-only nginx >/dev/null
  # remove nginx if a previous run of the lab installed it
  if dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -q "install ok installed"; then
    apt-get purge -y -qq nginx nginx-common nginx-core >/dev/null 2>&1 || true
    apt-get autoremove -y -qq >/dev/null 2>&1 || true
    apt-get install -y -qq --download-only nginx >/dev/null
  fi
  rm -rf /var/www/html
  # wipe the lists so the student has to run `apt update` in mission 3
  rm -rf /var/lib/apt/lists/*
  if systemd_up; then
    systemctl disable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
  fi
}

install_game() {
  install -d -m 755 "$LIB" "$CFG"
  cp "$SELF" "$LIB/setup.sh"; chmod 755 "$LIB/setup.sh"
  if [[ -f "$GAME_SRC" ]]; then
    install -m 755 "$GAME_SRC" /usr/local/bin/linux-quest
    log "installed /usr/local/bin/linux-quest"
  else
    log "WARNING: linux_quest.sh not found next to setup.sh; game binary not installed"
  fi
  # secret used to sign score codes
  if [[ ! -s "$CFG/secret" ]]; then
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$CFG/secret"
  fi
  chmod 600 "$CFG/secret"
}

# ---------------------------------------------------------------------------
# 3. Compromised state (both modes)
# ---------------------------------------------------------------------------
gen_auth_lines() {
  # 200 deterministic SSH lines; PID 31337.. marks them as ours
  local users=(alice bob carol dave root mallory)
  local ips=(203.0.113.42 198.51.100.7 192.0.2.19 10.0.0.5 203.0.113.42 203.0.113.42)
  echo "Sep 07 08:00:01 vault sshd[31337]: Accepted password for root from 10.0.0.2 port 51022 ssh2"
  local i u ip hh mm ss
  for i in $(seq 2 199); do
    u=${users[$((i % 6))]}; ip=${ips[$((i % 6))]}
    hh=$(printf '%02d' $((8 + i / 60))); mm=$(printf '%02d' $((i % 60))); ss=$(printf '%02d' $((i % 59)))
    if (( i % 3 == 0 )); then
      echo "Sep 07 $hh:$mm:$ss vault sshd[$((31337 + i))]: Accepted password for $u from $ip port $((40000 + i)) ssh2"
    else
      echo "Sep 07 $hh:$mm:$ss vault sshd[$((31337 + i))]: Failed password for $u from $ip port $((40000 + i)) ssh2"
    fi
  done
  echo "Sep 07 12:00:00 vault sshd[31537]: Failed password for mallory from 203.0.113.42 port 59999 ssh2"
}

state_users() {
  getent group vault-team >/dev/null || groupadd vault-team

  # legit user whose password the attacker changed
  id webadmin >/dev/null 2>&1 || useradd -m -s /bin/bash -c "Web Admin" webadmin
  echo "webadmin:$(head -c 12 /dev/urandom | base64)" | chpasswd
  getent shadow webadmin | cut -d: -f2 > "$CFG/webadmin.hash"; chmod 600 "$CFG/webadmin.hash"
  usermod -aG vault-team webadmin

  # analyst account is created by the student in mission 2; remove leftovers
  if id analyst >/dev/null 2>&1; then userdel -r analyst 2>/dev/null || true; fi

  # rogue user
  if ! id backup-svc >/dev/null 2>&1; then
    useradd -m -u 1337 -s /bin/bash -c "Backup Service" backup-svc
  fi
  echo "backup-svc:$(head -c 12 /dev/urandom | base64)" | chpasswd
  usermod -aG sudo backup-svc
  cat > /home/backup-svc/.bash_history <<'EOF'
whoami
sudo -l
cat /etc/passwd
cp /bin/sleep /usr/local/lib/.cache/kworkerd
systemctl stop cron
crontab -e
history -c
EOF
  chown backup-svc:backup-svc /home/backup-svc/.bash_history

  cat > /root/.attacker_notes <<'EOF'
== notes (do not leave this here) ==
- got in as root with the default password, lol
- made account backup-svc (uid 1337), added to sudo so I keep access
- changed webadmin's password so they can't push the site
- dropped tools in /usr/local/lib/.cache/
- backup-sync.service keeps my sync running, cron restarts the rest
codeword: FALCON
EOF
  chmod 600 /root/.attacker_notes
}

state_home() {
  rm -rf "$H"/{briefing.txt,.hidden_note,logs,junk,evidence,site,tools}
  install -d -o $STUDENT -g $STUDENT "$H"/{logs,junk,site,tools}

  cat > "$H/briefing.txt" <<'EOF'
=== INCIDENT BRIEFING: server "vault" ===
Last night someone broke into the DCIG web server. The site is down,
the admin is locked out, and strange things are running.

You have been given an account on the server. Your job, in three missions:
  1. TRIAGE    - get oriented and find the attacker's traces
  2. LOCKDOWN  - take back control: accounts, permissions, processes, services
  3. REBUILD   - remove persistence, prove it in the logs, bring the site back

Codeword for this briefing: OSPREY
Every command you learn is a tool in your kit. Good luck.
EOF

  cat > "$H/.hidden_note" <<'EOF'
Files that start with a dot are hidden from a plain `ls`.
Attackers love hiding things this way. Remember `ls -a`.
Codeword: KESTREL
EOF

  gen_auth_lines > "$H/logs/auth.log"
  cat > "$H/logs/README.txt" <<'EOF'
auth.log = SSH login attempts exported by the sysadmin (who tried, from where, success/fail)
EOF
  printf 'Sep 06 23:59:00 vault kernel: usb 1-1: new device\n' > "$H/logs/kern.log"

  echo "temporary garbage, safe to delete" > "$H/junk/old.tmp"
  echo "more garbage" > "$H/junk/cache.tmp"

  # the club website, hijacked (owned by the attacker's account) + a leaked key
  cat > "$H/site/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head><title>DCIG - vault</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 15%">
  <h1>vault is back online</h1>
  <p>Restored by the DCIG incident response team.</p>
  <p><code>FLAG{vault_is_back_online}</code></p>
</body>
</html>
EOF
  printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n(fake key for the lab)\n-----END OPENSSH PRIVATE KEY-----\n' > "$H/site/deploy_key"
  chmod 644 "$H/site/deploy_key"

  cat > "$H/tools/audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "Running quick audit..."
sleep 1
echo "Users with a shell: $(grep -c '/bin/bash' /etc/passwd)"
echo "Audit code: 4471"
EOF
  chmod 644 "$H/tools/audit.sh"

  chown -R $STUDENT:$STUDENT "$H"
  chown -R backup-svc:backup-svc "$H/site"

  # flag hidden outside the home directory (find / ... 2>/dev/null)
  install -d -m 755 /var/tmp/.cache
  echo "FLAG{stderr_to_dev_null}" > /var/tmp/.cache/vault-flag.txt
  chmod 644 /var/tmp/.cache/vault-flag.txt
}

state_malware() {
  install -d -m 755 "$CACHE"
  # A script rather than a copied binary: on newer Ubuntu /bin/sleep is a
  # multi-call coreutils binary that exits when renamed, so a copy would die.
  cat > "$CACHE/kworkerd" <<'EOF'
#!/usr/bin/env bash
# looks like a kernel worker, is not one
while true; do sleep 60; done
EOF
  chmod 755 "$CACHE/kworkerd"

  cat > "$CACHE/sync.sh" <<'EOF'
#!/usr/bin/env bash
echo "backup-sync started"
echo "sync target: exfil.badcorp.example"
while true; do
  date +"%F %T sync tick" >> /var/tmp/.sync.log
  sleep 60
done
EOF
  cat > "$CACHE/beacon.sh" <<'EOF'
#!/usr/bin/env bash
date +"%F %T beacon" >> /var/tmp/.beacon.log
EOF
  chmod 755 "$CACHE"/*.sh

  # rogue service
  cat > /etc/systemd/system/backup-sync.service <<EOF
[Unit]
Description=Backup synchronisation helper

[Service]
ExecStart=$CACHE/sync.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  # cron persistence
  if have crontab; then
    { crontab -l 2>/dev/null | grep -v "$CACHE" || true
      echo "@reboot $CACHE/kworkerd 99999"
      echo "*/10 * * * * $CACHE/beacon.sh"
    } | crontab -
  fi
  cat > /etc/cron.d/system-update <<EOF
# system update helper
*/15 * * * * root $CACHE/beacon.sh
EOF
  chmod 644 /etc/cron.d/system-update

  # rogue process running as root (cron @reboot would restart it)
  pkill -f "$CACHE/kworkerd" 2>/dev/null || true
  setsid nohup "$CACHE/kworkerd" 99999 </dev/null >/dev/null 2>&1 &

  if systemd_up; then
    systemctl daemon-reload
    systemctl enable backup-sync.service >/dev/null 2>&1
    systemctl restart backup-sync.service
    # "the attacker stopped cron so the admin's jobs would not run"
    systemctl disable --now cron >/dev/null 2>&1 || true
  fi
}

state_logs() {
  local f=/var/log/auth.log
  [[ -f $f ]] || { touch "$f"; chown root:adm "$f"; chmod 640 "$f"; }
  if ! grep -q 'sshd\[31337\]' "$f"; then
    gen_auth_lines >> "$f"
  fi
}

# ---------------------------------------------------------------------------
case "$MODE" in
  install|--install)
    create_student
    install_packages
    install_game
    state_users; state_home; state_malware; state_logs
    log "done. Student login: $STUDENT / $STUDENT_PW   Game: linux-quest"
    if (( SWITCH )) && [[ -t 0 && -t 1 ]]; then
      log "switching to $STUDENT and starting the game..."
      trap '' INT
      exec su - "$STUDENT" -c linux-quest
    fi
    ;;
  --state|state)
    state_users; state_home; state_malware; state_logs
    # mission 3 leftovers
    if dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -q "install ok installed"; then
      DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq nginx nginx-common nginx-core >/dev/null 2>&1 || true
      apt-get autoremove -y -qq >/dev/null 2>&1 || true
    fi
    rm -rf /var/www/html /var/lib/apt/lists/*
    log "compromised state rebuilt"
    ;;
  *) echo "usage: $0 [--install | --state | --no-switch]"; exit 1 ;;
esac
