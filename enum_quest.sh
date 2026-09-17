#!/usr/bin/env bash
# =============================================================================
#  ENUM QUEST  — interactive recon lab for DCIG
#
#  Run as your login user on a Kali jumpbox prepared by setup_jumpbox.sh
#  (e.g. ocig1, ocig2, … — no separate student account):
#
#      enum-quest                 start / resume
#      enum-quest --reset         clear progress and restart
#      enum-quest --verify CODE   check a score code (mentors)
#
#  Missions: NETWORK → SERVICES → USERS → SHARES → WEB → DNS
#  Players type real commands; most levels need:  answer <value>
# =============================================================================

set -o pipefail

LIB=/usr/local/lib/enum-quest
CFG=/etc/enum-quest
ANSWERS="$CFG/answers"
TARGETS="$CFG/targets.conf"
H="$HOME"
STATE="$H/.enum-quest"
PROGRESS="$STATE/progress"; SCOREFILE="$STATE/score"; NAMEFILE="$STATE/name"
HISTFILE="$STATE/history"; MARK="$STATE/level_marker"
SHOW_SCORE_CODE=${SHOW_SCORE_CODE:-0}

# ---------- helpers ----------------------------------------------------------
if [[ -t 1 ]]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; M=$'\e[35m'; C=$'\e[36m'
  BOLD=$'\e[1m'; DIM=$'\e[2m'; N=$'\e[0m'
else R= G= Y= M= C= BOLD= DIM= N=; fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✔ %s%s\n' "$G" "$*" "$N"; }
warn() { printf '%s! %s%s\n' "$Y" "$*" "$N"; }
err()  { printf '%s✘ %s%s\n' "$R" "$*" "$N"; }
line() { printf '%s%s%s\n' "$DIM" "──────────────────────────────────────────────────────────────────" "$N"; }
norm() { tr '[:upper:]' '[:lower:]' <<<"$1" | tr -d '[:space:]'; }

ans() {
  # read KEY from /etc/enum-quest/answers
  local k="$1" v
  [[ -f "$ANSWERS" ]] || { echo ""; return 1; }
  v=$(awk -F= -v k="$k" '$1==k {print substr($0,index($0,"=")+1); exit}' "$ANSWERS")
  printf '%s' "$v"
}
ans_norm() { norm "$(ans "$1")"; }
match_ans() {
  local key="$1" got; got=$(norm "$2")
  local want; want=$(ans_norm "$key")
  [[ -n "$want" && "$got" == "$want" ]]
}
# Accept several aliases for service names
match_any() {
  local got; got=$(norm "$1"); shift
  local a
  for a in "$@"; do [[ "$got" == "$(norm "$a")" ]] && return 0; done
  return 1
}

# =============================================================================
#  MISSIONS
# =============================================================================
M_NAME=(); M_TAG=(); M_STORY=(); M_OBJ=()
add_mission() { M_NAME+=("$1"); M_TAG+=("$2"); M_STORY+=("$3"); M_OBJ+=("$4"); }

add_mission "NETWORK" "M1" \
"You have a jumpbox and a briefing. Two hosts live on the lab network: a Linux
web box and a Windows server. Before you poke services, prove what is alive and
which TCP ports are open. nmap is your friend." \
"Read the briefing and know your two targets
Resolve hostnames / IPs from the briefing
Discover open ports on both hosts with nmap"

add_mission "SERVICES" "M2" \
"Open ports are only half the picture. Identify the products behind them —
web servers, SSH, SMB, DNS — so later missions know which tool to use." \
"Fingerprint HTTP on Linux and Windows
Confirm SSH, DNS, FTP, and SMB service names
Practice nmap version detection (-sV)"

add_mission "USERS" "M3" \
"Accounts leak through SMB and shared files. Pull usernames from the Windows
box (enum4linux if null sessions work, or the Public share staff list) and from
Samba on Linux." \
"Enumerate Windows local accounts (svc_backup, intern)
Enumerate Linux Samba users (webadmin, deploy)
Use enum4linux, smbclient, and/or nmap scripts"

add_mission "SHARES" "M4" \
"File services often expose more than SMB. Start with anonymous FTP on Linux,
then move to SMB shares on both Windows and Linux." \
"Check FTP (port 21) and pull the anonymous flag
List Windows shares including a hidden IT$ share
Read the Public share flag
Find the Linux teamfiles share and its flag"

add_mission "WEB" "M5" \
"Both hosts speak HTTP. Use curl for robots.txt and pages, then ffuf to find
directories that are not linked from the homepage." \
"Read robots.txt on the Linux site
Fetch admin / backup content and flags
Find the IIS /secret path and its flag"

