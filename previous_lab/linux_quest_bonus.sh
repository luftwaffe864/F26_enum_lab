#!/usr/bin/env bash
# =============================================================================
#  LINUX QUEST — BONUS MISSION "THE GHOST"
#
#  Run as the `student` user on a machine prepared by setup.sh + bonus_setup.sh.
#  Normally reached by typing `bonus` at the end of mission 3; the core game
#  execs this script. Can also be started directly:
#
#      linux-quest-bonus                start / resume
#      linux-quest-bonus --reset        re-plant the artifacts, restart the mission
#      LQ_BONUS_FORCE=1 linux-quest-bonus   start without finishing the core
#
#  Scoring: 25 points a stage. Each hint costs 2. Taking the third hint (the
#  full command) scores that stage 0. skip scores 0. The running total is
#  shared with the core game via ~/.linux-quest/score.
#
#  No answers are stored in this file: every check reads the planted values
#  from /etc/linux-quest/bonus_fragments (root-only, mode 600) through sudo.
# =============================================================================

set -o pipefail

LIB=/usr/local/lib/linux-quest
CFG=/etc/linux-quest
SYS=/opt/.sysmon
FRAGFILE="$CFG/bonus_fragments"
BONUS_SETUP="$LIB/bonus_setup.sh"
H="$HOME"
STATE="$H/.linux-quest"
CORE_PROGRESS="$STATE/progress"; SCOREFILE="$STATE/score"; NAMEFILE="$STATE/name"
BPROGRESS="$STATE/bonus_progress"; BPTS="$STATE/bonus_points"
COLLECTED="$STATE/fragments"; HISTFILE="$STATE/bonus_history"
CORE_LEVELS=54                     # missions 1-3 combined

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
as_root() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo -n "$@"; fi; }
norm() { tr '[:upper:]' '[:lower:]' <<<"$1" | tr -d '[:space:]'; }
squash() { tr -d '[:space:]' <<<"$1"; }          # case-preserving (base64 chunks)

# planted values, read from the root-only answer key
planted()      { as_root grep "^GHOST-$1:" "$FRAGFILE" 2>/dev/null | head -1; }
planted_meta() { as_root grep "^$1:" "$FRAGFILE" 2>/dev/null | head -1 | cut -d: -f2-; }

# a fragment answer is right if it matches the whole "GHOST-n:chunk" or just the
# chunk; case matters (base64), whitespace does not
frag_ok() {
  local want got
  want=$(squash "$(planted "$1")"); got=$(squash "$2")
  [[ -n "$want" ]] || return 1
  [[ "$got" == "$want" || "$got" == "${want#*:}" ]]
}

# The SUID donor is chosen by preflight (base64, xxd, or cat) and recorded here,
# because on newer Ubuntu the coreutils tools are one multi-call binary that will
# not act like base64 when renamed. Stage 7's hint has to match whatever was used.
donor_read_cmd() {
  case "$(cat "$CFG/bonus_donor" 2>/dev/null)" in
    xxd) echo "/usr/bin/systemd-helper -p /root/.ghost/note | /usr/bin/systemd-helper -r -p" ;;
    cat) echo "/usr/bin/systemd-helper /root/.ghost/note" ;;
    *)   echo "/usr/bin/systemd-helper /root/.ghost/note | /usr/bin/systemd-helper -d" ;;
  esac
}

kthread_name() { cat "$CFG/bonus_kworker" 2>/dev/null || echo "[kworker/2:1H]"; }
kthread_pid()  { ps -eo pid,args | grep -F -- "$(kthread_name)" | grep -v grep | awk '{print $1}' | head -1; }
beacon_pid()   { ps -eo pid,args | grep -F -- "$SYS/beacon" | grep -v grep | awk '{print $1}' | head -1; }

# =============================================================================
#  STAGES        add_stage <title> <task> <why> <auto|answer> "h1|h2|h3"
# =============================================================================
S_TITLE=(); S_TASK=(); S_WHY=(); S_TYPE=(); S_HINTS=()
add_stage() { S_TITLE+=("$1"); S_TASK+=("$2"); S_WHY+=("$3"); S_TYPE+=("$4"); S_HINTS+=("$5"); }

