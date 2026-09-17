# F26_enum_lab

# How to test ENUM QUEST on team30 (beginner guide)

You have never done this before — that is fine. Follow these steps **in order**.  
Do not skip the snapshot step.

**Goal:** Put the lab on **team30 only**, try it, and be able to undo everything if something breaks.

---

## What you are working with (simple picture)

Think of three student machines on team30’s private network:

1. **Kali jumpbox** — where the student logs in (`ocig1`, etc.) and runs `enum-quest`
2. **Ubuntu target** — the Linux machine students scan (`vault-web`)
3. **Windows target** — the Windows machine students scan (`vault-dc`)

There is also an **admin Kali** (for mentors). That machine is the **Salt master** — the “remote control” that can set up the other machines.

You will:

1. Take a safety save-point (snapshot)
2. Copy our lab files onto the admin Kali
3. Run setup on the three team30 machines
4. Log into the jumpbox and try the game

---

## Words you will see

| Word | Meaning |
|------|---------|
| **Proxmox** | The website/panel that shows all the VMs (virtual computers). You take snapshots here. |
| **Snapshot** | A save-point. Like “undo” for a whole computer. |
| **Guacamole / Guac** | A website that gives you a remote desktop or terminal into a VM. |
| **Salt / minion** | Software that lets the admin Kali configure other VMs. You can also set things up by hand if Salt is confusing. |
| **Jumpbox** | The Kali the student uses. |
| **Target** | The machine being scanned (Ubuntu or Windows). |

---

## Before you start — checklist

- [ ] You can open the range portal (Pangolin) and log in as a project admin  
  (password was shared with you separately — do not put it in this folder/git)
- [ ] You can open **Proxmox**
- [ ] You can open a desktop/terminal to the **admin Kali** and to **team30** VMs
- [ ] This lab folder is on your computer: `enum_lab` (with `setup_jumpbox.sh`, etc.)

If any of those fail, stop and ask the range host for access help before changing anything.

---

# PART 0 — How do I get the scripts onto the VMs?

Your lab files live on **your Windows PC** right now:

`C:\Users\cod08\enum_lab`

The VMs are **other computers**. You must copy the files over.  
A zip is already prepared for you:

`C:\Users\cod08\enum_lab\enum_lab_for_vms.zip`

Pick **one** method below. Method 1 is usually easiest.

---

## Method 1 — Upload through Guacamole (easiest if available)

Many ranges let you upload files inside the Guac window.

1. Open Guacamole and connect to a VM (start with **admin Kali** or the **team30 Kali jumpbox**).
2. Look for a way to send files:
   - Sometimes a **folder / file icon** in the Guac menu (often left side or Ctrl+Alt+Shift opens a panel)
   - Or drag-and-drop a file into the session window
3. Upload `enum_lab_for_vms.zip` from your PC.
4. On Linux (Kali/Ubuntu), find where it landed (often your home folder), then unzip:

```bash
cd ~
ls *.zip
unzip enum_lab_for_vms.zip -d enum_lab
cd enum_lab
ls
```

You should see `setup_jumpbox.sh`, `enum_quest.sh`, etc.

5. Repeat for the other VMs **or** copy from this first Linux box to the others (Method 3).

**Windows tip:** After upload, move/unzip with File Explorer, or in PowerShell:

```powershell
Expand-Archive -Path .\enum_lab_for_vms.zip -DestinationPath .\enum_lab -Force
cd .\enum_lab
```

If Guac has **no** upload at all, use Method 2 or ask the range host:  
“How do project admins copy files into team VMs?”

---

## Method 2 — Put the zip on the internet, then download inside the VM

Good when Guac cannot upload.

1. On your PC, upload `enum_lab_for_vms.zip` somewhere **you** control, for example:
   - a private GitHub release / gist (zip attached)
   - Discord to yourself (then open Discord **inside** the VM and download)
   - OneDrive/Google Drive link (download inside the VM)
2. Inside the Linux VM:

```bash
cd ~
# Example if you have a direct URL:
wget -O enum_lab_for_vms.zip "PASTE_YOUR_LINK_HERE"
unzip enum_lab_for_vms.zip -d enum_lab
cd enum_lab
ls
```

Do **not** post the zip somewhere public if it includes internal notes you care about. A private link is fine for class testing.

