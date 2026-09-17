#!/usr/bin/env bash
# =============================================================================
#  LINUX QUEST — bonus_setup.sh   (run as root, Ubuntu 22.04 / 24.04)
#
#  Plants the artifacts for the optional bonus mission "THE GHOST".
#  Run AFTER the core setup.sh on the same machine.
#
#    sudo ./bonus_setup.sh            install + plant everything
#    sudo ./bonus_setup.sh --state    re-plant artifacts only (game's `reset`)
#    sudo ./bonus_setup.sh --spawn <timer|kthread|beacon|all>
#                                     restart one live artifact (called by the
#                                     game when a reboot has killed it)
#    sudo ./bonus_setup.sh --check    print what is currently in place
#
#  Idempotent. Touches nothing owned by missions 1-3.
#
#  The final flag can be overridden per machine:
#    LQ_BONUS_FLAG='FLAG{...}' sudo -E ./bonus_setup.sh
#
#  Artifacts (all under the bonus's own namespace):
#    /opt/.sysmon/{collect.sh,kthread,beacon}   scripts
#    /etc/systemd/system/man-db-cache.{service,timer}
#    /usr/local/sbin/logrotate                  PATH-shadowing wrapper
#    /etc/.ghostrc                              immutable config (chattr +i)
#    /var/tmp/.sysmon.cache                     copy of the layered blob
#    /usr/bin/systemd-helper                    SUID copy of base64 (or xxd)
#    /root/.ghost/note                          root-only, holds fragment 7
#    /root/.ssh/authorized_keys                 backdoor key, fragment 8 in comment
#    /var/log/nginx/access.log                  ~4000 planted lines, 7 exfil
#    /var/www/html/assets/.data/x9f2.bin        fragment 9
#    /etc/linux-quest/bonus_fragments           answer key, root-only (600)
# =============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }

MODE="${1:-install}"
CFG=/etc/linux-quest
LIB=/usr/local/lib/linux-quest
SYS=/opt/.sysmon
FRAGFILE="$CFG/bonus_fragments"
SELF="$(readlink -f "$0")"
GAME_SRC="$(dirname "$SELF")/linux_quest_bonus.sh"
FINAL_FLAG="${LQ_BONUS_FLAG:-FLAG{the_ghost_never_left}}"
KWORKER_NAME=""          # decided by preflight
SUID_DONOR=""            # decided by preflight
EXFIL_PATH="/assets/.data/x9f2.bin"
EXFIL_UA="sysmon-agent/1.4"
GHOST_DOMAIN="telemetry.ghostmail.example"