add_stage "Something on a schedule" \
"The network team says the lookups happen about every 15 minutes, and cron is clean.
Something else on this machine runs things on a timer. Find what it runs, and submit
the fragment hidden inside it." \
"systemd timers are persistence that survives 'crontab -r' and is invisible to anyone who only checks cron." \
answer "cron is not the only scheduler on a modern Linux system. systemd can run things on a clock too, and it will list them for you.|systemctl list-timers --all  — one of those units is not a real Ubuntu one. systemctl cat <unit> shows what it executes.|systemctl list-timers --all ; systemctl cat man-db-cache.service ; cat /opt/.sysmon/collect.sh"

add_stage "The impostor in PATH" \
"The collector is not the only thing that was tampered with. One of the system's own
maintenance commands is not the file you think it is. Find the impostor and submit the
fragment inside it." \
"When two files share a name, the shell runs whichever directory comes first in PATH. Attackers exploit that ordering." \
answer "When you type a command, the shell walks a list of directories in order and takes the first match. There can be more than one match.|which shows the winner; type -a shows every candidate. Try it on the log maintenance command, logrotate.|type -a logrotate ; cat /usr/local/sbin/logrotate"

add_stage "The process that pretends to be the kernel" \
"Among the kernel's worker threads, one is an ordinary program wearing a kernel thread's
name. Identify it, then read the fragment out of its environment." \
"Real kernel threads share one parent and have no executable file. Anything else with a [bracketed] name is lying to you." \
answer "Real kernel threads all descend from the same process and have no executable file behind them. One of these entries differs on both counts.|Compare the PPID column and /proc/<pid>/exe across the kworker entries; the impostor's parent is not the one the others share. Then read that process's environment from /proc/<pid>/environ, where entries are separated by NUL bytes. Note: a < redirect is opened by YOUR shell before sudo runs, so the command running under sudo has to open the file itself.|ps -eo pid,ppid,args | grep kworker ; sudo ls -l /proc/<pid>/exe ; sudo cat /proc/<pid>/environ | tr '\0' '\n' | grep GHOST"

add_stage "A file that will not die" \
"The collector reads /etc/.ghostrc, and even root cannot delete it. Read it first: it holds
a fragment and the key= value you will need next. Then remove the protection, delete the
file, and submit the fragment." \
"Permissions are not the only gate on Linux. Filesystem attributes can stop root itself, and cleanup scripts never check for them." \
answer "Root was denied. Permissions are not the only thing that can forbid a write; the filesystem carries flags of its own.|lsattr shows those flags, chattr changes them. You are looking for the immutable flag.|sudo chattr -i /etc/.ghostrc ; sudo rm /etc/.ghostrc"

add_stage "Layers" \
"The key= value from that config is wrapped several times over. (A copy is cached at
/var/tmp/.sysmon.cache if you already deleted the file.) Peel it and submit the fragment." \
"Encoding is not encryption. Real samples are usually wrapped more than once, in an order you have to work out." \
answer "Three wrappings around something compressed. The outermost is the oldest trick in the book, and the '=' padding turning up at the wrong end is your second clue.|Undo them in reverse: a letter rotation, then a reversal, then base64, then decompression. tr, rev, base64 -d, gunzip.|echo '<blob>' | tr 'A-Za-z' 'N-ZA-Mn-za-m' | rev | base64 -d | gunzip"

add_stage "The binary that no longer exists" \
"One of the ghost's programs is running right now, but its file is gone from the disk.
Recover it from the running process and read the fragment out of it." \
"Deleting a file does not free it while a process holds it open. This is how responders recover malware that erased itself." \
answer "Deleting a file does not free it while a process still has it open. The kernel keeps a door to it for you.|Everything about a running process lives under /proc/<pid>/ — including links to its executable and to every file descriptor it holds. A shell script sits on one of the higher-numbered ones.|ps -eo pid,args | grep sysmon ; sudo ls -l /proc/<pid>/fd/ ; sudo cat /proc/<pid>/fd/255"

add_stage "Root's spare key" \
"The ghost left itself a way to read root's files without being root. Find it, and use it
to read /root/.ghost/note. Do not use sudo for the read — that is the whole point." \
"A SUID copy of an ordinary tool is a full compromise: it runs as its owner, not as you." \
answer "Some files run with the privileges of their owner instead of yours. Find every one of them on this machine and look for a name that does not belong.|find / -perm -4000 -type f 2>/dev/null — then work out what the odd one actually is. It is a renamed copy of a very ordinary tool, so ask it for --help and use that tool's own syntax.|@DONOR@"