---

## Method 3 — Copy once to admin Kali, then to team30 (nice long-term)

1. Get the zip onto **admin Kali** (Method 1 or 2).
2. Unzip there.
3. From admin Kali, copy to team30 machines (you need their IPs — ask or look in Proxmox):

```bash
# Examples — replace IPs/usernames with team30 real values
scp -r ~/enum_lab ocig1@192.168.1.10:~/
scp -r ~/enum_lab ocig1@192.168.1.11:~/
# Windows is harder over scp; use Guac upload for Windows, or copy just the .ps1
```

For Windows, Guac upload of `setup_win_target.ps1` (or the whole zip) is usually simplest.

---

## Method 4 — Git clone (if you push this folder to GitHub)

1. Create a GitHub repo and push `enum_lab` (optional; ask me if you want help).
2. On each Linux VM:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/YOUR_USER/YOUR_REPO.git enum_lab
cd enum_lab
ls
```

---

## What each VM needs

| VM | Files needed |
|----|----------------|
| Kali jumpbox | Whole folder (especially `setup_jumpbox.sh`, `enum_quest.sh`, `wordlists/`) |
| Ubuntu target | At least `setup_ubuntu_target.sh` (whole folder is fine) |
| Windows target | At least `setup_win_target.ps1` (whole folder is fine) |

After the files are on a VM, go back to **PART A** (snapshots), then **PART B** (run the setups).

---

# PART A — Make a safety save-point (do this first)

### Step A1 — Open Proxmox

1. Log into the range portal.
2. Open **Proxmox**.

### Step A2 — Find team30 machines

1. Look at the list of VMs (left side or datacenter list).
2. Find anything named like **team30**, **t30**, or similar.
3. You want the **three** machines for this lab (Kali jumpbox, Ubuntu, Windows).  
   If you are not sure which is which, write down the names and ask a mentor/range host before continuing.

### Step A3 — Snapshot each team30 VM

For **each** of those three VMs:

1. Click the VM name.
2. Click **Snapshot** (sometimes under a menu).
3. Click **Take Snapshot** (or similar).
4. Name it exactly something like:  
   `before-enum-quest`
5. Add a note if you want: `safe point before testing enum lab`
6. Wait until it says it finished (no spinning / “running” forever).

**Do not continue until all three snapshots are done.**

If you mess up later: open that VM → Snapshot → select `before-enum-quest` → **Rollback**. That puts the VM back to how it was.

---

# PART B — Easiest path for a first test (manual setup)

Salt is powerful but easy to aim at the wrong machine if you are new.  
For your **first** test, set each machine up by hand. Same result, less risk.

You will need to get our lab files onto each machine (or at least onto admin Kali and copy from there). Pick one way:

### Option 1 — USB / download / shared folder (whatever your range allows)

Copy the whole `enum_lab` folder onto:

- the Ubuntu target
- the Kali jumpbox
- the Windows target (at least `setup_win_target.ps1`)

### Option 2 — From admin Kali with `scp` (if you know the IPs)

Someone more experienced can help with this. You only need the files present on each VM before running the commands below.

---

## Step B1 — Set up the Ubuntu target

1. Open a terminal on the **Ubuntu target** (Guac/SSH).
2. Go to the folder that has the scripts:

```bash
cd /path/to/enum_lab
```

(Replace `/path/to/enum_lab` with the real folder, e.g. `cd ~/enum_lab` or `cd /home/ocig1/enum_lab`.)

3. Run:

```bash
sudo ./setup_ubuntu_target.sh --no-switch
```

4. Wait until it prints that the ubuntu target is ready.  
   If it asks for your password, that is normal (`ocigN` password is usually the same as the username).

5. Quick check (optional):

```bash
curl -I http://127.0.0.1
```

You should see something like `HTTP` and `nginx` or `Server`.

---

## Step B2 — Set up the Windows target

1. Open the **Windows Server 2019** VM.
2. Open **PowerShell as Administrator**  
   (right-click PowerShell → Run as administrator).
3. Go to the folder with `setup_win_target.ps1`:

```powershell
cd C:\path\to\enum_lab
```

4. If Windows blocks scripts, run once:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

5. Run:

```powershell
.\setup_win_target.ps1
```

6. Wait until it prints that the windows target is ready.  
   The first run can take a while (IIS/DNS features).

---

## Step B3 — Set up the Kali jumpbox

1. Open a terminal on the **team30 Kali jumpbox** (not necessarily the admin Kali).
2. Log in as your student-style user if needed (`ocig1`, `ocig2`, …).
3. Go to the lab folder:

```bash
cd /path/to/enum_lab
```

4. Run:

```bash
sudo ./setup_jumpbox.sh --no-switch
```

This installs/checks tools and installs the `enum-quest` command for **your** user (the one who typed `sudo`).

5. Confirm:

```bash
which enum-quest
ls ~/briefing.txt
cat /etc/enum-quest/targets.conf
```

You should see the game command, a briefing file, and IPs for `vault-web` / `vault-dc`.

---

## Step B4 — Important IP check

Open `/etc/enum-quest/targets.conf` on the jumpbox:

```bash
cat /etc/enum-quest/targets.conf
```

Default is:

- Linux = `192.168.1.11`
- Windows = `192.168.1.12`

**On the jumpbox, ping them:**

```bash
ping -c 2 192.168.1.11
ping -c 2 192.168.1.12
```

- If both reply → good, continue.
- If they fail → the real IPs on team30 are different.  
  Write down the real IPs of Ubuntu and Windows from Proxmox/Guac, then re-run setups with:

```bash
# On Ubuntu target:
sudo TARGET_UBUNTU_IP=REAL_LINUX_IP TARGET_WIN_IP=REAL_WIN_IP ./setup_ubuntu_target.sh --state