log()  { echo "[bonus] $*"; }
warn() { echo "[bonus] WARNING: $*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
systemd_up() { [[ -d /run/systemd/system ]] && have systemctl; }

# ---------------------------------------------------------------------------
# Fragments
# ---------------------------------------------------------------------------
# The flag is base64'd and split into 9 chunks; chunk i is planted in stage i.
# The answer key lives in $FRAGFILE (mode 600) so the game binary contains no
# answers and a student cannot grep them out of it.
build_fragments() {
  local b64 len n=9 base rem i off take chunk
  b64=$(printf '%s' "$FINAL_FLAG" | base64 -w0)
  len=${#b64}; base=$(( len / n )); rem=$(( len % n )); off=0
  install -d -m 755 "$CFG"
  : > "$FRAGFILE"; chmod 600 "$FRAGFILE"
  for (( i = 1; i <= n; i++ )); do
    take=$base; (( i <= rem )) && take=$(( base + 1 ))
    chunk=${b64:off:take}; off=$(( off + take ))
    echo "GHOST-$i:$chunk" >> "$FRAGFILE"
  done
  {
    echo "FINAL:$FINAL_FLAG"
    echo "EXFIL_PATH:$EXFIL_PATH"
    echo "EXFIL_UA:$EXFIL_UA"
    echo "DOMAIN:$GHOST_DOMAIN"
  } >> "$FRAGFILE"
}
frag() { grep "^GHOST-$1:" "$FRAGFILE" | head -1; }   # full "GHOST-n:chunk"

# ---------------------------------------------------------------------------
# Preflight: verify the platform assumptions this mission depends on
# ---------------------------------------------------------------------------
preflight() {
  local t rc=0

  # 1. chattr +i support (stage 4)
  t=$(mktemp /etc/.lqtest.XXXX)
  if chattr +i "$t" 2>/dev/null; then
    chattr -i "$t"; rm -f "$t"; rm -f "$CFG/bonus_nochattr"
  else
    rm -f "$t"; touch "$CFG/bonus_nochattr"
    warn "this filesystem does not support chattr +i; stage 4 runs without the immutable flag"
  fi

  # 2. a standalone (non multi-call) binary to use for the SUID stage
  for t in base64 xxd cat; do
    have "$t" || continue
    cp "$(command -v "$t")" /tmp/.lqdonor 2>/dev/null || continue
    chmod 755 /tmp/.lqdonor
    case "$t" in
      base64) [[ "$(printf x | /tmp/.lqdonor 2>/dev/null)" == "eA==" ]] && SUID_DONOR=base64 ;;
      xxd)    [[ "$(printf x | /tmp/.lqdonor -p 2>/dev/null)" == "78" ]] && SUID_DONOR=xxd ;;
      cat)    [[ "$(printf x | /tmp/.lqdonor 2>/dev/null)" == "x" ]] && SUID_DONOR=cat ;;
    esac
    rm -f /tmp/.lqdonor
    [[ -n "$SUID_DONOR" ]] && break
  done
  if [[ -z "$SUID_DONOR" ]]; then
    warn "no standalone donor binary found (multi-call coreutils?); stage 7 will use a shell wrapper"
    SUID_DONOR=wrapper
  fi

  # 3. a kernel-worker name that is not already taken. Stop our own instance
  #    first so a previous run's process does not make the name look occupied,
  #    and reuse the name we chose last time when it is still free.
  if [[ -s "$CFG/bonus_kworker" ]]; then kthread_stop_all; sleep 0.2; fi
  KWORKER_NAME=""
  for t in "$(cat "$CFG/bonus_kworker" 2>/dev/null)" "[kworker/2:1H]" "[kworker/3:2H]" "[kworker/5:1H]" "[kworker/7:2H]"; do
    [[ -n "$t" ]] || continue
    if ! ps -eo args | grep -qF "$t"; then KWORKER_NAME="$t"; break; fi
  done
  [[ -n "$KWORKER_NAME" ]] || KWORKER_NAME="[kworker/9:3H]"

  # 4. the layered blob must round-trip
  local blob out
  blob=$(make_blob "$(frag 5)")
  out=$(unmake_blob "$blob")
  if [[ "$out" != "$(frag 5)" ]]; then
    echo "[bonus] FATAL: layered blob does not round-trip on this machine" >&2; rc=1
  fi

  echo "$KWORKER_NAME" > "$CFG/bonus_kworker"; chmod 644 "$CFG/bonus_kworker"
  echo "$SUID_DONOR"   > "$CFG/bonus_donor";   chmod 644 "$CFG/bonus_donor"
  return $rc
}

