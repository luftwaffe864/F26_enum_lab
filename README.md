# ENUM QUEST — DCIG Enumeration Lab

Interactive CLI recon lab (same style as LINUX QUEST). Each student uses their **Kali jumpbox** login (`ocig1`, `ocig2`, … — password matches username) to enumerate two targets: **Ubuntu** and **Windows Server 2019**.

## Range / hosting notes

Infra matches the cyber-range style pod model:

| Item | Detail |
|------|--------|
| Team network | Each team gets **`192.168.1.0/24`** (isolated per team) |
| Student jumpbox | **Kali Linux** (ocigN accounts; Salt minion) |
| Salt master | **Admin Kali** — mentors push states to minions from here |
| Access | Project admins: Pangolin / Proxmox / Guacamole (URL and creds from range host — do not commit secrets here) |

Suggested fixed addresses inside each team's `/24` (override via env / pillar if your build differs):

| Role | Hostname | Default IP |
|------|----------|------------|
| Jumpbox (Kali) | (student login host) | whatever the range assigns (often `.10` or similar) |
| Ubuntu target | `vault-web` | `192.168.1.11` |
| Windows target | `vault-dc` | `192.168.1.12` |

DNS AXFR on the Ubuntu target is allowed from **`192.168.1.0/24`** so jumpboxes can transfer the zone.

## Topology

| Role | OS | Setup script |
|------|-----|--------------|
| Jumpbox | **Kali Linux** | `setup_jumpbox.sh` |
| Target A | Ubuntu | `setup_ubuntu_target.sh` |
| Target B | Windows Server 2019 | `setup_win_target.ps1` |

Missions: **Network → Services → Users → Shares → Web → DNS**

## Student (jumpbox)

Log in as yourself (`ocigN` / `ocigN`), then:

```bash
enum-quest
```

No separate `student` account. Mentors install with your user via sudo:

```bash
sudo ./setup_jumpbox.sh --no-switch
# uses $SUDO_USER (ocigN). To force:  sudo ./setup_jumpbox.sh --user ocig3 --no-switch
```

In-game: `help`, `task`, `mission`, `targets`, `hint`, `answer`, `progress`, `reset`, `quit`.

## Mentor — manual provision

Defaults assume `vault-web=192.168.1.11` and `vault-dc=192.168.1.12`. Override if needed:

```bash
# Jumpbox (as any ocigN with sudo)
export TARGET_UBUNTU_IP=192.168.1.11 TARGET_WIN_IP=192.168.1.12
sudo -E ./setup_jumpbox.sh --no-switch

# Ubuntu target
export JUMPBOX_CIDR=192.168.1.0/24
sudo -E ./setup_ubuntu_target.sh --no-switch

# Windows target (Admin PowerShell)
.\setup_win_target.ps1 -UbuntuIp 192.168.1.11 -WinIp 192.168.1.12
```

## Mentor — Salt (from admin Kali)

1. Copy this repo onto the Salt master (admin Kali), e.g. as `salt://enum_lab`.
2. Set minion grains per VM: `role: jumpbox` | `ubuntu-target` | `win-target`.
3. Pillar: see [`salt/pillar.example`](salt/pillar.example) (`192.168.1.0/24` defaults). Pin a student with `player_user: ocig12` if needed.
4. Apply from the master, e.g. `salt -G 'role:jumpbox' state.apply enum-quest` (and the other roles).

State file: [`salt/enum-quest.sls`](salt/enum-quest.sls).

## Defaults planted for answers

| Finding | Value |
|---------|--------|
| Briefing code | `OSPREY` |
| Hosts | `vault-web` / `192.168.1.11`, `vault-dc` / `192.168.1.12` · domain `vault.lab` |
| Linux ports | `21,22,53,80,139,445` (FTP + SSH + DNS + HTTP + SMB) |
| Win ports | `53,80,445,3389` |
| Users | Win `svc_backup`, `intern` · Linux `webadmin`, `deploy` |
| File services | FTP anon `pub/flag.txt` → `FLAG{ftp_anon_loot}` · SMB `Public` / `teamfiles` |
| Shares | `Public`, `Finance`, `IT$`, `teamfiles` |
| Flags | `FLAG{ftp_anon_loot}`, `FLAG{smb_public_read}`, `FLAG{linux_share_loot}`, `FLAG{web_admin_panel}`, `FLAG{nginx_backup_note}`, `FLAG{iis_secret_stash}`, `FLAG{dns_zone_transfer}` |

Answer key on the jumpbox: `/etc/enum-quest/answers` (mode 644 for classroom play without passwordless sudo).

## Previous lab (reference)

The original **LINUX QUEST** (Linux Basics / IR) scripts live in [`previous_lab/`](previous_lab/) for reference only. ENUM QUEST does not use them.

## Safe test on team30

See [`MENTOR_TEST_team30.md`](MENTOR_TEST_team30.md) — snapshot in Proxmox first, then apply only team30 minions.