# On Kali jumpbox:
sudo TARGET_UBUNTU_IP=REAL_LINUX_IP TARGET_WIN_IP=REAL_WIN_IP ./setup_jumpbox.sh --state
```

And on Windows (Admin PowerShell):

```powershell
.\setup_win_target.ps1 -UbuntuIp REAL_LINUX_IP -WinIp REAL_WIN_IP
```

Replace `REAL_LINUX_IP` / `REAL_WIN_IP` with the real addresses.

---

# PART C — Play / test the lab

1. On the **Kali jumpbox**, as `ocigN`:

```bash
enum-quest
```

2. When it asks your name, type anything (or your name).
3. Type `help` and press Enter.
4. Type `targets` to see the hosts.
5. Follow the first tasks. Example early answers:

```text
cat briefing.txt
answer OSPREY
```

6. Try real tools in the game prompt, for example:

```bash
nmap -p 21,22,53,80,139,445 vault-web
```

If levels accept answers and nmap shows open ports, **your test worked**.

Type `quit` when you want to leave (progress is saved).

---

# PART D — If something goes wrong

1. Stop running more setup commands.
2. Go back to **Proxmox**.
3. Select the VM that broke.
4. Open **Snapshot**.
5. Select `before-enum-quest`.
6. Click **Rollback** (or Restore).
7. Confirm.

That VM is back to before your test.  
Tell a mentor what failed (copy the error text).

---

# PART E — Salt later (optional, after manual test works)

Only do this after a manual test worked once, or with someone watching.

Salt = “run the same setup from the admin Kali remotely.”

Rough idea:

1. Copy `enum_lab` onto the **admin Kali**.
2. Point Salt at only **team30** minion names (never `salt '*'` for this test).
3. Apply one machine at a time.

Exact minion names depend on how the range was built. Ask the range host:

> “What are the Salt minion IDs for team30 jumpbox, Ubuntu, and Windows?”

Then use the more advanced notes in the repo README / Salt files — or ask me again with those three names and I will give you the exact three commands.

---

## Super-short version

1. **Proxmox → snapshot all team30 VMs** (`before-enum-quest`)
2. Run `setup_ubuntu_target.sh` on Ubuntu
3. Run `setup_win_target.ps1` on Windows
4. Run `setup_jumpbox.sh` on Kali jumpbox
5. Fix IPs if ping fails
6. Run `enum-quest` and try a few levels
7. If broken → **Rollback** snapshot

---

## When you are stuck

Send me (or a mentor) these four things — no passwords:

1. The three team30 VM names as shown in Proxmox  
2. Their IP addresses  
3. Which step you were on (A / B1 / B2 / B3 / C)  
4. The exact error text from the terminal  

I can then tell you the next single command to run.
