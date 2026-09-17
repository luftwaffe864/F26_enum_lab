#!/usr/bin/env bash
# =============================================================================
#  LINUX QUEST  v2  — an incident-response story for absolute Linux beginners
#  DCIG "Linux Basics for Cybersecurity"
#
#  Run as the `student` user on a VM prepared by setup.sh:
#      linux-quest                 start / resume
#      linux-quest --reset         rebuild the compromised server and start over
#      linux-quest --verify CODE   check a score code (mentors, leaderboard mode)
#
#  Structure
#    Mission 1  TRIAGE     shell, paths, files, redirection, grep, find
#    Mission 2  LOCKDOWN   users, groups, sudo, permissions, processes, services
#    Mission 3  REBUILD    cron, logs, apt, nginx, ss, curl
#    Mission 4  BONUS      (placeholder: add levels with  add_level 4 ...)
#
#  Engine
#    - Players type real commands. "auto" levels pass as soon as the system
#      state is right; "answer" levels need `answer <value>`.
#    - Points: 10 per core level, 25 per bonus level. Each hint costs 2.
#      In the bonus mission, taking the 3rd hint (the full command) = 0 points.
#      skip = 0 points.
#    - Checks that need root run through `sudo -n` (student has NOPASSWD sudo).
#    - Ctrl+C never exits the game. Progress and score persist in ~/.linux-quest.
#    - SHOW_SCORE_CODE=1 turns on signed score codes for a manual leaderboard.
#
#  Adding a level: one add_level call + one check_<global index> function.
# =============================================================================

set -o pipefail

LIB=/usr/local/lib/linux-quest
CFG=/etc/linux-quest
CACHE=/usr/local/lib/.cache
BONUS_BIN=/usr/local/bin/linux-quest-bonus
H="$HOME"
STATE="$H/.linux-quest"
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
as_root() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo -n "$@"; fi; }
norm() { tr '[:upper:]' '[:lower:]' <<<"$1" | tr -d '[:space:]'; }
svc_active()  { systemctl is-active "$1" 2>/dev/null | grep -qx active; }
svc_enabled() { systemctl is-enabled "$1" 2>/dev/null | grep -qx enabled; }

# =============================================================================
#  MISSIONS
# =============================================================================
M_NAME=(); M_TAG=(); M_STORY=(); M_OBJ=()
add_mission() { M_NAME+=("$1"); M_TAG+=("$2"); M_STORY+=("$3"); M_OBJ+=("$4"); }

add_mission "TRIAGE" "M1" \
"Someone broke into the DCIG web server 'vault' last night. The site is down, the
admin is locked out, and strange things are running. You have just been given a
normal user account on the server. Before you can fix anything you need to know
where you are, what is on this machine, and what the attacker touched." \
"Learn to move around the filesystem and read files
Build an evidence folder and keep notes without opening an editor
Pull facts out of a 200-line log with grep, pipes, and counting
Locate a file the attacker hid somewhere on the disk"

add_mission "LOCKDOWN" "M2" \
"You know the attacker came from 203.0.113.42 and left notes behind. Now take the
server back. The attacker created an account, gave it admin rights, locked out the
real admin, hijacked the website files, and left a rogue process and a fake
service running as root. Every one of those needs to be undone." \
"Understand who you are, who root is, and when sudo is needed
Find the rogue account, strip its admin rights, and delete it
Restore the real admin's access and create an analyst account
Fix ownership and permissions on the hijacked files
Find and kill the rogue process; stop and disable the rogue service"

add_mission "REBUILD" "M3" \
"The rogue process and service are gone, but attackers plan for that: scheduled
tasks bring things back. Remove the persistence, prove what happened from the
system logs, then install the web server, deploy the club's page, and verify with
your own eyes that vault is serving on port 80 again." \
"Find and remove the attacker's cron jobs
Use the real system logs (auth.log, journalctl) as evidence
Install software the right way with apt
Install nginx, deploy the site, and verify it with ss and curl"

add_mission "BONUS: THE GHOST" "M4" \
"The server looks clean. It is not. Something is still calling home." \
"Coming soon"

# =============================================================================
#  LEVELS     add_level <mission#> <title> <task> <why> <auto|answer> "h1|h2|h3"
# =============================================================================
L_M=(); L_TITLE=(); L_TASK=(); L_WHY=(); L_TYPE=(); L_HINTS=()
add_level() { L_M+=("$1"); L_TITLE+=("$2"); L_TASK+=("$3"); L_WHY+=("$4"); L_TYPE+=("$5"); L_HINTS+=("$6"); }

# ---------------- MISSION 1: TRIAGE ----------------
add_level 1 "Where am I?" \
"You just logged in. Print the directory you are standing in." \
"Every path you type later is relative to where you are. Always know your location." \
auto "There is a command that Prints the Working Directory.|Three letters: p, w, d.|pwd"

add_level 1 "Look around" \
"List the files and folders in this directory." \
"The sysadmin left you a briefing somewhere in here." \
auto "The command that LiSts files is very short.|Two letters.|ls"