add_mission "DNS" "M6" \
"Finish with name-service intel. Query the lab domain, pull MX/TXT/A records,
and attempt a zone transfer against the Linux DNS server." \
"Identify the lab domain
Query MX and A records
Complete an AXFR and capture the TXT flag"

# =============================================================================
#  LEVELS     add_level <mission#> <title> <task> <why> <auto|answer> "h1|h2|h3"
# =============================================================================
L_M=(); L_TITLE=(); L_TASK=(); L_WHY=(); L_TYPE=(); L_HINTS=()
add_level() { L_M+=("$1"); L_TITLE+=("$2"); L_TASK+=("$3"); L_WHY+=("$4"); L_TYPE+=("$5"); L_HINTS+=("$6"); }

# ---------------- M1 NETWORK ----------------
add_level 1 "Read the briefing" \
"Read ~/briefing.txt and submit the briefing codeword.  answer <codeword>" \
"Every engagement starts with the scope you were given." \
answer "cat prints a file.|cat ~/briefing.txt|cat briefing.txt ; answer OSPREY"

add_level 1 "How many targets?" \
"How many systems are you supposed to enumerate?  answer <number>" \
"Scope discipline: know the count before you scan the world." \
answer "It is in the briefing under Targets.|Count the Linux + Windows lines.|answer 2"

add_level 1 "Linux hostname" \
"What is the hostname of the Linux target?  answer <hostname>" \
"Hostnames beat raw IPs when writing notes." \
answer "Check briefing.txt or /etc/enum-quest/targets.conf|Look for vault-web.|answer vault-web"

add_level 1 "Windows hostname" \
"What is the hostname of the Windows target?  answer <hostname>" \
"Same idea — name the Windows box." \
answer "Briefing or targets.conf.|vault-dc is the Windows host.|answer vault-dc"

add_level 1 "Linux IP" \
"What is the IPv4 address of the Linux target?  answer <ip>" \
"You will feed this to nmap constantly." \
answer "targets.conf has UBUNTU_IP=…|Or ping vault-web.|answer 192.168.1.10"

add_level 1 "Windows IP" \
"What is the IPv4 address of the Windows target?  answer <ip>" \
"Keep both IPs in your notes folder." \
answer "WIN_IP in targets.conf.|ping vault-dc.|answer 192.168.1.11"

add_level 1 "SSH port" \
"Which TCP port is SSH listening on (Linux target)? Confirm with nmap.  answer <port>" \
"Default ports matter; always verify." \
answer "nmap -p- or nmap vault-web|SSH is almost always 22.|nmap -p 22 vault-web ; answer 22"

add_level 1 "RDP port" \
"Which TCP port is RDP on the Windows target?  answer <port>" \
"RDP is a classic Windows footprint." \
answer "nmap vault-dc -p 3389|Remote Desktop uses 3389.|answer 3389"

add_level 1 "SMB port" \
"Which TCP port do both hosts use for SMB file sharing?  answer <port>" \
"Shares missions will hit this port." \
answer "SMB over TCP is 445.|nmap -p 445 vault-web vault-dc|answer 445"

add_level 1 "FTP port" \
"Which TCP port is FTP on the Linux target? Confirm with nmap.  answer <port>" \
"FTP is older than SMB but still common on internal hosts." \
answer "nmap -p 21 vault-web|FTP control channel is 21.|answer 21"

add_level 1 "Linux open ports" \
"Submit the Linux target's key open TCP ports as a sorted comma-separated list
with no spaces (ftp,ssh,dns,http,netbios-ssn,microsoft-ds).  answer <list>" \
"A clean port list is the start of your attack surface notes." \
answer "nmap -sT vault-web  (or -F)|Expect 21,22,53,80,139,445|answer 21,22,53,80,139,445"

# ---------------- M2 SERVICES ----------------
add_level 2 "Linux web product" \
"What web server product is on the Linux host port 80?  answer <product>" \
"curl -I or nmap -sV will tell you." \
answer "nmap -sV -p 80 vault-web|Or curl -I http://vault-web|answer nginx"

add_level 2 "Windows web product" \
"What web server family is on the Windows host port 80?  answer <iis|microsoft>" \
"Look at Server headers or nmap -sV." \
answer "nmap -sV -p 80 vault-dc|curl -I http://vault-dc|answer iis"

add_level 2 "SSH product" \
"What SSH product is on the Linux host?  answer <product>" \
"Version detection beats guessing." \
answer "nmap -sV -p 22 vault-web|OpenSSH shows in the banner.|answer openssh"