add_stage "The spare front door" \
"Even with every password on this machine changed, the ghost can still log in as root.
Find how, and submit the fragment it left in plain sight." \
"Key-based access ignores passwords entirely. Rotating credentials without auditing keys leaves the door open." \
answer "Accounts are not the only way in. Key-based login does not care that you changed every password on this machine.|Look in root's home for the list of keys allowed to log in as root. The last field of a key line is free text the attacker chose.|sudo cat /root/.ssh/authorized_keys"

add_stage "What it took" \
"The lookups were only the signal; something was actually taken. From the web server's
access log, work out which client was not a browser and what it downloaded repeatedly,
then read that file off the disk and submit the fragment." \
"Exfiltration usually looks like ordinary traffic. The tell is a field nobody bothers to forge." \
answer "Thousands of requests, and only a handful are the ghost's. It never pretended to be a browser — that is the only thing that gives it away.|Count how often each user-agent appears and look at the rare ones. Then find what that client asked for, and read it off the disk.|sudo awk -F'\"' '{print \$6}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | tail ; sudo grep sysmon-agent /var/log/nginx/access.log | awk '{print \$7}' | sort -u ; cat /var/www/html/assets/.data/x9f2.bin"

add_stage "Assemble the key" \
"You have nine fragments. Each one is numbered. Put them in order, join them with nothing
in between, decode, and submit the key.  (Type  fragments  to see what you collected.)" \
"One last pipeline: sort, cut, join, decode. This is the shape of most real analysis work." \
answer "The numbers are there for a reason. What you get by joining them is not the key yet — it is the key wearing one last coat.|Sort by fragment number, keep only the part after the colon, join them with no separator, then base64 -d.|sort -t- -k2 -n ~/.linux-quest/fragments | cut -d: -f2 | tr -d '\\n' | base64 -d"

TOTAL=${#S_TITLE[@]}

# =============================================================================
#  CHECKS
# =============================================================================
check_1()  { frag_ok 1 "$1"; }
check_2()  { frag_ok 2 "$1"; }
check_3()  { frag_ok 3 "$1"; }
# 2 = right fragment, but the file is still there (try_answer explains)
check_4()  { frag_ok 4 "$1" || return 1; [[ -e /etc/.ghostrc ]] && return 2; return 0; }
check_5()  { frag_ok 5 "$1"; }
check_6()  { frag_ok 6 "$1"; }
check_7()  { frag_ok 7 "$1"; }
check_8()  { frag_ok 8 "$1"; }
check_9()  { frag_ok 9 "$1"; }
check_10() { [[ "$(norm "$1")" == "$(norm "$(planted_meta FINAL)")" ]]; }

# which stages hand over a fragment (stage 4 does not)
stage_frag_index() { case $1 in 10) echo "";; *) echo "$1";; esac; }

# =============================================================================
#  ENGINE
# =============================================================================
STAGE=1; HINTS_USED=0; LAST_OUT=""; SCORE=0; EARNED=0

banner() {
  cat <<EOF
${M}${BOLD}
      ████████ ██   ██ ███████      ██████  ██   ██  ██████  ███████ ████████
         ██    ██   ██ ██          ██       ██   ██ ██    ██ ██         ██
         ██    ███████ █████       ██   ███ ███████ ██    ██ ███████    ██
         ██    ██   ██ ██          ██    ██ ██   ██ ██    ██      ██    ██
         ██    ██   ██ ███████      ██████  ██   ██  ██████  ███████    ██
${N}${DIM}   Bonus mission. Nothing here is on the slides. Type ${N}help${DIM} for the controls.${N}

EOF
}

show_help() {
  line
  say "${BOLD}Commands${N}   (everything else runs as a real Linux command)"
  say "  ${C}stage${N}     show the current stage again        ${DIM}(task works too)${N}"
  say "  ${C}mission${N}   the story and objectives"
  say "  ${C}hint${N}      3 per stage, each costs 2 points"
  say "            ${DIM}the 3rd hint is the command itself and scores that stage 0${N}"
  say "  ${C}answer X${N}  submit a fragment or the final key"
  say "  ${C}fragments${N} what you have collected so far"
  say "  ${C}skip${N}      give up on this stage (0 points)"
  say "  ${C}progress${N}  stages done and your score"
  say "  ${C}reset${N}     re-plant the ghost and start the bonus over"
  say "  ${C}quit${N}      save and exit   ${DIM}(Ctrl+C only stops the current command)${N}"
  line
}

