#!/usr/bin/env bash
# =============================================================================
#  ENUM QUEST — deploy to one or more teams from the Salt master (admin Kali)
#
#  Minion naming (confirmed on range):
#    linux-ocig-kaliN
#    linux-ocig-ubuntuN
#    win-ocig-19srvN
#
#  Usage (run on admin Kali as a sudo-capable user):
#    cd /srv/salt/F26_enum_lab
#    sudo bash deploy_enum_quest.sh 1 2 3          # specific teams
#    sudo bash deploy_enum_quest.sh --all-known    # every N found in salt-key
#    sudo bash deploy_enum_quest.sh --dry-run 4 5  # print commands only
#
#  Order per team: Ubuntu → Windows → Kali jumpbox
# =============================================================================
set -euo pipefail

LAB_SRC="${LAB_SRC:-/srv/salt/F26_enum_lab}"
DRY=0
TEAMS=()

usage() {
  echo "usage: $0 [--dry-run] [--all-known] TEAM_NUM [TEAM_NUM...]"
  echo "  example: $0 1 2 5 30"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --all-known)
      mapfile -t TEAMS < <(sudo salt-key -l accepted 2>/dev/null | grep -oE 'linux-ocig-kali[0-9]+' | grep -oE '[0-9]+$' | sort -n | uniq)
      shift
      ;;
    -h|--help) usage ;;
    *) TEAMS+=("$1"); shift ;;
  esac
done

[[ ${#TEAMS[@]} -gt 0 ]] || usage
[[ -d "$LAB_SRC" ]] || { echo "Lab folder missing: $LAB_SRC"; exit 1; }
[[ -f "$LAB_SRC/setup_ubuntu_target.sh" ]] || { echo "setup scripts missing in $LAB_SRC — git pull?"; exit 1; }

run() {
  if (( DRY )); then
    echo "DRY: $*"
  else
    echo "+ $*"
    eval "$@"
  fi
}

deploy_team() {
  local n="$1"
  local kali="linux-ocig-kali${n}"
  local ubuntu="linux-ocig-ubuntu${n}"
  local win="win-ocig-19srv${n}"
  local player="ocig${n}"

  echo "============================================================"
  echo " TEAM $n"
  echo "   $ubuntu  →  $win  →  $kali (user $player)"
  echo "============================================================"

  # --- ping check ---
  for m in "$ubuntu" "$win" "$kali"; do
    if ! sudo salt "$m" test.ping --out=raw 2>/dev/null | grep -q True; then
      echo "WARN: $m did not respond to test.ping — skipping team $n"
      return 0
    fi
  done

  # --- Ubuntu ---
  echo "[team $n] Ubuntu target..."
  run "sudo salt '$ubuntu' cmd.run 'mkdir -p /opt/enum_lab'"
  run "sudo salt-cp '$ubuntu' '$LAB_SRC/setup_ubuntu_target.sh' /opt/enum_lab/setup_ubuntu_target.sh"
  run "sudo salt '$ubuntu' cmd.run 'chmod +x /opt/enum_lab/setup_ubuntu_target.sh && bash /opt/enum_lab/setup_ubuntu_target.sh --no-switch'"

  # --- Windows ---
  echo "[team $n] Windows target..."
  run "sudo salt '$win' cmd.run 'if (-not (Test-Path C:\\enum_lab)) { New-Item -ItemType Directory -Path C:\\enum_lab | Out-Null }; Write-Output ok' shell=powershell"
  run "sudo salt-cp '$win' '$LAB_SRC/setup_win_target.ps1' 'C:\\enum_lab\\setup_win_target.ps1'"
  run "sudo salt '$win' cmd.run 'powershell -ExecutionPolicy Bypass -File C:\\enum_lab\\setup_win_target.ps1' shell=powershell"

  # --- Kali jumpbox ---
  echo "[team $n] Kali jumpbox..."
  run "sudo salt '$kali' cmd.run 'mkdir -p /opt/enum_lab/wordlists'"
  run "sudo salt-cp '$kali' '$LAB_SRC/setup_jumpbox.sh' /opt/enum_lab/setup_jumpbox.sh"
  run "sudo salt-cp '$kali' '$LAB_SRC/enum_quest.sh' /opt/enum_lab/enum_quest.sh"
  run "sudo salt-cp '$kali' '$LAB_SRC/wordlists/common.txt' /opt/enum_lab/wordlists/common.txt"
  run "sudo salt '$kali' cmd.run 'chmod +x /opt/enum_lab/*.sh && bash /opt/enum_lab/setup_jumpbox.sh --no-switch --user $player'"

  echo "[team $n] DONE"
}

for t in "${TEAMS[@]}"; do
  [[ "$t" =~ ^[0-9]+$ ]] || { echo "Not a team number: $t"; exit 1; }
  deploy_team "$t"
done

echo "All requested teams finished."