add_level 2 "DNS service name" \
"nmap often labels port 53 as which service name?  answer <name>" \
"Know the short service name in scan output." \
answer "nmap -p 53 vault-web|Service column says domain.|answer domain"

add_level 2 "SMB service name" \
"nmap often labels port 445 as which service name?  answer <name>" \
"You will grep for this later." \
answer "nmap -p 445 vault-dc|Look for microsoft-ds.|answer microsoft-ds"

add_level 2 "FTP service name" \
"nmap usually labels port 21 as which service name?  answer <name>" \
"You will use the ftp client next mission." \
answer "nmap -p 21 vault-web|Service column says ftp.|answer ftp"

add_level 2 "HTTP port" \
"Both sites listen for plain HTTP on which TCP port?  answer <port>" \
"Later curl/ffuf URLs need the right port." \
answer "Default HTTP is 80.|answer 80"

add_level 2 "DNS port" \
"DNS usually listens on which UDP/TCP port?  answer <port>" \
"Mission 6 will query this port." \
answer "DNS is 53.|answer 53"

# ---------------- M3 USERS ----------------
add_level 3 "Windows service account" \
"Find the backup-related local username on the Windows target.  answer <username>" \
"Try enum4linux -U. If null sessions are blocked, read Public\\staff.txt over SMB." \
answer "enum4linux -U vault-dc|Or: smbclient //vault-dc/Public -N then get staff.txt|answer svc_backup"

add_level 3 "Windows intern" \
"What is the other non-admin lab username on Windows (hint: temporary staff)?  answer <username>" \
"Same sources as the previous level (enum4linux or Public/staff.txt)." \
answer "Look for intern in the user list or staff.txt.|smbclient //vault-dc/Public -N|answer intern"

add_level 3 "Linux web user" \
"Which Samba/Unix username on the Linux target looks like a web admin?  answer <username>" \
"enum4linux against vault-web or smbclient." \
answer "enum4linux -U vault-web|Look for webadmin.|answer webadmin"

add_level 3 "Linux deploy user" \
"Which Linux Samba username looks like an automation/deploy account?  answer <username>" \
"Same enum as before." \
answer "enum4linux -U vault-web|deploy is the bot account.|answer deploy"

add_level 3 "Tool check" \
"Name one tool you used (or can use) for SMB user enum from Linux.
Acceptable: enum4linux, enum4linux-ng, smbclient, rpcclient, nmap.  answer <tool>" \
"Knowing your toolkit matters as much as the finding." \
answer "Any of: enum4linux, smbclient, rpcclient, nmap|answer enum4linux"

# ---------------- M4 SHARES (FTP first, then SMB) ----------------
add_level 4 "FTP port confirm" \
"Re-confirm: FTP on the Linux target uses which TCP port?  answer <port>" \
"File-service enum often starts with the oldest protocol still listening." \
answer "nmap -p 21 vault-web|answer 21"

add_level 4 "Anonymous FTP" \
"Does the Linux FTP server allow anonymous login?  answer <yes|no>" \
"Try: ftp vault-web   (user anonymous, password empty or email)." \
answer "ftp vault-web|login anonymous|answer yes"

add_level 4 "FTP flag file" \
"What is the name of the flag file under the anonymous FTP pub folder?  answer <filename>" \
"After login: cd pub ; ls" \
answer "ftp> cd pub ; ls|Look for flag.txt|answer flag.txt"

add_level 4 "FTP flag" \
"Download that file and submit the FLAG{…}.  answer <flag>" \
"ftp get flag.txt, then cat it locally." \
answer "get flag.txt ; quit ; cat flag.txt|answer FLAG{ftp_anon_loot}"

add_level 4 "Public share" \
"What is the readable Windows share meant for everyone?  answer <name>" \
"smbclient -L //vault-dc -N" \
answer "smbclient -L //vault-dc -N|Look for Public.|answer Public"

add_level 4 "Finance share" \
"Which Windows share name looks finance-related (likely restricted)?  answer <name>" \
"Listing shares does not mean you can read them." \
answer "Same smbclient -L output.|answer Finance"

add_level 4 "Hidden share" \
"What is the hidden IT administrative share name (include the dollar sign)?  answer <name>" \
"Trailing \$ hides shares from casual browsing — still listable sometimes." \
answer "Look for IT\$|answer IT$"

add_level 4 "Public flag" \
"Read a file from the Public share and submit the FLAG{…}.  answer <flag>" \
"smbclient //vault-dc/Public -N  then get welcome.txt" \
answer "smbclient //vault-dc/Public -N|get welcome.txt ; cat welcome.txt|answer FLAG{smb_public_read}"