add_level 1 "Read the briefing" \
"Read the file briefing.txt. (Passes when its codeword appears on screen.)" \
"It describes the whole case and your three missions." \
auto "You need a command that prints a file's content to the screen.|It's named after an animal.|cat briefing.txt"

add_level 1 "Hidden in plain sight" \
"There is a hidden file in this folder. Find it, read it, and submit its codeword.  answer <codeword>" \
"Attackers hide files with a leading dot. If you can't see them, you can't find them." \
answer "Files starting with a dot don't show in a plain ls. ls has an option for ALL files.|ls -a   then cat the file that starts with a dot.|ls -a ; cat .hidden_note ; answer <codeword>"

add_level 1 "Into the logs" \
"Move into the logs folder." \
"The exported login log lives there." \
auto "The command to Change Directory is cd.|cd needs the folder name after it.|cd logs"

add_level 1 "Back up one level" \
"Go back UP to the folder you came from (your home)." \
"Two dots mean 'the parent folder'. You will use this constantly." \
auto "The parent folder is written as two dots.|cd works with .. too.|cd .."

add_level 1 "Absolute paths" \
"System configuration lives in /etc. Go there using its full path." \
"A path starting with / works from anywhere. Relative paths depend on where you stand." \
auto "A path that starts with / is absolute: it works from any location.|cd /etc|cd /etc"

add_level 1 "Read a system file" \
"You are in /etc. Read the file named hostname and submit the server's name.  answer <name>" \
"Config files are just text. Reading them is how you learn what a machine is." \
answer "cat works on any readable file, not just yours.|cat hostname   (or cat /etc/hostname from anywhere)|cat /etc/hostname ; answer <what it prints>"

add_level 1 "Go home" \
"Return to your home directory." \
"~ is your home. cd with no argument also takes you there." \
auto "The tilde character ~ means your home directory.|cd ~   or just   cd|cd ~"

add_level 1 "Evidence folder" \
"Create a folder called evidence in your home directory." \
"Investigators never work on originals. Everything you collect goes here." \
auto "MaKe DIRectory.|mkdir followed by the name.|mkdir evidence"

add_level 1 "Preserve the log" \
"Copy logs/auth.log into the evidence folder." \
"Work on the copy. The original stays untouched." \
auto "cp = copy. It needs a source and a destination.|cp source destination. The destination can be a folder.|cp logs/auth.log evidence/"

add_level 1 "Start a case file" \
"Without opening an editor, create evidence/notes.txt containing the line:  case: vault" \
"echo prints text; > sends that text into a file instead of the screen." \
auto "echo prints text. The > symbol redirects output into a file.|echo \"some text\" > file|echo \"case: vault\" > evidence/notes.txt"

add_level 1 "Add to the case file" \
"Add a second line to evidence/notes.txt:  analyst: <your name>   WITHOUT losing the first line." \
"> replaces a file's contents. >> appends. Mixing them up destroys evidence." \
auto "One > overwrites the file. Two >> append to it.|echo \"text\" >> file|echo \"analyst: yourname\" >> evidence/notes.txt"

add_level 1 "Rename it" \
"Rename evidence/notes.txt to evidence/report.txt. (Linux has no rename command: moving IS renaming.)" \
"mv moves files between folders or names. Same command." \
auto "mv = move. Moving a file to a new name renames it.|mv old_name new_name|mv evidence/notes.txt evidence/report.txt"

add_level 1 "Clean up" \
"Delete the file junk/old.tmp. Careful: rm has no recycle bin." \
"Deleting is permanent on the command line. Type the path carefully." \
auto "rm = remove.|rm takes the path of the file.|rm junk/old.tmp"

add_level 1 "How big is the log?" \
"How many lines does logs/auth.log have?  answer <number>" \
"Knowing the size tells you whether to read it or search it." \
answer "wc = word count, but it also counts lines.|wc -l file|wc -l logs/auth.log ; answer <number>"

add_level 1 "The last login" \
"Look at only the LAST line of logs/auth.log. Which username is in it?  answer <username>" \
"Logs are written in order; the end is the most recent event." \
answer "tail shows the end of a file.|tail -n 1 file|tail -n 1 logs/auth.log ; answer <username>"

add_level 1 "Count the failures" \
"How many lines in logs/auth.log contain 'Failed password'?  answer <number>" \
"Failed logins are the fingerprint of a brute-force attack." \
answer "grep searches for text inside files.|grep -c counts matching lines. Put the text in quotes.|grep -c \"Failed password\" logs/auth.log ; answer <number>"

add_level 1 "Who attacked us?" \
"Which IP address has the MOST failed logins in logs/auth.log?  answer <ip>" \
"Chaining small commands with | is how you turn a log into an answer." \
answer "Chain commands with | (pipe): output of one becomes input of the next.|grep \"Failed password\" logs/auth.log | awk '{print \$11}' | sort | uniq -c|grep \"Failed password\" logs/auth.log | awk '{print \$11}' | sort | uniq -c | sort -rn | head -1"