# ROT13( reverse( base64( gzip( text ) ) ) )   -- gzip -n keeps it deterministic
make_blob()   { printf '%s' "$1" | gzip -nc | base64 -w0 | rev | tr 'A-Za-z' 'N-ZA-Mn-za-m'; }
unmake_blob() { printf '%s' "$1" | tr 'A-Za-z' 'N-ZA-Mn-za-m' | rev | base64 -d 2>/dev/null | gunzip 2>/dev/null; }

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------
install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  local want=() p
  for p in logrotate e2fsprogs binutils openssh-client; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || want+=("$p")
  done
  if (( ${#want[@]} )); then
    log "installing: ${want[*]}"
    apt-get update -qq || true
    apt-get install -y -qq "${want[@]}" >/dev/null || warn "some packages failed to install"
  fi
}

install_game() {
  install -d -m 755 "$LIB" "$CFG"
  # root-only: this file contains the flag and every planted answer
  cp "$SELF" "$LIB/bonus_setup.sh"; chown root:root "$LIB/bonus_setup.sh"; chmod 700 "$LIB/bonus_setup.sh"
  if [[ -f "$GAME_SRC" ]]; then
    install -m 755 "$GAME_SRC" /usr/local/bin/linux-quest-bonus
    log "installed /usr/local/bin/linux-quest-bonus"
  else
    warn "linux_quest_bonus.sh not found next to this script; game binary not installed"
  fi
}

# ---------------------------------------------------------------------------
# Stage 1 — systemd timer persistence
# ---------------------------------------------------------------------------
plant_timer() {
  install -d -m 755 "$SYS"
  cat > "$SYS/collect.sh" <<EOF
#!/usr/bin/env bash
# system metrics collector
# $(frag 1)
getent hosts $GHOST_DOMAIN >/dev/null 2>&1
date +"%F %T collect" >> /var/tmp/.sysmon.log
EOF
  chmod 755 "$SYS/collect.sh"

  cat > /etc/systemd/system/man-db-cache.service <<EOF
[Unit]
Description=Daily man-db cache update

[Service]
Type=oneshot
ExecStart=$SYS/collect.sh
EOF
  cat > /etc/systemd/system/man-db-cache.timer <<'EOF'
[Unit]
Description=Daily man-db cache update

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF
  if systemd_up; then
    systemctl daemon-reload
    systemctl enable --now man-db-cache.timer >/dev/null 2>&1 || warn "could not enable man-db-cache.timer"
  else
    warn "systemd is not running; stage 1 will not be solvable on this machine"
  fi
}

# ---------------------------------------------------------------------------
# Stage 2 — PATH-shadowing wrapper
# ---------------------------------------------------------------------------
plant_pathhijack() {
  local real=/usr/sbin/logrotate
  [[ -x $real ]] || { warn "logrotate not installed; stage 2 wrapper still planted"; }
  install -d -m 755 /usr/local/sbin
  cat > /usr/local/sbin/logrotate <<EOF
#!/usr/bin/env bash
# $(frag 2)
[[ -x $real ]] && exec $real "\$@"
exit 0
EOF
  chmod 755 /usr/local/sbin/logrotate
}

# ---------------------------------------------------------------------------
# Stage 3 — process masquerading as a kernel thread
# ---------------------------------------------------------------------------
plant_kthread_file() {
  install -d -m 755 "$SYS"
  cat > "$SYS/kthread" <<'EOF'
#!/usr/bin/env bash
while true; do sleep 60; done
EOF
  chmod 755 "$SYS/kthread"
}
# The masquerading process's command line is only the fake name, so it cannot be
# found with pgrep -f "$SYS/kthread"; and the name contains [] which pgrep/pkill
# would read as a regex character class. Always match it with grep -F on ps.
kthread_name() { cat "$CFG/bonus_kworker" 2>/dev/null || echo "[kworker/2:1H]"; }
kthread_pid() {
  ps -eo pid,args | grep -F -- "$(kthread_name)" | grep -v grep | awk '{print $1}' | head -1
}
kthread_stop_all() {
  local p
  for p in $(ps -eo pid,args | grep -F -- "$(kthread_name)" | grep -v grep | awk '{print $1}'); do
    kill "$p" 2>/dev/null || true
  done
}
spawn_kthread() {
  local name; name=$(kthread_name)
  kthread_stop_all
  # bash reads the loop from stdin, so the command line is just the fake name
  GHOST_KEY="$(frag 3)" setsid nohup bash -c "exec -a \"$name\" bash" < "$SYS/kthread" \
    >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Stage 6 — running program whose file was deleted
# ---------------------------------------------------------------------------
spawn_beacon() {
  pkill -f "$SYS/beacon" 2>/dev/null || true
  install -d -m 755 "$SYS"
  cat > "$SYS/beacon" <<EOF
#!/usr/bin/env bash
# $(frag 6)
# beacon: phones home to $GHOST_DOMAIN
while true; do
  date +"%F %T beacon" >> /var/tmp/.beacon2.log
  sleep 300
done
EOF
  chmod 755 "$SYS/beacon"
  setsid nohup "$SYS/beacon" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
  sleep 0.5
  rm -f "$SYS/beacon"          # the file is gone; the process keeps fd 255 open
}

# ---------------------------------------------------------------------------
# Stages 4 and 5 — immutable config holding the layered blob
# ---------------------------------------------------------------------------
plant_ghostrc() {
  local blob; blob=$(make_blob "$(frag 5)")
  chattr -i /etc/.ghostrc 2>/dev/null || true
  cat > /etc/.ghostrc <<EOF
# sysmon runtime config - do not edit
# $(frag 4)
endpoint=$GHOST_DOMAIN
interval=900
key=$blob
EOF
  chmod 644 /etc/.ghostrc
  # a runtime cache of the same value, so a student who deletes the config
  # before reading it is not stuck
  printf 'key=%s\n' "$blob" > /var/tmp/.sysmon.cache
  chmod 644 /var/tmp/.sysmon.cache
  [[ -e "$CFG/bonus_nochattr" ]] || chattr +i /etc/.ghostrc 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Stage 7 — SUID copy of an ordinary tool + root-only note
# ---------------------------------------------------------------------------
plant_suid() {
  local donor; donor=$(cat "$CFG/bonus_donor" 2>/dev/null || echo base64)
  install -d -m 700 /root/.ghost
  printf '%s\n' "$(frag 7)" > /root/.ghost/note
  chmod 600 /root/.ghost/note

  rm -f /usr/bin/systemd-helper
  if [[ "$donor" == "wrapper" ]]; then
    # last resort: a tiny setuid-root wrapper is not possible without a compiler,
    # so fall back to a root-readable copy of the note guarded by group access
    warn "no standalone donor; stage 7 falls back to a group-readable note"
    install -d -m 755 /usr/local/share/ghost
    cp /root/.ghost/note /usr/local/share/ghost/note
    chmod 640 /usr/local/share/ghost/note
    return
  fi
  cp "$(command -v "$donor")" /usr/bin/systemd-helper
  chown root:root /usr/bin/systemd-helper
  chmod 4755 /usr/bin/systemd-helper
}

# ---------------------------------------------------------------------------
# Stage 8 — backdoor SSH key with the fragment in its comment
# ---------------------------------------------------------------------------
plant_authkeys() {
  local tmp pub_backdoor pub_legit
  install -d -m 700 /root/.ssh
  tmp=$(mktemp -d)
  if have ssh-keygen; then
    ssh-keygen -t ed25519 -N '' -q -C "$(frag 8)"        -f "$tmp/bd"   </dev/null
    ssh-keygen -t ed25519 -N '' -q -C "webadmin@vault"   -f "$tmp/ok"   </dev/null
    pub_backdoor=$(cat "$tmp/bd.pub"); pub_legit=$(cat "$tmp/ok.pub")
  else
    warn "ssh-keygen missing; using static key material"
    pub_backdoor="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH3Qk9m0nJ2v8ZrTf1uYl6xW4bK7cD0pR5sN9eA2gVtM $(frag 8)"
    pub_legit="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKp2Vv7dQ8mXr4tL1nB6cY0jZ3fH5sW9uE8aG2kR7xPq webadmin@vault"
  fi
  printf '%s\n%s\n' "$pub_legit" "$pub_backdoor" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  chown root:root /root/.ssh/authorized_keys
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# Stage 9 — a large, realistic nginx access log with 7 exfil requests
# ---------------------------------------------------------------------------
plant_weblog() {
  local logdir=/var/log/nginx
  local log=$logdir/access.log
  install -d -m 755 "$logdir"
  [[ -f $log ]] || : > "$log"

  if grep -qF "$EXFIL_UA" "$log" 2>/dev/null; then
    :   # already planted
  else
    awk -v ua="$EXFIL_UA" -v xp="$EXFIL_PATH" 'BEGIN{
      split("GET /|GET /index.html|GET /favicon.ico|GET /assets/style.css|GET /assets/app.js|GET /assets/logo.png|GET /about|GET /contact|GET /robots.txt", paths, "|");
      split("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36|Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15|Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0|Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148|curl/8.5.0", uas, "|");
      split("200|200|200|200|304|404", codes, "|");
      d=1; h=0; m=0; s=0;
      for (i = 1; i <= 4000; i++) {
        s += 7; if (s >= 60) { s -= 60; m++ } if (m >= 60) { m -= 60; h++ } if (h >= 24) { h -= 24; d++ }
        ip = sprintf("%d.%d.%d.%d", 10 + (i % 7), (i * 13) % 254, (i * 7) % 254, 1 + (i % 250));
        p = paths[1 + (i % 9)]; u = uas[1 + (i % 5)]; c = codes[1 + (i % 6)];
        b = 200 + (i * 37) % 9000;
        printf "%s - - [%02d/Sep/2026:%02d:%02d:%02d +0000] \"%s HTTP/1.1\" %s %d \"-\" \"%s\"\n",
               ip, d, h, m, s, p, c, b, u;
        if (i % 570 == 0 && exf < 7) {
          exf++;
          printf "%s - - [%02d/Sep/2026:%02d:%02d:%02d +0000] \"GET %s HTTP/1.1\" 200 %d \"-\" \"%s\"\n",
                 "198.51.100.77", d, h, m, s + 1, xp, 1048576 + exf * 1024, ua;
        }
      }
    }' >> "$log"
    chown root:adm "$log" 2>/dev/null || true
    chmod 640 "$log"
  fi

  install -d -m 755 /var/www/html/assets/.data
  printf '%s\n' "$(frag 9)" > /var/www/html/assets/.data/x9f2.bin
  chmod 644 /var/www/html/assets/.data/x9f2.bin
}

# ---------------------------------------------------------------------------
plant_all() {
  plant_timer
  plant_pathhijack
  plant_kthread_file; spawn_kthread
  plant_ghostrc
  spawn_beacon
  plant_suid
  plant_authkeys
  plant_weblog
  rm -f /var/tmp/.beacon2.log /var/tmp/.sysmon.log
}

show_check() {
  local name; name=$(cat "$CFG/bonus_kworker" 2>/dev/null || echo '?')
  echo "fragments file : $( [[ -s $FRAGFILE ]] && echo present || echo MISSING )"
  echo "timer          : $(systemctl is-active man-db-cache.timer 2>/dev/null || echo 'n/a') / $(systemctl is-enabled man-db-cache.timer 2>/dev/null || echo 'n/a')"
  echo "path wrapper   : $( [[ -x /usr/local/sbin/logrotate ]] && echo present || echo MISSING )"
  echo "fake kthread   : $( [[ -n "$(kthread_pid)" ]] && echo "running as $name" || echo STOPPED)"
  echo "ghostrc        : $( [[ -e /etc/.ghostrc ]] && echo "present ($(lsattr /etc/.ghostrc 2>/dev/null | awk '{print $1}'))" || echo 'deleted (stage 4 done)' )"
  echo "beacon         : $(pgrep -f "$SYS/beacon" >/dev/null && echo running || echo STOPPED)"
  echo "suid helper    : $( [[ -u /usr/bin/systemd-helper ]] && echo present || echo MISSING )"
  echo "authorized_keys: $( [[ -s /root/.ssh/authorized_keys ]] && echo present || echo MISSING )"
  echo "web log        : $(grep -cF "$EXFIL_UA" /var/log/nginx/access.log 2>/dev/null || echo 0) exfil lines"
  echo "exfil file     : $( [[ -f /var/www/html/assets/.data/x9f2.bin ]] && echo present || echo MISSING )"
}

# ---------------------------------------------------------------------------
case "$MODE" in
  install|--install)
    install_packages
    build_fragments
    preflight || exit 1
    install_game
    plant_all
    log "bonus mission planted. Final flag: $FINAL_FLAG"
    log "students reach it by typing 'bonus' at the end of mission 3."
    ;;
  --state|state)
    [[ -s "$FRAGFILE" ]] || build_fragments
    preflight || exit 1
    plant_all
    log "bonus artifacts rebuilt"
    ;;
  --spawn)
    case "${2:-all}" in
      timer)   systemd_up && systemctl enable --now man-db-cache.timer >/dev/null 2>&1 ;;
      kthread) spawn_kthread ;;
      beacon)  spawn_beacon ;;
      all)     systemd_up && systemctl enable --now man-db-cache.timer >/dev/null 2>&1
               spawn_kthread; spawn_beacon ;;
      *) echo "usage: $0 --spawn <timer|kthread|beacon|all>"; exit 1 ;;
    esac
    ;;
  --check) show_check ;;
  *) echo "usage: $0 [--install | --state | --spawn <what> | --check]"; exit 1 ;;
esac