add_level 4 "Linux share name" \
"What is the Samba share name on the Linux target?  answer <name>" \
"smbclient -L //vault-web -N" \
answer "smbclient -L //vault-web -N|answer teamfiles"

add_level 4 "Linux share flag" \
"Read the flag from the Linux share.  answer <flag>" \
"smbclient //vault-web/teamfiles -N and get loot.txt" \
answer "smbclient //vault-web/teamfiles -N|get loot.txt|answer FLAG{linux_share_loot}"

# ---------------- M5 WEB ----------------
add_level 5 "robots admin path" \
"On the Linux site, which path does robots.txt disallow first (admin)?  answer </path>" \
"curl http://vault-web/robots.txt" \
answer "curl http://vault-web/robots.txt|Disallow: /admin|answer /admin"

add_level 5 "robots backup path" \
"Second Disallow on the Linux robots.txt?  answer </path>" \
"Same file." \
answer "Disallow: /backup|answer /backup"

add_level 5 "Admin flag" \
"Fetch the Linux /admin page and submit its FLAG{…}.  answer <flag>" \
"curl http://vault-web/admin/" \
answer "curl http://vault-web/admin/|answer FLAG{web_admin_panel}"

add_level 5 "Backup flag" \
"Fetch the Linux backup notes and submit the FLAG{…}.  answer <flag>" \
"curl http://vault-web/backup/notes.txt" \
answer "curl http://vault-web/backup/notes.txt|answer FLAG{nginx_backup_note}"

add_level 5 "ffuf secret" \
"Use ffuf (wordlist ~/wordlists/common.txt) against http://vault-dc/ and find the
hidden directory named in Windows robots.txt. Submit that path.  answer </path>" \
"Directory brute force finds what links omit." \
answer "ffuf -u http://vault-dc/FUZZ -w ~/wordlists/common.txt|Or curl robots.txt on vault-dc|answer /secret"

add_level 5 "IIS secret flag" \
"Fetch the Windows secret page and submit FLAG{…}.  answer <flag>" \
"curl http://vault-dc/secret/" \
answer "curl http://vault-dc/secret/|answer FLAG{iis_secret_stash}"

# ---------------- M6 DNS ----------------
add_level 6 "Lab domain" \
"What is the lab DNS domain name?  answer <domain>" \
"Briefing, or dig against vault-web." \
answer "briefing.txt Domain line|targets.conf LAB_DOMAIN|answer vault.lab"

add_level 6 "MX host" \
"What is the MX mail hostname for the lab domain?  answer <hostname>" \
"dig MX vault.lab @vault-web" \
answer "dig MX vault.lab @vault-web|mail.vault.lab|answer mail.vault.lab"

add_level 6 "A record web" \
"What is the FQDN A-record name for the Linux web host in the zone?
Example style: vault-web.vault.lab  answer <fqdn>" \
"dig or zone transfer will show it." \
answer "dig A vault-web.vault.lab @vault-web|answer vault-web.vault.lab"

add_level 6 "Zone transfer flag" \
"Attempt a zone transfer from the Linux DNS server and submit the TXT FLAG{…}.
  answer <flag>" \
"dig AXFR vault.lab @vault-web" \
answer "dig AXFR vault.lab @vault-web|Find the TXT FLAG|answer FLAG{dns_zone_transfer}"

add_level 6 "A record DC" \
"What is the FQDN for the Windows host in the zone?  answer <fqdn>" \
"Same zone data." \
answer "vault-dc.vault.lab|answer vault-dc.vault.lab"