show_mission() {
  line
  printf '%s%s MISSION 4: THE GHOST %s\n' "$BOLD" "$M" "$N"
  say ""
  say "  vault is clean. You removed the account, the process, the service and the cron"
  say "  jobs, and the site is serving again. Then the campus network team called: vault"
  say "  is still making outbound DNS lookups to a domain nobody recognises, roughly"
  say "  every fifteen minutes, and it started before the break-in you investigated."
  say ""
  say "  The intruder you chased was not the first one in. Something older is still here,"
  say "  and it was built to survive exactly the cleanup you just performed. It hides in"
  say "  the places you did not look: in a scheduler you trusted, in a binary that no"
  say "  longer exists on disk, in a file you cannot delete, and in a process that"
  say "  pretends to be part of the kernel."
  say ""
  say "  Nine pieces of a single key are scattered across this machine."
  say ""
  say "  ${BOLD}Objectives${N}"
  say "   ${C}▸${N} Hunt persistence that survives a reboot and a cleanup"
  say "   ${C}▸${N} Tell a real system component from something wearing its name"
  say "   ${C}▸${N} Recover evidence from a process whose file is gone"
  say "   ${C}▸${N} Defeat a file that refuses to be deleted"
  say "   ${C}▸${N} Undo a layered encoding by hand"
  say "   ${C}▸${N} Assemble nine fragments into one key"
  line
}

show_stage() {
  local i=$((STAGE - 1))
  line
  printf '%s%sM4 · STAGE %d/%d: %s%s\n' "$BOLD" "$M" "$STAGE" "$TOTAL" "${S_TITLE[$i]}" "$N"
  say ""
  printf '%s\n' "${S_TASK[$i]}" | sed 's/^/  /'
  say ""
  say "  ${DIM}Why: ${S_WHY[$i]}${N}"
  [[ "${S_TYPE[$i]}" == "answer" ]] && say "  ${DIM}(when you have it:  answer <value>)${N}"
  line
}

show_hint() {
  local i=$((STAGE - 1)) hints
  IFS=$'\x1f' read -r -a hints <<<"$(sed 's/\([^ ]\)|\([^ ]\)/\1\x1f\2/g' <<<"${S_HINTS[$i]}")"
  hints=("${hints[@]//@DONOR@/find / -perm -4000 -type f 2>/dev/null ; $(donor_read_cmd)}")
  if (( HINTS_USED >= ${#hints[@]} )); then warn "No more hints. Last one: ${hints[-1]}"; return; fi
  if (( HINTS_USED == 2 )); then
    warn "This hint is the command itself and will score this stage 0. Type hint again to see it."
    HINTS_USED=3; return
  fi
  printf '%s💡 Hint %d/3 (-2 pts):%s %s\n' "$Y" $((HINTS_USED + 1)) "$N" "${hints[$HINTS_USED]}"
  HINTS_USED=$((HINTS_USED + 1))
}
reveal_last_hint() {
  local i=$((STAGE - 1)) hints
  IFS=$'\x1f' read -r -a hints <<<"$(sed 's/\([^ ]\)|\([^ ]\)/\1\x1f\2/g' <<<"${S_HINTS[$i]}")"
  hints=("${hints[@]//@DONOR@/find / -perm -4000 -type f 2>/dev/null ; $(donor_read_cmd)}")
  printf '%s💡 Hint 3/3 (this stage now scores 0):%s %s\n' "$Y" "$N" "${hints[2]}"
  HINTS_USED=4
}

stage_points() {
  (( HINTS_USED >= 3 )) && { echo 0; return; }
  local p=$(( 25 - 2 * HINTS_USED )); (( p < 0 )) && p=0; echo "$p"
}

save() {
  echo "$((STAGE - 1))" > "$BPROGRESS"
  echo "$SCORE" > "$SCOREFILE"
  echo "$EARNED" > "$BPTS"
}

collect_fragment() {
  local idx; idx=$(stage_frag_index "$STAGE")
  [[ -n "$idx" ]] || return 0
  local f; f=$(planted "$idx")
  [[ -n "$f" ]] || return 0
  grep -qxF "$f" "$COLLECTED" 2>/dev/null || echo "$f" >> "$COLLECTED"
}

show_fragments() {
  line
  if [[ ! -s "$COLLECTED" ]]; then
    say "  Nothing collected yet."
  else
    say "  ${BOLD}Fragments collected${N} ${DIM}(in the order you found them)${N}"
    while IFS= read -r f; do say "    $f"; done < "$COLLECTED"
    say ""
    say "  ${DIM}$(wc -l < "$COLLECTED") of 9. They are numbered for a reason.${N}"
  fi
  line
}

# live artifacts die on reboot; bring back whatever this stage needs
ensure_artifacts() {
  case $STAGE in
    1) systemctl is-active man-db-cache.timer >/dev/null 2>&1 || as_root "$BONUS_SETUP" --spawn timer >/dev/null 2>&1 ;;
    3) [[ -n "$(kthread_pid)" ]] || as_root "$BONUS_SETUP" --spawn kthread >/dev/null 2>&1 ;;
    6) [[ -n "$(beacon_pid)" ]] || as_root "$BONUS_SETUP" --spawn beacon  >/dev/null 2>&1 ;;
  esac
}