add_level 1 "Hidden on the disk" \
"The attacker hid a file named vault-flag.txt somewhere OUTSIDE your home. Search the whole disk, read it, submit the flag.  answer <flag>" \
"find can search from / downward. Errors about folders you can't open go to stderr; 2>/dev/null silences them." \
answer "find can start at / (the whole disk). You will see many 'Permission denied' errors.|Send errors away: find / -name vault-flag.txt 2>/dev/null|find / -name vault-flag.txt 2>/dev/null ; cat that path ; answer FLAG{...}"

# ---------------- MISSION 2: LOCKDOWN ----------------
add_level 2 "Who am I?" \
"Print your username." \
"Every command runs as someone. Permissions start with identity." \
auto "There's a command that literally asks who am i.|whoami|whoami"

add_level 2 "Your UID" \
"Users have numbers too. What is your numeric user ID?  answer <number>" \
"Linux tracks users by number; names are for humans." \
answer "id shows your user and group IDs.|id -u prints just the number.|id -u ; answer <number>"

add_level 2 "Who is root?" \
"What is the UID of the user root?  answer <number>" \
"UID 0 is the administrator. Anything running as UID 0 controls the machine." \
answer "id works for other users too: id <username>|id root|id root ; answer 0"

add_level 2 "The attacker's notes" \
"There is a hidden file in /root (the admin's home). Read it and submit its codeword.  answer <codeword>
(Try without sudo first and read the error.)" \
"Some places require admin rights. sudo runs ONE command as root. A permission error is the signal, not a reflex." \
answer "Your user can't enter /root. sudo runs a command as root.|sudo ls -a /root   then sudo cat the hidden file.|sudo ls -a /root ; sudo cat /root/.attacker_notes ; answer <codeword>"

add_level 2 "The rogue account" \
"The notes mention UID 1337. Which username has that UID? Look in /etc/passwd.  answer <username>" \
"/etc/passwd lists every account. Unknown accounts are a classic persistence trick." \
answer "/etc/passwd is readable by everyone. Each line is name:x:UID:GID:...|grep 1337 /etc/passwd|grep :1337: /etc/passwd ; answer <username>"

add_level 2 "How much power does it have?" \
"Which group gives the rogue account admin rights? Check its groups.  answer <group>" \
"Being in the sudo group means the account can become root." \
answer "There is a command that shows a user's groups.|groups <username>|groups backup-svc ; answer sudo"

add_level 2 "Strip its admin rights" \
"Remove backup-svc from that group." \
"First cut off the power, then deal with the account." \
auto "Removing a user from a group needs sudo.|sudo gpasswd -d <user> <group>|sudo gpasswd -d backup-svc sudo"

add_level 2 "Give the admin back their access" \
"The attacker changed webadmin's password. Set a new one (anything you like)." \
"Locking out the real admin is how attackers keep control. Reset it." \
auto "There is a command to change passwords; with sudo it works on other users.|sudo passwd <username>|sudo passwd webadmin   (type a new password twice)"

add_level 2 "Create an analyst account" \
"Create a new user named analyst WITH a home directory." \
"Investigators should not share accounts. Every action should be traceable to a person." \
auto "useradd creates accounts. Without -m there is no home folder.|sudo useradd -m <name>|sudo useradd -m analyst"

add_level 2 "Add to the team" \
"Add analyst to the group vault-team." \
"Groups grant shared access without making everyone an admin." \
auto "usermod modifies a user. -aG appends a group (never forget the -a!).|sudo usermod -aG <group> <user>|sudo usermod -aG vault-team analyst"

add_level 2 "Delete the rogue account" \
"Delete backup-svc AND its home directory." \
"An account with no admin rights is still a foothold. Remove it and its files." \
auto "userdel removes accounts. Its home folder stays unless you ask.|sudo userdel -r <user>|sudo userdel -r backup-svc"

add_level 2 "Read a permission string" \
"What are the permissions of site/deploy_key? Answer numeric (like 644) or symbolic (like -rw-r--r--).  answer <perms>" \
"A private key readable by everyone is a leak. ls -l shows who can do what." \
answer "ls -l shows permissions in the first column: owner, group, others.|r=4 w=2 x=1 for each of the three groups.|ls -l site/deploy_key ; answer 644"

add_level 2 "Take back ownership" \
"Look at who owns the site folder (ls -ld site). Make the site folder and everything in it owned by you (student)." \
"The files belonged to the deleted account, so you only see a number now. Until you own them you can't fix them." \
auto "chown changes the owner. -R applies to everything inside.|sudo chown -R user:group folder|sudo chown -R student:student site"

add_level 2 "Lock the key" \
"Make site/deploy_key readable and writable by its owner only." \
"600 = owner read/write, nobody else. The standard for secrets." \
auto "chmod changes permissions. Numeric mode: owner, group, others.|chmod 600 file|chmod 600 site/deploy_key"

add_level 2 "Run the audit" \
"tools/audit.sh is a script but not executable. Make it executable, run it, submit the audit code.  answer <code>" \
"Scripts need the x bit. Running something in the current folder needs ./ in front." \
answer "chmod +x adds execute permission.|./tools/audit.sh runs it.|chmod +x tools/audit.sh ; ./tools/audit.sh ; answer <code>"