TOTAL=${#L_M[@]}

# =============================================================================
#  CHECKS  (level index is 1-based; argument $1 is the submitted answer)
# =============================================================================
check_1()  { match_ans BRIEFING_CODE "$1" || [[ "$(norm "$1")" == "osprey" ]]; }
check_2()  { match_ans TARGET_COUNT "$1"; }
check_3()  { match_ans UBUNTU_HOST "$1"; }
check_4()  { match_ans WIN_HOST "$1"; }
check_5()  { match_ans UBUNTU_IP "$1"; }
check_6()  { match_ans WIN_IP "$1"; }
check_7()  { match_ans SSH_PORT "$1"; }
check_8()  { match_ans RDP_PORT "$1"; }
check_9()  { match_ans SMB_PORT "$1"; }
check_10() { match_ans FTP_PORT "$1"; }
check_11() {
  local a; a=$(norm "$1"); a=${a//|/,}
  [[ "$a" == "$(ans_norm UBUNTU_OPEN_PORTS)" ]]
}
check_12() { match_any "$1" nginx "$(ans WEB_SVC_UBUNTU)"; }
check_13() { match_any "$1" iis microsoft microsoft-iis microsoftiis "$(ans WEB_SVC_WIN)" "microsoft httpapi" httpapi; }
check_14() { match_any "$1" openssh "$(ans SSH_PRODUCT)" "openSSH"; }
check_15() { match_any "$1" domain dns "$(ans DNS_SVC)"; }
check_16() { match_any "$1" microsoft-ds microsoft_ds smb "$(ans SMB_SVC)"; }
check_17() { match_any "$1" ftp "$(ans FTP_SVC)"; }
check_18() { match_ans HTTP_PORT "$1"; }
check_19() { match_ans DNS_PORT "$1"; }
check_20() { match_ans WIN_USER_SVC "$1"; }
check_21() { match_ans WIN_USER_INTERN "$1"; }
check_22() { match_ans LINUX_USER_WEB "$1"; }
check_23() { match_ans LINUX_USER_DEPLOY "$1"; }
check_24() { match_any "$1" enum4linux enum4linux-ng smbclient rpcclient nmap "enum4linux-ng"; }
check_25() { match_ans FTP_PORT "$1"; }
check_26() { match_any "$1" yes y true anonymous "$(ans FTP_ANON)"; }
check_27() { match_ans FTP_FLAG_FILE "$1" || [[ "$(norm "$1")" == "flag.txt" ]]; }
check_28() { match_ans FLAG_FTP "$1" || [[ "$(norm "$1")" == "flag{ftp_anon_loot}" ]]; }
check_29() { match_ans SHARE_PUBLIC "$1"; }
check_30() { match_ans SHARE_FINANCE "$1"; }
check_31() {
  local a; a=$(norm "$1")
  [[ "$a" == "it\$" || "$a" == "it$" || "$a" == "$(ans_norm SHARE_HIDDEN)" ]]
}
check_32() { match_ans FLAG_SMB_PUBLIC "$1" || [[ "$(norm "$1")" == "flag{smb_public_read}" ]]; }
check_33() { match_ans SHARE_LINUX "$1"; }
check_34() { match_ans FLAG_SMB_LINUX "$1" || [[ "$(norm "$1")" == "flag{linux_share_loot}" ]]; }
check_35() { match_ans ROBOTS_PATH_ADMIN "$1" || [[ "$(norm "$1")" == "admin" || "$(norm "$1")" == "/admin" ]]; }
check_36() { match_ans ROBOTS_PATH_BACKUP "$1" || [[ "$(norm "$1")" == "backup" || "$(norm "$1")" == "/backup" ]]; }
check_37() { match_ans FLAG_WEB_ADMIN "$1" || [[ "$(norm "$1")" == "flag{web_admin_panel}" ]]; }
check_38() { match_ans FLAG_WEB_BACKUP "$1" || [[ "$(norm "$1")" == "flag{nginx_backup_note}" ]]; }
check_39() { [[ "$(norm "$1")" == "/secret" || "$(norm "$1")" == "secret" ]]; }
check_40() { match_ans FLAG_WEB_SECRET "$1" || [[ "$(norm "$1")" == "flag{iis_secret_stash}" ]]; }
check_41() { match_ans LAB_DOMAIN "$1"; }
check_42() { match_ans DNS_MX "$1" || [[ "$(norm "$1")" == "mail.$(ans_norm LAB_DOMAIN)" ]]; }
check_43() { match_ans DNS_A_WEB "$1"; }
check_44() { match_ans DNS_TXT_FLAG "$1" || [[ "$(norm "$1")" == "flag{dns_zone_transfer}" ]]; }
check_45() { match_ans DNS_A_DC "$1"; }

# =============================================================================
#  ENGINE
# =============================================================================
LEVEL=1; HINTS_USED=0; LAST_OUT=""; SCORE=0

lvl_mission()   { echo "${L_M[$(( $1 - 1 ))]}"; }
lvl_in_mission() { local i n=0 m; m=$(lvl_mission "$1"); for (( i = 0; i < $1; i++ )); do [[ "${L_M[$i]}" == "$m" ]] && n=$((n + 1)); done; echo "$n"; }
mission_size()  { local i n=0; for i in "${L_M[@]}"; do [[ "$i" == "$1" ]] && n=$((n + 1)); done; echo "$n"; }
mission_first() { local i; for (( i = 0; i < TOTAL; i++ )); do [[ "${L_M[$i]}" == "$1" ]] && { echo $((i + 1)); return; }; done; echo 0; }
base_points()   { echo 10; }

rank_title() {
  local s=$1
  if   (( s >= 350 )); then echo "Recon Lead"
  elif (( s >= 220 )); then echo "Enumerator"
  elif (( s >= 100 )); then echo "Scanner"
  else echo "Recruit"; fi
}

banner() {
  cat <<EOF
${C}${BOLD}
  ███████╗███╗   ██╗██╗   ██╗███╗   ███╗     ██████╗ ██╗   ██╗███████╗███████╗████████╗
  ██╔════╝████╗  ██║██║   ██║████╗ ████║    ██╔═══██╗██║   ██║██╔════╝██╔════╝╚══██╔══╝
  █████╗  ██╔██╗ ██║██║   ██║██╔████╔██║    ██║   ██║██║   ██║█████╗  ███████╗   ██║
  ██╔══╝  ██║╚██╗██║██║   ██║██║╚██╔╝██║    ██║▄▄ ██║██║   ██║██╔══╝  ╚════██║   ██║
  ███████╗██║ ╚████║╚██████╔╝██║ ╚═╝ ██║    ╚██████╔╝╚██████╔╝███████╗███████║   ██║
  ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝     ╚══▀▀═╝  ╚═════╝ ╚══════╝╚══════╝   ╚═╝
${N}${DIM}  Network enumeration lab. Type real commands. Type ${N}help${DIM} any time.${N}

EOF
}

show_help() {
  line
  say "${BOLD}Game commands${N}   (everything else runs as a real Linux command)"
  say "  ${C}task${N}      show the current level again"
  say "  ${C}mission${N}   show the current mission's story and objectives"
  say "  ${C}targets${N}   print target hostnames / IPs from the lab config"
  say "  ${C}hint${N}      get a hint (3 per level; each costs 2 points)"
  say "  ${C}answer X${N}  submit an answer for the current level"
  say "  ${C}skip${N}      skip this level (0 points for it)"
  say "  ${C}progress${N}  levels done and your score"
  say "  ${C}reset${N}     clear your progress and start over"
  say "  ${C}quit${N}      save and exit   ${DIM}(Ctrl+C only stops the current command)${N}"
  line
}

show_targets() {
  line
  if [[ -f "$TARGETS" ]]; then
    say "${BOLD}Lab targets${N}"
    sed 's/^/  /' "$TARGETS"
  else
    warn "No $TARGETS — ask a mentor to run setup_jumpbox.sh"
  fi
  line
}

show_mission() {
  local m=$1 i=$((m - 1)) o
  line
  printf '%s%s MISSION %d: %s %s\n' "$BOLD" "$M" "$m" "${M_NAME[$i]}" "$N"
  say ""
  printf '%s\n' "${M_STORY[$i]}" | sed 's/^/  /'
  say ""
  say "  ${BOLD}Objectives${N}"
  while IFS= read -r o; do say "   ${C}▸${N} $o"; done <<<"${M_OBJ[$i]}"
  line
}

mission_briefing() {
  say ""
  show_mission "$1"
  if [[ -t 0 ]]; then
    printf '%sPress Enter to begin the mission...%s' "$DIM" "$N"; read -r _ || true; say ""
  fi
}

mission_debrief() {
  local m=$1 pts
  pts=$(cat "$STATE/mission_$m.pts" 2>/dev/null || echo 0)
  line
  printf '%s%s✔ MISSION %d COMPLETE: %s%s\n' "$G" "$BOLD" "$m" "${M_NAME[$((m - 1))]}" "$N"
  printf '  Mission points: %s   Total: %s   Rank: %s\n' "$pts" "$SCORE" "$(rank_title "$SCORE")"
  case $m in
    1) say "  You can scope targets and map ports. That is network enumeration." ;;
    2) say "  You know what is listening. That is service enumeration." ;;
    3) say "  You found accounts without admin rights. That is user enumeration." ;;
    4) say "  FTP and SMB both gave up files. That is share / file-service enumeration." ;;
    5) say "  You probed HTTP with curl and ffuf. That is web enumeration." ;;
    6) say "  You pulled DNS intel and a zone transfer. That is DNS enumeration." ;;
  esac
  line
}