enter_stage() {
  HINTS_USED=0
  if (( STAGE > TOTAL )); then finish; exit 0; fi
  ensure_artifacts
  if (( STAGE == 4 )) && [[ -e "$CFG/bonus_nochattr" ]]; then
    warn "Note: this machine's filesystem does not support file attributes, so the"
    warn "      protection could not be applied. Deleting the file is enough here."
  fi
  show_stage
}

advance() {
  local pts=${1:-$(stage_points)}
  collect_fragment
  SCORE=$((SCORE + pts)); EARNED=$((EARNED + pts))
  ok "Stage $STAGE complete  +$pts pts   (total $SCORE)"
  STAGE=$((STAGE + 1)); save
  sleep 0.5
  enter_stage
}

try_auto() { [[ "${S_TYPE[$((STAGE - 1))]}" == "auto" ]] || return 0; "check_$STAGE" && advance; return 0; }
try_answer() {
  local i=$((STAGE - 1))
  [[ "${S_TYPE[$i]}" == "answer" ]] || { warn "This stage passes on its own once the task is done."; return; }
  [[ -n "$1" ]] || { warn "Usage: answer <value>"; return; }
  local rc; "check_$STAGE" "$1"; rc=$?
  case $rc in
    0) advance ;;
    2) warn "That is the right fragment, but the file is still on the disk. Remove its protection and delete it, then submit again." ;;
    *) err "Not it. Try again, or type hint." ;;
  esac
}

show_progress() {
  local i
  line
  printf '  %sScore: %d   (%d of it earned in the bonus)%s\n' "$BOLD" "$SCORE" "$EARNED" "$N"
  for (( i = 0; i < TOTAL; i++ )); do
    if   (( i + 1 < STAGE ));  then printf '    %s✔%s %d. %s\n' "$G" "$N" $((i + 1)) "${S_TITLE[$i]}"
    elif (( i + 1 == STAGE )); then printf '    %s▶%s %d. %s  %s(current)%s\n' "$Y" "$N" $((i + 1)) "${S_TITLE[$i]}" "$DIM" "$N"
    else printf '    %s·%s %d. %s\n' "$DIM" "$N" $((i + 1)) "${S_TITLE[$i]}"; fi
  done
  line
}

finish() {
  line
  printf '%s%s🏆  THE GHOST IS GONE. Final score: %d   Rank: Ghost Hunter%s\n' "$G" "$BOLD" "$SCORE" "$N"
  line
  say "  What you just did, in the words the industry uses:"
  say "   1. systemd timer persistence          ${DIM}T1053.006${N}"
  say "   2. path interception                  ${DIM}T1574.007${N}"
  say "   3. masquerading as a kernel thread    ${DIM}T1036${N}"
  say "   4. immutable-attribute anti-cleanup   ${DIM}anti-forensics${N}"
  say "   5. layered obfuscation                ${DIM}T1027${N}"
  say "   6. binary deleted while still running ${DIM}T1070.004${N}"
  say "   7. SUID privilege escalation          ${DIM}T1548.001${N}"
  say "   8. authorized_keys persistence        ${DIM}T1098.004${N}"
  say "   9. exfiltration hidden in web traffic ${DIM}T1041${N}"
  say ""
  say "  Nothing here was exotic. Every one of these is in real incident reports,"
  say "  and every one of them survives a password change."
  line
}