add_level 2 "The rogue process" \
"Something called kworkerd is running. Find its PID.  answer <pid>" \
"A program on disk is a file. A running one is a process with a PID and an owner." \
answer "ps aux lists every process. grep filters the list.|ps aux | grep kworkerd    (ignore the grep line itself)|ps aux | grep kworkerd | grep -v grep ; answer <PID in column 2>"

add_level 2 "Kill it" \
"Stop the kworkerd process. (Notice who owns it.)" \
"It runs as root. You can't kill root's processes without sudo." \
auto "kill sends a stop signal to a PID. Owner matters.|sudo kill <pid>|sudo kill <pid>   (or sudo pkill -f kworkerd)"

add_level 2 "The fake service" \
"A service named backup-sync is running. Show its status and submit the full path of the script it runs.  answer <path>" \
"Services restart themselves. Killing the process alone would not work here." \
answer "systemctl status <name> shows what a service runs.|Look at the CGroup lines near the bottom.|systemctl status backup-sync ; answer /usr/local/lib/.cache/sync.sh"

add_level 2 "Stop it for good" \
"Stop the backup-sync service AND make sure it won't start again at boot." \
"stop = now. disable = not at next boot. You need both." \
auto "systemctl stop for now, systemctl disable for boot.|sudo systemctl stop <name> ; sudo systemctl disable <name>|sudo systemctl stop backup-sync ; sudo systemctl disable backup-sync"

add_level 2 "Restore a good service" \
"The attacker stopped the cron service (the system's scheduler). Start it and enable it at boot." \
"Attackers also switch OFF things that get in their way. Defenders turn them back on." \
auto "The service is called cron.|sudo systemctl start cron ; sudo systemctl enable cron|sudo systemctl enable --now cron"

# ---------------- MISSION 3: REBUILD ----------------
add_level 3 "Root's scheduled jobs" \
"Check root's crontab. How often (in minutes) does beacon.sh run?  answer <minutes>" \
"cron reruns commands on a schedule. Killing a process means nothing if cron restarts it." \
answer "Each user has a crontab. Root's needs sudo to read.|sudo crontab -l|sudo crontab -l ; answer 10"

add_level 3 "Remove root's jobs" \
"Remove the attacker's entries from root's crontab." \
"This is the thing that would have brought kworkerd back at the next reboot." \
auto "crontab -e edits, crontab -r removes the whole table.|sudo crontab -r   (root has no legitimate jobs on this box)|sudo crontab -r"

add_level 3 "System-wide cron" \
"Cron also runs system jobs from /etc/cron.d/. Find the file there that runs beacon.sh and delete it." \
"Persistence hides in more than one place. Check them all." \
auto "grep can search every file in a folder: grep -r beacon /etc/cron.d/|The file is called system-update.|sudo rm /etc/cron.d/system-update"

add_level 3 "The real login log" \
"The real SSH log is /var/log/auth.log. How many lines in it mention 203.0.113.42?  answer <number>" \
"System logs are protected; reading them needs privilege. Note: sudo writes its own audit line to auth.log, so the count can grow as you work." \
answer "It's owned by root. Reading it needs sudo.|sudo grep -c <ip> /var/log/auth.log|sudo grep -c 203.0.113.42 /var/log/auth.log ; answer <number>"

add_level 3 "What was the service doing?" \
"Services log to the journal. Read backup-sync's log and submit the domain it was syncing to.  answer <domain>" \
"journalctl is how you read what a service said. Here it reveals the exfil target." \
answer "journalctl -u <service> shows a service's log, but you only see your own messages unless you read it as root.|sudo journalctl -u backup-sync --no-pager | grep target|sudo journalctl -u backup-sync --no-pager | grep target ; answer <domain>"

add_level 3 "Refresh the package list" \
"Before installing anything, refresh apt's package index." \
"apt update downloads the list of available software. It installs nothing." \
auto "The package manager on Ubuntu is apt.|sudo apt update|sudo apt update"

add_level 3 "Find the package" \
"Which version of nginx is available to install?  answer <version>" \
"apt search finds packages; apt show describes one. Check before you install." \
answer "apt search nginx lists related packages. apt show gives details.|apt show nginx | grep Version|apt show nginx 2>/dev/null | grep Version ; answer <version>"

add_level 3 "Install the web server" \
"Install nginx." \
"Installing from the repository gets a trusted, signed package." \
auto "apt install needs sudo.|sudo apt install nginx|sudo apt install -y nginx"

add_level 3 "Is it listening?" \
"Check which program is listening on TCP port 80.  answer <program>" \
"ss shows open ports. A port you didn't expect is a finding; one you did is proof." \
answer "ss lists sockets. -t tcp, -l listening, -n numeric, -p program.|sudo ss -tlnp|sudo ss -tlnp | grep :80 ; answer nginx"