show_task() {
  local i=$((LEVEL - 1)) m n sz
  m=${L_M[$i]}; n=$(lvl_in_mission "$LEVEL"); sz=$(mission_size "$m")
  line
  printf '%s%s%s · LEVEL %d/%d: %s%s\n' "$BOLD" "$M" "${M_TAG[$((m - 1))]}" "$n" "$sz" "${L_TITLE[$i]}" "$N"
  say ""
  printf '%s\n' "${L_TASK[$i]}" | sed 's/^/  /'
  say ""
  say "  ${DIM}Why: ${L_WHY[$i]}${N}"
  [[ "${L_TYPE[$i]}" == "answer" ]] && say "  ${DIM}(when you have it:  answer <value>)${N}"
  line
}

show_hint() {
  local i=$((LEVEL - 1)) hints
  IFS=$'\x1f' read -r -a hints <<<"$(sed 's/\([^ ]\)|\([^ ]\)/\1\x1f\2/g' <<<"${L_HINTS[$i]}")"
  if (( HINTS_USED >= ${#hints[@]} )); then warn "No more hints. Last one: ${hints[-1]}"; return; fi
  printf '%s💡 Hint %d/%d (-2 pts):%s %s\n' "$Y" $((HINTS_USED + 1)) "${#hints[@]}" "$N" "${hints[$HINTS_USED]}"
  HINTS_USED=$((HINTS_USED + 1))
}

level_points() {
  local base p; base=$(base_points "$LEVEL")
  p=$((base - 2 * HINTS_USED)); (( p < 0 )) && p=0; echo "$p"
}

save() { echo "$((LEVEL - 1))" > "$PROGRESS"; echo "$SCORE" > "$SCOREFILE"; }

add_points() {
  local m; m=$(lvl_mission "$LEVEL")
  SCORE=$((SCORE + $1))
  echo "$(( $(cat "$STATE/mission_$m.pts" 2>/dev/null || echo 0) + $1 ))" > "$STATE/mission_$m.pts"
}

enter_level() {
  HINTS_USED=0; touch "$MARK"
  if (( LEVEL > TOTAL )); then finish; exit 0; fi
  local m; m=$(lvl_mission "$LEVEL")
  if (( LEVEL == $(mission_first "$m") )); then mission_briefing "$m"; fi
  show_task
}

advance() {
  local pts m; pts=${1:-$(level_points)}; m=$(lvl_mission "$LEVEL")
  add_points "$pts"
  ok "Level complete  +$pts pts   (total $SCORE)"
  LEVEL=$((LEVEL + 1)); save
  if (( LEVEL > TOTAL )) || [[ "$(lvl_mission "$LEVEL")" != "$m" ]]; then mission_debrief "$m"; fi
  sleep 0.4
  enter_level
}

try_auto() { [[ "${L_TYPE[$((LEVEL - 1))]}" == "auto" ]] || return 0; "check_$LEVEL" && advance; return 0; }
try_answer() {
  local i=$((LEVEL - 1))
  [[ "${L_TYPE[$i]}" == "answer" ]] || { warn "This level passes automatically when the task is done; no answer needed."; return; }
  [[ -n "$1" ]] || { warn "Usage: answer <value>"; return; }
  if "check_$LEVEL" "$1"; then advance; else err "Not it. Try again, or type hint."; fi
}

show_progress() {
  local i m=0
  line
  printf '  %sScore: %d   Rank: %s%s\n' "$BOLD" "$SCORE" "$(rank_title "$SCORE")" "$N"
  for (( i = 0; i < TOTAL; i++ )); do
    if [[ "${L_M[$i]}" != "$m" ]]; then m=${L_M[$i]}; printf '  %s%s %s%s\n' "$BOLD" "${M_TAG[$((m - 1))]}" "${M_NAME[$((m - 1))]}" "$N"; fi
    if (( i + 1 < LEVEL )); then printf '    %s✔%s %s\n' "$G" "$N" "${L_TITLE[$i]}"
    elif (( i + 1 == LEVEL )); then printf '    %s▶%s %s  %s(current)%s\n' "$Y" "$N" "${L_TITLE[$i]}" "$DIM" "$N"
    else printf '    %s·%s %s\n' "$DIM" "$N" "${L_TITLE[$i]}"; fi
  done
  line
}

finish() {
  line
  printf '%s%s🏆  ENUM QUEST COMPLETE. Final score: %d   Rank: %s%s\n' "$G" "$BOLD" "$SCORE" "$(rank_title "$SCORE")" "$N"
  say "  Network, services, users, shares, web, and DNS — that is a full recon pass."
  line
  score_code_line
}

score_code() {
  local name=$1 score=$2 secret sig
  secret=$(cat "$CFG/secret" 2>/dev/null) || secret="nosecret"
  sig=$(printf '%s:%s:%s' "$name" "$score" "$secret" | sha256sum | cut -c1-4 | tr a-f A-F)
  printf '%s-%s-%s' "$(tr '[:lower:]' '[:upper:]' <<<"$name" | tr -cd 'A-Z0-9')" "$score" "$sig"
}
score_code_line() {
  (( SHOW_SCORE_CODE )) || return 0
  say "  ${DIM}Score code (give this to a mentor):${N} ${BOLD}$(score_code "$(cat "$NAMEFILE" 2>/dev/null)" "$SCORE")${N}"
}
verify_code() {
  local name score
  IFS=- read -r name score _ <<<"$1"
  if [[ "$(score_code "$name" "$score")" == "$1" ]]; then ok "valid: $name scored $score"; else err "invalid code"; exit 1; fi
}

is_interactive() {
  case "$1" in
    man|less|more|nano|vim|vi|top|htop|clear|cd|export|unset|alias|passwd|sudo|ssh|su|smbclient|ftp|ffuf|nmap) return 0;;
  esac
  return 1
}
run_player_cmd() {
  local cmd="$1" first; first=${cmd%% *}
  # Always leave nmap/ffuf/smbclient uncaptured so progress meters work
  if is_interactive "$first"; then
    eval "$cmd"; LAST_OUT=""
  else
    LAST_OUT=$(eval "$cmd" 2>&1); [[ -n "$LAST_OUT" ]] && printf '%s\n' "$LAST_OUT"
  fi
}
prompt_string() {
  local rel
  if [[ "$PWD" == "$H"* ]]; then rel="~${PWD#"$H"}"; else rel="$PWD"; fi
  printf '%s[%s L%d | %dpts]%s %s%s%s $ ' "$M" "${M_TAG[$(( $(lvl_mission "$LEVEL") - 1 ))]}" "$(lvl_in_mission "$LEVEL")" "$SCORE" "$N" "$C" "$rel" "$N"
}
read_input() {
  ( [[ -f "$HISTFILE" ]] && history -r "$HISTFILE"
    IFS= read -r -e -p "$(prompt_string)" line || exit $?
    printf '%s' "$line" )
}

do_reset() {
  say "Clearing your ENUM QUEST progress (targets are unchanged)..."
  mkdir -p "$STATE"
  echo 0 > "$PROGRESS"; echo 0 > "$SCOREFILE"
  rm -f "$STATE"/mission_*.pts
  LEVEL=1; SCORE=0
  cd "$H" || true
  ok "Fresh start."; enter_level
}

main_loop() {
  local input first rest rc
  while true; do
    input=$(read_input); rc=$?
    (( rc > 128 )) && continue
    (( rc != 0 )) && { say ""; break; }
    [[ -z "$input" ]] && continue
    history -s "$input"; history -w "$HISTFILE" 2>/dev/null
    first=${input%% *}; rest=${input#"$first"}; rest=${rest# }
    case "$first" in
      help)      show_help ;;
      task)      show_task ;;
      mission)   show_mission "$(lvl_mission "$(( LEVEL > TOTAL ? TOTAL : LEVEL ))")" ;;
      targets)   show_targets ;;
      hint)      show_hint ;;
      answer)    try_answer "$rest" ;;
      skip)      warn "Skipped (0 pts)."; advance 0 ;;
      progress)  show_progress ;;
      reset)     do_reset ;;
      quit|exit) break ;;
      *)         run_player_cmd "$input"; try_auto ;;
    esac
  done
  say "${DIM}Progress saved (score $SCORE). Run enum-quest again to continue.${N}"
}