# ---------- command runner ---------------------------------------------------
is_interactive() {
  case "$1" in man|less|more|nano|vim|vi|top|htop|clear|cd|export|unset|alias|passwd|sudo|visudo|crontab|journalctl|systemctl|apt|apt-get|ssh|su|watch|gdb|strace) return 0;; esac
  return 1
}
run_player_cmd() {
  local cmd="$1" first; first=${cmd%% *}
  if is_interactive "$first"; then eval "$cmd"; LAST_OUT=""
  else LAST_OUT=$(eval "$cmd" 2>&1); [[ -n "$LAST_OUT" ]] && printf '%s\n' "$LAST_OUT"; fi
}
prompt_string() {
  local rel
  if [[ "$PWD" == "$H"* ]]; then rel="~${PWD#"$H"}"; else rel="$PWD"; fi
  printf '%s[GHOST S%d | %dpts]%s %s%s%s $ ' "$M" "$STAGE" "$SCORE" "$N" "$C" "$rel" "$N"
}
read_input() {
  ( [[ -f "$HISTFILE" ]] && history -r "$HISTFILE"
    IFS= read -r -e -p "$(prompt_string)" l || exit $?
    printf '%s' "$l" )
}

do_reset() {
  say "Re-planting the ghost..."
  if as_root "$BONUS_SETUP" --state >/dev/null 2>&1; then
    SCORE=$((SCORE - EARNED)); (( SCORE < 0 )) && SCORE=0
    EARNED=0; STAGE=1; : > "$COLLECTED"; save
    ok "Done. Back to stage 1."
    enter_stage
  else
    err "Reset failed. Ask a mentor to run: sudo $BONUS_SETUP --state"
  fi
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
      help)        show_help ;;
      stage|task)  show_stage ;;
      mission)     show_mission ;;
      hint)        if (( HINTS_USED == 3 )); then reveal_last_hint; else show_hint; fi ;;
      answer)      try_answer "$rest" ;;
      fragments)   show_fragments ;;
      skip)        warn "Skipped (0 pts)."; advance 0 ;;
      progress)    show_progress ;;
      reset)       do_reset ;;
      quit|exit)   break ;;
      *)           run_player_cmd "$input"; try_auto ;;
    esac
  done
  say "${DIM}Progress saved (score $SCORE). Run linux-quest-bonus to continue.${N}"
}

# =============================================================================
#  START
# =============================================================================
on_interrupt() { printf '\n%s^C  (stops the current command only; type quit to leave)%s\n' "$DIM" "$N"; }
trap on_interrupt INT

[[ "${1:-}" == "--reset" ]] && { as_root "$BONUS_SETUP" --state || exit 1; rm -f "$BPROGRESS" "$BPTS" "$COLLECTED"; }

if [[ $EUID -eq 0 && "${LQ_ALLOW_ROOT:-0}" != 1 ]]; then
  err "Don't play as root. Switch to the student account:  su - student"; exit 1
fi
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
  err "This account needs passwordless sudo. Ask a mentor."; exit 1
fi
if ! as_root test -s "$FRAGFILE"; then
  err "The bonus mission is not installed on this machine."
  say "  A mentor can install it with:  sudo ./bonus_setup.sh"
  exit 1
fi
if [[ "${LQ_BONUS_FORCE:-0}" != 1 ]] && (( $(cat "$CORE_PROGRESS" 2>/dev/null || echo 0) < CORE_LEVELS )); then
  err "Finish missions 1-3 first (run: linux-quest)."
  say "  ${DIM}Mentors can override with:  LQ_BONUS_FORCE=1 linux-quest-bonus${N}"
  exit 1
fi

mkdir -p "$STATE"; touch "$COLLECTED"
cd "$H" || exit 1
SCORE=$(cat "$SCOREFILE" 2>/dev/null || echo 0)
EARNED=$(cat "$BPTS" 2>/dev/null || echo 0)
STAGE=$(( $(cat "$BPROGRESS" 2>/dev/null || echo 0) + 1 ))

banner
if (( STAGE > 1 )); then
  say "${DIM}Welcome back$( [[ -s $NAMEFILE ]] && printf ', %s' "$(cat "$NAMEFILE")" ). Resuming at stage $STAGE with $SCORE points.${N}"
else
  show_mission
  say "${BOLD}Bonus rules:${N} 25 points a stage. The hints start deliberately vague."
  say "The third hint gives the command and scores that stage 0."
  say "Type  ${C}fragments${N}  at any time to see what you have collected."
  say ""
  if [[ -t 0 ]]; then printf '%sPress Enter to begin the hunt...%s' "$DIM" "$N"; read -r _ || true; say ""; fi
fi
show_help
enter_stage
main_loop