add_level 3 "Talk to it" \
"Fetch the web page from this machine on the command line." \
"curl is a browser without the browser. The default nginx page proves the server works." \
auto "curl fetches URLs.|curl http://localhost|curl http://localhost"

add_level 3 "Deploy the site" \
"The club's page is at site/index.html. Put it where nginx serves files: /var/www/html/index.html" \
"Web roots are owned by root. Deploying is copying with privilege." \
auto "The web root is /var/www/html. It needs sudo.|sudo cp site/index.html /var/www/html/|sudo cp site/index.html /var/www/html/index.html"

add_level 3 "Vault is back" \
"Fetch the page again and submit the flag it now serves.  answer <flag>" \
"You restored the service. Verify it the way a user would." \
answer "Same command as before.|curl http://localhost|curl http://localhost ; answer FLAG{...}"

add_level 3 "Your own footprint" \
"Look at nginx's access log. What HTTP status code did your last request get?  answer <code>" \
"Every request is logged. Your curl is in there, and so would an attacker's." \
answer "nginx logs to /var/log/nginx/access.log (needs sudo).|sudo tail /var/log/nginx/access.log|sudo tail -n 1 /var/log/nginx/access.log ; answer 200"

add_level 3 "Keep it patched" \
"How many packages on this machine can be upgraded right now?  answer <number>" \
"Outdated software is how servers get broken into. Knowing the count is step one." \
answer "apt can list what has newer versions.|apt list --upgradable|apt list --upgradable 2>/dev/null | grep -c upgradable ; answer <number>"