# =============================================================================
#  START
# =============================================================================
on_interrupt() { printf '\n%s^C  (stops the current command only; type quit to leave)%s\n' "$DIM" "$N"; }
trap on_interrupt INT

case "${1:-}" in
  --verify) verify_code "$2"; exit ;;
  --reset)  rm -rf "$STATE" ;;
esac

if [[ $EUID -eq 0 && "${EQ_ALLOW_ROOT:-0}" != 1 ]]; then
  err "Don't play as root. Log in as your ocigN account, then run:  enum-quest"
  exit 1
fi

mkdir -p "$STATE"
cd "$H" || exit 1
if [[ ! -f "$H/briefing.txt" || ! -f "$ANSWERS" ]]; then
  err "Lab files missing for $(id -un)."
  say "  Ask a mentor to run on this jumpbox:"
  say "    sudo bash setup_jumpbox.sh --no-switch"
  say "  (uses your login user via sudo — e.g. ocig1)"
  exit 1
fi

banner
if [[ ! -s "$NAMEFILE" ]]; then
  printf 'What should I call you? '; IFS= read -r nm; nm=${nm:-$(id -un)}; printf '%s' "$nm" > "$NAMEFILE"; say ""
fi
SCORE=$(cat "$SCOREFILE" 2>/dev/null || echo 0)
LEVEL=$(( $(cat "$PROGRESS" 2>/dev/null || echo 0) + 1 ))
(( LEVEL > 1 )) && say "${DIM}Welcome back, $(cat "$NAMEFILE"). Resuming with $SCORE points. Type reset to start over.${N}"
show_help
enter_level
main_loop