TOTAL=${#L_TITLE[@]}

# =============================================================================
#  CHECKS   check_<global index>; auto levels see $LAST_OUT, answer levels get $1
# =============================================================================
# --- Mission 1 ---
check_1()  { [[ "$LAST_OUT" == "$H" ]]; }
check_2()  { [[ "$LAST_OUT" == *briefing.txt* && "$LAST_OUT" == *logs* ]]; }
check_3()  { [[ "$LAST_OUT" == *OSPREY* ]]; }
check_4()  { [[ "$(norm "$1")" == "kestrel" ]]; }
check_5()  { [[ "$PWD" == "$H/logs" ]]; }
check_6()  { [[ "$PWD" == "$H" ]]; }
check_7()  { [[ "$PWD" == "/etc" ]]; }
check_8()  { local a; a=$(norm "$1"); [[ -n "$a" ]] && { [[ "$a" == "$(norm "$(cat /etc/hostname 2>/dev/null)")" || "$a" == "$(norm "$(hostname 2>/dev/null)")" ]]; }; }
check_9()  { [[ "$PWD" == "$H" ]]; }
check_10() { [[ -d "$H/evidence" ]]; }
check_11() { [[ -f "$H/evidence/auth.log" ]]; }
check_12() { [[ -f "$H/evidence/notes.txt" ]] && grep -qi "vault" "$H/evidence/notes.txt"; }
check_13() { [[ -f "$H/evidence/notes.txt" ]] && (( $(wc -l < "$H/evidence/notes.txt") >= 2 )) \
             && head -n 1 "$H/evidence/notes.txt" | grep -qi vault && grep -qi analyst "$H/evidence/notes.txt"; }
check_14() { [[ -f "$H/evidence/report.txt" && ! -e "$H/evidence/notes.txt" ]]; }
check_15() { [[ ! -e "$H/junk/old.tmp" ]]; }
check_16() { [[ "$(norm "$1")" == "$(wc -l < "$H/logs/auth.log" | tr -d ' ')" ]]; }
check_17() { [[ "$(norm "$1")" == "$(tail -n 1 "$H/logs/auth.log" | awk '{print $9}')" ]]; }
check_18() { [[ "$(norm "$1")" == "$(grep -c 'Failed password' "$H/logs/auth.log")" ]]; }
check_19() { local t; t=$(grep 'Failed password' "$H/logs/auth.log" | awk '{print $11}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}'); [[ "$(norm "$1")" == "$t" ]]; }
check_20() { [[ "$(norm "$1")" == "flag{stderr_to_dev_null}" ]]; }
# --- Mission 2 ---
check_21() { [[ "$LAST_OUT" == "$(id -un)" ]]; }
check_22() { [[ "$(norm "$1")" == "$(id -u)" ]]; }
check_23() { [[ "$(norm "$1")" == "0" ]]; }
check_24() { [[ "$(norm "$1")" == "falcon" ]]; }
check_25() { [[ "$(norm "$1")" == "$(getent passwd 1337 | cut -d: -f1)" ]]; }
check_26() { [[ "$(norm "$1")" == "sudo" ]]; }
check_27() { ! id backup-svc >/dev/null 2>&1 || ! id -nG backup-svc 2>/dev/null | tr ' ' '\n' | grep -qx sudo; }
check_28() { local now saved; now=$(as_root getent shadow webadmin 2>/dev/null | cut -d: -f2); saved=$(as_root cat "$CFG/webadmin.hash" 2>/dev/null); [[ -n "$now" && "$now" != "$saved" ]]; }
check_29() { id analyst >/dev/null 2>&1 && [[ -d /home/analyst ]]; }
check_30() { id -nG analyst 2>/dev/null | tr ' ' '\n' | grep -qx vault-team; }
check_31() { ! id backup-svc >/dev/null 2>&1 && [[ ! -d /home/backup-svc ]]; }
check_32() { local a; a=$(norm "$1"); [[ "$a" == "644" || "$a" == "-rw-r--r--" || "$a" == "rw-r--r--" ]]; }
check_33() { [[ "$(stat -c %U "$H/site" 2>/dev/null)" == "$(id -un)" && "$(stat -c %U "$H/site/index.html" 2>/dev/null)" == "$(id -un)" ]]; }
check_34() { [[ "$(stat -c %a "$H/site/deploy_key" 2>/dev/null)" == "600" ]]; }
check_35() { [[ "$(norm "$1")" == "4471" ]]; }
check_36() { local p; p=$(pgrep -f "kworkerd 99999" | head -1); [[ -n "$p" && "$(norm "$1")" == "$p" ]]; }
check_37() { ! pgrep -f "kworkerd 99999" >/dev/null 2>&1; }
check_38() { [[ "$(norm "$1")" == *sync.sh* ]]; }
check_39() { ! svc_active backup-sync && ! svc_enabled backup-sync; }
check_40() { svc_active cron && svc_enabled cron; }
# --- Mission 3 ---
check_41() { local a; a=$(norm "$1"); [[ "$a" == "10" || "$a" == "*/10" || "$a" == "every10minutes" || "$a" == "10minutes" || "$a" == "10min" ]]; }
check_42() { ! as_root crontab -l 2>/dev/null | grep -q "$CACHE"; }
check_43() { [[ ! -e /etc/cron.d/system-update ]]; }
check_44() {
  # sudo writes an audit line (containing the student's command, hence the IP)
  # to auth.log on every call, so the count grows while they work. Accept
  # anything between the real SSH lines (no sudo audit lines) and the live count.
  local a lo hi
  a=$(norm "$1"); [[ "$a" =~ ^[0-9]+$ ]] || return 1
  lo=$(as_root grep -v 'sudo:' /var/log/auth.log 2>/dev/null | grep -c 203.0.113.42)
  hi=$(as_root grep -c 203.0.113.42 /var/log/auth.log 2>/dev/null)
  (( a >= lo && a <= hi ))
}
check_45() { [[ "$(norm "$1")" == *badcorp* ]]; }
check_46() { ls /var/lib/apt/lists/*Packages* >/dev/null 2>&1; }
check_47() { local v; v=$(apt-cache policy nginx 2>/dev/null | awk '/Candidate:/{print $2}'); [[ -n "$v" && "$(norm "$1")" == "$(norm "$v")" ]]; }
check_48() { dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -q "install ok installed"; }
check_49() { [[ "$(norm "$1")" == *nginx* ]]; }
check_50() { [[ "$LAST_OUT" == *nginx* && "$LAST_OUT" == *"<html"* ]]; }
check_51() { [[ -f /var/www/html/index.html ]] && grep -q "FLAG{vault_is_back_online}" /var/www/html/index.html 2>/dev/null; }
check_52() { [[ "$(norm "$1")" == "flag{vault_is_back_online}" ]]; }
check_53() { [[ "$(norm "$1")" == "200" ]]; }
check_54() { [[ "$(norm "$1")" == "$(apt list --upgradable 2>/dev/null | grep -c upgradable)" ]]; }

# =============================================================================
#  ENGINE
# =============================================================================
LEVEL=1; HINTS_USED=0; LAST_OUT=""; SCORE=0; AT_GATE=0; BONUS_ACCEPTED=0
CORE=0; for m in "${L_M[@]}"; do (( m <= 3 )) && CORE=$((CORE + 1)); done
BONUS_COUNT=$((TOTAL - CORE))

lvl_mission()   { echo "${L_M[$(( $1 - 1 ))]}"; }
lvl_in_mission() { local i n=0 m; m=$(lvl_mission "$1"); for (( i = 0; i < $1; i++ )); do [[ "${L_M[$i]}" == "$m" ]] && n=$((n + 1)); done; echo "$n"; }
mission_size()  { local i n=0; for i in "${L_M[@]}"; do [[ "$i" == "$1" ]] && n=$((n + 1)); done; echo "$n"; }
mission_first() { local i; for (( i = 0; i < TOTAL; i++ )); do [[ "${L_M[$i]}" == "$1" ]] && { echo $((i + 1)); return; }; done; echo 0; }
base_points()   { if (( $(lvl_mission "$1") == 4 )); then echo 25; else echo 10; fi; }

rank_title() {
  local s=$1
  if   (( s >= 560 )); then echo "Ghost Hunter"        # only reachable with bonus levels
  elif (( s >= 400 )); then echo "Incident Responder"
  elif (( s >= 200 )); then echo "Analyst"
  else echo "Recruit"; fi
}

banner() {
  cat <<EOF
${C}${BOLD}
  ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗     ██████╗ ██╗   ██╗███████╗███████╗████████╗
  ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝    ██╔═══██╗██║   ██║██╔════╝██╔════╝╚══██╔══╝
  ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝     ██║   ██║██║   ██║█████╗  ███████╗   ██║
  ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗     ██║▄▄ ██║██║   ██║██╔══╝  ╚════██║   ██║
  ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗    ╚██████╔╝╚██████╔╝███████╗███████║   ██║
  ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝     ╚══▀▀═╝  ╚═════╝ ╚══════╝╚══════╝   ╚═╝
${N}${DIM}  Incident response for beginners. Type real commands. Type ${N}help${DIM} any time.${N}

EOF
}

show_help() {
  line
  say "${BOLD}Game commands${N}   (everything else runs as a real Linux command)"
  say "  ${C}task${N}      show the current level again"
  say "  ${C}mission${N}   show the current mission's story and objectives"
  say "  ${C}hint${N}      get a hint (3 per level; each costs 2 points)"
  say "  ${C}answer X${N}  submit an answer for investigation levels"
  say "  ${C}skip${N}      skip this level (0 points for it)"
  say "  ${C}progress${N}  levels done and your score"
  say "  ${C}reset${N}     rebuild the compromised server and start over"
  say "  ${C}quit${N}      save and exit   ${DIM}(Ctrl+C only stops the current command)${N}"
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
    1) say "  You can navigate, read, collect evidence, and interrogate a log. That is triage." ;;
    2) say "  Rogue account gone, admin restored, files reclaimed, process and service dead. That is containment." ;;
    3) say "  Persistence removed, evidence pulled from real logs, and the site is serving again. That is recovery." ;;
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
  if (( $(lvl_mission "$LEVEL") == 4 && HINTS_USED == 2 )); then
    warn "Bonus rule: the 3rd hint is the full command and drops this level to 0 points."
  fi
  printf '%s💡 Hint %d/%d (-2 pts):%s %s\n' "$Y" $((HINTS_USED + 1)) "${#hints[@]}" "$N" "${hints[$HINTS_USED]}"
  HINTS_USED=$((HINTS_USED + 1))
}

level_points() {
  local base p; base=$(base_points "$LEVEL")
  if (( $(lvl_mission "$LEVEL") == 4 && HINTS_USED >= 3 )); then echo 0; return; fi
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
  if (( LEVEL == CORE + 1 && AT_GATE == 0 && BONUS_ACCEPTED == 0 )); then core_complete; return; fi
  if (( LEVEL > TOTAL )); then finish; exit 0; fi
  local m; m=$(lvl_mission "$LEVEL")
  if (( LEVEL == $(mission_first "$m") )); then mission_briefing "$m"; fi
  # M2 levels 16/17 need the rogue process; a reboot after setup (cron is
  # stopped, so @reboot never fires) would leave it missing. Respawn it.
  if (( LEVEL == 36 || LEVEL == 37 )) && ! pgrep -f "kworkerd 99999" >/dev/null 2>&1; then
    as_root setsid nohup "$CACHE/kworkerd" 99999 </dev/null >/dev/null 2>&1 &
    sleep 0.3
  fi
  show_task
}

advance() {
  local pts m; pts=${1:-$(level_points)}; m=$(lvl_mission "$LEVEL")
  add_points "$pts"
  ok "Level complete  +$pts pts   (total $SCORE)"
  LEVEL=$((LEVEL + 1)); save
  if (( LEVEL > TOTAL )) || [[ "$(lvl_mission "$LEVEL")" != "$m" ]]; then mission_debrief "$m"; fi
  sleep 0.5
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

core_complete() {
  AT_GATE=1
  line
  printf '%s%s🎉  You did it! All three missions complete. vault is back online.%s\n' "$G" "$BOLD" "$N"
  printf '  Final core score: %s   Rank: %s\n' "$SCORE" "$(rank_title "$SCORE")"
  say "  Every command you just used is one you'll use for the rest of your career."
  say ""
if [[ -x "$BONUS_BIN" ]]; then
    say "  Feeling confident? The BONUS mission is waiting. It is meant to be hard."
    say "  Type  ${C}bonus${N}  to continue, or  ${C}quit${N}  to finish here."
  else
    say "  The bonus mission is not installed on this machine. Type  ${C}quit${N}  to finish."
  fi
  line
  score_code_line
}

start_bonus() {
  (( AT_GATE )) || { warn "The bonus mission unlocks after mission 3."; return; }
  if [[ -x "$BONUS_BIN" ]]; then
    save
    exec "$BONUS_BIN"
  fi
  warn "The bonus mission is not installed on this machine."
}

finish() {
  line
  printf '%s%s🏆  EVERYTHING COMPLETE. Final score: %d   Rank: %s%s\n' "$G" "$BOLD" "$SCORE" "$(rank_title "$SCORE")" "$N"
  line
  score_code_line
}

# ---------- score code (leaderboard mode; off unless SHOW_SCORE_CODE=1) -----
score_code() {
  local name=$1 score=$2 secret sig
  secret=$(as_root cat "$CFG/secret" 2>/dev/null) || secret="nosecret"
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

# ---------- command runner ---------------------------------------------------
# Commands that need the real terminal (prompts, pagers, editors) run uncaptured.
is_interactive() {
  case "$1" in man|less|more|nano|vim|vi|top|htop|clear|cd|export|unset|alias|passwd|sudo|visudo|crontab|journalctl|systemctl|apt|apt-get|ssh|su) return 0;; esac
  return 1
}
run_player_cmd() {
  local cmd="$1" first; first=${cmd%% *}
  if is_interactive "$first"; then
    eval "$cmd"; LAST_OUT=""
  else
    LAST_OUT=$(eval "$cmd" 2>&1); [[ -n "$LAST_OUT" ]] && printf '%s\n' "$LAST_OUT"
  fi
}
prompt_string() {
  local rel
  if [[ "$PWD" == "$H"* ]]; then rel="~${PWD#"$H"}"; else rel="$PWD"; fi
  if (( AT_GATE )); then printf '%s[bonus?]%s %s%s%s $ ' "$M" "$N" "$C" "$rel" "$N"; return; fi
  printf '%s[%s L%d | %dpts]%s %s%s%s $ ' "$M" "${M_TAG[$(( $(lvl_mission "$LEVEL") - 1 ))]}" "$(lvl_in_mission "$LEVEL")" "$SCORE" "$N" "$C" "$rel" "$N"
}
read_input() {
  ( [[ -f "$HISTFILE" ]] && history -r "$HISTFILE"
    IFS= read -r -e -p "$(prompt_string)" line || exit $?
    printf '%s' "$line" )
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
      task)      if (( AT_GATE )); then core_complete; else show_task; fi ;;
      mission)   show_mission "$(lvl_mission "$(( LEVEL > TOTAL ? TOTAL : LEVEL ))")" ;;
      hint)      if (( AT_GATE )); then say "Type  bonus  or  quit."; else show_hint; fi ;;
      bonus)     start_bonus ;;
      answer)    if (( AT_GATE )); then say "Type  bonus  or  quit."; else try_answer "$rest"; fi ;;
      skip)      if (( AT_GATE )); then say "Type  bonus  or  quit."; else warn "Skipped (0 pts)."; advance 0; fi ;;
      progress)  show_progress ;;
      reset)     do_reset ;;
      quit|exit) break ;;
      *)         run_player_cmd "$input"; try_auto ;;
    esac
  done
  if (( AT_GATE )); then say "${DIM}Progress saved. Run linux-quest again and type bonus if you change your mind.${N}"
  else say "${DIM}Progress saved (score $SCORE). Run linux-quest again to continue.${N}"; fi
}

do_reset() {
  say "Rebuilding the compromised server (this takes a few seconds)..."
  if as_root "$LIB/setup.sh" --state; then
    mkdir -p "$STATE"; echo 0 > "$PROGRESS"; echo 0 > "$SCOREFILE"; rm -f "$STATE"/mission_*.pts
    LEVEL=1; SCORE=0; AT_GATE=0; BONUS_ACCEPTED=0
    cd "$H" || true
    ok "Fresh start."; enter_level
  else err "Reset failed. Ask a mentor to run: sudo $LIB/setup.sh --state"; fi
}

# =============================================================================
#  START
# =============================================================================
on_interrupt() { printf '\n%s^C  (stops the current command only; type quit to leave)%s\n' "$DIM" "$N"; }
trap on_interrupt INT

case "${1:-}" in
  --verify) verify_code "$2"; exit ;;
  --reset)  as_root "$LIB/setup.sh" --state || exit 1; rm -rf "$STATE" ;;
esac

if [[ $EUID -eq 0 && "${LQ_ALLOW_ROOT:-0}" != 1 ]]; then
  err "Don't play as root. Switch to the student account first:  su - student   (password 123456)"; exit 1
fi
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
  err "This account needs passwordless sudo (setup.sh does that). Ask a mentor."; exit 1
fi

mkdir -p "$STATE"
cd "$H" || exit 1
if [[ ! -f "$H/briefing.txt" || ! -f "$H/logs/auth.log" ]]; then
  err "No playground found for $(id -un) in $H."
  say "  The game must be played as the student account on a machine prepared by setup.sh:"
  say "    sudo bash setup.sh        (as root; it switches to student and starts the game)"
  say "    su - student              (password 123456), then: linux-quest"
  exit 1
fi
banner
if [[ ! -s "$NAMEFILE" ]]; then
  printf 'What should I call you? '; IFS= read -r nm; nm=${nm:-analyst}; printf '%s' "$nm" > "$NAMEFILE"; say ""
fi
SCORE=$(cat "$SCOREFILE" 2>/dev/null || echo 0)
LEVEL=$(( $(cat "$PROGRESS" 2>/dev/null || echo 0) + 1 ))
(( LEVEL > 1 )) && say "${DIM}Welcome back, $(cat "$NAMEFILE"). Resuming with $SCORE points. Type reset to start over.${N}"
show_help
enter_level
main_loop
